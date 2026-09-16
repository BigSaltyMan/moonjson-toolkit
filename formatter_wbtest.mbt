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
