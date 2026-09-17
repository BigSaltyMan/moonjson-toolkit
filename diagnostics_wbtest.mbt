///|
/// Parse `text` expecting failure and return the rendered diagnostic.
fn diagnostic_for(text : String) -> JsonDiagnostic {
  match @pjson.parse(text) {
    Ok(_) => abort("expected {text} to fail parsing")
    Err(error) => JsonDiagnostic::from_error(text, error)
  }
}

///|
test "offset_to_line_col starts at line one column one" {
  assert_eq(offset_to_line_col("abc", 0), (1, 1))
  assert_eq(offset_to_line_col("abc", 2), (1, 3))
}

///|
test "offset_to_line_col reports the position after the last character" {
  assert_eq(offset_to_line_col("abc", 3), (1, 4))
}

///|
test "offset_to_line_col tracks newlines" {
  let input = "{\n  \"a\": 1\n}"
  assert_eq(offset_to_line_col(input, 3), (2, 2))
  assert_eq(offset_to_line_col(input, 11), (3, 1))
}

///|
test "offset_to_line_col clamps offsets past the end" {
  assert_eq(offset_to_line_col("a\nb", 99), (2, 2))
}

///|
test "line_text extracts the offending line" {
  assert_eq(line_text("one\ntwo\nthree", 2), "two")
  assert_eq(line_text("one\ntwo\nthree", 3), "three")
  assert_eq(line_text("one\ntwo\nthree", 9), "")
}

///|
test "a trailing comma points at the offending column" {
  let diagnostic = diagnostic_for("{\"a\":1,}")
  assert_eq(diagnostic.line, 1)
  assert_eq(diagnostic.column, 8)
  assert_eq(diagnostic.message, "expected opening quote")
  assert_eq(diagnostic.summary(), "line 1, column 8: expected opening quote")
}

///|
test "render includes the source line and a caret" {
  let rendered = diagnostic_for("{\"a\":1,}").render()
  assert_eq(
    rendered, "line 1, column 8: expected opening quote\n  {\"a\":1,}\n         ^",
  )
}

///|
test "an unterminated object reports a missing brace" {
  assert_eq(diagnostic_for("{\"a\":1").message, "expected closing brace")
}

///|
test "an unterminated array reports a missing bracket" {
  assert_eq(diagnostic_for("[1,2").message, "expected closing bracket")
}

///|
test "a duplicate key is reported with its line and column" {
  let diagnostic = diagnostic_for("{\"a\":1,\"a\":2}")
  // The caret belongs on the repeat, and the message also names the original so
  // that the two spellings can be told apart without hunting for them.
  assert_eq(
    diagnostic.message,
    "duplicate object key \"a\" (first defined at line 1, column 2)",
  )
  assert_eq(diagnostic.column, 8)
}

///|
test "the first definition of a repeated key is located on its own line" {
  let diagnostic = diagnostic_for("{\n  \"a\": 1,\n  \"b\": 2,\n  \"a\": 3\n}")
  assert_eq(diagnostic.line, 4)
  assert_eq(diagnostic.column, 3)
  assert_eq(
    diagnostic.message,
    "duplicate object key \"a\" (first defined at line 2, column 3)",
  )
}

///|
test "a truncated literal reports what was expected" {
  assert_eq(diagnostic_for("tru").message, "expected true")
}

///|
test "a missing colon is reported" {
  assert_eq(diagnostic_for("{\"a\" 1}").message, "expected colon")
}

///|
test "diagnostics survive a multi-line document" {
  let input = "{\n  \"a\": 1,\n  \"b\": ,\n}"
  let diagnostic = diagnostic_for(input)
  assert_eq(diagnostic.line, 3)
  assert_eq(diagnostic.column, 8)
  // A missing value lists every alternative the grammar would have accepted.
  assert_true(
    diagnostic.message.has_prefix("expected one of: null, true, false"),
  )
}

///|
test "limit kinds have readable names" {
  assert_eq(describe_limit_kind(NestingDepth), "nesting depth")
  assert_eq(describe_limit_kind(InputChars), "input length")
}
