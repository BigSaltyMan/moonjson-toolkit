///|
let upstream_sha = "55719286c33ae0d1823bfb65fea10338a19bc37c"

///|
suberror RunnerError {
  RunnerError(String)
} derive(Debug)

///|
struct Policy {
  file : String
  group : Int
  description : String
  capability : String
  action : String
  reason : String
  expected_problems : Array[@pjson.Json]
}

///|
struct Record {
  file : String
  group : Int
  test_index : Int
  group_description : String
  description : String
  capability : String
  action : String
  expected_valid : Bool
  actual_valid : Bool?
  result : String
  reason : String
  diagnostics : Array[String]
} derive(ToJson)

///|
struct Counts {
  groups : Int
  tests : Int
  executed : Int
  passed : Int
  false_accept : Int
  false_reject : Int
  compile_rejected : Int
  execution_error : Int
  skipped : Int
} derive(ToJson)

///|
struct CapabilityCounts {
  capability : String
  counts : Counts
} derive(ToJson)

///|
struct SuiteReport {
  upstream_commit : String
  manifest_sha256 : String
  toolchain : String
  command : String
  counts : Counts
  capabilities : Array[CapabilityCounts]
  scope_errors : Array[String]
  runner_errors : Array[String]
  records : Array[Record]
} derive(ToJson)

///|
fn field(value : @pjson.Json, key : String) -> @pjson.Json raise RunnerError {
  match value {
    Object(members~) =>
      for (name, held) in members {
        if name == key {
          return held
        }
      }
    _ => ()
  }
  raise RunnerError("missing object field: " + key)
}

///|
fn string(value : @pjson.Json) -> String raise RunnerError {
  match value {
    Text(value~) => value
    _ => raise RunnerError("expected string")
  }
}

///|
fn array(value : @pjson.Json) -> Array[@pjson.Json] raise RunnerError {
  match value {
    Array(items~) => items
    _ => raise RunnerError("expected array")
  }
}

///|
fn boolean(value : @pjson.Json) -> Bool raise RunnerError {
  match value {
    Bool(value~) => value
    _ => raise RunnerError("expected boolean")
  }
}

///|
fn index(value : @pjson.Json) -> Int raise RunnerError {
  match value {
    Number(raw~) => {
      if raw == "" || !raw.to_array().all(fn(ch) { ch >= '0' && ch <= '9' }) {
        raise RunnerError("expected nonnegative integer index")
      }
      @string.parse_int(raw) catch {
        _ => raise RunnerError("index out of range")
      }
    }
    _ => raise RunnerError("expected index")
  }
}

///|
fn parse_json(text : String) -> @pjson.Json raise RunnerError {
  match @pjson.parse(text) {
    Ok(value) => value
    Err(_) => raise RunnerError("invalid JSON")
  }
}

///|
fn safe_file(path : String) -> Bool {
  path != "" &&
  !path.has_prefix("/") &&
  !path.contains("\\") &&
  !path.contains(":") &&
  !path.split("/").any(fn(part) { part == ".." || part == "" || part == "." })
}

///|
fn policies(value : @pjson.Json) -> Array[Policy] raise RunnerError {
  if index(field(value, "version")) != 1 ||
    string(field(value, "upstream_commit")) != upstream_sha {
    raise RunnerError("manifest version or upstream commit does not match")
  }
  array(field(value, "groups")).map(fn(item) raise RunnerError {
    let file = string(field(item, "file"))
    if !safe_file(file) ||
      !file.has_prefix("tests/draft2020-12/") ||
      !file.has_suffix(".json") {
      raise RunnerError("invalid manifest file path: " + file)
    }
    let action = string(field(item, "action"))
    if action != "validate" && action != "reject" && action != "skip" {
      raise RunnerError("unknown manifest action: " + action)
    }
    let reason = if action == "validate" {
      ""
    } else {
      string(field(item, "reason"))
    }
    if action != "validate" && reason == "" {
      raise RunnerError("exclusions require a concrete reason")
    }
    let expected_problems = if action == "reject" {
      array(field(item, "expected_problems"))
    } else {
      []
    }
    let mut unsupported = false
    for problem in expected_problems {
      let kind = string(field(problem, "kind"))
      if kind != "UnsupportedFeature" &&
        kind != "UnsupportedVersion" &&
        kind != "InvalidSchema" {
        raise RunnerError("unknown rejection category")
      }
      if kind != "InvalidSchema" {
        unsupported = true
      }
      string(field(problem, "path")) |> ignore
      if string(field(problem, "message_contains")) == "" {
        raise RunnerError("reject policy needs a diagnostic reason")
      }
    }
    if action == "reject" && !unsupported {
      raise RunnerError(
        "reject policy requires a declared unsupported capability",
      )
    }
    {
      file,
      group: index(field(item, "group")),
      description: string(field(item, "description")),
      capability: string(field(item, "capability")),
      action,
      reason,
      expected_problems,
    }
  })
}

///|
fn check_scope(
  files : Map[String, @pjson.Json],
  entries : Array[Policy],
) -> Array[String] raise RunnerError {
  let errors = []
  let seen : Map[(String, Int), Bool] = Map([])
  for policy in entries {
    let key = (policy.file, policy.group)
    if seen.contains(key) {
      errors.push(
        "duplicate manifest entry: " +
        policy.file +
        " group " +
        policy.group.to_string(),
      )
    }
    seen[key] = true
    match files.get(policy.file) {
      None => errors.push("manifest file does not exist: " + policy.file)
      Some(json) => {
        let groups = array(json)
        if policy.group >= groups.length() {
          errors.push("manifest group index out of range: " + policy.file)
        } else if string(field(groups[policy.group], "description")) !=
          policy.description {
          errors.push(
            "manifest description mismatch: " +
            policy.file +
            " group " +
            policy.group.to_string(),
          )
        }
      }
    }
  }
  for file, json in files {
    for i, _group in array(json) {
      if !seen.contains((file, i)) {
        errors.push(
          "missing manifest entry: " + file + " group " + i.to_string(),
        )
      }
    }
  }
  if !entries.any(fn(p) { p.action == "validate" }) {
    errors.push("empty validation scope")
  }
  errors.sort()
  errors
}

///|
fn rejection_matches(
  policy : Policy,
  problems : Array[@lib.SchemaProblem],
) -> Bool raise RunnerError {
  let mut matched = 0
  for expected in policy.expected_problems {
    let path = string(field(expected, "path"))
    let kind = string(field(expected, "kind"))
    let reason = string(field(expected, "message_contains"))
    if problems.any(fn(problem) {
        problem.path == path &&
        problem.message.contains(reason) &&
        kind ==
        (match problem.kind {
          @lib.InvalidSchema => "InvalidSchema"
          @lib.UnsupportedFeature => "UnsupportedFeature"
          @lib.UnsupportedVersion => "UnsupportedVersion"
        })
      }) {
      matched = matched + 1
    }
  }
  matched == policy.expected_problems.length() && matched == problems.length()
}

///|
fn completed_result(expected : Bool, actual : Bool) -> String {
  if expected == actual {
    "passed"
  } else if actual {
    "false_accept"
  } else {
    "false_reject"
  }
}

///|
/// Compilation failures never become actual_valid=false, including invalid tests.
fn run_group(
  group : @pjson.Json,
  policy : Policy,
  scope_errors : Array[String],
) -> Array[Record] raise RunnerError {
  let tests = array(field(group, "tests"))
  if tests.is_empty() {
    raise RunnerError("empty upstream test_index group")
  }
  let schema = field(group, "schema")
  let compiled = if policy.action == "skip" {
    None
  } else {
    Some(@lib.compile_schema(schema))
  }
  match compiled {
    Some(Err(problems)) =>
      if policy.action == "validate" {
        scope_errors.push(
          policy.file +
          " group " +
          policy.group.to_string() +
          ": validate schema was compile_rejected",
        )
      } else if !rejection_matches(policy, problems) {
        scope_errors.push(
          policy.file +
          " group " +
          policy.group.to_string() +
          ": rejection differs from manifest",
        )
      }
    Some(Ok(_)) =>
      if policy.action == "reject" {
        scope_errors.push(
          policy.file +
          " group " +
          policy.group.to_string() +
          ": reject schema unexpectedly compiled",
        )
      }
    None => ()
  }
  let records = []
  for i, test_index in tests {
    let data = field(test_index, "data")
    let expected_valid = boolean(field(test_index, "valid"))
    let (result, actual_valid, diagnostics) = match compiled {
      None => ("skipped", None, [])
      Some(Err(problems)) =>
        ("compile_rejected", None, problems.map(@lib.render_schema_problem))
      Some(Ok(schema)) =>
        match @lib.validate_compiled_schema(data, schema) {
          Err(error) =>
            (
              "execution_error",
              None,
              [
                (match error.kind {
                  @lib.ReferenceCycle => "ReferenceCycle"
                  @lib.ResourceLimit => "ResourceLimit"
                }) +
                ": " +
                error.message +
                "; instance=" +
                error.instance_path +
                "; schema=" +
                error.schema_path,
              ],
            )
          Ok(violations) => {
            let valid = violations.is_empty()
            (
              completed_result(expected_valid, valid),
              Some(valid),
              violations.map(@lib.render_schema_error),
            )
          }
        }
    }
    records.push({
      file: policy.file,
      group: policy.group,
      test_index: i,
      group_description: policy.description,
      description: string(field(test_index, "description")),
      capability: policy.capability,
      action: policy.action,
      expected_valid,
      actual_valid,
      result,
      reason: policy.reason,
      diagnostics,
    })
  }
  records
}

///|
fn count_records(records : Array[Record]) -> Counts {
  let groups : Map[(String, Int), Bool] = Map([])
  let statuses : Map[String, Int] = Map([])
  let mut executed = 0
  for record in records {
    groups[(record.file, record.group)] = true
    statuses[record.result] = statuses.get(record.result).unwrap_or(0) + 1
    if record.actual_valid != None || record.result == "execution_error" {
      executed = executed + 1
    }
  }
  {
    groups: groups.length(),
    tests: records.length(),
    executed,
    passed: statuses.get("passed").unwrap_or(0),
    false_accept: statuses.get("false_accept").unwrap_or(0),
    false_reject: statuses.get("false_reject").unwrap_or(0),
    compile_rejected: statuses.get("compile_rejected").unwrap_or(0),
    execution_error: statuses.get("execution_error").unwrap_or(0),
    skipped: statuses.get("skipped").unwrap_or(0),
  }
}

///|
fn report_code(report : SuiteReport) -> Int {
  if !report.runner_errors.is_empty() {
    2
  } else if !report.scope_errors.is_empty() ||
    report.counts.executed == 0 ||
    report.counts.false_accept > 0 ||
    report.counts.false_reject > 0 ||
    report.counts.execution_error > 0 {
    1
  } else {
    0
  }
}

///|
fn RunnerError::to_string(self : RunnerError) -> String {
  match self {
    RunnerError(reason) => reason
  }
}
