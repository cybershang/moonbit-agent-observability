// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///|
/// An agent that orchestrates LLM chat with tool calls.
///
/// The agent maintains conversation history and automatically executes
/// any tool calls requested by the LLM, feeding results back until a
/// final response is produced.
pub struct Agent {
  client : Client
  messages : Array[Message]
  tools : Array[Tool]
  max_tool_turns : Int
  capture_content : Bool
}

///|
/// Create a new agent with the given client and optional tools.
pub fn Agent::new(
  client : Client,
  tools? : Array[Tool] = [],
  max_tool_turns? : Int = 10,
  capture_content? : Bool = true,
) -> Agent {
  { client, messages: [], tools, max_tool_turns, capture_content }
}

///|
/// Record of a single tool call executed during an agent turn.
pub struct ToolCallRecord {
  call : ToolCall
  result : String
} derive(Debug)

///|
/// Result of a single agent turn, including the assistant's reply
/// and any tool calls that were executed.
pub struct AgentTurnResult {
  reply : String
  tool_calls : Array[ToolCallRecord]
} derive(Debug)

///|
/// Run one turn of conversation with the agent.
///
/// The prompt is appended to the conversation history, then the agent
/// loops over LLM responses and tool calls until a final text response
/// is received. Returns the assistant's reply and a record of any tool
/// calls executed during the turn.
pub async fn Agent::run(self : Agent, prompt : String) -> AgentTurnResult {
  let tracer = @telemetry.tracer("cybershang/agent-o11y-demo/agent")
  let meter = @telemetry.meter("cybershang/agent-o11y-demo/agent")
  let span_input = if self.capture_content { prompt } else { "" }
  let span = @telemetry.start_agent_turn_span(
    tracer,
    span_input,
    self.max_tool_turns,
  )
  // No async context storage by design — explicit is better than implicit.
  let parent_context = span.context()

  @telemetry.set_int(
    span,
    "app.agent.tool_count",
    self.tools.length().to_int64(),
  )
  @telemetry.set_int(span, "app.prompt.length", prompt.length().to_int64())

  self.messages.push(Message::new(content=Some(prompt)))

  let mut turn = 0
  let mut has_tool_calls = true
  let mut final_reply = ""
  let executed : Array[ToolCallRecord] = []
  while has_tool_calls && turn < self.max_tool_turns {
    turn = turn + 1
    let response = self.client.chat(
      self.messages,
      tools=self.tools,
      parent_context~,
    )
    if response.finish_reason == "tool_calls" {
      // Add assistant message with tool_calls
      self.messages.push(
        Message::new(role="assistant", tool_calls=Some(response.tool_calls)),
      )
      // Execute each tool call and add tool results
      for call in response.tool_calls {
        let result = execute_tool(call.name, call.arguments, parent_context~)
        executed.push({ call, result })
        self.messages.push(
          Message::new(
            role="tool",
            content=Some(result),
            tool_call_id=Some(call.id),
          ),
        )
      }
      // Continue loop to send tool results back to LLM
    } else {
      has_tool_calls = false
      final_reply = match response.content {
        Some(content) => content
        None => ""
      }
    }
  }

  // If we hit the turn limit without a final reply, report it
  if has_tool_calls {
    final_reply = "[Agent reached maximum tool-call turns without producing a final reply.]"
    @telemetry.set_turn_exhausted(span)
  }

  @telemetry.set_int(
    span,
    "app.response.length",
    final_reply.length().to_int64(),
  )
  @telemetry.set_bool(span, "app.agent.reached_max_turns", has_tool_calls)

  let span_output = if self.capture_content { final_reply } else { "" }
  @telemetry.set_turn(span, turn, executed.length(), span_output)
  @telemetry.record_turn(meter, max_tool_turns_reached=has_tool_calls)
  @telemetry.end_span(span)

  { reply: final_reply, tool_calls: executed }
}
