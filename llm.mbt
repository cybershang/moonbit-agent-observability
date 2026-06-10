// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

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
// Content capture toggle (controlled by CAPTURE_CONTENT env var)
// ============================================================================

///| Check whether content capture is enabled via environment variable.
/// Reads CAPTURE_CONTENT from env only (not .env file) to avoid async issues.
fn is_capture_content_enabled() -> Bool {
  let from_env = @env.get_env_var("CAPTURE_CONTENT").unwrap_or_else(fn() { "" })
  from_env.to_lower() == "true"
}

// ============================================================================
// OpenTelemetry Tracer (lazy-init so library code works before SDK setup)
// ============================================================================

///| Lazily-initialized tracer for the LLMGateway module.
let llm_tracer : Ref[@trace.Tracer?] = Ref::new(None)

///| Get or create the LLMGateway tracer.
fn get_llm_tracer() -> @trace.Tracer {
  match llm_tracer.val {
    Some(t) => t
    None => {
      let t = @otel.tracer("yingjie/agent-observability/llm", version=Some("0.1.0"))
      llm_tracer.val = Some(t)
      t
    }
  }
}

// ============================================================================
// Public API
// ============================================================================

///| Send a single request to the LLM with optional tools.
///
/// This function is instrumented with OpenTelemetry GenAI semantic conventions:
/// - Span name: `gen_ai.chat`
/// - `gen_ai.system` = "stepfun"
/// - `gen_ai.operation.name` = "chat"
/// - `gen_ai.request.model` = model_name
/// - `gen_ai.request.max_tokens` = max_tokens
/// - `gen_ai.usage.input_tokens` (from response)
/// - `gen_ai.usage.output_tokens` (from response)
/// - `gen_ai.response.finish_reasons` (from response)
pub async fn llm_request(
  messages : Array[Message],
  tools~ : Array[Tool] = [],
  model_name~ : String = "step-3.7-flash",
  max_tokens~ : Int = 1024,
) -> LLMResponse {
  let capture_content = is_capture_content_enabled()
  let tracer = get_llm_tracer()
  let builder = tracer
    .span_builder("gen_ai.chat")
    .with_kind(@trace.Client)
    .with_attributes([
      @otel.KeyValue::new(@semtrace.GEN_AI_SYSTEM, String("stepfun")),
      @otel.KeyValue::new(@semtrace.GEN_AI_OPERATION_NAME, String("chat")),
      @otel.KeyValue::new(@semtrace.GEN_AI_REQUEST_MODEL, String(model_name)),
      @otel.KeyValue::new(@semtrace.GEN_AI_REQUEST_MAX_TOKENS, Int64(max_tokens.to_int64())),
    ])
  let span = tracer.build(builder)

  // Record tool count if tools are present
  if !tools.is_empty() {
    span.set_attribute(
      @otel.KeyValue::new("gen_ai.request.tool_count", Int64(tools.length().to_int64())),
    )
  }

  // Capture user messages as events when enabled
  if capture_content {
    for i = 0; i < messages.length(); i = i + 1 {
      let msg = messages[i]
      if msg.role == "user" {
        match msg.content {
          Some(text) => span.add_event("gen_ai.user.message", attributes=[
            @otel.KeyValue::new("message.index", Int64(i.to_int64())),
            @otel.KeyValue::new("message.content", String(text)),
          ])
          None => ()
        }
      }
    }
  }

  let api_key = read_dotenv("STEPFUN_API_KEY").unwrap_or_else(fn() {
    @env.get_env_var("STEPFUN_API_KEY").unwrap_or_else(fn() { "" })
  })
  let body_json = build_request_json(messages, tools, model_name, max_tokens)
  let headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer " + api_key,
  }

  // HTTP POST with error handling
  let (response, resp_body) = @http.post(
    "https://api.stepfun.com/v1/chat/completions",
    body_json,
    headers~,
  )

  guard response.code == 200 else {
    span.set_status(@trace.Status::error(description=Some("HTTP \{response.code}")))
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
          @otel.KeyValue::new(@semtrace.GEN_AI_USAGE_INPUT_TOKENS, Int64(pt.to_int64())),
        )
      }
      if u is { "completion_tokens": Number(ct, ..), .. } {
        span.set_attribute(
          @otel.KeyValue::new(@semtrace.GEN_AI_USAGE_OUTPUT_TOKENS, Int64(ct.to_int64())),
        )
      }
    }
    None => ()
  }

  // Record finish reason
  if llm_resp.finish_reason != "" {
    span.set_attribute(
      @otel.KeyValue::new(@semtrace.GEN_AI_RESPONSE_FINISH_REASONS, String(llm_resp.finish_reason)),
    )
  }

  // Record tool calls as events
  if !llm_resp.tool_calls.is_empty() {
    for call in llm_resp.tool_calls {
      span.add_event("gen_ai.tool.call", attributes=[
        @otel.KeyValue::new(@semtrace.GEN_AI_TOOL_CALL_ID, String(call.id)),
        @otel.KeyValue::new(@semtrace.GEN_AI_TOOL_NAME, String(call.name)),
      ])
    }
  }

  // Capture assistant response content when enabled
  if capture_content {
    match llm_resp.content {
      Some(text) => span.add_event("gen_ai.assistant.message", attributes=[
        @otel.KeyValue::new("message.content", String(text)),
      ])
      None => ()
    }
  }

  span.set_status(@trace.Status::ok())
  span.end()

  llm_resp
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

///| Read a `.env` file and look up a key.
async fn read_dotenv(key : String) -> String? {
  let content = try {
    (@fs.read_file(".env").text() : String)
  } catch {
    _ => return None
  }
  for line in content.split("\n") {
    let trimmed = line.trim(char_set="\r ")
    if trimmed.is_empty() || trimmed.has_prefix("#") {
      continue
    }
    match trimmed.split_once("=") {
      Some((k, v)) => if k == key { return Some(v.to_owned()) }
      None => continue
    }
  }
  None
}
