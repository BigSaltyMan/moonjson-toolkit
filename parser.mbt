///|
/// Parse `text` as JSON, reporting the raw library error.
pub fn parse(text : String) -> Result[@pjson.Json, @pjson.JsonError] {
  @pjson.parse(text)
}

///|
/// The nesting depth the parser allows when the caller does not ask for a
/// different one.
///
/// This is the value `Nanaloveyuki/parsec/json` uses for `JsonLimits::standard()`,
/// restated because the struct keeps its fields private and exposes no
/// accessors. `parser_wbtest.mbt` measures the limit the library actually
/// applies and fails if the two ever disagree.
pub let standard_max_depth : Int = 128

///|
/// Parse `text`, turning any failure into a diagnostic that carries the line,
/// the column and a human-readable reason.
///
/// `max_depth` caps how many collections may nest, counting one for each array
/// or object entered. `Some(limit)` refuses anything deeper, reporting the
/// position where the limit was passed; `None` leaves the parser's own default
/// in place. Either way the other four size limits keep their standard values,
/// so this changes only how deep a document may go.
pub fn parse_with_diagnostic(
  text : String,
  max_depth : Int?,
) -> Result[@pjson.Json, JsonDiagnostic] {
  match parse_raw(text, max_depth) {
    Ok(json) => Ok(json)
    Err(error) => Err(JsonDiagnostic::from_error(text, error))
  }
}

///|
/// The parser call itself, with no diagnostic built around it.
///
/// Split out because JSON Lines parses a record at a time and needs the raw
/// error to place it in the file as a whole rather than in the record.
fn parse_raw(
  text : String,
  max_depth : Int?,
) -> Result[@pjson.Json, @pjson.JsonError] {
  match max_depth {
    None => @pjson.parse(text)
    Some(limit) => @pjson.parse_with_limits(text, depth_limits(limit))
  }
}

///|
/// The standard limits, with `max_depth` replaced by `limit`.
///
/// Four of the five fields are the sizes `JsonLimits::standard()` picks, spelled
/// out again because only the depth is meant to change and the struct offers no
/// way to read the others back.
fn depth_limits(limit : Int) -> @pjson.JsonLimits {
  @pjson.JsonLimits::new(
    max_input_chars=1_048_576,
    max_depth=limit,
    max_string_chars=262_144,
    max_array_items=65_536,
    max_object_members=65_536,
  )
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
