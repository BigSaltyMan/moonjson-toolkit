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
  priv patterns : Map[String, Pattern]
  priv nodes : Array[SchemaNode]
  priv node_ids : Map[String, Int]
  priv references : Map[String, Int]
}

///|
priv struct SchemaNode {
  id : Int
  pointer : String
  display : String
  schema : @pjson.Json
}

///|
priv struct SchemaCompileContext {
  root : @pjson.Json
  nodes : Array[SchemaNode]
  node_ids : Map[String, Int]
  references : Map[String, Int]
  mut pointer : String
}

///|
fn enqueue_schema(
  ctx : SchemaCompileContext,
  schema : @pjson.Json,
  pointer : String,
  display : String,
) -> Int {
  match ctx.node_ids.get(pointer) {
    Some(id) => id
    None => {
      let id = ctx.nodes.length()
      ctx.node_ids[pointer] = id
      ctx.nodes.push({ id, pointer, display, schema, })
      id
    }
  }
}

///|
fn enqueue_schema_child(
  ctx : SchemaCompileContext,
  schema : @pjson.Json,
  tokens : Array[String],
  display : String,
) -> Unit {
  let mut pointer = ctx.pointer
  for token in tokens {
    pointer = pointer_child(pointer, token)
  }
  enqueue_schema(ctx, schema, pointer, display) |> ignore
}

///|
/// Scan iteratively before copying; ordinary data also counts toward these
/// limits so annotations cannot exhaust the copying stack before precheck.
fn schema_snapshot_problem(root : @pjson.Json) -> SchemaProblem? {
  schema_snapshot_problem_with_limits(
    root, schema_compile_depth_limit, schema_compile_node_limit,
  )
}

///|
fn schema_snapshot_problem_with_limits(
  root : @pjson.Json,
  depth_limit : Int,
  node_limit : Int,
) -> SchemaProblem? {
  let stack = [(root, 0, "")]
  let mut count = 0
  while !stack.is_empty() {
    let (value, depth, pointer) = stack.pop().unwrap()
    count = count + 1
    if depth > depth_limit || count > node_limit {
      return Some({
        path: pointer,
        kind: UnsupportedFeature,
        message: "schema snapshot exceeds the depth limit of " +
        depth_limit.to_string() +
        " or node limit of " +
        node_limit.to_string(),
      })
    }
    let children = match value {
      Object(members~) => members.length()
      Array(items~) => items.length()
      _ => 0
    }
    if children > node_limit - count - stack.length() {
      return Some({
        path: pointer,
        kind: UnsupportedFeature,
        message: "schema snapshot exceeds the node limit of " +
        node_limit.to_string(),
      })
    }
    match value {
      Object(members~) =>
        for (name, child) in members {
          stack.push((child, depth + 1, pointer_child(pointer, name)))
        }
      Array(items~) =>
        for i, child in items {
          stack.push((child, depth + 1, pointer_child(pointer, i.to_string())))
        }
      _ => ()
    }
  }
  None
}

///|
pub fn compile_schema(
  schema : @pjson.Json,
) -> Result[CompiledSchema, Array[SchemaProblem]] {
  match schema_snapshot_problem(schema) {
    Some(problem) => return Err([problem])
    None => ()
  }
  let snapshot = copy_schema_json(schema)
  let cache : Map[String, Result[Pattern, PatternProblem]] = Map([])
  compile_schema_snapshot(snapshot, cache)
}

///|
fn compile_schema_snapshot(
  snapshot : @pjson.Json,
  cache : Map[String, Result[Pattern, PatternProblem]],
) -> Result[CompiledSchema, Array[SchemaProblem]] {
  let problems = []
  let ctx : SchemaCompileContext = {
    root: snapshot,
    nodes: [],
    node_ids: Map([]),
    references: Map([]),
    pointer: "",
  }
  enqueue_schema(ctx, snapshot, "", "") |> ignore
  let mut index = 0
  while index < ctx.nodes.length() {
    let node = ctx.nodes[index]
    ctx.pointer = node.pointer
    check_schema(node.schema, node.display, problems, cache, ctx)
    index = index + 1
  }
  if problems.is_empty() {
    let patterns : Map[String, Pattern] = Map([])
    for text, result in cache {
      match result {
        Ok(pattern) => patterns[text] = pattern
        Err(_) => abort("schema precheck lost a pattern compilation problem")
      }
    }
    Ok({
      patterns,
      nodes: ctx.nodes,
      node_ids: ctx.node_ids,
      references: ctx.references,
    })
  } else {
    Err(problems)
  }
}

///|
fn precheck_schema(
  schema : @pjson.Json,
  cache : Map[String, Result[Pattern, PatternProblem]],
) -> Array[SchemaProblem] {
  match schema_snapshot_problem(schema) {
    Some(problem) => [problem]
    None =>
      match compile_schema_snapshot(schema, cache) {
        Ok(_) => []
        Err(problems) => problems
      }
  }
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
