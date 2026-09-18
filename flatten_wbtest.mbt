///|
/// Flatten `text` and render the result on one line.
fn flatten_text(text : String) -> String {
  match flatten(parse_ok(text)) {
    Ok(json) => format_compact(json)
    Err(message) => abort("expected this document to flatten: " + message)
  }
}

///|
/// Unflatten `text` and render the result on one line.
fn unflatten_text(text : String) -> String {
  match unflatten(parse_ok(text)) {
    Ok(json) => format_compact(json)
    Err(message) => abort("expected this document to unflatten: " + message)
  }
}

///|
/// The message a document is refused with, for the tests about conflicts.
fn flatten_error(text : String) -> String {
  match flatten(parse_ok(text)) {
    Ok(json) =>
      abort(
        "expected this document to be refused, got: " + format_compact(json),
      )
    Err(message) => message
  }
}

///|
fn unflatten_error(text : String) -> String {
  match unflatten(parse_ok(text)) {
    Ok(json) =>
      abort(
        "expected this document to be refused, got: " + format_compact(json),
      )
    Err(message) => message
  }
}

///|
test "flattening joins the path of every nested object" {
  assert_eq(flatten_text("{\"a\":{\"b\":1},\"c\":2}"), "{\"a.b\":1,\"c\":2}")
  // Any depth, and the members keep the order they were written in.
  assert_eq(
    flatten_text("{\"a\":{\"b\":{\"c\":{\"d\":1}}}}"),
    "{\"a.b.c.d\":1}",
  )
  assert_eq(
    flatten_text("{\"x\":1,\"a\":{\"b\":2},\"y\":3}"),
    "{\"x\":1,\"a.b\":2,\"y\":3}",
  )
  // The tree handed in is left as it was found, as with sorting and trimming.
  let json = parse_ok("{\"a\":{\"b\":1}}")
  ignore(flatten(json))
  assert_eq(format_compact(json), "{\"a\":{\"b\":1}}")
}

///|
test "flattening leaves a document that is already flat alone" {
  // A key with a dot in it is just a key: flattening only ever joins keys, so
  // a document that was written this way comes back unchanged.
  assert_eq(flatten_text("{\"a.b\":1,\"c\":2}"), "{\"a.b\":1,\"c\":2}")
  assert_eq(flatten_text("{}"), "{}")
  assert_eq(flatten_text("[]"), "[]")
  assert_eq(flatten_text("\"text\""), "\"text\"")
  // An empty object has no paths inside it, so it stays a value rather than
  // disappearing.
  assert_eq(flatten_text("{\"a\":{},\"b\":1}"), "{\"a\":{},\"b\":1}")
}

///|
test "flattening reaches objects inside arrays" {
  // The array keeps its key and its length: flattening changes what is inside
  // an object, never how many values there are.
  assert_eq(
    flatten_text("{\"a\":[{\"b\":{\"c\":1}},2]}"),
    "{\"a\":[{\"b.c\":1},2]}",
  )
  assert_eq(
    flatten_text("{\"d\":{\"e\":[{\"f\":{\"g\":1}}]}}"),
    "{\"d.e\":[{\"f.g\":1}]}",
  )
  assert_eq(flatten_text("[{\"a\":{\"b\":1}}]"), "[{\"a.b\":1}]")
}

///|
test "flattening refuses a document that spells one path two ways" {
  // Lifting `a` would produce a second `a.b`, and one of the two would have to
  // be dropped. The message names both keys, and names them the same way round
  // whichever order they were written in.
  assert_eq(
    flatten_error("{\"a.b\":1,\"a\":{\"b\":2}}"),
    "conflicting keys: \"a\" and \"a.b\"",
  )
  assert_eq(
    flatten_error("{\"a\":{\"b\":2},\"a.b\":1}"),
    "conflicting keys: \"a\" and \"a.b\"",
  )
  // The clash is found inside an array too, where it is a clash between the
  // keys of that object and no one else's.
  assert_eq(
    flatten_error("{\"x\":[{\"b.c\":1,\"b\":{\"c\":2}}]}"),
    "conflicting keys: \"b\" and \"b.c\"",
  )
  // The lifted path is named by the key the descent started from, not by the
  // key it ended on, so the two keys named are always brothers.
  assert_eq(
    flatten_error("{\"a\":{\"b\":{\"c\":1}},\"a.b.c\":2}"),
    "conflicting keys: \"a\" and \"a.b.c\"",
  )
  // A literal dotted key beside a key holding something else is no trouble:
  // nothing is lifted, so nothing collides.
  assert_eq(flatten_text("{\"a.b\":1,\"a\":2}"), "{\"a.b\":1,\"a\":2}")
}

///|
test "unflattening expands dotted keys into nested objects" {
  assert_eq(unflatten_text("{\"a.b\":1,\"c\":2}"), "{\"a\":{\"b\":1},\"c\":2}")
  assert_eq(
    unflatten_text("{\"a.b.c.d\":1}"),
    "{\"a\":{\"b\":{\"c\":{\"d\":1}}}}",
  )
  // Keys sharing a prefix are merged, in the order they were written.
  assert_eq(
    unflatten_text("{\"a.b\":1,\"a.c\":2}"),
    "{\"a\":{\"b\":1,\"c\":2}}",
  )
  assert_eq(
    unflatten_text("{\"a.b.c\":1,\"a.d\":2,\"e\":3}"),
    "{\"a\":{\"b\":{\"c\":1},\"d\":2},\"e\":3}",
  )
  // A key with no dot in it names a member of the object it is already in, so
  // a document that was never flattened comes back unchanged.
  assert_eq(unflatten_text("{\"a\":{\"b\":1}}"), "{\"a\":{\"b\":1}}")
  assert_eq(unflatten_text("{}"), "{}")
}

///|
test "unflattening refuses a document that spells one path two ways" {
  assert_eq(
    unflatten_error("{\"a\":1,\"a.b\":2}"),
    "conflicting keys: \"a\" and \"a.b\"",
  )
  assert_eq(
    unflatten_error("{\"a.b\":2,\"a\":1}"),
    "conflicting keys: \"a\" and \"a.b\"",
  )
  // The clash can be further along the same path, and then the two keys named
  // are the ones that actually meet.
  assert_eq(
    unflatten_error("{\"a.b\":1,\"a.b.c\":2}"),
    "conflicting keys: \"a.b\" and \"a.b.c\"",
  )
  // A key holding an object is refused like any other: a document that names
  // one place two ways does not agree with itself, whatever is at the place.
  assert_eq(
    unflatten_error("{\"a\":{\"z\":1},\"a.b\":2}"),
    "conflicting keys: \"a\" and \"a.b\"",
  )
  // The clash is a property of the keys, not of the values: two keys that only
  // share a prefix are merged rather than refused.
  assert_eq(
    unflatten_text("{\"a.b\":1,\"a.c.d\":2}"),
    "{\"a\":{\"b\":1,\"c\":{\"d\":2}}}",
  )
}

///|
test "each direction undoes the other" {
  // A document with no nesting of its own is what unflattening is for: it takes
  // the dotted keys apart and flattening puts them back together exactly as they
  // were written.
  for
    document in [
      "{\"a.b\":1,\"c\":2}", "{\"a.b.c\":1,\"a.d\":2,\"e\":3}",
      // An empty segment is a segment like any other, on both sides of the trip:
      // `""` is a key, and `".b"` is the key `b` inside it.
       "{\"a.\":1,\".b\":2,\"..\":3}", "{\"a\":[{\"b.c\":1},2]}", "{\"a\":{}}", "{}",
      "[]", "\"text\"",
    ] {
    assert_eq(flatten_text(unflatten_text(document)), document)
  }
  // A nested document: flattening joins the paths and unflattening rebuilds the
  // nesting they came from.
  for
    document in [
      "{\"a\":{\"b\":1},\"c\":2}", "{\"a\":{\"b\":{\"c\":1}},\"d\":[{\"e\":{\"f\":2}},3]}",
      "{\"a\":[{\"b\":{\"c\":1}},{\"d\":2}]}", "{\"\":{\"a\":1}}", "{\"a\":{}}",
      "{}", "[]", "\"text\"",
    ] {
    assert_eq(unflatten_text(flatten_text(document)), document)
  }
}
