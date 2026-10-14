///|
pub(all) enum SchemaProblemKind {
  InvalidSchema
  UnsupportedFeature
  UnsupportedVersion
} derive(Eq, Debug)

///|
/// A problem at a path in the schema, rather than in the business input.
pub(all) struct SchemaProblem {
  path : String
  message : String
  kind : SchemaProblemKind
} derive(Eq, Debug)

///|
/// A checked schema with a private snapshot. Callers cannot construct or
/// change it; mutable arrays in the original JSON are copied at compilation.
pub struct CompiledSchema {
  priv schema : @pjson.Json
}

///|
pub fn compile_schema(
  schema : @pjson.Json,
) -> Result[CompiledSchema, Array[SchemaProblem]] {
  let snapshot = copy_schema_json(schema)
  let problems = schema_problems(snapshot)
  if problems.is_empty() {
    Ok({ schema: snapshot, })
  } else {
    Err(problems)
  }
}

///|
fn copy_schema_json(json : @pjson.Json) -> @pjson.Json {
  match json {
    Object(members~) =>
      Object(
        members=members.map(fn(entry) { (entry.0, copy_schema_json(entry.1)) }),
      )
    Array(items~) => Array(items=items.map(copy_schema_json))
    _ => json
  }
}

///|
pub fn render_schema_problem(problem : SchemaProblem) -> String {
  (if problem.path == "" { "(root)" } else { problem.path }) +
  ": " +
  problem.message
}
