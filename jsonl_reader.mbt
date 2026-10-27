///|
/// An owned file or borrowed stdin. The no-op stdin release leaves it open.
priv struct JsonlInput {
  read : async (FixedArray[Byte]) -> Int
  close : () -> Unit
}

///|
async fn open_jsonl_input(input : String?) -> JsonlInput {
  match input {
    Some(path) => {
      let file = @fs.open(path, mode=ReadOnly)
      {
        read: block => @io.Reader::read(file, block),
        close: fn() { file.close() },
      }
    }
    None =>
      {
        read: block => @io.Reader::read(@stdio.stdin, block),
        close: fn() { () },
      }
  }
}

///|
/// Decode only complete records, preserving strict UTF-8 and the input's BOM
/// policy. The byte buffer grows with the longest record, not the whole input.
fn consume_jsonl_bytes(
  bytes : Bytes,
  line : Int,
  base : Int,
  max_depth : Int?,
  consume : (Int, Result[@pjson.Json, JsonDiagnostic]) -> Bool,
) -> (Bool, Int) raise {
  let text = @utf8.decode(bytes)
  let more = if text.trim().is_empty() {
    true
  } else {
    consume(line, parse_stream_record(text, line, base, max_depth))
  }
  (more, count_chars(text))
}

///|
/// LF alone delimits records. No read is started after a callback stops us,
/// and release runs on EOF, early return, decoding/I/O failure or cancellation.
async fn visit_jsonl_input(
  input : JsonlInput,
  max_depth : Int?,
  consume : (Int, Result[@pjson.Json, JsonDiagnostic]) -> Bool,
) -> Unit {
  defer (input.close)()
  let block = FixedArray::make(8192, b'\x00')
  let pending = @buffer.Buffer()
  let mut line = 1
  let mut base = 0
  while true {
    let size = (input.read)(block)
    if size == 0 {
      if !pending.is_empty() {
        ignore(
          consume_jsonl_bytes(
            pending.to_bytes(),
            line,
            base,
            max_depth,
            consume,
          ),
        )
      }
      return
    }
    let bytes = block.unsafe_reinterpret_as_bytes()
    let mut start = 0
    for index = 0; index < size; index = index + 1 {
      if bytes[index] == b'\n' {
        pending.write_bytes(bytes[start:index])
        let (more, chars) = consume_jsonl_bytes(
          pending.to_bytes(),
          line,
          base,
          max_depth,
          consume,
        )
        pending.reset()
        if !more {
          return
        }
        base = base + chars + 1
        line = line + 1
        start = index + 1
      }
    }
    pending.write_bytes(bytes[start:size])
  }
}

///|
/// Reuse the ordinary parser/diagnostic, rebasing locations without retaining
/// or rereading earlier lines. Duplicate-key messages also name the global line.
fn parse_stream_record(
  record : String,
  line : Int,
  base : Int,
  max_depth : Int?,
) -> Result[@pjson.Json, JsonDiagnostic] {
  match parse_raw(record, max_depth) {
    Ok(json) => Ok(json)
    Err(error) => {
      let diagnostic = JsonDiagnostic::from_error(record, error)
      let message = match error {
        DuplicateKey(first_offset~, ..) => {
          let (first_line, column) = offset_to_line_col(record, first_offset)
          describe_json_error(error) +
          first_defined_location(line + first_line - 1, column)
        }
        _ => diagnostic.message
      }
      Err({
        offset: base + diagnostic.offset,
        line: line + diagnostic.line - 1,
        column: diagnostic.column,
        snippet: diagnostic.snippet,
        message,
      })
    }
  }
}
