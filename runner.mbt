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
  if options.help {
    return { out: usage() + "\n", err: "", code: exit_success, }
  }
  let (text, source) = match read_input(options.file) {
    Ok(input) => input
    Err(message) => return failure("error: " + message, exit_input_error)
  }
  let json = match parse_with_diagnostic(text) {
    Ok(json) => json
    Err(diagnostic) =>
      return failure(
        "error: " + source + " is not valid JSON\n" + diagnostic.render(),
        exit_input_error,
      )
  }
  let formatted = format(json, options.indent)
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
            "error: cannot write " + path + ": " + message,
            exit_input_error,
          )
      }
    None => ()
  }
  // Nothing below can fail, so this is where standard output starts.
  let out = StringBuilder()
  if options.validate {
    // `-v` replaces the document with a one-line verdict, nothing else.
    out.write_string(source + ": valid JSON\n")
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
