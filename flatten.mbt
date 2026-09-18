///|
/// The message for two keys that cannot both be honoured.
///
/// The shorter spelling is named first: it is the one the longer extends, and
/// reading it that way round is what makes the pair a pair.
fn conflicting_keys(left : String, right : String) -> String {
  let (shorter, longer) = if left.length() <= right.length() {
    (left, right)
  } else {
    (right, left)
  }
  "conflicting keys: " +
  quote_for_message(shorter) +
  " and " +
  quote_for_message(longer)
}

///|
/// Return `json` with every nested object collapsed into dotted keys.
///
/// A member whose value is an object is replaced by one member per path inside
/// that object, each named by joining the keys along the way with a dot, so
/// `{"a":{"b":1},"c":2}` becomes `{"a.b":1,"c":2}`. Any depth is collapsed, and
/// the members come out in the order the paths were written in.
///
/// Keys are only ever joined, never rewritten, so a document that was already
/// flat comes back the way it was. An empty object has no paths inside it and
/// stays a value: `{"a":{}}` keeps its member holding `{}`.
///
/// An array is a value rather than a level, so a key holding one keeps its
/// name, but the objects inside it are documents of their own and are flattened
/// in turn: `{"a":[{"b":{"c":1}}]}` becomes `{"a":[{"b.c":1}]}`.
///
/// A document can also be written so that it has no flattening. If a member is
/// named `a.b` while a sibling named `a` holds an object, lifting `a` produces
/// a second `a.b` and one of the two would have to go; that is refused with a
/// message naming both keys rather than settled by a rule about which of them
/// matters less. Literal dotted keys are perfectly readable, though, so a
/// sibling named `a` holding anything else is no trouble at all.
pub fn flatten(json : @pjson.Json) -> Result[@pjson.Json, String] {
  match json {
    Object(members~) => {
      let out : Array[(String, @pjson.Json)] = []
      // Which member of this object each path came out of: when two of them
      // land on the same path, the message has to name both.
      let sources : Map[String, String] = Map([])
      match flatten_members(members, None, None, out, sources) {
        Ok(_) => Ok(Object(members=out))
        Err(message) => Err(message)
      }
    }
    Array(items~) => flatten_items(items)
    // A scalar has nothing inside it to lift.
    leaf => Ok(leaf)
  }
}

///|
/// Lift the members of one object into `out`, prefixing every path with
/// `prefix`.
///
/// The prefix is optional rather than a string that may be empty, because an
/// empty prefix is a real one: a member named `""` puts a dot in front of
/// everything under it, and `{"": {"a": 1}}` is the key `".a"` rather than the
/// key `"a"`.
///
/// `root` is the key this descent started under, or `None` when the members
/// belong to the object the caller was given. Every path lifted out of a
/// subtree is named by that one key, however deep the path goes, which is what
/// lets a clash with a sibling be reported with the two keys that are actually
/// brothers: `{"a": {"b": {"c": 1}}, "a.b.c": 2}` is a clash between `a` and
/// `a.b.c`, not between `c` and `a.b.c`.
fn flatten_members(
  members : Array[(String, @pjson.Json)],
  prefix : String?,
  root : String?,
  out : Array[(String, @pjson.Json)],
  sources : Map[String, String],
) -> Result[Unit, String] {
  for entry in members {
    let (key, value) = entry
    let path = match prefix {
      None => key
      Some(prefix) => prefix + "." + key
    }
    let source = match root {
      None => key
      Some(root) => root
    }
    let placed = match value {
      Object(members=inner) =>
        if inner.is_empty() {
          emit(out, sources, path, source, value)
        } else {
          flatten_members(inner, Some(path), Some(source), out, sources)
        }
      Array(items~) =>
        match flatten_items(items) {
          Ok(flat) => emit(out, sources, path, source, flat)
          Err(message) => Err(message)
        }
      leaf => emit(out, sources, path, source, leaf)
    }
    match placed {
      Ok(_) => ()
      Err(message) => return Err(message)
    }
  }
  Ok(())
}

///|
/// Flatten the objects inside an array.
///
/// The array keeps its length and its items keep their places: flattening
/// changes what is inside an object and never how many values there are.
fn flatten_items(items : Array[@pjson.Json]) -> Result[@pjson.Json, String] {
  let out : Array[@pjson.Json] = []
  for item in items {
    match flatten(item) {
      Ok(flat) => out.push(flat)
      Err(message) => return Err(message)
    }
  }
  Ok(Array(items=out))
}

///|
/// Add one flattened member, refusing a path that is already taken.
///
/// Two members of the same object can only reach the same path when one of them
/// spells out what the other holds: `{"a.b":1,"a":{"b":2}}`. `source` is the key
/// that named the path where the descent began, which is what the message names
/// on that side.
fn emit(
  out : Array[(String, @pjson.Json)],
  sources : Map[String, String],
  path : String,
  source : String,
  value : @pjson.Json,
) -> Result[Unit, String] {
  match sources.get(path) {
    Some(first) => Err(conflicting_keys(first, source))
    None => {
      sources.set(path, source)
      out.push((path, value))
      Ok(())
    }
  }
}

///|
/// Return `json` with the dotted keys of every object expanded into nested
/// objects, the inverse of `flatten`.
///
/// A key is split at its dots and the value is placed at the end of the path,
/// creating the objects along the way: `{"a.b":1,"c":2}` becomes
/// `{"a":{"b":1},"c":2}`. Keys that share a prefix are merged, so
/// `{"a.b":1,"a.c":2}` becomes `{"a":{"b":1,"c":2}}`, and the members keep the
/// order they were written in. A key with no dot in it names a member of the
/// object it is already in, so a document that was never flattened comes back
/// unchanged.
///
/// A document that spells one path two ways is refused rather than sorted out
/// by letting one key win. `{"a":1,"a.b":2}` cannot be expanded, since writing
/// `b` into `a` would mean dropping the `1`; it is reported as
///
/// ```
/// conflicting keys: "a" and "a.b"
/// ```
///
/// The rule is about the keys themselves rather than the order they are written
/// in, and it is deliberately blind to what the value at `a` holds:
/// `{"a":{"z":1},"a.b":2}` could be merged, but a document that names one place
/// two ways is a document that does not agree with itself.
pub fn unflatten(json : @pjson.Json) -> Result[@pjson.Json, String] {
  match json {
    Object(members~) =>
      match check_key_conflicts(members) {
        Err(message) => Err(message)
        Ok(_) => {
          let entries : Array[(Array[String], String, @pjson.Json)] = []
          for entry in members {
            let (key, value) = entry
            match unflatten(value) {
              Err(message) => return Err(message)
              Ok(expanded) => entries.push((split_path(key), key, expanded))
            }
          }
          Ok(Object(members=expand(entries)))
        }
      }
    Array(items~) => unflatten_items(items)
    leaf => Ok(leaf)
  }
}

///|
/// Unflatten the objects inside an array. As in `flatten`, the array keeps its
/// length and its items keep their places.
fn unflatten_items(items : Array[@pjson.Json]) -> Result[@pjson.Json, String] {
  let out : Array[@pjson.Json] = []
  for item in items {
    match unflatten(item) {
      Ok(flat) => out.push(flat)
      Err(message) => return Err(message)
    }
  }
  Ok(Array(items=out))
}

///|
/// Refuse a set of keys in which one is the dotted start of another.
///
/// Such a pair cannot both be honoured: expanding `a.b` means writing into the
/// member named `a`, and `a` is already there holding something else. Every
/// proper dotted prefix of every key is looked up, so `a` and `a.b` are caught,
/// and so are `a.b` and `a.b.c`, which clash further along the same path.
fn check_key_conflicts(
  members : Array[(String, @pjson.Json)],
) -> Result[Unit, String] {
  let keys : Map[String, Unit] = Map([])
  for entry in members {
    let (key, _) = entry
    keys.set(key, ())
  }
  for entry in members {
    let (key, _) = entry
    let segments = split_path(key)
    let mut prefix = segments[0]
    let mut index = 1
    // The whole key is not a prefix of itself, so the walk stops before the
    // last segment is joined on.
    while index < segments.length() {
      if keys.contains(prefix) {
        return Err(conflicting_keys(prefix, key))
      }
      prefix = prefix + "." + segments[index]
      index = index + 1
    }
  }
  Ok(())
}

///|
/// The segments of a dotted key, in order.
///
/// A separator that produces an empty segment is kept: `"a."` is two segments
/// and `""` is one, so the path a key names has exactly as many levels as the
/// key has dots.
fn split_path(key : String) -> Array[String] {
  key.split(".").map(fn(part) { part.to_owned() }).collect()
}

///|
/// Build the members of one object from entries that have already been checked
/// against each other and whose values have already been unflattened.
///
/// Entries are grouped by their first segment, keeping the order they came in:
/// each group becomes one member, either the value itself when the group is the
/// key on its own, or an object holding the rest of the path when the key
/// continues.
fn expand(
  entries : Array[(Array[String], String, @pjson.Json)],
) -> Array[(String, @pjson.Json)] {
  let groups : Map[String, Array[(Array[String], String, @pjson.Json)]] = Map([])
  for entry in entries {
    let (segments, _, _) = entry
    groups.get_or_init(segments[0], fn() { [] }).push(entry)
  }
  let out : Array[(String, @pjson.Json)] = []
  for head, group in groups {
    let (segments, _, value) = group[0]
    if segments.length() == 1 {
      // A key with no dot in it. Nothing else can be in this group: two members
      // cannot share a key, and a key extending this one by a dot was refused.
      out.push((head, value))
    } else {
      let tails = group.map(fn(entry) {
        let (segments, spelling, value) = entry
        (segments[1:].to_owned(), spelling, value)
      })
      out.push((head, Object(members=expand(tails))))
    }
  }
  out
}
