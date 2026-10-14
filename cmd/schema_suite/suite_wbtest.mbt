///|
fn fixture_policy(action : String) -> Policy {
  {
    file: "tests/draft2020-12/fixture.json",
    group: 0,
    description: "fixture",
    capability: "fixture",
    action,
    reason: if action == "validate" {
      ""
    } else {
      "unknown keyword unsupported"
    },
    expected_problems: if action == "reject" {
      [
        parse_json(
          "{\"path\":\"unknown\",\"kind\":\"UnsupportedFeature\",\"message_contains\":\"keyword is not supported\"}",
        ) catch {
          _ => abort("bad fixture")
        },
      ]
    } else {
      []
    },
  }
}

///|
fn fixture_group(
  schema : String,
  valid : Bool,
) -> @pjson.Json raise RunnerError {
  parse_json(
    "{\"description\":\"fixture\",\"schema\":" +
    schema +
    ",\"tests\":[{\"description\":\"input\",\"data\":1,\"valid\":" +
    valid.to_string() +
    "}]}",
  )
}

///|
fn fixture_report(
  records : Array[Record],
  scope_errors : Array[String],
  runner_errors : Array[String],
) -> SuiteReport {
  {
    upstream_commit: upstream_sha,
    manifest_sha256: "fixture",
    toolchain: "fixture",
    command: "fixture",
    counts: count_records(records),
    capabilities: [],
    scope_errors,
    runner_errors,
    records,
  }
}

///|
test "false accepts and false rejects are distinct from completed passes" {
  let scope = []
  let accept = run_group(
    fixture_group("true", false),
    fixture_policy("validate"),
    scope,
  )
  let reject = run_group(
    fixture_group("false", true),
    fixture_policy("validate"),
    scope,
  )
  let pass = run_group(
    fixture_group("true", true),
    fixture_policy("validate"),
    scope,
  )
  assert_eq(accept[0].result, "false_accept")
  assert_eq(reject[0].result, "false_reject")
  assert_eq(pass[0].result, "passed")
  let report = fixture_report(accept + reject + pass, scope, [])
  assert_eq(report.counts.tests, 3)
  assert_eq(report.counts.groups, 1)
  assert_eq(report.counts.executed, 3)
  assert_eq(report.counts.passed, 1)
  assert_eq(report.counts.false_accept, 1)
  assert_eq(report.counts.false_reject, 1)
  assert_eq(report_code(report), 1)
}

///|
test "compile rejection cannot satisfy an upstream invalid test" {
  let scope = []
  let rows = run_group(
    fixture_group("{\"unknown\":true}", false),
    fixture_policy("validate"),
    scope,
  )
  assert_eq(rows[0].result, "compile_rejected")
  assert_eq(rows[0].actual_valid, None)
  let report = fixture_report(rows, scope, [])
  assert_eq(report.counts.passed, 0)
  assert_eq(report.counts.executed, 0)
  assert_eq(report.counts.compile_rejected, 1)
  assert_eq(report.scope_errors.length(), 1)
  assert_eq(report_code(report), 1)
}

///|
test "execution failures in not and successful anyOf cannot be passes or mismatches" {
  for
    schema in [
      "{\"$ref\":\"#\"}", "{\"not\":{\"$ref\":\"#\"}}", "{\"anyOf\":[true,{\"$ref\":\"#\"}]}",
    ] {
    let rows = run_group(
      fixture_group(schema, false),
      fixture_policy("validate"),
      [],
    )
    assert_eq(rows[0].result, "execution_error")
    assert_eq(rows[0].actual_valid, None)
    assert_true(rows[0].diagnostics[0].contains("ReferenceCycle"))
    let report = fixture_report(rows, [], [])
    assert_eq(report.counts.execution_error, 1)
    assert_eq(report.counts.false_reject + report.counts.passed, 0)
    assert_eq(report_code(report), 1)
  }
}

///|
test "rejection policy success is not standard success and unexpected acceptance fails scope" {
  let pass = run_group(
    fixture_group("true", true),
    fixture_policy("validate"),
    [],
  )
  let scope = []
  let rejected = run_group(
    fixture_group("{\"unknown\":true}", false),
    fixture_policy("reject"),
    scope,
  )
  assert_eq(scope.length(), 0)
  let report = fixture_report(pass + rejected, scope, [])
  assert_eq(report.counts.passed, 1)
  assert_eq(report.counts.compile_rejected, 1)
  assert_eq(report_code(report), 0)
  let unexpected = []
  let rows = run_group(
    fixture_group("true", true),
    fixture_policy("reject"),
    unexpected,
  )
  assert_eq(unexpected.length(), 1)
  assert_true(unexpected[0].contains("unexpectedly compiled"))
  assert_eq(report_code(fixture_report(pass + rows, unexpected, [])), 1)
  let wrong = []
  let rows = run_group(
    fixture_group("{\"unevaluatedItems\":true}", false),
    fixture_policy("reject"),
    wrong,
  )
  assert_eq(wrong.length(), 1)
  assert_eq(report_code(fixture_report(pass + rows, wrong, [])), 1)
  let extra = []
  run_group(
    fixture_group("{\"unknown\":true,\"type\":123}", false),
    fixture_policy("reject"),
    extra,
  )
  |> ignore
  assert_eq(extra.length(), 1)
}

///|
test "manifest holes duplicates missing files and description drift are errors" {
  let group = fixture_group("true", true)
  let policy = fixture_policy("validate")
  let files : Map[String, @pjson.Json] = Map([
    (policy.file, Array(items=[group])),
  ])
  assert_eq(check_scope(files, [policy]).length(), 0)
  assert_true(check_scope(files, []).contains("empty validation scope"))
  assert_true(check_scope(files, [policy, policy])[0].contains("duplicate"))
  assert_true(check_scope(Map([]), [policy])[0].contains("does not exist"))
  let changed : Policy = { ..policy, description: "other", }
  assert_true(check_scope(files, [changed])[0].contains("description mismatch"))
  files["tests/draft2020-12/new.json"] = Array(items=[group])
  assert_true(
    check_scope(files, [policy])[0].contains("missing manifest entry"),
  )
}

///|
test "precise upstream numbers survive parsing and execution without rounding" {
  let values = array(parse_json("[9007199254740992,9007199254740993,1e-400]"))
  assert_true(values[0] is Number(raw="9007199254740992"))
  assert_true(values[1] is Number(raw="9007199254740993"))
  assert_true(values[2] is Number(raw="1e-400"))
  let group = parse_json(
    "{\"description\":\"fixture\",\"schema\":{\"enum\":[9007199254740992,0]},\"tests\":[{\"description\":\"adjacent\",\"data\":9007199254740993,\"valid\":false},{\"description\":\"tiny\",\"data\":1e-400,\"valid\":false}]}",
  )
  let rows = run_group(group, fixture_policy("validate"), [])
  assert_true(
    rows.all(fn(row) {
      row.result == "passed" && row.actual_valid == Some(false)
    }),
  )
}

///|
test "empty scope and runner errors never produce a successful acceptance message" {
  let empty = fixture_report([], [], [])
  assert_eq(report_code(empty), 1)
  assert_false(markdown(empty).contains("All declared validation cases agree"))
  let rows = run_group(
    fixture_group("true", true),
    fixture_policy("validate"),
    [],
  )
  let broken = fixture_report(rows, [], ["cannot read file"])
  assert_eq(report_code(broken), 2)
  assert_false(markdown(broken).contains("All declared validation cases agree"))
  assert_true(
    try {
      parse_json("{") |> ignore
      false
    } catch {
      _ => true
    },
  )
}

///|
test "repeated execution counts ordering and hashes are stable" {
  let group = fixture_group("true", true)
  let first = run_group(group, fixture_policy("validate"), [])
  let second = run_group(group, fixture_policy("validate"), [])
  assert_eq(@json.to_json(first).stringify(), @json.to_json(second).stringify())
  assert_eq(
    @json.to_json(count_records(first)).stringify(),
    @json.to_json(count_records(second)).stringify(),
  )
  assert_eq(
    digest(@utf8.encode("abc")),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
async test "missing and corrupt manifest files fail the runner and write failure reports" {
  let directory = @fs.tmpdir(prefix="schema-suite-test-")
  let missing = directory + "/missing.json"
  let output_json = directory + "/report.json"
  let output_md = directory + "/report.md"
  assert_eq(
    run_suite([
      "--manifest", missing, "--report-json", output_json, "--report-md", output_md,
      "--strict",
    ]),
    2,
  )
  assert_false(
    @fs.read_file(output_md)
    .text()
    .contains("All declared validation cases agree"),
  )
  @fs.write_file(missing, "{")
  assert_eq(
    run_suite([
      "--manifest", missing, "--report-json", output_json, "--report-md", output_md,
      "--strict",
    ]),
    2,
  )
  assert_false(
    @fs.read_file(output_md)
    .text()
    .contains("All declared validation cases agree"),
  )
  @fs.write_file(
    missing,
    "{\"version\":1,\"upstream_commit\":\"" + upstream_sha + "\",\"groups\":[]}",
  )
  assert_eq(
    run_suite([
      "--manifest", missing, "--report-json", output_json, "--report-md", output_md,
      "--strict",
    ]),
    2,
  )
  assert_false(
    @fs.read_file(output_md)
    .text()
    .contains("All declared validation cases agree"),
  )
}
