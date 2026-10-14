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
  priv patterns : Map[String, Pattern]
}

///|
pub fn compile_schema(
  schema : @pjson.Json,
) -> Result[CompiledSchema, Array[SchemaProblem]] {
  let snapshot = copy_schema_json(schema)
  let cache : Map[String, Result[Pattern, PatternProblem]] = Map([])
  let problems = precheck_schema(snapshot, cache)
  if problems.is_empty() {
    let patterns : Map[String, Pattern] = Map([])
    for text, result in cache {
      match result {
        Ok(pattern) => patterns[text] = pattern
        Err(_) => abort("schema precheck lost a pattern compilation problem")
      }
    }
    Ok({ schema: snapshot, patterns, })
  } else {
    Err(problems)
  }
}

///|
fn precheck_schema(
  schema : @pjson.Json,
  cache : Map[String, Result[Pattern, PatternProblem]],
) -> Array[SchemaProblem] {
  let problems = []
  check_schema(schema, "", problems, cache)
  problems
}

///|
/// Cache errors too so duplicate patterns are parsed once while every schema
/// location still receives its own diagnostic.
fn cache_schema_pattern(
  text : String,
  path : String,
  problems : Array[SchemaProblem],
  cache : Map[String, Result[Pattern, PatternProblem]],
) -> Unit {
  let result = match cache.get(text) {
    Some(result) => result
    None => {
      let result = read_pattern(text)
      cache[text] = result
      result
    }
  }
  match result {
    Ok(_) => ()
    Err(problem) =>
      problems.push({
        path,
        kind: problem.kind(),
        message: "\"" +
        escape_json_string(text) +
        "\" is not a pattern this tool reads: " +
        problem.message(),
      })
  }
}

///|
fn compiled_schema_pattern(
  patterns : Map[String, Pattern],
  text : String,
) -> Pattern {
  match patterns.get(text) {
    Some(pattern) => pattern
    None => abort("missing compiled schema pattern: " + text)
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
