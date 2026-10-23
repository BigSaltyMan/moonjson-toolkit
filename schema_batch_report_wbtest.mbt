///|
/// Write only the inputs this case needs, preserving missing-file cases.
async fn batch_report_case(
  name : String,
  schema : String?,
  texts : Array[String?],
  order? : Array[Int] = [],
  json? : Bool = true,
  extra? : Array[String] = [],
) -> (RunResult, Array[String]) {
  let scratch = Scratch::named("schema_batch_" + name)
  discard(scratch.schema)
  match schema {
    Some(text) => @fs.write_file(scratch.schema, text)
    None => ()
  }
  let paths = []
  for index, text in texts {
    let path = Scratch::named("schema_batch_" + name + index.to_string()).input
    paths.push(path)
    discard(path)
    match text {
      Some(text) => @fs.write_file(path, text)
      None => ()
    }
  }
  let selected = if order.is_empty() {
    paths
  } else {
    order.map(fn(index) { paths[index] })
  }
  let args = ["-v", "--schema", scratch.schema, "--no-color"]
  for path in selected {
    args.push("-f")
    args.push(path)
  }
  if json {
    args.push("--schema-output=json")
  }
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let result = run(args + extra, analyze=analyzer.analyzer())
  for path in paths {
    discard(path)
  }
  discard(scratch.schema)
  assert_eq(analyzer.calls, 0)
  (result, selected)
}

///|
fn batch_report_results(report : @pjson.Json) -> Array[@pjson.Json] {
  match report_field(report, "results") {
    Array(items~) => items
    _ => abort("expected a results array")
  }
}

///|
fn assert_batch_summary(
  report : @pjson.Json,
  requested : Int,
  processed : Int,
  valid : Int,
  invalid : Int,
  errors : Int,
) -> Unit raise {
  assert_true(report_field(report, "reportVersion") is Number(raw="1"))
  assert_true(
    report_field(report, "reportType") is Text(value="batchValidation"),
  )
  let summary = report_field(report, "summary")
  for
    (field, expected) in [
      ("requested", requested),
      ("processed", processed),
      ("valid", valid),
      ("invalid", invalid),
      ("errors", errors),
    ] {
    assert_true(
      report_field(summary, field) is Number(raw~) &&
      raw == expected.to_string(),
    )
  }
  assert_eq(valid + invalid + errors, processed)
  assert_eq(batch_report_results(report).length(), processed)
}

///|
async test "schema batch report: parameter scope" {
  let options = cli_ok([
    "-v", "--schema", "schema.json", "-f", "one.json", "-f", "two.json", "--schema-output=json",
    "--max-depth", "10", "--no-color",
  ])
  assert_true(validate_options(options) is Ok(_))
  for
    extra in [
      ["--jsonl"],
      ["--ai"],
      ["--stats"],
      ["--flatten"],
      ["--json-out", "unused.json"],
      ["--fail-fast"],
      ["--continue-on-error"],
    ] {
    let (result, _) = batch_report_case("conflict", None, [None, None], extra~)
    assert_eq(result.code, 2)
    assert_eq(result.out, "")
    assert_true(
      result.err.has_prefix(
        "error: --schema-output json cannot be combined with ",
      ),
    )
    assert_false(result.err.contains("cannot read"))
  }
}

///|
async test "schema batch report: valid and invalid files" {
  for
    (name, second, code, status, valid, invalid) in [
      ("valid", "2", 0, "valid", 2, 0),
      ("invalid", "\"bad\"", 1, "invalid", 1, 1),
    ] {
    let (result, paths) = batch_report_case(
      name,
      Some("{\"type\":\"integer\"}"),
      [Some("1"), Some(second)],
    )
    assert_eq(result.code, code)
    let report = if code == 0 {
      assert_eq(result.err, "")
      report_json(result.out)
    } else {
      assert_eq(result.out, "")
      report_json(result.err)
    }
    assert_batch_summary(report, 2, 2, valid, invalid, 0)
    assert_true(
      report_field(report, "status") is Text(value=actual) && actual == status,
    )
    assert_eq(report_issues(report).length(), 0)
    let results = batch_report_results(report)
    for index, item in results {
      assert_true(
        report_field(item, "inputFile") is Text(value=path) &&
        path == paths[index],
      )
    }
    assert_true(report_field(results[0], "status") is Text(value="valid"))
    assert_true(report_field(results[0], "exitCode") is Number(raw="0"))
    assert_eq(report_issues(results[0]).length(), 0)
    if code == 1 {
      assert_true(report_field(results[1], "status") is Text(value="invalid"))
      assert_true(report_field(results[1], "exitCode") is Number(raw="1"))
      let issue = report_issues(results[1])[0]
      assert_true(report_field(issue, "stage") is Text(value="input"))
      assert_true(report_field(issue, "kind") is Text(value="ValidationError"))
      assert_true(report_field(issue, "location") is Text(value=""))
    }
  }
}

///|
async test "schema batch report: input errors do not stop later files" {
  let (result, _) = batch_report_case("input_errors", Some("true"), [
    None,
    Some("{"),
    Some("null"),
  ])
  assert_eq(result.code, 1)
  assert_eq(result.out, "")
  let report = report_json(result.err)
  assert_true(report_field(report, "status") is Text(value="error"))
  assert_batch_summary(report, 3, 3, 1, 0, 2)
  assert_eq(report_issues(report).length(), 0)
  let results = batch_report_results(report)
  for index, kind in ["ReadError", "ParseError"] {
    assert_true(report_field(results[index], "status") is Text(value="error"))
    assert_true(report_field(results[index], "exitCode") is Number(raw="1"))
    let issue = report_issues(results[index])[0]
    assert_true(report_field(issue, "stage") is Text(value="input"))
    assert_true(
      report_field(issue, "kind") is Text(value=actual) && actual == kind,
    )
    assert_true(report_field(issue, "location") is Null)
  }
  assert_true(report_field(results[2], "status") is Text(value="valid"))
}

///|
async test "schema batch report: evaluation error priority and isolation" {
  let schema = "{\"properties\":{\"name\":{\"type\":\"string\"},\"loop\":{\"$ref\":\"#/properties/loop\"}}}"
  for order in [[0, 1, 2], [1, 0, 2]] {
    let (result, _) = batch_report_case(
      "evaluation",
      Some(schema),
      [Some("{\"name\":0}"), Some("{\"loop\":1}"), Some("{\"name\":\"ok\"}")],
      order~,
    )
    assert_eq(result.code, 2)
    assert_eq(result.out, "")
    let report = report_json(result.err)
    assert_true(report_field(report, "status") is Text(value="error"))
    assert_batch_summary(report, 3, 3, 1, 1, 1)
    let results = batch_report_results(report)
    let cycle_index = if order[0] == 1 { 0 } else { 1 }
    assert_true(
      report_field(results[cycle_index], "exitCode") is Number(raw="2"),
    )
    let issue = report_issues(results[cycle_index])[0]
    assert_true(report_field(issue, "stage") is Text(value="evaluation"))
    assert_true(report_field(issue, "kind") is Text(value="ReferenceCycle"))
    assert_true(report_field(issue, "instancePointer") is Text(value="/loop"))
    assert_true(
      report_field(issue, "schemaPointer")
      is Text(value="/properties/loop/$ref"),
    )
    assert_true(report_field(results[2], "status") is Text(value="valid"))
  }
}

///|
async test "schema batch report: schema errors precede all inputs" {
  for
    (schema, kind) in [
      (None, "ReadError"),
      (Some("{"), "ParseError"),
      (Some("{\"unevaluatedProperties\":false}"), "UnsupportedFeature"),
    ] {
    let (result, _) = batch_report_case("schema_error", schema, [None, None])
    assert_eq(result.code, 2)
    assert_eq(result.out, "")
    let report = report_json(result.err)
    assert_true(report_field(report, "status") is Text(value="error"))
    assert_batch_summary(report, 2, 0, 0, 0, 0)
    let issues = report_issues(report)
    assert_eq(issues.length(), 1)
    assert_true(report_field(issues[0], "stage") is Text(value="schema"))
    assert_true(
      report_field(issues[0], "kind") is Text(value=actual) && actual == kind,
    )
    if kind == "UnsupportedFeature" {
      assert_true(
        report_field(issues[0], "location")
        is Text(value="unevaluatedProperties"),
      )
    }
  }
}

///|
async test "schema batch report: order escaping and existing formats" {
  let name = "中文\"\\\n"
  let schema = @pjson.Object(members=[
    (
      "properties",
      @pjson.Object(members=[(name, report_json("{\"type\":\"integer\"}"))]),
    ),
  ])
  let bad = @pjson.Object(members=[(name, @pjson.Text(value="bad"))])
  let (result, paths) = batch_report_case(
    "顺序",
    Some(format_compact(schema)),
    [Some("{}"), Some(format_compact(bad))],
    order=[1, 0, 1],
  )
  assert_eq(result.code, 1)
  assert_eq(result.out, "")
  let report = report_json(result.err)
  assert_batch_summary(report, 3, 3, 1, 2, 0)
  let results = batch_report_results(report)
  for index, item in results {
    assert_true(
      report_field(item, "inputFile") is Text(value=path) &&
      path == paths[index],
    )
  }
  let issue = report_issues(results[0])[0]
  assert_true(
    report_field(issue, "location") is Text(value=actual) && actual == name,
  )
  assert_eq(report_issues(results[2]).length(), 1)
  let repeated = report_issues(results[2])[0]
  assert_true(
    report_field(repeated, "location") is Text(value=actual) && actual == name,
  )
  assert_true(
    report_field(repeated, "message") is Text(value=actual) &&
    actual == "it is a string where the schema expects an integer",
  )
  assert_false(result.err.contains("\u001b"))
  let escaped_path = "C:\\中文\\\"data\"\n.json"
  let message = "bad \"value\"\\\nnext line"
  let escaped = schema_batch_report(
    escaped_path,
    2,
    [
      {
        source: escaped_path,
        status: "error",
        code: 1,
        issues: [schema_report_issue("ReadError", None, message, stage="input")],
      },
    ],
    [],
  )
  let escaped_report = report_json(escaped.err)
  assert_true(
    report_field(escaped_report, "schemaFile") is Text(value=actual) &&
    actual == escaped_path,
  )
  let escaped_item = batch_report_results(escaped_report)[0]
  assert_true(
    report_field(escaped_item, "inputFile") is Text(value=actual) &&
    actual == escaped_path,
  )
  assert_true(
    report_field(report_issues(escaped_item)[0], "message")
    is Text(value=actual) &&
    actual == message,
  )
  let (single, _) = batch_report_case("single", Some("true"), [Some("null")])
  assert_eq(single.code, 0)
  assert_eq(single.err, "")
  assert_true(
    report_field(report_json(single.out), "reportType")
    is Text(value="validation"),
  )
  let (text, text_paths) = batch_report_case(
    "text",
    Some("{\"type\":\"integer\"}"),
    [Some("1"), Some("\"bad\"")],
    json=false,
  )
  assert_eq(text.code, 1)
  assert_true(text.out.contains("==> " + text_paths[0] + " <=="))
  assert_true(text.out.contains("matches the schema"))
  assert_true(text.err.contains(text_paths[1] + " does not match the schema"))
}
