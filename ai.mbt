///|
/// Environment variable holding the DeepSeek API key.
pub let api_key_variable : String = "DEEPSEEK_API_KEY"

///|
/// DeepSeek's chat-completions endpoint.
pub let deepseek_endpoint : String = "https://api.deepseek.com/v1/chat/completions"

///|
/// The model used for the quality report.
pub let deepseek_model : String = "deepseek-chat"

///|
/// How long to wait for DeepSeek before giving up, in milliseconds.
pub let request_timeout_ms : Int = 60_000

///|
/// Documents larger than this are cut before being sent, so that one huge
/// input cannot turn into an enormous request.
pub let max_prompt_chars : Int = 20_000

///|
/// The instruction that turns DeepSeek into a JSON reviewer.
fn system_prompt() -> String {
  [
    "You are a JSON quality reviewer embedded in a command-line tool.", "Reply in plain text without markdown fences.",
    "Cover, in this order: structural problems, naming and consistency,", "redundancy, and concrete refactoring suggestions.",
    "Be specific and concise: at most 200 words.",
  ].join(" ")
}

///|
/// The marker appended to a document that had to be cut.
let truncation_note : String = "\n... (document truncated for review)"

///|
/// Shorten `text` so a single oversized document cannot dominate the request.
///
/// The note counts against the budget, so the result never exceeds
/// `max_prompt_chars` even when the input is only marginally over it.
fn truncate_for_prompt(text : String) -> String {
  let chars = text.to_array()
  if chars.length() <= max_prompt_chars {
    text
  } else {
    let keep = max_prompt_chars - truncation_note.char_length()
    String::from_array(chars[0:keep]) + truncation_note
  }
}

///|
/// One turn of the chat-completions conversation.
struct ChatMessage {
  role : String
  content : String
} derive(ToJson)

///|
/// The chat-completions request body.
struct ChatRequest {
  model : String
  messages : Array[ChatMessage]
  stream : Bool
} derive(ToJson)

///|
/// Build the chat-completions request body for `json_text`.
///
/// The body is serialised from a typed record so that the document reaches the
/// API escaped correctly, however unusual its strings are.
fn build_request_body(json_text : String) -> String {
  let request : ChatRequest = {
    model: deepseek_model,
    messages: [
      { role: "system", content: system_prompt(), },
      {
        role: "user",
        content: "Review this JSON document:\n\n" +
        truncate_for_prompt(json_text),
      },
    ],
    stream: false,
  }
  @json.to_json(request).stringify()
}

///|
/// Read `key` from an object node.
fn object_field(json : @pjson.Json, key : String) -> @pjson.Json? {
  match json {
    Object(members~) => {
      let mut found = None
      for entry in members {
        let (name, value) = entry
        if name == key {
          found = Some(value)
        }
      }
      found
    }
    _ => None
  }
}

///|
/// Read `index` from an array node.
fn array_item(json : @pjson.Json, index : Int) -> @pjson.Json? {
  match json {
    Array(items~) =>
      if index >= 0 && index < items.length() {
        Some(items[index])
      } else {
        None
      }
    _ => None
  }
}

///|
/// Read a node that is expected to be a JSON string.
fn text_value(json : @pjson.Json) -> String? {
  match json {
    Text(value~) => Some(value)
    _ => None
  }
}

///|
/// Pull the report out of a chat-completions response.
///
/// Both the success shape (`choices[0].message.content`) and the error shape
/// (`error.message`) are understood, so a rejected request still produces a
/// message worth showing to the user.
fn extract_report(response : String) -> Result[String, String] {
  let parsed = match @pjson.parse(response) {
    Ok(json) => json
    Err(error) =>
      return Err(
        "the API response was not valid JSON: " + describe_json_error(error),
      )
  }
  let failure = object_field(parsed, "error")
    .bind(node => object_field(node, "message"))
    .bind(text_value)
  if failure is Some(message) {
    return Err("the API reported an error: " + message)
  }
  let content = object_field(parsed, "choices")
    .bind(choices => array_item(choices, 0))
    .bind(choice => object_field(choice, "message"))
    .bind(message => object_field(message, "content"))
  match content {
    None => Err("the API response did not contain choices[0].message.content")
    Some(node) =>
      match text_value(node) {
        Some(text) => Ok(text)
        None => Err("the API returned a message whose content was not text")
      }
  }
}

///|
/// Ask DeepSeek for a quality report and refactoring suggestions for the
/// formatted `json_text`.
///
/// The API key is read from the environment and never taken from a file or an
/// argument, so it cannot leak through shell history or a process listing.
pub async fn analyze(json_text : String) -> Result[String, String] {
  let api_key = match @env.get_env_var(api_key_variable) {
    Some(key) =>
      if key == "" {
        return Err(api_key_variable + " is empty; export a key to use --ai")
      } else {
        key
      }
    None =>
      return Err(api_key_variable + " is not set; export a key to use --ai")
  }
  let body = build_request_body(json_text)
  let response = @async.with_timeout(request_timeout_ms, async fn() {
    let headers : Map[String, String] = {
      "Content-Type": "application/json",
      "Authorization": "Bearer " + api_key,
    }
    @mio.post(deepseek_endpoint, body, headers~).text()
  }) catch {
    error =>
      return Err(
        "could not reach the DeepSeek API: " + describe_io_error(error),
      )
  }
  extract_report(response)
}
