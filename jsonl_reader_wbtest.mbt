///|
priv struct JsonlReadProbe {
  mut reads : Int
  mut releases : Int
}

///|
fn jsonl_byte_chunks(bytes : Bytes, size : Int) -> Array[Bytes] {
  let chunks = []
  for start = 0; start < bytes.length(); start = start + size {
    let end = if start + size < bytes.length() {
      start + size
    } else {
      bytes.length()
    }
    chunks.push(bytes[start:end].to_owned())
  }
  chunks
}

///|
fn jsonl_probe_input(
  chunks : Array[Bytes],
  fail_after? : Int? = None,
) -> (JsonlInput, JsonlReadProbe) {
  let probe = JsonlReadProbe::{ reads: 0, releases: 0, }
  let mut index = 0
  let input : JsonlInput = {
    read: block => {
      probe.reads = probe.reads + 1
      if fail_after is Some(after) && index >= after {
        raise Failure::Failure("injected JSONL read failure")
      }
      if index == chunks.length() {
        return 0
      }
      let chunk = chunks[index]
      for offset, byte in chunk {
        block[offset] = byte
      }
      index = index + 1
      chunk.length()
    },
    close: fn() { probe.releases = probe.releases + 1 },
  }
  (input, probe)
}

///|
async test "jsonl stream input: chunk boundaries and UTF-8 records" {
  let long_record = StringBuilder()
  long_record.write_string("\"中😀")
  for _ in 0..<9000 {
    long_record.write_string("x")
  }
  long_record.write_string("\"")
  let long_text = long_record.to_string()
  let text = "\r\n" + long_text + "\r\n \t\r\n1\ntrue\nfalse"
  let bytes = @utf8.encode(text)
  // One-byte reads split every multibyte codepoint; large reads contain many
  // records and still split the long record across the fixed-size blocks.
  for size in [1, 2, 7, 8192] {
    let (input, probe) = jsonl_probe_input(jsonl_byte_chunks(bytes, size))
    let lines = []
    let records = []
    visit_jsonl_input(input, None, fn(line, record) {
      lines.push(line)
      records.push(record_text(record))
      true
    })
    assert_eq(lines, [2, 4, 5, 6])
    assert_eq(records, [long_text, "1", "true", "false"])
    assert_eq(probe.releases, 1)
  }
  for bytes in [b"", b"\n \t\r\n", b"1\n", b"1"] {
    let (input, probe) = jsonl_probe_input(jsonl_byte_chunks(bytes, 2))
    let records = []
    visit_jsonl_input(input, None, fn(_line, record) {
      records.push(record_text(record))
      true
    })
    assert_eq(records, parse_jsonl(@utf8.decode(bytes)).map(record_text))
    assert_eq(probe.releases, 1)
  }
  let (input, _) = jsonl_probe_input([@utf8.encode("1\r2\u{2028}3\ntrue")])
  let outcomes = []
  visit_jsonl_input(input, None, fn(line, record) {
    outcomes.push((line, record is Ok(_)))
    true
  })
  assert_eq(outcomes, [(1, false), (2, true)])
}

///|
async test "jsonl stream input: diagnostics and text path compatibility" {
  let schema = "{\"properties\":{\"n\":{\"type\":\"integer\"},\"loop\":{\"$ref\":\"#/properties/loop\"}}}"
  for
    (text, extra, compiled) in [
      (
        "\r\n{\"😀\":1}\r\n \t\r\n{\"中\":}\r\n[[]]\r\n[]\r\n",
        ["--max-depth", "1"],
        None,
      ),
      ("\n{\"中\":1,\"中\":2}\r\n{}", [], None),
      ("\u{FEFF}{}\n\u{FEFF}{}\n", [], None),
      ("{\"a\":1,\"a.b\":2}\n{}", ["--unflatten"], None),
      (
        "{}\n{\"n\":\"bad\"}\n{\"loop\":1}\n{\n{}",
        ["--schema", "schema.json", "--schema-output", "text"],
        Some(ref_compiled(schema)),
      ),
    ] {
    let options = cli_ok(["-v", "--jsonl", "--no-color"] + extra)
    let expected = run_jsonl(options, compiled, "data.jsonl", text)
    let (input, probe) = jsonl_probe_input(
      jsonl_byte_chunks(@utf8.encode(text), 3),
    )
    let actual = run_jsonl_reader(options, compiled, Some("data.jsonl"), input)
    assert_eq(actual.code, expected.code)
    assert_eq(actual.out, expected.out)
    assert_eq(actual.err, expected.err)
    assert_eq(probe.releases, 1)
  }
  let (input, _) = jsonl_probe_input(
    jsonl_byte_chunks(
      @utf8.encode("\r\n{\"😀\":1}\r\n \t\r\n{\"中\":}\r\n[[]]\r\n[]\r\n"),
      1,
    ),
  )
  let diagnostics = []
  visit_jsonl_input(input, Some(1), fn(_line, record) {
    if record is Err(diagnostic) {
      diagnostics.push(diagnostic)
    }
    true
  })
  assert_eq(diagnostics.length(), 2)
  let syntax = diagnostics[0]
  assert_eq((syntax.line, syntax.column, syntax.offset), (4, 6, 20))
  assert_eq(syntax.snippet, "{\"中\":}\r")
  let depth = diagnostics[1]
  assert_eq((depth.line, depth.column, depth.offset), (5, 2, 24))
  assert_eq(depth.snippet, "[[]]\r")
  // Exercise real file dispatch too, including explicit text and an allowed
  // transform that must still run even when document output is suppressed.
  for extra in [["--schema-output", "text"], ["--unflatten"]] {
    let scratch = Scratch::named("stream_file_compat")
    let text = "{}\n{\"a\":1,\"a.b\":2}\n{\"n\":\"bad\"}\n{}"
    let options = cli_ok(
      ["-v", "--jsonl", "--schema", scratch.schema, "--no-color"] + extra,
    )
    let expected = run_jsonl(
      options,
      Some(ref_compiled(schema)),
      scratch.input,
      text,
    )
    let actual = run_against_schema(
      scratch,
      text,
      schema,
      ["--jsonl", "--no-color"] + extra,
      StubAnalyzer::new(Ok("unused")),
    )
    assert_eq(actual.code, expected.code)
    assert_eq(actual.out, expected.out)
    assert_eq(actual.err, expected.err)
  }
}

///|
async test "jsonl stream input: stop read failure and release" {
  let schema = ref_compiled(
    "{\"properties\":{\"loop\":{\"$ref\":\"#/properties/loop\"}}}",
  )
  for
    (chunks, fail_after, fast, expected_code, expected_reads, compiled) in [
      ([b"{}\n"], None, false, 0, 2, None),
      ([b"{\n\xff", b"{}\n"], None, true, 1, 1, None),
      ([b"{\n", b"{}\n"], Some(1), false, 1, 2, None),
      ([b"{"], Some(1), false, 1, 2, None),
      ([b"{\"loop\":1}\n"], Some(1), false, 2, 2, Some(schema)),
      ([b"{}\n", b"\xff\n"], None, false, 1, 2, None),
    ] {
    let extra = if fast { ["--fail-fast"] } else { [] }
    let options = cli_ok(["-v", "--jsonl", "--no-color"] + extra)
    let (input, probe) = jsonl_probe_input(chunks, fail_after~)
    let result = run_jsonl_reader(options, compiled, None, input)
    assert_eq(result.code, expected_code)
    assert_eq(probe.reads, expected_reads)
    assert_eq(probe.releases, 1)
    if expected_code != 0 {
      assert_eq(result.out, "")
      assert_false(result.err.contains("valid JSON, and every record"))
    }
    if fail_after != None {
      assert_true(result.err.contains("cannot read standard input:"))
      assert_true(result.err.contains("injected JSONL read failure"))
      if chunks[0] == b"{\n" {
        assert_true(result.err.contains("line 1, column "))
      }
      if expected_code == 2 {
        assert_true(result.err.contains("reference cycle"))
      }
      if chunks[0] == b"{" {
        assert_false(result.err.contains("is not valid JSON"))
      }
    }
  }
  // The same release boundary closes an actual file on EOF, early stop and
  // injected mid-read failure. A post-release read must fail in all three cases.
  let scratch = Scratch::named("stream_release")
  @fs.write_file(scratch.input, "{}\n{}\n")
  for mode in ["eof", "stop", "error"] {
    let file = @fs.open(scratch.input, mode=ReadOnly)
    let mut reads = 0
    let input : JsonlInput = {
      read: async fn(block) {
        reads = reads + 1
        if mode == "error" && reads == 2 {
          raise Failure::Failure("injected JSONL read failure")
        }
        @io.Reader::read(file, block, max_len=3)
      },
      close: fn() { file.close() },
    }
    let mut failed = false
    visit_jsonl_input(input, None, fn(_line, _record) { mode != "stop" }) catch {
      _ => failed = true
    }
    assert_eq(failed, mode == "error")
    let mut closed = false
    ignore(@io.Reader::read(file, FixedArray::make(1, b'\x00'))) catch {
      _ => closed = true
    }
    assert_true(closed)
  }
  discard(scratch.input)
}
