///|
/// Resolve one step of a path: an object member, or a decimal array index.
fn json_child(node : @pjson.Json, key : String) -> @pjson.Json? {
  match object_field(node, key) {
    Some(value) => Some(value)
    None =>
      match parse_decimal(key) {
        Some(index) => array_item(node, index)
        None => None
      }
  }
}

///|
/// Walk `keys` down through nested objects and arrays.
fn json_path(json : @pjson.Json, keys : Array[String]) -> @pjson.Json? {
  let mut current : @pjson.Json? = Some(json)
  for key in keys {
    current = current.bind(node => json_child(node, key))
  }
  current
}

///|
/// Parse `text`, failing the test when it is not valid JSON.
fn require_json(text : String) -> @pjson.Json {
  match @pjson.parse(text) {
    Ok(json) => json
    Err(_) => abort("expected valid JSON, got: " + text)
  }
}

///|
/// Read a nested string out of `text`, failing the test when it is absent.
fn require_text(text : String, keys : Array[String]) -> String {
  match json_path(require_json(text), keys).bind(text_value) {
    Some(value) => value
    None => abort("expected a string at the requested path")
  }
}

///|
/// A string of `length` copies of `ch`.
fn repeat_char(ch : Char, length : Int) -> String {
  let buf = StringBuilder()
  for _ in 0..<length {
    buf.write_char(ch)
  }
  buf.to_string()
}

///|
test "the request body is valid JSON that names the model" {
  let body = build_request_body("{\"a\":1}")
  assert_eq(require_text(body, ["model"]), deepseek_model)
  assert_eq(require_text(body, ["messages", "0", "role"]), "system")
  assert_eq(require_text(body, ["messages", "1", "role"]), "user")
}

///|
test "the request body is not streamed" {
  let parsed = require_json(build_request_body("{}"))
  match object_field(parsed, "stream") {
    Some(Bool(value~)) => assert_eq(value, false)
    _ => abort("expected a boolean stream field")
  }
}

///|
test "the user message embeds the document verbatim when it is small" {
  let document = "{\"a\":1}"
  let body = build_request_body(document)
  assert_true(
    require_text(body, ["messages", "1", "content"]).contains(document),
  )
}

///|
test "an oversized document is truncated before it is sent" {
  let huge = repeat_char('a', max_prompt_chars + 10)
  let truncated = truncate_for_prompt(huge)
  assert_true(truncated.contains("document truncated"))
  assert_true(truncated.char_length() <= max_prompt_chars)
}

///|
test "a document just over the limit is still brought back inside it" {
  let huge = repeat_char('a', max_prompt_chars + 1)
  assert_true(truncate_for_prompt(huge).char_length() <= max_prompt_chars)
}

///|
test "a document at the limit is left alone" {
  let exact = repeat_char('a', max_prompt_chars)
  assert_eq(truncate_for_prompt(exact), exact)
}

///|
test "awkward document text survives the round trip into the body" {
  let document = "{\"quote\":\"\\\"\",\"nl\":\"a\\nb\",\"slash\":\"a\\\\b\"}"
  let body = build_request_body(document)
  // Re-reading the body proves the escaping is correct rather than merely
  // well-intentioned: a broken escape would not parse back.
  assert_true(
    require_text(body, ["messages", "1", "content"]).contains(document),
  )
}

///|
test "the report is read from choices[0].message.content" {
  let response = "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"Looks fine.\"}}]}"
  assert_eq(extract_report(response), Ok("Looks fine."))
}

///|
test "an API error envelope is surfaced as a readable message" {
  let response = "{\"error\":{\"message\":\"Invalid API key\",\"type\":\"auth\"}}"
  assert_eq(
    extract_report(response),
    Err("the API reported an error: Invalid API key"),
  )
}

///|
test "a response that is not JSON is reported" {
  let result = extract_report("<html>gateway timeout</html>")
  match result {
    Ok(_) => abort("a non-JSON response should not be accepted")
    Err(message) =>
      assert_true(message.has_prefix("the API response was not valid JSON"))
  }
}

///|
test "a response without choices is reported" {
  assert_eq(
    extract_report("{}"),
    Err("the API response did not contain choices[0].message.content"),
  )
}

///|
test "a response with an empty choices array is reported" {
  assert_eq(
    extract_report("{\"choices\":[]}"),
    Err("the API response did not contain choices[0].message.content"),
  )
}

///|
test "a non-text message content is reported" {
  assert_eq(
    extract_report("{\"choices\":[{\"message\":{\"content\":42}}]}"),
    Err("the API returned a message whose content was not text"),
  )
}

///|
test "the API key is read from the documented environment variable" {
  assert_eq(api_key_variable, "DEEPSEEK_API_KEY")
}

///|
async test "analyze reports a missing API key instead of calling the API" {
  @env.unset_env_var(api_key_variable)
  match analyze("{\"a\":1}") {
    Ok(_) => abort("analyze should not succeed without an API key")
    Err(message) => {
      assert_true(message.contains(api_key_variable))
      assert_true(message.contains("not set"))
    }
  }
}

///|
async test "analyze reports an empty API key" {
  @env.set_env_var(api_key_variable, "")
  let result = analyze("{\"a\":1}")
  @env.unset_env_var(api_key_variable)
  match result {
    Ok(_) => abort("analyze should not succeed with an empty API key")
    Err(message) => assert_true(message.contains("is empty"))
  }
}
