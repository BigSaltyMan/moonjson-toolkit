///|
/// The type a document is turned into, under the name `Root`.
fn emitted(text : String) -> String {
  emit_moonbit(parse_ok(text), "Root")
}

///|
/// The declarations of an emitted type, without the header comment above them.
///
/// The header is the same in every answer, so it is checked once on its own and
/// every other test states the part that depends on the document. What is left
/// is the whole of the rest of the output, blank lines and all, since the layout
/// is half of what a pasted type is.
fn declarations(text : String) -> String {
  match text.find("pub ") {
    Some(start) => text.exact_view(start~).to_owned()
    None => abort("the emitted type has no declarations in it")
  }
}

///|
/// What a document becomes, declarations only.
fn emitted_declarations(text : String) -> String {
  declarations(emitted(text))
}

///|
test "an object becomes a struct of its fields, in the order it wrote them" {
  assert_eq(
    emitted_declarations(
      "{\"name\":\"moon\",\"version\":1,\"score\":1.5,\"ok\":true}",
    ),
    "pub struct Root {\n" +
    "  name : String\n" +
    "  version : Int\n" +
    "  score : Double\n" +
    "  ok : Bool\n" +
    "} derive(FromJson, ToJson)\n" +
    "\n" +
    "pub extend Root with FromJson::{from_json}\n" +
    "pub extend Root with ToJson::{to_json}\n",
  )
}

///|
test "a nested object is a struct of its own, named after the path to it" {
  // The path is what the name is made of, so a document holding two objects of
  // the same shape gives two types with two names rather than one shared type:
  // the name is the answer to "where in the document is this?", which is the
  // question a reader pasting the code in has.
  assert_eq(
    emitted_declarations("{\"meta\":{\"owner\":\"me\"},\"rows\":{\"id\":1}}"),
    "pub struct Root {\n" +
    "  meta : RootMeta\n" +
    "  rows : RootRows\n" +
    "} derive(FromJson, ToJson)\n" +
    "\n" +
    "pub extend Root with FromJson::{from_json}\n" +
    "pub extend Root with ToJson::{to_json}\n" +
    "\n" +
    "pub struct RootMeta {\n" +
    "  owner : String\n" +
    "} derive(FromJson, ToJson)\n" +
    "\n" +
    "pub extend RootMeta with FromJson::{from_json}\n" +
    "pub extend RootMeta with ToJson::{to_json}\n" +
    "\n" +
    "pub struct RootRows {\n" +
    "  id : Int\n" +
    "} derive(FromJson, ToJson)\n" +
    "\n" +
    "pub extend RootRows with FromJson::{from_json}\n" +
    "pub extend RootRows with ToJson::{to_json}\n",
  )
  // Nesting goes on down the path, so a struct inside a struct inside the root
  // is named for all three of them.
  assert_true(
    emitted_declarations("{\"a\":{\"b\":{\"c\":1}}}").contains(
      "pub struct RootAB {",
    ),
  )
}

///|
test "a list of records becomes one type for all of them" {
  // The union of the records is what the list holds, not the first record: a
  // type built from one of them would refuse the rest of the list.
  assert_eq(
    emitted_declarations("[{\"id\":1,\"tag\":\"a\"},{\"id\":2,\"tag\":\"b\"}]"),
    "pub type Root = Array[RootItem]\n" +
    "\n" +
    "pub struct RootItem {\n" +
    "  id : Int\n" +
    "  tag : String\n" +
    "} derive(FromJson, ToJson)\n" +
    "\n" +
    "pub extend RootItem with FromJson::{from_json}\n" +
    "pub extend RootItem with ToJson::{to_json}\n",
  )
  // The records are merged rather than replaced, so a member only the second of
  // them has is a member of the type as well.
  assert_eq(
    emitted_declarations("[{\"a\":1},{\"a\":2,\"b\":3}]"),
    "pub type Root = Array[RootItem]\n" +
    "\n" +
    "pub struct RootItem {\n" +
    "  a : Int\n" +
    "  b : Int?\n" +
    "} derive(FromJson, ToJson)\n" +
    "\n" +
    "pub extend RootItem with FromJson::{from_json}\n" +
    "pub extend RootItem with ToJson::{to_json}\n",
  )
}

///|
test "a member that is missing or null is a member that may be missing" {
  // A null is a value of a shape the sample does not show, which is what a `Json`
  // is: the key is in the document, and what is under it could be anything.
  assert_eq(
    emitted_declarations("{\"a\":null,\"b\":null}"),
    "pub struct Root {\n" +
    "  a : Json\n" +
    "  b : Json\n" +
    "} derive(FromJson, ToJson)\n" +
    "\n" +
    "pub extend Root with FromJson::{from_json}\n" +
    "pub extend Root with ToJson::{to_json}\n",
  )
  assert_true(
    emitted_declarations("{\"a\":null,\"b\":1}").contains("a : Json\n"),
  )
  assert_true(
    emitted_declarations("{\"a\":null,\"b\":1}").contains("b : Int\n"),
  )
  // A value in one place and a null in another is a `Json` and not a `T?`. The
  // two are not two spellings of one type: an optional member is read by
  // decoding whatever is there as the type inside it, so a null where an `Int?`
  // was expected is reported as a number that is not a number, while a `Json`
  // takes the null as the value it is.
  assert_true(
    emitted_declarations("[{\"a\":1},{\"a\":null}]").contains("a : Json\n"),
  )
  assert_true(emitted_declarations("[1,null]").contains("Array[Json]"))
  // An empty array is the other kind of nothing: it says nothing about what
  // belongs in it, so what belongs in it is left as whatever turns up.
  assert_true(
    emitted_declarations("[]").contains("pub type Root = Array[Json]"),
  )
  // A member the sample holds in one record and not in the next is optional even
  // when what it holds is a `Json`: `Json` takes any value that is there, and
  // the key still has to be there for the derived decoder to find it.
  assert_true(
    emitted_declarations("[{\"a\":1,\"b\":null},{\"a\":2}]").contains(
      "b : Json?",
    ),
  )
  assert_true(
    emitted_declarations("[{\"a\":1,\"b\":\"x\"},{\"a\":2,\"b\":1},{\"a\":3}]").contains(
      "b : Json?",
    ),
  )
  // A member that is there in every record and holds a list in one of them and
  // nothing in the next is a `Json?` for the same two reasons.
  assert_true(
    emitted_declarations("[{\"a\":[1]},{\"a\":null},{\"b\":2}]").contains(
      "a : Json?",
    ),
  )
  // Two nulls are a null: a member every record holds as null is a member of no
  // shape, and nothing is added to it for having been seen twice.
  assert_true(
    emitted_declarations("[{\"a\":null},{\"a\":null}]").contains("a : Json\n"),
  )
  // A member that is already optional stays as it is when a later record leaves
  // it out as well: optional twice is still one question mark.
  assert_true(
    emitted_declarations("[{\"a\":{\"x\":1}},{\"b\":1},{\"b\":2}]").contains(
      "a : RootItemA?\n",
    ),
  )
}

///|
test "a list of lists is an array of arrays, and a list of objects of structs" {
  assert_true(
    emitted_declarations("[[1,2],[3]]").contains(
      "pub type Root = Array[Array[Int]]",
    ),
  )
  // A null inside a list is a value in a place, not a missing member: the place
  // it is in is the second item of the list, and no list has a member missing.
  // So the null merges with the numbers into a `Json` and the list stays a list
  // of them.
  assert_true(emitted_declarations("[[1,null]]").contains("Array[Array[Json]]"))
  assert_true(emitted_declarations("[[1],null]").contains("Array[Json]"))
  // A list that is a member of a record is a different matter: one record having
  // it and the next not is a member that may be missing, and the question mark
  // is what says so.
  assert_true(
    emitted_declarations("[{\"a\":[1]},{\"b\":2}]").contains(
      "a : Array[Int]?\n",
    ),
  )
  assert_true(
    emitted_declarations("[{\"a\":{\"b\":1}}]").contains(
      "pub struct RootItemA {",
    ),
  )
}

///|
test "a number that does not fit in an Int is a Double" {
  assert_true(emitted_declarations("{\"a\":2147483647}").contains("a : Int\n"))
  // One past that, and the number has no Int to be: the type that holds it is
  // the one that holds every number.
  assert_true(
    emitted_declarations("{\"a\":2147483648}").contains("a : Double\n"),
  )
  assert_true(emitted_declarations("{\"a\":-2147483648}").contains("a : Int\n"))
  assert_true(emitted_declarations("{\"a\":1e3}").contains("a : Double\n"))
  // The number that is written as an integer but is one no double can hold
  // exactly is still a Double: there is no type here that holds it better.
  assert_true(
    emitted_declarations("{\"a\":12345678901234567890}").contains(
      "a : Double\n",
    ),
  )
  // A number in one place and a string in another is a Json, since no one type
  // is both. An Int and a Double are a Double.
  assert_true(emitted_declarations("[1,\"a\"]").contains("Array[Json]"))
  assert_true(emitted_declarations("[1,2.5]").contains("Array[Double]"))
  assert_true(emitted_declarations("[1,true]").contains("Array[Json]"))
  // A third kind mixed in does not change the answer, and neither does a shape
  // the sample only shows once: the `Json` stands for all of them.
  assert_true(emitted_declarations("[1,\"a\",true]").contains("Array[Json]"))
  assert_true(emitted_declarations("[1,{\"a\":1}]").contains("Array[Json]"))
}

///|
test "a key that is not a name is mangled, and the field says which key it was" {
  // The characters a key cannot spend on a name become underscores, and the
  // comment beside the field is the only place the key itself can be read — the
  // derive decodes by field name, so the name is what this type will look for.
  assert_eq(
    emitted_declarations("{\"user-name\":\"a\",\"2fa\":true,\"type\":\"t\"}"),
    "pub struct Root {\n" +
    "  user_name : String // \"user-name\"\n" +
    "  _2fa : Bool // \"2fa\"\n" +
    "  type_ : String // \"type\"\n" +
    "} derive(FromJson, ToJson)\n" +
    "\n" +
    "pub extend Root with FromJson::{from_json}\n" +
    "pub extend Root with ToJson::{to_json}\n",
  )
  // A name that the key can already spell is left exactly as it was written, so
  // no comment is needed: the field name and the key are the same text.
  assert_eq(
    emitted_declarations("{\"user_name\":\"a\"}"),
    "pub struct Root {\n" +
    "  user_name : String\n" +
    "} derive(FromJson, ToJson)\n" +
    "\n" +
    "pub extend Root with FromJson::{from_json}\n" +
    "pub extend Root with ToJson::{to_json}\n",
  )
  // An upper case letter is part of the key and is not given up: `Name` and
  // `name` are two keys of one object, and the two fields have to stay apart.
  assert_eq(
    emitted_declarations("{\"Name\":1,\"name\":2}"),
    "pub struct Root {\n" +
    "  _Name : Int // \"Name\"\n" +
    "  name : Int\n" +
    "} derive(FromJson, ToJson)\n" +
    "\n" +
    "pub extend Root with FromJson::{from_json}\n" +
    "pub extend Root with ToJson::{to_json}\n",
  )
}

///|
test "a key that is a word of the language is given a name that is not" {
  // Two kinds of word are renamed: the ones the parser refuses as a field and
  // the ones it takes but warns about. Both would keep a pasted type from
  // building in a module that denies warnings, which is why the list is read off
  // the compiler rather than off a mental list of the language's words — `mut`
  // and `self` are words too, and neither is a problem as a field name.
  assert_eq(
    emitted_declarations("{\"type\":1,\"await\":2,\"mut\":3,\"_\":4}"),
    "pub struct Root {\n" +
    "  type_ : Int // \"type\"\n" +
    "  await_ : Int // \"await\"\n" +
    "  mut : Int\n" +
    "  __ : Int // \"_\"\n" +
    "} derive(FromJson, ToJson)\n" +
    "\n" +
    "pub extend Root with FromJson::{from_json}\n" +
    "pub extend Root with ToJson::{to_json}\n",
  )
}

///|
test "two keys that spell the same name are numbered, and each says which it is" {
  assert_eq(
    emitted_declarations("{\"a-b\":1,\"a.b\":2,\"a b\":3}"),
    "pub struct Root {\n" +
    "  a_b : Int // \"a-b\"\n" +
    "  a_b2 : Int // \"a.b\"\n" +
    "  a_b3 : Int // \"a b\"\n" +
    "} derive(FromJson, ToJson)\n" +
    "\n" +
    "pub extend Root with FromJson::{from_json}\n" +
    "pub extend Root with ToJson::{to_json}\n",
  )
  // A key with nothing in it at all is called `field`; one whose characters can
  // none of them be part of a name is as many underscores as it is characters,
  // which is the same mangling as everywhere else.
  assert_eq(
    emitted_declarations("{\"\":1,\"!!\":2}"),
    "pub struct Root {\n" +
    "  field : Int // \"\"\n" +
    "  __ : Int // \"!!\"\n" +
    "} derive(FromJson, ToJson)\n" +
    "\n" +
    "pub extend Root with FromJson::{from_json}\n" +
    "pub extend Root with ToJson::{to_json}\n",
  )
  // A struct is named after the path to it, and two paths can spell one name:
  // these two members both ask for `RootA_b`.
  assert_true(
    emitted_declarations("{\"a-b\":{\"x\":1},\"a.b\":{\"x\":1}}").contains(
      "pub struct RootA_b2 {",
    ),
  )
  // A key with nothing left of it to spell contributes nothing to the name of
  // the struct under it either, so that name is the shorter one.
  assert_true(
    emitted_declarations("{\"\":{\"x\":1}}").contains("pub struct RootField {"),
  )
  // The path and the key need not be the two of them alike for their names to
  // be: `b` inside `a` and the member `aB` are both `RootAB`.
  assert_true(
    emitted_declarations("{\"a\":{\"b\":{\"x\":1}},\"aB\":{\"x\":1}}").contains(
      "pub struct RootAB2 {",
    ),
  )
}

///|
test "a document that is not an object is a type alias" {
  // Nothing has members to be declared, so the name the command line gave goes
  // on the shape itself, and the objects the shape holds are named after it.
  assert_eq(
    emitted_declarations("[\"a\",\"b\"]"),
    "pub type Root = Array[String]\n",
  )
  assert_true(emitted_declarations("1").contains("pub type Root = Int\n"))
  assert_true(
    emitted_declarations("\"text\"").contains("pub type Root = String\n"),
  )
  assert_true(emitted_declarations("null").contains("pub type Root = Json\n"))
  assert_true(emitted_declarations("true").contains("pub type Root = Bool\n"))
  // The objects under an alias are named for the alias and the place they hold.
  assert_true(
    emitted_declarations("[{\"id\":1}]").contains("pub struct RootItem {"),
  )
  assert_true(
    emitted_declarations("{\"records\":[{\"id\":1}]}").contains(
      "records : Array[RootRecords]",
    ),
  )
}

///|
test "an object with no members is a struct with no fields" {
  assert_eq(
    emitted_declarations("{}"),
    "pub struct Root {\n" +
    "} derive(FromJson, ToJson)\n" +
    "\n" +
    "pub extend Root with FromJson::{from_json}\n" +
    "pub extend Root with ToJson::{to_json}\n",
  )
}

///|
test "the name the command line gave is the name of the root type" {
  let text = emit_moonbit(parse_ok("{\"a\":1}"), "Payload")
  assert_true(text.contains("pub struct Payload {"))
  assert_true(text.contains("pub extend Payload with FromJson::{from_json}"))
  let under_alias = emit_moonbit(parse_ok("[1]"), "Payload")
  assert_true(under_alias.contains("pub type Payload = Array[Int]"))
}

///|
test "the header says where the traits come from" {
  // The one part of the output that does not depend on the document, and the one
  // part a reader needs before pasting it anywhere: the derive lines name traits
  // that are not in the prelude of every package.
  let text = emitted("{\"a\":1}")
  assert_true(
    text.has_prefix("/// A MoonBit type for the shape of a JSON document"),
  )
  assert_true(text.contains("imports \"moonbitlang/core/json\""))
}

///|
test "the same document gives the same text, however it was written out" {
  // The answer is a reading of the shape, so the whitespace the document was
  // laid out with does not reach it: the same document on one line and over
  // several is one type.
  assert_eq(
    emitted("{\"a\":1,\"b\":{\"c\":2}}"),
    emitted("{\n  \"a\": 1,\n  \"b\": { \"c\": 2 }\n}"),
  )
}
