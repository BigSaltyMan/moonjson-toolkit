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
/// Where `marker` first appears in `text`, failing the test when it does not
/// appear at all.
///
/// Ordering is what these tests are about, and a test that asserted on the
/// whole page would be asserting the printer's own mind rather than the order
/// the printer wrote in.
fn offset_of(text : String, marker : String) -> Int {
  match text.find(marker) {
    Some(at) => at
    None => abort("the output does not mention " + marker + ":\n" + text)
  }
}

///|
/// A batch reads its inputs at once, and what comes back is still one answer per
/// input in the order the inputs were named.
///
/// The three reviews are held at a barrier until all three have been asked for,
/// which is a gate a run that handled the files one after another could never
/// pass: the first call would sit waiting for a call that the waiting is itself
/// what stands in the way of. The timeout turns that into a failure with
/// something to read instead of a test that never ends.
///
/// The first input is then the slowest of the three by a wide margin, so the
/// answers are ready in an order that is not the order they were asked for.
/// Printing each one as it arrived would put the second file first, which is the
/// mistake the ordering below is looking for.
async test "a batch reads several inputs at once and answers them in order" {
  let first = Scratch::named("parallel_first")
  let second = Scratch::named("parallel_second")
  let third = Scratch::named("parallel_third")
  @fs.write_file(first.input, "{\"one\":1}")
  @fs.write_file(second.input, "{\"two\":2}")
  @fs.write_file(third.input, "{\"three\":3}")
  @env.set_env_var(api_key_variable, stub_api_key)
  let arrived : @ref.Ref[Int] = @ref.new(0)
  let result = try
    @async.with_timeout(4000, async fn() {
      run(["-f", first.input, "-f", second.input, "-f", third.input, "--ai"], analyze=async fn(
        document,
        _endpoint,
        _model,
        _api_key,
      ) {
        // Nothing below is reached until the other two have arrived, so a run
        // that is not reading all three at once stops here and is timed out.
        arrived.val = arrived.val + 1
        while arrived.val < 3 {
          @async.sleep(1)
        }
        if document.contains("\"one\"") {
          // The slow one, and the first one named, so the answers finish in
          // the opposite order to the one they are printed in.
          @async.sleep(200)
          return Ok("REVIEW-ONE")
        }
        if document.contains("\"two\"") {
          return Ok("REVIEW-TWO")
        }
        Ok("REVIEW-THREE")
      })
    })
  catch {
    err => abort("the three inputs were not read at once: " + err.to_string())
  } noraise {
    result => result
  }
  discard(first.input)
  discard(second.input)
  discard(third.input)
  inspect(result.code, content="0")
  inspect(result.err, content="")
  // Each document, then its own review, then the next document: the answers are
  // back in the order the inputs were named even though they were not ready in
  // that order, and no review has been filed under another input's name.
  let first_document = offset_of(result.out, "==> " + first.input + " <==")
  let first_review = offset_of(result.out, "REVIEW-ONE")
  let second_document = offset_of(result.out, "==> " + second.input + " <==")
  let second_review = offset_of(result.out, "REVIEW-TWO")
  let third_document = offset_of(result.out, "==> " + third.input + " <==")
  let third_review = offset_of(result.out, "REVIEW-THREE")
  assert_true(first_document < first_review)
  assert_true(first_review < second_document)
  assert_true(second_document < second_review)
  assert_true(second_review < third_document)
  assert_true(third_document < third_review)
}

///|
/// `--fail-fast` cancels the inputs that are still being read rather than
/// waiting for them: a run that stops at the first failure gives up the inputs
/// behind it where they stand, which is the difference between a run that ends
/// early and one that only stops printing early.
///
/// The second input's review is asked for and does not answer for far longer
/// than the timeout, so the run can only finish in time by taking it away. The
/// first input's own failure is held back long enough for the second to be under
/// way — which is asserted on, since a run that never started the second input
/// would be easy to mistake for one that cancelled it.
async test "--fail-fast cancels the inputs that are still being read" {
  let failing = Scratch::named("cancelled_failing")
  let parked = Scratch::named("cancelled_parked")
  @fs.write_file(failing.input, "{\"fails\":1}")
  @fs.write_file(parked.input, "{\"parks\":2}")
  @env.set_env_var(api_key_variable, stub_api_key)
  let parked_calls : @ref.Ref[Int] = @ref.new(0)
  let result = try
    @async.with_timeout(4000, async fn() {
      run(["-f", failing.input, "-f", parked.input, "--ai", "--fail-fast"], analyze=async fn(
        document,
        _endpoint,
        _model,
        _api_key,
      ) {
        if document.contains("\"fails\"") {
          // The failure the run stops at, held back until the other input has
          // had time to reach its own review.
          @async.sleep(200)
          return Err("the review could not be asked for")
        }
        parked_calls.val = parked_calls.val + 1
        // Far beyond the timeout: only being cancelled ends this.
        @async.sleep(30000)
        Ok("never printed")
      })
    })
  catch {
    err =>
      abort(
        "the input that failed did not take the one behind it with it: " +
        err.to_string(),
      )
  } noraise {
    result => result
  }
  discard(failing.input)
  discard(parked.input)
  inspect(result.code, content="3")
  // Neither input prints a document: one failed, and the other was taken away
  // while it was still being read.
  inspect(result.out, content="")
  assert_true(result.err.contains("the review could not be asked for"))
  assert_eq(parked_calls.val, 1)
}

///|
/// More inputs than the run reads at once: the ones that have to wait for a turn
/// are not dropped and not reordered, they are read after the ones in front of
/// them, and the answer still names every input the command line did.
async test "a batch longer than the window answers every input in order" {
  let paths : Array[String] = []
  for index in 0..<6 {
    paths.push(Scratch::named("window_" + index.to_string()).input)
  }
  for index, path in paths {
    @fs.write_file(path, "{\"n\":" + index.to_string() + "}")
  }
  let args : Array[String] = ["-c"]
  for path in paths {
    args.push("-f")
    args.push(path)
  }
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let result = run(args, analyze=analyzer.analyzer())
  for path in paths {
    discard(path)
  }
  let expected = StringBuilder()
  for index, path in paths {
    expected.write_string(
      "==> " + path + " <==\n{\"n\":" + index.to_string() + "}\n",
    )
  }
  inspect(result.code, content="0")
  inspect(result.out, content=expected.to_string())
  inspect(result.err, content="")
  assert_eq(analyzer.calls, 0)
}

///|
/// `--fail-fast` over more inputs than the window: the inputs that are waiting
/// for a turn when the failure arrives are not started at all, so nothing the
/// run does after the failure is work the reader will never see.
///
/// Six inputs and a window of four means two of them are still queued when the
/// task that fails is done, which is the only shape in which the waiting can be
/// given up on rather than cancelled.
async test "--fail-fast starts no input after the one that failed" {
  let paths : Array[String] = []
  for index in 0..<6 {
    paths.push(Scratch::named("stopped_" + index.to_string()).input)
  }
  for index, path in paths {
    // The second one is the failure; nothing else about it matters.
    let text = if index == 1 {
      "{\"bad\":,}"
    } else {
      "{\"n\":" + index.to_string() + "}"
    }
    @fs.write_file(path, text)
  }
  let args : Array[String] = ["--fail-fast"]
  for path in paths {
    args.push("-f")
    args.push(path)
  }
  let analyzer = StubAnalyzer::new(Ok("unused"))
  let result = run(args, analyze=analyzer.analyzer())
  for path in paths {
    discard(path)
  }
  inspect(result.code, content="1")
  // The first input was in hand when the second failed, and the four behind it
  // were only ever waiting: one document, then the failure and nothing else.
  inspect(result.out, content="==> " + paths[0] + " <==\n{\n  \"n\": 0\n}\n")
  assert_true(result.err.contains(paths[1] + " is not valid JSON"))
  for index in 2..<6 {
    assert_false(result.out.contains("==> " + paths[index] + " <=="))
  }
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
