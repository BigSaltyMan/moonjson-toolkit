///|
/// Run a rewrite and render what it produced on one line.
///
/// Every test below states its expectation as the document the rewrite gives
/// back, which is the whole of what a rewrite is: a caller asking for a
/// selection wants to read the selection, not to inspect a tree for it. The
/// rendering is the compact one so that the expectation fits on a line and
/// shows the order of the members as well as their values.
fn transformed(result : Result[@pjson.Json, String]) -> String {
  match result {
    Ok(json) => format_compact(json)
    Err(message) => abort("expected the rewrite to succeed: " + message)
  }
}

///|
/// The sentence a refused rewrite gave, failing the test if it succeeded.
///
/// A rewrite that cannot be done is not a wrong answer to be compared against
/// another wrong answer: it is an error the run reports and exits on, so what a
/// test can hold it to is that it refused and that the reader is told why.
fn refused(result : Result[@pjson.Json, String]) -> String {
  match result {
    Ok(json) =>
      abort("expected the rewrite to be refused, got " + format_compact(json))
    Err(message) => message
  }
}

///|
test "selecting keeps the named fields in the order they were named" {
  // The list is what the caller wrote, so `b` comes first because it was asked
  // for first, not because `a` is earlier in the document.
  assert_eq(
    transformed(select(parse_ok("{\"a\":1,\"b\":2}"), ["b", "a"])),
    "{\"b\":2,\"a\":1}",
  )
  assert_eq(
    transformed(select(parse_ok("{\"a\":1,\"b\":2,\"c\":3}"), ["c"])),
    "{\"c\":3}",
  )
  // A field named twice is taken once, since an object cannot hold the same
  // member twice and printing it twice would produce a document this tool
  // refuses to read back.
  assert_eq(
    transformed(select(parse_ok("{\"a\":1,\"b\":2}"), ["a", "a", "b"])),
    "{\"a\":1,\"b\":2}",
  )
  // The values come through as they were, nesting and all.
  assert_eq(
    transformed(
      select(parse_ok("{\"a\":{\"b\":[1,2]},\"c\":null}"), ["a", "c"]),
    ),
    "{\"a\":{\"b\":[1,2]},\"c\":null}",
  )
}

///|
test "selecting a field the object does not have is not an error" {
  // A selection is written once and used over a folder of documents, so the
  // ones that have moved on are the case it has to survive rather than the case
  // it reports.
  assert_eq(transformed(select(parse_ok("{\"a\":1}"), ["a", "z"])), "{\"a\":1}")
  assert_eq(transformed(select(parse_ok("{}"), ["a"])), "{}")
  // A key that is there holding null is a field that was found.
  assert_eq(
    transformed(select(parse_ok("{\"a\":null}"), ["a"])),
    "{\"a\":null}",
  )
  // Space is part of a name, since a JSON key may contain one.
  assert_eq(transformed(select(parse_ok("{\" a\":1}"), ["a"])), "{}")
}

///|
test "selecting from something that is not an object is refused" {
  // The sentence names the option and what the document actually is, so the
  // reader knows both what was asked for and what it was asked of.
  let message = refused(select(parse_ok("[1,2]"), ["a"]))
  assert_true(message.contains("--select"))
  assert_true(message.contains("an array"))
  assert_true(refused(select(parse_ok("\"text\""), ["a"])).contains("a string"))
  assert_true(refused(select(parse_ok("7"), ["a"])).contains("a number"))
  assert_true(refused(select(parse_ok("null"), ["a"])).contains("null"))
  assert_true(refused(select(parse_ok("true"), ["a"])).contains("a boolean"))
}

///|
test "selecting nothing from an object gives an empty object" {
  // An empty list is a selection of no fields, which is a document with no
  // members rather than a refusal: the request was answered, and the answer is
  // that nothing was asked for.
  assert_eq(transformed(select(parse_ok("{\"a\":1}"), [])), "{}")
  // A member whose name is the empty string is a member like any other, and the
  // empty path is the one path that reaches it without being a special case.
  assert_eq(transformed(select(parse_ok("{\"\":1}"), [""])), "{\"\":1}")
}

///|
test "sorting an array of numbers puts them in order" {
  assert_eq(transformed(sort_by(parse_ok("[3,1,2]"), "")), "[1,2,3]")
  // Negative numbers and fractions compare as the numbers they are, not as the
  // text that spells them: `-1` is less than `0` though `-` sorts before `0`.
  assert_eq(
    transformed(sort_by(parse_ok("[0,-1,0.5,-0.25]"), "")),
    "[-1,-0.25,0,0.5]",
  )
  // An array of records is sorted by the field the path names, and the whole
  // records move together.
  assert_eq(
    transformed(sort_by(parse_ok("[{\"n\":3},{\"n\":1},{\"n\":2}]"), "n")),
    "[{\"n\":1},{\"n\":2},{\"n\":3}]",
  )
  // Numbers written in exponent form are read as the numbers they denote, so
  // `1.5e2` moves in front of `1e3` — while each keeps the text that spells it,
  // since sorting moves the items and does not rewrite them.
  assert_eq(
    transformed(sort_by(parse_ok("[1e3,2,1.5e2]"), "")),
    "[2,1.5e2,1e3]",
  )
}

///|
test "sorting by a string field compares strings" {
  assert_eq(
    transformed(sort_by(parse_ok("[{\"s\":\"pear\"},{\"s\":\"apple\"}]"), "s")),
    "[{\"s\":\"apple\"},{\"s\":\"pear\"}]",
  )
  // The comparison is by code point, so an upper case letter sorts before a
  // lower case one.
  assert_eq(
    transformed(sort_by(parse_ok("[\"b\",\"A\",\"a\"]"), "")),
    "[\"A\",\"a\",\"b\"]",
  )
  // Length is not consulted, so a string that is the start of another comes
  // first: `"a"` before `"ab"` before `"b"`. Ordering by length first would put
  // `"b"` in the middle, and that shortlex order is what `String::compare` in
  // the standard library does — which is why the comparison is written out here
  // rather than taken from it.
  assert_eq(
    transformed(sort_by(parse_ok("[\"b\",\"ab\",\"a\"]"), "")),
    "[\"a\",\"ab\",\"b\"]",
  )
}

///|
test "sorting treats a field that is not there as null" {
  // A record with no value for the field sorts as though it held null, which
  // puts it in front of the records that do have one.
  assert_eq(
    transformed(sort_by(parse_ok("[{\"n\":2},{\"other\":1},{\"n\":1}]"), "n")),
    "[{\"other\":1},{\"n\":1},{\"n\":2}]",
  )
  // A field that is not there and a field that is there holding null are the
  // same key, so those two items keep the order the document gave them.
  assert_eq(
    transformed(sort_by(parse_ok("[{\"n\":1},{\"k\":null},{\"n\":null}]"), "n")),
    "[{\"k\":null},{\"n\":null},{\"n\":1}]",
  )
  // A path that stops partway is a path that reached nothing, so an item whose
  // object is there but has no such member in it is a null as well.
  assert_eq(
    transformed(
      sort_by(
        parse_ok("[{\"a\":{\"b\":2}},{\"a\":{}},{\"a\":{\"b\":1}}]"),
        "a.b",
      ),
    ),
    "[{\"a\":{}},{\"a\":{\"b\":1}},{\"a\":{\"b\":2}}]",
  )
  // A path that runs into a value partway is a path that reached nothing too:
  // `a` is a number here, so there is no `b` inside it to find.
  assert_eq(
    transformed(
      sort_by(
        parse_ok("[{\"a\":{\"b\":2}},{\"a\":1},{\"a\":{\"b\":1}}]"),
        "a.b",
      ),
    ),
    "[{\"a\":1},{\"a\":{\"b\":1}},{\"a\":{\"b\":2}}]",
  )
}

///|
test "sorting puts values of different kinds in the order jq uses" {
  // One of every kind at once, so the order between all seven is stated in one
  // place: null, false, true, numbers, strings, arrays, objects.
  assert_eq(
    transformed(
      sort_by(parse_ok("[{\"a\":1},[1],false,true,\"s\",1,null]"), ""),
    ),
    "[null,false,true,1,\"s\",[1],{\"a\":1}]",
  )
  // Numbers come before strings, so `9` is not less than `10` here: neither is
  // being read as text.
  assert_eq(
    transformed(sort_by(parse_ok("[10,\"9\",2,\"3\"]"), "")),
    "[2,10,\"3\",\"9\"]",
  )
  // Two arrays are equal to each other, and two objects too: what is inside
  // them is not compared, so they keep the order the document gave them.
  assert_eq(
    transformed(sort_by(parse_ok("[[2],[1],{\"b\":1},{\"a\":2}]"), "")),
    "[[2],[1],{\"b\":1},{\"a\":2}]",
  )
}

///|
test "sorting reads a number too large for a double as the end it went past" {
  // `1e400` and `-1e400` are legal JSON numbers that no double denotes. Reading
  // them as the ends of the range keeps them in an order with every other
  // number, which is what a sort needs of every pair: left equal to everything
  // they would compare equal to both `5` and `10` at once.
  assert_eq(transformed(sort_by(parse_ok("[1e400,5]"), "")), "[5,1e400]")
  assert_eq(transformed(sort_by(parse_ok("[-1e400,5]"), "")), "[-1e400,5]")
  assert_eq(
    transformed(sort_by(parse_ok("[1e400,-1e400]"), "")),
    "[-1e400,1e400]",
  )
  // Two of them on the same side are equal, since neither has a size a double
  // can tell from the other's, and equal keys keep the order they came in.
  assert_eq(
    transformed(sort_by(parse_ok("[1e500,1e400]"), "")),
    "[1e500,1e400]",
  )
}

///|
test "sorting is stable and leaves the tree alone" {
  // Two items whose keys are equal keep the order the document gave them, so a
  // sort by one field does not disturb what a previous sort by another did.
  assert_eq(
    transformed(
      sort_by(
        parse_ok("[{\"k\":1,\"n\":\"first\"},{\"k\":1,\"n\":\"second\"}]"),
        "k",
      ),
    ),
    "[{\"k\":1,\"n\":\"first\"},{\"k\":1,\"n\":\"second\"}]",
  )
  // Equal keys are common enough to be worth checking on a longer list, where a
  // sort that swapped equal items would have somewhere to swap them to.
  assert_eq(
    transformed(sort_by(parse_ok("[2,1,2,1,2,1]"), "")),
    "[1,1,1,2,2,2]",
  )
  let json = parse_ok("[3,1,2]")
  ignore(sort_by(json, ""))
  assert_eq(format_compact(json), "[3,1,2]")
}

///|
test "sorting an object sorts the array it holds" {
  // The shape most exports arrive in: the records are one member, and the rest
  // of the object is left as it was written, down to the order of the members.
  assert_eq(
    transformed(
      sort_by(parse_ok("{\"n\":\"a\",\"items\":[3,1],\"m\":true}"), ""),
    ),
    "{\"n\":\"a\",\"items\":[1,3],\"m\":true}",
  )
  assert_eq(
    transformed(sort_by(parse_ok("{\"items\":[{\"n\":2},{\"n\":1}]}"), "n")),
    "{\"items\":[{\"n\":1},{\"n\":2}]}",
  )
  // An object with no array in it is not a document this can be done to.
  assert_true(
    refused(sort_by(parse_ok("{\"a\":1}"), "")).contains("no array in it"),
  )
  // An object with several is refused rather than guessed at, and the sentence
  // says which ones were there so the run can be fixed without reading the
  // document again.
  let several = refused(sort_by(parse_ok("{\"a\":[1],\"b\":[2]}"), ""))
  assert_true(several.contains("a"))
  assert_true(several.contains("b"))
  assert_true(refused(sort_by(parse_ok("{\"a\":1}"), "")).contains("--sort-by"))
}

///|
test "sorting something that is not an array is refused" {
  assert_true(refused(sort_by(parse_ok("\"text\""), "")).contains("a string"))
  assert_true(refused(sort_by(parse_ok("7"), "")).contains("a number"))
  assert_true(refused(sort_by(parse_ok("null"), "")).contains("null"))
  // An empty array is not refused: it is already in order, and saying so is
  // answering the request rather than failing it.
  assert_eq(transformed(sort_by(parse_ok("[]"), "")), "[]")
  assert_eq(transformed(sort_by(parse_ok("[{}]"), "n")), "[{}]")
}

///|
test "deduplicating compares whole items as they would be printed" {
  assert_eq(transformed(unique(parse_ok("[1,2,1,3,2]"), None)), "[1,2,3]")
  assert_eq(transformed(unique(parse_ok("[1,2,1,3,2]"), Some(""))), "[1,2,3]")
  // The first of a run of equal items is the one kept, so the order of the
  // document is the order of the answer.
  assert_eq(
    transformed(unique(parse_ok("[\"b\",\"a\",\"b\"]"), None)),
    "[\"b\",\"a\"]",
  )
  // The comparison is of the serialised item, so two objects whose members are
  // written in different orders are two items — and `--sort-keys` first makes
  // them one.
  assert_eq(
    transformed(unique(parse_ok("[{\"a\":1,\"b\":2},{\"b\":2,\"a\":1}]"), None)),
    "[{\"a\":1,\"b\":2},{\"b\":2,\"a\":1}]",
  )
  assert_eq(
    transformed(
      unique(sort_keys(parse_ok("[{\"a\":1,\"b\":2},{\"b\":2,\"a\":1}]")), None),
    ),
    "[{\"a\":1,\"b\":2}]",
  )
  // Numbers are compared as the text that spells them, so `1` and `1.0` are two
  // items: they print differently, and printing is the comparison.
  assert_eq(transformed(unique(parse_ok("[1,1.0,1]"), None)), "[1,1.0]")
}

///|
test "deduplicating by a field compares that field" {
  assert_eq(
    transformed(
      unique(
        parse_ok("[{\"id\":1,\"n\":\"a\"},{\"id\":1,\"n\":\"b\"}]"),
        Some("id"),
      ),
    ),
    "[{\"id\":1,\"n\":\"a\"}]",
  )
  // The path reaches into nested objects, and two items whose paths hold equal
  // values are equal however the rest of them differs.
  assert_eq(
    transformed(
      unique(
        parse_ok("[{\"a\":{\"b\":1}},{\"a\":{\"b\":1}},{\"a\":{\"b\":2}}]"),
        Some("a.b"),
      ),
    ),
    "[{\"a\":{\"b\":1}},{\"a\":{\"b\":2}}]",
  )
  // An item that does not have the field is kept: it has no value to be
  // compared, so it cannot be a repeat of anything. Calling it a duplicate of
  // another item that also has none would be answering a question the document
  // did not ask.
  assert_eq(
    transformed(
      unique(parse_ok("[{\"id\":1},{\"other\":2},{\"other\":3}]"), Some("id")),
    ),
    "[{\"id\":1},{\"other\":2},{\"other\":3}]",
  )
  // A field that is there holding null is a value, and one that repeats is a
  // repeat.
  assert_eq(
    transformed(unique(parse_ok("[{\"id\":null},{\"id\":null}]"), Some("id"))),
    "[{\"id\":null}]",
  )
}

///|
test "deduplicating an empty or single-item array gives it back" {
  assert_eq(transformed(unique(parse_ok("[]"), None)), "[]")
  assert_eq(transformed(unique(parse_ok("[]"), Some("id"))), "[]")
  assert_eq(transformed(unique(parse_ok("[1]"), None)), "[1]")
  assert_eq(transformed(unique(parse_ok("[{}]"), Some("id"))), "[{}]")
  // Everything distinct stays, and everything equal collapses to the first.
  assert_eq(transformed(unique(parse_ok("[{},{},{}]"), None)), "[{}]")
  let json = parse_ok("[1,1]")
  ignore(unique(json, None))
  assert_eq(format_compact(json), "[1,1]")
}

///|
test "deduplicating something that is not an array is refused" {
  let message = refused(unique(parse_ok("{\"a\":1}"), None))
  assert_true(message.contains("--unique"))
  assert_true(message.contains("an object"))
  assert_true(refused(unique(parse_ok("\"text\""), None)).contains("a string"))
  assert_true(refused(unique(parse_ok("7"), None)).contains("a number"))
  assert_true(refused(unique(parse_ok("null"), None)).contains("null"))
}
