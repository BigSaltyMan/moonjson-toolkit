///|
async test "jsonl stream report: normal records diagnostics and empty input" {
  let schema = "{\"properties\":{\"n\":{\"type\":\"integer\"}}}"
  let compiled = ref_compiled(schema)
  let mixed = "\r\n{\"n\":1,\"文\":\"😀\"}\r\n \t\r\n{\"n\":\"bad\"}\r\n{\"中\":}\r\n{\"n\":2}"
  for
    (text, extra, code, valid, invalid, errors, lines) in [
      (mixed, [], 1, 2, 1, 1, [2, 4, 5, 6]),
      ("", [], 0, 0, 0, 0, []),
      (" \r\n\t\n", [], 0, 0, 0, 0, []),
      ("{\"n\":3}", [], 0, 1, 0, 0, [1]),
      ("{}\n[[0]]\n{}", ["--max-depth", "1"], 1, 2, 0, 1, [1, 2, 3]),
    ] {
    let options = cli_ok(
      [
        "-v", "--jsonl", "--schema", "schema.json", "--schema-output", "json", "--no-color",
      ] +
      extra,
    )
    let (reader, probe) = jsonl_probe_input(
      jsonl_byte_chunks(@utf8.encode(text), 2),
    )
    let result = run_schema_jsonl_reader_report(
      options,
      "schema.json",
      compiled,
      None,
      reader,
    )
    assert_eq(result.code, code)
    assert_eq(probe.releases, 1)
    let report = if code == 0 {
      assert_eq(result.err, "")
      report_json(result.out)
    } else {
      assert_eq(result.out, "")
      report_json(result.err)
    }
    assert_jsonl_summary(report, lines.length(), valid, invalid, errors)
    assert_true(report_field(report, "schemaFile") is Text(value="schema.json"))
    assert_true(report_field(report, "inputFile") is Text(value="<stdin>"))
    assert_true(
      report_field(report, "status") is Text(value~) &&
      value ==
      (if errors > 0 {
        "error"
      } else if invalid > 0 {
        "invalid"
      } else {
        "valid"
      }),
    )
    assert_eq(report_issues(report).length(), 0)
    let rows = batch_report_results(report)
    for index, line in lines {
      assert_true(
        report_field(rows[index], "line") is Number(raw~) &&
        raw == line.to_string(),
      )
    }
    if text == mixed {
      let violation = report_issues(rows[1])[0]
      assert_true(
        report_field(violation, "kind") is Text(value="ValidationError"),
      )
      assert_true(report_field(violation, "location") is Text(value="n"))
      let parse = report_issues(rows[2])[0]
      assert_true(report_field(parse, "kind") is Text(value="ParseError"))
      assert_true(report_field(parse, "stage") is Text(value="input"))
      assert_true(report_field(parse, "location") is Null)
      assert_true(
        report_field(parse, "message") is Text(value~) &&
        value.has_prefix("line 5, column 6:"),
      )
      assert_true(report_field(rows[3], "status") is Text(value="valid"))
    }
    if !extra.is_empty() {
      let issue = report_issues(rows[1])[0]
      assert_true(
        report_field(issue, "message") is Text(value~) &&
        value.has_prefix("line 2, column 2: nesting depth exceeds limit 1"),
      )
    }
  }
  // The public runner's file path uses the same reader and keeps its file label.
  let (result, paths) = batch_report_case(
    "stream_report_file",
    Some(schema),
    [Some(mixed)],
    extra=["--jsonl"],
  )
  assert_eq(result.code, 1)
  assert_eq(result.out, "")
  let report = report_json(result.err)
  assert_jsonl_summary(report, 4, 2, 1, 1)
  assert_true(
    report_field(report, "inputFile") is Text(value~) && value == paths[0],
  )
}

///|
async test "jsonl stream report: mid-read failure keeps only completed results" {
  let compiled = ref_compiled(
    "{\"properties\":{\"n\":{\"type\":\"integer\"},\"loop\":{\"$ref\":\"#/properties/loop\"}}}",
  )
  let options = cli_ok([
    "-v", "--jsonl", "--schema", "schema.json", "--schema-output=json",
  ])
  for
    (prefix, code, invalid, errors) in [
      (b"{}\n{\"n\":\"bad\"}\n", 1, 1, 0),
      (b"{\"loop\":1}\n{}\n", 2, 0, 1),
    ] {
    let (reader, probe) = jsonl_probe_input(
      [prefix, b"{\"n\":"],
      fail_after=Some(2),
    )
    let result = run_schema_jsonl_reader_report(
      options,
      "schema.json",
      compiled,
      Some("data.jsonl"),
      reader,
    )
    assert_eq(result.code, code)
    assert_eq(result.out, "")
    assert_eq(probe.reads, 3)
    assert_eq(probe.releases, 1)
    let report = report_json(result.err)
    assert_jsonl_summary(report, 2, 1, invalid, errors)
    assert_true(report_field(report, "status") is Text(value="error"))
    let issues = report_issues(report)
    assert_eq(issues.length(), 1)
    assert_true(report_field(issues[0], "stage") is Text(value="input"))
    assert_true(report_field(issues[0], "kind") is Text(value="ReadError"))
    assert_true(report_field(issues[0], "location") is Null)
    assert_true(
      report_field(issues[0], "message") is Text(value~) &&
      value.contains("injected JSONL read failure"),
    )
    let rows = batch_report_results(report)
    assert_true(report_field(rows[0], "line") is Number(raw="1"))
    assert_true(report_field(rows[1], "line") is Number(raw="2"))
    for row in rows {
      for issue in report_issues(row) {
        assert_false(report_field(issue, "kind") is Text(value="ParseError"))
      }
    }
    if code == 2 {
      assert_true(report_field(rows[0], "exitCode") is Number(raw="2"))
      assert_true(
        report_field(report_issues(rows[0])[0], "kind")
        is Text(value="ReferenceCycle"),
      )
      assert_true(report_field(rows[1], "status") is Text(value="valid"))
    }
  }
}

///|
async test "jsonl stream report: schema priority evaluation isolation and release" {
  let (unsupported, _) = batch_report_case(
    "stream_report_precheck",
    Some("{\"unevaluatedProperties\":false}"),
    [None],
    extra=["--jsonl"],
  )
  assert_eq(unsupported.code, 2)
  assert_eq(unsupported.out, "")
  let report = report_json(unsupported.err)
  assert_jsonl_summary(report, 0, 0, 0, 0)
  let issue = report_issues(report)[0]
  assert_true(report_field(issue, "stage") is Text(value="schema"))
  assert_true(report_field(issue, "kind") is Text(value="UnsupportedFeature"))
  assert_eq(report_issues(report).length(), 1)
  let (missing, _) = batch_report_case(
    "stream_report_missing",
    Some("true"),
    [None],
    extra=["--jsonl"],
  )
  assert_eq(missing.code, 1)
  assert_eq(missing.out, "")
  let report = report_json(missing.err)
  assert_jsonl_summary(report, 0, 0, 0, 0)
  assert_true(
    report_field(report_issues(report)[0], "kind") is Text(value="ReadError"),
  )
  let compiled = ref_compiled(
    "{\"properties\":{\"loop\":{\"$ref\":\"#/properties/loop\"}}}",
  )
  let options = cli_ok([
    "-v", "--jsonl", "--schema", "schema.json", "--schema-output=json",
  ])
  let (reader, probe) = jsonl_probe_input([
    b"{\"loop\":1}\n{}\n{\"loop\":2}\n{}",
  ])
  let result = run_schema_jsonl_reader_report(
    options,
    "schema.json",
    compiled,
    None,
    reader,
  )
  assert_eq(result.code, 2)
  assert_eq(result.out, "")
  assert_eq(probe.releases, 1)
  assert_eq(probe.reads, 2)
  let report = report_json(result.err)
  assert_jsonl_summary(report, 4, 2, 0, 2)
  assert_eq(report_issues(report).length(), 0)
  let rows = batch_report_results(report)
  for index in [0, 2] {
    let issue = report_issues(rows[index])[0]
    assert_true(report_field(issue, "kind") is Text(value="ReferenceCycle"))
    assert_true(report_field(issue, "instancePointer") is Text(value="/loop"))
    assert_true(
      report_field(issue, "schemaPointer")
      is Text(value="/properties/loop/$ref"),
    )
    assert_true(report_field(rows[index + 1], "status") is Text(value="valid"))
  }
}
