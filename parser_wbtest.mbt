///|
/// Parse `text`, failing the test if it is rejected.
fn accept(text : String, max_depth : Int?) -> @pjson.Json {
  match parse_with_diagnostic(text, max_depth) {
    Ok(json) => json
    Err(diagnostic) => abort("expected this to parse: " + diagnostic.summary())
  }
}

///|
/// Parse `text`, failing the test if it is accepted, and return the diagnostic.
fn reject(text : String, max_depth : Int?) -> JsonDiagnostic {
  match parse_with_diagnostic(text, max_depth) {
    Ok(_) => abort("expected this to be rejected: " + text)
    Err(diagnostic) => diagnostic
  }
}

///|
/// An array nested `levels` deep, as JSON text.
fn brackets(levels : Int) -> String {
  let buf = StringBuilder()
  for _ in 0..<levels {
    buf.write_char('[')
  }
  for _ in 0..<levels {
    buf.write_char(']')
  }
  buf.to_string()
}

///|
test "an object without repeated keys parses" {
  let json = accept("{\"a\":1,\"b\":{\"c\":2}}", None)
  match json {
    Object(members~) => {
      assert_eq(members.length(), 2)
      assert_eq(members[0].0, "a")
      assert_eq(members[1].0, "b")
    }
    _ => abort("expected an object at the root")
  }
}

///|
test "a repeated object key is reported with its position" {
  // The first `"a"` is fine, so it is the second one that the diagnostic has to
  // point at: line 2, and the quote that opens it.
  let diagnostic = reject("{\"a\":1,\n \"a\":2}", None)
  assert_eq(
    diagnostic.message,
    "duplicate object key \"a\" (first defined at line 1, column 2)",
  )
  assert_eq(diagnostic.line, 2)
  assert_eq(diagnostic.column, 2)
  assert_eq(diagnostic.snippet, " \"a\":2}")
}

///|
test "a document within the depth limit parses" {
  // The limit counts collections entered, so three levels are what an argument
  // of 3 buys, in arrays and in objects alike.
  let _ = accept("[[[]]]", Some(3))
  let _ = accept("{\"a\":{\"b\":{\"c\":1}}}", Some(3))
  // A bare scalar nests nothing at all, which is the one thing a limit of zero
  // still allows.
  let _ = accept("5", Some(0))
}

///|
test "a document past the depth limit is reported with its position" {
  let diagnostic = reject("[[[[]]]]", Some(3))
  assert_eq(diagnostic.message, "nesting depth exceeds limit 3")
  // The fourth `[` is the one that went one level too far.
  assert_eq(diagnostic.line, 1)
  assert_eq(diagnostic.column, 4)
}

///|
test "a depth limit reaches nested objects as well as arrays" {
  assert_eq(
    reject("{\"a\":{\"b\":{\"c\":{\"d\":1}}}}", Some(3)).message,
    "nesting depth exceeds limit 3",
  )
}

///|
/// `standard_max_depth` restates a number the parser library owns, since
/// `JsonLimits` keeps its fields private. This measures the limit the library
/// actually applies, so the copy cannot drift without the suite saying so.
test "the default depth limit matches the documented constant" {
  let _ = accept(brackets(standard_max_depth), None)
  let diagnostic = reject(brackets(standard_max_depth + 1), None)
  assert_eq(
    diagnostic.message,
    "nesting depth exceeds limit " + standard_max_depth.to_string(),
  )
}

///|
test "asking for a depth above the standard one raises the limit" {
  // Without this the flag could only ever tighten the parser's own limit, and
  // a caller who wanted room for a deeper document would be out of luck.
  let deep = brackets(standard_max_depth + 1)
  assert_eq(
    reject(deep, None).message,
    "nesting depth exceeds limit " + standard_max_depth.to_string(),
  )
  let _ = accept(deep, Some(standard_max_depth + 1))
}
