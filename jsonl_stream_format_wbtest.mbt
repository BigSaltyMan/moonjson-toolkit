///|
/// The previous buffered entry is kept only as a whitebox compatibility helper.
/// Existing reader tests also use it to compare source diagnostics.
fn run_jsonl(
  options : CliOptions,
  schema : CompiledSchema?,
  source : String,
  text : String,
) -> RunResult {
  let state = JsonlTextRun::new(options, schema, source)
  visit_jsonl_records(text, options.max_depth, fn(line, record) {
    state.consume(line, record)
  })
  state.finish()
}

///|
async test "jsonl stream format: formatting transforms and file dispatch" {
  let text = "\r\n{\"z\":9007199254740993,\"n\":1e500,\"name\":\"  中文😀  \",\"a\":1.00}\r\n \t\r\n[1e-400,-0,1e500]"
  let compact = "{\"z\":9007199254740993,\"n\":1e500,\"name\":\"  中文😀  \",\"a\":1.00}\n[1e-400,-0,1e500]\n"
  for
    (extra, expected_text) in [
      (
        [],
        "{\n  \"z\": 9007199254740993,\n  \"n\": 1e500,\n  \"name\": \"  中文😀  \",\n  \"a\": 1.00\n}\n[\n  1e-400,\n  -0,\n  1e500\n]\n",
      ),
      (["--compact"], compact),
      (
        ["--compact", "--sort-keys", "--trim-strings"],
        "{\"a\":1.00,\"n\":1e500,\"name\":\"中文😀\",\"z\":9007199254740993}\n[1e-400,-0,1e500]\n",
      ),
    ] {
    let options = cli_ok(["--jsonl", "--no-color"] + extra)
    let expected = run_jsonl(options, None, "data.jsonl", text)
    assert_eq(expected.out, expected_text)
    let (reader, probe) = jsonl_probe_input(
      jsonl_byte_chunks(@utf8.encode(text), 3),
    )
    let result = run_jsonl_reader(options, None, Some("data.jsonl"), reader)
    assert_eq(result.code, 0)
    assert_eq(result.out, expected.out)
    assert_eq(result.err, "")
    assert_eq(probe.releases, 1)
    let file = run_on(
      Scratch::named("stream_format"),
      text,
      ["--jsonl", "--no-color"] + extra,
      StubAnalyzer::new(Ok("unused")),
    )
    assert_eq(file.code, 0)
    assert_eq(file.out, expected_text)
    assert_eq(file.err, "")
  }
  let scratch = Scratch::named("stream_format_batch")
  @fs.write_file(scratch.stats, "{\"last\":true}")
  let batch = run_on(
    scratch,
    text,
    ["--jsonl", "--compact", "--no-color", "-f", scratch.stats],
    StubAnalyzer::new(Ok("unused")),
  )
  discard(scratch.stats)
  assert_eq(batch.code, 0)
  assert_eq(batch.err, "")
  assert_eq(
    batch.out,
    "==> " +
    scratch.input +
    " <==\n" +
    compact +
    "==> " +
    scratch.stats +
    " <==\n{\"last\":true}\n",
  )
}

///|
async test "jsonl stream format: recovery and fail-fast stop reading" {
  for fast in [false, true] {
    let extra = if fast { ["--fail-fast"] } else { [] }
    let options = cli_ok(["--jsonl", "--compact", "--no-color"] + extra)
    let (reader, probe) = jsonl_probe_input([
      b"{\"a\":1}\n\n",
      @utf8.encode("{\"中\":}\r\n"),
      b"{\"b\":2}\n",
    ])
    let result = run_jsonl_reader(options, None, None, reader)
    assert_eq(result.code, 1)
    assert_eq(
      result.out,
      if fast {
        "{\"a\":1}\n"
      } else {
        "{\"a\":1}\n{\"b\":2}\n"
      },
    )
    assert_true(result.err.has_prefix("error: <stdin> is not valid JSON\n"))
    assert_true(result.err.contains("line 3, column 6:"))
    assert_eq(probe.reads, if fast { 2 } else { 4 })
    assert_eq(probe.releases, 1)
  }
  for
    (text, extra, fragment) in [
      (
        "\n[[0]]\n1",
        ["--max-depth", "1"],
        "line 2, column 2: nesting depth exceeds limit 1",
      ),
      ("\n{\"中\":1,\"中\":2}\r\n1", [], "first defined at line 2, column 2"),
    ] {
    let options = cli_ok(["--jsonl", "--compact", "--no-color"] + extra)
    let (reader, _) = jsonl_probe_input(
      jsonl_byte_chunks(@utf8.encode(text), 2),
    )
    let result = run_jsonl_reader(options, None, None, reader)
    assert_eq(result.code, 1)
    assert_eq(result.out, "1\n")
    assert_true(result.err.contains(fragment))
  }
}

///|
async test "jsonl stream format: read failures preserve output and release" {
  for
    (chunks, fail_after, fast, code, reads, expected_out) in [
      ([b"{\"a\":1}\n"], None, false, 0, 2, "{\"a\":1}\n"),
      ([b"{\"a\":1}\n{\n", b"unused"], None, true, 1, 1, "{\"a\":1}\n"),
      ([b"{\"a\":1}\n{\n", b"{\"tail\":"], Some(2), false, 1, 3, "{\"a\":1}\n"),
    ] {
    let extra = if fast { ["--fail-fast"] } else { [] }
    let options = cli_ok(["--jsonl", "--compact", "--no-color"] + extra)
    let (reader, probe) = jsonl_probe_input(chunks, fail_after~)
    let result = run_jsonl_reader(options, None, Some("data.jsonl"), reader)
    assert_eq(result.code, code)
    assert_eq(result.out, expected_out)
    assert_eq(probe.reads, reads)
    assert_eq(probe.releases, 1)
    if code == 0 {
      assert_eq(result.err, "")
    } else {
      assert_true(result.err.contains("line 2, column "))
    }
    if fail_after != None {
      assert_true(result.err.contains("cannot read data.jsonl:"))
      assert_true(result.err.contains("injected JSONL read failure"))
      assert_false(result.err.contains("line 3, column"))
    }
  }
}
