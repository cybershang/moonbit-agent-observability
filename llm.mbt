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
pub struct ToolCall {
  id : String
  name : String
  arguments : String
} derive(Debug)

///|
/// Result of a single LLM request.
pub struct LLMResponse {
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

///| OpenTelemetry tracer

///|
/// Lazily-initialized tracer for the LLMGateway module.
let llm_tracer : Ref[@trace.Tracer?] = Ref(None)

///|
/// Get or create the LLMGateway tracer.
fn get_llm_tracer() -> @trace.Tracer {
  match llm_tracer.val {
    Some(t) => t
    None => {
      let t = @otel.tracer(
        "yingjie/agent-observability/llm",
        version=Some("0.1.0"),
      )
      llm_tracer.val = Some(t)
      t
    }
  }
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
  let tracer = get_llm_tracer()
  let builder = tracer
    .span_builder("gen_ai.chat")
    .with_kind(@trace.Client)
    .with_attributes([
      @otel.KeyValue::new(@semtrace.GEN_AI_OPERATION_NAME, String("chat")),
      @otel.KeyValue::new("gen_ai.provider.name", String(self.provider_name)),
      @otel.KeyValue::new(@semtrace.GEN_AI_REQUEST_MODEL, String(self.model)),
      @otel.KeyValue::new(
        @semtrace.GEN_AI_REQUEST_MAX_TOKENS,
        Int64(self.max_tokens.to_int64()),
      ),
    ])
  let span = tracer.build_with_context(builder, parent_context)

  // Capture input messages as span attribute when enabled
  if self.capture_content {
    let input_messages = messages_to_json_array(messages)
    span.set_attribute(
      @otel.KeyValue::new(
        "gen_ai.input.messages",
        String(input_messages.stringify()),
      ),
    )
  }

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
    span.set_status(
      @trace.Status::error(description=Some("HTTP \{response.code}")),
    )
    span.add_event("llm.http_error", attributes=[
      @otel.KeyValue::new("http.status_code", Int64(response.code.to_int64())),
    ])
    span.end()
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
    Some(u) => {
      if u is { "prompt_tokens": Number(pt, ..), .. } {
        span.set_attribute(
          @otel.KeyValue::new(
            @semtrace.GEN_AI_USAGE_INPUT_TOKENS,
            Int64(pt.to_int64()),
          ),
        )
      }
      if u is { "completion_tokens": Number(ct, ..), .. } {
        span.set_attribute(
          @otel.KeyValue::new(
            @semtrace.GEN_AI_USAGE_OUTPUT_TOKENS,
            Int64(ct.to_int64()),
          ),
        )
      }
    }
    None => ()
  }

  // Record response metadata
  if llm_resp.finish_reason != "" {
    span.set_attribute(
      @otel.KeyValue::new(
        @semtrace.GEN_AI_RESPONSE_FINISH_REASONS,
        String(llm_resp.finish_reason),
      ),
    )
  }
  match llm_resp.response_id {
    Some(id) =>
      span.set_attribute(
        @otel.KeyValue::new(@semtrace.GEN_AI_RESPONSE_ID, String(id)),
      )
    None => ()
  }
  match llm_resp.response_model {
    Some(m) =>
      span.set_attribute(
        @otel.KeyValue::new(@semtrace.GEN_AI_RESPONSE_MODEL, String(m)),
      )
    None => ()
  }

  // Record output messages as span attribute when enabled
  if self.capture_content {
    let output_messages = output_messages_to_json_array(llm_resp)
    span.set_attribute(
      @otel.KeyValue::new(
        "gen_ai.output.messages",
        String(output_messages.stringify()),
      ),
    )
  }

  span.set_status(@trace.Status::ok())
  span.end()

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
