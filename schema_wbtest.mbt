///|
test "propertyNames checks string names including Unicode and ignores member values" {
  for
    (schema, data, count) in [
      ("{\"propertyNames\":false}", "{}", 0),
      ("{\"propertyNames\":false}", "{\"a\":null}", 1),
      ("{\"propertyNames\":true}", "{\"a\":false}", 0),
      ("{\"propertyNames\":{\"type\":\"integer\"}}", "{\"1\":1}", 1),
      ("{\"propertyNames\":{\"enum\":[\"a\",\"b\"]}}", "{}", 0),
      (
        "{\"propertyNames\":{\"enum\":[\"a\",\"b\"]}}", "{\"a\":1,\"b\":false}",
        0,
      ),
      ("{\"propertyNames\":{\"const\":\"a\"}}", "{\"b\":1}", 1),
      (
        "{\"propertyNames\":{\"pattern\":\"^[a-z][a-z0-9_]*$\"}}", "{\"user_id\":1}",
        0,
      ),
      (
        "{\"propertyNames\":{\"pattern\":\"^[a-z][a-z0-9_]*$\"}}", "{\"User-ID\":1}",
        1,
      ),
      ("{\"propertyNames\":{\"minLength\":1}}", "{\"\":1}", 1),
      ("{\"propertyNames\":{\"maxLength\":1}}", "{\"中文\":1}", 1),
      (
        "{\"propertyNames\":{\"minLength\":1,\"maxLength\":1}}", "{\"😀\":1}",
        0,
      ),
      ("{\"propertyNames\":{\"const\":\"\"}}", "{\"\":false}", 0),
      ("{\"propertyNames\":{\"const\":\"中文\"}}", "{\"中文\":false}", 0),
      ("{\"propertyNames\":{\"const\":\"😀\"}}", "{\"😀\":false}", 0),
      (
        "{\"propertyNames\":{\"const\":\"quote\\\"\"}}", "{\"quote\\\"\":false}",
        0,
      ),
      (
        "{\"propertyNames\":{\"const\":\"line\\nbreak\"}}", "{\"line\\nbreak\":false}",
        0,
      ),
      ("{\"propertyNames\":{\"const\":\"/\"}}", "{\"/\":false}", 0),
      ("{\"propertyNames\":{\"const\":\"~\"}}", "{\"~\":false}", 0),
      ("{\"propertyNames\":{\"const\":\"a/b~c\"}}", "{\"a/b~c\":false}", 0),
      ("{\"propertyNames\":{\"const\":\"a\"}}", "{\"a\":null}", 0),
      ("{\"propertyNames\":{\"const\":\"a\"}}", "{\"a\":false}", 0),
      ("{\"propertyNames\":{\"const\":\"a\"}}", "{\"a\":0}", 0),
      ("{\"propertyNames\":{\"const\":\"a\"}}", "{\"a\":\"\"}", 0),
      ("{\"propertyNames\":{\"const\":\"a\"}}", "{\"a\":[]}", 0),
      ("{\"propertyNames\":{\"const\":\"a\"}}", "{\"a\":[1]}", 0),
      ("{\"propertyNames\":{\"const\":\"a\"}}", "{\"a\":{\"nested\":1}}", 0),
      ("{\"propertyNames\":false}", "null", 0),
      ("{\"propertyNames\":false}", "false", 0),
      ("{\"propertyNames\":false}", "0", 0),
      ("{\"propertyNames\":false}", "\"\"", 0),
      ("{\"propertyNames\":false}", "[]", 0),
      ("{\"propertyNames\":false}", "[{}]", 0),
    ] {
    match validate_schema(parse_ok(data), parse_ok(schema)) {
      Ok(errors) => assert_eq(errors.length(), count)
      Err(_) => abort("property name validation could not complete")
    }
  }
}

///|
test "propertyNames composes independently without declaring additional properties" {
  for
    (schema, data, count) in [
      (
        "{\"propertyNames\":{\"enum\":[\"a\"]},\"additionalProperties\":false}",
        "{\"a\":1}", 1,
      ),
      (
        "{\"properties\":{\"a\":{\"type\":\"integer\"}},\"propertyNames\":{\"const\":\"a\"}}",
        "{\"a\":\"bad\"}", 1,
      ),
      (
        "{\"propertyNames\":{\"maxLength\":1},\"patternProperties\":{\"^a\":{\"type\":\"integer\"}},\"additionalProperties\":false}",
        "{\"a\":\"bad\"}", 1,
      ),
      (
        "{\"propertyNames\":{\"enum\":[\"a\",\"b\"]},\"dependentRequired\":{\"a\":[\"b\"]}}",
        "{\"a\":0}", 1,
      ),
      (
        "{\"propertyNames\":{\"const\":\"a\"},\"dependentSchemas\":{\"a\":false}}",
        "{\"a\":0}", 1,
      ),
      (
        "{\"if\":{\"required\":[\"a\"]},\"then\":{\"propertyNames\":{\"const\":\"a\"}},\"else\":{\"propertyNames\":true}}",
        "{\"a\":0,\"b\":1}", 1,
      ),
      (
        "{\"propertyNames\":{\"if\":{\"pattern\":\"^a\"},\"then\":{\"maxLength\":1},\"else\":{\"const\":\"b\"}}}",
        "{\"a\":1,\"b\":0}", 0,
      ),
      (
        "{\"propertyNames\":{\"if\":{\"pattern\":\"^a\"},\"then\":{\"maxLength\":1},\"else\":{\"const\":\"b\"}}}",
        "{\"aa\":0,\"c\":0}", 2,
      ),
      (
        "{\"propertyNames\":{\"allOf\":[{\"minLength\":1},{\"maxLength\":1}]}}",
        "{\"\":1,\"ab\":2}", 2,
      ),
      (
        "{\"propertyNames\":{\"anyOf\":[{\"const\":\"a\"},{\"const\":\"b\"}]}}",
        "{\"a\":1,\"b\":2}", 0,
      ),
      (
        "{\"propertyNames\":{\"oneOf\":[{\"const\":\"a\"},{\"type\":\"string\"}]}}",
        "{\"a\":1}", 1,
      ),
      ("{\"propertyNames\":{\"not\":{\"const\":\"a\"}}}", "{\"b\":1}", 0),
      ("{\"if\":true,\"else\":{\"propertyNames\":true}}", "{}", 0),
      (
        "{\"dependentSchemas\":{\"a\":{\"propertyNames\":true}}}", "{\"a\":null}",
        0,
      ),
    ] {
    match validate_schema(parse_ok(data), parse_ok(schema)) {
      Ok(errors) => assert_eq(errors.length(), count)
      Err(_) => abort("property name validation could not complete")
    }
  }
}

///|
test "property name diagnostics identify names in order at the containing object" {
  match
    validate_schema(
      parse_ok("{\"data\":{\"bad-name\":1,\"A\":0,\"good\":null}}"),
      parse_ok(
        "{\"properties\":{\"data\":{\"propertyNames\":{\"pattern\":\"^[a-z]+$\"}}}}",
      ),
    ) {
    Ok(errors) => {
      assert_eq(errors.length(), 2)
      assert_eq(errors[0].path, "data")
      assert_eq(errors[1].path, "data")
      assert_eq(
        errors[0].message,
        "property name \"bad-name\": it does not match the pattern \"^[a-z]+$\"",
      )
      assert_eq(
        errors[1].message,
        "property name \"A\": it does not match the pattern \"^[a-z]+$\"",
      )
    }
    _ => abort("name violations changed order or path")
  }
  for
    (name, expected) in [
      ("", "property name \"\": it is rejected by the false schema"),
      ("中文", "property name \"中文\": it is rejected by the false schema"),
      ("😀", "property name \"😀\": it is rejected by the false schema"),
      (
        "quote\"", "property name \"quote\\\"\": it is rejected by the false schema",
      ),
      (
        "line\nbreak", "property name \"line\\nbreak\": it is rejected by the false schema",
      ),
      ("/", "property name \"/\": it is rejected by the false schema"),
      ("~", "property name \"~\": it is rejected by the false schema"),
      ("a/b~c", "property name \"a/b~c\": it is rejected by the false schema"),
    ] {
    let value = @pjson.Object(members=[(name, parse_ok("null"))])
    match validate_schema(value, parse_ok("{\"propertyNames\":false}")) {
      Ok([error]) => {
        assert_eq(error.path, "")
        assert_eq(error.message, expected)
        assert_eq(render_schema_error(error).split("\n").length(), 1)
      }
      _ => abort("special name was not diagnosed as a name")
    }
  }
}

///|
test "propertyNames prechecks all schemas including inactive names and branches" {
  for
    (raw, location, kind) in [
      ("{\"propertyNames\":1}", "propertyNames", InvalidSchema),
      ("{\"propertyNames\":\"x\"}", "propertyNames", InvalidSchema),
      ("{\"propertyNames\":[]}", "propertyNames", InvalidSchema),
      ("{\"propertyNames\":null}", "propertyNames", InvalidSchema),
      (
        "{\"propertyNames\":{\"pattern\":\"[\"}}",
        "propertyNames.pattern",
        InvalidSchema,
      ),
      (
        "{\"propertyNames\":{\"minLength\":-1}}",
        "propertyNames.minLength",
        InvalidSchema,
      ),
      (
        "{\"propertyNames\":{\"$ref\":\"#/missing\"}}",
        "propertyNames.$ref",
        InvalidSchema,
      ),
      (
        "{\"propertyNames\":{\"unevaluatedProperties\":true}}",
        "propertyNames.unevaluatedProperties",
        UnsupportedFeature,
      ),
      (
        "{\"if\":true,\"else\":{\"propertyNames\":{\"pattern\":\"[\"}}}",
        "else.propertyNames.pattern",
        InvalidSchema,
      ),
    ] {
    match compile_schema(parse_ok(raw)) {
      Err(problems) => {
        assert_eq(problems.length(), 1)
        assert_eq(problems[0].path, location)
        assert_eq(problems[0].kind, kind)
      }
      _ => abort("invalid property name schema compiled")
    }
  }
}

///|
test "object dependencies trigger on presence and remain directional" {
  for
    (schema, data, count) in [
      ("{\"dependentRequired\":{\"a\":[\"b\",\"c\"]}}", "{}", 0),
      ("{\"dependentRequired\":{\"a\":[\"b\",\"c\"]}}", "{\"a\":1}", 2),
      ("{\"dependentRequired\":{\"a\":[\"b\",\"c\"]}}", "{\"a\":1,\"b\":0}", 1),
      (
        "{\"dependentRequired\":{\"a\":[\"b\",\"c\"]}}", "{\"a\":1,\"b\":false,\"c\":null}",
        0,
      ),
      ("{\"dependentRequired\":{\"a\":[\"b\"]}}", "{\"a\":null}", 1),
      ("{\"dependentRequired\":{\"a\":[\"b\"]}}", "{\"a\":null,\"b\":null}", 0),
      ("{\"dependentRequired\":{\"a\":[\"b\"]}}", "{\"a\":false}", 1),
      (
        "{\"dependentRequired\":{\"a\":[\"b\"]}}", "{\"a\":false,\"b\":false}", 0,
      ),
      ("{\"dependentRequired\":{\"a\":[\"b\"]}}", "{\"a\":0}", 1),
      ("{\"dependentRequired\":{\"a\":[\"b\"]}}", "{\"a\":0,\"b\":0}", 0),
      ("{\"dependentRequired\":{\"a\":[\"b\"]}}", "{\"a\":\"\"}", 1),
      ("{\"dependentRequired\":{\"a\":[\"b\"]}}", "{\"a\":\"\",\"b\":\"\"}", 0),
      ("{\"dependentRequired\":{\"a\":[]}}", "{\"a\":1}", 0),
      ("{\"dependentRequired\":{}}", "{}", 0),
      ("{\"dependentRequired\":{\"a\":[\"a\"]}}", "{\"a\":1}", 0),
      ("{\"dependentRequired\":{\"a\":[\"b\"]}}", "{\"b\":1}", 0),
      ("{\"dependentRequired\":{\"a\":[\"b\"],\"b\":[\"a\"]}}", "{\"a\":1}", 1),
      (
        "{\"dependentRequired\":{\"a\":[\"b\"],\"b\":[\"a\"]}}", "{\"a\":1,\"b\":null}",
        0,
      ),
      (
        "{\"dependentRequired\":{\"a\":[\"b\"]},\"dependentSchemas\":{\"a\":false}}",
        "null", 0,
      ),
      (
        "{\"dependentRequired\":{\"a\":[\"b\"]},\"dependentSchemas\":{\"a\":false}}",
        "false", 0,
      ),
      (
        "{\"dependentRequired\":{\"a\":[\"b\"]},\"dependentSchemas\":{\"a\":false}}",
        "0", 0,
      ),
      (
        "{\"dependentRequired\":{\"a\":[\"b\"]},\"dependentSchemas\":{\"a\":false}}",
        "\"\"", 0,
      ),
      (
        "{\"dependentRequired\":{\"a\":[\"b\"]},\"dependentSchemas\":{\"a\":false}}",
        "[]", 0,
      ),
      (
        "{\"dependentRequired\":{\"a\":[\"b\"]},\"dependentSchemas\":{\"a\":false}}",
        "[{\"a\":1}]", 0,
      ),
    ] {
    match validate_schema(parse_ok(data), parse_ok(schema)) {
      Ok(errors) => assert_eq(errors.length(), count)
      Err(_) => abort("dependency validation unexpectedly failed")
    }
  }
}

///|
test "dependent schemas validate the entire object and keep sibling scopes separate" {
  for
    (schema, data, count) in [
      ("{\"dependentSchemas\":{\"a\":false}}", "{}", 0),
      ("{\"dependentSchemas\":{\"a\":false}}", "{\"a\":null}", 1),
      ("{\"dependentSchemas\":{\"a\":true}}", "{\"a\":false}", 0),
      ("{\"dependentSchemas\":{}}", "{}", 0),
      (
        "{\"dependentSchemas\":{\"a\":{\"required\":[\"b\"]}}}", "{\"a\":{\"b\":1}}",
        1,
      ),
      (
        "{\"dependentSchemas\":{\"a\":{\"type\":\"object\",\"required\":[\"b\"]}}}",
        "{\"a\":null,\"b\":1}", 0,
      ),
      (
        "{\"dependentSchemas\":{\"a\":false,\"b\":false}}", "{\"a\":0,\"b\":\"\"}",
        2,
      ),
      (
        "{\"properties\":{\"a\":true},\"dependentSchemas\":{\"a\":{\"additionalProperties\":false}}}",
        "{\"a\":1}", 1,
      ),
      (
        "{\"properties\":{\"a\":true},\"additionalProperties\":false,\"dependentSchemas\":{\"a\":{\"properties\":{\"b\":true}}}}",
        "{\"a\":1,\"b\":1}", 1,
      ),
      (
        "{\"allOf\":[{\"dependentRequired\":{\"a\":[\"b\"]}},{\"dependentSchemas\":{\"a\":{\"properties\":{\"b\":{\"type\":\"string\"}}}}}]}",
        "{\"a\":0,\"b\":1}", 1,
      ),
      (
        "{\"if\":{\"required\":[\"a\"]},\"then\":{\"dependentRequired\":{\"a\":[\"b\"]}},\"else\":true}",
        "{\"a\":0}", 1,
      ),
      (
        "{\"dependentSchemas\":{\"a\":{\"if\":{\"required\":[\"b\"]},\"then\":{\"required\":[\"c\"]}}}}",
        "{\"a\":0,\"b\":0}", 1,
      ),
    ] {
    match validate_schema(parse_ok(data), parse_ok(schema)) {
      Ok(errors) => assert_eq(errors.length(), count)
      Err(_) => abort("dependency validation unexpectedly failed")
    }
  }
}

///|
test "dependency diagnostics follow schema order and escape arbitrary names" {
  let schema = parse_ok(
    "{\"dependentRequired\":{\"a\":[\"c\",\"b\"],\"b\":[\"d\"]}}",
  )
  match validate_schema(parse_ok("{\"a\":null,\"b\":false}"), schema) {
    Ok(errors) => {
      assert_eq(errors.length(), 2)
      assert_eq(errors[0].message, "member \"a\" requires member \"c\"")
      assert_eq(errors[1].message, "member \"b\" requires member \"d\"")
    }
    _ => abort("expected ordered dependency violations")
  }
  for
    (name, expected) in [
      ("", "member \"\" requires member \"!\""),
      ("中文", "member \"中文\" requires member \"中文!\""),
      ("quote\"", "member \"quote\\\"\" requires member \"quote\\\"!\""),
      (
        "line\nbreak", "member \"line\\nbreak\" requires member \"line\\nbreak!\"",
      ),
      ("/", "member \"/\" requires member \"/!\""),
      ("~", "member \"~\" requires member \"~!\""),
      ("a/b~c", "member \"a/b~c\" requires member \"a/b~c!\""),
    ] {
    let needed = name + "!"
    let dependency = @pjson.Object(members=[
      (
        "dependentRequired",
        @pjson.Object(members=[
          (name, @pjson.Array(items=[@pjson.Text(value=needed)])),
        ]),
      ),
    ])
    let schema = @pjson.Object(members=[
      ("properties", @pjson.Object(members=[("data", dependency)])),
    ])
    let members = [(name, parse_ok("null"))]
    let data = @pjson.Object(members=[("data", @pjson.Object(members~))])
    match validate_schema(data, schema) {
      Ok([error]) => {
        assert_eq(error.path, "data")
        assert_eq(error.message, expected)
        assert_eq(error.message.split("\n").length(), 1)
      }
      _ => abort("special dependency name was not checked")
    }
    members.push((needed, parse_ok("false")))
    assert_true(validate_schema(data, schema) is Ok([]))
  }
}

///|
test "dependency prechecks inspect every name list and inactive subschema" {
  for
    (raw, location, kind) in [
      ("{\"dependentRequired\":[]}", "dependentRequired", InvalidSchema),
      ("{\"dependentSchemas\":[]}", "dependentSchemas", InvalidSchema),
      (
        "{\"dependentRequired\":{\"a\":null}}",
        "dependentRequired.a",
        InvalidSchema,
      ),
      (
        "{\"dependentRequired\":{\"a\":[1]}}",
        "dependentRequired.a[0]",
        InvalidSchema,
      ),
      (
        "{\"dependentRequired\":{\"a\":[\"x\",\"x\"]}}",
        "dependentRequired.a[1]",
        InvalidSchema,
      ),
      (
        "{\"dependentSchemas\":{\"a\":null}}",
        "dependentSchemas.a",
        InvalidSchema,
      ),
      (
        "{\"dependentSchemas\":{\"a\":{\"type\":3}}}",
        "dependentSchemas.a.type",
        InvalidSchema,
      ),
      (
        "{\"dependentSchemas\":{\"a\":{\"pattern\":\"[\"}}}",
        "dependentSchemas.a.pattern",
        InvalidSchema,
      ),
      (
        "{\"dependentSchemas\":{\"a\":{\"$ref\":\"#/missing\"}}}",
        "dependentSchemas.a.$ref",
        InvalidSchema,
      ),
      (
        "{\"dependentSchemas\":{\"a\":{\"unevaluatedProperties\":true}}}",
        "dependentSchemas.a.unevaluatedProperties",
        UnsupportedFeature,
      ),
      ("{\"dependencies\":{}}", "dependencies", UnsupportedFeature),
    ] {
    match compile_schema(parse_ok(raw)) {
      Err(problems) => {
        assert_eq(problems.length(), 1)
        assert_eq(problems[0].path, location)
        assert_eq(problems[0].kind, kind)
      }
      _ => abort("invalid dependency escaped compilation")
    }
  }
  assert_true(
    compile_schema(
      parse_ok(
        "{\"dependentRequired\":{\"anyOf\":[\"multipleOf\",\"dependentSchemas\"]}}",
      ),
    )
    is Ok(_),
  )
  assert_true(
    compile_schema(parse_ok("{\"dependentSchemas\":{\"anyOf\":true}}")) is Ok(_),
  )
  assert_true(
    compile_schema(parse_ok("{\"const\":{\"dependentSchemas\":{\"bad\":3}}}"))
    is Ok(_),
  )
  assert_true(
    compile_schema(parse_ok("{\"enum\":[{\"dependentRequired\":3}]}")) is Ok(_),
  )
}

///|
/// The report of checking a document against a schema, written the way a report
/// reads: one line per error, in the order they were found, and nothing at all
/// when the document matches.
fn report(document : String, schema : String) -> String {
  match validate_schema(parse_ok(document), parse_ok(schema)) {
    Ok(errors) => errors.map(render_schema_error).join("\n")
    Err(_) => abort("expected a supported schema")
  }
}

///|
/// The report of reading a schema itself, written the same way.
fn problems(schema : String) -> String {
  schema_problems(parse_ok(schema)).map(render_schema_problem).join("\n")
}

///|
test "conditional selection discards predicate errors and ignores absent branches" {
  for
    (schema, data, count) in [
      ("{\"if\":true,\"then\":false,\"else\":true}", "null", 1),
      ("{\"if\":false,\"then\":false,\"else\":true}", "null", 0),
      ("{\"if\":true,\"then\":true,\"else\":false}", "null", 0),
      ("{\"if\":false,\"then\":true,\"else\":false}", "null", 1),
      (
        "{\"if\":{\"type\":\"integer\"},\"then\":{\"minimum\":10},\"else\":{\"const\":\"x\"}}",
        "12", 0,
      ),
      (
        "{\"if\":{\"type\":\"integer\"},\"then\":{\"minimum\":10},\"else\":{\"const\":\"x\"}}",
        "2", 1,
      ),
      (
        "{\"if\":{\"type\":\"integer\"},\"then\":{\"minimum\":10},\"else\":{\"const\":\"x\"}}",
        "\"x\"", 0,
      ),
      (
        "{\"if\":{\"type\":\"integer\"},\"then\":{\"minimum\":10},\"else\":{\"const\":\"x\"}}",
        "true", 1,
      ),
      ("{\"if\":false,\"then\":false}", "null", 0),
      ("{\"if\":true,\"else\":false}", "null", 0),
      ("{\"if\":false}", "null", 0),
      ("{\"if\":{\"type\":\"integer\"}}", "\"x\"", 0),
      ("{\"then\":false}", "null", 0),
      ("{\"else\":false}", "null", 0),
      ("{\"then\":false,\"else\":false}", "null", 0),
    ] {
    match validate_schema(parse_ok(data), parse_ok(schema)) {
      Ok(errors) => assert_eq(errors.length(), count)
      Err(_) => abort("valid conditional could not complete")
    }
  }
  assert_eq(
    report(
      "true", "{\"if\":{\"type\":\"integer\"},\"else\":{\"type\":\"string\"}}",
    ),
    "(root): it is a boolean where the schema expects a string",
  )
  let business = "{\"type\":\"object\",\"if\":{\"required\":[\"kind\"],\"properties\":{\"kind\":{\"const\":\"business\"}}},\"then\":{\"required\":[\"taxId\"]},\"else\":{\"required\":[\"name\"]}}"
  assert_eq(report("{\"kind\":\"business\",\"taxId\":\"T1\"}", business), "")
  assert_eq(report("{\"kind\":\"personal\",\"name\":\"Li\"}", business), "")
  assert_eq(report("{\"name\":\"Li\"}", business), "")
  assert_true(report("{\"kind\":\"business\"}", business).contains("taxId"))
  assert_true(
    report(
      "{\"name\":\"Li\"}", "{\"if\":{\"properties\":{\"kind\":{\"const\":\"business\"}}},\"then\":{\"required\":[\"taxId\"]},\"else\":{\"required\":[\"name\"]}}",
    ).contains("taxId"),
  )
}

///|
test "conditional sibling order and allOf scopes preserve independent constraints" {
  let keywords = [
    "\"if\":{\"const\":1}", "\"then\":{\"minimum\":5}", "\"else\":{\"maximum\":0}",
  ]
  for data in ["-1", "0", "1", "4", "8"] {
    let expected = report(data, "{" + keywords.join(",") + "}")
    for
      order in [
        [0, 1, 2],
        [0, 2, 1],
        [1, 0, 2],
        [1, 2, 0],
        [2, 0, 1],
        [2, 1, 0],
      ] {
      assert_eq(
        report(data, "{" + order.map(fn(i) { keywords[i] }).join(",") + "}"),
        expected,
      )
    }
  }
  assert_eq(
    report(
      "null", "{\"allOf\":[{\"if\":true},{\"then\":false},{\"else\":false}]}",
    ),
    "",
  )
  assert_eq(report("null", "{\"if\":true,\"allOf\":[{\"then\":false}]}"), "")
  assert_eq(report("null", "{\"then\":false,\"allOf\":[{\"if\":true}]}"), "")
  match
    validate_schema(
      parse_ok("{}"),
      parse_ok(
        "{\"type\":\"array\",\"required\":[\"tag\"],\"if\":true,\"then\":false}",
      ),
    ) {
    Ok(errors) => assert_eq(errors.length(), 3)
    _ => abort("sibling constraints were bypassed")
  }
}

///|
test "conditions nested in items properties contains and predicates select correctly" {
  let schema = "{\"properties\":{\"orders\":{\"items\":{\"if\":{\"type\":\"integer\"},\"then\":{\"minimum\":0},\"else\":{\"type\":\"string\"}}}}}"
  assert_eq(report("{\"orders\":[1,\"x\"]}", schema), "")
  let failures = report("{\"orders\":[-1,true]}", schema)
  assert_true(failures.contains("orders[0]: it is less than the minimum 0"))
  assert_true(
    failures.contains(
      "orders[1]: it is a boolean where the schema expects a string",
    ),
  )
  assert_false(failures.contains("expects an integer"))
  let contains = "{\"contains\":{\"if\":{\"type\":\"integer\"},\"then\":{\"minimum\":2},\"else\":false},\"minContains\":2}"
  assert_eq(report("[2,\"x\",3,1]", contains), "")
  assert_eq(
    report("[1,\"x\"]", contains),
    "(root): contains matched 0 items; expected at least 2",
  )
  let nested = "{\"if\":{\"if\":{\"type\":\"integer\"},\"then\":{\"minimum\":10},\"else\":false},\"then\":{\"maximum\":20},\"else\":{\"const\":0}}"
  for data in ["0", "15"] {
    assert_eq(report(data, nested), "")
  }
  assert_eq(report("21", nested), "(root): it is more than the maximum 20")
  assert_eq(
    report("1", nested),
    "(root): it is not the constant value the schema specifies",
  )
}

///|
test "every conditional branch is prechecked even when ignored or never selected" {
  for
    (raw, path, kind) in [
      ("{\"if\":null}", "if", InvalidSchema),
      ("{\"then\":123}", "then", InvalidSchema),
      ("{\"else\":[]}", "else", InvalidSchema),
      (
        "{\"if\":true,\"else\":{\"unevaluatedProperties\":true}}",
        "else.unevaluatedProperties",
        UnsupportedFeature,
      ),
      (
        "{\"if\":false,\"then\":{\"pattern\":\"[\"}}",
        "then.pattern",
        InvalidSchema,
      ),
      ("{\"else\":{\"$ref\":\"#/missing\"}}", "else.$ref", InvalidSchema),
      (
        "{\"then\":{\"$dynamicRef\":\"#x\"}}",
        "then.$dynamicRef",
        UnsupportedFeature,
      ),
      (
        "{\"if\":{\"minLength\":-1},\"then\":true}",
        "if.minLength",
        InvalidSchema,
      ),
      (
        "{\"properties\":{\"x\":{\"if\":false,\"then\":{\"required\":123}}}}",
        "properties.x.then.required",
        InvalidSchema,
      ),
    ] {
    let issues = schema_problems(parse_ok(raw))
    assert_eq(issues.length(), 1)
    assert_eq(issues[0].path, path)
    assert_eq(issues[0].kind, kind)
    assert_true(
      validate_schema(parse_ok("{}"), parse_ok(raw)) is Err(SchemaProblems(_)),
    )
  }
  assert_true(
    compile_schema(
      parse_ok(
        "{\"const\":{\"if\":null,\"then\":3},\"default\":{\"else\":[]},\"enum\":[{\"if\":false}]}",
      ),
    )
    is Ok(_),
  )
}

///|
test "a document the schema describes is not reported on" {
  let schema =
    #|{
    #|  "type": "object",
    #|  "required": ["id", "name"],
    #|  "properties": {
    #|    "id": { "type": "integer", "minimum": 1 },
    #|    "name": { "type": "string", "minLength": 1, "maxLength": 20, "pattern": "^[A-Za-z ]+$" },
    #|    "tags": { "type": "array", "items": { "type": "string" } },
    #|    "kind": { "enum": ["a", "b", null] }
    #|  }
    #|}
  let document =
    #|{
    #|  "id": 7,
    #|  "name": "Moon JSON",
    #|  "tags": ["json", "cli"],
    #|  "kind": null
    #|}
  assert_eq(report(document, schema), "")
  // A member the schema does not name is left as it is, and a document holding
  // more than the schema describes still matches it.
  assert_eq(
    report(
      "{\"id\":1,\"name\":\"a\",\"tags\":[],\"kind\":\"b\",\"extra\":[1,{\"b\":{}}]}",
      schema,
    ),
    "",
  )
}

///|
test "type asks for the kind of value it names" {
  assert_eq(
    report("\"x\"", "{\"type\":\"number\"}"),
    "(root): it is a string where the schema expects a number",
  )
  assert_eq(
    report("null", "{\"type\":\"object\"}"),
    "(root): it is null where the schema expects an object",
  )
  assert_eq(
    report("[]", "{\"type\":\"boolean\"}"),
    "(root): it is an array where the schema expects a boolean",
  )
  assert_eq(
    report("{\"a\":1}", "{\"type\":\"string\"}"),
    "(root): it is an object where the schema expects a string",
  )
  // A list of names is any one of them, and the message reads the way the list
  // is written.
  assert_eq(report("1", "{\"type\":[\"string\",\"number\"]}"), "")
  assert_eq(
    report("true", "{\"type\":[\"string\",\"number\"]}"),
    "(root): it is a boolean where the schema expects a string or a number",
  )
  assert_eq(
    report("null", "{\"type\":[\"string\",\"number\",\"boolean\"]}"),
    "(root): it is null where the schema expects a string, a number or a boolean",
  )
  // A type the value is not is a type it is not, whether the schema wants an
  // array or nothing at all.
  assert_eq(
    report("1", "{\"type\":\"array\"}"),
    "(root): it is a number where the schema expects an array",
  )
  assert_eq(
    report("1", "{\"type\":\"null\"}"),
    "(root): it is a number where the schema expects null",
  )
  assert_eq(report("null", "{\"type\":\"null\"}"), "")
  // The type of a value is asked about where the value is, and the path says
  // where that is.
  assert_eq(
    report(
      "{\"a\":{\"b\":[true]}}", "{\"properties\":{\"a\":{\"properties\":{\"b\":{\"items\":{\"type\":\"number\"}}}}}}",
    ),
    "a.b[0]: it is a boolean where the schema expects a number",
  )
}

///|
test "an integer is a number with nothing after the point" {
  assert_eq(report("1", "{\"type\":\"integer\"}"), "")
  assert_eq(report("-40", "{\"type\":\"integer\"}"), "")
  // Every integer is a number as well.
  assert_eq(report("1.5", "{\"type\":\"number\"}"), "")
  assert_eq(
    report("1.5", "{\"type\":\"integer\"}"),
    "(root): it is a number where the schema expects an integer",
  )
  // Decimal notation and exponents are interpreted by their mathematical value.
  assert_eq(report("1.0", "{\"type\":\"integer\"}"), "")
  assert_eq(report("1e3", "{\"type\":\"integer\"}"), "")
  assert_eq(
    report("1.05", "{\"type\":\"integer\"}"),
    "(root): it is a number where the schema expects an integer",
  )
  // A numeral too long for a double is read as it was written: rounding it to
  // fit would have turned thirty digits of whole number into one with a
  // fraction, and the answer is about the document rather than about the reader.
  assert_eq(
    report("123456789012345678901234567890", "{\"type\":\"integer\"}"),
    "",
  )
}

///|
test "required names the members an object has to have" {
  let schema = "{\"type\":\"object\",\"required\":[\"id\",\"name\"]}"
  assert_eq(report("{\"id\":1,\"name\":\"a\"}", schema), "")
  // Every missing member is reported, in the order the schema lists them rather
  // than the order they were looked for.
  assert_eq(
    report("{}", schema),
    "(root): required member \"id\" is missing\n" +
    "(root): required member \"name\" is missing",
  )
  assert_eq(
    report("{\"id\":1}", schema),
    "(root): required member \"name\" is missing",
  )
  // A member that is there is there whatever it holds, a null among them: what a
  // member has to be is what `properties` says about it.
  assert_eq(report("{\"id\":null,\"name\":null}", schema), "")
  // A `required` is about an object, and a value that is not one is not a
  // document with members missing: `type` is the keyword that says so.
  assert_eq(report("[]", "{\"required\":[\"id\"]}"), "")
  assert_eq(report("5", "{\"required\":[\"id\"]}"), "")
}

///|
test "properties checks the members it names and leaves the rest" {
  let schema =
    #|{
    #|  "properties": {
    #|    "a": { "properties": { "b": { "type": "number" } } },
    #|    "list": { "items": { "properties": { "c": { "type": "boolean" } } } }
    #|  }
    #|}
  assert_eq(report("{\"a\":{\"b\":1},\"list\":[{\"c\":true}]}", schema), "")
  assert_eq(
    report("{\"a\":{\"b\":\"x\"},\"list\":[{\"c\":true},{\"c\":1}]}", schema),
    "a.b: it is a string where the schema expects a number\n" +
    "list[1].c: it is a number where the schema expects a boolean",
  )
  // The report follows the schema, so the order of the members in the document
  // is not the order of the report.
  assert_eq(
    report("{\"list\":[{\"c\":1}],\"a\":{\"b\":\"x\"}}", schema),
    "a.b: it is a string where the schema expects a number\n" +
    "list[0].c: it is a number where the schema expects a boolean",
  )
  // A member the document does not have is not checked here, and a member the
  // schema does not name is left alone.
  assert_eq(report("{}", schema), "")
  assert_eq(report("{\"z\":{\"b\":\"x\"}}", schema), "")
  assert_eq(report("5", schema), "")
}

///|
test "items checks every element of an array" {
  let schema = "{\"items\":{\"type\":\"number\",\"minimum\":0}}"
  assert_eq(report("[1,2,3]", schema), "")
  assert_eq(report("[]", schema), "")
  assert_eq(
    report("[1,\"x\",-2]", schema),
    "[1]: it is a string where the schema expects a number\n" +
    "[2]: it is less than the minimum 0",
  )
  // An array of arrays is checked all the way down, and the path says which
  // element each answer is about.
  assert_eq(
    report("[[1],[2,\"x\"]]", "{\"items\":{\"items\":{\"type\":\"number\"}}}"),
    "[1][1]: it is a string where the schema expects a number",
  )
  // An `items` is about an array, and a value that is not one has no elements to
  // check.
  assert_eq(report("{\"a\":1}", schema), "")
}

///|
test "enum is the list of values a document has to be one of" {
  assert_eq(report("\"b\"", "{\"enum\":[\"a\",\"b\"]}"), "")
  assert_eq(
    report("\"c\"", "{\"enum\":[\"a\",\"b\"]}"),
    "(root): it is not one of the 2 values the schema lists",
  )
  // One value reads as one value, and a list with nothing in it is a schema no
  // document can match.
  assert_eq(
    report("true", "{\"enum\":[false,0]}"),
    "(root): it is not one of the 2 values the schema lists",
  )
  assert_eq(
    report("1", "{\"enum\":[2]}"),
    "(root): it is not the value the schema lists",
  )
  assert_eq(
    report("1", "{\"enum\":[]}"),
    "(root): it is not one of the values the schema lists",
  )
  assert_eq(report("null", "{\"enum\":[null,false]}"), "")
  // A number is the number it stands for rather than the text it was written
  // with, and an object holds its members whatever order they were written in.
  assert_eq(report("1.0", "{\"enum\":[1]}"), "")
  assert_eq(report("{\"a\":1,\"b\":2}", "{\"enum\":[{\"b\":2,\"a\":1}]}"), "")
  assert_eq(
    report("{\"a\":1,\"b\":3}", "{\"enum\":[{\"b\":2,\"a\":1}]}"),
    "(root): it is not the value the schema lists",
  )
  // An object is the value listed only when it has the same members: a member
  // the listed value does not have is one the document brought, and a member the
  // document does not have is one it left out, and both make them two values.
  assert_eq(
    report("{\"a\":1,\"b\":2}", "{\"enum\":[{\"a\":1,\"c\":2}]}"),
    "(root): it is not the value the schema lists",
  )
  assert_eq(
    report("{\"a\":1,\"b\":2}", "{\"enum\":[{\"a\":1}]}"),
    "(root): it is not the value the schema lists",
  )
  assert_eq(
    report("{\"a\":1}", "{\"enum\":[{\"a\":1,\"b\":2}]}"),
    "(root): it is not the value the schema lists",
  )
  // An array holds its values in the order it wrote them, and a value of another
  // kind is never one of the values listed.
  assert_eq(report("[1,2]", "{\"enum\":[[1,2]]}"), "")
  assert_eq(
    report("[2,1]", "{\"enum\":[[1,2]]}"),
    "(root): it is not the value the schema lists",
  )
  assert_eq(
    report("\"1\"", "{\"enum\":[1]}"),
    "(root): it is not the value the schema lists",
  )
}

///|
test "minimum and maximum include the bound they name" {
  let schema = "{\"minimum\":5,\"maximum\":10}"
  assert_eq(report("5", schema), "")
  assert_eq(report("10", schema), "")
  assert_eq(report("4.999", schema), "(root): it is less than the minimum 5")
  assert_eq(report("10.5", schema), "(root): it is more than the maximum 10")
  // The bound is read as the number it is, so a bound written with a point is
  // the same bound, and the message says it the way the schema wrote it.
  assert_eq(
    report("4", "{\"minimum\":5.0}"),
    "(root): it is less than the minimum 5.0",
  )
  // A bound is about a number, and a value that is not one is left to `type`.
  assert_eq(report("\"5\"", schema), "")
}

///|
test "minLength and maxLength count characters" {
  let schema = "{\"minLength\":3,\"maxLength\":5}"
  assert_eq(report("\"abc\"", schema), "")
  assert_eq(report("\"abcde\"", schema), "")
  assert_eq(
    report("\"ab\"", schema),
    "(root): it is 2 characters long, and the schema asks for at least 3",
  )
  assert_eq(
    report("\"abcdef\"", schema),
    "(root): it is 6 characters long, and the schema asks for at most 5",
  )
  // One character reads as one character, and a character outside the basic
  // plane is one character as it is everywhere else in this tool: counting the
  // code units the text is stored in would have made it two.
  assert_eq(
    report("\"a\"", "{\"minLength\":2}"),
    "(root): it is 1 character long, and the schema asks for at least 2",
  )
  assert_eq(report("\"😀😀\"", "{\"minLength\":2,\"maxLength\":2}"), "")
  assert_eq(
    report("\"😀😀😀\"", "{\"maxLength\":2}"),
    "(root): it is 3 characters long, and the schema asks for at most 2",
  )
  // A length is about a string, and a value of another kind has no length here.
  assert_eq(report("1", schema), "")
}

///|
test "a pattern is looked for in the string" {
  let schema = "{\"pattern\":\"^[a-z]+$\"}"
  assert_eq(report("\"abc\"", schema), "")
  assert_eq(
    report("\"aBc\"", schema),
    "(root): it does not match the pattern \"^[a-z]+$\"",
  )
  // A pattern is found anywhere in the string unless it anchors itself, which is
  // what a pattern with no `^` in it means.
  assert_eq(report("\"a1b\"", "{\"pattern\":\"[0-9]\"}"), "")
  assert_eq(
    report("\"ab\"", "{\"pattern\":\"[0-9]\"}"),
    "(root): it does not match the pattern \"[0-9]\"",
  )
  // A pattern is about a string, and a value of another kind is not one.
  assert_eq(report("1", schema), "")
}

///|
test "every violation is reported rather than the first" {
  let schema =
    #|{
    #|  "required": ["id", "name"],
    #|  "properties": {
    #|    "id": { "type": "integer" },
    #|    "name": { "type": "string" },
    #|    "kind": { "enum": ["a", "b"] }
    #|  }
    #|}
  assert_eq(
    report("{\"id\":\"one\",\"name\":3,\"kind\":\"z\"}", schema),
    "id: it is a string where the schema expects an integer\n" +
    "name: it is a number where the schema expects a string\n" +
    "kind: it is not one of the 2 values the schema lists",
  )
  assert_eq(
    report("{}", schema),
    "(root): required member \"id\" is missing\n" +
    "(root): required member \"name\" is missing",
  )
  // Two keywords about one value are two answers about it, in the order the
  // schema asks them.
  assert_eq(
    report("\"ab\"", "{\"type\":\"string\",\"minLength\":3,\"pattern\":\"^c\"}"),
    "(root): it is 2 characters long, and the schema asks for at least 3\n" +
    "(root): it does not match the pattern \"^c\"",
  )
}

///|
test "unsupported keywords refuse the entire schema" {
  let schema =
    #|{
    #|  "$schema": "https://json-schema.org/draft/2020-12/schema",
    #|  "title": "A person",
    #|  "description": 3,
    #|  "type": "object",
    #|  "additionalProperties": false,
    #|  "$ref": "other.json#/$defs/person",
    #|  "anyOf": [3, "nonsense"],
    #|  "properties": {
    #|    "id": { "type": "integer", "unevaluatedProperties": false, "format": 7 }
    #|  }
    #|}
  assert_true(compile_schema(parse_ok(schema)) is Err(_))
  assert_true(
    problems(schema).contains("$ref: external references are not supported"),
  )
  assert_true(
    problems(schema).contains(
      "properties.id.unevaluatedProperties: keyword is not supported",
    ),
  )
  assert_true(
    validate_schema(parse_ok("{\"id\":1}"), parse_ok(schema)) is Err(_),
  )
}

///|
test "a schema this tool cannot read says where" {
  assert_eq(
    problems("[]"),
    "(root): a schema must be an object or a boolean, but this is an array",
  )
  assert_eq(
    problems("\"x\""),
    "(root): a schema must be an object or a boolean, but this is a string",
  )
  assert_eq(
    problems("{\"type\":3}"),
    "type: expected a JSON type name or a list of them, but this is a number",
  )
  assert_eq(
    problems("{\"type\":[\"object\",\"thing\"]}"),
    "type[1]: \"thing\" is not a JSON type; the types are object, array, string, number, integer, boolean and null",
  )
  assert_eq(
    problems("{\"type\":[\"object\",3]}"),
    "type[1]: expected a JSON type name, but this is a number",
  )
  assert_eq(
    problems("{\"required\":\"id\"}"),
    "required: expected a list of member names, but this is a string",
  )
  assert_eq(
    problems("{\"required\":[\"id\",3]}"),
    "required[1]: expected a member name, but this is a number",
  )
  assert_eq(
    problems("{\"properties\":[]}"),
    "properties: expected an object naming the members it is about, but this is an array",
  )
  assert_eq(
    problems("{\"items\":[{\"type\":\"number\"}]}"),
    "items: expected one schema for the items, but this is an array; a list of schemas is not read here",
  )
  assert_eq(
    problems("{\"enum\":3}"),
    "enum: expected a list of values, but this is a number",
  )
  assert_eq(
    problems("{\"minimum\":\"5\"}"),
    "minimum: expected a number, but this is a string",
  )
  assert_eq(
    problems("{\"maxLength\":2.5}"),
    "maxLength: 2.5 is not a count of characters; a count must be a nonnegative integer",
  )
  assert_eq(
    problems("{\"minLength\":-1}"),
    "minLength: -1 is not a count of characters; a count must be a nonnegative integer",
  )
  assert_eq(
    problems("{\"pattern\":3}"),
    "pattern: expected a pattern, but this is a number",
  )
  // A pattern the engine cannot read is reported with the reason it gave, so its
  // author is told what to fix rather than that something is wrong somewhere.
  assert_eq(
    problems("{\"pattern\":\"(a\"}"),
    "pattern: \"(a\" is not a pattern this tool reads: \"(\" is never closed",
  )
  // Every problem is reported, and the paths say which keyword each is about.
  let two_problems =
    #|{
    #|  "type": "object",
    #|  "required": 3,
    #|  "properties": { "a": { "enum": 1 } }
    #|}
  assert_eq(
    problems(two_problems),
    "required: expected a list of member names, but this is a number\n" +
    "properties.a.enum: expected a list of values, but this is a number",
  )
}

///|
test "a schema has the same keywords inside it" {
  let schema =
    #|{
    #|  "properties": {
    #|    "a": { "properties": { "b": { "type": "wat" } } },
    #|    "list": { "items": { "minLength": true } }
    #|  }
    #|}
  assert_eq(
    problems(schema),
    "properties.a.properties.b.type: \"wat\" is not a JSON type; the types are object, array, string, number, integer, boolean and null\n" +
    "properties.list.items.minLength: expected a count of characters, but this is a boolean",
  )
}

///|
test "a schema written the way this tool reads it has nothing to report" {
  // All supported constraints and annotations compile before validation.
  let schema =
    #|{
    #|  "$schema": "https://json-schema.org/draft/2020-12/schema",
    #|  "title": "a person",
    #|  "type": ["object", "null"],
    #|  "required": ["id"],
    #|  "properties": { "id": { "type": "integer", "minimum": 0 } },
    #|  "items": { "type": "string" },
    #|  "enum": [1, "two", null],
    #|  "minimum": 0,
    #|  "maximum": 10,
    #|  "minLength": 0,
    #|  "maxLength": 10,
    #|  "pattern": "^a+$"
    #|}
  assert_eq(problems(schema), "")
  // The keywords it does read are the ones the check applies: an object missing
  // the member the schema requires is reported for that, and for not being one
  // of the values the schema lists, and the array and string keywords it also
  // holds are not asked of an object at all.
  assert_eq(
    report("{}", schema),
    "(root): required member \"id\" is missing\n" +
    "(root): it is not one of the 3 values the schema lists",
  )
}

///|
test "invalid schema arguments fail before document validation" {
  for
    schema in [
      "{\"type\":3}", "{\"enum\":\"nope\"}", "{\"minimum\":null}", "{\"minLength\":\"2\"}",
      "{\"pattern\":\"(\"}", "{\"type\":[3]}", "{\"required\":\"id\"}", "{\"required\":[\"id\",3]}",
      "{\"properties\":[]}", "{\"pattern\":3}", "{\"items\":{\"type\":3}}",
    ] {
    assert_true(validate_schema(parse_ok("{}"), parse_ok(schema)) is Err(_))
  }
  assert_eq(problems("{\"items\":{\"type\":\"number\"}}"), "")
}

///|
test "the root of a document is named rather than left blank" {
  assert_eq(
    render_schema_error({
      path: "",
      message: "it is a string where the schema expects a number",
    }),
    "(root): it is a string where the schema expects a number",
  )
  assert_eq(
    render_schema_error({
      path: "a[0].b",
      message: "required member \"c\" is missing",
    }),
    "a[0].b: required member \"c\" is missing",
  )
}

///|
test "integer schemas accept shifted fractions and refuse fractional exponents" {
  for
    raw in [
      "1", "1.0", "1e3", "1.2e1", "100e-2", "0.001e3", "0", "-0", "0e-1000", "-1.2e1",
    ] {
    assert_eq(report(raw, "{\"type\":\"integer\"}"), "")
  }
  for raw in ["1e-1", "1.0e-1", "12e-1", "-1e-1", "1e-400"] {
    assert_eq(
      report(raw, "{\"type\":\"integer\"}"),
      "(root): it is a number where the schema expects an integer",
    )
  }
}

///|
test "schema bounds compare exact decimals including negatives and equality" {
  for
    (schema, value, message) in [
      (
        "{\"minimum\":9007199254740993}", "9007199254740992", "it is less than the minimum 9007199254740993",
      ),
      (
        "{\"maximum\":9007199254740992}", "9007199254740993", "it is more than the maximum 9007199254740992",
      ),
      ("{\"maximum\":1e400}", "1e401", "it is more than the maximum 1e400"),
      ("{\"minimum\":1e-400}", "0", "it is less than the minimum 1e-400"),
      (
        "{\"maximum\":0.1}", "0.10000000000000001", "it is more than the maximum 0.1",
      ),
      (
        "{\"minimum\":-9007199254740992}", "-9007199254740993", "it is less than the minimum -9007199254740992",
      ),
      ("{\"maximum\":-1e400}", "-9e399", "it is more than the maximum -1e400"),
    ] {
    assert_eq(report(value, schema), "(root): " + message)
  }
  for
    (schema, value) in [
      ("{\"minimum\":1.2e1,\"maximum\":12}", "12.0"),
      ("{\"minimum\":-1e400,\"maximum\":-1e400}", "-10e399"),
      ("{\"minimum\":1e-400,\"maximum\":1e-400}", "10e-401"),
      ("{\"minimum\":0,\"maximum\":0}", "-0e-1000"),
    ] {
    assert_eq(report(value, schema), "")
  }
}

///|
test "enum decimal equality remains exact inside arrays and objects" {
  assert_eq(report("1.0", "{\"enum\":[1]}"), "")
  assert_eq(report("1e0", "{\"enum\":[1]}"), "")
  assert_eq(report("-0e-1000", "{\"enum\":[0]}"), "")
  for
    (schema, value) in [
      ("{\"enum\":[9007199254740992]}", "9007199254740993"),
      ("{\"enum\":[1e400]}", "1e401"),
      ("{\"enum\":[0]}", "1e-400"),
      ("{\"enum\":[[9007199254740992]]}", "[9007199254740993]"),
      ("{\"enum\":[{\"id\":[1e400,0]}]}", "{\"id\":[1e401,0]}"),
      ("{\"enum\":[{\"id\":[1e400,0]}]}", "{\"id\":[1e400,1e-400]}"),
    ] {
    assert_eq(
      report(value, schema),
      "(root): it is not the value the schema lists",
    )
  }
  assert_eq(
    report("{\"id\":[1.0,10e399,-0]}", "{\"enum\":[{\"id\":[1,1e400,0]}]}"),
    "",
  )
}

///|
test "length arguments are exact integers with an explicit implementation cap" {
  for
    schema in [
      "{\"minLength\":0}", "{\"maxLength\":1000000000}", "{\"maxLength\":1e9}", "{\"minLength\":-0e-1000}",
    ] {
    assert_eq(problems(schema), "")
  }
  assert_eq(report("\"abcdefghijkl\"", "{\"maxLength\":1.2e1}"), "")
  assert_eq(
    report("\"abcdefghijklm\"", "{\"maxLength\":1.2e1}"),
    "(root): it is 13 characters long, and the schema asks for at most 12",
  )
  for
    (raw, kind) in [
      ("-1", InvalidSchema),
      ("1e-1", InvalidSchema),
      ("1e-400", InvalidSchema),
      ("1000000001", UnsupportedFeature),
      ("1e400", UnsupportedFeature),
    ] {
    let errors = schema_problems(
      parse_ok("{\"properties\":{\"name\":{\"minLength\":" + raw + "}}}"),
    )
    assert_eq(errors.length(), 1)
    assert_eq(errors[0].path, "properties.name.minLength")
    assert_eq(errors[0].kind, kind)
  }
  assert_eq(
    problems("{\"maxLength\":1000000001}"),
    "maxLength: 1000000001 exceeds the supported character count limit of 1000000000",
  )
}

///|
test "boolean schemas behave consistently at every instance location" {
  for value in ["null", "true", "false", "1", "\"x\"", "[]", "{}"] {
    assert_eq(report(value, "true"), "")
    assert_eq(
      report(value, "false"),
      "(root): it is rejected by the false schema",
    )
  }
  assert_eq(report("{}", "{\"properties\":{\"x\":false}}"), "")
  assert_eq(
    report("{\"x\":1}", "{\"properties\":{\"x\":false}}"),
    "x: it is rejected by the false schema",
  )
  assert_eq(report("[]", "{\"items\":false}"), "")
  assert_eq(
    report("[1]", "{\"items\":false}"),
    "[0]: it is rejected by the false schema",
  )
  assert_eq(report("[1]", "{\"items\":true}"), "")
}

///|
test "const compares arbitrary data with exact nested numeric equality" {
  for
    (schema, value) in [
      ("{\"const\":false}", "false"),
      ("{\"const\":null}", "null"),
      ("{\"const\":1}", "1.0"),
      ("{\"const\":{\"b\":[1,1e400],\"a\":0}}", "{\"a\":-0,\"b\":[1e0,10e399]}"),
      ("{\"const\":{\"multipleOf\":2}}", "{\"multipleOf\":2}"),
    ] {
    assert_eq(problems(schema), "")
    assert_eq(report(value, schema), "")
  }
  for
    (schema, value) in [
      ("{\"const\":false}", "null"),
      ("{\"const\":9007199254740992}", "9007199254740993"),
      ("{\"const\":[1,2]}", "[2,1]"),
      ("{\"const\":{\"id\":[9007199254740992]}}", "{\"id\":[9007199254740993]}"),
      ("{\"const\":[1e400,0]}", "[1e401,0]"),
      ("{\"const\":[0]}", "[1e-400]"),
    ] {
    assert_eq(
      report(value, schema),
      "(root): it is not the constant value the schema specifies",
    )
  }
}

///|
test "combinations use independent branch results and count all matches" {
  assert_eq(
    report("11", "{\"allOf\":[{\"minimum\":0},{\"maximum\":10}]}"),
    "(root): allOf[1]: it is more than the maximum 10",
  )
  assert_eq(report("5", "{\"allOf\":[{\"minimum\":0},{\"maximum\":10}]}"), "")
  let any = "{\"anyOf\":[{\"type\":\"string\"},{\"type\":\"number\"}]}"
  assert_eq(report("1", any), "")
  assert_eq(report("\"x\"", any), "")
  assert_eq(report("true", any), "(root): it does not match any anyOf branch")
  let one = "{\"oneOf\":[{\"type\":\"number\"},{\"type\":\"integer\"}]}"
  assert_eq(
    report("1", one),
    "(root): it matches 2 oneOf branches; exactly one is required",
  )
  assert_eq(report("1.5", one), "")
  assert_eq(
    report("true", one),
    "(root): it matches 0 oneOf branches; exactly one is required",
  )
  assert_eq(
    report("null", "{\"oneOf\":[true,true,true]}"),
    "(root): it matches 3 oneOf branches; exactly one is required",
  )
  assert_eq(
    report("null", "{\"allOf\":[true,false]}"),
    "(root): allOf[1]: it is rejected by the false schema",
  )
  assert_eq(report("null", "{\"anyOf\":[false,true]}"), "")
}

///|
test "not and nested combinations retain instance paths and sibling constraints" {
  assert_eq(report("1.5", "{\"not\":{\"type\":\"integer\"}}"), "")
  assert_eq(
    report("1", "{\"not\":{\"type\":\"integer\"}}"),
    "(root): it matches the schema forbidden by not",
  )
  assert_eq(
    report("null", "{\"not\":true}"),
    "(root): it matches the schema forbidden by not",
  )
  assert_eq(report("null", "{\"not\":false}"), "")
  assert_eq(report("2", "{\"not\":{\"not\":{\"const\":2}}}"), "")
  assert_eq(
    report(
      "2", "{\"allOf\":[{\"anyOf\":[{\"const\":2},false]},{\"not\":{\"const\":3}}]}",
    ),
    "",
  )
  assert_eq(
    report("1", "{\"type\":\"string\",\"anyOf\":[true,false]}"),
    "(root): it is a number where the schema expects a string",
  )
  assert_eq(
    report(
      "1", "{\"type\":\"integer\",\"anyOf\":[{\"const\":2},{\"const\":3}]}",
    ),
    "(root): it does not match any anyOf branch",
  )
  assert_eq(
    report(
      "{\"x\":11}", "{\"properties\":{\"x\":{\"allOf\":[{\"maximum\":10},false]}}}",
    ),
    "x: allOf[0]: it is more than the maximum 10\nx: allOf[1]: it is rejected by the false schema",
  )
  assert_eq(
    report(
      "[true]", "{\"items\":{\"anyOf\":[{\"type\":\"string\"},{\"type\":\"number\"}]}}",
    ),
    "[0]: it does not match any anyOf branch",
  )
}

///|
test "composition parameters require nonempty arrays of valid schemas" {
  for keyword in ["allOf", "anyOf", "oneOf"] {
    for argument in ["[]", "false", "{}", "null", "[null]", "[1]", "[[]]"] {
      let issues = schema_problems(
        parse_ok("{\"" + keyword + "\":" + argument + "}"),
      )
      assert_eq(issues.length(), 1)
      assert_eq(issues[0].kind, InvalidSchema)
      assert_eq(
        issues[0].path,
        if argument == "[null]" || argument == "[1]" || argument == "[[]]" {
          keyword + "[0]"
        } else {
          keyword
        },
      )
    }
  }
  for
    (schema, path) in [
      ("{\"not\":null}", "not"),
      ("{\"additionalProperties\":123}", "additionalProperties"),
    ] {
    let issues = schema_problems(parse_ok(schema))
    assert_eq(issues.length(), 1)
    assert_eq(issues[0].kind, InvalidSchema)
    assert_eq(issues[0].path, path)
  }
}

///|
test "all branches are compiled even when their outcome is already decided" {
  for
    (schema, path) in [
      (
        "{\"anyOf\":[true,{\"unevaluatedProperties\":false}]}", "anyOf[1].unevaluatedProperties",
      ),
      ("{\"allOf\":[false,{\"$ref\":\"other.json#/x\"}]}", "allOf[1].$ref"),
      (
        "{\"oneOf\":[true,true,{\"unevaluatedProperties\":false}]}", "oneOf[2].unevaluatedProperties",
      ),
      (
        "{\"not\":{\"unevaluatedProperties\":false}}", "not.unevaluatedProperties",
      ),
      (
        "{\"additionalProperties\":{\"unevaluatedProperties\":false}}", "additionalProperties.unevaluatedProperties",
      ),
      (
        "{\"properties\":{\"missing\":{\"not\":{\"$ref\":\"other.json#/x\"}}}}",
        "properties.missing.not.$ref",
      ),
    ] {
    let issues = schema_problems(parse_ok(schema))
    assert_eq(issues.length(), 1)
    assert_eq(issues[0].kind, UnsupportedFeature)
    assert_eq(issues[0].path, path)
    assert_true(validate_schema(parse_ok("{}"), parse_ok(schema)) is Err(_))
  }
}

///|
test "additionalProperties allows refuses and validates only extra values" {
  assert_eq(report("{\"x\":1}", "{}"), "")
  assert_eq(report("{\"x\":1}", "{\"additionalProperties\":true}"), "")
  assert_eq(
    report("{\"x\":1,\"y\":2}", "{\"additionalProperties\":false}"),
    "x: additional property is not allowed\ny: additional property is not allowed",
  )
  assert_eq(
    report(
      "{\"x\":\"bad\"}", "{\"additionalProperties\":{\"type\":\"integer\"}}",
    ),
    "x: it is a string where the schema expects an integer",
  )
  assert_eq(
    report("{\"x\":1}", "{\"additionalProperties\":{\"type\":\"integer\"}}"),
    "",
  )
  assert_eq(
    report("{\"x\":[1]}", "{\"additionalProperties\":{\"items\":false}}"),
    "x[0]: it is rejected by the false schema",
  )
  for value in ["null", "1", "true", "\"x\"", "[]"] {
    assert_eq(report(value, "{\"additionalProperties\":false}"), "")
  }
}

///|
test "extra property declarations are local and independent of keyword order" {
  let first = "{\"additionalProperties\":false,\"properties\":{\"x\":{\"type\":\"integer\"}}}"
  let last = "{\"properties\":{\"x\":{\"type\":\"integer\"}},\"additionalProperties\":false}"
  for schema in [first, last] {
    assert_eq(report("{\"x\":1}", schema), "")
    assert_eq(
      report("{\"x\":\"bad\"}", schema),
      "x: it is a string where the schema expects an integer",
    )
    assert_eq(
      report("{\"x\":1,\"y\":2}", schema),
      "y: additional property is not allowed",
    )
  }
  assert_eq(
    report("{\"x\":1}", "{\"required\":[\"x\"],\"additionalProperties\":false}"),
    "x: additional property is not allowed",
  )
  assert_eq(
    report(
      "{\"id\":1}", "{\"allOf\":[{\"properties\":{\"id\":{\"type\":\"integer\"}}},{\"additionalProperties\":false}]}",
    ),
    "id: allOf[1]: additional property is not allowed",
  )
  assert_eq(
    report(
      "{\"x\":1}", "{\"properties\":{\"x\":false},\"additionalProperties\":false}",
    ),
    "x: it is rejected by the false schema",
  )
}

///|
test "exclusive bounds reject equality and compare both sides exactly" {
  for
    (schema, value, message) in [
      (
        "{\"exclusiveMinimum\":1}", "1.0", "it is not greater than the exclusive minimum 1",
      ),
      (
        "{\"exclusiveMaximum\":1}", "1e0", "it is not less than the exclusive maximum 1",
      ),
      (
        "{\"exclusiveMaximum\":1e400}", "1e400", "it is not less than the exclusive maximum 1e400",
      ),
      (
        "{\"exclusiveMinimum\":-2}", "-3", "it is not greater than the exclusive minimum -2",
      ),
      (
        "{\"exclusiveMinimum\":-2}", "-2", "it is not greater than the exclusive minimum -2",
      ),
      (
        "{\"exclusiveMaximum\":-2}", "-1", "it is not less than the exclusive maximum -2",
      ),
      (
        "{\"exclusiveMaximum\":-2}", "-2", "it is not less than the exclusive maximum -2",
      ),
      (
        "{\"exclusiveMinimum\":0}", "-0", "it is not greater than the exclusive minimum 0",
      ),
      (
        "{\"exclusiveMaximum\":0}", "0e1000000", "it is not less than the exclusive maximum 0",
      ),
    ] {
    assert_eq(report(value, schema), "(root): " + message)
  }
  for
    (schema, value) in [
      ("{\"exclusiveMinimum\":9007199254740992}", "9007199254740993"),
      ("{\"exclusiveMinimum\":-2}", "-1"),
      ("{\"exclusiveMaximum\":-2}", "-3"),
      ("{\"exclusiveMinimum\":0}", "1e-400"),
      ("{\"exclusiveMaximum\":0}", "-1e-400"),
      ("{\"exclusiveMinimum\":1}", "1.1"),
      ("{\"exclusiveMaximum\":1}", "0.9"),
      (
        "{\"exclusiveMinimum\":0,\"exclusiveMaximum\":1,\"multipleOf\":2}", "\"hello\"",
      ),
      ("{\"minimum\":0,\"exclusiveMinimum\":1}", "1.1"),
    ] {
    assert_eq(report(value, schema), "")
  }
  assert_eq(
    report("1", "{\"minimum\":0,\"exclusiveMinimum\":1}"),
    "(root): it is not greater than the exclusive minimum 1",
  )
  let contradictory = "{\"exclusiveMinimum\":2,\"exclusiveMaximum\":1}"
  assert_eq(problems(contradictory), "")
  assert_eq(
    report("1.5", contradictory),
    "(root): it is not greater than the exclusive minimum 2\n(root): it is not less than the exclusive maximum 1",
  )
}

///|
test "multipleOf applies exact decimal divisibility only to numeric instances" {
  for
    (value, divisor) in [
      ("0.3", "0.1"),
      ("0.21", "0.03"),
      ("-0.3", "0.1"),
      ("-0.0", "2"),
      ("1e-400", "1e-401"),
      ("0.3", "0.10"),
      ("0.3", "1e-1"),
      ("\"hello\"", "2"),
      ("1e100000000000000000000", "2"),
      ("1", "1e-100000000000000000000"),
    ] {
    assert_eq(report(value, "{\"multipleOf\":" + divisor + "}"), "")
  }
  for
    (value, divisor) in [
      ("0.30000000000000004", "0.1"),
      ("0.3", "0.2"),
      ("9007199254740993", "2"),
      ("1e-400", "3e-400"),
      ("1e100000000000000000000", "3"),
      ("1e-100000000000000000000", "1"),
    ] {
    assert_eq(
      report(value, "{\"multipleOf\":" + divisor + "}"),
      "(root): it is not a multiple of " + divisor,
    )
  }
  assert_eq(
    report(
      "{\"price\":12.345}", "{\"properties\":{\"price\":{\"multipleOf\":0.01}}}",
    ),
    "price: it is not a multiple of 0.01",
  )
}

///|
test "numeric keyword parameters are fully prechecked with category and location" {
  for
    (schema, path) in [
      ("{\"exclusiveMinimum\":true}", "exclusiveMinimum"),
      ("{\"exclusiveMaximum\":\"1\"}", "exclusiveMaximum"),
      ("{\"multipleOf\":0}", "multipleOf"),
      ("{\"multipleOf\":-0.0}", "multipleOf"),
      ("{\"multipleOf\":-2}", "multipleOf"),
      ("{\"multipleOf\":\"2\"}", "multipleOf"),
      ("{\"multipleOf\":0e1000000}", "multipleOf"),
      (
        "{\"properties\":{\"price\":{\"multipleOf\":0}}}", "properties.price.multipleOf",
      ),
      ("{\"anyOf\":[true,{\"multipleOf\":0}]}", "anyOf[1].multipleOf"),
    ] {
    let issues = schema_problems(parse_ok(schema))
    assert_eq(issues.length(), 1)
    assert_eq(issues[0].kind, InvalidSchema)
    assert_eq(issues[0].path, path)
    assert_true(validate_schema(parse_ok("{}"), parse_ok(schema)) is Err(_))
  }
  for
    schema in [
      "{\"exclusiveMinimum\":0}", "{\"multipleOf\":0.1}", "{\"multipleOf\":1e-400}",
      "{\"anyOf\":[true,{\"multipleOf\":2}]}",
    ] {
    assert_eq(problems(schema), "")
  }
}

///|
test "numeric assertions compose using independent exact results" {
  assert_eq(report("3", "{\"not\":{\"multipleOf\":2}}"), "")
  assert_eq(
    report("4", "{\"not\":{\"multipleOf\":2}}"),
    "(root): it matches the schema forbidden by not",
  )
  assert_eq(
    report("6", "{\"allOf\":[{\"multipleOf\":2},{\"multipleOf\":3}]}"),
    "",
  )
  assert_eq(
    report("4", "{\"allOf\":[{\"multipleOf\":2},{\"multipleOf\":3}]}"),
    "(root): allOf[1]: it is not a multiple of 3",
  )
  assert_eq(
    report("3", "{\"anyOf\":[{\"multipleOf\":2},{\"multipleOf\":3}]}"),
    "",
  )
  assert_eq(
    report("5", "{\"anyOf\":[{\"multipleOf\":2},{\"multipleOf\":3}]}"),
    "(root): it does not match any anyOf branch",
  )
  assert_eq(
    report("3", "{\"oneOf\":[{\"multipleOf\":2},{\"multipleOf\":3}]}"),
    "",
  )
  assert_eq(
    report("6", "{\"oneOf\":[{\"multipleOf\":2},{\"multipleOf\":3}]}"),
    "(root): it matches 2 oneOf branches; exactly one is required",
  )
}

///|
test "array counts include boundaries and preserve independent constraints" {
  assert_eq(
    report("[1]", "{\"minItems\":2}"),
    "(root): it has 1 item, but the schema requires at least 2",
  )
  for raw in ["2", "2.0", "2e0", "0.02e2"] {
    assert_eq(
      report("[1,2]", "{\"minItems\":" + raw + ",\"maxItems\":" + raw + "}"),
      "",
    )
  }
  assert_eq(report("[]", "{\"maxItems\":0}"), "")
  assert_eq(
    report("[null]", "{\"maxItems\":0}"),
    "(root): it has 1 item, but the schema allows at most 0",
  )
  assert_eq(
    report(
      "{\"orders\":[1,2,3]}", "{\"properties\":{\"orders\":{\"maxItems\":2}}}",
    ),
    "orders: it has 3 items, but the schema allows at most 2",
  )
  let contradictory = "{\"minItems\":3,\"maxItems\":1}"
  assert_eq(problems(contradictory), "")
  assert_eq(
    report("[1,2]", contradictory),
    "(root): it has 2 items, but the schema requires at least 3\n(root): it has 2 items, but the schema allows at most 1",
  )
  for value in ["null", "true", "1", "\"text\"", "{}"] {
    assert_eq(
      report(
        value, "{\"minItems\":2,\"maxItems\":0,\"uniqueItems\":true,\"prefixItems\":[false]}",
      ),
      "",
    )
  }
}

///|
test "uniqueItems uses precise deep equality and reports only the first pair" {
  for
    value in [
      "[1,1.0]", "[0,-0.0]", "[null,null]", "[{\"a\":1,\"b\":2},{\"b\":2,\"a\":1.0}]",
      "[{\"x\":[1,1e400]},{\"x\":[1.0,10e399]}]", "[[1,2],[1.0,2]]",
    ] {
    assert_eq(
      report(value, "{\"uniqueItems\":true}"),
      "(root): items at indexes 0 and 1 are equal, but uniqueItems is true",
    )
  }
  for
    value in [
      "[]", "[1]", "[true,1]", "[\"1\",1]", "[9007199254740992,9007199254740993]",
      "[1e-400,0]", "[[1,2],[2,1]]", "[{\"n\":1e400},{\"n\":1e401}]",
    ] {
    assert_eq(report(value, "{\"uniqueItems\":true}"), "")
  }
  assert_eq(report("[1,1]", "{\"uniqueItems\":false}"), "")
  assert_eq(report("[1,1]", "{}"), "")
  assert_eq(
    report("[1,2,1,2]", "{\"uniqueItems\":true,\"maxItems\":2}"),
    "(root): items at indexes 0 and 2 are equal, but uniqueItems is true\n(root): it has 4 items, but the schema allows at most 2",
  )
}

///|
test "prefixItems validates existing positions and items validates the suffix" {
  let schema = "{\"prefixItems\":[{\"type\":\"integer\"}],\"items\":{\"type\":\"string\"}}"
  for value in ["[]", "[1]", "[1,\"a\"]"] {
    assert_eq(report(value, schema), "")
  }
  assert_eq(
    report("[1,2]", schema),
    "[1]: it is a number where the schema expects a string",
  )
  assert_eq(
    report("[\"bad\",\"a\"]", schema),
    "[0]: it is a string where the schema expects an integer",
  )
  assert_eq(report("[]", "{\"prefixItems\":[false]}"), "")
  assert_eq(
    report("[1]", "{\"prefixItems\":[false]}"),
    "[0]: it is rejected by the false schema",
  )
  assert_eq(report("[1,2,3]", "{\"prefixItems\":[true,true]}"), "")
  assert_eq(report("[1]", "{\"prefixItems\":[true,false],\"items\":false}"), "")
  assert_eq(report("[1]", "{\"prefixItems\":[true],\"items\":false}"), "")
  assert_eq(
    report("[1,2]", "{\"prefixItems\":[true],\"items\":false}"),
    "[1]: it is rejected by the false schema",
  )
  assert_eq(
    report("[1]", "{\"items\":false}"),
    "[0]: it is rejected by the false schema",
  )
}

///|
test "tuple keyword order and composition do not change suffix scope" {
  for
    schema in [
      "{\"prefixItems\":[false,true],\"items\":false}", "{\"items\":false,\"prefixItems\":[false,true]}",
    ] {
    // Reports retain keyword order; both orders must identify the same two
    // instance violations, and the failed prefix must not move the suffix start.
    let violations = match
      validate_schema(parse_ok("[1,2,3]"), parse_ok(schema)) {
      Ok(violations) => violations
      Err(_) => abort("valid tuple schema rejected")
    }
    assert_eq(violations.length(), 2)
    for path in ["[0]", "[2]"] {
      assert_true(
        violations.any(fn(error) {
          error.path == path &&
          error.message == "it is rejected by the false schema"
        }),
      )
    }
  }
  assert_eq(
    report("[1]", "{\"allOf\":[{\"prefixItems\":[true]}],\"items\":false}"),
    "[0]: it is rejected by the false schema",
  )
  assert_eq(
    report("[1]", "{\"prefixItems\":[true],\"allOf\":[{\"items\":false}]}"),
    "[0]: allOf[0]: it is rejected by the false schema",
  )
}

///|
test "nested array errors use instance paths for tuple and suffix elements" {
  let schema = "{\"properties\":{\"orders\":{\"prefixItems\":[true,{\"prefixItems\":[{\"type\":\"integer\"}],\"items\":false}],\"items\":false}}}"
  assert_eq(
    report("{\"orders\":[0,[\"bad\",2],3]}", schema),
    "orders[1][0]: it is a string where the schema expects an integer\norders[1][1]: it is rejected by the false schema\norders[2]: it is rejected by the false schema",
  )
}

///|
test "array parameters use exact counts and schema error categories" {
  for keyword in ["minItems", "maxItems"] {
    for
      (raw, kind) in [
        ("-1", InvalidSchema),
        ("0.1", InvalidSchema),
        ("1e-400", InvalidSchema),
        ("true", InvalidSchema),
        ("1000000001", UnsupportedFeature),
        ("1e400", UnsupportedFeature),
      ] {
      let issues = schema_problems(
        parse_ok(
          "{\"properties\":{\"orders\":{\"" + keyword + "\":" + raw + "}}}",
        ),
      )
      assert_eq(issues.length(), 1)
      assert_eq(issues[0].kind, kind)
      assert_eq(issues[0].path, "properties.orders." + keyword)
      assert_true(
        issues[0].message.contains("items") ||
        issues[0].message.contains("item count"),
      )
      assert_false(issues[0].message.contains("characters"))
    }
    for raw in ["0", "-0", "2.0", "2e0", "1000000000", "1e9"] {
      assert_eq(problems("{\"" + keyword + "\":" + raw + "}"), "")
    }
  }
  assert_eq(report("[]", "{\"maxItems\":1000000000}"), "")
  for
    (schema, path) in [
      ("{\"prefixItems\":[]}", "prefixItems"),
      ("{\"prefixItems\":false}", "prefixItems"),
      ("{\"prefixItems\":[null]}", "prefixItems[0]"),
      ("{\"uniqueItems\":1}", "uniqueItems"),
      ("{\"items\":[]}", "items"),
    ] {
    let issues = schema_problems(parse_ok(schema))
    assert_eq(issues.length(), 1)
    assert_eq(issues[0].kind, InvalidSchema)
    assert_eq(issues[0].path, path)
  }
}

///|
test "all array subschemas are prechecked and ordinary const enum fields stay data" {
  for
    (schema, path, kind) in [
      (
        "{\"maxItems\":0,\"prefixItems\":[true,{\"$ref\":\"other.json#/missing\"}]}",
        "prefixItems[1].$ref",
        UnsupportedFeature,
      ),
      (
        "{\"prefixItems\":[true,{\"multipleOf\":0}]}",
        "prefixItems[1].multipleOf",
        InvalidSchema,
      ),
      (
        "{\"prefixItems\":[true],\"items\":{\"$ref\":\"other.json#/missing\"}}",
        "items.$ref",
        UnsupportedFeature,
      ),
      (
        "{\"prefixItems\":[true],\"items\":{\"minItems\":-1}}",
        "items.minItems",
        InvalidSchema,
      ),
      ("{\"additionalItems\":false}", "additionalItems", UnsupportedFeature),
      ("{\"unevaluatedItems\":true}", "unevaluatedItems", UnsupportedFeature),
      ("{\"unevaluatedItems\":false}", "unevaluatedItems", UnsupportedFeature),
    ] {
    let issues = schema_problems(parse_ok(schema))
    assert_eq(issues.length(), 1)
    assert_eq(issues[0].path, path)
    assert_eq(issues[0].kind, kind)
    assert_true(validate_schema(parse_ok("[]"), parse_ok(schema)) is Err(_))
  }
  for keyword in ["const", "enum"] {
    let data = "{\"prefixItems\":[],\"uniqueItems\":123}"
    let schema = if keyword == "const" {
      "{\"const\":" + data + "}"
    } else {
      "{\"enum\":[" + data + "]}"
    }
    assert_eq(report(data, schema), "")
  }
}

///|
test "contains counts matches with default and explicit bounds" {
  for
    (schema, data, count) in [
      ("{\"contains\":{\"type\":\"integer\"}}", "[\"bad\",1]", 0),
      ("{\"contains\":true}", "[]", 1),
      ("{\"contains\":true}", "[1]", 0),
      ("{\"contains\":false}", "[1,2]", 1),
      ("{\"contains\":false,\"minContains\":0}", "[]", 0),
      ("{\"contains\":false,\"minContains\":0}", "[1,2]", 0),
      ("{\"contains\":true,\"maxContains\":0}", "[]", 1),
      ("{\"contains\":true,\"maxContains\":0}", "[1]", 1),
      (
        "{\"contains\":{\"type\":\"integer\"},\"minContains\":0,\"maxContains\":0}",
        "[\"a\",null]", 0,
      ),
      (
        "{\"contains\":{\"type\":\"integer\"},\"minContains\":0,\"maxContains\":0}",
        "[1]", 1,
      ),
      ("{\"contains\":true,\"minContains\":2,\"maxContains\":1}", "[1,2]", 1),
      (
        "{\"contains\":true,\"minContains\":2.0,\"maxContains\":2e0}", "[1,1]", 0,
      ),
      ("{\"contains\":true,\"minContains\":2,\"maxContains\":3}", "[1]", 1),
      ("{\"contains\":true,\"minContains\":2,\"maxContains\":3}", "[1,2,3]", 0),
      (
        "{\"contains\":true,\"minContains\":2,\"maxContains\":3}", "[1,2,3,4]", 1,
      ),
    ] {
    match validate_schema(parse_ok(data), parse_ok(schema)) {
      Ok(errors) => assert_eq(errors.length(), count)
      Err(_) => abort("supported contains schema refused or evaluation failed")
    }
  }
  for data in ["null", "1", "\"x\"", "true", "{}"] {
    assert_eq(
      report(data, "{\"contains\":false,\"minContains\":3,\"maxContains\":0}"),
      "",
    )
  }
  assert_eq(report("[1,2]", "{\"minContains\":5,\"maxContains\":0}"), "")
  assert_eq(report("[]", "{\"maxContains\":0}"), "")
}

///|
test "contains counts repeated positions and exact numbers without leaking trial violations" {
  assert_eq(
    report(
      "[1,1.0,1e0]", "{\"contains\":{\"const\":1},\"minContains\":3,\"maxContains\":3}",
    ),
    "",
  )
  assert_eq(
    report(
      "[9007199254740992,9007199254740993]", "{\"contains\":{\"const\":9007199254740992},\"minContains\":2}",
    ),
    "(root): contains matched 1 item; expected at least 2",
  )
  assert_eq(
    report("[0,1e-400]", "{\"contains\":{\"const\":0},\"maxContains\":1}"),
    "",
  )
  assert_eq(
    report("[\"bad\",null]", "{\"contains\":{\"type\":\"integer\"}}"),
    "(root): contains matched 0 items; expected at least 1",
  )
  assert_eq(
    report(
      "{\"orders\":[1,\"x\",2]}", "{\"properties\":{\"orders\":{\"contains\":{\"type\":\"integer\"},\"minContains\":3}}}",
    ),
    "orders: contains matched 2 items; expected at least 3",
  )
}

///|
test "contains siblings keyword order and applicator scopes are independent" {
  let first = "{\"contains\":{\"type\":\"integer\"},\"minContains\":2,\"maxContains\":3}"
  let last = "{\"maxContains\":3,\"minContains\":2,\"contains\":{\"type\":\"integer\"}}"
  for data in ["[1,\"x\",2]", "[1,\"x\"]", "[1,2,3,4]"] {
    assert_eq(report(data, first), report(data, last))
  }
  let tuple = "{\"prefixItems\":[true],\"items\":{\"type\":\"string\"},\"contains\":{\"type\":\"integer\"}}"
  assert_eq(report("[1,\"a\"]", tuple), "")
  assert_true(report("[1,2]", tuple).contains("[1]: it is a number"))
  assert_eq(
    report("[\"a\",\"b\"]", tuple),
    "(root): contains matched 0 items; expected at least 1",
  )
  assert_eq(
    report("[1,2]", "{\"allOf\":[{\"contains\":true},{\"maxContains\":0}]}"),
    "",
  )
  assert_eq(
    report("[]", "{\"allOf\":[{\"contains\":false},{\"minContains\":0}]}"),
    "(root): allOf[0]: contains matched 0 items; expected at least 1",
  )
  assert_eq(report("[1]", "{\"not\":{\"contains\":{\"type\":\"string\"}}}"), "")
  assert_eq(
    report("[]", "{\"anyOf\":[{\"contains\":true},{\"maxItems\":0}]}"),
    "",
  )
}

///|
test "contains precheck rejects invalid counts and unavailable children even without matches" {
  for
    (schema, path, kind) in [
      ("{\"contains\":null}", "contains", InvalidSchema),
      ("{\"contains\":[]}", "contains", InvalidSchema),
      ("{\"minContains\":-1}", "minContains", InvalidSchema),
      ("{\"maxContains\":0.1}", "maxContains", InvalidSchema),
      ("{\"minContains\":1e-400}", "minContains", InvalidSchema),
      ("{\"maxContains\":true}", "maxContains", InvalidSchema),
      ("{\"minContains\":\"2\"}", "minContains", InvalidSchema),
      ("{\"maxContains\":1000000001}", "maxContains", UnsupportedFeature),
      (
        "{\"contains\":{\"pattern\":\"[\"},\"minContains\":0}",
        "contains.pattern",
        InvalidSchema,
      ),
      (
        "{\"contains\":{\"$ref\":\"#/missing\"}}",
        "contains.$ref",
        InvalidSchema,
      ),
      (
        "{\"contains\":{\"unevaluatedItems\":true},\"minContains\":0}",
        "contains.unevaluatedItems",
        UnsupportedFeature,
      ),
      (
        "{\"properties\":{\"orders\":{\"contains\":{\"minContains\":-1}}}}",
        "properties.orders.contains.minContains",
        InvalidSchema,
      ),
    ] {
    let issues = schema_problems(parse_ok(schema))
    assert_eq(issues.length(), 1)
    assert_eq(issues[0].path, path)
    assert_eq(issues[0].kind, kind)
    for data in ["[]", "null"] {
      assert_true(
        validate_schema(parse_ok(data), parse_ok(schema))
        is Err(SchemaProblems(_)),
      )
    }
  }
  assert_true(
    compile_schema(parse_ok("{\"minContains\":1000000000,\"maxContains\":0}"))
    is Ok(_),
  )
  assert_true(
    compile_schema(
      parse_ok(
        "{\"const\":{\"contains\":null},\"default\":{\"minContains\":-1},\"enum\":[{\"contains\":123}]}",
      ),
    )
    is Ok(_),
  )
}

///|
test "object counts apply only to current object members" {
  assert_eq(
    report("{}", "{\"minProperties\":1}"),
    "(root): it has 0 properties, but the schema requires at least 1",
  )
  assert_eq(report("{}", "{\"maxProperties\":0}"), "")
  assert_eq(
    report("{\"x\":null}", "{\"maxProperties\":0}"),
    "(root): it has 1 property, but the schema allows at most 0",
  )
  assert_eq(report("{\"x\":{\"a\":1,\"b\":2}}", "{\"maxProperties\":1}"), "")
  for raw in ["2", "2.0", "2e0"] {
    assert_eq(
      report(
        "{\"x\":1,\"y\":2}",
        "{\"minProperties\":" + raw + ",\"maxProperties\":" + raw + "}",
      ),
      "",
    )
  }
  let contradictory = "{\"minProperties\":3,\"maxProperties\":1}"
  assert_eq(problems(contradictory), "")
  assert_eq(
    report("{\"x\":1,\"y\":2}", contradictory),
    "(root): it has 2 properties, but the schema requires at least 3\n(root): it has 2 properties, but the schema allows at most 1",
  )
  for value in ["null", "true", "1", "[]", "\"text\""] {
    assert_eq(
      report(
        value, "{\"minProperties\":1,\"maxProperties\":0,\"patternProperties\":{\"\":false},\"additionalProperties\":false}",
      ),
      "",
    )
  }
}

///|
test "patterns match names without implicit anchoring or required properties" {
  assert_eq(report("{\"x\":1}", "{\"patternProperties\":{}}"), "")
  assert_eq(
    report("{\"prefix_x_suffix\":1}", "{\"patternProperties\":{\"x\":false}}"),
    "prefix_x_suffix: it is rejected by the false schema",
  )
  assert_eq(
    report("{\"\":1}", "{\"patternProperties\":{\"\":false}}"),
    "(root): it is rejected by the false schema",
  )
  assert_eq(report("{\"y\":1}", "{\"patternProperties\":{\"^x\":false}}"), "")
  assert_eq(report("{}", "{\"patternProperties\":{\"^x\":false}}"), "")
  let schema = "{\"patternProperties\":{\"^x\":{\"type\":\"integer\"},\"x$\":{\"minimum\":0}}}"
  assert_eq(report("{\"x\":1}", schema), "")
  assert_eq(report("{\"x\":-1}", schema), "x: it is less than the minimum 0")
  assert_eq(
    report("{\"x\":\"a\"}", schema),
    "x: it is a string where the schema expects an integer",
  )
}

///|
test "every overlapping property constraint runs without treating covered names as extra" {
  let schema = "{\"properties\":{\"x\":{\"minimum\":0}},\"patternProperties\":{\"^x\":{\"maximum\":1},\"x$\":{\"multipleOf\":2}},\"additionalProperties\":false}"
  assert_eq(
    report("{\"x\":-3}", schema),
    "x: it is less than the minimum 0\nx: it is not a multiple of 2",
  )
  assert_eq(
    report("{\"x\":3}", schema),
    "x: it is more than the maximum 1\nx: it is not a multiple of 2",
  )
  let patterned = "{\"patternProperties\":{\"^x\":{\"type\":\"integer\"}},\"additionalProperties\":false}"
  assert_eq(report("{\"x1\":1}", patterned), "")
  assert_eq(
    report("{\"x1\":\"bad\"}", patterned),
    "x1: it is a string where the schema expects an integer",
  )
  assert_eq(
    report("{\"y\":1}", patterned),
    "y: additional property is not allowed",
  )
  assert_eq(
    report(
      "{\"x1\":1}", "{\"patternProperties\":{\"^x\":false},\"additionalProperties\":false}",
    ),
    "x1: it is rejected by the false schema",
  )
  assert_eq(
    report(
      "{\"x\":\"text\",\"y\":1}", "{\"patternProperties\":{\"^x\":true},\"additionalProperties\":{\"type\":\"integer\"}}",
    ),
    "",
  )
}

///|
test "property pattern scope is local and independent of keyword order" {
  for
    schema in [
      "{\"properties\":{\"id\":true},\"patternProperties\":{\"^x\":{\"type\":\"integer\"}},\"additionalProperties\":false}",
      "{\"additionalProperties\":false,\"patternProperties\":{\"^x\":{\"type\":\"integer\"}},\"properties\":{\"id\":true}}",
      "{\"patternProperties\":{\"^x\":{\"type\":\"integer\"}},\"additionalProperties\":false,\"properties\":{\"id\":true}}",
      "{\"properties\":{\"id\":true},\"additionalProperties\":false,\"patternProperties\":{\"^x\":{\"type\":\"integer\"}}}",
      "{\"additionalProperties\":false,\"properties\":{\"id\":true},\"patternProperties\":{\"^x\":{\"type\":\"integer\"}}}",
      "{\"patternProperties\":{\"^x\":{\"type\":\"integer\"}},\"properties\":{\"id\":true},\"additionalProperties\":false}",
    ] {
    assert_eq(report("{\"id\":1,\"x1\":1}", schema), "")
    assert_eq(
      report("{\"x1\":\"bad\"}", schema),
      "x1: it is a string where the schema expects an integer",
    )
    assert_eq(
      report("{\"y\":1}", schema),
      "y: additional property is not allowed",
    )
  }
  assert_eq(
    report(
      "{\"x\":1}", "{\"allOf\":[{\"patternProperties\":{\"^x\":true}},{\"additionalProperties\":false}]}",
    ),
    "x: allOf[1]: additional property is not allowed",
  )
  assert_eq(
    report(
      "{\"x\":1}", "{\"allOf\":[{\"patternProperties\":{\"^x\":true}}],\"additionalProperties\":false}",
    ),
    "x: additional property is not allowed",
  )
  assert_eq(
    report(
      "{\"x\":1}", "{\"required\":[\"x\"],\"patternProperties\":{},\"additionalProperties\":false}",
    ),
    "x: additional property is not allowed",
  )
}

///|
test "property count and regex preflight retain categories and escaped locations" {
  for keyword in ["minProperties", "maxProperties"] {
    for
      (raw, kind) in [
        ("-1", InvalidSchema),
        ("1e-400", InvalidSchema),
        ("false", InvalidSchema),
        ("1000000001", UnsupportedFeature),
        ("1e400", UnsupportedFeature),
      ] {
      let issues = schema_problems(
        parse_ok("{\"" + keyword + "\":" + raw + "}"),
      )
      assert_eq(issues.length(), 1)
      assert_eq(issues[0].kind, kind)
      assert_eq(issues[0].path, keyword)
      assert_true(issues[0].message.contains("propert"))
      assert_false(issues[0].message.contains("character"))
      assert_false(issues[0].message.contains("items"))
    }
    for raw in ["0", "2.0", "2e0", "1000000000"] {
      assert_eq(problems("{\"" + keyword + "\":" + raw + "}"), "")
    }
  }
  for
    (schema, path, kind) in [
      ("{\"patternProperties\":[]}", "patternProperties", InvalidSchema),
      (
        "{\"patternProperties\":{\"^x\":null}}",
        "patternProperties[\"^x\"]",
        InvalidSchema,
      ),
      (
        "{\"patternProperties\":{\"^x\":{\"type\":123}}}",
        "patternProperties[\"^x\"].type",
        InvalidSchema,
      ),
      (
        "{\"patternProperties\":{\"[\":true}}",
        "patternProperties[\"[\"]",
        InvalidSchema,
      ),
      (
        "{\"patternProperties\":{\"(?=x)\":true}}",
        "patternProperties[\"(?=x)\"]",
        UnsupportedFeature,
      ),
      (
        "{\"patternProperties\":{\"^x\":{\"$ref\":\"other.json#/missing\"}}}",
        "patternProperties[\"^x\"].$ref",
        UnsupportedFeature,
      ),
      (
        "{\"anyOf\":[true,{\"patternProperties\":{\"[\":true}}]}",
        "anyOf[1].patternProperties[\"[\"]",
        InvalidSchema,
      ),
    ] {
    let issues = schema_problems(parse_ok(schema))
    assert_eq(issues.length(), 1)
    assert_eq(issues[0].path, path)
    assert_eq(issues[0].kind, kind)
    assert_true(validate_schema(parse_ok("{}"), parse_ok(schema)) is Err(_))
  }
  let key = "a.b[\"x\"]\\\\"
  let schema = @pjson.Object(members=[
    (
      "patternProperties",
      @pjson.Object(members=[(key, parse_ok("{\"type\":123}"))]),
    ),
  ])
  let issues = schema_problems(schema)
  assert_eq(issues.length(), 1)
  assert_eq(
    issues[0].path,
    "patternProperties[\"a.b[\\\"x\\\"]\\\\\\\\\"].type",
  )
}

///|
test "regex cache collects only real schema positions and reuses identical patterns" {
  let schema = parse_ok(
    (
      #|{"pattern":"^x","properties":{"a":{"pattern":"^x"}},
      #| "patternProperties":{"^x":{"pattern":"^x"}},
      #| "prefixItems":[{"pattern":"^y"}],"items":{"not":{"pattern":"^x"}},
      #| "additionalProperties":{"pattern":"^y"},
      #| "const":{"pattern":"[","patternProperties":{"(":false}},
      #| "enum":[{"pattern":"["}],"default":{"pattern":"["},"examples":[{"patternProperties":{"[":true}}]}
    ),
  )
  let compiled = match compile_schema(schema) {
    Ok(compiled) => compiled
    Err(_) => abort("valid schema refused")
  }
  assert_eq(compiled.patterns.length(), 2)
  assert_true(compiled.patterns.contains("^x"))
  assert_true(compiled.patterns.contains("^y"))
  let cache : Map[String, Result[Pattern, PatternProblem]] = Map([])
  let issues = precheck_schema(
    parse_ok("{\"pattern\":\"[\",\"properties\":{\"x\":{\"pattern\":\"[\"}}}"),
    cache,
  )
  assert_eq(cache.length(), 1)
  assert_eq(issues.length(), 2)
  assert_eq(issues[0].path, "pattern")
  assert_eq(issues[1].path, "properties.x.pattern")
  assert_eq(issues[0].kind, InvalidSchema)
  // Seed a parsed entry under an otherwise invalid raw key to prove cache hits
  // never invoke the parser again. This context is accessible only to whitebox tests.
  let parsed = match read_pattern("^x") {
    Ok(pattern) => pattern
    Err(_) => abort("valid pattern refused")
  }
  let seeded : Map[String, Result[Pattern, PatternProblem]] = Map([
    ("[", Ok(parsed)),
  ])
  assert_eq(
    precheck_schema(
      parse_ok("{\"pattern\":\"[\",\"patternProperties\":{\"[\":true}}"),
      seeded,
    ).length(),
    0,
  )
  let compiled = match
    compile_schema_snapshot(parse_ok("{\"pattern\":\"[\"}"), seeded) {
    Ok(compiled) => compiled
    Err(_) => abort("seeded cache was ignored")
  }
  assert_true(validate_compiled_schema(parse_ok("\"x\""), compiled) is Ok([]))
  assert_true(validate_compiled_schema(parse_ok("\"y\""), compiled) is Ok([_]))
}
