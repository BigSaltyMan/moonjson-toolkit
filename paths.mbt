///|
/// Every path in `json`, in document order, one entry per value.
///
/// A path names the route from the root to one value: object members are joined
/// with a dot and array elements are indexed in brackets, so
///
/// ```json
/// {"name": "x", "tags": ["a"], "nested": {"a": {"b": 1}}}
/// ```
///
/// yields `name`, `tags`, `tags[0]`, `nested`, `nested.a` and `nested.a.b`.
/// Containers are listed as well as the values inside them, since a path that
/// names an object or an array is as much a part of the document as one that
/// names a number. The root itself has no path and so is not listed, and a
/// document whose root is a scalar therefore has none.
pub fn collect_paths(json : @pjson.Json) -> Array[String] {
  let paths = []
  walk(json, "", true, paths)
  paths
}

///|
/// Every path in `json` that names an object member, in document order.
///
/// This is `collect_paths` with two things left out. Array elements are not
/// indexed, and arrays are not descended into, so a value inside one is not
/// reached however deeply it is nested: the path stops at the key that holds
/// the array. `{"tags": [{"a": 1}]}` yields `tags` alone, where `collect_paths`
/// would go on to `tags[0]` and `tags[0].a`.
///
/// The result answers "which fields does this document have", ignoring how many
/// times an array repeats them.
pub fn collect_key_paths(json : @pjson.Json) -> Array[String] {
  let paths = []
  walk(json, "", false, paths)
  paths
}

///|
/// Append the paths of everything below `json`, whose own path is `prefix`, to
/// `paths`.
///
/// The path of a value is recorded by whoever holds it — the object or array it
/// sits in — just before descending, so `json` itself is never recorded here.
/// That is what keeps an array from being listed twice, and what lets
/// `expand_arrays` mean "stop at the key holding the array" rather than
/// "record the array and then also descend into it".
fn walk(
  json : @pjson.Json,
  prefix : String,
  expand_arrays : Bool,
  paths : Array[String],
) -> Unit {
  match json {
    Array(items~) =>
      if expand_arrays {
        for index, item in items {
          let path = prefix + "[" + index.to_string() + "]"
          paths.push(path)
          walk(item, path, expand_arrays, paths)
        }
      }
    Object(members~) =>
      for entry in members {
        let (key, value) = entry
        // A member of the root is named by its key alone; there is no leading
        // dot to mark a prefix that does not exist.
        let path = if prefix == "" { key } else { prefix + "." + key }
        paths.push(path)
        walk(value, path, expand_arrays, paths)
      }
    // A scalar is a leaf: its path was recorded on the way in, and there is
    // nothing below it to record.
    _ => ()
  }
}
