///|
async fn main {
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
          let result = @agent.execute_tool(call.name, call.arguments)
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
