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
) -> @pjson.Json {
  @pjson.Object(members=[
    ("kind", @pjson.Text(value=kind)),
    (
      "location",
      match location {
        Some(path) => @pjson.Text(value=path)
        None => @pjson.Null
      },
    ),
    ("message", @pjson.Text(value=message)),
  ])
}

///|
fn schema_read_failure_json(error : SchemaReadFailure) -> RunResult {
  let (path, issues) = match error {
    SchemaReadError(path, message) =>
      (path, [schema_report_issue("ReadError", None, message)])
    SchemaParseError(path, diagnostic) =>
      (
        path,
        [
          schema_report_issue(
            "ParseError",
            None,
            "line " +
            diagnostic.line.to_string() +
            ", column " +
            diagnostic.column.to_string() +
            ": " +
            diagnostic.message,
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
          schema_report_issue(kind, Some(problem.path), problem.message)
        }),
      )
  }
  failure(schema_check_json(path, issues), exit_usage_error)
}
