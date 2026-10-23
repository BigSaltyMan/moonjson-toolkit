///|
/// Versioned CLI report. Locations use SchemaProblem.path's display syntax,
/// not JSON Pointer; non-schema failures have no schema location.
fn schema_check_json(path : String, issues : Array[@pjson.Json]) -> String {
  format_compact(
    @pjson.Object(members=[
      ("reportVersion", @pjson.Number(raw="1")),
      ("schemaFile", @pjson.Text(value=path)),
      (
        "status",
        @pjson.Text(value=if issues.is_empty() { "supported" } else { "error" }),
      ),
      ("issues", @pjson.Array(items=issues)),
    ]),
  )
}

///|
fn schema_report_issue(
  kind : String,
  location : String?,
  message : String,
  stage? : String = "",
) -> @pjson.Json {
  let members = [
    ("kind", @pjson.Text(value=kind)),
    (
      "location",
      match location {
        Some(path) => @pjson.Text(value=path)
        None => @pjson.Null
      },
    ),
    ("message", @pjson.Text(value=message)),
  ]
  @pjson.Object(
    members=if stage == "" {
      members
    } else {
      [("stage", @pjson.Text(value=stage))] + members
    },
  )
}

///|
fn schema_parse_message(diagnostic : JsonDiagnostic) -> String {
  "line " +
  diagnostic.line.to_string() +
  ", column " +
  diagnostic.column.to_string() +
  ": " +
  diagnostic.message
}

///|
fn schema_read_issues(
  error : SchemaReadFailure,
  stage? : String = "",
) -> (String, Array[@pjson.Json]) {
  match error {
    SchemaReadError(path, message) =>
      (path, [schema_report_issue("ReadError", None, message, stage~)])
    SchemaParseError(path, diagnostic) =>
      (
        path,
        [
          schema_report_issue(
            "ParseError",
            None,
            schema_parse_message(diagnostic),
            stage~,
          ),
        ],
      )
    SchemaCompileError(path, problems) =>
      (
        path,
        problems.map(fn(problem) {
          let kind = match problem.kind {
            InvalidSchema => "InvalidSchema"
            UnsupportedFeature => "UnsupportedFeature"
            UnsupportedVersion => "UnsupportedVersion"
          }
          schema_report_issue(kind, Some(problem.path), problem.message, stage~)
        }),
      )
  }
}

///|
fn schema_read_failure_json(error : SchemaReadFailure) -> RunResult {
  let (path, issues) = schema_read_issues(error)
  failure(schema_check_json(path, issues), exit_usage_error)
}

///|
fn schema_validation_report(
  schema_path : String,
  source : String,
  status : String,
  issues : Array[@pjson.Json],
  code : Int,
) -> RunResult {
  let text = format_compact(
    @pjson.Object(members=[
      ("reportVersion", @pjson.Number(raw="1")),
      ("reportType", @pjson.Text(value="validation")),
      ("schemaFile", @pjson.Text(value=schema_path)),
      ("inputFile", @pjson.Text(value=source)),
      ("status", @pjson.Text(value=status)),
      ("issues", @pjson.Array(items=issues)),
    ]),
  )
  if code == exit_success {
    { out: text + "\n", err: "", code, }
  } else {
    failure(text, code)
  }
}

///|
fn schema_evaluation_issue(error : SchemaEvaluationError) -> @pjson.Json {
  let kind = match error.kind {
    ReferenceCycle => "ReferenceCycle"
    ResourceLimit => "ResourceLimit"
  }
  @pjson.Object(members=[
    ("stage", @pjson.Text(value="evaluation")),
    ("kind", @pjson.Text(value=kind)),
    ("location", @pjson.Null),
    ("message", @pjson.Text(value=error.message)),
    ("instancePointer", @pjson.Text(value=error.instance_path)),
    ("schemaPointer", @pjson.Text(value=error.schema_path)),
  ])
}

///|
/// Build the entire batch before choosing a stream. Schema-level failures
/// have no input outcomes; all other issues belong to their input result.
fn schema_batch_report(
  schema_path : String,
  requested : Int,
  results : Array[SchemaInputResult],
  issues : Array[@pjson.Json],
) -> RunResult {
  let mut valid = 0
  let mut invalid = 0
  let mut errors = 0
  let mut code = if issues.is_empty() { exit_success } else { exit_usage_error }
  for result in results {
    match result.status {
      "valid" => valid += 1
      "invalid" => invalid += 1
      _ => errors += 1
    }
    if result.code > code {
      code = result.code
    }
  }
  let status = if !issues.is_empty() || errors > 0 {
    "error"
  } else if invalid > 0 {
    "invalid"
  } else {
    "valid"
  }
  let text = format_compact(
    @pjson.Object(members=[
      ("reportVersion", @pjson.Number(raw="1")),
      ("reportType", @pjson.Text(value="batchValidation")),
      ("schemaFile", @pjson.Text(value=schema_path)),
      ("status", @pjson.Text(value=status)),
      (
        "summary",
        @pjson.Object(members=[
          ("requested", @pjson.Number(raw=requested.to_string())),
          ("processed", @pjson.Number(raw=results.length().to_string())),
          ("valid", @pjson.Number(raw=valid.to_string())),
          ("invalid", @pjson.Number(raw=invalid.to_string())),
          ("errors", @pjson.Number(raw=errors.to_string())),
        ]),
      ),
      ("issues", @pjson.Array(items=issues)),
      (
        "results",
        @pjson.Array(
          items=results.map(fn(result) {
            @pjson.Object(members=[
              ("inputFile", @pjson.Text(value=result.source)),
              ("status", @pjson.Text(value=result.status)),
              ("exitCode", @pjson.Number(raw=result.code.to_string())),
              ("issues", @pjson.Array(items=result.issues)),
            ])
          }),
        ),
      ),
    ]),
  )
  if code == exit_success {
    { out: text + "\n", err: "", code, }
  } else {
    failure(text, code)
  }
}
