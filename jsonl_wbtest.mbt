///|
/// The document a record holds, so a test can say what it expected to read
/// without spelling out the tree it parses to.
fn record_text(record : Result[@pjson.Json, JsonDiagnostic]) -> String {
  match record {
    Ok(json) => format_compact(json)
    Err(diagnostic) =>
      abort("this record should have parsed: " + diagnostic.render())
  }
}

///|
/// The diagnostic a record must carry, for the tests about what went wrong.
fn record_error(record : Result[@pjson.Json, JsonDiagnostic]) -> JsonDiagnostic {
  match record {
    Ok(json) =>
      abort("this record should not have parsed: " + format_compact(json))
    Err(diagnostic) => diagnostic
  }
}

///|
test "jsonl incremental: order and public array compatibility" {
  let input = "\n1\n \t\n{\ntrue\n"
  let lines = []
  let records = []
  visit_jsonl_records(input, None, fn(line, record) {
    lines.push(line)
    records.push(record)
    true
  })
  assert_eq(lines, [2, 4, 5])
  assert_eq(jsonl_record_lines(input), lines)
  for
    collected in [
      records,
      parse_jsonl(input),
      parse_jsonl_with_depth(input, None),
    ] {
    assert_eq(collected.length(), 3)
    assert_eq(record_text(collected[0]), "1")
    assert_eq(record_error(collected[1]).line, 4)
    assert_eq(record_text(collected[2]), "true")
  }
  for empty in ["", "\n \t\r\n"] {
    let mut calls = 0
    visit_jsonl_records(empty, None, fn(_line, _record) {
      calls = calls + 1
      true
    })
    assert_eq(calls, 0)
    assert_eq(parse_jsonl(empty).length(), 0)
  }
  assert_eq(parse_jsonl("1").map(record_text), ["1"])
  assert_eq(parse_jsonl("1\n").map(record_text), ["1"])
}

///|
test "jsonl incremental: CRLF Unicode diagnostics and per-record depth" {
  let input = "\r\n{\"😀\":1}\r\n \t\r\n{\"中\":}\r\n[[]]\r\n[]\r\n"
  let lines = []
  let records = []
  visit_jsonl_records(input, Some(1), fn(line, record) {
    lines.push(line)
    records.push(record)
    true
  })
  assert_eq(lines, [2, 4, 5, 6])
  assert_eq(record_text(records[0]), "{\"😀\":1}")
  let syntax = record_error(records[1])
  assert_eq(syntax.line, 4)
  assert_eq(syntax.column, 6)
  assert_eq(syntax.offset, 20)
  assert_eq(syntax.snippet, "{\"中\":}\r")
  let depth = record_error(records[2])
  assert_eq(depth.line, 5)
  assert_eq(depth.column, 2)
  assert_eq(depth.offset, 24)
  assert_eq(depth.snippet, "[[]]\r")
  assert_eq(depth.message, "nesting depth exceeds limit 1")
  assert_eq(record_text(records[3]), "[]")
  // The public bounded collector still applies the same per-record limit.
  let collected = parse_jsonl_with_depth(input, Some(1))
  assert_eq(record_error(collected[2]).offset, depth.offset)
  assert_eq(record_text(collected[3]), "[]")
}

///|
test "jsonl incremental: stop after a successful or failed record" {
  for (first, successful) in [("1", true), ("{", false)] {
    let lines = []
    let outcomes = []
    visit_jsonl_records("\n" + first + "\n{\n3\n", None, fn(line, record) {
      lines.push(line)
      outcomes.push(record is Ok(_))
      false
    })
    assert_eq(lines, [2])
    assert_eq(outcomes, [successful])
  }
}

///|
test "every record of a JSON Lines input is parsed, in order" {
  let records = parse_jsonl("{\"a\":1}\n[1,2]\n\"x\"\ntrue\n")
  assert_eq(records.length(), 4)
  assert_eq(records.map(record_text), ["{\"a\":1}", "[1,2]", "\"x\"", "true"])
}

///|
test "a record in the middle that is not valid JSON is reported where it is" {
  let records = parse_jsonl("{\"a\":1}\n{\"b\":}\n{\"c\":3}\n")
  assert_eq(records.length(), 3)
  // The records on either side are unaffected: a mistake in one line of a JSON
  // Lines file does not cost the reader any other line.
  assert_eq(record_text(records[0]), "{\"a\":1}")
  assert_eq(record_text(records[2]), "{\"c\":3}")
  let diagnostic = record_error(records[1])
  // The position is in the file, not in the record: line 2 is the second line
  // of the input, and the snippet is that line as it was written.
  inspect(diagnostic.line, content="2")
  inspect(diagnostic.column, content="6")
  inspect(diagnostic.snippet, content="{\"b\":}")
  assert_true(
    diagnostic.summary().contains("expected one of: null, true, false"),
  )
}

///|
test "blank lines are skipped without losing the count of the others" {
  let records = parse_jsonl("\n{\"a\":1}\n   \n\t\n{\"b\":2}\n\n")
  // Four lines hold nothing, two hold a document, and only the documents are
  // reported: spacing a file out is not something to complain about.
  assert_eq(records.map(record_text), ["{\"a\":1}", "{\"b\":2}"])
  // Skipping a line must not skip its length: the offset still has to advance
  // over the blank lines, or every line after the first one would be numbered
  // as though it came earlier in the file.
  let after_blanks = parse_jsonl("\n\n{\"a\":}\n")
  inspect(record_error(after_blanks[0]).line, content="3")
  inspect(record_error(after_blanks[0]).snippet, content="{\"a\":}")
}

///|
test "a last record with no trailing newline is still a record" {
  let records = parse_jsonl("{\"a\":1}\n{\"b\":2}")
  assert_eq(records.map(record_text), ["{\"a\":1}", "{\"b\":2}"])
  // A file that does end in a line separator has no empty last line to skip,
  // and an empty input is no records at all rather than one empty one.
  assert_eq(parse_jsonl("{\"a\":1}\n").length(), 1)
  assert_eq(parse_jsonl("").length(), 0)
  assert_eq(parse_jsonl("\n\n").length(), 0)
}

///|
test "every record is reported against the line it was written on" {
  // The lines a record starts on are the lines the parser skips blank ones
  // around, so the two lists line up: a record reported by number has to be
  // numbered the way a reader of the file would.
  let input = "\n{\"a\":1}\n   \n\t\n{\"b\":}\n{\"c\":3}\n"
  let lines = jsonl_record_lines(input)
  assert_eq(lines.length(), parse_jsonl(input).length())
  assert_eq(lines, [2, 5, 6])
  // Four blank lines in a row move the count as much as one does per line, and
  // an input with no records has no lines to report.
  assert_eq(jsonl_record_lines("\n\n\n\n{\"a\":1}"), [5])
  assert_eq(jsonl_record_lines("").length(), 0)
  assert_eq(jsonl_record_lines("\n\n").length(), 0)
  assert_eq(jsonl_record_lines("{\"a\":1}"), [1])
  assert_eq(jsonl_record_lines("{\"a\":1}\n{\"b\":2}"), [1, 2])
}

///|
test "an astral character does not move the lines that follow it" {
  // An emoji is one character but two UTF-16 code units, and the two ways of
  // measuring a string disagree about it. A diagnostic counts characters, so an
  // offset into the file has to be measured the same way, or the line after a
  // non-BMP character would be reported as though part of it had already been
  // read.
  let records = parse_jsonl("{\"\u{1F389}\":1}\n{\"a\":}\n")
  assert_eq(records.length(), 2)
  assert_eq(record_text(records[0]), "{\"\u{1F389}\":1}")
  let diagnostic = record_error(records[1])
  inspect(diagnostic.line, content="2")
  inspect(diagnostic.column, content="6")
  inspect(diagnostic.snippet, content="{\"a\":}")
}
