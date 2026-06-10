// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

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
  let response1 = client.chat(messages, tools=tools)
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
    let response2 = client.chat(messages, tools=tools)
    @debug.debug(response2)
    match response2.content {
      Some(content) => @stdio.stdout.write(content + "\n")
      None => ()
    }
  } else {
    match response1.content {
      Some(content) => @stdio.stdout.write(content + "\n")
      None => ()
    }
  }

  ignore(provider.shutdown())
}
