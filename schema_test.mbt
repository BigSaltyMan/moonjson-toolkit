///|
fn json(text : String) -> @pjson.Json {
  match @pjson.parse(text) {
    Ok(value) => value
    Err(_) => abort("invalid test JSON")
  }
}

///|
fn rejected(text : String) -> Array[@moonjson-toolkit.SchemaProblem] {
  match @moonjson-toolkit.compile_schema(json(text)) {
    Err(problems) => problems
    Ok(_) => abort("unsupported schema compiled")
  }
}

///|
test "public validation refuses unsupported features with locations" {
  for
    (schema, path) in [
      ("{\"patternProperties\":{}}", "patternProperties"),
      ("{\"anyOf\":[true,{\"multipleOf\":2}]}", "anyOf[1].multipleOf"),
      ("{\"$ref\":\"#/$defs/person\"}", "$ref"),
      (
        "{\"properties\":{\"id\":{\"minimum\":0,\"multipleOf\":2}}}", "properties.id.multipleOf",
      ),
      (
        "{\"items\":{\"additionalProperties\":{\"multipleOf\":2}}}", "items.additionalProperties.multipleOf",
      ),
    ] {
    let problems = rejected(schema)
    assert_eq(problems.length(), 1)
    assert_eq(problems[0].path, path)
    assert_eq(problems[0].kind, @moonjson-toolkit.UnsupportedFeature)
    assert_eq(problems[0].message, "keyword is not supported")
    assert_true(
      @moonjson-toolkit.validate_schema(json("{}"), json(schema)) is Err(_),
    )
  }
}

///|
test "schema mechanisms remain unsupported and booleans compile" {
  for
    keyword in [
      "$defs", "$id", "$anchor", "$dynamicRef", "$vocabulary", "unknown",
    ] {
    let problems = rejected("{\"" + keyword + "\":null}")
    assert_eq(problems[0].path, keyword)
    assert_eq(problems[0].kind, @moonjson-toolkit.UnsupportedFeature)
  }
  for
    schema in [
      "true", "false", "{\"items\":true}", "{\"properties\":{\"id\":false}}",
    ] {
    assert_true(@moonjson-toolkit.compile_schema(json(schema)) is Ok(_))
  }
}

///|
test "parameter and version problems have distinct categories" {
  assert_eq(rejected("{\"type\":123}")[0].kind, @moonjson-toolkit.InvalidSchema)
  let version = rejected(
      "{\"$schema\":\"http://json-schema.org/draft-07/schema#\"}",
    )[0]
  assert_eq(version.path, "$schema")
  assert_eq(version.kind, @moonjson-toolkit.UnsupportedVersion)
  assert_true(version.message.contains("unsupported schema version"))
  for
    schema in [
      "{\"title\":1}", "{\"description\":null}", "{\"$comment\":[]}", "{\"examples\":{}}",
      "{\"format\":false}", "{\"$schema\":123}", "{\"type\":false}", "{\"required\":false}",
      "{\"type\":[]}", "{\"type\":[\"string\",\"string\"]}", "{\"required\":[\"id\",\"id\"]}",
    ] {
    assert_eq(rejected(schema)[0].kind, @moonjson-toolkit.InvalidSchema)
  }
}

///|
test "annotations and data members are not schemas" {
  let annotations = json(
    (
      #|{"$schema":"https://json-schema.org/draft/2020-12/schema",
      #| "title":"person","description":"sample","$comment":"note",
      #| "default":{"anyOf":true},"examples":[{"anyOf":false}],"format":"email"}
    ),
  )
  assert_true(@moonjson-toolkit.compile_schema(annotations) is Ok(_))
  assert_true(
    @moonjson-toolkit.validate_schema(json("\"not an email\""), annotations)
    is Ok([]),
  )
  let data = json("{\"anyOf\":1}")
  assert_true(
    @moonjson-toolkit.validate_schema(data, json("{\"enum\":[{\"anyOf\":1}]}"))
    is Ok([]),
  )
  assert_true(
    @moonjson-toolkit.compile_schema(
      json("{\"properties\":{\"anyOf\":{\"type\":\"number\"}}}"),
    )
    is Ok(_),
  )
  assert_true(
    @moonjson-toolkit.validate_schema(data, json("{\"default\":{\"extra\":1}}"))
    is Ok([]),
  )
  match data {
    Object(members~) => assert_eq(members.length(), 1)
    _ => abort("expected object")
  }
}

///|
test "public validation returns matches or violations for supported schemas" {
  let schema = json("{\"type\":\"number\",\"minimum\":0,\"maximum\":10}")
  let compiled = match @moonjson-toolkit.compile_schema(schema) {
    Ok(compiled) => compiled
    Err(_) => abort("supported schema rejected")
  }
  assert_true(@moonjson-toolkit.validate_schema(json("2"), schema) is Ok([]))
  assert_eq(
    @moonjson-toolkit.validate_compiled_schema(json("2"), compiled).length(),
    0,
  )
  match @moonjson-toolkit.validate_schema(json("-1"), schema) {
    Ok(errors) => assert_eq(errors.length(), 1)
    Err(_) => abort("supported schema rejected")
  }
  assert_eq(
    @moonjson-toolkit.validate_compiled_schema(json("-1"), compiled).length(),
    1,
  )
}

///|
test "compilation snapshots arrays in nested schemas and enum values" {
  let choices = [json("{\"id\":1}")]
  let keywords = [("enum", @pjson.Array(items=choices))]
  let properties = [("person", @pjson.Object(members=keywords))]
  let schema = @pjson.Object(members=[
    ("properties", @pjson.Object(members=properties)),
  ])
  let compiled = match @moonjson-toolkit.compile_schema(schema) {
    Ok(compiled) => compiled
    Err(_) => abort("supported schema rejected")
  }
  match choices[0] {
    Object(members~) => members[0] = ("id", json("2"))
    _ => abort("expected object")
  }
  choices.push(json("{\"id\":3}"))
  keywords.push(("multipleOf", json("2")))
  properties.clear()
  assert_eq(
    @moonjson-toolkit.validate_compiled_schema(
      json("{\"person\":{\"id\":1}}"),
      compiled,
    ).length(),
    0,
  )
  assert_eq(
    @moonjson-toolkit.validate_compiled_schema(
      json("{\"person\":{\"id\":2}}"),
      compiled,
    ).length(),
    1,
  )
  assert_eq(
    @moonjson-toolkit.validate_compiled_schema(
      json("{\"person\":{\"id\":3}}"),
      compiled,
    ).length(),
    1,
  )
}

///|
test "public raw and compiled validators agree on exact numeric semantics" {
  for
    (schema_text, document_text, count) in [
      ("{\"minimum\":9007199254740993}", "9007199254740992", 1),
      ("{\"maximum\":9007199254740992}", "9007199254740993", 1),
      ("{\"maximum\":1e400}", "1e401", 1),
      ("{\"minimum\":1e-400}", "0", 1),
      ("{\"maximum\":0.1}", "0.10000000000000001", 1),
      ("{\"minimum\":-9007199254740992}", "-9007199254740993", 1),
      ("{\"maximum\":-1e400}", "-9e399", 1),
      ("{\"minimum\":-1e400,\"maximum\":-1e400}", "-10e399", 0),
      ("{\"enum\":[1]}", "1.0", 0),
      ("{\"enum\":[9007199254740992]}", "9007199254740993", 1),
      ("{\"enum\":[1e400]}", "1e401", 1),
      ("{\"enum\":[0]}", "1e-400", 1),
      (
        "{\"enum\":[{\"id\":[9007199254740992]}]}", "{\"id\":[9007199254740993]}",
        1,
      ),
      ("{\"type\":\"integer\"}", "1.2e1", 0),
      ("{\"type\":\"integer\"}", "1e-1", 1),
      ("{\"type\":\"integer\"}", "1.0e-1", 1),
      ("{\"type\":\"integer\"}", "12e-1", 1),
      ("{\"type\":\"integer\"}", "100e-2", 0),
      ("{\"type\":\"integer\"}", "0.001e3", 0),
      ("{\"type\":\"integer\"}", "0e-1000", 0),
      ("{\"maxLength\":1.2e1}", "\"abcdefghijkl\"", 0),
      ("{\"maxLength\":1.2e1}", "\"abcdefghijklm\"", 1),
    ] {
    let schema = json(schema_text)
    let document = json(document_text)
    let compiled = match @moonjson-toolkit.compile_schema(schema) {
      Ok(compiled) => compiled
      Err(_) => abort("supported schema rejected")
    }
    let direct = match @moonjson-toolkit.validate_schema(document, schema) {
      Ok(violations) => violations
      Err(_) => abort("supported schema rejected")
    }
    let reused = @moonjson-toolkit.validate_compiled_schema(document, compiled)
    assert_eq(direct.length(), count)
    assert_eq(
      direct.map(@moonjson-toolkit.render_schema_error),
      reused.map(@moonjson-toolkit.render_schema_error),
    )
  }
}

///|
test "public length preflight reports category location and reason" {
  for
    (raw, kind, reason) in [
      ("1e-1", @moonjson-toolkit.InvalidSchema, "nonnegative integer"),
      ("1e-400", @moonjson-toolkit.InvalidSchema, "nonnegative integer"),
      ("-1", @moonjson-toolkit.InvalidSchema, "nonnegative integer"),
      ("false", @moonjson-toolkit.InvalidSchema, "expected a count"),
      (
        "1000000001",
        @moonjson-toolkit.UnsupportedFeature,
        "supported character count limit",
      ),
      (
        "1e400",
        @moonjson-toolkit.UnsupportedFeature,
        "supported character count limit",
      ),
    ] {
    let schema = json("{\"properties\":{\"name\":{\"minLength\":" + raw + "}}}")
    let issues = rejected(
      "{\"properties\":{\"name\":{\"minLength\":" + raw + "}}}",
    )
    assert_eq(issues.length(), 1)
    assert_eq(issues[0].path, "properties.name.minLength")
    assert_eq(issues[0].kind, kind)
    assert_true(issues[0].message.contains(reason))
    match @moonjson-toolkit.validate_schema(json("{}"), schema) {
      Err(problems) => assert_eq(problems, issues)
      Ok(_) => abort("invalid or unsupported length was accepted")
    }
  }
}

///|
test "public validators agree on boolean const combinations and extra properties" {
  for
    (schema_text, value_text, count, path) in [
      ("true", "null", 0, ""),
      ("false", "null", 1, ""),
      ("{\"properties\":{\"x\":false}}", "{}", 0, ""),
      ("{\"properties\":{\"x\":false}}", "{\"x\":1}", 1, "x"),
      ("{\"items\":false}", "[]", 0, ""),
      ("{\"items\":false}", "[1]", 1, "[0]"),
      ("{\"const\":false}", "false", 0, ""),
      ("{\"const\":1}", "1.0", 0, ""),
      ("{\"const\":9007199254740992}", "9007199254740993", 1, ""),
      ("{\"const\":{\"multipleOf\":2}}", "{\"multipleOf\":2}", 0, ""),
      ("{\"allOf\":[{\"minimum\":0},{\"maximum\":10}]}", "11", 1, ""),
      ("{\"anyOf\":[{\"type\":\"string\"},{\"type\":\"number\"}]}", "1", 0, ""),
      (
        "{\"anyOf\":[{\"type\":\"string\"},{\"type\":\"number\"}]}", "true", 1, "",
      ),
      ("{\"oneOf\":[{\"type\":\"number\"},{\"type\":\"integer\"}]}", "1", 1, ""),
      (
        "{\"oneOf\":[{\"type\":\"number\"},{\"type\":\"integer\"}]}", "1.5", 0, "",
      ),
      (
        "{\"oneOf\":[{\"type\":\"number\"},{\"type\":\"integer\"}]}", "true", 1,
        "",
      ),
      ("{\"not\":{\"type\":\"integer\"}}", "1.5", 0, ""),
      ("{\"not\":true}", "null", 1, ""),
      ("{\"not\":false}", "null", 0, ""),
      ("{\"additionalProperties\":false}", "{\"x\":1}", 1, "x"),
      (
        "{\"additionalProperties\":{\"type\":\"integer\"}}", "{\"x\":\"bad\"}", 1,
        "x",
      ),
      (
        "{\"allOf\":[{\"properties\":{\"id\":true}},{\"additionalProperties\":false}]}",
        "{\"id\":1}", 1, "id",
      ),
    ] {
    let schema = json(schema_text)
    let value = json(value_text)
    let compiled = match @moonjson-toolkit.compile_schema(schema) {
      Ok(compiled) => compiled
      Err(_) => abort("valid schema rejected")
    }
    let direct = match @moonjson-toolkit.validate_schema(value, schema) {
      Ok(violations) => violations
      Err(_) => abort("valid schema rejected")
    }
    let reused = @moonjson-toolkit.validate_compiled_schema(value, compiled)
    assert_eq(direct.length(), count)
    assert_eq(
      direct.map(@moonjson-toolkit.render_schema_error),
      reused.map(@moonjson-toolkit.render_schema_error),
    )
    if count > 0 {
      assert_eq(direct[0].path, path)
    }
  }
}

///|
test "public compilation rejects invalid applicators and unsupported hidden branches" {
  for
    (text, path, kind) in [
      ("{\"allOf\":[]}", "allOf", @moonjson-toolkit.InvalidSchema),
      ("{\"anyOf\":[]}", "anyOf", @moonjson-toolkit.InvalidSchema),
      ("{\"oneOf\":[]}", "oneOf", @moonjson-toolkit.InvalidSchema),
      ("{\"allOf\":[null]}", "allOf[0]", @moonjson-toolkit.InvalidSchema),
      ("{\"not\":1}", "not", @moonjson-toolkit.InvalidSchema),
      (
        "{\"additionalProperties\":[]}",
        "additionalProperties",
        @moonjson-toolkit.InvalidSchema,
      ),
      (
        "{\"anyOf\":[true,{\"multipleOf\":2}]}",
        "anyOf[1].multipleOf",
        @moonjson-toolkit.UnsupportedFeature,
      ),
      (
        "{\"not\":{\"multipleOf\":2}}",
        "not.multipleOf",
        @moonjson-toolkit.UnsupportedFeature,
      ),
    ] {
    let issues = rejected(text)
    assert_eq(issues.length(), 1)
    assert_eq(issues[0].path, path)
    assert_eq(issues[0].kind, kind)
    match @moonjson-toolkit.validate_schema(json("null"), json(text)) {
      Err(problems) => assert_eq(problems, issues)
      Ok(_) => abort("schema preflight was bypassed")
    }
  }
}

///|
test "compiled combinations const objects and extra schemas own snapshots" {
  let branches = [json("{\"const\":1}"), json("{\"const\":2}")]
  let combination = match
    @moonjson-toolkit.compile_schema(
      @pjson.Object(members=[("oneOf", @pjson.Array(items=branches))]),
    ) {
    Ok(compiled) => compiled
    Err(_) => abort("valid schema rejected")
  }
  match branches[0] {
    Object(members~) => members[0] = ("const", json("3"))
    _ => abort("expected object")
  }
  branches.clear()
  branches.push(json("true"))
  branches.push(json("true"))
  assert_eq(
    @moonjson-toolkit.validate_compiled_schema(json("1"), combination).length(),
    0,
  )
  assert_eq(
    @moonjson-toolkit.validate_compiled_schema(json("3"), combination).length(),
    1,
  )

  let constant_members = [("id", json("9007199254740992"))]
  let constant = match
    @moonjson-toolkit.compile_schema(
      @pjson.Object(members=[("const", @pjson.Object(members=constant_members))]),
    ) {
    Ok(compiled) => compiled
    Err(_) => abort("valid schema rejected")
  }
  constant_members[0] = ("id", json("9007199254740993"))
  assert_eq(
    @moonjson-toolkit.validate_compiled_schema(
      json("{\"id\":9007199254740992}"),
      constant,
    ).length(),
    0,
  )
  assert_eq(
    @moonjson-toolkit.validate_compiled_schema(
      json("{\"id\":9007199254740993}"),
      constant,
    ).length(),
    1,
  )

  let extra_members = [("type", json("\"integer\""))]
  let extra = match
    @moonjson-toolkit.compile_schema(
      @pjson.Object(members=[
        ("additionalProperties", @pjson.Object(members=extra_members)),
      ]),
    ) {
    Ok(compiled) => compiled
    Err(_) => abort("valid schema rejected")
  }
  extra_members[0] = ("type", json("\"string\""))
  assert_eq(
    @moonjson-toolkit.validate_compiled_schema(json("{\"x\":1}"), extra).length(),
    0,
  )
  let violations = @moonjson-toolkit.validate_compiled_schema(
    json("{\"x\":\"bad\"}"),
    extra,
  )
  assert_eq(violations.length(), 1)
  assert_eq(violations[0].path, "x")
}
