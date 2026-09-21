///|
/// How many nodes of one JSON type the document holds.
pub(all) struct TypeCount {
  kind : String
  count : Int
} derive(ToJson)

///|
/// Name the `to_json` method that `derive(ToJson)` provides.
///
/// The implicit promotion of an impl's methods to regular methods is deprecated
/// as of moon 0.1.20260920, and `--deny-warn` refuses it. Spelling the promotion
/// out changes nothing about the type or the JSON it produces: `derive` still
/// writes the method, and this says which one it is.
pub extend TypeCount with ToJson::{to_json}

///|
/// How many keys one top-level field contains, counting nested ones.
pub(all) struct KeyCount {
  name : String
  count : Int
} derive(ToJson)

///|
/// As for `TypeCount`: the promotion `derive(ToJson)` makes, spelled out.
pub extend KeyCount with ToJson::{to_json}

///|
/// How many nodes sit at one nesting depth.
pub(all) struct DepthCount {
  depth : Int
  count : Int
} derive(ToJson)

///|
/// As for `TypeCount`: the promotion `derive(ToJson)` makes, spelled out.
pub extend DepthCount with ToJson::{to_json}

///|
/// Summary statistics for one JSON document.
///
/// This is the shape written by `--json-out` and read by the frontend, so the
/// field names are part of the tool's interface rather than an internal detail.
pub(all) struct JsonStats {
  total_keys : Int
  total_nodes : Int
  max_depth : Int
  type_counts : Array[TypeCount]
  key_counts : Array[KeyCount]
  depth_counts : Array[DepthCount]
} derive(ToJson)

///|
/// As for `TypeCount`: the promotion `derive(ToJson)` makes, spelled out.
pub extend JsonStats with ToJson::{to_json}

///|
/// Mutable accumulator threaded through the statistics walk.
///
/// The record holds mutable fields, so it is passed by reference and every
/// `walk_stats` call contributes to the same totals.
priv struct StatsBuilder {
  mut total_keys : Int
  mut total_nodes : Int
  mut max_depth : Int
  mut nulls : Int
  mut booleans : Int
  mut numbers : Int
  mut strings : Int
  mut arrays : Int
  mut objects : Int
  depth_counts : Array[Int]
}

///|
/// A fresh accumulator, with the root depth already present.
fn StatsBuilder::new() -> StatsBuilder {
  {
    total_keys: 0,
    total_nodes: 0,
    max_depth: 0,
    nulls: 0,
    booleans: 0,
    numbers: 0,
    strings: 0,
    arrays: 0,
    objects: 0,
    depth_counts: [0],
  }
}

///|
/// Count one more node at `depth`, growing the table if this is a new depth.
fn record_depth(builder : StatsBuilder, depth : Int) -> Unit {
  while builder.depth_counts.length() <= depth {
    builder.depth_counts.push(0)
  }
  builder.depth_counts[depth] = builder.depth_counts[depth] + 1
}

///|
/// Record `json` at `depth` and recurse into its children.
///
/// Depths are 1-based, so a scalar document reports a maximum depth of 1.
fn walk_stats(builder : StatsBuilder, json : @pjson.Json, depth : Int) -> Unit {
  builder.total_nodes = builder.total_nodes + 1
  if depth > builder.max_depth {
    builder.max_depth = depth
  }
  record_depth(builder, depth)
  match json {
    Null => builder.nulls = builder.nulls + 1
    Bool(_) => builder.booleans = builder.booleans + 1
    Number(_) => builder.numbers = builder.numbers + 1
    Text(_) => builder.strings = builder.strings + 1
    Array(items~) => {
      builder.arrays = builder.arrays + 1
      for item in items {
        walk_stats(builder, item, depth + 1)
      }
    }
    Object(members~) => {
      builder.objects = builder.objects + 1
      builder.total_keys = builder.total_keys + members.length()
      for entry in members {
        let (_, value) = entry
        walk_stats(builder, value, depth + 1)
      }
    }
  }
}

///|
/// Count every object member inside `json`, at any depth.
fn count_keys(json : @pjson.Json) -> Int {
  match json {
    Object(members~) => {
      let mut total = members.length()
      for entry in members {
        let (_, value) = entry
        total = total + count_keys(value)
      }
      total
    }
    Array(items~) => {
      let mut total = 0
      for item in items {
        total = total + count_keys(item)
      }
      total
    }
    _ => 0
  }
}

///|
/// The number of keys inside each top-level field.
///
/// Charting these counts shows which parts of a document carry the most
/// structure, which is usually where a refactor pays off. A document whose root
/// is not an object is reported as a single `<root>` entry.
fn top_level_key_counts(json : @pjson.Json) -> Array[KeyCount] {
  match json {
    Object(members~) => {
      let counts = []
      for entry in members {
        let (name, value) = entry
        counts.push({ name, count: count_keys(value), })
      }
      counts
    }
    _ => [{ name: "<root>", count: count_keys(json), }]
  }
}

///|
/// Compute the statistics of `json`.
pub fn JsonStats::of(json : @pjson.Json) -> JsonStats {
  let builder = StatsBuilder::new()
  walk_stats(builder, json, 1)
  let types : Array[TypeCount] = [
    { kind: "null", count: builder.nulls, },
    { kind: "boolean", count: builder.booleans, },
    { kind: "number", count: builder.numbers, },
    { kind: "string", count: builder.strings, },
    { kind: "array", count: builder.arrays, },
    { kind: "object", count: builder.objects, },
  ]
  let depths : Array[DepthCount] = []
  for depth in 1..<(builder.max_depth + 1) {
    depths.push({ depth, count: builder.depth_counts[depth], })
  }
  {
    total_keys: builder.total_keys,
    total_nodes: builder.total_nodes,
    max_depth: builder.max_depth,
    type_counts: types,
    key_counts: top_level_key_counts(json),
    depth_counts: depths,
  }
}

///|
/// Render the statistics as indented JSON, ready for the frontend to read.
pub fn JsonStats::to_json_text(self : JsonStats) -> String {
  @json.to_json(self).stringify(indent=2)
}

///|
/// Render the statistics as the two lines `--stats` prints:
///
/// ```
/// keys: 6  nodes: 9  depth: 4
/// type counts: object=3 array=1 string=3 number=2
/// ```
///
/// A type that does not occur is left out rather than printed as `kind=0`. The
/// line is a summary of what the document holds, and the absence of a type says
/// that in less room than a row of zeroes would.
///
/// The counts that remain keep the canonical order of `type_counts` — the order
/// `to_json_text` writes and the dashboard charts — rather than being sorted by
/// size, so a reader comparing two documents can follow one type with their eye
/// down both lines. It also means the two lines agree with the statistics file
/// entry for entry: `--stats` is the same numbers in less space.
pub fn JsonStats::to_text(self : JsonStats) -> String {
  let buf = StringBuilder()
  buf.write_string("keys: " + self.total_keys.to_string())
  buf.write_string("  nodes: " + self.total_nodes.to_string())
  buf.write_string("  depth: " + self.max_depth.to_string())
  buf.write_char('\n')
  buf.write_string("type counts:")
  for entry in self.type_counts {
    if entry.count > 0 {
      buf.write_string(" " + entry.kind + "=" + entry.count.to_string())
    }
  }
  buf.to_string()
}

///|
/// Write the statistics of `json` to `path`.
pub async fn write_stats_file(
  path : String,
  json : @pjson.Json,
) -> Result[Unit, String] {
  let text = JsonStats::of(json).to_json_text() + "\n"
  try {
    @fs.write_file(path, text)
    Ok(())
  } catch {
    error => Err(describe_io_error(error))
  }
}
