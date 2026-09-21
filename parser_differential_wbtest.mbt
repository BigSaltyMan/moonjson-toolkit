///|
/// White-box tests for the fast path in `parser.mbt`.
///
/// The scanner is allowed to be fast only because deciding anything is the
/// library parser's job: every document the scanner turns away is read a second
/// time by `Nanaloveyuki/parsec/json`, and it is that second reading the tool
/// reports. One rule makes the split safe — the scanner accepts a document
/// exactly when the library parser does, and reads the same value out of it —
/// and these tests are that rule, measured rather than assumed.
///
/// The comparison is made through `@pjson.parse_with_limits`, the same call the
/// fallback in `parse_raw` makes, so the two readers are held to the same limits
/// as well as the same grammar.

///|
/// What the library parser, on its own, makes of `text`.
fn library_reading(
  text : String,
  max_depth : Int,
) -> Result[@pjson.Json, @pjson.JsonError] {
  @pjson.parse_with_limits(text, depth_limits(max_depth))
}

///|
/// A reading as text, so that two of them can be compared in one expression.
fn reading_text(reading : Result[@pjson.Json, @pjson.JsonError]) -> String {
  match reading {
    Ok(json) => "reads " + format(json, 2)
    Err(error) => "turns away at offset " + error.offset().to_string()
  }
}

///|
/// Fail unless the scanner and the library parser make the same thing of `text`.
fn assert_same_reading(text : String, max_depth : Int) -> Unit {
  match (library_reading(text, max_depth), scan(text, max_depth)) {
    (Ok(expected), Some(actual)) => {
      let want = format(expected, 2)
      let got = format(actual, 2)
      if want != got {
        abort(
          "the two readers disagree on " +
          text +
          ": library " +
          want +
          ", scanner " +
          got,
        )
      }
    }
    (Err(_), None) => ()
    (Ok(_), None) =>
      abort("the scanner turned away a document the library reads: " + text)
    (Err(_), Some(actual)) =>
      abort(
        "the scanner read a document the library turns away: " +
        text +
        " as " +
        format(actual, 2),
      )
  }
}

///|
/// Documents the scanner has to read, spanning the grammar: every scalar, every
/// kind of escape, both containers, nesting, and whitespace where it is allowed.
fn differential_corpus() -> Array[String] {
  [
    // Scalars.
    "null", "true", "false",
    // Numbers, in every shape the grammar allows.
     "0", "-0", "5", "-12", "1.5", "-1.5", "1e3", "1E3", "1e+3", "1e-3", "-1.5e-3",
    "0.0", "1.50e+2", "0.0000001", "12345678901234567890",
    // Strings: plain, escaped, and the escapes that stand for characters that
    // cannot be written plainly.
     "\"\"", "\"a\"", "\"abc def\"", "\"\\\"\\\\\\/\"", "\"\\b\\f\\n\\r\\t\"", "\"\\u0000\"",
    "\"\\u0041\"", "\"\\u00e9\"", "\"\\u4e2d\"", "\"\\uD83D\\uDE00\"", "\"中文字符串\"",
    "\"emoji 🎉 inside\"", "\"a\\uD83D\\uDE00b\"",
    // Containers.
     "[]", "[1]", "[1,2,3]", "[[1],[2]]", "[null,true,false]", "{}", "{\"a\":1}",
    "{\"a\":1,\"b\":2}", "{\"a\":{\"b\":[1,2,{}]}}", "[{\"a\":[{\"b\":null}]}]",
    "[{\"a\":1},{\"b\":2}]",
    // Whitespace, where the grammar allows it and nowhere else.
     " 5 ", "\t\r\n[ 1 , 2 ]\r\n", " { \"a\" : [ ] } ", "\r\n",
  ]
}

///|
/// Documents that are not JSON, or are JSON the library refuses. The scanner has
/// to turn every one of them away, so that what they mean is still the library's
/// to say.
fn rejected_corpus() -> Array[String] {
  [
    // Nothing, or nothing but whitespace.
    "", "   ", "\n",
    // Words that are nearly keywords.
     "nul", "nulll", "tru", "TRUE", "None", "undefined", "'a'",
    // One document in a file that holds two, or holds more than one.
     "{} {}", "[1,2] extra",
    // Containers that do not close, or close wrongly.
     "[1,2", "[1 2]", "[,1]", "[1,]", "{,}", "{\"a\"}", "{\"a\":}", "{\"a\" 1}",
    "{\"a\":1,}", "{\"a\":1", "[1}", "{]",
    // Keys that are not strings, and one key twice — the second time in an
    // object large enough that a repeated key is looked for in a map rather than
    // by walking the members, which is a different path through the scanner.
     "{a:1}", "{'a':1}", "{\"a\":1,\"a\":2}", "{\"a\":1,\"b\":2,\"c\":3,\"d\":4,\"e\":5,\"f\":6,\"g\":7,\"h\":8,\"i\":9,\"a\":2}",
    // Numbers that are nearly numbers.
     "+1", ".5", "5.", "01", "-", "1e", "1e+", "1.e3", "0x10", "Infinity", "NaN",
    "1.2.3", "--1", "- 1",
    // Strings that do not close, and escapes that are not escapes.
     "\"abc", "\"a\\\"b", "\"\\x41\"", "\"\\u12\"", "\"\\uZZZZ\"", "\"\\uD83D\"",
    "\"\\uDE00\"", "\"\\uD83Dx\"", "\"\\uD83D\\u0041\"",
    // Control characters, which have to be written as escapes.
     "\"a\nb\"", "\"a\tb\"",
    // A byte order mark is not whitespace here.
     "\u{feff}{\"a\":1}",
  ]
}

///|
/// Every document one edit away from `text`: cut short at each character, or with
/// one character swapped for one that means something to JSON.
///
/// A single edit is what reaches the mistakes a reader makes — a missing comma, a
/// stray bracket, a quote where a digit belongs — and every one of them has to
/// come out the same way from both readers. The two halves of a surrogate pair
/// are left alone: an edit between them would leave the text holding half a
/// character, which is not a document at all, so there is nothing there to read.
fn one_edit_away(text : String) -> Array[String] {
  let substitutes : Array[String] = [
    "{", "}", "[", "]", ",", ":", "\"", "\\", "e", "0", " ", "-", "\n",
  ]
  let units = text.code_units()
  let out : Array[String] = []
  for at in 0..<units.length() {
    let unit = units[at]
    if unit >= 0xDC00 && unit <= 0xDFFF {
      continue
    }
    let head = text.exact_view(start=0, end=at).to_owned()
    out.push(head)
    if unit >= 0xD800 && unit <= 0xDBFF {
      continue
    }
    let tail = text.exact_view(start=at + 1, end=units.length()).to_owned()
    for substitute in substitutes {
      out.push(head + substitute + tail)
    }
  }
  out
}

///|
test "the two readers agree on every document in the corpus" {
  for text in differential_corpus() {
    assert_same_reading(text, standard_max_depth)
  }
}

///|
test "the two readers agree that these documents are not JSON" {
  for text in rejected_corpus() {
    assert_same_reading(text, standard_max_depth)
  }
}

///|
test "the two readers agree one edit away from every document in the corpus" {
  for text in differential_corpus() {
    for edited in one_edit_away(text) {
      assert_same_reading(edited, standard_max_depth)
    }
  }
}

///|
test "the two readers agree one edit away from every rejected document" {
  for text in rejected_corpus() {
    for edited in one_edit_away(text) {
      assert_same_reading(edited, standard_max_depth)
    }
  }
}

///|
/// The tool's own reading, scanner and all, has to be the library's reading: the
/// scanner is an optimisation, and an optimisation that changes an answer is a
/// bug. `reading_text` compares the two outcomes whole, so this covers the
/// acceptance decisions, the values read out of accepted documents, and the
/// offsets of the errors reported for rejected ones.
test "the tool reads a document the way the library does" {
  for text in differential_corpus() {
    assert_eq(
      reading_text(parse(text)),
      reading_text(library_reading(text, standard_max_depth)),
    )
  }
  for text in rejected_corpus() {
    assert_eq(
      reading_text(parse(text)),
      reading_text(library_reading(text, standard_max_depth)),
    )
  }
}

///|
/// A JSON string of exactly `count` characters.
fn string_of_length(count : Int) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  for _ in 0..<count {
    buf.write_char('a')
  }
  buf.write_char('"')
  buf.to_string()
}

///|
/// A JSON array of exactly `count` items.
fn array_of_items(count : Int) -> String {
  let buf = StringBuilder()
  buf.write_char('[')
  for index in 0..<count {
    if index > 0 {
      buf.write_char(',')
    }
    buf.write_char('0')
  }
  buf.write_char(']')
  buf.to_string()
}

///|
/// A JSON object of exactly `count` members, no two keys alike.
fn object_of_members(count : Int) -> String {
  let buf = StringBuilder()
  buf.write_char('{')
  for index in 0..<count {
    if index > 0 {
      buf.write_char(',')
    }
    buf.write_string("\"k")
    buf.write_string(index.to_string())
    buf.write_string("\":0")
  }
  buf.write_char('}')
  buf.to_string()
}

///|
/// The size limits are where the scanner and the library are most likely to
/// drift apart, and every one of them is a boundary: the document at the limit
/// has to be read, and the one character past it has to be turned away — by the
/// library either way, so that the message for it is the library's.
test "the two readers agree at every size limit" {
  // Depth, which is the limit the tool lets a caller move.
  assert_same_reading(brackets(standard_max_depth), standard_max_depth)
  assert_same_reading(brackets(standard_max_depth + 1), standard_max_depth)
  assert_same_reading(brackets(3), 3)
  assert_same_reading(brackets(4), 3)
  assert_same_reading("5", 0)
  assert_same_reading("[]", 0)
  assert_same_reading("[5]", 1)
  assert_same_reading("[[]]", 1)
  // Strings, counted in characters rather than bytes, and an escape counting as
  // the one character it stands for.
  assert_same_reading(
    string_of_length(standard_max_string_chars),
    standard_max_depth,
  )
  assert_same_reading(
    string_of_length(standard_max_string_chars + 1),
    standard_max_depth,
  )
  assert_same_reading("\"\\uD83D\\uDE00\"", standard_max_depth)
  // Arrays and objects.
  assert_same_reading(
    array_of_items(standard_max_array_items),
    standard_max_depth,
  )
  assert_same_reading(
    array_of_items(standard_max_array_items + 1),
    standard_max_depth,
  )
  assert_same_reading(
    object_of_members(standard_max_object_members),
    standard_max_depth,
  )
  assert_same_reading(
    object_of_members(standard_max_object_members + 1),
    standard_max_depth,
  )
  // Agreeing with the library is not enough on its own here: a document the
  // scanner turns away is a document that gets read the slow way, and a limit
  // the scanner undercut would quietly cost the fast path the largest documents
  // there are — the ones it exists for.
  let at_the_limit = [
    array_of_items(standard_max_array_items),
    object_of_members(standard_max_object_members),
    string_of_length(standard_max_string_chars),
  ]
  for text in at_the_limit {
    match scan(text, standard_max_depth) {
      Some(_) => ()
      None => abort("the scanner turned away a document within its limits")
    }
  }
}
