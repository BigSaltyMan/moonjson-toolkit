///|
/// Indentation width used when the caller does not ask for a specific one.
pub let default_indent : Int = 2

///|
/// Largest indentation width the formatter accepts.
pub let max_indent : Int = 16

///|
/// Clamp a caller-supplied indent width into the supported `0..=16` range.
pub fn clamp_indent(indent : Int) -> Int {
  if indent < 0 {
    0
  } else if indent > max_indent {
    max_indent
  } else {
    indent
  }
}

///|
/// Render one code point as a four-digit `\uXXXX` escape body.
fn hex4(code : Int) -> String {
  let digits = "0123456789abcdef"
  let table = digits.to_array()
  let buf = StringBuilder()
  for shift in [12, 8, 4, 0] {
    buf.write_char(table[(code >> shift) & 0xF])
  }
  buf.to_string()
}

///|
/// Append `value` to `buf` as the *contents* of a JSON string.
///
/// Quotes and backslashes are escaped, the short escapes are used where one
/// exists, and any remaining control character becomes a `\uXXXX` escape.
pub fn escape_json_string(value : String) -> String {
  let buf = StringBuilder()
  for ch in value {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\u{08}' => buf.write_string("\\b")
      '\u{0C}' => buf.write_string("\\f")
      _ =>
        if ch.to_int() < 0x20 {
          buf.write_string("\\u")
          buf.write_string(hex4(ch.to_int()))
        } else {
          buf.write_char(ch)
        }
    }
  }
  buf.to_string()
}

///|
/// Emit the line break and leading spaces that open a nesting level.
fn break_line(buf : StringBuilder, level : Int, width : Int) -> Unit {
  buf.write_char('\n')
  let spaces = level * width
  for _ in 0..<spaces {
    buf.write_char(' ')
  }
}

///|
/// Write `json` to `buf`, breaking lines according to `width`.
fn write_json(
  buf : StringBuilder,
  json : @pjson.Json,
  level : Int,
  width : Int,
) -> Unit {
  match json {
    Null => buf.write_string("null")
    Bool(value~) => buf.write_string(if value { "true" } else { "false" })
    // The parser keeps the original literal, so `1e2` and `1.0` round-trip
    // exactly instead of being reformatted through a Double.
    Number(raw~) => buf.write_string(raw)
    Text(value~) => {
      buf.write_char('"')
      buf.write_string(escape_json_string(value))
      buf.write_char('"')
    }
    Array(items~) =>
      if items.is_empty() {
        buf.write_string("[]")
      } else {
        buf.write_char('[')
        let mut first = true
        for item in items {
          if !first {
            buf.write_char(',')
          }
          first = false
          break_line(buf, level + 1, width)
          write_json(buf, item, level + 1, width)
        }
        break_line(buf, level, width)
        buf.write_char(']')
      }
    Object(members~) =>
      if members.is_empty() {
        buf.write_string("{}")
      } else {
        buf.write_char('{')
        let mut first = true
        for entry in members {
          let (key, value) = entry
          if !first {
            buf.write_char(',')
          }
          first = false
          break_line(buf, level + 1, width)
          buf.write_char('"')
          buf.write_string(escape_json_string(key))
          buf.write_string("\": ")
          write_json(buf, value, level + 1, width)
        }
        break_line(buf, level, width)
        buf.write_char('}')
      }
  }
}

///|
/// Render `json` as indented, human-readable JSON text.
///
/// `indent` is the number of spaces per nesting level and is clamped to
/// `0..=16`. An indent of `0` keeps the line breaks but drops the leading
/// spaces. Empty arrays and objects are rendered inline as `[]` and `{}`.
pub fn format(json : @pjson.Json, indent : Int) -> String {
  let width = clamp_indent(indent)
  let buf = StringBuilder()
  write_json(buf, json, 0, width)
  buf.to_string()
}

///|
/// Write `json` to `buf` as one unbroken line.
///
/// No line break and no padding space is emitted anywhere, including after the
/// colon that separates an object key from its value. The only spaces that
/// survive are the ones inside string contents, which are data and are escaped
/// exactly as the indented form escapes them.
fn write_compact(buf : StringBuilder, json : @pjson.Json) -> Unit {
  match json {
    Null => buf.write_string("null")
    Bool(value~) => buf.write_string(if value { "true" } else { "false" })
    Number(raw~) => buf.write_string(raw)
    Text(value~) => {
      buf.write_char('"')
      buf.write_string(escape_json_string(value))
      buf.write_char('"')
    }
    // An empty array or object writes its two brackets and nothing between
    // them, so `[]` and `{}` need no special case here.
    Array(items~) => {
      buf.write_char('[')
      let mut first = true
      for item in items {
        if !first {
          buf.write_char(',')
        }
        first = false
        write_compact(buf, item)
      }
      buf.write_char(']')
    }
    Object(members~) => {
      buf.write_char('{')
      let mut first = true
      for entry in members {
        let (key, value) = entry
        if !first {
          buf.write_char(',')
        }
        first = false
        buf.write_char('"')
        buf.write_string(escape_json_string(key))
        buf.write_string("\":")
        write_compact(buf, value)
      }
      buf.write_char('}')
    }
  }
}

///|
/// Render `json` on a single line, with no padding spaces.
///
/// The result parses back to the same document as `format(json, indent)`; only
/// the layout differs. Callers that ask for this are usually piping the output
/// somewhere a line break would be noise, so the indent width has no effect.
pub fn format_compact(json : @pjson.Json) -> String {
  let buf = StringBuilder()
  write_compact(buf, json)
  buf.to_string()
}

///|
/// Return `json` with the members of every object ordered by key.
///
/// Keys are compared with `String::compare`, so the order is code point by code
/// point: ASCII keys come out the way a dictionary would list them, and upper
/// case sorts before lower case. The ordering reaches every object in the
/// document, including the ones nested inside arrays.
///
/// The argument is not modified. Each object is rebuilt around a fresh array
/// rather than sorted in place, so a caller that still holds the original tree
/// keeps seeing the document in the order it was written.
pub fn sort_keys(json : @pjson.Json) -> @pjson.Json {
  match json {
    Object(members~) => {
      let rebuilt = members.map(fn(entry) {
        let (key, value) = entry
        (key, sort_keys(value))
      })
      rebuilt.sort_by(fn(left, right) {
        let (left_key, _) = left
        let (right_key, _) = right
        left_key.compare(right_key)
      })
      Object(members=rebuilt)
    }
    Array(items~) => Array(items=items.map(fn(item) { sort_keys(item) }))
    // Everything else is a leaf: a scalar holds no keys to order.
    leaf => leaf
  }
}

///|
/// Return `json` with the leading and trailing whitespace removed from every
/// string in it.
///
/// The whitespace removed is the set `String::trim` defines — space, tab,
/// newline and carriage return — which is exactly the set JSON itself treats as
/// whitespace between tokens. Only the ends of a string are touched, so spaces
/// inside a value are part of it and stay: `"  a  b  "` becomes `"a  b"`.
///
/// Keys are left alone. A key is a name rather than a value, and trimming one
/// would rename it: two keys differing only in the spaces around them would
/// collapse into the repeated key the parser refuses, turning a document that
/// parsed into one that would not.
///
/// The argument is not modified, for the same reason `sort_keys` is not: the
/// containers are rebuilt, so a caller still holding the original tree keeps
/// seeing the document as it was written.
pub fn trim_strings(json : @pjson.Json) -> @pjson.Json {
  match json {
    Text(value~) => Text(value=value.trim().to_owned())
    Object(members~) => {
      let rebuilt = members.map(fn(entry) {
        let (key, value) = entry
        (key, trim_strings(value))
      })
      Object(members=rebuilt)
    }
    Array(items~) => Array(items=items.map(fn(item) { trim_strings(item) }))
    // Everything else is a leaf: a number keeps the literal it was written
    // with, and there is nothing in a null or a boolean to trim.
    leaf => leaf
  }
}
