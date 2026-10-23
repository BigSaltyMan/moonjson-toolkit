///|
fn assert_jsonl_summary(
  report : @pjson.Json,
  records : Int,
  valid : Int,
  invalid : Int,
  errors : Int,
) -> Unit raise {
  assert_true(report_field(report, "reportVersion") is Number(raw="1"))
  assert_true(
    report_field(report, "reportType") is Text(value="jsonlValidation"),
  )
  let summary = report_field(report, "summary")
  for
    (field, expected) in [
      ("records", records),
      ("valid", valid),
      ("invalid", invalid),
      ("errors", errors),
    ] {
    assert_true(
      report_field(summary, field) is Number(raw~) &&
      raw == expected.to_string(),
    )
  }
  assert_eq(valid + invalid + errors, records)
  assert_eq(batch_report_results(report).length(), records)
}

///|
async test "schema jsonl report: parameter scope" {
  for extra in [[], ["-f", "data.jsonl"], ["--max-depth", "2", "--no-color"]] {
    let options = cli_ok(
      ["-v", "--schema", "schema.json", "--jsonl", "--schema-output=json"] +
      extra,
    )
    assert_true(validate_options(options) is Ok(_))
  }
  for
    extra in [
      ["--ai"],
      ["--stats"],
      ["--flatten"],
      ["--json-out", "unused.json"],
      ["--fail-fast"],
      ["--continue-on-error"],
      ["-f", "second.jsonl"],
    ] {
    let (result, _) = batch_report_case(
      "jsonl_conflict",
      None,
      [None],
      extra=["--jsonl"] + extra,
    )
    assert_eq(result.code, 2)
    assert_eq(result.out, "")
    assert_true(result.err.has_prefix("error: --schema-output json "))
    assert_false(result.err.contains("cannot read"))
  }
  let stdin = schema_jsonl_report("schema.json", input_label(None), [], [])
  assert_eq(stdin.code, 0)
  assert_true(
    report_field(report_json(stdin.out), "inputFile") is Text(value="<stdin>"),
  )
}

///|
async test "schema jsonl report: valid invalid false and empty inputs" {
  for
    (name, schema, text, code, status, valid, invalid) in [
      ("valid", "{\"type\":\"integer\"}", "1\n2\n", 0, "valid", 2, 0),
      ("invalid", "{\"type\":\"integer\"}", "1\n\"bad\"\n", 1, "invalid", 1, 1),
      ("false", "false", "null\n1", 1, "invalid", 0, 2),
      ("empty", "true", "", 0, "valid", 0, 0),
      ("whitespace", "false", " \r\n\t\n", 0, "valid", 0, 0),
    ] {
    let (result, paths) = batch_report_case(
      "jsonl_" + name,
      Some(schema),
      [Some(text)],
      extra=["--jsonl"],
    )
    assert_eq(result.code, code)
    let report = if code == 0 {
      assert_eq(result.err, "")
      report_json(result.out)
    } else {
      assert_eq(result.out, "")
      report_json(result.err)
    }
    assert_true(
      report_field(report, "status") is Text(value=actual) && actual == status,
    )
    assert_true(
      report_field(report, "inputFile") is Text(value=actual) &&
      actual == paths[0],
    )
    assert_true(
      report_field(report, "schemaFile") is Text(value=actual) &&
      actual == Scratch::named("schema_batch_jsonl_" + name).schema,
    )
    assert_jsonl_summary(report, valid + invalid, valid, invalid, 0)
    assert_eq(report_issues(report).length(), 0)
    for index, item in batch_report_results(report) {
      assert_true(
        report_field(item, "line") is Number(raw~) &&
        raw == (index + 1).to_string(),
      )
      if report_issues(item).is_empty() {
        assert_true(report_field(item, "status") is Text(value="valid"))
        assert_true(report_field(item, "exitCode") is Number(raw="0"))
      } else {
        assert_true(report_field(item, "status") is Text(value="invalid"))
        assert_true(report_field(item, "exitCode") is Number(raw="1"))
        let issue = report_issues(item)[0]
        assert_true(report_field(issue, "stage") is Text(value="input"))
        assert_true(
          report_field(issue, "kind") is Text(value="ValidationError"),
        )
        assert_true(report_field(issue, "location") is Text(value=""))
      }
    }
  }
}

///|
async test "schema jsonl report: read parse errors and actual lines" {
  let (missing, _) = batch_report_case("jsonl_missing", Some("true"), [None], extra=[
    "--jsonl",
  ])
  assert_eq(missing.code, 1)
  assert_eq(missing.out, "")
  let missing_report = report_json(missing.err)
  assert_jsonl_summary(missing_report, 0, 0, 0, 0)
  assert_true(report_field(missing_report, "status") is Text(value="error"))
  let issue = report_issues(missing_report)[0]
  assert_true(report_field(issue, "stage") is Text(value="input"))
  assert_true(report_field(issue, "kind") is Text(value="ReadError"))
  for
    (name, text, lines, extra) in [
      (
        "parse",
        "\r\n{\"name\":\"😀\"}\r\n \t\r\n{\r\nnull\r\n",
        [2, 4, 5],
        [],
      ),
      ("depth", "null\n \n[[0]]\nnull", [1, 3, 4], ["--max-depth", "0"]),
    ] {
    let (result, _) = batch_report_case(
      "jsonl_" + name,
      Some("true"),
      [Some(text)],
      extra=["--jsonl"] + extra,
    )
    assert_eq(result.code, 1)
    assert_eq(result.out, "")
    let report = report_json(result.err)
    assert_jsonl_summary(report, 3, 2, 0, 1)
    assert_true(report_field(report, "status") is Text(value="error"))
    assert_eq(report_issues(report).length(), 0)
    let results = batch_report_results(report)
    for index, item in results {
      assert_true(
        report_field(item, "line") is Number(raw~) &&
        raw == lines[index].to_string(),
      )
    }
    assert_true(report_field(results[1], "status") is Text(value="error"))
    assert_true(report_field(results[1], "exitCode") is Number(raw="1"))
    let issue = report_issues(results[1])[0]
    assert_true(report_field(issue, "stage") is Text(value="input"))
    assert_true(report_field(issue, "kind") is Text(value="ParseError"))
    assert_true(report_field(issue, "location") is Null)
    assert_true(
      report_field(issue, "message") is Text(value=message) &&
      message.has_prefix("line " + lines[1].to_string() + ", column "),
    )
    assert_true(report_field(results[2], "status") is Text(value="valid"))
  }
}

///|
async test "schema jsonl report: evaluation priority and record isolation" {
  let schema = "{\"properties\":{\"name\":{\"type\":\"string\"},\"loop\":{\"$ref\":\"#/properties/loop\"}}}"
  for
    (text, cycle_index) in [
      ("{\"name\":0}\n\n{\"loop\":1}\n{\"name\":\"ok\"}", 1),
      ("{\"loop\":1}\n\n{\"name\":0}\n{\"name\":\"ok\"}", 0),
    ] {
    let (result, _) = batch_report_case(
      "jsonl_cycle",
      Some(schema),
      [Some(text)],
      extra=["--jsonl"],
    )
    assert_eq(result.code, 2)
    assert_eq(result.out, "")
    let report = report_json(result.err)
    assert_jsonl_summary(report, 3, 1, 1, 1)
    assert_true(report_field(report, "status") is Text(value="error"))
    let results = batch_report_results(report)
    assert_true(
      report_field(results[cycle_index], "exitCode") is Number(raw="2"),
    )
    let issue = report_issues(results[cycle_index])[0]
    assert_true(report_field(issue, "stage") is Text(value="evaluation"))
    assert_true(report_field(issue, "kind") is Text(value="ReferenceCycle"))
    assert_true(report_field(issue, "location") is Null)
    assert_true(report_field(issue, "instancePointer") is Text(value="/loop"))
    assert_true(
      report_field(issue, "schemaPointer")
      is Text(value="/properties/loop/$ref"),
    )
    assert_true(report_field(results[2], "status") is Text(value="valid"))
    assert_true(report_field(results[2], "line") is Number(raw="4"))
  }
}

///|
async test "schema jsonl report: schema errors precede input and empty content" {
  for
    (schema, input, kind) in [
      (None, None, "ReadError"),
      (Some("{"), None, "ParseError"),
      (Some("{\"unevaluatedProperties\":false}"), None, "UnsupportedFeature"),
      (
        Some("{\"unevaluatedProperties\":false}"),
        Some(""),
        "UnsupportedFeature",
      ),
    ] {
    let (result, _) = batch_report_case("jsonl_schema_error", schema, [input], extra=[
      "--jsonl",
    ])
    assert_eq(result.code, 2)
    assert_eq(result.out, "")
    let report = report_json(result.err)
    assert_jsonl_summary(report, 0, 0, 0, 0)
    assert_true(report_field(report, "status") is Text(value="error"))
    assert_eq(report_issues(report).length(), 1)
    let issue = report_issues(report)[0]
    assert_true(report_field(issue, "stage") is Text(value="schema"))
    assert_true(
      report_field(issue, "kind") is Text(value=actual) && actual == kind,
    )
    if kind == "UnsupportedFeature" {
      assert_true(
        report_field(issue, "location") is Text(value="unevaluatedProperties"),
      )
    }
  }
}

///|
async test "schema jsonl report: escaping and text compatibility" {
  let name = "中文\"\\\n"
  let schema = @pjson.Object(members=[
    (
      "properties",
      @pjson.Object(members=[(name, report_json("{\"type\":\"integer\"}"))]),
    ),
  ])
  let bad = @pjson.Object(members=[(name, @pjson.Text(value="bad"))])
  let text = "{}\n\n" + format_compact(bad) + "\n{\n{}"
  let (result, _) = batch_report_case(
    "jsonl_中文",
    Some(format_compact(schema)),
    [Some(text)],
    extra=["--jsonl"],
  )
  assert_eq(result.code, 1)
  assert_eq(result.out, "")
  let report = report_json(result.err)
  assert_jsonl_summary(report, 4, 2, 1, 1)
  let issue = report_issues(batch_report_results(report)[1])[0]
  assert_true(
    report_field(issue, "location") is Text(value=actual) && actual == name,
  )
  assert_true(
    report_field(issue, "message") is Text(value=actual) &&
    actual == "it is a string where the schema expects an integer",
  )
  assert_false(result.err.contains("\u001b"))
  let path = "C:\\中文\\\"data\"\n.jsonl"
  let message = "bad \"value\"\\\nnext line"
  let escaped = schema_jsonl_report(
    path,
    path,
    [],
    [schema_report_issue("ReadError", None, message, stage="input")],
    code=1,
  )
  let escaped_report = report_json(escaped.err)
  assert_true(
    report_field(escaped_report, "schemaFile") is Text(value=actual) &&
    actual == path,
  )
  assert_true(
    report_field(escaped_report, "inputFile") is Text(value=actual) &&
    actual == path,
  )
  assert_true(
    report_field(report_issues(escaped_report)[0], "message")
    is Text(value=actual) &&
    actual == message,
  )
  let (plain, paths) = batch_report_case(
    "jsonl_text",
    Some(format_compact(schema)),
    [Some(text)],
    json=false,
    extra=["--jsonl"],
  )
  assert_eq(plain.code, 1)
  assert_eq(plain.out, "")
  assert_true(
    plain.err.contains(paths[0] + " line 3 does not match the schema"),
  )
  match parse_jsonl(text)[2] {
    Err(diagnostic) => assert_true(plain.err.contains(diagnostic.render()))
    Ok(_) => abort("expected the fourth source line to fail parsing")
  }
}
