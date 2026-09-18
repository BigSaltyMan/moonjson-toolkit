///|
/// The input was formatted, or validated successfully.
pub let exit_success : Int = 0

///|
/// The input could not be read, or is not valid JSON.
pub let exit_input_error : Int = 1

///|
/// The command line itself was wrong.
pub let exit_usage_error : Int = 2

///|
/// The input was fine, but the AI review could not be produced.
pub let exit_ai_error : Int = 3

///|
/// Everything one run produced: the text destined for each output stream, and
/// the code the process should end with.
pub(all) struct RunResult {
  out : String
  err : String
  code : Int
}

///|
/// A run that stopped early, with `message` on standard error and an empty
/// standard output.
fn failure(message : String, code : Int) -> RunResult {
  { out: "", err: message + "\n", code, }
}

///|
/// The `error:` marker every failure message opens with, in red when colour is
/// on and plain when it is not.
///
/// The argument error is the one message that does not use this: it is built
/// from an argument list that did not parse, so whether `--no-color` was among
/// those arguments is unknown, and the safe answer for an unknown is no colour.
fn error_prefix() -> String {
  red("error:") + " "
}

///|
/// Read the JSON text, from `--file` when given and from standard input
/// otherwise. Returns the text together with a label naming its source.
async fn read_input(file : String?) -> Result[(String, String), String] {
  match file {
    Some(path) =>
      match read_file(path) {
        Ok(text) => Ok((text, path))
        Err(message) => Err("cannot read " + path + ": " + message)
      }
    None =>
      match read_stdin() {
        Ok(text) => Ok((text, "<stdin>"))
        Err(message) => Err("cannot read standard input: " + message)
      }
  }
}

///|
/// Run the tool over `args` and collect everything it produced.
///
/// Every step that can fail — reading, parsing, the AI review, writing the
/// statistics file — runs before a single byte reaches `out`, so a failure
/// never leaves a half-written document on standard output. `-v` suppresses
/// only the formatted document itself; `--json-out` and `--ai` still run.
pub async fn run(
  args : Array[String],
  analyze~ : async (String) -> Result[String, String],
) -> RunResult {
  let options = match CliOptions::parse(args) {
    Ok(options) => options
    Err(message) =>
      return failure(
        "error: " +
        message +
        "\nrun 'moonjson-toolkit --help' to see the available options",
        exit_usage_error,
      )
  }
  // Colour is settled here, once everything that decides it is known: it takes
  // a terminal and an absence of `--no-color`. The argument error above is
  // deliberately left out of it — an argument list that failed to parse is
  // exactly the one whose `--no-color` cannot be read, so the only safe answer
  // is no colour, which is what the default already is.
  set_color_enabled(!options.no_color && is_tty())
  // `--help` and `--version` both answer without reading any input. When both
  // are asked for, the usage text wins: it is the longer answer and the one
  // that tells you the other flag exists.
  if options.help {
    return { out: usage() + "\n", err: "", code: exit_success, }
  }
  if options.version {
    return { out: version_line() + "\n", err: "", code: exit_success, }
  }
  let (text, source) = match read_input(options.file) {
    Ok(input) => input
    Err(message) => return failure(error_prefix() + message, exit_input_error)
  }
  let json = match parse_with_diagnostic(text, options.max_depth) {
    Ok(json) => json
    Err(diagnostic) =>
      return failure(
        error_prefix() + source + " is not valid JSON\n" + diagnostic.render(),
        exit_input_error,
      )
  }
  // Sorting is a change to the document, not to its layout, so it happens
  // first and both the review and the printed output see the same order.
  let ordered = if options.sort_keys { sort_keys(json) } else { json }
  // `--compact` asks for a document with no line breaks in it at all, which is
  // what `--indent` exists to place, so the width is simply not consulted.
  let formatted = if options.compact {
    format_compact(ordered)
  } else {
    format(ordered, options.indent)
  }
  // The review is asked for before anything is printed, so that a failure here
  // leaves standard output empty rather than trailing a document that the
  // caller may be piping somewhere.
  let review = if options.ai {
    match analyze(formatted) {
      Ok(report) => Some(report)
      Err(message) => return failure("error: " + message, exit_ai_error)
    }
  } else {
    None
  }
  let mut err = ""
  match options.json_out {
    Some(path) =>
      match write_stats_file(path, json) {
        Ok(_) => err = "statistics written to " + path + "\n"
        Err(message) =>
          return failure(
            error_prefix() + "cannot write " + path + ": " + message,
            exit_input_error,
          )
      }
    None => ()
  }
  // `--stats` and `--json-out` are two answers to the same question, so asking
  // for both is not an error but a tie, and the file is the more useful of the
  // two: it is the one that can be kept, charted and compared. The summary on
  // standard output is what is given up.
  let show_stats = options.stats && options.json_out == None
  // Nothing below can fail, so this is where standard output starts.
  let out = StringBuilder()
  if options.validate {
    // `-v` replaces the document with a one-line verdict, nothing else.
    out.write_string(source + ": valid JSON\n")
  } else if options.paths || options.keys_only {
    // The two name lists are alternatives to the document rather than additions
    // to it, and `--paths` is the longer of the pair, so it is the one that
    // answers when both are asked for.
    let names = if options.paths {
      collect_paths(ordered)
    } else {
      collect_key_paths(ordered)
    }
    for name in names {
      out.write_string(name)
      out.write_string("\n")
    }
  } else if show_stats {
    // Computed from `json` rather than from `ordered`: sorting changes the
    // order the document is printed in and none of these counts, and taking
    // them from the same value `--json-out` is given keeps the two reports
    // saying the same thing when both are asked for.
    out.write_string(JsonStats::of(json).to_text())
    out.write_string("\n")
  } else {
    out.write_string(formatted)
    out.write_string("\n")
  }
  match review {
    Some(report) => {
      out.write_string("\n")
      out.write_string("AI quality report\n")
      out.write_string("-----------------\n")
      out.write_string(report)
      out.write_string("\n")
    }
    None => ()
  }
  { out: out.to_string(), err, code: exit_success, }
}
