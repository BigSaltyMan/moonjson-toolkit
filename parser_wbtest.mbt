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

///|
/// A scratch path this file's tests own.
///
/// `moon test` runs tests concurrently, and these share the working directory
/// with `runner_wbtest.mbt`, so a name of one's own is what keeps two tests from
/// deleting each other's files.
fn parser_scratch(name : String) -> String {
  "parser_scratch_" + name + ".json"
}

///|
/// `parse` is the door that hands back the library's own error rather than a
/// diagnostic built around it, which is what a caller that only needs to know
/// whether the text is JSON wants.
test "parse returns the document, or the library's own error" {
  match parse("{\"a\":1}") {
    Ok(json) =>
      match json {
        Object(members~) => assert_eq(members.length(), 1)
        _ => abort("expected an object at the root")
      }
    Err(_) => abort("expected this to parse")
  }
  // The error keeps the parser's shape: an offset into the text, which is what
  // a caller building its own message would place the caret with. The trailing
  // comma means the `}` at index 7 is where the value was expected.
  match parse("{\"a\":1,}") {
    Ok(_) => abort("expected this to be rejected")
    Err(error) => assert_eq(error.offset(), 7)
  }
}

///|
/// Read `path`, failing the test if it succeeds, and return the message.
async fn read_error(path : String) -> String {
  match read_file(path) {
    Err(message) => message
    Ok(_) => abort("expected reading " + path + " to fail")
  }
}

///|
/// The two ways a wrong path fails, told apart rather than collapsed into one
/// message: a path that is not there, and a path that walks through a file.
/// The user can act on the difference.
async test "read_file tells a missing file from a path through a file" {
  let missing = parser_scratch("missing")
  discard(missing)
  assert_eq(read_error(missing), "no such file or directory")
  // `moon.mod` is a regular file, so nothing can sit underneath it.
  assert_eq(read_error("moon.mod/nested.json"), "not a directory")
}

///|
/// A file the process may not read is a third message again, and it is the one
/// a user is most likely to meet on a file they own but have not yet made
/// readable.
///
/// Permissions do not apply to a process running as root, and this suite can run
/// anywhere, so a read that unexpectedly succeeds leaves nothing to assert.
async test "read_file reports a file it may not read as permission denied" {
  let locked = parser_scratch("locked")
  @fs.write_file(locked, "{}")
  @fs.chmod(locked, 0o000)
  let outcome = read_file(locked)
  discard(locked)
  match outcome {
    Err(message) => assert_eq(message, "permission denied")
    Ok(_) => ()
  }
}

///|
/// An errno the tool has no phrase for still comes out as a message, so a
/// failure nobody anticipated is reported rather than swallowed.
///
/// Reading a directory is the everyday way to reach that branch: the open
/// succeeds and the read does not.
async test "an errno with no phrase of its own is reported with its number" {
  match read_file(".") {
    Err(message) => assert_true(message.has_prefix("operating system error "))
    Ok(_) => ()
  }
}
