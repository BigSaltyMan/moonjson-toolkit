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
/// Reject the command lines that do not describe a run, before any input is
/// read.
///
/// Each of them pairs a request that only makes sense for one document with a
/// command line that names more than one, and the answer is to refuse rather
/// than to answer for the first of them and quietly drop the rest.
fn validate_options(options : CliOptions) -> Result[Unit, String] {
  if options.files.length() > 1 && options.json_out != None {
    return Err(
      "--json-out describes a single document, but " +
      options.files.length().to_string() +
      " files were given",
    )
  }
  if options.jsonl {
    // Each of these asks about a document as a whole: a statistics file to
    // write, a review to ask for, or a summary of the structure to print. A
    // JSON Lines input is many documents, and none of those answers survives
    // being repeated once per record with nothing to say which record it
    // belongs to.
    let refused = if options.json_out != None {
      Some("--json-out")
    } else if options.ai {
      Some("--ai")
    } else if options.stats {
      Some("--stats")
    } else if options.paths {
      Some("--paths")
    } else if options.keys_only {
      Some("--keys-only")
    } else {
      None
    }
    match refused {
      Some(option) =>
        return Err(
          option +
          " describes a single document, and --jsonl reads many: the two cannot be combined",
        )
      None => ()
    }
  }
  Ok(())
}

///|
/// Apply the changes that alter the document rather than its layout.
///
/// Trimming rewrites the strings and sorting rebuilds the objects, so both
/// happen before anything is printed and the review sees them too. The order
/// between the two does not matter: neither looks at what the other changes,
/// one moving keys and the other rewriting values.
fn prepare_document(options : CliOptions, json : @pjson.Json) -> @pjson.Json {
  let trimmed = if options.trim_strings { trim_strings(json) } else { json }
  if options.sort_keys {
    sort_keys(trimmed)
  } else {
    trimmed
  }
}

///|
/// Render a document in the layout the options ask for.
///
/// `--compact` wants a document with no line breaks in it at all, which is what
/// `--indent` exists to place, so the width is simply not consulted.
fn format_document(options : CliOptions, json : @pjson.Json) -> String {
  if options.compact {
    format_compact(json)
  } else {
    format(json, options.indent)
  }
}

///|
/// Run the tool over `args` and collect everything it produced.
///
/// Several `--file` arguments mean several documents, and each is handled in
/// turn by `run_document`: a file that fails is reported on standard error and
/// the ones after it are still processed, so one bad input does not hide the
/// state of the rest. The run ends with the first non-zero code any of them
/// produced — the earliest failure is the one worth naming, and the other
/// failures are already on standard error beside it.
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
  // Checked before any input is read, so a command line that names several
  // documents and then asks a question about one of them costs nothing to
  // answer.
  match validate_options(options) {
    Ok(_) => ()
    Err(message) =>
      return failure(
        error_prefix() +
        message +
        "\nrun 'moonjson-toolkit --help' to see the available options",
        exit_usage_error,
      )
  }
  let inputs : Array[String?] = if options.files.length() == 0 {
    // No file named is not no input: standard input is the document.
    [None]
  } else {
    options.files.map(fn(path) { Some(path) })
  }
  // A heading is only worth printing when there is more than one document to
  // tell apart, which is why a single file reads exactly as it always has.
  let many = inputs.length() > 1
  let out = StringBuilder()
  let err = StringBuilder()
  let mut code = exit_success
  for input in inputs {
    let (text, source) = match read_input(input) {
      Ok(read) => read
      Err(message) => {
        err.write_string(error_prefix() + message + "\n")
        if code == exit_success {
          code = exit_input_error
        }
        continue
      }
    }
    let result = if options.jsonl {
      run_jsonl(options, source, text)
    } else {
      run_document(options, source, text, analyze)
    }
    if many && result.out != "" {
      out.write_string("==> " + source + " <==\n")
    }
    out.write_string(result.out)
    err.write_string(result.err)
    if code == exit_success {
      code = result.code
    }
  }
  { out: out.to_string(), err: err.to_string(), code, }
}

///|
/// Handle one document, from its text to everything the run prints for it.
///
/// Every step that can fail — parsing, the AI review, writing the statistics
/// file — runs before a single byte for this document reaches `out`, so a
/// failure never leaves a half-written document on standard output. `-v`
/// suppresses only the formatted document itself; `--json-out` and `--ai` still
/// run.
async fn run_document(
  options : CliOptions,
  source : String,
  text : String,
  analyze : async (String) -> Result[String, String],
) -> RunResult {
  let json = match parse_with_diagnostic(text, options.max_depth) {
    Ok(json) => json
    Err(diagnostic) =>
      return failure(
        error_prefix() + source + " is not valid JSON\n" + diagnostic.render(),
        exit_input_error,
      )
  }
  render_document(options, source, json, analyze)
}

///|
/// Everything one parsed document produces, from the options to the text.
///
/// Split from `run_document` so that a parse failure is the only thing that has
/// to happen before this point: from here on the document is known to be good.
async fn render_document(
  options : CliOptions,
  source : String,
  json : @pjson.Json,
  analyze : async (String) -> Result[String, String],
) -> RunResult {
  let prepared = prepare_document(options, json)
  let formatted = format_document(options, prepared)
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
      collect_paths(prepared)
    } else {
      collect_key_paths(prepared)
    }
    for name in names {
      out.write_string(name)
      out.write_string("\n")
    }
  } else if show_stats {
    // Computed from `json` rather than from `prepared`: sorting and trimming
    // change how the document is printed and none of these counts, and taking
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

///|
/// Handle one JSON Lines input: every record is rendered onto a line of its
/// own, and every record that is not valid JSON is reported on standard error.
///
/// A bad record does not stop the run. Each line of the input stands alone by
/// definition, so the ones that can be read are printed whether or not the
/// others could be, and a mistake on the fourth line does not cost the reader
/// the fifth. The code is the first non-zero one any record produced, so a run
/// with a single bad record ends 1 however many good ones followed it.
///
/// `-v` asks for no document output at all, so a run where every record parsed
/// is answered with the one verdict line it prints for a single document, and a
/// run where one did not is answered by that record's report alone.
fn run_jsonl(options : CliOptions, source : String, text : String) -> RunResult {
  let out = StringBuilder()
  let err = StringBuilder()
  let mut code = exit_success
  for record in parse_jsonl_with_depth(text, options.max_depth) {
    match record {
      Ok(json) =>
        if !options.validate {
          out.write_string(
            format_document(options, prepare_document(options, json)),
          )
          out.write_string("\n")
        }
      Err(diagnostic) => {
        err.write_string(
          error_prefix() +
          source +
          " is not valid JSON\n" +
          diagnostic.render() +
          "\n",
        )
        if code == exit_success {
          code = exit_input_error
        }
      }
    }
  }
  if options.validate && code == exit_success {
    out.write_string(source + ": valid JSON\n")
  }
  { out: out.to_string(), err: err.to_string(), code, }
}
