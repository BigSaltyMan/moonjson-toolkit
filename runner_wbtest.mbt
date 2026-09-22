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
/// A stand-in for the network call, so no test ever reaches a real API and the
/// number of calls can be asserted on.
///
/// It keeps the arguments it was handed as well as counting them, because the
/// settings reach `analyze` as four positional strings, and nothing but a test
/// can tell a call that put the model where the endpoint belongs from one that
/// put it where the model belongs.
struct StubAnalyzer {
  mut calls : Int
  mut asked : (String, String, String, String)?
  reply : Result[String, String]
}

///|
fn StubAnalyzer::new(reply : Result[String, String]) -> StubAnalyzer {
  { calls: 0, asked: None, reply, }
}

///|
fn StubAnalyzer::analyzer(
  self : StubAnalyzer,
) -> async (String, String, String, String) -> Result[String, String] {
  fn(json_text, endpoint, model, api_key) {
    self.calls = self.calls + 1
    self.asked = Some((json_text, endpoint, model, api_key))
    self.reply
  }
}

///|
/// The key the runner resolves in these tests.
///
/// A stub for the call is not enough on its own: the runner reads the
/// environment before it calls the analyzer, so without a key there every `--ai`
/// run would stop before reaching the stub. It is planted under the name that
/// is read first, so a real key in the developer's own environment cannot
/// change what these tests do.
let stub_api_key : String = "sk-test-key"

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
  @env.set_env_var(api_key_variable, stub_api_key)
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
/// What was asked for is what is sent: the endpoint, the model and the key
/// travel from the command line and the environment to the request as three
/// separate strings, and this is the one place they can be checked in the
/// order `analyze` reads them.
async test "the review names the endpoint and model the command line asked for" {
  let scratch = Scratch::named("review_settings")
  let analyzer = StubAnalyzer::new(Ok("looks fine to me"))
  let result = run_on(
    scratch,
    document_sample,
    [
      "--ai", "--model", "a-model", "--ai-base-url", "http://localhost:1234/v1/chat/completions",
    ],
    analyzer,
  )
  inspect(result.code, content="0")
  match analyzer.asked {
    Some((json_text, endpoint, model, api_key)) => {
      assert_eq(endpoint, "http://localhost:1234/v1/chat/completions")
      assert_eq(model, "a-model")
      assert_eq(api_key, stub_api_key)
      assert_true(json_text.contains("\"name\""))
    }
    None => abort("the analyzer should have been asked exactly once")
  }
}

///|
async test "a failed review exits 3 and leaves standard output empty" {
  let scratch = Scratch::named("review_failed")
  let analyzer = StubAnalyzer::new(
    Err("MOONJSON_AI_API_KEY or DEEPSEEK_API_KEY is not set"),
  )
  let result = run_on(scratch, document_sample, ["--ai"], analyzer)
  inspect(result.code, content="3")
  // The document must not be printed: a caller piping the output would
  // otherwise get half a result before the failure.
  inspect(result.out, content="")
  assert_true(result.err.contains("is not set"))
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
async test "--flatten and --unflatten reach the printed document" {
  let scratch = Scratch::named("flatten")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let flattened = run_on(
    scratch,
    "{\"a\":{\"b\":1},\"c\":2}",
    ["--flatten", "--compact"],
    analyzer,
  )
  inspect(flattened.code, content="0")
  inspect(flattened.out, content="{\"a.b\":1,\"c\":2}\n")
  inspect(flattened.err, content="")
  // The same text read the other way, and printed as the nesting it describes:
  // the reshaping happens before the layout, so the two agree on what the
  // document is.
  let unflattened = run_on(
    scratch,
    "{\"a.b\":1,\"c\":2}",
    ["--unflatten"],
    analyzer,
  )
  inspect(unflattened.code, content="0")
  inspect(
    unflattened.out,
    content="{\n  \"a\": {\n    \"b\": 1\n  },\n  \"c\": 2\n}\n",
  )
  assert_eq(analyzer.calls, 0)
}

///|
async test "a document that cannot be reshaped exits 1 and prints nothing" {
  let scratch = Scratch::named("flatten_conflict")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let result = run_on(
    scratch,
    "{\"a\":{\"b\":1},\"a.b\":2}",
    ["--flatten"],
    analyzer,
  )
  inspect(result.code, content="1")
  // Nothing reaches standard output, as with a document that does not parse:
  // there is no flattened form of this one to print.
  inspect(result.out, content="")
  inspect(
    result.err,
    content="error: " +
      scratch.input +
      " cannot be flattened\nconflicting keys: \"a\" and \"a.b\"\n",
  )
  assert_eq(analyzer.calls, 0)
}

///|
async test "--prune-null and --prune-empty reach the printed document" {
  let scratch = Scratch::named("prune")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  // The nulls go first, then the containers they left empty, so one pass of the
  // pair clears a document down to what it actually says.
  let result = run_on(
    scratch,
    "{\"a\":null,\"b\":{},\"c\":[1,null],\"d\":{\"e\":null}}",
    ["--prune-null", "--prune-empty", "--compact"],
    analyzer,
  )
  inspect(result.code, content="0")
  inspect(result.out, content="{\"c\":[1,null]}\n")
  inspect(result.err, content="")
  // `--prune-null` on its own keeps every item of an array, null ones included.
  let nulls_only = run_on(
    scratch,
    "{\"a\":null,\"b\":[1,null]}",
    ["--prune-null", "--compact"],
    analyzer,
  )
  inspect(nulls_only.out, content="{\"b\":[1,null]}\n")
  assert_eq(analyzer.calls, 0)
}

///|
async test "--stats counts the document the run produced" {
  let scratch = Scratch::named("prune_stats")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let text = "{\"a\":null,\"b\":{\"c\":null,\"d\":1}}"
  let whole = run_on(scratch, text, ["--stats"], analyzer)
  inspect(
    whole.out,
    content="keys: 4  nodes: 5  depth: 3\ntype counts: null=2 number=1 object=2\n",
  )
  // The members the pruning takes away are gone from the counts as well as from
  // the document: the summary describes what the run produced, which is what
  // the reader has in front of them.
  let pruned = run_on(scratch, text, ["--prune-null", "--stats"], analyzer)
  inspect(
    pruned.out,
    content="keys: 2  nodes: 3  depth: 3\ntype counts: number=1 object=2\n",
  )
  // The file `--json-out` writes reports the same numbers as the summary.
  let reported = run_on(
    scratch,
    text,
    ["--prune-null", "--json-out", scratch.stats],
    analyzer,
  )
  inspect(reported.code, content="0")
  let written = read_back(scratch.stats)
  assert_true(written.contains("\"total_keys\": 2"))
  assert_true(written.contains("\"total_nodes\": 3"))
  discard(scratch.stats)
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
/// The same bad file in the middle of three, with `--continue-on-error` asking
/// the run to say at the end what it found on the way.
///
/// The count is of inputs rather than of documents: the bad one is the input
/// that failed and the two around it are the ones that passed, which is why a
/// run of three files can be two and one. Each failure is named once, with the
/// message it produced indented under it — the same message standard error
/// already carries, printed where the run ends instead of where it happened.
async test "--continue-on-error carries on past a failure and summarises the run" {
  let first = Scratch::named("recover_first")
  let bad = Scratch::named("recover_bad")
  let last = Scratch::named("recover_last")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  @fs.write_file(first.input, "{\"a\":1}")
  @fs.write_file(bad.input, "{\"a\":1,}")
  @fs.write_file(last.input, "{\"c\":3}")
  let result = run(
    [
      "-f",
      first.input,
      "-f",
      bad.input,
      "-f",
      last.input,
      "--continue-on-error",
    ],
    analyze=analyzer.analyzer(),
  )
  discard(first.input)
  discard(bad.input)
  discard(last.input)
  inspect(result.code, content="1")
  inspect(
    result.out,
    content="==> " +
      first.input +
      " <==\n{\n  \"a\": 1\n}\n==> " +
      last.input +
      " <==\n{\n  \"c\": 3\n}\n\nSummary: 2 passed, 1 failed\n  failed: " +
      bad.input +
      "\n    error: " +
      bad.input +
      " is not valid JSON\n    line 1, column 8: expected opening quote\n      {\"a\":1,}\n             ^\n",
  )
  // The same failure as standard error carries it, with the run's own
  // indentation taken back off.
  inspect(
    result.err,
    content="error: " +
      bad.input +
      " is not valid JSON\nline 1, column 8: expected opening quote\n  {\"a\":1,}\n         ^\n",
  )
  assert_eq(analyzer.calls, 0)
}

///|
/// A summary is a report of failures, and a run that had none has nothing to
/// report: the output must not grow a line saying that nothing went wrong.
async test "--continue-on-error says nothing when every input passed" {
  let first = Scratch::named("quiet_first")
  let second = Scratch::named("quiet_second")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  @fs.write_file(first.input, "{\"a\":1}")
  @fs.write_file(second.input, "{\"b\":2}")
  let result = run(
    ["-f", first.input, "-f", second.input, "--continue-on-error"],
    analyze=analyzer.analyzer(),
  )
  discard(first.input)
  discard(second.input)
  inspect(result.code, content="0")
  assert_false(result.out.contains("Summary"))
  inspect(result.err, content="")
}

///|
/// `--fail-fast` is the other reading of the same run: the first input that
/// fails is the last one read, so the files after it never appear.
///
/// Both orders are tried, because stopping early is only visible when there was
/// something left to stop before: after a bad file at the front, nothing is
/// printed at all, and after a good one everything printed so far stands.
async test "--fail-fast stops at the input that failed" {
  let good = Scratch::named("fast_good")
  let bad = Scratch::named("fast_bad")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  @fs.write_file(good.input, "{\"a\":1}")
  @fs.write_file(bad.input, "{\"a\":1,}")
  let leading = run(
    ["-f", bad.input, "-f", good.input, "--fail-fast"],
    analyze=analyzer.analyzer(),
  )
  inspect(leading.code, content="1")
  // The good file is never read, so it prints nothing and gets no heading.
  inspect(leading.out, content="")
  assert_true(leading.err.contains(bad.input + " is not valid JSON"))
  let trailing = run(
    ["-f", good.input, "-f", bad.input, "-f", good.input, "--fail-fast"],
    analyze=analyzer.analyzer(),
  )
  discard(good.input)
  discard(bad.input)
  inspect(trailing.code, content="1")
  // The file before the failure is printed and the one after it is not: the
  // same file is named twice, and only the first of the two is handled.
  inspect(
    trailing.out,
    content="==> " + good.input + " <==\n{\n  \"a\": 1\n}\n",
  )
  assert_true(trailing.err.contains(bad.input + " is not valid JSON"))
  assert_eq(analyzer.calls, 0)
}

///|
async test "--fail-fast and --continue-on-error are refused together" {
  let analyzer = StubAnalyzer::new(Ok("unused"))
  // The name does not exist, which is the point: the two flags are about the
  // run as a whole, so they are settled before anything is opened.
  let result = run(
    ["-f", "no_such.json", "--fail-fast", "--continue-on-error"],
    analyze=analyzer.analyzer(),
  )
  inspect(result.code, content="2")
  inspect(result.out, content="")
  assert_true(result.err.contains("--fail-fast stops at the first failure"))
  assert_false(result.err.contains("no such file"))
  assert_eq(analyzer.calls, 0)
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
async test "--flatten and --unflatten together are refused" {
  let analyzer = StubAnalyzer::new(Ok("unused"))
  // Neither name exists, which is the point: the command line is refused
  // before anything is opened.
  let result = run(
    ["-f", "no_such.json", "--flatten", "--unflatten"],
    analyze=analyzer.analyzer(),
  )
  inspect(result.code, content="2")
  inspect(result.out, content="")
  assert_true(result.err.contains("--flatten and --unflatten are inverses"))
  assert_false(result.err.contains("no such file"))
  assert_eq(analyzer.calls, 0)
}

///|
async test "--jsonl prints one record per line" {
  let scratch = Scratch::named("jsonl")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let result = run_on(
    scratch,
    "{\"a\":1}\n\n{\"b\":[2]}\n",
    ["--jsonl"],
    analyzer,
  )
  inspect(result.code, content="0")
  // Each record is formatted on its own, and the blank line between them is not
  // a record: it prints nothing.
  inspect(
    result.out,
    content="{\n  \"a\": 1\n}\n{\n  \"b\": [\n    2\n  ]\n}\n",
  )
  inspect(result.err, content="")
  assert_eq(analyzer.calls, 0)
}

///|
async test "--jsonl keeps going past a bad record and exits 1" {
  let scratch = Scratch::named("jsonl_bad")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let result = run_on(
    scratch,
    "{\"a\":1}\n{\"b\":}\n{\"c\":3}\n",
    ["--jsonl", "--compact"],
    analyzer,
  )
  inspect(result.code, content="1")
  // The records on either side are printed: one line of the file going wrong
  // does not cost the reader the others.
  inspect(result.out, content="{\"a\":1}\n{\"c\":3}\n")
  assert_true(result.err.contains(scratch.input + " is not valid JSON"))
  assert_true(result.err.contains("line 2"))
  assert_true(result.err.contains("{\"b\":}"))
  assert_eq(analyzer.calls, 0)
}

///|
/// `--fail-fast` inside one input: the records are handled in turn like the
/// files of a batch, so a bad record is where the reading stops. The record
/// after it is not printed, which is the whole difference from the run above.
async test "--jsonl --fail-fast stops at the record that failed" {
  let scratch = Scratch::named("jsonl_fast")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let result = run_on(
    scratch,
    "{\"a\":1}\n{\"b\":}\n{\"c\":3}\n",
    ["--jsonl", "--compact", "--fail-fast"],
    analyzer,
  )
  inspect(result.code, content="1")
  inspect(result.out, content="{\"a\":1}\n")
  assert_true(result.err.contains(scratch.input + " is not valid JSON"))
  assert_true(result.err.contains("line 2"))
  assert_eq(analyzer.calls, 0)
}

///|
async test "--jsonl reshapes every record on its own" {
  let scratch = Scratch::named("jsonl_flatten")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let result = run_on(
    scratch,
    "{\"a\":{\"b\":1}}\n{\"c\":{\"d\":2},\"c.d\":3}\n{\"e\":{\"f\":4}}\n",
    ["--jsonl", "--flatten", "--compact"],
    analyzer,
  )
  inspect(result.code, content="1")
  // A record that cannot be reshaped is reported and the records around it are
  // still printed, exactly as for one that does not parse.
  inspect(result.out, content="{\"a.b\":1}\n{\"e.f\":4}\n")
  assert_true(result.err.contains(scratch.input + " cannot be flattened"))
  assert_true(result.err.contains("conflicting keys: \"c\" and \"c.d\""))
  assert_eq(analyzer.calls, 0)
}

///|
async test "--jsonl is refused with the options that describe one document" {
  let analyzer = StubAnalyzer::new(Ok("unused"))
  // The file does not exist, which is the point: the command line is refused
  // before anything is opened.
  let result = run(
    ["-f", "no_such.jsonl", "--jsonl", "--ai"],
    analyze=analyzer.analyzer(),
  )
  inspect(result.code, content="2")
  inspect(result.out, content="")
  assert_true(result.err.contains("--ai describes a single document"))
  assert_true(result.err.contains("--jsonl reads many"))
  assert_false(result.err.contains("no such file"))
  assert_eq(analyzer.calls, 0)
}

///|
async test "--jsonl -v answers with the verdict instead of the records" {
  let scratch = Scratch::named("jsonl_validate")
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let result = run_on(
    scratch,
    "{\"a\":1}\n{\"b\":2}\n",
    ["--jsonl", "-v"],
    analyzer,
  )
  inspect(result.code, content="0")
  inspect(result.out, content=scratch.input + ": valid JSON\n")
  inspect(result.err, content="")
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
