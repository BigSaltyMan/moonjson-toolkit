///|
/// Prune the null members out of `text` and render the result on one line.
fn pruned_nulls(text : String) -> String {
  format_compact(prune_null(parse_ok(text)))
}

///|
/// Prune the empty containers out of `text` and render the result on one line.
fn pruned_empties(text : String) -> String {
  format_compact(prune_empty(parse_ok(text)))
}

///|
/// The two prunings in the order the tool applies them, which is the pair the
/// flags are for.
fn pruned(text : String) -> String {
  format_compact(prune_empty(prune_null(parse_ok(text))))
}

///|
test "pruning nulls drops the members that hold them" {
  assert_eq(pruned_nulls("{\"a\":null,\"b\":1}"), "{\"b\":1}")
  // The members that stay keep the order they were written in.
  assert_eq(pruned_nulls("{\"a\":1,\"b\":null,\"c\":2}"), "{\"a\":1,\"c\":2}")
  // Every object in the document is looked at, not just the outermost.
  assert_eq(
    pruned_nulls("{\"a\":{\"b\":null,\"c\":{\"d\":null,\"e\":2}}}"),
    "{\"a\":{\"c\":{\"e\":2}}}",
  )
  // A bare `null` is the document rather than a member of one, so there is
  // nothing above it that could be emptied by dropping it.
  assert_eq(pruned_nulls("null"), "null")
  assert_eq(pruned_nulls("{\"a\":null}"), "{}")
}

///|
test "pruning nulls leaves arrays and the tree alone" {
  // A null inside an array is a value in a place rather than a member with no
  // value: dropping it would renumber the items after it, so it stays.
  assert_eq(pruned_nulls("[null,1]"), "[null,1]")
  assert_eq(
    pruned_nulls("{\"a\":[null,{\"b\":null,\"c\":2}]}"),
    "{\"a\":[null,{\"c\":2}]}",
  )
  // An object inside an array is an object like any other, and loses its null
  // members like any other.
  let json = parse_ok("{\"a\":{\"b\":null,\"c\":1}}")
  ignore(prune_null(json))
  assert_eq(format_compact(json), "{\"a\":{\"b\":null,\"c\":1}}")
}

///|
test "pruning empty containers drops them and keeps going up" {
  assert_eq(pruned_empties("{\"a\":{},\"b\":1}"), "{\"b\":1}")
  assert_eq(pruned_empties("{\"a\":[],\"b\":1}"), "{\"b\":1}")
  assert_eq(pruned_empties("{\"a\":{},\"b\":[]}"), "{}")
  // The member holding the empty one is left empty by its removal, and an empty
  // object is exactly what this removes, so it goes too.
  assert_eq(pruned_empties("{\"a\":{\"b\":{}},\"c\":1}"), "{\"c\":1}")
  assert_eq(pruned_empties("{\"a\":{\"b\":{\"c\":[]}},\"d\":1}"), "{\"d\":1}")
}

///|
test "pruning empty containers reaches into arrays" {
  assert_eq(pruned_empties("{\"a\":[{},1]}"), "{\"a\":[1]}")
  // The inner array goes, which leaves the outer one with nothing in it: the
  // two removals are one pass, each one making the next possible.
  assert_eq(pruned_empties("{\"a\":[[]]}"), "{}")
  assert_eq(pruned_empties("{\"a\":[{\"b\":{}},2]}"), "{\"a\":[2]}")
  // An array of arrays keeps the ones that have something in them.
  assert_eq(pruned_empties("[[1],[],[]]"), "[[1]]")
}

///|
test "the document itself is kept even when it ends up empty" {
  // There is no container above the document to be told it is empty, so an
  // empty one is only ever removed from inside another.
  assert_eq(pruned_empties("{}"), "{}")
  assert_eq(pruned_empties("[]"), "[]")
  assert_eq(pruned_empties("[{}]"), "[]")
  // A scalar has no members to lose and is not a container to be found empty.
  assert_eq(pruned_empties("1"), "1")
  assert_eq(pruned_empties("\"\""), "\"\"")
  assert_eq(pruned_empties("null"), "null")
}

///|
test "the two prunings are applied nulls first, then empties" {
  // The null goes, and the member holding it is left empty, which is what the
  // second pruning removes: one pass of each is enough for both.
  assert_eq(pruned("{\"a\":{\"b\":null}}"), "{}")
  // The order is not a detail: asked the other way round, nothing is empty to
  // begin with, and the member that held the null survives as an empty object.
  assert_eq(pruned_empties("{\"a\":{\"b\":null}}"), "{\"a\":{\"b\":null}}")
  assert_eq(
    format_compact(prune_null(prune_empty(parse_ok("{\"a\":{\"b\":null}}")))),
    "{\"a\":{}}",
  )
  // Together they clear a document down to what it actually says.
  assert_eq(
    pruned("{\"a\":null,\"b\":{},\"c\":[1,null],\"d\":{\"e\":null}}"),
    "{\"c\":[1,null]}",
  )
}
