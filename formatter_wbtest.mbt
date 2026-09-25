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
  // And the order is decided by the characters rather than by the lengths, which
  // is where `"pear"` would come first if it were not: `"apple"` sorts before it
  // because `a` is before `p`, and `"ab"` before that because it runs out of
  // characters while `"apple"` has `p` left over. Sorting by length first would
  // have answered `b, ab, pear, apple` instead.
  let words = parse_ok("{\"pear\":1,\"apple\":2,\"b\":3,\"ab\":4}")
  assert_eq(
    format_compact(sort_keys(words)),
    "{\"ab\":4,\"apple\":2,\"b\":3,\"pear\":1}",
  )
  // A character outside the basic plane is compared as the character it is
  // rather than as the code units it is written with: `😀` is one character of
  // its own, past every character in the basic plane, where comparing the code
  // units would have found the `😀` to start before the `�` below it.
  let wide = parse_ok("{\"😀\":1,\"a\":2,\"é\":3,\"\u{FFFD}\":4}")
  assert_eq(
    format_compact(sort_keys(wide)),
    "{\"a\":2,\"é\":3,\"\u{FFFD}\":4,\"😀\":1}",
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

///|
test "trimming removes the whitespace around top-level strings" {
  let json = parse_ok("{\"a\":\"  x  \",\"b\":\"   \",\"c\":1}")
  // An all-whitespace string becomes empty rather than disappearing: it is
  // still a member, and still one of the document's strings.
  assert_eq(
    format(trim_strings(json), 2),
    "{\n  \"a\": \"x\",\n  \"b\": \"\",\n  \"c\": 1\n}",
  )
  // A bare string is a document too, and gets the same treatment.
  assert_eq(format(trim_strings(parse_ok("\"  y \"")), 2), "\"y\"")
  // Newlines and tabs count as whitespace, not just spaces, so a string can be
  // joined across the lines it was written on.
  assert_eq(format(trim_strings(parse_ok("\"\\n\\ta\\t\\n\"")), 2), "\"a\"")
}

///|
test "trimming reaches strings nested in objects and arrays" {
  let json = parse_ok(
    "{\"a\":[\" p \",{\"b\":\"\\tq\\n\"}],\"c\":{\"d\":\" r \"}}",
  )
  let expected = "{\n  \"a\": [\n    \"p\",\n    {\n      \"b\": \"q\"\n    }\n  ],\n  \"c\": {\n    \"d\": \"r\"\n  }\n}"
  assert_eq(format(trim_strings(json), 2), expected)
  // Keys are names, not values, and are left exactly as they were written.
  assert_eq(
    format(trim_strings(parse_ok("{\"  k  \":\"  v  \"}")), 2),
    "{\n  \"  k  \": \"v\"\n}",
  )
  // The document handed in is untouched, as with sorting.
  assert_eq(
    format(json, 2),
    "{\n  \"a\": [\n    \" p \",\n    {\n      \"b\": \"\\tq\\n\"\n    }\n  ],\n  \"c\": {\n    \"d\": \" r \"\n  }\n}",
  )
}
