// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///| Types

///|
/// A tool definition that can be registered with the LLM.
pub struct Tool {
  name : String
  description : String
  parameters : Json
} derive(Debug)

///|
/// Create a new tool definition.
pub fn Tool::new(
  name~ : String,
  description~ : String,
  parameters~ : Json,
) -> Tool {
  { name, description, parameters }
}

///|
/// A single message in the conversation history.
pub struct Message {
  role : String
  content : String?
  tool_calls : Array[ToolCall]?
  tool_call_id : String?
} derive(Debug)

///|
/// Create a new message.
pub fn Message::new(
  role? : String = "user",
  content? : String? = None,
  tool_calls? : Array[ToolCall]? = None,
  tool_call_id? : String? = None,
) -> Message {
  { role, content, tool_calls, tool_call_id }
}

///|
/// A tool call requested by the LLM.
pub(all) struct ToolCall {
  id : String
  name : String
  arguments : String
} derive(Debug)

///|
/// Result of a single LLM request.
pub(all) struct LLMResponse {
  content : String?
  tool_calls : Array[ToolCall]
  finish_reason : String
  response_id : String?
  response_model : String?
} derive(Debug)

///|
/// A client for a GenAI provider.
pub struct Client {
  provider_name : String
  base_url : String
  model : String
  api_key : String
  max_tokens : Int
  capture_content : Bool
}

///|
/// Create a new GenAI client.
pub fn Client::new(
  provider_name~ : String,
  base_url~ : String,
  model~ : String,
  api_key~ : String,
  max_tokens? : Int = 1024,
  capture_content? : Bool = false,
) -> Client {
  { provider_name, base_url, model, api_key, max_tokens, capture_content }
}

///|
/// Create a client from a loaded `Settings` value.
pub fn Client::from_settings(settings : Settings) -> Client {
  Client::new(
    provider_name=settings.provider_name,
    base_url=settings.base_url,
    model=settings.model,
    api_key=settings.api_key,
    max_tokens=settings.max_tokens,
    capture_content=settings.capture_content,
  )
}

///| Public API

///|
/// Send a chat request to the configured GenAI provider.
///
/// This method is instrumented with OpenTelemetry GenAI semantic conventions:
/// - Span name: `gen_ai.chat`
/// - `gen_ai.operation.name` = "chat"
/// - `gen_ai.provider.name` = provider_name
/// - `gen_ai.request.model` = model
/// - `gen_ai.request.max_tokens` = max_tokens
/// - `gen_ai.usage.input_tokens` (from response)
/// - `gen_ai.usage.output_tokens` (from response)
/// - `gen_ai.response.id` (from response)
/// - `gen_ai.response.model` (from response)
/// - `gen_ai.response.finish_reasons` (from response)
/// - `gen_ai.input.messages` and `gen_ai.output.messages` when `capture_content` is enabled
pub async fn Client::chat(
  self : Client,
  messages : Array[Message],
  tools? : Array[Tool] = [],
  parent_context? : @context.Context = @context.Context::empty(),
) -> LLMResponse {
  let tracer = @telemetry.tracer("cybershang/agent-observability/llm")
  let input_messages = if self.capture_content {
    Some(messages_to_json_array(messages))
  } else {
    None
  }
  let span = @telemetry.start_chat_span(
    tracer,
    self.provider_name,
    self.model,
    self.max_tokens,
    input_messages~,
    parent_context~,
  )

  let body_json = build_request_json(
    messages,
    tools,
    self.model,
    self.max_tokens,
  )
  let headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer " + self.api_key,
  }

  // HTTP POST with error handling
  let (response, resp_body) = @http.post(
    self.base_url + "/chat/completions",
    body_json,
    headers~,
  )

  guard response.code == 200 else {
    @telemetry.set_chat_http_error(span, response.code)
    @telemetry.end_span(span)
    abort("LLM request failed with status: \{response.code}")
  }

  let data = resp_body.json()
  let llm_resp = parse_llm_response(data)

  // Extract usage from response if available
  let usage = if data is { "usage": usage_obj, .. } {
    Some(usage_obj)
  } else {
    None
  }
  match usage {
    Some(u) => @telemetry.record_chat_usage(span, u)
    None => ()
  }

  // Record response metadata and optional output messages
  let output_messages = if self.capture_content {
    Some(output_messages_to_json_array(llm_resp))
  } else {
    None
  }
  @telemetry.record_chat_response(span, data, output_messages~)

  @telemetry.end_span_ok(span)

  llm_resp
}

///|
/// Convert a `Message` to JSON for the API request.
pub fn Message::to_json(self : Message) -> Json {
  let obj : Map[String, Json] = {}
  obj["role"] = self.role.to_json()
  match self.content {
    Some(c) => obj["content"] = c.to_json()
    None => obj["content"] = Json::null()
  }
  match self.tool_calls {
    Some(calls) =>
      obj["tool_calls"] = calls.map(fn(c) { c.to_json() }).to_json()
    None => ()
  }
  match self.tool_call_id {
    Some(id) => obj["tool_call_id"] = id.to_json()
    None => ()
  }
  Json::object(obj)
}

///|
/// Convert a `ToolCall` to JSON.
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

///| Internal helpers

///|
/// Build the request JSON body.
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

///|
/// Parse the LLM JSON response into `LLMResponse`.
fn parse_llm_response(data : Json) -> LLMResponse {
  guard data
    is {
      "choices": Array(
        [{ "message": message, "finish_reason": String(finish_reason), .. }, ..]
      ),
      ..
    } else {
    return {
      content: None,
      tool_calls: [],
      finish_reason: "",
      response_id: None,
      response_model: None,
    }
  }

  // Extract content
  let content = if message is { "content": String(c), .. } {
    Some(c)
  } else {
    None
  }

  // Extract tool_calls
  let tool_calls = if message is { "tool_calls": Array(calls), .. } {
    calls.filter_map(fn(call) {
      guard call
        is {
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

  // Extract response-level metadata
  let response_id = if data is { "id": String(id), .. } {
    Some(id)
  } else {
    None
  }
  let response_model = if data is { "model": String(m), .. } {
    Some(m)
  } else {
    None
  }

  { content, tool_calls, finish_reason, response_id, response_model }
}

///|
/// Convert conversation messages to the GenAI input.messages JSON schema.
///
/// Schema: [{ "role": string, "content": string }]
fn messages_to_json_array(messages : Array[Message]) -> Json {
  let arr = messages.map(fn(msg) {
    let obj : Map[String, Json] = {}
    obj["role"] = msg.role.to_json()
    match msg.content {
      Some(text) => obj["content"] = text.to_json()
      None => obj["content"] = Json::null()
    }
    Json::object(obj)
  })
  arr.to_json()
}

///|
/// Convert an LLM response to the GenAI output.messages JSON schema.
///
/// Schema: [{ "role": "assistant", "content": string?, "tool_calls": [...]? }]
fn output_messages_to_json_array(response : LLMResponse) -> Json {
  let obj : Map[String, Json] = {}
  obj["role"] = "assistant".to_json()
  match response.content {
    Some(text) => obj["content"] = text.to_json()
    None => obj["content"] = Json::null()
  }
  if !response.tool_calls.is_empty() {
    obj["tool_calls"] = response.tool_calls.map(fn(c) { c.to_json() }).to_json()
  }
  [Json::object(obj)].to_json()
}
