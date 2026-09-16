///|
/// Parse `text` as JSON, reporting the raw library error.
pub fn parse(text : String) -> Result[@pjson.Json, @pjson.JsonError] {
  @pjson.parse(text)
}

///|
/// Parse `text`, turning any failure into a diagnostic that carries the line,
/// the column and a human-readable reason.
pub fn parse_with_diagnostic(
  text : String,
) -> Result[@pjson.Json, JsonDiagnostic] {
  match @pjson.parse(text) {
    Ok(json) => Ok(json)
    Err(error) => Err(JsonDiagnostic::from_error(text, error))
  }
}

///|
/// Render a caught error as a concise message fit for one line of output.
///
/// Operating-system failures are reduced to a plain-language reason. The debug
/// form of these errors carries internal call context that only clutters a CLI
/// message, so the errno is translated through the public predicates instead.
fn describe_io_error(error : Error) -> String {
  match error {
    @os_error.OSError(errno, ..) as failure =>
      if failure.is_ENOENT() {
        "no such file or directory"
      } else if failure.is_EACCES() {
        "permission denied"
      } else if failure.is_ENOTDIR() {
        "not a directory"
      } else {
        "operating system error " + errno.to_string()
      }
    _ => @debug.to_string(error)
  }
}

///|
/// Read `path` as UTF-8 text.
///
/// The failure is reported as a message rather than an error value so that the
/// caller can print it and exit with code 1 without unwrapping anything.
pub async fn read_file(path : String) -> Result[String, String] {
  Ok(@fs.read_file(path).text()) catch {
    error => Err(describe_io_error(error))
  }
}

///|
/// Read all of standard input as UTF-8 text.
pub async fn read_stdin() -> Result[String, String] {
  Ok(@stdio.stdin.read_all().text()) catch {
    error => Err(describe_io_error(error))
  }
}
