///|
/// The count recorded for one JSON type, or zero when it was never seen.
fn type_count(stats : JsonStats, kind : String) -> Int {
  let mut total = 0
  for entry in stats.type_counts {
    if entry.kind == kind {
      total = entry.count
    }
  }
  total
}

///|
/// The count recorded for one nesting depth, or zero when it was never seen.
fn depth_count(stats : JsonStats, depth : Int) -> Int {
  let mut total = 0
  for entry in stats.depth_counts {
    if entry.depth == depth {
      total = entry.count
    }
  }
  total
}

///|
/// The key count recorded for one top-level field name.
fn key_count(stats : JsonStats, name : String) -> Int {
  let mut total = 0
  for entry in stats.key_counts {
    if entry.name == name {
      total = entry.count
    }
  }
  total
}

///|
test "a scalar document has one node at depth one" {
  let stats = JsonStats::of(parse_ok("42"))
  assert_eq(stats.total_nodes, 1)
  assert_eq(stats.max_depth, 1)
  assert_eq(stats.total_keys, 0)
  assert_eq(type_count(stats, "number"), 1)
}

///|
test "an empty container is counted but is not deep" {
  let stats = JsonStats::of(parse_ok("{}"))
  assert_eq(stats.total_nodes, 1)
  assert_eq(stats.max_depth, 1)
  assert_eq(type_count(stats, "object"), 1)
  assert_eq(stats.key_counts.length(), 0)
}

///|
test "keys are counted at every depth" {
  let stats = JsonStats::of(parse_ok("{\"a\":{\"b\":{\"c\":1}}}"))
  assert_eq(stats.total_keys, 3)
}

///|
test "each JSON type is counted" {
  let stats = JsonStats::of(parse_ok("[null,true,1,\"s\",[],{}]"))
  assert_eq(type_count(stats, "null"), 1)
  assert_eq(type_count(stats, "boolean"), 1)
  assert_eq(type_count(stats, "number"), 1)
  assert_eq(type_count(stats, "string"), 1)
  assert_eq(type_count(stats, "array"), 2)
  assert_eq(type_count(stats, "object"), 1)
}

///|
test "nesting depth follows the deepest branch" {
  let stats = JsonStats::of(parse_ok("{\"a\":[1,{\"b\":2}],\"c\":3}"))
  assert_eq(stats.max_depth, 4)
}

///|
test "depth counts cover every level up to the maximum" {
  // Depth 2 holds the array and the number 3; depth 3 holds 1 and {"b": 2}.
  let stats = JsonStats::of(parse_ok("{\"a\":[1,{\"b\":2}],\"c\":3}"))
  assert_eq(stats.depth_counts.length(), stats.max_depth)
  assert_eq(depth_count(stats, 1), 1)
  assert_eq(depth_count(stats, 2), 2)
  assert_eq(depth_count(stats, 3), 2)
  assert_eq(depth_count(stats, 4), 1)
}

///|
test "top-level fields are counted separately for charting" {
  let stats = JsonStats::of(
    parse_ok("{\"small\":1,\"big\":{\"a\":1,\"b\":{\"c\":2}}}"),
  )
  assert_eq(key_count(stats, "small"), 0)
  assert_eq(key_count(stats, "big"), 3)
}

///|
test "an array document is charted as a single root entry" {
  let stats = JsonStats::of(parse_ok("[{\"a\":1},{\"b\":2}]"))
  assert_eq(stats.key_counts.length(), 1)
  assert_eq(key_count(stats, "<root>"), 2)
}

///|
test "the statistics serialise to JSON the frontend can read back" {
  let stats = JsonStats::of(parse_ok("{\"a\":[1,2],\"b\":{\"c\":null}}"))
  let reparsed = parse_ok(stats.to_json_text())
  match object_field(reparsed, "max_depth") {
    Some(Number(raw~)) => assert_eq(raw, "3")
    _ => abort("max_depth should survive the round trip as a number")
  }
  assert_eq(object_field(reparsed, "total_keys").bind(text_value), None)
}

///|
test "no JSON type is missing from the report" {
  let stats = JsonStats::of(parse_ok("1"))
  assert_eq(stats.type_counts.length(), 6)
}
