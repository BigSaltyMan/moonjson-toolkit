///|
/// The report of checking a document against a schema, written the way a report
/// reads: one line per error, in the order they were found, and nothing at all
/// when the document matches.
fn report(document : String, schema : String) -> String {
  validate_schema(parse_ok(document), parse_ok(schema))
  .map(render_schema_error)
  .join("\n")
}

///|
/// The report of reading a schema itself, written the same way.
fn problems(schema : String) -> String {
  schema_problems(parse_ok(schema)).map(render_schema_error).join("\n")
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
  // A point with nothing but zeros after it is still a whole number, and an
  // exponent moves the point without putting anything after it.
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
test "a keyword this tool does not read is passed over" {
  // A schema written for a full validator can be handed to this one: the part of
  // it this tool does not read is not enforced, and a keyword it does not read
  // cannot make a document that was never compared to it look wrong.
  let schema =
    #|{
    #|  "$schema": "https://json-schema.org/draft/2020-12/schema",
    #|  "title": "A person",
    #|  "description": 3,
    #|  "type": "object",
    #|  "additionalProperties": false,
    #|  "anyOf": [3, "nonsense"],
    #|  "properties": {
    #|    "id": { "type": "integer", "exclusiveMinimum": 0, "format": 7 }
    #|  }
    #|}
  assert_eq(problems(schema), "")
  assert_eq(report("{\"id\":1}", schema), "")
  assert_eq(
    report("{\"id\":\"x\"}", schema),
    "id: it is a string where the schema expects an integer",
  )
  // A keyword holding something no comparison could use is still passed over
  // when it is not one this tool reads.
  assert_eq(report("1", "{\"anyOf\":3}"), "")
}

///|
test "a schema this tool cannot read says where" {
  assert_eq(
    problems("[]"),
    "(root): a schema is an object of keywords, but this is an array",
  )
  assert_eq(
    problems("\"x\""),
    "(root): a schema is an object of keywords, but this is a string",
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
    "maxLength: 2.5 is not a count of characters; a count is a whole number from 0 to 1000000000",
  )
  assert_eq(
    problems("{\"minLength\":-1}"),
    "minLength: -1 is not a count of characters; a count is a whole number from 0 to 1000000000",
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
  // `schema_problems` walks the keywords this tool reads and asks whether each
  // is in a form it can use, so a schema written entirely in those forms is read
  // without a word — and a schema holding keywords it does not read at all is
  // not a schema with anything wrong with it.
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
    #|  "pattern": "^a+$",
    #|  "additionalProperties": false,
    #|  "anyOf": [{ "type": "object" }]
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
test "a keyword this tool cannot read is not a document that does not match" {
  // The two questions are separate, and the answer to one is not the answer to
  // the other: a `type` holding a number says nothing about any document, so no
  // document is reported against it — the schema is what is reported.
  assert_eq(report("{\"a\":1}", "{\"type\":3}"), "")
  assert_true(problems("{\"type\":3}").contains("expected a JSON type name"))
  assert_eq(report("1", "{\"enum\":\"nope\"}"), "")
  assert_eq(report("1", "{\"minimum\":null}"), "")
  assert_eq(report("\"a\"", "{\"minLength\":\"2\"}"), "")
  assert_eq(report("\"a\"", "{\"pattern\":\"(\"}"), "")
  assert_eq(report("1", "{\"type\":[3]}"), "")
  assert_eq(report("{}", "{\"required\":\"id\"}"), "")
  // A name this tool cannot read in a list of them is passed over the same way,
  // so the names around it are still asked for.
  assert_eq(
    report("{}", "{\"required\":[\"id\",3]}"),
    "(root): required member \"id\" is missing",
  )
  assert_eq(report("{}", "{\"properties\":[]}"), "")
  assert_eq(report("\"a\"", "{\"pattern\":3}"), "")
  // A keyword this tool does read is read wherever it is written, even inside a
  // schema that another keyword makes no use of.
  assert_true(problems("{\"items\":{\"type\":3}}").contains("type:"))
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
