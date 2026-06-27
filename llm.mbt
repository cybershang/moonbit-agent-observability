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
/// - `gen_ai.client.token.usage` metric for input/output tokens
/// - Conversation logs when `capture_content` is enabled
pub async fn Client::chat(
  self : Client,
  messages : Array[Message],
  tools? : Array[Tool] = [],
  parent_context? : @context.Context = @context.Context::empty(),
) -> LLMResponse {
  let tracer = @telemetry.tracer("cybershang/agent-observability/llm")
  let meter = @telemetry.meter("cybershang/agent-observability/llm")
  let input_messages = if self.capture_content {
    Some(messages_to_json_array(messages))
  } else {
    None
  }
  let (server_address, server_port) = parse_base_url(self.base_url)
  let span = @telemetry.start_chat_span(
    tracer,
    self.provider_name,
    self.model,
    self.max_tokens,
    input_messages~,
    server_address~,
    server_port~,
    parent_context~,
  )

  @telemetry.set_bool(span, "app.llm.capture_content", self.capture_content)

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

  // Log input conversation messages when content capture is enabled.
  if self.capture_content {
    for index, msg in messages {
      let content = msg.content.unwrap_or("")
      @telemetry.log_conversation_message(
        "cybershang/agent-observability/llm",
        msg.role,
        content,
        index~,
        trace_context=Some(span.span_context()),
      )
    }
  }

  // HTTP POST with error handling
  let start = @telemetry.now_seconds()
  let (response, resp_body) = @http.post(
    self.base_url + "/chat/completions",
    body_json,
    headers~,
  )
  let elapsed = @telemetry.now_seconds() - start
  @telemetry.record_llm_latency(
    meter,
    self.provider_name,
    self.model,
    seconds=elapsed,
  )

  guard response.code == 200 else {
    @telemetry.set_chat_http_error(span, response.code)
    @telemetry.log_error(
      "cybershang/agent-observability/llm",
      "LLM request failed with status \{response.code}",
      trace_context=Some(span.span_context()),
    )
    @telemetry.end_span_error(
      span,
      description="LLM request failed with status: \{response.code}",
    )
    return {
      content: Some("[LLM request failed with status \{response.code}]"),
      tool_calls: [],
      finish_reason: "stop",
      response_id: None,
      response_model: None,
    }
  }

  let data = resp_body.json()
  let llm_resp = parse_llm_response(data)
  @telemetry.set_int(
    span,
    "app.llm.tool_calls.count",
    llm_resp.tool_calls.length().to_int64(),
  )

  // Extract usage from response if available and record metrics.
  let usage = if data is { "usage": usage_obj, .. } {
    Some(usage_obj)
  } else {
    None
  }
  match usage {
    Some(u) => {
      @telemetry.set_chat_usage(span, u)
      if u is { "prompt_tokens": Number(pt, ..), .. } {
        @telemetry.record_llm_token_usage(
          meter,
          self.provider_name,
          self.model,
          "input",
          pt.to_int64(),
        )
      }
      if u is { "completion_tokens": Number(ct, ..), .. } {
        @telemetry.record_llm_token_usage(
          meter,
          self.provider_name,
          self.model,
          "output",
          ct.to_int64(),
        )
      }
    }
    None => ()
  }

  // Record response metadata and optional output messages.
  let output_messages = if self.capture_content {
    Some(output_messages_to_json_array(llm_resp))
  } else {
    None
  }
  @telemetry.set_chat_response(span, data, output_messages~)

  // Log output conversation messages when content capture is enabled.
  if self.capture_content {
    let output_json = output_messages_to_json_array(llm_resp)
    if output_json is Array(output_arr) {
      for index, out_msg in output_arr {
        let role = if out_msg is { "role": String(r), .. } {
          r
        } else {
          "assistant"
        }
        let content = if out_msg is { "content": String(c), .. } {
          c
        } else {
          ""
        }
        @telemetry.log_conversation_message(
          "cybershang/agent-observability/llm",
          role,
          content,
          index~,
          trace_context=Some(span.span_context()),
        )
      }
    }
  }

  @telemetry.end_span(span)

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

///|
/// Parse a base URL into server address and port for GenAI span attributes.
fn parse_base_url(base_url : String) -> (String?, Int?) {
  let mut rest = base_url
  if rest.has_prefix("http://") {
    rest = rest[7:].to_owned()
  } else if rest.has_prefix("https://") {
    rest = rest[8:].to_owned()
  }
  let host_port = match rest.split_once("/") {
    Some((host_port, _)) => host_port.to_owned()
    None => rest
  }
  match host_port.split_once(":") {
    Some((host, port_str)) => {
      let host = host.to_owned()
      let port = @string.parse_int(port_str) catch { _ => -1 }
      if port >= 0 {
        (Some(host), Some(port))
      } else {
        (Some(host_port), None)
      }
    }
    None => (Some(host_port), None)
  }
}
