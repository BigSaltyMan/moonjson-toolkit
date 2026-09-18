///|
/// A document that exercises nesting, so the statistics are not all zeroes.
/// 9 nodes, 4 keys and a maximum depth of 4.
let document_sample : String =
  #|{"name":"moon","version":1,"tags":["json","cli"],"nested":{"a":{"b":2}}}

///|
/// The two scratch paths one test owns.
///
/// `moon test` runs tests concurrently, so every test needs its own names: a
/// shared path would let one test delete a file another is still reading.
struct Scratch {
  input : String
  stats : String
}

///|
fn Scratch::named(name : String) -> Scratch {
  {
    input: "runner_scratch_" + name + ".json",
    stats: "runner_scratch_" + name + "_stats.json",
  }
}

///|
/// A stand-in for the network call, so no test ever reaches DeepSeek and the
/// number of calls can be asserted on.
struct StubAnalyzer {
  mut calls : Int
  reply : Result[String, String]
}

///|
fn StubAnalyzer::new(reply : Result[String, String]) -> StubAnalyzer {
  { calls: 0, reply, }
}

///|
fn StubAnalyzer::analyzer(
  self : StubAnalyzer,
) -> async (String) -> Result[String, String] {
  fn(_prompt) {
    self.calls = self.calls + 1
    self.reply
  }
}

///|
/// The shape every test follows: write the document, run the tool over it,
/// clean up, and hand back what happened.
async fn run_on(
  scratch : Scratch,
  text : String,
  extra : Array[String],
  analyzer : StubAnalyzer,
) -> RunResult {
  @fs.write_file(scratch.input, text)
  let result = run(["-f", scratch.input] + extra, analyze=analyzer.analyzer())
  discard(scratch.input)
  result
}

///|
/// Read a file back, so a test can assert on what was written.
async fn read_back(path : String) -> String {
  @fs.read_file(path).text()
}

///|
/// Whether a path exists, so a test can assert that nothing was written.
async fn exists(path : String) -> Bool {
  try @fs.read_file(path) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
/// Delete a scratch file, ignoring the case where it was never created.
async fn discard(path : String) -> Unit {
  try @fs.remove(path) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
async test "-v prints the verdict, not the document, and still writes statistics" {
  let scratch = Scratch::named("verdict")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let result = run_on(
    scratch,
    document_sample,
    ["-v", "--json-out", scratch.stats],
    analyzer,
  )
  inspect(result.code, content="0")
  inspect(result.out, content=scratch.input + ": valid JSON\n")
  assert_eq(analyzer.calls, 0)
  // The statistics file is half the point of the combination, so it must be
  // written even though `-v` suppressed the document itself.
  let written = read_back(scratch.stats)
  assert_true(written.contains("\"total_nodes\": 9"))
  assert_true(written.contains("\"max_depth\": 4"))
  discard(scratch.stats)
}

///|
async test "-v still asks for the AI review and prints its report" {
  let scratch = Scratch::named("validate_ai")
  let analyzer = StubAnalyzer::new(Ok("looks fine to me"))
  let result = run_on(scratch, document_sample, ["-v", "--ai"], analyzer)
  inspect(result.code, content="0")
  assert_eq(analyzer.calls, 1)
  assert_true(result.out.contains(scratch.input + ": valid JSON"))
  assert_true(result.out.contains("AI quality report"))
  assert_true(result.out.contains("looks fine to me"))
  assert_false(result.out.contains("\"name\""))
}

///|
async test "a successful review follows the document without --json-out" {
  let scratch = Scratch::named("review_ok")
  let analyzer = StubAnalyzer::new(Ok("looks fine to me"))
  let result = run_on(scratch, document_sample, ["--ai"], analyzer)
  inspect(result.code, content="0")
  assert_eq(analyzer.calls, 1)
  match (result.out.find("\"name\""), result.out.find("AI quality report")) {
    (Some(document_at), Some(report_at)) => assert_true(document_at < report_at)
    _ => abort("both the document and the report should be on standard output")
  }
}

///|
async test "a failed review exits 3 and leaves standard output empty" {
  let scratch = Scratch::named("review_failed")
  let analyzer = StubAnalyzer::new(Err("DEEPSEEK_API_KEY is not set"))
  let result = run_on(scratch, document_sample, ["--ai"], analyzer)
  inspect(result.code, content="3")
  // The document must not be printed: a caller piping the output would
  // otherwise get half a result before the failure.
  inspect(result.out, content="")
  assert_true(result.err.contains("DEEPSEEK_API_KEY is not set"))
  assert_eq(analyzer.calls, 1)
}

///|
async test "a failed review exits 3 in validate mode too" {
  let scratch = Scratch::named("validate_failed")
  let analyzer = StubAnalyzer::new(Err("network is down"))
  let result = run_on(scratch, document_sample, ["-v", "--ai"], analyzer)
  inspect(result.code, content="3")
  inspect(result.out, content="")
  assert_true(result.err.contains("network is down"))
}

///|
async test "an invalid document exits 1 without statistics or a review" {
  let scratch = Scratch::named("invalid")
  let analyzer = StubAnalyzer::new(Ok("should never run"))
  let result = run_on(
    scratch,
    "{\"a\":1,}",
    ["--json-out", scratch.stats, "--ai"],
    analyzer,
  )
  inspect(result.code, content="1")
  inspect(result.out, content="")
  assert_true(result.err.contains("is not valid JSON"))
  // Neither the statistics file nor the review may happen for a document that
  // did not parse.
  assert_eq(analyzer.calls, 0)
  assert_false(exists(scratch.stats))
}

///|
async test "an unwritable statistics path exits 1 and prints no document" {
  let scratch = Scratch::named("unwritable")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let result = run_on(
    scratch,
    document_sample,
    ["--json-out", "runner_scratch_no_such_dir/stats.json"],
    analyzer,
  )
  inspect(result.code, content="1")
  inspect(result.out, content="")
  assert_true(result.err.contains("cannot write"))
  assert_eq(analyzer.calls, 0)
}

///|
async test "--trim-strings reaches the printed document" {
  let scratch = Scratch::named("trim")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let result = run_on(
    scratch,
    "{\"a\":\"  x  \"}",
    ["--trim-strings"],
    analyzer,
  )
  inspect(result.code, content="0")
  inspect(result.out, content="{\n  \"a\": \"x\"\n}\n")
  assert_eq(analyzer.calls, 0)
}

///|
async test "several files are handled in turn, each under its own heading" {
  let first = Scratch::named("multi_first")
  let second = Scratch::named("multi_second")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  @fs.write_file(first.input, "{\"a\":1}")
  @fs.write_file(second.input, "{\"b\":2}")
  let result = run(
    ["-f", first.input, "-f", second.input],
    analyze=analyzer.analyzer(),
  )
  discard(first.input)
  discard(second.input)
  inspect(result.code, content="0")
  inspect(
    result.out,
    content="==> " +
      first.input +
      " <==\n{\n  \"a\": 1\n}\n==> " +
      second.input +
      " <==\n{\n  \"b\": 2\n}\n",
  )
  inspect(result.err, content="")
}

///|
async test "a file that fails does not stop the ones after it" {
  let good = Scratch::named("multi_good")
  let bad = Scratch::named("multi_bad")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  @fs.write_file(good.input, "{\"a\":1}")
  @fs.write_file(bad.input, "{\"a\":1,}")
  // The bad file is named first, so the good one is only reached at all if a
  // failure leaves the run going.
  let result = run(
    ["-f", bad.input, "-f", good.input],
    analyze=analyzer.analyzer(),
  )
  discard(good.input)
  discard(bad.input)
  inspect(result.code, content="1")
  assert_true(result.out.contains("==> " + good.input + " <=="))
  // The failure is reported, and reports nothing on standard output: no heading
  // for a document that was never produced.
  assert_true(result.err.contains(bad.input + " is not valid JSON"))
  assert_false(result.out.contains(bad.input + " <=="))
}

///|
async test "--json-out is refused when several files are named" {
  let analyzer = StubAnalyzer::new(Ok("unused"))
  // Neither name exists, which is the point: the command line is refused
  // before anything is opened.
  let result = run(
    ["-f", "no_such_a.json", "-f", "no_such_b.json", "--json-out", "s.json"],
    analyze=analyzer.analyzer(),
  )
  inspect(result.code, content="2")
  inspect(result.out, content="")
  assert_true(result.err.contains("--json-out describes a single document"))
  assert_false(result.err.contains("no such file"))
  assert_eq(analyzer.calls, 0)
}

///|
async test "--help prints the usage and exits 0 without reading anything" {
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let result = run(["--help"], analyze=analyzer.analyzer())
  inspect(result.code, content="0")
  assert_true(result.out.contains("Usage:"))
  assert_true(
    result.out.contains("3  the input was valid but the AI review failed"),
  )
  inspect(result.err, content="")
}

///|
async test "an unknown option exits 2" {
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let result = run(["--nonsense"], analyze=analyzer.analyzer())
  inspect(result.code, content="2")
  inspect(result.out, content="")
  assert_true(result.err.contains("--nonsense"))
}
