///|
/// Environment variable holding the API key, read first.
pub let api_key_variable : String = "MOONJSON_AI_API_KEY"

///|
/// Environment variable holding the API key, read when the first is unset or
/// empty.
///
/// The tool is no longer DeepSeek-only, but a shell that already exports a
/// DeepSeek key should not have to be told that, so the old name keeps working
/// and only takes second place.
pub let fallback_api_key_variable : String = "DEEPSEEK_API_KEY"

///|
/// Environment variable naming the endpoint to post to.
pub let endpoint_variable : String = "MOONJSON_AI_BASE_URL"

///|
/// Environment variable naming the model to ask for.
pub let model_variable : String = "MOONJSON_AI_MODEL"

///|
/// The chat-completions endpoint used when nothing overrides it.
pub let deepseek_endpoint : String = "https://api.deepseek.com/chat/completions"

///|
/// The model used for the quality report when nothing overrides it.
pub let deepseek_model : String = "deepseek-flash"

///|
/// How long to wait for the API before giving up, in milliseconds.
pub let request_timeout_ms : Int = 60_000

///|
/// Documents larger than this are cut before being sent, so that one huge
/// input cannot turn into an enormous request.
pub let max_prompt_chars : Int = 20_000

///|
/// Read `name` from the environment, treating an empty value as absent.
///
/// An exported-but-empty variable is a shell that meant to configure something
/// and did not, and every caller here wants the fallback in that case rather
/// than an empty endpoint or an empty model name.
///
/// This is the only place any of the three settings is read from the process,
/// and the three resolvers below take what it returns as an argument rather
/// than calling it. That keeps the precedence — the whole of their behaviour —
/// a pure function of what they are handed, which is what lets it be tested
/// without writing to an environment every test in the file shares.
pub fn non_empty_env(name : String) -> String? {
  match @env.get_env_var(name) {
    Some(value) => if value == "" { None } else { Some(value) }
    None => None
  }
}

///|
/// The model a run should ask for: the one `--model` names, else the one the
/// environment names, else the default.
pub fn resolve_model(
  cli_model : String?,
  environment_model : String?,
) -> String {
  let chosen = match cli_model {
    Some(model) => Some(model)
    None => environment_model
  }
  match chosen {
    Some(model) => model
    None => deepseek_model
  }
}

///|
/// The endpoint a run should post to: the one `--ai-base-url` names, else the
/// one the environment names, else the default.
///
/// The URL is expected to be the whole endpoint rather than a base, because
/// that is the one spelling every OpenAI-compatible service documents and the
/// one that leaves nothing to guess: a base would have to have
/// `/chat/completions` appended to it, which is the path a service is most
/// likely to spell differently.
pub fn resolve_endpoint(cli_url : String?, environment_url : String?) -> String {
  let chosen = match cli_url {
    Some(url) => Some(url)
    None => environment_url
  }
  match chosen {
    Some(url) => url
    None => deepseek_endpoint
  }
}

///|
/// The API key a run should send: the newer variable when it holds something,
/// else the older one.
///
/// The two arguments are `MOONJSON_AI_API_KEY` and `DEEPSEEK_API_KEY` read
/// through `non_empty_env`, in that order. The failure names both variables,
/// because a reader who has exported neither needs to know which name to
/// export, and one who has exported the other needs to know why it was not
/// found.
pub fn resolve_api_key(
  newer : String?,
  older : String?,
) -> Result[String, String] {
  let chosen = match newer {
    Some(key) => Some(key)
    None => older
  }
  match chosen {
    Some(key) => Ok(key)
    None =>
      Err(
        api_key_variable +
        " or " +
        fallback_api_key_variable +
        " is not set; export a key to use --ai",
      )
  }
}

///|
/// The instruction that turns a chat model into a JSON reviewer.
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
/// Name the `to_json` method that `derive(ToJson)` provides.
///
/// The implicit promotion of an impl's methods to regular methods is deprecated
/// as of moon 0.1.20260920, and `--deny-warn` refuses it. Spelling the promotion
/// out changes nothing about the type or the JSON it produces: `derive` still
/// writes the method, and this says which one it is.
pub extend ChatMessage with ToJson::{to_json}

///|
/// The chat-completions request body.
struct ChatRequest {
  model : String
  messages : Array[ChatMessage]
  stream : Bool
} derive(ToJson)

///|
/// As for `ChatMessage`: the promotion `derive(ToJson)` makes, spelled out.
pub extend ChatRequest with ToJson::{to_json}

///|
/// Build the chat-completions request body for `json_text`.
///
/// The body is serialised from a typed record so that the document reaches the
/// API escaped correctly, however unusual its strings are. The model is
/// labelled because it and the document are both strings, and a call that
/// swapped the two would build a request that no API would accept and no
/// type-checker would refuse.
fn build_request_body(json_text : String, model~ : String) -> String {
  let request : ChatRequest = {
    model,
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
/// Ask the configured API for a quality report and refactoring suggestions for
/// the formatted `json_text`.
///
/// Everything the call needs is handed in, so this function reads no
/// environment and holds no opinion about who is answering: `endpoint` is
/// posted to as given, `model` is the name the request asks for, and `api_key`
/// goes into the `Authorization` header. The three come from `resolve_model`,
/// `resolve_endpoint` and `resolve_api_key`, which the runner calls — the key
/// is still never taken from a file or an argument, so it cannot leak through
/// shell history or a process listing.
///
/// The key is expected to be non-empty, which is what the resolver guarantees;
/// an empty one would be sent as a bare `Bearer` and rejected by the service
/// with a less useful message than the resolver's.
pub async fn analyze(
  json_text : String,
  endpoint : String,
  model : String,
  api_key : String,
) -> Result[String, String] {
  let body = build_request_body(json_text, model~)
  let response = @async.with_timeout(request_timeout_ms, async fn() {
    let headers : Map[String, String] = {
      "Content-Type": "application/json",
      "Authorization": "Bearer " + api_key,
    }
    @mio.post(endpoint, body, headers~).text()
  }) catch {
    error =>
      // The endpoint is named in the failure because a request that never
      // arrived is most often a request sent to the wrong place, and which
      // place is exactly what the reader cannot see from here.
      return Err(
        "could not reach " + endpoint + ": " + describe_io_error(error),
      )
  }
  extract_report(response)
}
