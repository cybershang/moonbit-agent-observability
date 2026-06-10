///|
async fn main {
  // Step 6: Tool call loop with get_weather
  let api_key = "YOUR_API_KEY"
  let messages : Array[@agent.Message] = []

  messages.push(@agent.Message::new(content=Some("北京今天天气怎么样？")))
  let response1 = @agent.llm_request(messages, api_key, tools=@agent.tools)
  @debug.debug(response1)

  if response1.finish_reason == "tool_calls" {
    // Add assistant message with tool_calls
    messages.push(@agent.Message::new(
      role="assistant",
      tool_calls=Some(response1.tool_calls),
    ))
    // Execute each tool call and add tool results
    for call in response1.tool_calls {
      let result = @agent.execute_tool(call.name, call.arguments)
      messages.push(@agent.Message::new(
        role="tool",
        content=Some(result),
        tool_call_id=Some(call.id),
      ))
    }
    // Round 2: send tool results back to LLM
    let response2 = @agent.llm_request(messages, api_key, tools=@agent.tools)
    @debug.debug(response2)
    match response2.content {
      Some(content) => @stdio.stdout.write(content)
      None => ()
    }
  } else {
    match response1.content {
      Some(content) => @stdio.stdout.write(content)
      None => ()
    }
  }
}
