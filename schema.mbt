///|
/// Checking a JSON document against a JSON Schema.
///
/// The dialect read here is the part of the one at json-schema.org that a
/// document of data is described with: `type`, `required`, `properties`,
/// `items`, `enum`, `minimum`, `maximum`, `minLength`, `maxLength` and
/// `pattern`. Every other keyword is left alone rather than refused, so a schema
/// written for a full validator can be handed to this one — the part of it this
/// tool does not read is simply not enforced, and a keyword that is not read
/// cannot be reported as a document that does not match.
///
/// Two questions are asked here, and they are asked separately because they have
/// two different answers. `schema_problems` reads the schema itself: whether
/// every keyword it uses holds a value this tool can do anything with. A schema
/// that fails it is a mistake in what the run was told, not a document that is
/// wrong, and the caller can say so before the document is looked at.
/// `validate_schema` then checks a document against a schema that has been read,
/// and answers with every place the two disagree rather than the first one: a
/// reader fixing a document wants the list, not a walk through the same command
/// ten times.
///
/// Both answer with `SchemaError`, whose `path` is the path of the value that
/// was being looked at. For `validate_schema` that is a path in the document —
/// the paths `--paths` prints, where the root is the empty path and a member is
/// joined to its object with a dot. For `schema_problems` it is a path in the
/// schema, to the keyword or to the value under it that cannot be read.

///|
/// One place where a schema and something else disagree.
///
/// `path` names where the trouble is and `message` says what it is, in a
/// sentence about the value at that path: a report is the two joined with a
/// colon, one error to a line. The message never names the path itself, so the
/// same error reads the same wherever it is found.
pub(all) struct SchemaError {
  path : String
  message : String
}

///|
/// Every place `json` and `schema` disagree.
///
/// The schema is expected to have been through `schema_problems`: a keyword
/// holding something this tool cannot read is passed over here rather than
/// reported, since what is wrong with it is a fact about the schema, which is
/// the other question.
pub fn validate_schema(
  json : @pjson.Json,
  schema : @pjson.Json,
) -> Array[SchemaError] {
  let errors = []
  check_value(json, schema, "", errors)
  errors
}

///|
/// A schema error as one line: where it is and what it is.
///
/// The root has the empty path, which would leave nothing in front of the
/// colon, so it is named instead: a report is read line by line and a line that
/// starts with a colon says nothing about where it is about.
pub fn render_schema_error(error : SchemaError) -> String {
  (if error.path == "" { "(root)" } else { error.path }) + ": " + error.message
}

///|
/// Every keyword in `schema` that this tool cannot read.
///
/// Read before a document is: what is being checked is that the schema is one
/// this tool knows how to apply, and a schema that is not is answered with the
/// place to fix rather than with a document that was never compared to it.
pub fn schema_problems(schema : @pjson.Json) -> Array[SchemaError] {
  let errors = []
  check_schema(schema, "", errors)
  errors
}

///|
/// Check one value against one schema, adding every disagreement to `errors`.
///
/// A keyword says what it is about as much as what it wants: `required` is about
/// an object, `minLength` about a string, `items` about an array. A value of
/// another kind is left alone by it — there is no member that could be missing
/// from a number — and it is `type` that says a number is the wrong kind of value
/// to find here.
fn check_value(
  value : @pjson.Json,
  schema : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  match schema {
    Object(members~) =>
      for entry in members {
        let (keyword, wanted) = entry
        match keyword {
          "type" => check_type(value, wanted, path, errors)
          "required" => check_required(value, wanted, path, errors)
          "properties" => check_properties(value, wanted, path, errors)
          "items" => check_items(value, wanted, path, errors)
          "enum" => check_enum(value, wanted, path, errors)
          "minimum" => check_bound(value, wanted, path, errors, true)
          "maximum" => check_bound(value, wanted, path, errors, false)
          "minLength" => check_length(value, wanted, path, errors, true)
          "maxLength" => check_length(value, wanted, path, errors, false)
          "pattern" => check_pattern(value, wanted, path, errors)
          _ => ()
        }
      }
    // Unreachable: `schema_problems` refuses a schema that is not an object.
    _ => ()
  }
}

///|
/// Whether a value is of the type a name stands for.
fn type_matches(json : @pjson.Json, name : String) -> Bool {
  match name {
    "object" =>
      match json {
        Object(_) => true
        _ => false
      }
    "array" =>
      match json {
        Array(_) => true
        _ => false
      }
    "string" =>
      match json {
        Text(_) => true
        _ => false
      }
    "number" =>
      match json {
        Number(_) => true
        _ => false
      }
    // An integer is a number with nothing after the point rather than a number
    // that is not written as a fraction: `1.0` and `1e3` are both integers, and
    // reading them as doubles to find that out would answer for a numeral too
    // long for a double by rounding it first.
    "integer" =>
      match json {
        Number(raw~) => is_whole_number(raw)
        _ => false
      }
    "boolean" =>
      match json {
        Bool(_) => true
        _ => false
      }
    "null" =>
      match json {
        Null => true
        _ => false
      }
    // Unreachable: `schema_problems` refuses any other name.
    _ => false
  }
}

///|
/// Whether a numeral stands for a whole number: `1`, `1.0` and `1e3` do, `1.5`
/// and `0.25` do not.
///
/// Read off the text the document was written with, so the answer does not
/// depend on what a double can hold: a numeral with thirty digits and nothing
/// after the point is a whole number whatever it is too large to become.
fn is_whole_number(raw : String) -> Bool {
  let chars = raw.to_array()
  let mut index = if chars.length() > 0 && (chars[0] == '-' || chars[0] == '+') {
    1
  } else {
    0
  }
  let mut whole = true
  while index < chars.length() {
    let ch = chars[index]
    if ch == '.' {
      whole = false
    } else if ch == 'e' || ch == 'E' {
      // An exponent moves the point without putting anything after it, so every
      // numeral with one stands for a whole number or for nothing at all.
      return true
    } else if !ch.is_ascii_digit() {
      return false
    } else if !whole && ch != '0' {
      return false
    }
    index = index + 1
  }
  true
}

///|
/// How a JSON type name reads in a sentence, article and all.
fn type_name(name : String) -> String {
  match name {
    "object" => "an object"
    "array" => "an array"
    "string" => "a string"
    "number" => "a number"
    "integer" => "an integer"
    "boolean" => "a boolean"
    "null" => "null"
    // Unreachable: `schema_problems` refuses any other name.
    other => other
  }
}

///|
/// The names a `type` keyword holds, whether it holds one or a list of them.
fn type_names(wanted : @pjson.Json) -> Array[String] {
  match wanted {
    Text(value~) => [value]
    Array(items~) =>
      items.filter_map(fn(item) {
        match item {
          Text(value~) => Some(value)
          // Unreachable: `schema_problems` refuses the rest.
          _ => None
        }
      })
    // A `type` that is neither is one this tool cannot read, and there is
    // nothing to expect of the value: `schema_problems` is where it is answered.
    _ => []
  }
}

///|
/// Join a list of names into a phrase: `a`, `a or b`, `a, b or c`.
fn join_or(names : Array[String]) -> String {
  match names.length() {
    0 => ""
    1 => names[0]
    _ => {
      let head = names[0:names.length() - 1].join(", ")
      head + " or " + names[names.length() - 1]
    }
  }
}

///|
/// `type`: the value has to be of one of the kinds the schema names.
fn check_type(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  let names = type_names(wanted)
  if names.length() == 0 {
    return
  }
  let mut matched = false
  for name in names {
    if type_matches(value, name) {
      matched = true
    }
  }
  if !matched {
    errors.push({
      path,
      message: "it is " +
      kind_name(value) +
      " where the schema expects " +
      join_or(names.map(type_name)),
    })
  }
}

///|
/// `required`: every name has to be a member of the object.
///
/// The names are checked in the order the schema lists them, so a report reads
/// in that order rather than in the order the object happens to be missing them.
fn check_required(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  let names = match wanted {
    Array(items~) =>
      items.filter_map(fn(item) {
        match item {
          Text(value~) => Some(value)
          // Unreachable: `schema_problems` refuses the rest.
          _ => None
        }
      })
    // Unreachable: `schema_problems` refuses a `required` that is not a list.
    _ => []
  }
  match value {
    Object(members~) =>
      for name in names {
        let mut found = false
        for entry in members {
          if entry.0 == name {
            found = true
          }
        }
        if !found {
          errors.push({
            path,
            message: "required member \"" + name + "\" is missing",
          })
        }
      }
    // A `required` says nothing about a value that has no members, and `type`
    // is the keyword that says the value should not be one.
    _ => ()
  }
}

///|
/// `properties`: every member the schema names is checked against the schema it
/// is given, and a member it does not name is left as it is.
///
/// Members the document does not have are not reported here: a schema that
/// requires them says so with `required`, and one that does not means what it
/// says. The walk follows the schema rather than the document, so a report reads
/// in the order the schema lists what it is about, which is the order its reader
/// reads.
fn check_properties(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  let subschemas = match wanted {
    Object(members~) => members
    // Unreachable: `schema_problems` refuses a `properties` that is not an
    // object.
    _ => []
  }
  let members = match value {
    Object(members~) => members
    // A `properties` says nothing about a value that has no members, and `type`
    // is the keyword that says the value should not be one.
    _ => []
  }
  for entry in subschemas {
    match find_member(members, entry.0) {
      Some(held) =>
        check_value(held, entry.1, child_path(path, entry.0), errors)
      None => ()
    }
  }
}

///|
/// `items`: every element of the array is checked against the schema.
fn check_items(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  match value {
    Array(items~) =>
      for index, item in items {
        check_value(item, wanted, path + "[" + index.to_string() + "]", errors)
      }
    _ => ()
  }
}

///|
/// `enum`: the value has to be one of the values listed.
///
/// The message gives the number of them rather than the values: the list is in
/// the schema the reader has to hand, and a schema naming fifty values would
/// otherwise put all fifty on one line of the report.
fn check_enum(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  let allowed = match wanted {
    Array(items~) => items
    // A keyword this tool cannot read is a fact about the schema, which
    // `schema_problems` answers, and not a document that does not match it: a
    // list of no values would have said every document is wrong.
    _ => return
  }
  let mut found = false
  for allowed_value in allowed {
    if same_value(value, allowed_value) {
      found = true
    }
  }
  if !found {
    errors.push({ path, message: "it is not " + listed(allowed.length()), })
  }
}

///|
/// How a number of listed values reads in a sentence: `the value the schema
/// lists`, `one of the 3 values the schema lists`.
///
/// A list with nothing in it lists no values at all, and a value it holds
/// nothing for is a value the schema cannot accept rather than one it does not
/// know.
fn listed(count : Int) -> String {
  match count {
    0 => "one of the values the schema lists"
    1 => "the value the schema lists"
    _ => "one of the " + count.to_string() + " values the schema lists"
  }
}

///|
/// `minimum` and `maximum`: the number has to be inside the bound, which is
/// included in it.
///
/// The bound is compared as the number it denotes, so `5` and `5.0` are one
/// bound, and a numeral past the end of the double range is read as the end it
/// went past — the reading `--sort-by` compares numbers with.
fn check_bound(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
  least : Bool,
) -> Unit {
  let bound = match wanted {
    Number(raw~) => Some(number_value(raw))
    // Unreachable: `schema_problems` refuses a bound that is not a number.
    _ => None
  }
  match (value, bound) {
    (Number(raw~), Some(bound)) => {
      let number = number_value(raw)
      if least && number < bound {
        errors.push({
          path,
          message: "it is less than the minimum " + raw_of(wanted),
        })
      }
      if !least && number > bound {
        errors.push({
          path,
          message: "it is more than the maximum " + raw_of(wanted),
        })
      }
    }
    _ => ()
  }
}

///|
/// `minLength` and `maxLength`: the string has to be long enough, or short
/// enough. The length is counted in characters, as the columns of a diagnostic
/// are.
fn check_length(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
  least : Bool,
) -> Unit {
  let length = match length_argument(wanted) {
    Some(length) => length
    // Unreachable: `schema_problems` refuses a length that is not a count.
    None => return
  }
  match value {
    Text(value~) => {
      let count = count_chars(value)
      if least && count < length {
        errors.push({
          path,
          message: "it is " +
          characters(count) +
          " long, and the schema asks for at least " +
          length.to_string(),
        })
      }
      if !least && count > length {
        errors.push({
          path,
          message: "it is " +
          characters(count) +
          " long, and the schema asks for at most " +
          length.to_string(),
        })
      }
    }
    _ => ()
  }
}

///|
/// How a length reads in a sentence, singular and all: `1 character`, `2
/// characters`.
fn characters(count : Int) -> String {
  if count == 1 {
    "1 character"
  } else {
    count.to_string() + " characters"
  }
}

///|
/// `pattern`: the string has to hold a match of the expression.
///
/// The expression is matched by `pattern.mbt`, whose subset of regular
/// expressions is the one schemas are written with; a pattern it cannot read has
/// already been reported by `schema_problems`, and a document is not the place
/// to say so again.
fn check_pattern(
  value : @pjson.Json,
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  let pattern = match text_of(wanted) {
    Some(pattern) => pattern
    // Unreachable: `schema_problems` refuses a `pattern` that is not a string.
    None => return
  }
  match text_of(value) {
    Some(text) =>
      match pattern_matches(pattern, text) {
        Ok(true) => ()
        Ok(false) =>
          errors.push({
            path,
            message: "it does not match the pattern \"" + pattern + "\"",
          })
        Err(_) => ()
      }
    _ => ()
  }
}

///|
/// Every keyword in the schema that this tool cannot read, with the path of the
/// keyword it is under.
///
/// A schema is read the same way at every level, so this walks into the schemas
/// inside it: `properties` for the members it names and `items` for the elements
/// of an array. A keyword that is not one of the ten this tool reads is passed
/// over without being looked at, whatever it holds.
fn check_schema(
  schema : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  match schema {
    Object(members~) =>
      for entry in members {
        let (keyword, wanted) = entry
        let here = child_path(path, keyword)
        match keyword {
          "type" => check_type_argument(wanted, here, errors)
          "required" => check_name_list(wanted, here, errors)
          "properties" =>
            match wanted {
              Object(members=subschemas) =>
                for entry in subschemas {
                  check_schema(entry.1, child_path(here, entry.0), errors)
                }
              _ =>
                errors.push({
                  path: here,
                  message: "expected an object naming the members it is about, but this is " +
                  kind_name(wanted),
                })
            }
          "items" =>
            match wanted {
              Object(_) => check_schema(wanted, here, errors)
              _ =>
                errors.push({
                  path: here,
                  message: "expected one schema for the items, but this is " +
                  kind_name(wanted) +
                  "; a list of schemas is not read here",
                })
            }
          "enum" =>
            match wanted {
              Array(_) => ()
              _ =>
                errors.push({
                  path: here,
                  message: "expected a list of values, but this is " +
                  kind_name(wanted),
                })
            }
          "minimum" | "maximum" =>
            match wanted {
              Number(_) => ()
              _ =>
                errors.push({
                  path: here,
                  message: "expected a number, but this is " + kind_name(wanted),
                })
            }
          "minLength" | "maxLength" =>
            match length_argument(wanted) {
              Some(_) => ()
              None =>
                errors.push({
                  path: here,
                  message: match wanted {
                    // A number that is not a count is a number with a point in
                    // it, a negative one, or one no document could hold: saying
                    // which number it is leaves the reading of the message to
                    // the schema's author.
                    Number(raw~) =>
                      raw +
                      " is not a count of characters; a count is a whole number from 0 to 1000000000"
                    _ =>
                      "expected a count of characters, but this is " +
                      kind_name(wanted)
                  },
                })
            }
          "pattern" => check_pattern_argument(wanted, here, errors)
          // Every other keyword is a part of the dialect this tool does not
          // read, and a schema is not refused for holding one: it says nothing
          // about the document here, and nothing about it is wrong.
          _ => ()
        }
      }
    _ =>
      errors.push({
        path,
        message: "a schema is an object of keywords, but this is " +
        kind_name(schema),
      })
  }
}

///|
/// Whether a `type` keyword holds the name of a type or a list of them.
fn check_type_argument(
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  match wanted {
    Text(value~) => check_type_name(value, path, errors)
    Array(items~) =>
      for index, item in items {
        match item {
          Text(value~) =>
            check_type_name(value, path + "[" + index.to_string() + "]", errors)
          _ =>
            errors.push({
              path: path + "[" + index.to_string() + "]",
              message: "expected a JSON type name, but this is " +
              kind_name(item),
            })
        }
      }
    _ =>
      errors.push({
        path,
        message: "expected a JSON type name or a list of them, but this is " +
        kind_name(wanted),
      })
  }
}

///|
/// Whether a name is one of the seven JSON types.
fn check_type_name(
  name : String,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  match name {
    "object" | "array" | "string" | "number" | "integer" | "boolean" | "null" =>
      ()
    _ =>
      errors.push({
        path,
        message: "\"" +
        name +
        "\" is not a JSON type; the types are object, array, string, number, integer, boolean and null",
      })
  }
}

///|
/// Whether a `required` keyword holds a list of member names.
fn check_name_list(
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  match wanted {
    Array(items~) =>
      for index, item in items {
        match item {
          Text(_) => ()
          _ =>
            errors.push({
              path: path + "[" + index.to_string() + "]",
              message: "expected a member name, but this is " + kind_name(item),
            })
        }
      }
    _ =>
      errors.push({
        path,
        message: "expected a list of member names, but this is " +
        kind_name(wanted),
      })
  }
}

///|
/// The value of a `minLength` or `maxLength` keyword, if it is a count of
/// characters.
///
/// A length is a whole number of characters, so `3`, `3.0` and `1e3` are the
/// counts three, three and a thousand: what is not a count is a number with a
/// fraction in it, which would be a fraction of a character, and a negative one,
/// which no string is shorter than. A count past a billion is not read either —
/// no document this tool is handed holds that many characters of one string, and
/// reading it would mean answering with a number that is not there.
fn length_argument(wanted : @pjson.Json) -> Int? {
  match wanted {
    Number(raw~) =>
      if !is_whole_number(raw) {
        None
      } else {
        let count = number_value(raw)
        if count < 0.0 || count > 1_000_000_000.0 {
          None
        } else {
          Some(count.to_int())
        }
      }
    _ => None
  }
}

///|
/// Whether a `pattern` keyword holds an expression this tool can read,
/// answering with the reason it cannot if it does not.
fn check_pattern_argument(
  wanted : @pjson.Json,
  path : String,
  errors : Array[SchemaError],
) -> Unit {
  match text_of(wanted) {
    Some(pattern) =>
      match pattern_matches(pattern, "") {
        Ok(_) => ()
        Err(reason) =>
          errors.push({
            path,
            message: "\"" +
            pattern +
            "\" is not a pattern this tool reads: " +
            reason,
          })
      }
    _ =>
      errors.push({
        path,
        message: "expected a pattern, but this is " + kind_name(wanted),
      })
  }
}

///|
/// Whether two values are the same value, as `enum` means it.
///
/// Numbers are compared as the numbers they denote rather than as the text they
/// were written with, so `1` is the same value as `1.0` — the reading the sort
/// order compares them with. Two objects are the same when they hold the same
/// members, whatever order they were written in, and two arrays when they hold
/// the same values in the same order. Values of different kinds are never the
/// same one.
fn same_value(one : @pjson.Json, other : @pjson.Json) -> Bool {
  match (one, other) {
    (Null, Null) => true
    (Bool(value=first), Bool(value=second)) => first == second
    (Number(raw=first), Number(raw=second)) =>
      number_value(first) == number_value(second)
    (Text(value=first), Text(value=second)) => first == second
    (Array(items=first), Array(items=second)) => {
      let mut equal = first.length() == second.length()
      if equal {
        for index, item in first {
          if !same_value(item, second[index]) {
            equal = false
          }
        }
      }
      equal
    }
    (Object(members=first), Object(members=second)) => {
      let mut equal = first.length() == second.length()
      if equal {
        for entry in first {
          match find_member(second, entry.0) {
            Some(value) => if !same_value(entry.1, value) { equal = false }
            None => equal = false
          }
        }
      }
      equal
    }
    _ => false
  }
}

///|
/// The text of a value, if it is a string.
fn text_of(json : @pjson.Json) -> String? {
  match json {
    Text(value~) => Some(value)
    _ => None
  }
}

///|
/// The value of one member, if the object has it.
fn find_member(
  members : Array[(String, @pjson.Json)],
  key : String,
) -> @pjson.Json? {
  for entry in members {
    if entry.0 == key {
      return Some(entry.1)
    }
  }
  None
}

///|
/// The path of a member of the value at `path`.
///
/// The root of a document has the empty path, which is the path `--paths` gives
/// it: a member of the root is named by its key alone, and everything below it
/// is joined with dots.
fn child_path(path : String, key : String) -> String {
  if path == "" {
    key
  } else {
    path + "." + key
  }
}

///|
/// The text a number was written with.
fn raw_of(wanted : @pjson.Json) -> String {
  match wanted {
    Number(raw~) => raw
    // Unreachable: every caller has already read the number out of it.
    _ => ""
  }
}
