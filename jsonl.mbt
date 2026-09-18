///|
/// Parse `input` as JSON Lines: one JSON document per line, each line standing
/// on its own.
///
/// Every line holding a document contributes one `Ok` and every line holding
/// something that is not one contributes one `Err`, so the results are the
/// documents of the file in the order they were written. A blank line — empty,
/// or nothing but whitespace — is skipped rather than reported: spacing a file
/// out that way is common, and there is nothing in such a line to complain
/// about. A file ending in a line separator therefore produces no trailing
/// empty record.
///
/// The diagnostics are positioned in `input` as a whole rather than in the line
/// they came out of, so a mistake on the fourth line of a file is reported as
/// line 4 with the fourth line quoted under it.
pub fn parse_jsonl(
  input : String,
) -> Array[Result[@pjson.Json, JsonDiagnostic]] {
  parse_jsonl_with_depth(input, None)
}

///|
/// `parse_jsonl` with the nesting limit `--max-depth` asks for.
///
/// The limit is applied to each record on its own, since a record is a document
/// of its own: depth is counted from the start of the line, not from the start
/// of the file.
pub fn parse_jsonl_with_depth(
  input : String,
  max_depth : Int?,
) -> Array[Result[@pjson.Json, JsonDiagnostic]] {
  let records = []
  let mut base = 0
  for piece in input.split("\n") {
    let record = piece.to_owned()
    if !record.trim().is_empty() {
      records.push(parse_record(input, base, record, max_depth))
    }
    // Blank lines are skipped, not forgotten: the offset still advances over
    // them, or every line after the first blank one would be misnumbered.
    base = base + count_chars(record) + 1
  }
  records
}

///|
/// The number of Unicode characters in `text`.
///
/// `String::length()` counts UTF-16 code units, which is not the unit an offset
/// in a diagnostic is measured in — `offset_to_line_col` counts characters. The
/// two agree on all of the basic multilingual plane and differ beyond it, where
/// one character is two code units, so counting with `length()` would move
/// every line after an emoji one column to the left and take the caret with it.
fn count_chars(text : String) -> Int {
  let mut total = 0
  for _ch in text {
    total = total + 1
  }
  total
}

///|
/// Parse one record, reporting its problems at their place in `whole`.
fn parse_record(
  whole : String,
  base : Int,
  record : String,
  max_depth : Int?,
) -> Result[@pjson.Json, JsonDiagnostic] {
  match parse_raw(record, max_depth) {
    Ok(json) => Ok(json)
    Err(error) => Err(JsonDiagnostic::for_record(whole, base, error))
  }
}
