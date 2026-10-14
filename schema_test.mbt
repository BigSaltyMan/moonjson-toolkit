///|
fn json(text : String) -> @pjson.Json {
  match @pjson.parse(text) {
    Ok(value) => value
    Err(_) => abort("invalid test JSON")
  }
}

///|
test "public contains APIs agree on match counts and schema problem locations" {
  for
    (raw, data, count) in [
      (
        "{\"contains\":{\"type\":\"integer\"},\"minContains\":2,\"maxContains\":3}",
        "[1,\"x\",2]", 0,
      ),
      (
        "{\"contains\":{\"type\":\"integer\"},\"minContains\":2,\"maxContains\":3}",
        "[1,\"x\"]", 1,
      ),
      (
        "{\"contains\":{\"type\":\"integer\"},\"minContains\":2,\"maxContains\":3}",
        "[1,2,3,4]", 1,
      ),
      ("{\"contains\":true}", "[]", 1),
      ("{\"contains\":false,\"minContains\":0}", "[1]", 0),
      ("{\"minContains\":2,\"maxContains\":0}", "[]", 0),
      (
        "{\"contains\":{\"const\":9007199254740992},\"minContains\":2}", "[9007199254740992,9007199254740993]",
        1,
      ),
    ] {
    let schema = json(raw)
    let compiled = match @moonjson-toolkit.compile_schema(schema) {
      Ok(compiled) => compiled
      Err(_) => abort("valid contains schema refused")
    }
    let direct = match @moonjson-toolkit.validate_schema(json(data), schema) {
      Ok(errors) => errors
      Err(_) => abort("unexpected failure")
    }
    let reused = match
      @moonjson-toolkit.validate_compiled_schema(json(data), compiled) {
      Ok(errors) => errors
      Err(_) => abort("unexpected failure")
    }
    assert_eq(direct.length(), count)
    assert_eq(
      direct.map(@moonjson-toolkit.render_schema_error),
      reused.map(@moonjson-toolkit.render_schema_error),
    )
  }
  for
    (raw, path, kind) in [
      ("{\"contains\":1}", "contains", @moonjson-toolkit.InvalidSchema),
      ("{\"minContains\":-1}", "minContains", @moonjson-toolkit.InvalidSchema),
      (
        "{\"maxContains\":1000000001}",
        "maxContains",
        @moonjson-toolkit.UnsupportedFeature,
      ),
      (
        "{\"contains\":{\"$ref\":\"#/missing\"},\"minContains\":0}",
        "contains.$ref",
        @moonjson-toolkit.InvalidSchema,
      ),
    ] {
    match @moonjson-toolkit.validate_schema(json("[]"), json(raw)) {
      Err(@moonjson-toolkit.SchemaProblems(problems)) => {
        assert_eq(problems[0].path, path)
        assert_eq(problems[0].kind, kind)
      }
      _ => abort("contains precheck was bypassed")
    }
  }
}

///|
test "contains snapshots and repeated validation do not retain mutations or failures" {
  let child = [("const", json("1"))]
  let members = [
    ("contains", @pjson.Object(members=child)),
    ("minContains", json("2")),
  ]
  let schema = @pjson.Object(members~)
  let compiled = match @moonjson-toolkit.compile_schema(schema) {
    Ok(compiled) => compiled
    Err(_) => abort("valid contains schema refused")
  }
  child[0] = ("const", json("2"))
  members[1] = ("minContains", json("0"))
  members.clear()
  for _ in 0..<3 {
    assert_true(
      @moonjson-toolkit.validate_compiled_schema(json("[1,1.0]"), compiled)
      is Ok([]),
    )
    assert_true(
      @moonjson-toolkit.validate_compiled_schema(json("[2,2]"), compiled)
      is Ok([_]),
    )
  }
  let recursive = match
    @moonjson-toolkit.compile_schema(
      json(
        "{\"contains\":{\"properties\":{\"loop\":{\"$ref\":\"#/contains/properties/loop\"}}}}",
      ),
    ) {
    Ok(compiled) => compiled
    Err(_) => abort("recursive contains refused")
  }
  assert_true(
    @moonjson-toolkit.validate_compiled_schema(
      json("[{}, {\"loop\":1}]"),
      recursive,
    )
    is Err(
      { kind: @moonjson-toolkit.ReferenceCycle, instance_path: "/1/loop", .. }
    ),
  )
  assert_true(
    @moonjson-toolkit.validate_compiled_schema(json("[{}]"), recursive)
    is Ok([]),
  )
  match
    @moonjson-toolkit.validate_schema(
      json("[1]"),
      json("{\"contains\":{\"$ref\":\"#/contains\"}}"),
    ) {
    Err(@moonjson-toolkit.EvaluationFailed(error)) =>
      assert_eq(error.instance_path, "/0")
    _ => abort("contains cycle became an ordinary nonmatch")
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
      ("{\"unevaluatedProperties\":false}", "unevaluatedProperties"),
      (
        "{\"anyOf\":[true,{\"unevaluatedProperties\":false}]}", "anyOf[1].unevaluatedProperties",
      ),
      ("{\"$ref\":\"other.json#/$defs/person\"}", "$ref"),
      (
        "{\"properties\":{\"id\":{\"minimum\":0,\"unevaluatedProperties\":false}}}",
        "properties.id.unevaluatedProperties",
      ),
      (
        "{\"items\":{\"additionalProperties\":{\"unevaluatedProperties\":false}}}",
        "items.additionalProperties.unevaluatedProperties",
      ),
    ] {
    let problems = rejected(schema)
    assert_eq(problems.length(), 1)
    assert_eq(problems[0].path, path)
    assert_eq(problems[0].kind, @moonjson-toolkit.UnsupportedFeature)
    assert_eq(
      problems[0].message,
      if path == "$ref" {
        "external references are not supported"
      } else {
        "keyword is not supported"
      },
    )
    assert_true(
      @moonjson-toolkit.validate_schema(json("{}"), json(schema)) is Err(_),
    )
  }
}

///|
test "schema mechanisms remain unsupported and booleans compile" {
  for keyword in ["$id", "$anchor", "$dynamicRef", "$vocabulary", "unknown"] {
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
  assert_eq(checked_errors(json("2"), compiled).length(), 0)
  match @moonjson-toolkit.validate_schema(json("-1"), schema) {
    Ok(errors) => assert_eq(errors.length(), 1)
    Err(_) => abort("supported schema rejected")
  }
  assert_eq(checked_errors(json("-1"), compiled).length(), 1)
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
  keywords.push(("unevaluatedProperties", json("false")))
  properties.clear()
  assert_eq(
    checked_errors(json("{\"person\":{\"id\":1}}"), compiled).length(),
    0,
  )
  assert_eq(
    checked_errors(json("{\"person\":{\"id\":2}}"), compiled).length(),
    1,
  )
  assert_eq(
    checked_errors(json("{\"person\":{\"id\":3}}"), compiled).length(),
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
    let reused = checked_errors(document, compiled)
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
      Err(@moonjson-toolkit.SchemaProblems(problems)) =>
        assert_eq(problems, issues)
      Err(_) => abort("unexpected evaluation failure")
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
    let reused = checked_errors(value, compiled)
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
        "{\"anyOf\":[true,{\"unevaluatedProperties\":false}]}",
        "anyOf[1].unevaluatedProperties",
        @moonjson-toolkit.UnsupportedFeature,
      ),
      (
        "{\"not\":{\"unevaluatedProperties\":false}}",
        "not.unevaluatedProperties",
        @moonjson-toolkit.UnsupportedFeature,
      ),
    ] {
    let issues = rejected(text)
    assert_eq(issues.length(), 1)
    assert_eq(issues[0].path, path)
    assert_eq(issues[0].kind, kind)
    match @moonjson-toolkit.validate_schema(json("null"), json(text)) {
      Err(@moonjson-toolkit.SchemaProblems(problems)) =>
        assert_eq(problems, issues)
      Err(_) => abort("unexpected evaluation failure")
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
  assert_eq(checked_errors(json("1"), combination).length(), 0)
  assert_eq(checked_errors(json("3"), combination).length(), 1)

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
    checked_errors(json("{\"id\":9007199254740992}"), constant).length(),
    0,
  )
  assert_eq(
    checked_errors(json("{\"id\":9007199254740993}"), constant).length(),
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
  assert_eq(checked_errors(json("{\"x\":1}"), extra).length(), 0)
  let violations = checked_errors(json("{\"x\":\"bad\"}"), extra)
  assert_eq(violations.length(), 1)
  assert_eq(violations[0].path, "x")
}

///|
test "public numeric keyword validators agree before and after compilation" {
  for
    (schema_text, value_text, count) in [
      ("{\"exclusiveMinimum\":1}", "1.0", 1),
      ("{\"exclusiveMaximum\":1}", "1e0", 1),
      ("{\"exclusiveMinimum\":9007199254740992}", "9007199254740993", 0),
      ("{\"exclusiveMaximum\":1e400}", "1e400", 1),
      ("{\"multipleOf\":0.1}", "0.3", 0),
      ("{\"multipleOf\":0.1}", "0.30000000000000004", 1),
      ("{\"multipleOf\":0.2}", "0.3", 1),
      ("{\"multipleOf\":0.03}", "0.21", 0),
      ("{\"multipleOf\":0.1}", "-0.3", 0),
      ("{\"multipleOf\":2}", "-0.0", 0),
      ("{\"multipleOf\":2}", "9007199254740993", 1),
      ("{\"multipleOf\":1e-401}", "1e-400", 0),
      ("{\"multipleOf\":3e-400}", "1e-400", 1),
      ("{\"multipleOf\":2}", "\"hello\"", 0),
      ("{\"multipleOf\":2}", "1e100000000000000000000", 0),
      ("{\"multipleOf\":3}", "1e100000000000000000000", 1),
      ("{\"multipleOf\":1e-100000000000000000000}", "1", 0),
      ("{\"multipleOf\":1}", "1e-100000000000000000000", 1),
      ("{\"anyOf\":[true,{\"multipleOf\":2}]}", "3", 0),
      ("{\"not\":{\"multipleOf\":2}}", "3", 0),
      ("{\"not\":{\"multipleOf\":2}}", "4", 1),
    ] {
    let schema = json(schema_text)
    let value = json(value_text)
    let compiled = match @moonjson-toolkit.compile_schema(schema) {
      Ok(compiled) => compiled
      Err(_) => abort("valid numeric schema rejected")
    }
    let direct = match @moonjson-toolkit.validate_schema(value, schema) {
      Ok(violations) => violations
      Err(_) => abort("valid numeric schema rejected")
    }
    assert_eq(direct.length(), count)
    assert_eq(
      direct.map(@moonjson-toolkit.render_schema_error),
      checked_errors(value, compiled).map(@moonjson-toolkit.render_schema_error),
    )
  }
}

///|
test "public numeric preflight rejects invalid divisors even in hidden branches" {
  for
    (schema_text, path) in [
      ("{\"multipleOf\":0}", "multipleOf"),
      ("{\"multipleOf\":-0.0}", "multipleOf"),
      ("{\"multipleOf\":-2}", "multipleOf"),
      ("{\"multipleOf\":\"2\"}", "multipleOf"),
      ("{\"multipleOf\":0e1000000}", "multipleOf"),
      ("{\"anyOf\":[true,{\"multipleOf\":0}]}", "anyOf[1].multipleOf"),
      ("{\"not\":{\"multipleOf\":0}}", "not.multipleOf"),
      (
        "{\"properties\":{\"price\":{\"exclusiveMinimum\":true}}}", "properties.price.exclusiveMinimum",
      ),
    ] {
    let issues = rejected(schema_text)
    assert_eq(issues.length(), 1)
    assert_eq(issues[0].kind, @moonjson-toolkit.InvalidSchema)
    assert_eq(issues[0].path, path)
    match @moonjson-toolkit.validate_schema(json("{}"), json(schema_text)) {
      Err(@moonjson-toolkit.SchemaProblems(problems)) =>
        assert_eq(problems, issues)
      Err(_) => abort("unexpected evaluation failure")
      Ok(_) => abort("invalid numeric schema was accepted")
    }
  }
}

///|
test "compiled numeric assertions retain their private snapshot" {
  let members = [
    ("exclusiveMinimum", json("0")),
    ("multipleOf", json("0.01")),
    ("exclusiveMaximum", json("100")),
  ]
  let compiled = match
    @moonjson-toolkit.compile_schema(
      @pjson.Object(members=[
        (
          "properties",
          @pjson.Object(members=[("price", @pjson.Object(members~))]),
        ),
      ]),
    ) {
    Ok(compiled) => compiled
    Err(_) => abort("valid schema rejected")
  }
  members[0] = ("exclusiveMinimum", json("1000"))
  members[1] = ("multipleOf", json("2"))
  members[2] = ("exclusiveMaximum", json("0"))
  assert_eq(checked_errors(json("{\"price\":12.34}"), compiled).length(), 0)
  for
    (value, reason) in [
      ("12.345", "it is not a multiple of 0.01"),
      ("0", "it is not greater than the exclusive minimum 0"),
      ("100", "it is not less than the exclusive maximum 100"),
    ] {
    let violations = checked_errors(json("{\"price\":" + value + "}"), compiled)
    assert_eq(violations.length(), 1)
    assert_eq(violations[0].path, "price")
    assert_eq(violations[0].message, reason)
  }
}

///|
test "public validators agree on array counts uniqueness and tuple suffixes" {
  for
    (schema_text, value_text, count, path) in [
      ("{\"minItems\":2}", "[1]", 1, ""),
      ("{\"minItems\":2.0}", "[1,2]", 0, ""),
      ("{\"maxItems\":0}", "[]", 0, ""),
      ("{\"maxItems\":0}", "[null]", 1, ""),
      ("{\"uniqueItems\":true}", "[1,1.0]", 1, ""),
      ("{\"uniqueItems\":false}", "[1,1]", 0, ""),
      ("{\"uniqueItems\":true}", "[true,1]", 0, ""),
      ("{\"uniqueItems\":true}", "[9007199254740992,9007199254740993]", 0, ""),
      (
        "{\"uniqueItems\":true}", "[{\"a\":1,\"b\":2},{\"b\":2,\"a\":1.0}]", 1, "",
      ),
      ("{\"prefixItems\":[false]}", "[]", 0, ""),
      ("{\"prefixItems\":[false]}", "[1]", 1, "[0]"),
      ("{\"prefixItems\":[true],\"items\":false}", "[1]", 0, ""),
      ("{\"prefixItems\":[true],\"items\":false}", "[1,2]", 1, "[1]"),
      ("{\"items\":false}", "[1]", 1, "[0]"),
      (
        "{\"prefixItems\":[{\"type\":\"integer\"}],\"items\":{\"type\":\"string\"}}",
        "[1,\"a\"]", 0, "",
      ),
      (
        "{\"items\":{\"type\":\"string\"},\"prefixItems\":[{\"type\":\"integer\"}]}",
        "[1,2]", 1, "[1]",
      ),
      (
        "{\"allOf\":[{\"prefixItems\":[true]}],\"items\":false}", "[1]", 1, "[0]",
      ),
      (
        "{\"minItems\":1,\"maxItems\":0,\"uniqueItems\":true,\"prefixItems\":[false]}",
        "null", 0, "",
      ),
    ] {
    let schema = json(schema_text)
    let value = json(value_text)
    let compiled = match @moonjson-toolkit.compile_schema(schema) {
      Ok(compiled) => compiled
      Err(_) => abort("valid array schema rejected")
    }
    let direct = match @moonjson-toolkit.validate_schema(value, schema) {
      Ok(violations) => violations
      Err(_) => abort("valid array schema rejected")
    }
    assert_eq(direct.length(), count)
    assert_eq(
      direct.map(@moonjson-toolkit.render_schema_error),
      checked_errors(value, compiled).map(@moonjson-toolkit.render_schema_error),
    )
    if count > 0 {
      assert_eq(direct[0].path, path)
    }
  }
}

///|
test "public array preflight preserves categories and precise schema locations" {
  for
    (text, kind, path) in [
      ("{\"minItems\":-1}", @moonjson-toolkit.InvalidSchema, "minItems"),
      ("{\"maxItems\":1e-400}", @moonjson-toolkit.InvalidSchema, "maxItems"),
      (
        "{\"maxItems\":1000000001}",
        @moonjson-toolkit.UnsupportedFeature,
        "maxItems",
      ),
      (
        "{\"uniqueItems\":\"true\"}",
        @moonjson-toolkit.InvalidSchema,
        "uniqueItems",
      ),
      ("{\"prefixItems\":[]}", @moonjson-toolkit.InvalidSchema, "prefixItems"),
      (
        "{\"prefixItems\":false}",
        @moonjson-toolkit.InvalidSchema,
        "prefixItems",
      ),
      (
        "{\"prefixItems\":[null]}",
        @moonjson-toolkit.InvalidSchema,
        "prefixItems[0]",
      ),
      (
        "{\"maxItems\":0,\"prefixItems\":[true,{\"$ref\":\"other.json#/missing\"}]}",
        @moonjson-toolkit.UnsupportedFeature,
        "prefixItems[1].$ref",
      ),
      (
        "{\"prefixItems\":[true],\"items\":{\"multipleOf\":0}}",
        @moonjson-toolkit.InvalidSchema,
        "items.multipleOf",
      ),
      ("{\"items\":[]}", @moonjson-toolkit.InvalidSchema, "items"),
      (
        "{\"additionalItems\":false}",
        @moonjson-toolkit.UnsupportedFeature,
        "additionalItems",
      ),
    ] {
    let issues = rejected(text)
    assert_eq(issues.length(), 1)
    assert_eq(issues[0].kind, kind)
    assert_eq(issues[0].path, path)
    match @moonjson-toolkit.validate_schema(json("[]"), json(text)) {
      Err(@moonjson-toolkit.SchemaProblems(problems)) =>
        assert_eq(problems, issues)
      Err(_) => abort("unexpected evaluation failure")
      Ok(_) => abort("array preflight was bypassed")
    }
  }
}

///|
test "compiled tuple snapshots are isolated and unique validation never rewrites arrays" {
  let inner = [("type", json("\"integer\""))]
  let schemas = [
    @pjson.Object(members=[
      (
        "properties",
        @pjson.Object(members=[("id", @pjson.Object(members=inner))]),
      ),
    ]),
    json("{\"type\":\"string\"}"),
  ]
  let compiled = match
    @moonjson-toolkit.compile_schema(
      @pjson.Object(members=[
        ("prefixItems", @pjson.Array(items=schemas)),
        ("items", json("false")),
      ]),
    ) {
    Ok(compiled) => compiled
    Err(_) => abort("valid tuple schema rejected")
  }
  inner[0] = ("type", json("\"string\""))
  schemas.push(json("true"))
  schemas.clear()
  assert_eq(checked_errors(json("[{\"id\":1},\"a\"]"), compiled).length(), 0)
  for
    (text, path) in [
      ("[{\"id\":\"bad\"},\"a\"]", "[0].id"),
      ("[{\"id\":1},2]", "[1]"),
      ("[{\"id\":1},\"a\",true]", "[2]"),
    ] {
    let violations = checked_errors(json(text), compiled)
    assert_eq(violations.length(), 1)
    assert_eq(violations[0].path, path)
  }
  for
    text in [
      "[1,2,1.0]", "[[1,2],[2,1]]", "[{\"a\":1,\"b\":2},{\"b\":2,\"a\":1.0}]",
    ] {
    let value = json(text)
    let before = @moonjson-toolkit.format_compact(value)
    let schema = json("{\"uniqueItems\":true}")
    let checked = match @moonjson-toolkit.compile_schema(schema) {
      Ok(compiled) => compiled
      Err(_) => abort("valid schema rejected")
    }
    let direct = @moonjson-toolkit.validate_schema(value, schema)
    assert_true(direct is Ok(_))
    assert_eq(@moonjson-toolkit.format_compact(value), before)
    let _ = checked_errors(value, checked)
    assert_eq(@moonjson-toolkit.format_compact(value), before)
  }
}

///|
test "public object validation agrees with compiled regex validation" {
  for
    (schema_text, value_text, count, path) in [
      ("{\"minProperties\":1}", "{}", 1, ""),
      ("{\"maxProperties\":0}", "{}", 0, ""),
      ("{\"maxProperties\":0}", "{\"x\":null}", 1, ""),
      ("{\"maxProperties\":1}", "{\"x\":{\"a\":1,\"b\":2}}", 0, ""),
      ("{\"patternProperties\":{}}", "{\"x\":1}", 0, ""),
      (
        "{\"patternProperties\":{\"x\":false}}", "{\"prefix_x_suffix\":1}", 1, "prefix_x_suffix",
      ),
      ("{\"patternProperties\":{\"^x\":false}}", "{\"y\":1}", 0, ""),
      (
        "{\"patternProperties\":{\"^x\":true},\"additionalProperties\":false}", "{\"x1\":1}",
        0, "",
      ),
      (
        "{\"patternProperties\":{\"^x\":true},\"additionalProperties\":false}", "{\"y\":1}",
        1, "y",
      ),
      (
        "{\"patternProperties\":{\"^x\":{\"type\":\"integer\"}},\"additionalProperties\":false}",
        "{\"x1\":\"bad\"}", 1, "x1",
      ),
      (
        "{\"properties\":{\"data\":{\"patternProperties\":{\"^x\":{\"type\":\"integer\"}}}}}",
        "{\"data\":{\"x1\":\"bad\"}}", 1, "data.x1",
      ),
      (
        "{\"allOf\":[{\"patternProperties\":{\"^x\":true}},{\"additionalProperties\":false}]}",
        "{\"x\":1}", 1, "x",
      ),
      ("{\"items\":{\"pattern\":\"^x\"}}", "[\"x\",\"y\"]", 1, "[1]"),
      (
        "{\"minProperties\":1,\"patternProperties\":{\"\":false}}", "null", 0, "",
      ),
    ] {
    let schema = json(schema_text)
    let value = json(value_text)
    let compiled = match @moonjson-toolkit.compile_schema(schema) {
      Ok(compiled) => compiled
      Err(_) => abort("valid object schema rejected")
    }
    let direct = match @moonjson-toolkit.validate_schema(value, schema) {
      Ok(violations) => violations
      Err(_) => abort("valid object schema rejected")
    }
    assert_eq(direct.length(), count)
    assert_eq(
      direct.map(@moonjson-toolkit.render_schema_error),
      checked_errors(value, compiled).map(@moonjson-toolkit.render_schema_error),
    )
    if count > 0 {
      assert_eq(direct[0].path, path)
    }
  }
  let ordinary = "{\"patternProperties\":{\"[\":false},\"pattern\":\"(\"}"
  for
    schema in ["{\"const\":" + ordinary + "}", "{\"enum\":[" + ordinary + "]}"] {
    assert_true(
      @moonjson-toolkit.validate_schema(json(ordinary), json(schema)) is Ok([]),
    )
  }
}

///|
test "public object preflight classifies patterns counts and nested schema failures" {
  for
    (schema_text, kind, path) in [
      (
        "{\"minProperties\":-1}",
        @moonjson-toolkit.InvalidSchema,
        "minProperties",
      ),
      (
        "{\"maxProperties\":1000000001}",
        @moonjson-toolkit.UnsupportedFeature,
        "maxProperties",
      ),
      ("{\"pattern\":\"[\"}", @moonjson-toolkit.InvalidSchema, "pattern"),
      (
        "{\"pattern\":\"(?=x)\"}",
        @moonjson-toolkit.UnsupportedFeature,
        "pattern",
      ),
      (
        "{\"patternProperties\":{\"[\":true}}",
        @moonjson-toolkit.InvalidSchema,
        "patternProperties[\"[\"]",
      ),
      (
        "{\"patternProperties\":{\"(?=x)\":true}}",
        @moonjson-toolkit.UnsupportedFeature,
        "patternProperties[\"(?=x)\"]",
      ),
      (
        "{\"patternProperties\":{\"^x\":{\"type\":123}}}",
        @moonjson-toolkit.InvalidSchema,
        "patternProperties[\"^x\"].type",
      ),
      (
        "{\"patternProperties\":{\"^x\":{\"$ref\":\"other.json#/missing\"}}}",
        @moonjson-toolkit.UnsupportedFeature,
        "patternProperties[\"^x\"].$ref",
      ),
      (
        "{\"anyOf\":[true,{\"patternProperties\":{\"[\":true}}]}",
        @moonjson-toolkit.InvalidSchema,
        "anyOf[1].patternProperties[\"[\"]",
      ),
    ] {
    let issues = rejected(schema_text)
    assert_eq(issues.length(), 1)
    assert_eq(issues[0].kind, kind)
    assert_eq(issues[0].path, path)
    match @moonjson-toolkit.validate_schema(json("{}"), json(schema_text)) {
      Err(@moonjson-toolkit.SchemaProblems(problems)) =>
        assert_eq(problems, issues)
      Err(_) => abort("unexpected evaluation failure")
      Ok(_) => abort("object schema preflight was bypassed")
    }
  }
}

///|
test "compiled pattern mappings own snapshots and matches never retain input state" {
  let inner = [("type", json("\"integer\""))]
  let rules = [("^x", @pjson.Object(members=inner))]
  let schema = @pjson.Object(members=[
    ("patternProperties", @pjson.Object(members=rules)),
    ("additionalProperties", json("false")),
  ])
  let compiled = match @moonjson-toolkit.compile_schema(schema) {
    Ok(compiled) => compiled
    Err(_) => abort("valid schema rejected")
  }
  inner[0] = ("type", json("\"string\""))
  rules[0] = ("[", json("true"))
  rules.clear()
  for _ in 0..<3 {
    for
      (text, count, path) in [
        ("{\"x1\":1}", 0, ""),
        ("{\"x1\":\"bad\"}", 1, "x1"),
        ("{\"y\":1}", 1, "y"),
        ("{}", 0, ""),
      ] {
      let violations = checked_errors(json(text), compiled)
      assert_eq(violations.length(), count)
      if count > 0 {
        assert_eq(violations[0].path, path)
      }
    }
  }
  let regex = match
    @moonjson-toolkit.compile_schema(json("{\"pattern\":\"^x+$\"}")) {
    Ok(compiled) => compiled
    Err(_) => abort("valid schema rejected")
  }
  for _ in 0..<3 {
    assert_eq(checked_errors(json("\"xx\""), regex).length(), 0)
    assert_eq(checked_errors(json("\"y\""), regex).length(), 1)
    assert_eq(checked_errors(json("\"x\""), regex).length(), 0)
  }
}

///|
fn checked_errors(
  value : @pjson.Json,
  compiled : @moonjson-toolkit.CompiledSchema,
) -> Array[@moonjson-toolkit.SchemaError] {
  match @moonjson-toolkit.validate_compiled_schema(value, compiled) {
    Ok(errors) => errors
    Err(_) =>
      abort("unexpected evaluation failure in a nonrecursive regression")
  }
}

///|
test "public reference validation distinguishes compile evaluation and data failures" {
  let schema = json(
    "{\"$defs\":{\"n\":{\"type\":\"integer\"}},\"$ref\":\"#/$defs/n\",\"minimum\":2}",
  )
  let compiled = match @moonjson-toolkit.compile_schema(schema) {
    Ok(compiled) => compiled
    Err(_) => abort("local reference refused")
  }
  for (input, count) in [("3", 0), ("1", 1), ("\"x\"", 1)] {
    let direct = match @moonjson-toolkit.validate_schema(json(input), schema) {
      Ok(violations) => violations.map(@moonjson-toolkit.render_schema_error)
      Err(_) => abort("unexpected execution failure")
    }
    let reused = match
      @moonjson-toolkit.validate_compiled_schema(json(input), compiled) {
      Ok(violations) => violations.map(@moonjson-toolkit.render_schema_error)
      Err(_) => abort("unexpected execution failure")
    }
    assert_eq(direct, reused)
    assert_eq(direct.length(), count)
  }
  match
    @moonjson-toolkit.validate_schema(
      json("null"),
      json("{\"$ref\":\"#/missing\"}"),
    ) {
    Err(@moonjson-toolkit.SchemaProblems(problems)) => {
      assert_eq(problems[0].kind, @moonjson-toolkit.InvalidSchema)
      assert_eq(problems[0].path, "$ref")
    }
    _ => abort("missing target did not fail compilation")
  }
  match
    @moonjson-toolkit.validate_schema(json("null"), json("{\"$ref\":\"#\"}")) {
    Err(@moonjson-toolkit.EvaluationFailed(error)) => {
      assert_eq(error.kind, @moonjson-toolkit.ReferenceCycle)
      assert_eq(error.instance_path, "")
      assert_eq(error.schema_path, "/$ref")
    }
    _ => abort("cycle did not propagate through the raw interface")
  }
}

///|
test "compiled references definitions and explicitly referenced data are isolated snapshots" {
  let target = [("type", json("\"integer\""))]
  let defs = [("n", @pjson.Object(members=target))]
  let ref_member = [("$ref", json("\"#/$defs/n\""))]
  let keywords = [
    ("$defs", @pjson.Object(members=defs)),
    (
      "properties",
      @pjson.Object(members=[("x", @pjson.Object(members=ref_member))]),
    ),
  ]
  let schema = @pjson.Object(members=keywords)
  let compiled = match @moonjson-toolkit.compile_schema(schema) {
    Ok(compiled) => compiled
    Err(_) => abort("reference schema refused")
  }
  target[0] = ("type", json("\"string\""))
  defs.clear()
  ref_member[0] = ("$ref", json("\"#\""))
  keywords.clear()
  assert_true(
    @moonjson-toolkit.validate_compiled_schema(json("{\"x\":1}"), compiled)
    is Ok([]),
  )
  assert_true(
    @moonjson-toolkit.validate_compiled_schema(
      json("{\"x\":\"bad\"}"),
      compiled,
    )
    is Ok([_]),
  )
  let ordinary = [("type", json("\"number\""))]
  let schema = @pjson.Object(members=[
    ("default", @pjson.Object(members=ordinary)),
    ("$ref", json("\"#/default\"")),
  ])
  let compiled = match @moonjson-toolkit.compile_schema(schema) {
    Ok(compiled) => compiled
    Err(_) => abort("explicitly referenced data refused")
  }
  ordinary[0] = ("type", json("\"string\""))
  assert_true(
    @moonjson-toolkit.validate_compiled_schema(json("1"), compiled) is Ok([]),
  )
}

///|
test "public compiled evaluation state resets after cycles and resource failures" {
  let raw = "{\"type\":\"object\",\"properties\":{\"loop\":{\"$ref\":\"#/properties/loop\"},\"next\":{\"$ref\":\"#\"}}}"
  let compiled = match @moonjson-toolkit.compile_schema(json(raw)) {
    Ok(compiled) => compiled
    Err(_) => abort("recursive schema refused")
  }
  assert_true(
    @moonjson-toolkit.validate_compiled_schema(json("{\"loop\":1}"), compiled)
    is Err({ kind: @moonjson-toolkit.ReferenceCycle, .. }),
  )
  let mut deep = json("{}")
  for _ in 0..<70 {
    deep = @pjson.Object(members=[("next", deep)])
  }
  assert_true(
    @moonjson-toolkit.validate_compiled_schema(deep, compiled)
    is Err({ kind: @moonjson-toolkit.ResourceLimit, .. }),
  )
  assert_true(
    @moonjson-toolkit.validate_schema(deep, json(raw))
    is Err(
      @moonjson-toolkit.EvaluationFailed(
        { kind: @moonjson-toolkit.ResourceLimit, .. }
      )
    ),
  )
  for _ in 0..<3 {
    assert_true(
      @moonjson-toolkit.validate_compiled_schema(
        json("{\"next\":{}}"),
        compiled,
      )
      is Ok([]),
    )
  }
}
