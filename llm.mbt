// ============================================================================
// Types
// ============================================================================

///| A tool definition that can be registered with the LLM.
pub struct Tool {
  name : String
  description : String
  parameters : Json
} derive(Debug)

///| Create a new tool definition.
pub fn Tool::new(
  name~ : String,
  description~ : String,
  parameters~ : Json,
) -> Tool {
  { name, description, parameters }
}

///| A single message in the conversation history.
pub struct Message {
  role : String
  content : String?
  tool_calls : Array[ToolCall]?
  tool_call_id : String?
} derive(Debug)

///| Create a new message.
pub fn Message::new(
  role~ : String = "user",
  content~ : String? = None,
  tool_calls~ : Array[ToolCall]? = None,
  tool_call_id~ : String? = None,
) -> Message {
  { role, content, tool_calls, tool_call_id }
}

///| A tool call requested by the LLM.
pub struct ToolCall {
  id : String
  name : String
  arguments : String
} derive(Debug)

///| Result of a single LLM request.
pub struct LLMResponse {
  content : String?
  tool_calls : Array[ToolCall]
  finish_reason : String
} derive(Debug)

// ============================================================================
// Public API
// ============================================================================

///| Send a single request to the LLM with optional tools.
pub async fn llm_request(
  messages : Array[Message],
  api_key : String,
  tools~ : Array[Tool] = [],
  model_name~ : String = "step-3.7-flash",
  max_tokens~ : Int = 1024,
) -> LLMResponse {
  let body_json = build_request_json(messages, tools, model_name, max_tokens)
  let (response, resp_body) = @http.post(
    "https://api.stepfun.com/v1/chat/completions",
    body_json,
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

///| Convert a `Message` to JSON for the API request.
pub fn Message::to_json(self : Message) -> Json {
  let obj : Map[String, Json] = {}
  obj["role"] = self.role.to_json()
  match self.content {
    Some(c) => obj["content"] = c.to_json()
    None => obj["content"] = Json::null()
  }
  match self.tool_calls {
    Some(calls) => obj["tool_calls"] = calls.map(fn(c) { c.to_json() }).to_json()
    None => ()
  }
  match self.tool_call_id {
    Some(id) => obj["tool_call_id"] = id.to_json()
    None => ()
  }
  Json::object(obj)
}

///| Convert a `ToolCall` to JSON.
pub fn ToolCall::to_json(self : ToolCall) -> Json {
  let fn_obj : Map[String, Json] = {}
  fn_obj["name"] = self.name.to_json()
  fn_obj["arguments"] = self.arguments.to_json()
  let obj : Map[String, Json] = {}
  obj["id"] = self.id.to_json()
  obj["type"] = "function".to_json()
  obj["function"] = Json::object(fn_obj)
  Json::object(obj)
}

// ============================================================================
// Internal helpers
// ============================================================================

///| Build the request JSON body.
fn build_request_json(
  messages : Array[Message],
  tools : Array[Tool],
  model_name : String,
  max_tokens : Int,
) -> Json {
  let msg_json = messages.map(fn(m) { m.to_json() })
  let body : Map[String, Json] = {}
  body["model"] = model_name.to_json()
  body["messages"] = msg_json.to_json()
  body["max_tokens"] = max_tokens.to_json()
  if !tools.is_empty() {
    let tools_json = tools.map(fn(t) {
      let fn_obj : Map[String, Json] = {}
      fn_obj["name"] = t.name.to_json()
      fn_obj["description"] = t.description.to_json()
      fn_obj["parameters"] = t.parameters
      let obj : Map[String, Json] = {}
      obj["type"] = "function".to_json()
      obj["function"] = Json::object(fn_obj)
      Json::object(obj)
    })
    body["tools"] = tools_json.to_json()
  }
  Json::object(body)
}

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
    return { content: None, tool_calls: [], finish_reason: "" }
  }

  // Extract content
  let content = if message is { "content": String(c), .. } {
    Some(c)
  } else {
    None
  }

  // Extract tool_calls
  let tool_calls = if message is { "tool_calls": Array(calls), .. } {
    calls
    .filter_map(fn(call) {
      guard call is {
        "id": String(id),
        "function": { "name": String(name), "arguments": String(args), .. },
        ..
      } else {
        return None
      }
      Some({ id, name, arguments: args })
    })
  } else {
    []
  }

  { content, tool_calls, finish_reason }
}
