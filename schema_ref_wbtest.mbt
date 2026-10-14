///|
fn ref_compiled(text : String) -> CompiledSchema {
  match compile_schema(parse_ok(text)) {
    Ok(compiled) => compiled
    Err(problems) => abort(problems.map(render_schema_problem).join("\n"))
  }
}

///|
test "contains references advance instance positions and finite recursion stays valid" {
  let schema = ref_compiled(
    "{\"$defs\":{\"number\":{\"type\":\"integer\"}},\"contains\":{\"$ref\":\"#/$defs/number\"},\"minContains\":2}",
  )
  assert_true(
    validate_compiled_schema(parse_ok("[1,\"x\",2]"), schema) is Ok([]),
  )
  assert_true(
    validate_compiled_schema(parse_ok("[1,\"x\"]"), schema) is Ok([_]),
  )
  let recursive = ref_compiled(
    "{\"contains\":{\"$ref\":\"#\"},\"minContains\":0}",
  )
  assert_true(
    validate_compiled_schema(parse_ok("[[[]],[],1]"), recursive) is Ok([]),
  )
  assert_true(
    evaluate_schema_with_limits(parse_ok("[[]]"), recursive, 3, 3) is Ok([]),
  )
  match evaluate_schema_with_limits(parse_ok("[[]]"), recursive, 2, 3) {
    Err(error) => {
      assert_eq(error.kind, ResourceLimit)
      assert_eq(error.instance_path, "/0")
      assert_eq(error.schema_path, "")
    }
    _ => abort("contains recursion exceeded depth without execution failure")
  }
}

///|
test "contains evaluates later items after a match and propagates cycle locations" {
  let schema = ref_compiled(
    "{\"contains\":{\"properties\":{\"loop\":{\"$ref\":\"#/contains/properties/loop\"}}}}",
  )
  match validate_compiled_schema(parse_ok("[{}, {\"loop\":1}]"), schema) {
    Err(error) => {
      assert_eq(error.kind, ReferenceCycle)
      assert_eq(error.instance_path, "/1/loop")
      assert_eq(error.schema_path, "/contains/properties/loop/$ref")
    }
    _ => abort("first contains match swallowed a later execution error")
  }
  assert_true(validate_compiled_schema(parse_ok("[{}]"), schema) is Ok([]))
  for applicator in ["not", "anyOf", "oneOf", "allOf"] {
    let child = "{\"contains\":{\"$ref\":\"#/" +
      applicator +
      (if applicator == "not" { "" } else { "/0" }) +
      "/contains\"}}"
    let raw = "{\"" +
      applicator +
      "\":" +
      (if applicator == "not" { child } else { "[" + child + ",true]" }) +
      "}"
    assert_true(
      validate_compiled_schema(parse_ok("[1]"), ref_compiled(raw))
      is Err({ kind: ReferenceCycle, .. }),
    )
  }
}

///|
test "contains shares visit budgets across all elements even with zero minimum" {
  let schema = ref_compiled("{\"contains\":true}")
  assert_true(
    evaluate_schema_with_limits(parse_ok("[null,null]"), schema, 2, 3) is Ok([]),
  )
  match evaluate_schema_with_limits(parse_ok("[null,null]"), schema, 2, 2) {
    Err(error) => {
      assert_eq(error.kind, ResourceLimit)
      assert_eq(error.instance_path, "/1")
      assert_eq(error.schema_path, "/contains")
    }
    _ =>
      abort("matching first item reset or short-circuited the contains budget")
  }
  let zero = ref_compiled(
    "{\"contains\":true,\"minContains\":0,\"maxContains\":0}",
  )
  assert_true(evaluate_schema_with_limits(parse_ok("[]"), zero, 1, 1) is Ok([]))
  assert_true(
    evaluate_schema_with_limits(parse_ok("[1]"), zero, 2, 1)
    is Err({ kind: ResourceLimit, instance_path: "/0", .. }),
  )
  assert_true(validate_compiled_schema(parse_ok("[]"), zero) is Ok([]))
}

///|
test "reference decoding is strict and applied once" {
  let root = parse_ok(
    (
      #|{"$defs":{"a/b":true,"a~b":true,"~1":true,"":false,"a b":true,"%20":true,"+":true,"你好":true,"01":true},"allOf":[false]}
    ),
  )
  for
    (raw, pointer, truth) in [
      ("#/$defs/a~1b", "/$defs/a~1b", true),
      ("#/$defs/a~0b", "/$defs/a~0b", true),
      ("#/$defs/~01", "/$defs/~01", true),
      ("#/$defs/", "/$defs/", false),
      ("#/$defs/a%20b", "/$defs/a b", true),
      ("#/$defs/%2520", "/$defs/%20", true),
      ("#/$defs/+", "/$defs/+", true),
      ("#/$defs/%E4%BD%A0%E5%A5%BD", "/$defs/你好", true),
      ("#/$defs/你好", "/$defs/你好", true),
      ("#%2F$defs%2Fa~1b", "/$defs/a~1b", true),
      ("#/$defs/01", "/$defs/01", true),
      ("#/allOf/0", "/allOf/0", false),
    ] {
    match resolve_schema_ref(root, raw) {
      Ok((actual, Bool(value~))) => {
        assert_eq(actual, pointer)
        assert_eq(value, truth)
      }
      _ => abort("reference was not resolved correctly: " + raw)
    }
  }
  assert_true(resolve_schema_ref(root, "#") is Ok(("", Object(_))))
  assert_true(resolve_schema_ref(root, "#%2F$defs%2F%257E1") is Err(_))
}

///|
test "reference failures distinguish unsupported forms from broken pointers" {
  let root = parse_ok("{\"allOf\":[true],\"default\":3}")
  for raw in ["other.json#/x", "https://example.com/schema", "#anchor"] {
    assert_true(resolve_schema_ref(root, raw) is Err((UnsupportedFeature, _)))
  }
  for
    raw in [
      "#/%", "#/%0", "#/%GG", "#/%C0%AF", "#/%E4%BD", "#/%ED%A0%80", "#/%F4%90%80%80",
      "#/%80", "#/~", "#/~2", "#/missing", "#/default", "#/default/x", "#/allOf/-",
      "#/allOf/-1", "#/allOf/01", "#/allOf/1", "#/allOf/99999999999999999999999999999999999999999",
    ] {
    assert_true(resolve_schema_ref(root, raw) is Err((InvalidSchema, _)))
  }
}

///|
test "compiled references reuse stable nodes and inspect explicitly referenced data" {
  let schema = ref_compiled(
    (
      #|{"$defs":{"count":{"type":"integer"},"off":false},"allOf":[{"$ref":"#/$defs/count"},{"$ref":"#/$defs/count"}]}
    ),
  )
  assert_eq(schema.nodes.length(), 5)
  assert_eq(
    schema.references["/allOf/0/$ref"],
    schema.references["/allOf/1/$ref"],
  )
  assert_true(validate_compiled_schema(parse_ok("1"), schema) is Ok([]))
  assert_true(
    validate_schema(
      parse_ok("null"),
      parse_ok("{\"$defs\":{\"n\":{\"type\":\"integer\"}}}"),
    )
    is Ok([]),
  )
  assert_true(
    validate_schema(
      parse_ok("1"),
      parse_ok("{\"default\":{\"type\":\"integer\"},\"$ref\":\"#/default\"}"),
    )
    is Ok([]),
  )
  assert_true(
    validate_schema(
      parse_ok("null"),
      parse_ok("{\"default\":false,\"$ref\":\"#/default\"}"),
    )
    is Ok([_]),
  )
  let ordinary = parse_ok(
    "{\"default\":{\"unknown\":1},\"enum\":[{\"$ref\":false}]}",
  )
  assert_true(compile_schema(ordinary) is Ok(_))
  let referenced = parse_ok(
    "{\"default\":{\"unknown\":1},\"$ref\":\"#/default\"}",
  )
  let issues = schema_problems(referenced)
  assert_eq(issues[0].path, "/default.unknown")
  assert_eq(issues[0].kind, UnsupportedFeature)
  assert_true(compile_schema(referenced) is Err(_))
  let regex = ref_compiled(
    "{\"default\":{\"pattern\":\"^x$\"},\"$ref\":\"#/default\"}",
  )
  assert_eq(regex.patterns.length(), 1)
  assert_true(validate_compiled_schema(parse_ok("\"x\""), regex) is Ok([]))
}

///|
test "definitions precheck all values including unused and ordinary definition names" {
  for
    (raw, path, kind) in [
      ("{\"$defs\":false}", "$defs", InvalidSchema),
      ("{\"$defs\":{\"n\":3}}", "$defs.n", InvalidSchema),
      ("{\"$ref\":123}", "$ref", InvalidSchema),
      (
        "{\"$defs\":{\"unused\":{\"unevaluatedProperties\":true}}}",
        "$defs.unused.unevaluatedProperties",
        UnsupportedFeature,
      ),
      (
        "{\"anyOf\":[true,{\"$ref\":\"#/missing\"}]}",
        "anyOf[1].$ref",
        InvalidSchema,
      ),
    ] {
    let problems = schema_problems(parse_ok(raw))
    assert_eq(problems.length(), 1)
    assert_eq(problems[0].path, path)
    assert_eq(problems[0].kind, kind)
  }
  assert_true(
    compile_schema(parse_ok("{\"$defs\":{\"anyOf\":true,\"$ref\":false}}"))
    is Ok(_),
  )
}

///|
test "reference siblings apply independently and do not merge property declarations" {
  assert_eq(
    report(
      "5", "{\"$defs\":{\"n\":{\"type\":\"number\"}},\"$ref\":\"#/$defs/n\",\"minimum\":10}",
    ),
    "(root): it is less than the minimum 10",
  )
  assert_true(
    report(
      "{\"id\":1}", "{\"$defs\":{\"n\":{\"properties\":{\"id\":true}}},\"$ref\":\"#/$defs/n\",\"additionalProperties\":false}",
    ).contains("id: additional property is not allowed"),
  )
  assert_true(
    report(
      "{\"id\":\"bad\"}", "{\"$defs\":{\"n\":true},\"$ref\":\"#/$defs/n\",\"properties\":{\"id\":{\"type\":\"integer\"}}}",
    ).contains("id: it is a string"),
  )
}

///|
test "cycles propagate through every applicator with machine readable paths" {
  for
    (raw, location) in [
      ("{\"$ref\":\"#\"}", "/$ref"),
      ("{\"not\":{\"$ref\":\"#\"}}", "/not/$ref"),
      ("{\"anyOf\":[true,{\"$ref\":\"#\"}]}", "/anyOf/1/$ref"),
      ("{\"allOf\":[false,{\"$ref\":\"#\"}]}", "/allOf/1/$ref"),
      ("{\"oneOf\":[true,{\"$ref\":\"#\"}]}", "/oneOf/1/$ref"),
      (
        "{\"$defs\":{\"a\":{\"$ref\":\"#/$defs/b\"},\"b\":{\"$ref\":\"#/$defs/a\"}},\"$ref\":\"#/$defs/a\"}",
        "/$defs/b/$ref",
      ),
    ] {
    let compiled = ref_compiled(raw)
    match validate_compiled_schema(parse_ok("null"), compiled) {
      Err(error) => {
        assert_eq(error.kind, ReferenceCycle)
        assert_eq(error.instance_path, "")
        assert_eq(error.schema_path, location)
      }
      _ => abort("cycle was silently accepted or became a data violation")
    }
    assert_true(
      validate_schema(parse_ok("null"), parse_ok(raw))
      is Err(EvaluationFailed(_)),
    )
  }
  let compiled = ref_compiled(
    "{\"properties\":{\"a/b~c\":{\"$ref\":\"#/properties/a~1b~0c\"}}}",
  )
  match validate_compiled_schema(parse_ok("{\"a/b~c\":1}"), compiled) {
    Err(error) => {
      assert_eq(error.instance_path, "/a~1b~0c")
      assert_eq(error.schema_path, "/properties/a~1b~0c/$ref")
    }
    _ => abort("cycle not reported")
  }
}

///|
test "finite object and array recursion and sibling reuse do not count as cycles" {
  let raw = "{\"$defs\":{\"node\":{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"integer\"},\"next\":{\"$ref\":\"#/$defs/node\"}}}},\"$ref\":\"#/$defs/node\"}"
  assert_eq(report("{\"value\":1,\"next\":{\"value\":2}}", raw), "")
  assert_true(
    report("{\"value\":1,\"next\":{\"value\":\"x\"}}", raw).contains(
      "next.value: it is a string",
    ),
  )
  assert_eq(
    report("[[[]],[]]", "{\"type\":\"array\",\"items\":{\"$ref\":\"#\"}}"),
    "",
  )
  assert_eq(
    report(
      "1", "{\"$defs\":{\"n\":{\"type\":\"integer\"}},\"allOf\":[{\"$ref\":\"#/$defs/n\"},{\"$ref\":\"#/$defs/n\"}]}",
    ),
    "",
  )
  // Distinct tokens which collide under the legacy dotted display path.
  assert_eq(
    report(
      "{\"a.b\":{},\"a\":{\"b\":{}}}", "{\"type\":\"object\",\"additionalProperties\":{\"$ref\":\"#\"}}",
    ),
    "",
  )
  assert_eq(
    report(
      "{\"\":{\"\":{}}}", "{\"type\":\"object\",\"additionalProperties\":{\"$ref\":\"#\"}}",
    ),
    "",
  )
}

///|
test "shared budgets have exact boundaries and do not leak between invocations" {
  let compiled = ref_compiled("{\"allOf\":[true,true]}")
  assert_true(
    evaluate_schema_with_limits(parse_ok("null"), compiled, 2, 3) is Ok([]),
  )
  match evaluate_schema_with_limits(parse_ok("null"), compiled, 2, 2) {
    Err(error) => {
      assert_eq(error.kind, ResourceLimit)
      assert_eq(error.schema_path, "/allOf/1")
      assert_eq(error.instance_path, "")
    }
    _ => abort("shared node budget was reset in a branch")
  }
  assert_true(
    evaluate_schema_with_limits(parse_ok("null"), compiled, 1, 3)
    is Err({ kind: ResourceLimit, .. }),
  )
  assert_true(
    evaluate_schema_with_limits(parse_ok("null"), compiled, 2, 3) is Ok([]),
  )
  let conditional = ref_compiled(
    "{\"properties\":{\"loop\":{\"$ref\":\"#/properties/loop\"}}}",
  )
  assert_true(
    validate_compiled_schema(parse_ok("{\"loop\":1}"), conditional)
    is Err({ kind: ReferenceCycle, .. }),
  )
  assert_true(validate_compiled_schema(parse_ok("{}"), conditional) is Ok([]))
}

///|
test "snapshot depth and node guards run before recursive copying" {
  let mut deep : @pjson.Json = Bool(value=true)
  for _ in 0..<(schema_compile_depth_limit + 1) {
    deep = Array(items=[deep])
  }
  assert_true(compile_schema(deep) is Err([{ kind: UnsupportedFeature, .. }]))
  assert_true(schema_problems(deep) is [{ kind: UnsupportedFeature, .. }])
  let small = parse_ok("{\"default\":[true,false]}")
  assert_true(schema_snapshot_problem_with_limits(small, 2, 4) is None)
  assert_true(
    schema_snapshot_problem_with_limits(small, 2, 3)
    is Some({ kind: UnsupportedFeature, .. }),
  )
  assert_true(
    schema_snapshot_problem_with_limits(small, 1, 4)
    is Some({ kind: UnsupportedFeature, .. }),
  )
  let cyclic_items : Array[@pjson.Json] = []
  let cyclic : @pjson.Json = Array(items=cyclic_items)
  cyclic_items.push(cyclic)
  assert_true(compile_schema(cyclic) is Err([{ kind: UnsupportedFeature, .. }]))
}

///|
test "boolean and array references execute and unresolved edges retain both locations" {
  for
    (raw, pass) in [
      ("{\"$defs\":{\"flag\":true},\"$ref\":\"#/$defs/flag\"}", true),
      ("{\"$defs\":{\"flag\":false},\"$ref\":\"#/$defs/flag\"}", false),
      ("{\"allOf\":[true],\"$ref\":\"#/allOf/0\"}", true),
    ] {
    match validate_compiled_schema(parse_ok("null"), ref_compiled(raw)) {
      Ok(errors) => assert_eq(errors.is_empty(), pass)
      Err(_) => abort("nonrecursive reference did not complete")
    }
  }
  let issues = schema_problems(
    parse_ok("{\"allOf\":[{\"$ref\":\"#/missing\"},{\"$ref\":\"#/missing\"}]}"),
  )
  assert_eq(issues.length(), 2)
  assert_eq(issues[0].path, "allOf[0].$ref")
  assert_eq(issues[1].path, "allOf[1].$ref")
}
