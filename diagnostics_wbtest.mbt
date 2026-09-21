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

///|
/// The three lines of a rendered report: the summary, the source line, and the
/// caret under it.
fn report_lines(rendered : String) -> (String, String, String) {
  let lines = rendered.split("\n").collect()
  if lines.length() != 3 {
    abort("expected a three-line report, got: " + rendered)
  }
  (lines[0].to_owned(), lines[1].to_owned(), lines[2].to_owned())
}

///|
/// A one-line document of exactly `count` characters that fails at its last
/// character: a long string, closed, with one character of junk after it.
///
/// The mistake is where the construction puts it, so the column the report
/// should name is known without asking the parser.
fn long_broken_line(count : Int) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  for _ in 0..<(count - 3) {
    buf.write_char('a')
  }
  buf.write_string("\"X")
  buf.to_string()
}

///|
/// A line of `count` characters with one bad character in the middle, and the
/// one-based column of that character.
fn line_with_a_mistake_at(count : Int, at : Int) -> (String, Int) {
  let buf = StringBuilder()
  for index in 0..<count {
    buf.write_char(if index == at - 1 { 'X' } else { 'a' })
  }
  (buf.to_string(), at)
}

///|
/// A line too long to print is elided around the column, and the caret keeps its
/// place: this is the case that used to print the whole line, which for a
/// document written on one line is the whole document.
test "an over-long line is elided around the column" {
  let input = long_broken_line(500)
  assert_eq(input.char_length(), 500)
  let diagnostic = diagnostic_for(input)
  let (summary, snippet, caret) = report_lines(diagnostic.render())
  // The position reported is the one in the document, not the one in the
  // elided line: the line and column are what a person needs to find the
  // mistake in an editor, and they do not move.
  assert_eq(summary, "line 1, column 500: " + diagnostic.message)
  assert_eq(diagnostic.line, 1)
  assert_eq(diagnostic.column, 500)
  // Two spaces of indent, three of leading ellipsis, the sixty characters
  // before the column, and the one the caret is under: the line ends at the
  // column, so the sixty that would have followed it are not there to show.
  assert_eq(snippet.char_length(), 2 + 3 + snippet_margin + 1)
  assert_true(snippet.has_prefix("  ..."))
  assert_true(snippet.has_suffix("\"X"))
  assert_true(snippet.char_length() <= 130)
  assert_eq(caret.char_length(), snippet.char_length())
  assert_true(caret.has_suffix("^"))
  // The caret is under the `X`, which is the character the column names: the
  // last one on the line, and so the last one in what is left of it.
  assert_eq(snippet.code_units()[caret.char_length() - 1].to_int(), 88)
}

///|
test "a line short enough to read is printed whole" {
  let diagnostic = diagnostic_for("{\"a\":1,}")
  let (_, snippet, caret) = report_lines(diagnostic.render())
  assert_eq(snippet, "  {\"a\":1,}")
  assert_eq(caret, "         ^")
}

///|
/// The boundary of the elision, either side of it: `snippet_margin` characters
/// twice over is still one line, and one character more is not.
test "the elision starts one character past twice the margin" {
  let (whole, column) = line_with_a_mistake_at(snippet_margin * 2, 100)
  let (shown, caret) = snippet_window(whole, column)
  assert_eq(shown, whole)
  assert_eq(caret, 99)
  // One character more, with the column a hundred in: sixty characters either
  // side of it, except that the line ends first, so only the head is elided.
  let (longer, column) = line_with_a_mistake_at(snippet_margin * 2 + 1, 100)
  let (shown, caret) = snippet_window(longer, column)
  assert_eq(shown.char_length(), 3 + snippet_margin + 22)
  assert_eq(caret, snippet_margin + 3)
  assert_true(shown.has_prefix("..."))
  assert_false(shown.has_suffix("..."))
  // The character the caret is under is the one the column names.
  assert_eq(shown.code_units()[caret].to_int(), 88)
}

///|
/// A mistake in the middle of a line long enough that the window fits inside it
/// without reaching either end: the line is then elided at both, and the caret
/// still lands on the character the column names.
test "a long line is elided at both ends" {
  let (line, column) = line_with_a_mistake_at(1000, 500)
  let (shown, caret) = snippet_window(line, column)
  assert_eq(shown.char_length(), 6 + snippet_margin * 2)
  assert_eq(caret, snippet_margin + 3)
  assert_true(shown.has_prefix("..."))
  assert_true(shown.has_suffix("..."))
  assert_eq(shown.code_units()[caret].to_int(), 88)
}
