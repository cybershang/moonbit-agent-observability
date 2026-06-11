// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

// ============================================================================
// White-box Tests for llm.mbt - Tests private functions
// ============================================================================

///|
test "parse_llm_response - normal text response" {
  let data = @json.parse(
    "{\"id\":\"chat-123\",\"model\":\"step-3.7-flash\",\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"Hello!\"},\"finish_reason\":\"stop\"}]}",
  )
  let resp = parse_llm_response(data)
  debug_inspect(
    resp.content,
    content=(
      #|Some("Hello!")
    ),
  )
  debug_inspect(resp.tool_calls.length(), content="0")
  debug_inspect(
    resp.finish_reason,
    content=(
      #|"stop"
    ),
  )
  debug_inspect(
    resp.response_id,
    content=(
      #|Some("chat-123")
    ),
  )
  debug_inspect(
    resp.response_model,
    content=(
      #|Some("step-3.7-flash")
    ),
  )
}

///|
test "parse_llm_response - tool_calls response" {
  let data = @json.parse(
    "{\"id\":\"chat-456\",\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"{\\\"city\\\":\\\"Beijing\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}",
  )
  let resp = parse_llm_response(data)
  debug_inspect(resp.content, content="None")
  debug_inspect(
    resp.finish_reason,
    content=(
      #|"tool_calls"
    ),
  )
  debug_inspect(resp.tool_calls.length(), content="1")
  debug_inspect(
    resp.tool_calls[0].id,
    content=(
      #|"call_1"
    ),
  )
  debug_inspect(
    resp.tool_calls[0].name,
    content=(
      #|"get_weather"
    ),
  )
  debug_inspect(
    resp.tool_calls[0].arguments,
    content=(
      #|"{\"city\":\"Beijing\"}"
    ),
  )
}

///|
test "parse_llm_response - empty/invalid response" {
  let data = @json.parse("{}")
  let resp = parse_llm_response(data)
  debug_inspect(resp.content, content="None")
  debug_inspect(resp.tool_calls.length(), content="0")
  debug_inspect(
    resp.finish_reason,
    content=(
      #|""
    ),
  )
  debug_inspect(resp.response_id, content="None")
  debug_inspect(resp.response_model, content="None")
}

///|
test "parse_llm_response - missing choices array" {
  let data = @json.parse("{\"id\":\"test\",\"choices\":[]}")
  let resp = parse_llm_response(data)
  debug_inspect(
    resp.finish_reason,
    content=(
      #|""
    ),
  )
  debug_inspect(resp.content, content="None")
}

///|
test "parse_llm_response - multiple tool calls" {
  let data = @json.parse(
    "{\"choices\":[{\"message\":{\"tool_calls\":[{\"id\":\"c1\",\"function\":{\"name\":\"t1\",\"arguments\":\"{}\"}},{\"id\":\"c2\",\"function\":{\"name\":\"t2\",\"arguments\":\"{}\"}}]},\"finish_reason\":\"tool_calls\"}]}",
  )
  let resp = parse_llm_response(data)
  debug_inspect(resp.tool_calls.length(), content="2")
  debug_inspect(
    resp.tool_calls[0].id,
    content=(
      #|"c1"
    ),
  )
  debug_inspect(
    resp.tool_calls[1].id,
    content=(
      #|"c2"
    ),
  )
}

///|
test "parse_llm_response - malformed tool_call is skipped" {
  // Missing "function" field - should be filtered out
  let data = @json.parse(
    "{\"choices\":[{\"message\":{\"tool_calls\":[{\"id\":\"bad\",\"type\":\"function\"}]},\"finish_reason\":\"tool_calls\"}]}",
  )
  let resp = parse_llm_response(data)
  debug_inspect(resp.tool_calls.length(), content="0")
}

///|
test "build_request_json - basic request without tools" {
  let messages = [Message::new(content=Some("hi"))]
  let json = build_request_json(messages, [], "gpt-4", 1024)
  let s = json.stringify()
  assert_true(s.contains("\"model\":\"gpt-4\""))
  assert_true(s.contains("\"messages\""))
  assert_true(s.contains("\"max_tokens\":1024"))
  assert_false(s.contains("\"tools\""))
}

///|
test "build_request_json - request with tools" {
  let messages = [Message::new(content=Some("weather?"))]
  let tool = Tool::new(name="get_weather", description="weather", parameters={})
  let json = build_request_json(messages, [tool], "model-x", 512)
  let s = json.stringify()
  assert_true(s.contains("\"tools\""))
  assert_true(s.contains("\"get_weather\""))
  assert_true(s.contains("\"function\""))
}

///|
test "messages_to_json_array" {
  let messages = [
    Message::new(role="user", content=Some("hello")),
    Message::new(role="assistant", content=Some("hi there")),
  ]
  let json = messages_to_json_array(messages)
  let s = json.stringify()
  assert_true(s.contains("\"role\":\"user\""))
  assert_true(s.contains("\"role\":\"assistant\""))
  assert_true(s.contains("\"hello\""))
  assert_true(s.contains("\"hi there\""))
}

///|
test "output_messages_to_json_array - with content" {
  let resp : LLMResponse = {
    content: Some("answer"),
    tool_calls: [],
    finish_reason: "stop",
    response_id: None,
    response_model: None,
  }
  let json = output_messages_to_json_array(resp)
  let s = json.stringify()
  assert_true(s.contains("\"role\":\"assistant\""))
  assert_true(s.contains("\"answer\""))
}

///|
test "output_messages_to_json_array - with tool_calls" {
  let call : ToolCall = { id: "c1", name: "t1", arguments: "{}" }
  let resp : LLMResponse = {
    content: None,
    tool_calls: [call],
    finish_reason: "tool_calls",
    response_id: None,
    response_model: None,
  }
  let json = output_messages_to_json_array(resp)
  let s = json.stringify()
  assert_true(s.contains("\"tool_calls\""))
  assert_true(s.contains("\"c1\""))
}
