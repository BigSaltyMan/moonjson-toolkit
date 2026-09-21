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
test "the request body is valid JSON that names the model it was given" {
  let body = build_request_body("{\"a\":1}", model="a-model-of-my-own")
  assert_eq(require_text(body, ["model"]), "a-model-of-my-own")
  assert_eq(require_text(body, ["messages", "0", "role"]), "system")
  assert_eq(require_text(body, ["messages", "1", "role"]), "user")
}

///|
test "the request body is not streamed" {
  let parsed = require_json(build_request_body("{}", model=deepseek_model))
  match object_field(parsed, "stream") {
    Some(Bool(value~)) => assert_eq(value, false)
    _ => abort("expected a boolean stream field")
  }
}

///|
test "the user message embeds the document verbatim when it is small" {
  let document = "{\"a\":1}"
  let body = build_request_body(document, model=deepseek_model)
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
  let body = build_request_body(document, model=deepseek_model)
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
/// The four variable names are the contract with the outside world: everything
/// below them decides precedence among values already in hand, so the names are
/// the only part of the resolution a test cannot state in the abstract.
test "the configuration variables are named" {
  assert_eq(api_key_variable, "MOONJSON_AI_API_KEY")
  assert_eq(fallback_api_key_variable, "DEEPSEEK_API_KEY")
  assert_eq(model_variable, "MOONJSON_AI_MODEL")
  assert_eq(endpoint_variable, "MOONJSON_AI_BASE_URL")
}

///|
/// The three tests for each setting are the same three: what a run was told
/// wins over what the shell was set up with, which wins over the default. They
/// are written against `None` for "the environment says nothing" rather than
/// against an unset variable, so they neither read nor write the environment
/// and cannot disagree with each other when `moon test` runs them at once.
test "the model named on the command line wins over the environment" {
  assert_eq(
    resolve_model(Some("from-the-command-line"), Some("from-the-environment")),
    "from-the-command-line",
  )
}

///|
test "the environment names the model when the command line does not" {
  assert_eq(
    resolve_model(None, Some("from-the-environment")),
    "from-the-environment",
  )
}

///|
test "the default model is used when nothing names one" {
  assert_eq(resolve_model(None, None), deepseek_model)
}

///|
test "the endpoint named on the command line wins over the environment" {
  assert_eq(
    resolve_endpoint(
      Some("http://from-the-command-line/v1/chat/completions"),
      Some("http://from-the-environment/v1/chat/completions"),
    ),
    "http://from-the-command-line/v1/chat/completions",
  )
}

///|
test "the environment names the endpoint when the command line does not" {
  assert_eq(
    resolve_endpoint(
      None,
      Some("http://from-the-environment/v1/chat/completions"),
    ),
    "http://from-the-environment/v1/chat/completions",
  )
}

///|
test "the default endpoint is used when nothing names one" {
  assert_eq(resolve_endpoint(None, None), deepseek_endpoint)
}

///|
test "the newer API key variable is read first" {
  assert_eq(resolve_api_key(Some("sk-new"), Some("sk-old")), Ok("sk-new"))
}

///|
/// The old name is neither an error nor a last resort: a shell that already
/// exports a DeepSeek key goes on working without being told to rename
/// anything. An empty variable reads as absent rather than as a key, which is
/// the difference between this and the version that refused an empty key
/// outright.
test "an unusable newer key falls back to the older variable" {
  assert_eq(resolve_api_key(None, Some("sk-old")), Ok("sk-old"))
  // An exported-but-blank variable reads as absent, which is the one thing the
  // pure functions cannot be asked: they are handed `None`, and this is what
  // produces it. The name is used by no other test, so setting it here cannot
  // change what any of them sees.
  let scratch : String = "MOONJSON_AI_UNUSED_BY_ANYTHING"
  @env.unset_env_var(scratch)
  assert_eq(non_empty_env(scratch), None)
  @env.set_env_var(scratch, "")
  let blank = non_empty_env(scratch)
  @env.unset_env_var(scratch)
  assert_eq(blank, None)
}

///|
test "a missing API key names both variables" {
  assert_eq(
    resolve_api_key(None, None),
    Err(
      "MOONJSON_AI_API_KEY or DEEPSEEK_API_KEY is not set; export a key to use --ai",
    ),
  )
}
