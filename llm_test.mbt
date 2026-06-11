// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

// ============================================================================
// Black-box Unit Tests for llm.mbt - Public API only
// ============================================================================

///|
test "Tool::new creates tool with correct fields" {
  let tool = Tool::new(
    name="test_tool",
    description="A test tool",
    parameters={"type": "object"},
  )
  debug_inspect(tool.name, content=(
    #|"test_tool"
  ))
  debug_inspect(tool.description, content=(
    #|"A test tool"
  ))
}

///|
test "Message::new with defaults" {
  let msg = Message::new()
  debug_inspect(msg.role, content=(
    #|"user"
  ))
  debug_inspect(msg.content, content="None")
  debug_inspect(msg.tool_call_id, content="None")
}

///|
test "Message::new with all fields" {
  let msg = Message::new(
    role="assistant",
    content=Some("hello"),
    tool_call_id=Some("call_123"),
  )
  debug_inspect(msg.role, content=(
    #|"assistant"
  ))
  debug_inspect(msg.content, content=(
    #|Some("hello")
  ))
  debug_inspect(msg.tool_call_id, content=(
    #|Some("call_123")
  ))
}

///|
test "Message::to_json - user message with content" {
  let msg = Message::new(content=Some("hello world"))
  let json = msg.to_json()
  let s = json.stringify()
  assert_true(s.contains("\"role\":\"user\""))
  assert_true(s.contains("\"content\":\"hello world\""))
}

///|
test "Message::to_json - assistant message with tool_calls" {
  let call : ToolCall = { id: "call_1", name: "get_weather", arguments: "{\"city\":\"Beijing\"}" }
  let msg = Message::new(role="assistant", tool_calls=Some([call]))
  let json = msg.to_json()
  let s = json.stringify()
  assert_true(s.contains("\"role\":\"assistant\""))
  assert_true(s.contains("\"tool_calls\""))
  assert_true(s.contains("\"id\":\"call_1\""))
  assert_true(s.contains("\"name\":\"get_weather\""))
}

///|
test "Message::to_json - tool message with tool_call_id" {
  let msg = Message::new(role="tool", content=Some("sunny"), tool_call_id=Some("call_1"))
  let json = msg.to_json()
  let s = json.stringify()
  assert_true(s.contains("\"role\":\"tool\""))
  assert_true(s.contains("\"content\":\"sunny\""))
  assert_true(s.contains("\"tool_call_id\":\"call_1\""))
}

///|
test "Message::to_json - message with null content" {
  let msg = Message::new(role="assistant")
  let json = msg.to_json()
  let s = json.stringify()
  assert_true(s.contains("\"role\":\"assistant\""))
  assert_true(s.contains("\"content\":null"))
}

///|
test "ToolCall record construction" {
  let call : ToolCall = { id: "abc", name: "test", arguments: "{}" }
  debug_inspect(call.id, content=(
    #|"abc"
  ))
  debug_inspect(call.name, content=(
    #|"test"
  ))
  debug_inspect(call.arguments, content=(
    #|"{}"
  ))
}

///|
test "Client::new with defaults" {
  let client = Client::new(
    provider_name="stepfun",
    base_url="https://api.stepfun.com/v1",
    model="step-3.7-flash",
    api_key="test-key",
  )
  debug_inspect(client.provider_name, content=(
    #|"stepfun"
  ))
  debug_inspect(client.model, content=(
    #|"step-3.7-flash"
  ))
  debug_inspect(client.max_tokens, content="1024")
  debug_inspect(client.capture_content, content="false")
}

///|
test "Client::new with custom max_tokens and capture_content" {
  let client = Client::new(
    provider_name="openai",
    base_url="https://api.openai.com/v1",
    model="gpt-4",
    api_key="sk-test",
    max_tokens=2048,
    capture_content=true,
  )
  debug_inspect(client.max_tokens, content="2048")
  debug_inspect(client.capture_content, content="true")
}

///|
test "LLMResponse record construction" {
  let resp : LLMResponse = {
    content: Some("hello"),
    tool_calls: [],
    finish_reason: "stop",
    response_id: Some("id-1"),
    response_model: Some("model-x"),
  }
  debug_inspect(resp.content, content=(
    #|Some("hello")
  ))
  debug_inspect(resp.finish_reason, content=(
    #|"stop"
  ))
  debug_inspect(resp.tool_calls.length(), content="0")
}

// ============================================================================
// Integration Tests (require network & API key)
// ============================================================================

///|
async test "LLM Request" {
  // Setup OTel with print exporter for test visibility
  let exporter = @print.SpanExporter::new()
  let provider = @sdk.tracer_provider_builder()
    .with_simple_exporter(exporter.into_span_exporter())
    .build()
  @sdk.set_tracer_provider(provider)

  let api_key = read_dotenv("LLM_API_KEY").unwrap_or_else(fn() {
    @env.get_env_var("LLM_API_KEY").unwrap_or_else(fn() { "" })
  })
  let client = Client::new(
    provider_name="stepfun",
    base_url="https://api.stepfun.com/v1",
    model="step-3.7-flash",
    api_key~,
  )
  let messages = [Message::new(content=Some("现在是几点？"))]
  let response = client.chat(messages)
  @debug.debug(response)

  ignore(provider.shutdown())
}

///|
async test "LLM Tool Call" {
  // Setup OTel with print exporter for test visibility
  let exporter = @print.SpanExporter::new()
  let provider = @sdk.tracer_provider_builder()
    .with_simple_exporter(exporter.into_span_exporter())
    .build()
  @sdk.set_tracer_provider(provider)

  let api_key = read_dotenv("LLM_API_KEY").unwrap_or_else(fn() {
    @env.get_env_var("LLM_API_KEY").unwrap_or_else(fn() { "" })
  })
  let client = Client::new(
    provider_name="stepfun",
    base_url="https://api.stepfun.com/v1",
    model="step-3.7-flash",
    api_key~,
  )

  // Round 1: User asks about Beijing weather
  let messages = [Message::new(content=Some("北京今天天气怎么样？"))]
  let response1 = client.chat(messages, tools~)
  @debug.debug(response1)

  // If LLM requests tool calls, execute them and continue
  if response1.finish_reason == "tool_calls" {
    // Add assistant message with tool_calls
    let assistant_msg = Message::new(
      role="assistant",
      tool_calls=Some(response1.tool_calls),
    )
    messages.push(assistant_msg)

    // Execute each tool call and add tool results
    for call in response1.tool_calls {
      let result = execute_tool(call.name, call.arguments)
      let tool_msg = Message::new(
        role="tool",
        content=Some(result),
        tool_call_id=Some(call.id),
      )
      messages.push(tool_msg)
    }

    // Round 2: Send tool results back to LLM
    let response2 = client.chat(messages, tools~)
    @debug.debug(response2)
  } else {
    @debug.debug(response1)
  }

  ignore(provider.shutdown())
}
