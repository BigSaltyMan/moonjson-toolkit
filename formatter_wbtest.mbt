///|
fn parse_ok(text : String) -> @pjson.Json {
  match @pjson.parse(text) {
    Ok(json) => json
    Err(_) => abort("failed to parse test fixture: " + text)
  }
}

///|
test "format spreads an object over indented lines" {
  let json = parse_ok("{\"a\":1}")
  assert_eq(format(json, default_indent), "{\n  \"a\": 1\n}")
}

///|
test "format keeps empty containers inline" {
  assert_eq(format(parse_ok("{}"), 2), "{}")
  assert_eq(format(parse_ok("[]"), 2), "[]")
  assert_eq(
    format(parse_ok("{\"a\":{},\"b\":[]}"), 2),
    "{\n  \"a\": {},\n  \"b\": []\n}",
  )
}

///|
test "format nests arrays and objects" {
  let json = parse_ok("{\"a\":[1,2,{\"b\":true}]}")
  let expected = "{\n  \"a\": [\n    1,\n    2,\n    {\n      \"b\": true\n    }\n  ]\n}"
  assert_eq(format(json, 2), expected)
}

///|
test "format honours the requested indent width" {
  let json = parse_ok("{\"a\":[1]}")
  assert_eq(format(json, 4), "{\n    \"a\": [\n        1\n    ]\n}")
}

///|
test "indent zero keeps line breaks but drops leading spaces" {
  let json = parse_ok("{\"a\":[1]}")
  assert_eq(format(json, 0), "{\n\"a\": [\n1\n]\n}")
}

///|
test "indent widths are clamped to the supported range" {
  assert_eq(clamp_indent(-1), 0)
  assert_eq(clamp_indent(0), 0)
  assert_eq(clamp_indent(16), 16)
  assert_eq(clamp_indent(99), max_indent)
}

///|
test "format escapes strings and object keys" {
  let json = parse_ok("{\"a\\\"b\":\"line\\nbreak\\ttab\\\\slash\"}")
  assert_eq(
    format(json, 2),
    "{\n  \"a\\\"b\": \"line\\nbreak\\ttab\\\\slash\"\n}",
  )
}

///|
test "format escapes control characters as \\uXXXX" {
  assert_eq(escape_json_string("\u{01}"), "\\u0001")
  assert_eq(escape_json_string("\u{1F}"), "\\u001f")
}

///|
test "format preserves the original number literal" {
  assert_eq(format(parse_ok("1.50e+2"), 2), "1.50e+2")
}

///|
test "format_compact puts a nested document on one line" {
  let json = parse_ok("{\"a\":[1,2,{\"b\":true}]}")
  // The same document needs six lines when indented and one when compact, so
  // the two renderings are shown side by side to make the difference plain.
  assert_eq(
    format(json, 2),
    "{\n  \"a\": [\n    1,\n    2,\n    {\n      \"b\": true\n    }\n  ]\n}",
  )
  assert_eq(format_compact(json), "{\"a\":[1,2,{\"b\":true}]}")
}

///|
test "format_compact keeps the spaces inside strings" {
  // The only spaces that survive are the ones that are data: the ones between
  // the words of a key and of a value. The newline inside the string is still
  // an escape, so the line really is unbroken.
  let json = parse_ok("{\"a b\":\"c d\\ne\"}")
  assert_eq(format_compact(json), "{\"a b\":\"c d\\ne\"}")
}

///|
test "format_compact renders empty containers and bare scalars" {
  assert_eq(
    format_compact(parse_ok("{\"a\":[],\"b\":{}}")),
    "{\"a\":[],\"b\":{}}",
  )
  assert_eq(format_compact(parse_ok("[]")), "[]")
  // Numbers keep the literal they were written with, as in the indented form.
  assert_eq(format_compact(parse_ok("1.50e+2")), "1.50e+2")
}

///|
test "sorting orders the members of an object" {
  let json = parse_ok("{\"b\":1,\"a\":2,\"C\":3}")
  // Code point order, so the capital letter comes first: this is a byte-order
  // sort, not the case-insensitive one a spell checker would use.
  assert_eq(
    format(sort_keys(json), 2),
    "{\n  \"C\": 3,\n  \"a\": 2,\n  \"b\": 1\n}",
  )
}

///|
test "sorting reaches nested objects and objects inside arrays" {
  let json = parse_ok("{\"b\":{\"z\":1,\"a\":2},\"a\":[{\"y\":3,\"x\":4}]}")
  let expected = "{\n  \"a\": [\n    {\n      \"x\": 4,\n      \"y\": 3\n    }\n  ],\n  \"b\": {\n    \"a\": 2,\n    \"z\": 1\n  }\n}"
  assert_eq(format(sort_keys(json), 2), expected)
}

///|
test "sorting leaves the document it was given alone" {
  let json = parse_ok("{\"b\":{\"z\":1,\"a\":2},\"a\":[{\"y\":3,\"x\":4}]}")
  let before = format(json, 2)
  let sorted = sort_keys(json)
  // Sorting rebuilds the objects rather than reordering them in place, so the
  // tree the caller passed in still reads in the order it was written.
  assert_eq(format(json, 2), before)
  assert_eq(
    format(sorted, 2),
    "{\n  \"a\": [\n    {\n      \"x\": 4,\n      \"y\": 3\n    }\n  ],\n  \"b\": {\n    \"a\": 2,\n    \"z\": 1\n  }\n}",
  )
}
