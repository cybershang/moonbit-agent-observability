// ============================================================================
// Types
// ============================================================================

///| A single message in the conversation history.
pub struct Message {
  role : String
  content : String?
} derive(Debug)

///| Create a new message.
pub fn Message::new(
  role~ : String = "user",
  content~ : String? = None,
) -> Message {
  { role, content }
}

///| Convert a `Message` to JSON for the API request.
pub fn Message::to_json(self : Message) -> Json {
  let obj : Map[String, Json] = {}
  obj["role"] = self.role.to_json()
  match self.content {
    Some(c) => obj["content"] = c.to_json()
    None => obj["content"] = Json::null()
  }
  Json::object(obj)
}

///| Result of a single LLM request.
pub struct LLMResponse {
  content : String?
  finish_reason : String
} derive(Debug)

// ============================================================================
// Public API
// ============================================================================

///| Send a single request to the LLM with a message history.
pub async fn llm_request(
  messages : Array[Message],
  api_key : String,
  model_name~ : String = "step-3.7-flash",
  max_tokens~ : Int = 1024,
) -> LLMResponse {
  let msg_json = messages.map(fn(m) { m.to_json() })
  let body : Map[String, Json] = {}
  body["model"] = model_name.to_json()
  body["messages"] = msg_json.to_json()
  body["max_tokens"] = max_tokens.to_json()
  let (response, resp_body) = @http.post(
    "https://api.stepfun.com/v1/chat/completions",
    Json::object(body),
    headers={
      "Content-Type": "application/json",
      "Authorization": "Bearer " + api_key,
    },
  )
  guard response.code == 200 else {
    abort("LLM request failed with status: \{response.code}")
  }
  parse_llm_response(resp_body.json())
}

// ============================================================================
// Internal helpers
// ============================================================================

///| Parse the LLM JSON response into `LLMResponse`.
fn parse_llm_response(data : Json) -> LLMResponse {
  guard data is {
    "choices": Array([
      {
        "message": message,
        "finish_reason": String(finish_reason),
        ..
      },
      ..
    ]),
    ..
  } else {
    return { content: None, finish_reason: "" }
  }

  let content = if message is { "content": String(c), .. } {
    Some(c)
  } else {
    None
  }

  { content, finish_reason }
}
