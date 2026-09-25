///|
/// The three ways one document is turned into another.
///
/// These differ from everything else the tool does to a document in that they
/// change what it says rather than how it looks: `--sort-keys` reorders the
/// members of an object and `--indent` decides where the line breaks go, while
/// selecting, sorting and deduplicating decide which values are left at all.
/// They are also the only three that can be asked for something the document
/// cannot give — a sort of a document that is not a list, a selection from one
/// that is not an object — and each answers `Err` with a sentence saying so
/// rather than returning something the caller did not ask for.
///
/// As with the other rewrites, the tree handed in is left as it was found:
/// every container these build is a new one, and nothing already in the
/// document is edited in place.

///|
/// The name of what a value is, for the sentence that says a rewrite cannot be
/// done to it.
///
/// The articles are part of it so that the sentences read as English: a reader
/// told `this document is an array` knows what to do, and one told `is array`
/// is reading a message that was assembled rather than written.
fn kind_name(json : @pjson.Json) -> String {
  match json {
    Null => "null"
    Bool(_) => "a boolean"
    Number(_) => "a number"
    Text(_) => "a string"
    Array(_) => "an array"
    Object(_) => "an object"
  }
}

///|
/// Pick the named members out of the top-level object.
///
/// The result holds the fields in the order they were named rather than the
/// order the document wrote them in, because the list is the thing the caller
/// wrote: `--select b,a` on `{"a":1,"b":2}` asks for `b` first, and a document
/// that came back as `{"a":1,"b":2}` would be one where the request was read and
/// then ignored. A name given twice is taken once, since an object cannot have
/// the same member twice and printing one would produce a document this tool
/// refuses to read.
///
/// A name the object does not have is skipped rather than reported. Fields come
/// and go between documents of the same shape, and a run over a folder of them
/// expects the same selection to work on all of them — refusing the ones that
/// have moved on would make the option useless for exactly the job it is for.
pub fn select(
  json : @pjson.Json,
  fields : Array[String],
) -> Result[@pjson.Json, String] {
  match json {
    Object(members~) => {
      let out : Array[(String, @pjson.Json)] = []
      for field in fields {
        let mut already = false
        for entry in out {
          if entry.0 == field {
            already = true
          }
        }
        if !already {
          for entry in members {
            let (key, value) = entry
            if key == field {
              out.push((key, value))
            }
          }
        }
      }
      Ok(Object(members=out))
    }
    _ =>
      Err(
        "--select picks fields out of the top-level object, and this document is " +
        kind_name(json),
      )
  }
}

///|
/// Follow a dotted path from `json` to the value it names.
///
/// Only object members are walked. An array is a sequence rather than a table of
/// names — its positions are not names it has, and `items.0` reads as a member
/// called `0` rather than as the first item — so a path that reaches an array
/// and asks to go further finds nothing, which is the same answer as a path that
/// names a member the document does not have.
///
/// An empty path is the value itself. It is the one path that cannot be a
/// mistake — every document has itself — and it is what makes `--unique=` the
/// whole-element form of `--unique <field>`.
pub fn lookup_path(json : @pjson.Json, path : String) -> @pjson.Json? {
  if path == "" {
    return Some(json)
  }
  let mut current = json
  for segment in path.split(".") {
    let name = segment.to_owned()
    match current {
      Object(members~) => {
        let mut found : @pjson.Json? = None
        for entry in members {
          let (key, value) = entry
          if key == name {
            found = Some(value)
          }
        }
        match found {
          Some(value) => current = value
          None => return None
        }
      }
      _ => return None
    }
  }
  Some(current)
}

///|
/// Read a JSON number's text as a value to compare.
///
/// The parser keeps a number as the text it was written with, so that printing
/// a document gives back the digits it was given, which means the comparison
/// has to read that text here.
///
/// `Double` is what the reading is done in, as it is in `jq` and in most other
/// tools that sort JSON. The cost is that two numbers closer together than a
/// double can tell apart — beyond seventeen significant digits — compare equal
/// and keep the order they came in, which is a sort that leaves them where they
/// were rather than one that puts them in the wrong order.
///
/// A literal past the end of the range is read as the end it went past: `1e400`
/// is more than every number a double can hold, `-1e400` is less than all of
/// them. Those are legal JSON numbers that no double denotes, and the reading
/// has to place them somewhere — leaving them equal to everything would put
/// `1e400` equal to both `5` and `10` while `5` is less than `10`, and a
/// comparison that says that has no order in it for a sort to find.
fn number_value(raw : String) -> Double {
  @string.parse_double(raw) catch {
    _ =>
      if raw.has_prefix("-") {
        @double.neg_infinity
      } else {
        @double.infinity
      }
  }
}

///|
/// Where a value belongs in the order of kinds, which is how two values of
/// different kinds are compared.
///
/// The order is the one `jq` sorts by: null, false, true, numbers, strings,
/// arrays, objects. It is not a claim that a number is less than a string but a
/// decision that every two values have an order between them, which is what
/// makes the sort answer the same way whatever order it looks at the items in.
/// The rule this replaces — values of different kinds are equal — is not a
/// smaller claim but an inconsistent one: it says `false` equals `0`, `0` equals
/// `"a"` and `false` is not equal to `"a"`, and a comparison like that has no
/// order to find, so the answer depends on which pairs the sorting algorithm
/// happened to look at.
///
/// Within one kind the order is the obvious one: `false` before `true`, numbers
/// by the numbers they denote, strings by code point. Two arrays, and two
/// objects, are equal — their contents are not compared, so they keep the order
/// the document gave them.
fn kind_rank(json : @pjson.Json) -> Int {
  match json {
    Null => 0
    Bool(value=false) => 1
    Bool(value=true) => 2
    Number(_) => 3
    Text(_) => 4
    Array(_) => 5
    Object(_) => 6
  }
}

///|
/// Compare two strings by code point.
///
/// This is the comparison the tool documents for keys and the one `jq` uses,
/// and it is not `String::compare`: that one orders by length first, so `"pear"`
/// comes before `"apple"` and `"b"` before `"ab"`. A shorter string that is the
/// start of a longer one therefore sorts first here without the length being
/// consulted at all, which is what the order of a dictionary looks like.
///
/// Both places that order strings use this one: `--sort-by` and `--unique`
/// through `compare_keys` below, and `--sort-keys` through `sort_keys` in
/// `formatter.mbt`, so the order a key is printed in and the order a value is
/// sorted in are the same order.
fn compare_text(first : String, second : String) -> Int {
  let left = first.to_array()
  let right = second.to_array()
  let shared = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for index in 0..<shared {
    let order = left[index].compare(right[index])
    if order != 0 {
      return order
    }
  }
  return left.length().compare(right.length())
}

///|
/// Compare two values as sort keys.
///
/// Values of different kinds are ordered by kind, so the comparison is a total
/// order and the sort it drives is one whose answer does not depend on the
/// algorithm underneath. Numbers compare as numbers and strings as strings.
fn compare_keys(first : @pjson.Json, second : @pjson.Json) -> Int {
  let order = kind_rank(first).compare(kind_rank(second))
  if order != 0 {
    return order
  }
  match (first, second) {
    (Number(raw=first_raw), Number(raw=second_raw)) =>
      number_value(first_raw).compare(number_value(second_raw))
    (Text(value=first_text), Text(value=second_text)) =>
      compare_text(first_text, second_text)
    _ => 0
  }
}

///|
/// The value an item is sorted by, which is the one its path names.
///
/// An item the path does not reach is sorted as if the field held null, which
/// puts it with the nulls at the front of the order. The alternative — such an
/// item has no key, so leave it where it is — cannot be kept to once there is
/// more than one of them: an item with no key is not equal to the items that
/// have one, and the document would come back in an order that depends on where
/// the sort happened to look. A missing field is also the ordinary way of
/// saying that a record has no value for something, which is what null is.
fn sort_key(item : @pjson.Json, path : String) -> @pjson.Json {
  match lookup_path(item, path) {
    Some(value) => value
    None => Null
  }
}

///|
/// Sort the items of an array by the value a path names inside each of them.
///
/// The sort is stable: two items whose keys compare equal keep the order the
/// document gave them, which is what makes sorting by one field of records that
/// may be equal in it worth doing. Stability is arranged rather than assumed —
/// the items are sorted with their original positions as the tie-breaker, so
/// the answer does not depend on which sort the standard library happens to
/// use — and each item is carried through untouched, since the path is read for
/// the comparison and not written back.
fn sort_items(items : Array[@pjson.Json], path : String) -> Array[@pjson.Json] {
  let decorated : Array[(Int, @pjson.Json)] = []
  for index, item in items {
    decorated.push((index, item))
  }
  decorated.sort_by(fn(first, second) {
    let order = compare_keys(sort_key(first.1, path), sort_key(second.1, path))
    if order == 0 {
      first.0.compare(second.0)
    } else {
      order
    }
  })
  decorated.map(fn(entry) { entry.1 })
}

///|
/// Sort an array, or the one array an object holds.
///
/// A document that is itself a list is sorted directly. A document that is an
/// object is the shape most exports arrive in — one array under a name, which
/// is the "records" of the document — and the array it holds is sorted where it
/// sits, so the rest of the object is left as it was written.
///
/// An object holding more than one array is refused rather than guessed at.
/// There is no way to tell which of them the path was meant for, and sorting
/// the wrong one would be a silent change to a document the caller thought they
/// had described exactly. The message names them so that the run can be given a
/// document with one of them in it.
pub fn sort_by(
  json : @pjson.Json,
  path : String,
) -> Result[@pjson.Json, String] {
  match json {
    Array(items~) => Ok(Array(items=sort_items(items, path)))
    Object(members~) => {
      let arrays : Array[String] = []
      for entry in members {
        match entry.1 {
          Array(_) => arrays.push(entry.0)
          _ => ()
        }
      }
      if arrays.length() == 0 {
        Err(
          "--sort-by sorts an array, and this document is an object with no array in it",
        )
      } else if arrays.length() == 1 {
        let name = arrays[0]
        let out : Array[(String, @pjson.Json)] = []
        for entry in members {
          let (key, value) = entry
          if key == name {
            match value {
              Array(items~) =>
                out.push((key, Array(items=sort_items(items, path))))
              // Unreachable: the name was taken from a member holding an array.
              _ => out.push(entry)
            }
          } else {
            out.push(entry)
          }
        }
        Ok(Object(members=out))
      } else {
        Err(
          "--sort-by sorts one array, and this document is an object holding " +
          arrays.length().to_string() +
          ": " +
          arrays.join(", ") +
          " (leave one of them in the document to say which)",
        )
      }
    }
    _ =>
      Err("--sort-by sorts an array, and this document is " + kind_name(json))
  }
}

///|
/// Drop the items of an array that repeat an item already seen.
///
/// With no field named, an item repeats another when the two print the same:
/// the comparison is of the serialised item, which is the only reading of
/// "the same value" that needs no rule about which differences matter. So `1`
/// and `1.0` are two items, since the text that says `1` is not the text that
/// says `1.0`, and two objects whose members were written in different orders
/// are two items as well — unless the tree handed in has had its keys sorted
/// first, which is how `--sort-keys` reaches this function and how the two
/// become one item.
///
/// With a field named, an item repeats another when that field holds the same
/// value in both. An item that does not have the field at all is kept: it has
/// no value to be compared, and calling it a duplicate of another item that
/// also has none would be answering a question the document did not ask.
///
/// The first of a run of equal items is the one kept, so the document keeps its
/// order and the item kept is the one that was written first.
pub fn unique(
  json : @pjson.Json,
  path : String?,
) -> Result[@pjson.Json, String] {
  match json {
    Array(items~) => {
      let seen : Map[String, Unit] = Map([])
      let out : Array[@pjson.Json] = []
      for item in items {
        let key : String? = match path {
          None => Some(format_compact(item))
          Some(path) =>
            match lookup_path(item, path) {
              Some(value) => Some(format_compact(value))
              None => None
            }
        }
        match key {
          None => out.push(item)
          Some(key) =>
            if !seen.contains(key) {
              seen.set(key, ())
              out.push(item)
            }
        }
      }
      Ok(Array(items=out))
    }
    _ =>
      Err(
        "--unique drops repeats from an array, and this document is " +
        kind_name(json),
      )
  }
}
