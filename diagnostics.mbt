///|
/// A syntax or limit problem located in a specific piece of JSON text.
///
/// Offsets are character offsets into the original input, matching the offsets
/// reported by `Nanaloveyuki/parsec/json`.
pub struct JsonDiagnostic {
  offset : Int
  line : Int
  column : Int
  message : String
  snippet : String
}

///|
/// Convert a character offset into a 1-based `(line, column)` pair.
///
/// Offsets past the end of the input report the position just after the last
/// character, so an unexpected end of input still points somewhere sensible.
pub fn offset_to_line_col(input : String, offset : Int) -> (Int, Int) {
  let mut line = 1
  let mut column = 1
  let mut index = 0
  for ch in input {
    if index >= offset {
      break
    }
    if ch == '\n' {
      line = line + 1
      column = 1
    } else {
      column = column + 1
    }
    index = index + 1
  }
  (line, column)
}

///|
/// Extract the 1-based `line` from `input`, without its terminator.
pub fn line_text(input : String, line : Int) -> String {
  let mut current = 1
  let buf = StringBuilder()
  for ch in input {
    if current > line {
      break
    }
    if ch == '\n' {
      current = current + 1
    } else if current == line {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
/// Turn a low-level parsec error into a human-readable reason.
pub fn describe_syntax_error(error : @parsec.ParseError) -> String {
  match error {
    UnexpectedEnd(_) => "unexpected end of input"
    Expected(label~, ..) => "expected " + label
    ExpectedAny(labels~, ..) => {
      let buf = StringBuilder()
      buf.write_string("expected one of: ")
      let mut first = true
      for label in labels {
        if !first {
          buf.write_string(", ")
        }
        first = false
        buf.write_string(label)
      }
      buf.to_string()
    }
    NotFollowedBy(label~, ..) => "unexpected " + label
    Context(cause~, ..) => describe_syntax_error(cause)
    EmptyMatchInMany(_) => "repetition matched an empty input"
    EmptyChoice(_) => "no alternative matched"
    UnboundReference(_) => "unbound parser reference"
  }
}

///|
/// Turn a JSON error into a human-readable reason.
pub fn describe_json_error(error : @pjson.JsonError) -> String {
  match error {
    Syntax(error~) => describe_syntax_error(error)
    DuplicateKey(key~, ..) => "duplicate object key " + quote_for_message(key)
    Limit(kind~, limit~, ..) =>
      "input exceeds the " +
      describe_limit_kind(kind) +
      " limit of " +
      limit.to_string()
  }
}

///|
/// Human-readable name for a `JsonLimitKind`.
pub fn describe_limit_kind(kind : @pjson.JsonLimitKind) -> String {
  match kind {
    InputChars => "input length"
    NestingDepth => "nesting depth"
    StringChars => "string length"
    ArrayItems => "array length"
    ObjectMembers => "object member count"
  }
}

///|
/// Render `value` as a quoted, escaped literal for use in a message.
fn quote_for_message(value : String) -> String {
  "\"" + escape_json_string(value) + "\""
}

///|
/// Build a diagnostic for `error` located in `input`.
pub fn JsonDiagnostic::from_error(
  input : String,
  error : @pjson.JsonError,
) -> JsonDiagnostic {
  let offset = error.offset()
  let (line, column) = offset_to_line_col(input, offset)
  let message = describe_json_error(error)
  JsonDiagnostic::{
    offset,
    line,
    column,
    message,
    snippet: line_text(input, line),
  }
}

///|
/// Build a diagnostic for an explicit offset and message.
pub fn JsonDiagnostic::at(
  input : String,
  offset : Int,
  message : String,
) -> JsonDiagnostic {
  let (line, column) = offset_to_line_col(input, offset)
  JsonDiagnostic::{
    offset,
    line,
    column,
    message,
    snippet: line_text(input, line),
  }
}

///|
/// A one-line summary: `line 3, column 5: expected value`.
pub fn JsonDiagnostic::summary(self : JsonDiagnostic) -> String {
  "line " +
  self.line.to_string() +
  ", column " +
  self.column.to_string() +
  ": " +
  self.message
}

///|
/// A multi-line report: the summary followed by the offending source line and
/// a caret marking the column.
pub fn JsonDiagnostic::render(self : JsonDiagnostic) -> String {
  let buf = StringBuilder()
  buf.write_string(self.summary())
  if self.snippet != "" {
    buf.write_char('\n')
    buf.write_string("  " + self.snippet)
    buf.write_char('\n')
    buf.write_string("  ")
    for _ in 1..<self.column {
      buf.write_char(' ')
    }
    buf.write_char('^')
  }
  buf.to_string()
}
