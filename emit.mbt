///|
/// A MoonBit type for the shape a JSON document shows.
///
/// The output is meant to be pasted into a module and used, not read: it names
/// every object the document holds, derives `FromJson` and `ToJson` for each of
/// them, and comes out in the layout `moon fmt` would leave it in. What it
/// cannot do is make the sample say more than it says — a field the sample holds
/// as null could hold anything, and a field the sample never mentions is a field
/// the type cannot mention either — so the places that cannot be pinned down are
/// written as `Json`, which accepts whatever turns up there.
///
/// Nothing here reads a value as a value: the same shape written twice produces
/// the same type twice, and where the document was written over several lines or
/// on one makes no difference to the answer. The order of an object's members is
/// the one thing carried over from the document, because that order is part of
/// what the document says.

///|
/// The shape a sample shows, as the type that would hold it.
///
/// The two empty forms are told apart because they merge differently: an empty
/// array is no evidence at all, while a null is evidence that the place can be
/// empty, so a later sample of a real value turns the second into `T?` and
/// leaves the first as `T`.
priv enum EmitType {
  Nothing // an empty array: the sample says nothing about what belongs here
  NullOnly // the sample holds null, and nothing but null, here
  Named(String) // Int, Double, String, Bool, or Json when nothing can be told
  ArrayOf(EmitType)
  Optional(EmitType)
  Object(Array[EmitField]) // a struct, once it has been given a name
}

///|
/// One member of an object: the key the document wrote, the field name the
/// generated struct will spell it with, and the shape the value showed.
priv struct EmitField {
  name : String
  key : String
  kind : EmitType
}

///|
/// The names a run has already given out, so that the next struct asked for
/// under the same name is given a different one.
///
/// Two structs cannot be declared under one name, and two of them can want the
/// same one: the members `"a-b"` and `"a.b"` are both spelled `A_b`, and the
/// `b` inside `"a"` and the member `"aB"` are both spelled `AB`. The later ask
/// is answered with the first numbered form that is free.
priv struct NameBook {
  taken : Array[String]
}

///|
fn NameBook::new() -> NameBook {
  { taken: [], }
}

///|
/// The next free name of the form `candidate`, `candidate2`, `candidate3`...
fn NameBook::claim(self : NameBook, candidate : String) -> String {
  free_name(self.taken, candidate)
}

///|
/// `candidate` if no name in `taken` is that one, and otherwise its first free
/// numbered form.
///
/// Shared by the struct names and the field names, since the two have the same
/// problem: a name is derived from the document rather than chosen by the run,
/// so two derivations can arrive at the same spelling and nothing else can tell
/// them apart.
fn free_name(taken : Array[String], candidate : String) -> String {
  if !taken.contains(candidate) {
    taken.push(candidate)
    return candidate
  }
  let mut number = 2
  while taken.contains(candidate + number.to_string()) {
    number = number + 1
  }
  let name = candidate + number.to_string()
  taken.push(name)
  name
}

///|
/// The names a struct field cannot be given.
///
/// Read off the compiler rather than taken from a list of the language's words:
/// every name here was written as a field name and came back with something to
/// say about it, and the words that were taken without a word — `mut`, `by`,
/// `self`, `init` — are not in it. Most of these the parser refuses outright;
/// the rest are the ones it reads as a name and warns about, `await` and
/// `package` among them, which comes to the same thing here. A generated type is
/// pasted into a module this tool has never seen, and a module that denies
/// warnings would not build around a warning that was handed to it.
let reserved_words : Array[String] = [
  "_", "abstract", "alias", "and", "as", "assert", "assume", "async", "await", "break",
  "catch", "comptime", "const", "continue", "defer", "do", "dyn", "else", "enum",
  "extern", "false", "final", "finally", "fn", "for", "guard", "if", "impl", "import",
  "in", "is", "let", "loop", "macro", "match", "method", "module", "move", "noraise",
  "opaque", "override", "package", "priv", "pub", "raise", "readonly", "ref", "resume",
  "return", "sealed", "static", "struct", "super", "test", "trait", "true", "try",
  "type", "typeof", "unsafe", "use", "using", "var", "virtual", "void", "where",
  "while", "with", "yield",
]

///|
/// The type names the generated code is itself written with.
///
/// Every one of them can turn up in what it produces, as a field type, inside an
/// `Array[...]` or after the `?` of an optional, so a root type named after one
/// of them would be a type made of itself.
let builtin_type_names : Array[String] = [
  "Int", "Double", "String", "Bool", "Json", "Array",
]

///|
/// A key with every character that cannot be part of a name written as `_`.
///
/// Written over the characters rather than over the names the language happens
/// to allow, so that a key has exactly one spelling and a reader can work it out
/// from the key alone: `"a b"`, `"a-b"` and `"a.b"` all come out as `a_b`, and
/// the field says which of the three it was, since none of them is that.
fn spellable(key : String) -> String {
  let text = StringBuilder()
  for ch in key {
    if ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '_' {
      text.write_char(ch)
    } else {
      text.write_char('_')
    }
  }
  text.to_string()
}

///|
/// The field name for a JSON key.
///
/// A key is not a name the language has to accept, so this is where the two are
/// reconciled. A name that would not start with a lower case letter or an
/// underscore is given a leading `_` rather than having its case changed: the
/// case is part of the key, and a mangling that lowercased it would leave
/// `"Name"` and `"name"` as one field. A name the compiler refuses as a field
/// gets a `_` on the end, and one that has nothing left of it to spell is called
/// `field`.
///
/// Every one of these is a name the key did not have, which is why a field says
/// which key it stands for whenever the two differ.
fn field_name(key : String) -> String {
  let spelled = spellable(key)
  let leading = if spelled == "" {
    "field"
  } else {
    let first = spelled.to_array()[0]
    if first.is_ascii_lowercase() || first == '_' {
      spelled
    } else {
      "_" + spelled
    }
  }
  if reserved_words.contains(leading) {
    leading + "_"
  } else {
    leading
  }
}

///|
/// The part a key contributes to the name of a struct found under it.
///
/// This one is added to the end of the name of the struct that holds it, so it
/// is the first letter that is capitalised and the rest is left as it was: the
/// field `records` inside `Root` declares `RootRecords`. A long name is the path
/// to the type written as one word, and it is the one name that cannot be
/// mistaken for a sibling's.
fn type_part(key : String) -> String {
  let spelled = spellable(key)
  if spelled == "" {
    return "Field"
  }
  let chars = spelled.to_array()
  chars[0] = chars[0].to_ascii_uppercase()
  String::from_array(chars)
}

///|
/// The type a number's text stands for.
///
/// A numeral that fits in an `Int` is one, and anything else is a `Double`. The
/// reading is the parser's rather than a count of digits, so the boundary is
/// exactly where the language's own boundary is. `Int64` is not among the
/// answers: this version of the JSON library reads an `Int64` from a number
/// written as a string, so a field of that type would not decode the document it
/// came from.
fn number_type(raw : String) -> String {
  let fits = try @string.parse_int(raw) catch {
    _ => false
  } noraise {
    _ => true
  }
  if fits {
    "Int"
  } else {
    "Double"
  }
}

///|
/// The shape one value shows.
fn infer(json : @pjson.Json) -> EmitType {
  match json {
    Null => NullOnly
    Bool(_) => Named("Bool")
    Number(raw~) => Named(number_type(raw))
    Text(_) => Named("String")
    Array(items~) => {
      let mut element : EmitType = Nothing
      for item in items {
        element = merge(element, infer(item))
      }
      ArrayOf(element)
    }
    Object(members~) => {
      let fields : Array[EmitField] = []
      // Two members of one object cannot share a key, and the spelling is a
      // function of the key alone, so two fields here can still want one name:
      // `"a-b"` and `"a.b"` are both `a_b`. The later one is numbered, and the
      // comment beside it says which key it holds.
      let taken : Array[String] = []
      for entry in members {
        let (key, value) = entry
        fields.push({
          name: free_name(taken, field_name(key)),
          key,
          kind: infer(value),
        })
      }
      Object(fields)
    }
  }
}

///|
/// A shape whose place the sample did not always have a value in.
///
/// Everything is made optional, `Json` included. A `Json` is a value of any
/// shape at all, but the key still has to be there — the derived decoder reports
/// `Missing field` for a member that is not in the document — so a member the
/// sample holds in one record and not in the next is a `Json?` and not a `Json`.
/// The two are not two ways of saying one thing: the question mark is the whole
/// of what the second sample said.
fn nullable(kind : EmitType) -> EmitType {
  match kind {
    Optional(_) => kind
    _ => Optional(kind)
  }
}

///|
/// The shape two samples of one place show between them.
///
/// This is what makes a list of records into one record type rather than into
/// the first record's: the members the samples share are merged field by field,
/// and a member only some of them have is a member that may be missing, which is
/// what `T?` is. A number written `1` in one place and `1.5` in another is a
/// `Double`, and a place holding a number in one sample and a string in another
/// is a `Json` — the samples cannot say which of the two the field is, and a
/// wrong field type is worse than an unhelpful one.
///
/// A null merges with a value into a `Json`, and not into a `T?`. An optional
/// field is read by decoding whatever is there as the type inside it, so a null
/// where an `Int?` was expected is reported as a number that is not a number
/// rather than as nothing at all; what holds both a value and a null is a `Json`
/// and nothing narrower. A place that is null in one sample and a value in
/// another is a place whose type the samples do not agree on, which is the same
/// thing a number in one and a string in another means.
fn merge(first : EmitType, second : EmitType) -> EmitType {
  match (first, second) {
    // An empty array shows nothing, so it has nothing to contribute.
    (Nothing, other) | (other, Nothing) => other
    (NullOnly, NullOnly) => NullOnly
    (NullOnly, _) | (_, NullOnly) => Named("Json")
    (Named(one), Named(another)) => Named(merge_names(one, another))
    (ArrayOf(one), ArrayOf(another)) => ArrayOf(merge(one, another))
    // Unreachable: only a member an earlier record left out is optional, and
    // what is merged into it is a shape read off a record that has the member,
    // so two of these never meet. Written out rather than left to the `Json`
    // below, which would throw the option away if they ever did.
    (Optional(one), Optional(another)) => Optional(merge(one, another))
    (Optional(one), other) | (other, Optional(one)) =>
      nullable(merge(one, other))
    (Object(one), Object(another)) => Object(merge_fields(one, another))
    _ => Named("Json")
  }
}

///|
/// The type two named types agree on.
///
/// Two names that are one name are that name; `Int` and `Double` are a `Double`,
/// since every integer is one; and anything else is a `Json`, since a number and
/// a string have no type in common that would not also be a number's or a
/// string's.
fn merge_names(first : String, second : String) -> String {
  if first == second {
    first
  } else if first == "Json" || second == "Json" {
    "Json"
  } else if (first == "Int" && second == "Double") ||
    (first == "Double" && second == "Int") {
    "Double"
  } else {
    "Json"
  }
}

///|
/// The members two objects show between them.
///
/// The order is the order the keys were first seen in, so the type reads in the
/// order the document does. A key only one of the objects has is a key the other
/// does not, and an object that does not have the key is an object whose member
/// is missing — the same thing as null as far as the type is concerned — so
/// those members are merged with a null rather than dropped.
fn merge_fields(
  first : Array[EmitField],
  second : Array[EmitField],
) -> Array[EmitField] {
  let merged : Array[EmitField] = []
  for field in first {
    let mut kind = field.kind
    let mut both = false
    for other in second {
      if other.key == field.key {
        kind = merge(kind, other.kind)
        both = true
      }
    }
    merged.push({
      name: field.name,
      key: field.key,
      kind: if both {
        kind
      } else {
        nullable(kind)
      },
    })
  }
  for other in second {
    let mut both = false
    for field in first {
      if field.key == other.key {
        both = true
      }
    }
    if !both {
      merged.push({
        name: other.name,
        key: other.key,
        kind: nullable(other.kind),
      })
    }
  }
  merged
}

///|
/// The shape a value shows, written as the type that holds it, declaring the
/// structs that type needs along the way.
///
/// `parent` is the name of the struct the value sits in and `key` the member it
/// is found under; between them they name the struct an object becomes, so the
/// pair travels down through the arrays and the optionals that wrap it.
fn render(
  kind : EmitType,
  parent : String,
  key : String,
  names : NameBook,
  declared : Array[String],
) -> String {
  match kind {
    Nothing | NullOnly => "Json"
    Named(name) => name
    ArrayOf(inner) =>
      "Array[" + render(inner, parent, key, names, declared) + "]"
    Optional(inner) => render(inner, parent, key, names, declared) + "?"
    Object(fields) => {
      // Named after the path that reached it: the name of the struct it sits in,
      // and the key it was found under. A root object never arrives here — the
      // name the command line gave is already on it — so every object this sees
      // is a member of something, and `""` is a member key like any other, which
      // contributes the shortest part a key can.
      let name = names.claim(parent + type_part(key))
      add_struct(name, fields, names, declared)
      name
    }
  }
}

///|
/// The declaration of one struct, followed by the declarations of the structs
/// its own members need.
///
/// The struct comes first because that is the one the name the command line gave
/// belongs to, and the ones under it are read afterwards as what it is made of.
fn add_struct(
  name : String,
  fields : Array[EmitField],
  names : NameBook,
  declared : Array[String],
) -> Unit {
  let later : Array[String] = []
  declared.push(struct_text(name, fields, names, later))
  for child in later {
    declared.push(child)
  }
}

///|
/// The declaration of one struct, with the declarations of the structs its
/// members need appended to `later`.
///
/// The fields are written in the order the document holds them, and a field
/// whose name is not the key it came from says so on the line it is written on:
/// the reader pasting this in has to be able to see which key each field is
/// looking for, and a comment is the only place the answer can go, since the
/// derive reads the field name and nothing else.
fn struct_text(
  name : String,
  fields : Array[EmitField],
  names : NameBook,
  later : Array[String],
) -> String {
  let text = StringBuilder()
  text.write_string("pub struct " + name + " {")
  for field in fields {
    text.write_string("\n  " + field.name + " : ")
    text.write_string(render(field.kind, name, field.key, names, later))
    if field.name != field.key {
      text.write_string(" // " + format_compact(@pjson.Text(value=field.key)))
    }
  }
  text.write_string("\n} derive(FromJson, ToJson)\n")
  // What the compiler would otherwise warn about: without these the derived
  // methods are promoted to methods of the type implicitly, which the compiler
  // reports as deprecated, and a module that denies warnings would not build.
  text.write_string("\npub extend " + name + " with FromJson::{from_json}\n")
  text.write_string("pub extend " + name + " with ToJson::{to_json}")
  text.to_string()
}

///|
/// The note at the top of the generated file.
///
/// It is the only part of the output that is the same every time, which is what
/// makes it worth writing once here: what the type can and cannot say is said by
/// the type itself.
fn emit_header() -> String {
  [
    "/// A MoonBit type for the shape of a JSON document, generated by", "/// moonjson-toolkit --emit-moonbit.",
    "///", "/// Paste it into a package that imports \"moonbitlang/core/json\": that is",
    "/// where FromJson and ToJson come from. The `extend` lines under each struct",
    "/// keep the derived methods from being promoted implicitly, which the", "/// compiler reports as deprecated.",
    "///", "/// A field is named after the JSON key it holds. A key that is not a name",
    "/// moonbit can spell appears mangled, with the key written beside it.",
  ].join("\n") +
  "\n"
}

///|
/// The name a generated root type is given when the command line names none.
pub let default_root_name : String = "Root"

///|
/// The reason a name cannot be the one a type is declared under, or `None` when
/// it can.
///
/// The rules are read off the compiler rather than taken from a grammar: a type
/// name starts with an upper case ASCII letter — `payload`, `_Root` and a name
/// in another script are all reported as lower case identifiers — and goes on
/// with letters, digits and underscores, since anything else is a parse error.
///
/// The names the generated code is itself written with are refused as well. A
/// struct named `Int` compiles, and every `Int` written inside it then means the
/// new struct rather than the builtin, so `--emit-moonbit Int` on `{"a":1}`
/// would answer with a type that says something other than what it looks like it
/// says.
pub fn type_name_problem(name : String) -> String? {
  let chars = name.to_array()
  if chars.length() == 0 {
    return Some("it is empty")
  }
  if !chars[0].is_ascii_uppercase() {
    return Some(
      "\"" +
      name +
      "\" starts with a lower case letter (a type name starts with an upper case one)",
    )
  }
  for ch in chars {
    if !(ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '_') {
      return Some(
        "\"" +
        name +
        "\" holds a character that is not a letter, a digit or an underscore",
      )
    }
  }
  if builtin_type_names.contains(name) {
    Some(
      "\"" +
      name +
      "\" is one of the types the generated code is written with (" +
      builtin_type_names.join(", ") +
      ")",
    )
  } else {
    None
  }
}

///|
/// The document as a MoonBit type, under the name the command line gave.
///
/// A document that is an object is that type. Anything else has no members to
/// declare, so the name goes on a `type` alias for the shape the document shows:
/// `--emit-moonbit` on a list of records gives `type Root = Array[RootItem]`,
/// with the records declared under the name the alias uses for them.
pub fn emit_moonbit(json : @pjson.Json, root_name : String) -> String {
  let root = infer(json)
  let names = NameBook::new()
  let declared : Array[String] = []
  match root {
    Object(fields) =>
      add_struct(names.claim(root_name), fields, names, declared)
    other => {
      // The alias is written before the structs it is made of, for the same
      // reason the root struct is: it is the name the run was asked for, and the
      // rest of the answer is what it is made of.
      let later : Array[String] = []
      let shape = render(other, root_name, "Item", names, later)
      declared.push("pub type " + root_name + " = " + shape)
      for child in later {
        declared.push(child)
      }
    }
  }
  let text = StringBuilder()
  text.write_string(emit_header())
  for block in declared {
    text.write_string("\n")
    text.write_string(block)
    text.write_string("\n")
  }
  text.to_string()
}
