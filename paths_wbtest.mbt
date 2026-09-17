///|
/// Parse `text` and list the path of every value in it.
fn paths_of(text : String) -> Array[String] {
  match @pjson.parse(text) {
    Ok(json) => collect_paths(json)
    Err(_) => abort("failed to parse test fixture: " + text)
  }
}

///|
/// Parse `text` and list the paths in it that name an object member.
fn keys_of(text : String) -> Array[String] {
  match @pjson.parse(text) {
    Ok(json) => collect_key_paths(json)
    Err(_) => abort("failed to parse test fixture: " + text)
  }
}

///|
test "paths of a flat object are its keys" {
  assert_eq(paths_of("{\"name\":\"x\",\"version\":2,\"stable\":true}"), [
    "name", "version", "stable",
  ])
}

///|
test "paths join nested members with a dot" {
  // A member of the root carries no leading dot, so the first level and the
  // second are written differently on purpose.
  assert_eq(paths_of("{\"nested\":{\"a\":{\"b\":1}}}"), [
    "nested", "nested.a", "nested.a.b",
  ])
}

///|
test "paths index array elements in brackets" {
  assert_eq(paths_of("{\"tags\":[\"a\",\"b\"]}"), ["tags", "tags[0]", "tags[1]"])
  // The array itself is listed before anything inside it, and an index follows
  // a key with no dot between them.
  assert_eq(paths_of("{\"m\":[[1],{\"k\":2}]}"), [
    "m", "m[0]", "m[0][0]", "m[1]", "m[1].k",
  ])
}

///|
test "paths treat empty containers as values with no descendants" {
  // An empty object contributes no paths of its own, and the members holding
  // empty containers are themselves paths.
  assert_eq(paths_of("{}"), [])
  assert_eq(paths_of("{\"a\":{},\"b\":[]}"), ["a", "b"])
  // A document that is a bare scalar has no path to report: the root is not
  // named by anything.
  assert_eq(paths_of("7"), [])
}

///|
test "paths of a root array are its indices" {
  assert_eq(paths_of("[1,{\"k\":2}]"), ["[0]", "[1]", "[1].k"])
}

///|
test "keys-only stops at the key that holds an array" {
  // Nothing inside an array is reached, so a value nested three deep is
  // missing from this list while `collect_paths` would report all of it.
  assert_eq(keys_of("{\"tags\":[{\"a\":{\"b\":1}}]}"), ["tags"])
  assert_eq(paths_of("{\"tags\":[{\"a\":{\"b\":1}}]}"), [
    "tags", "tags[0]", "tags[0].a", "tags[0].a.b",
  ])
}

///|
test "keys-only keeps every object member and drops only the indices" {
  assert_eq(keys_of("{\"a\":{\"b\":1},\"c\":[2,3]}"), ["a", "a.b", "c"])
  // With no objects to walk there are no keys, however much array there is.
  assert_eq(keys_of("[1,2]"), [])
}
