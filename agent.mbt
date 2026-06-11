// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///| OpenTelemetry tracer for the Agent module.
let agent_tracer : Ref[@trace.Tracer?] = Ref(None)

///| Get or create the Agent tracer.
fn get_agent_tracer() -> @trace.Tracer {
  match agent_tracer.val {
    Some(t) => t
    None => {
      let t = @otel.tracer("yingjie/agent-observability/agent", version=Some("0.1.0"))
      agent_tracer.val = Some(t)
      t
    }
  }
}

///| An agent that orchestrates LLM chat with tool calls.
///
/// The agent maintains conversation history and automatically executes
/// any tool calls requested by the LLM, feeding results back until a
/// final response is produced.
pub struct Agent {
  client : Client
  messages : Array[Message]
  tools : Array[Tool]
  max_tool_turns : Int
}

///| Create a new agent with the given client and optional tools.
pub fn Agent::new(
  client : Client,
  tools~ : Array[Tool] = [],
  max_tool_turns~ : Int = 10,
) -> Agent {
  { client, messages: [], tools, max_tool_turns }
}

///| Record of a single tool call executed during an agent turn.
pub struct ToolCallRecord {
  call : ToolCall
  result : String
} derive(Debug)

///| Result of a single agent turn, including the assistant's reply
/// and any tool calls that were executed.
pub struct AgentTurnResult {
  reply : String
  tool_calls : Array[ToolCallRecord]
} derive(Debug)

///| Run one turn of conversation with the agent.
///
/// The prompt is appended to the conversation history, then the agent
/// loops over LLM responses and tool calls until a final text response
/// is received. Returns the assistant's reply and a record of any tool
/// calls executed during the turn.
pub async fn Agent::run(self : Agent, prompt : String) -> AgentTurnResult {
  let tracer = get_agent_tracer()
  let builder = tracer
    .span_builder("agent.turn")
    .with_kind(@trace.Internal)
    .with_attributes([
      @otel.KeyValue::new("agent.turn.input", String(prompt)),
      @otel.KeyValue::new("agent.turn.max_tool_turns", Int64(self.max_tool_turns.to_int64())),
    ])
  let span = tracer.build(builder)

  self.messages.push(Message::new(content=Some(prompt)))

  let mut turn = 0
  let mut has_tool_calls = true
  let mut final_reply = ""
  let executed : Array[ToolCallRecord] = []
  while has_tool_calls && turn < self.max_tool_turns {
    turn = turn + 1
    let response = self.client.chat(self.messages, tools=self.tools)
    if response.finish_reason == "tool_calls" {
      // Add assistant message with tool_calls
      self.messages.push(Message::new(
        role="assistant",
        tool_calls=Some(response.tool_calls),
      ))
      // Execute each tool call and add tool results
      for call in response.tool_calls {
        let result = execute_tool(call.name, call.arguments)
        executed.push({ call, result })
        self.messages.push(Message::new(
          role="tool",
          content=Some(result),
          tool_call_id=Some(call.id),
        ))
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
    span.set_status(@trace.Status::error(description=Some("max_tool_turns_reached")))
  } else {
    span.set_status(@trace.Status::ok())
  }

  span.set_attribute(
    @otel.KeyValue::new("agent.turn.actual_turns", Int64(turn.to_int64())),
  )
  span.set_attribute(
    @otel.KeyValue::new("agent.turn.tool_call_count", Int64(executed.length().to_int64())),
  )
  span.set_attribute(
    @otel.KeyValue::new("agent.turn.output", String(final_reply)),
  )
  span.end()

  { reply: final_reply, tool_calls: executed }
}

///| Execute a tool by name with JSON arguments.
pub async fn execute_tool(name : String, arguments : String) -> String {
  let tracer = get_agent_tracer()
  let builder = tracer
    .span_builder("gen_ai.tool.execution")
    .with_kind(@trace.Internal)
    .with_attributes([
      @otel.KeyValue::new("gen_ai.tool.name", String(name)),
      @otel.KeyValue::new("gen_ai.tool.call.arguments", String(arguments)),
    ])
  let span = tracer.build(builder)

  let result = match name {
    "get_weather" => get_weather(arguments)
    "execute_command" => execute_command_tool(arguments)
    _ => {
      span.set_status(@trace.Status::error(description=Some("Unknown tool: " + name)))
      "{\"error\": \"Unknown tool: " + name + "\"}"
    }
  }

  // Record whether the result indicates an error
  if result.contains("\"error\"") {
    span.set_status(@trace.Status::error(description=Some("tool returned error")))
  } else {
    span.set_status(@trace.Status::ok())
  }
  span.set_attribute(@otel.KeyValue::new("gen_ai.tool.call.result", String(result)))
  span.end()

  result
}

///| Mock weather tool: always returns sunny 25°C.
fn get_weather(args : String) -> String {
  ignore(args)
  "{\"temperature\": 25, \"condition\": \"晴\"}"
}

///| Execute a shell command and return stdout as string.
async fn execute_command_tool(args_json : String) -> String {
  let args = try {
    @json.parse(args_json)
  } catch {
    _ => return "{\"error\": \"Invalid JSON arguments\"}"
  }
  let command = if args is { "command": String(cmd), .. } {
    cmd
  } else {
    return "{\"error\": \"Missing 'command' field\"}"
  }
  // Security: reject dangerous commands
  let forbidden = ["rm", "mv", "cp", "dd", "mkfs", "fdisk", "format", "del", "rd", "rmdir"]
  let cmd_lower = command.trim().to_lower()
  for bad in forbidden {
    if cmd_lower.has_prefix(bad + " ") || cmd_lower == bad {
      return "{\"error\": \"Forbidden command: " + bad + "\"}"
    }
  }
  // Run command and collect output
  let (code, stdout, _stderr) = @process.collect_output("sh", ["-c", command])
  let output = stdout.text()
  "{\"exit_code\": " + code.to_string() + ", \"output\": \"" + escape_json(output) + "\"}"
}

///| Escape special characters in a JSON string value.
fn escape_json(s : String) -> String {
  let sb = StringBuilder::new()
  for ch in s {
    match ch {
      '\\' => sb.write_string("\\\\")
      '"' => sb.write_string("\\\"")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      _ => sb.write_char(ch)
    }
  }
  sb.to_string()
}
