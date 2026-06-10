///|
async fn main {
  // Initialize OpenTelemetry SDK only when OTEL_STDOUT=true
  let otel_stdout = @env.get_env_var("OTEL_STDOUT").unwrap_or_else(fn() { "" })
  if otel_stdout.to_lower() == "true" {
    let exporter = @print.SpanExporter::new()
    let provider = @sdk.tracer_provider_builder()
      .with_simple_exporter(exporter.into_span_exporter())
      .build()
    @sdk.set_tracer_provider(provider)
  }

  // Step 8: REPL with continuous dialogue and auto tool-call loop
  let messages = []
  while true {
    @stdio.stdout.write("> ")
    let prompt = match @stdio.stdin.read_until("\n") {
      Some(line) => line.trim(char_set="\r\n").to_owned()
      None => break
    }
    if prompt == "exit" || prompt == "quit" {
      break
    }
    messages.push(@agent.Message::new(content=Some(prompt)))

    // LLM request loop: handle tool calls automatically
    let mut has_tool_calls = true
    while has_tool_calls {
      let response = @agent.llm_request(messages, tools=@agent.tools)
      if response.finish_reason == "tool_calls" {
        // Add assistant message with tool_calls
        messages.push(@agent.Message::new(
          role="assistant",
          tool_calls=Some(response.tool_calls),
        ))
        // Execute each tool call and add tool results
        for call in response.tool_calls {
          @stdio.stdout.write("\n[Tool Call] " + call.name + "(" + call.arguments + ")\n")
          let result = @agent.execute_tool(call.name, call.arguments)
          let display_result = if result.length() > 200 {
            result.substring(start=0, end=200) + "... (truncated)"
          } else {
            result
          }
          @stdio.stdout.write("[Tool Result] " + display_result + "\n")
          messages.push(@agent.Message::new(
            role="tool",
            content=Some(result),
            tool_call_id=Some(call.id),
          ))
        }
        // Continue loop to send tool results back to LLM
      } else {
        has_tool_calls = false
        match response.content {
          Some(content) => @stdio.stdout.write(content)
          None => ()
        }
      }
    }
    @stdio.stdout.write("\n")
  }
}

async test "Simple Http Request" {
  let (response, body) = @http.get("https://jsonplaceholder.typicode.com/todos/1")
  @debug.debug(response.code)
  let data = body.json()
  let number_opt = if data is { "id": Number(id, ..), .. } {
    Some(id)
  } else {
    None
  }
  @debug.debug(number_opt)
}

async test "LLM Request" {
  // Setup OTel with print exporter for test visibility
  let exporter = @print.SpanExporter::new()
  let provider = @sdk.tracer_provider_builder()
    .with_simple_exporter(exporter.into_span_exporter())
    .build()
  @sdk.set_tracer_provider(provider)

  let messages = [@agent.Message::new(content=Some("现在是几点？"))]
  let response = @agent.llm_request(messages)
  @debug.debug(response)

  ignore(provider.shutdown())
}

async test "LLM Tool Call" {
  // Setup OTel with print exporter for test visibility
  let exporter = @print.SpanExporter::new()
  let provider = @sdk.tracer_provider_builder()
    .with_simple_exporter(exporter.into_span_exporter())
    .build()
  @sdk.set_tracer_provider(provider)

  // Round 1: User asks about Beijing weather
  let messages = [@agent.Message::new(content=Some("北京今天天气怎么样？"))]
  let response1 = @agent.llm_request(messages, tools=@agent.tools)
  @debug.debug(response1)

  // If LLM requests tool calls, execute them and continue
  if response1.finish_reason == "tool_calls" {
    // Add assistant message with tool_calls
    let assistant_msg = @agent.Message::new(
      role="assistant",
      tool_calls=Some(response1.tool_calls),
    )
    messages.push(assistant_msg)

    // Execute each tool call and add tool results
    for call in response1.tool_calls {
      let result = @agent.execute_tool(call.name, call.arguments)
      let tool_msg = @agent.Message::new(
        role="tool",
        content=Some(result),
        tool_call_id=Some(call.id),
      )
      messages.push(tool_msg)
    }

    // Round 2: Send tool results back to LLM
    let response2 = @agent.llm_request(messages, tools=@agent.tools)
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
