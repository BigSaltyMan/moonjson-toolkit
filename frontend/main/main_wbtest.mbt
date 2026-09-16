///|
/// The report the CLI writes for
/// `{"name":"moonjson","tags":["json","cli"],"meta":{"level":2,"ok":true,"none":null}}`,
/// pasted verbatim from `moonjson-toolkit --json-out stats.json`.
let sample_report : String =
  #|{"total_keys":6,"total_nodes":9,"max_depth":3,"type_counts":[{"kind":"string","count":3},{"kind":"object","count":2}],"key_counts":[{"name":"name","count":0},{"name":"meta","count":3}],"depth_counts":[{"depth":1,"count":1},{"depth":2,"count":3},{"depth":3,"count":5}]}

///|
/// Decode a report the way the page does when the fetch succeeds.
fn decode(text : String) -> StatsReport raise {
  let json : Json = @json.parse(text)
  @json.from_json(json)
}

///|
test "the report the CLI writes decodes field for field" {
  let report = decode(sample_report)
  assert_eq(report.total_keys, 6)
  assert_eq(report.total_nodes, 9)
  assert_eq(report.max_depth, 3)
}

///|
test "every distribution survives the round trip" {
  let report = decode(sample_report)
  assert_eq(report.type_counts.length(), 2)
  assert_eq(report.type_counts[0].kind, "string")
  assert_eq(report.type_counts[0].count, 3)
  assert_eq(report.key_counts[1].name, "meta")
  assert_eq(report.key_counts[1].count, 3)
  assert_eq(report.depth_counts[2].depth, 3)
  assert_eq(report.depth_counts[2].count, 5)
}

///|
test "the report survives being sent on to the charts" {
  let report = decode(sample_report)
  let text = @json.to_json(report).stringify()
  assert_eq(@json.to_json(decode(text)).stringify(), text)
}

///|
test "a report that is missing a field is rejected rather than defaulted" {
  let json : Json = @json.parse("{\"total_keys\":1,\"total_nodes\":1}")
  let decoded : Result[StatsReport, Error] = try @json.from_json(json) catch {
    error => Err(error)
  } noraise {
    report => Ok(report)
  }
  assert_true(decoded is Err(_))
}
