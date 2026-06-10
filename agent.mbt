// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

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
  }

  { reply: final_reply, tool_calls: executed }
}

///| Execute a tool by name with JSON arguments.
pub async fn execute_tool(name : String, arguments : String) -> String {
  match name {
    "get_weather" => get_weather(arguments)
    "execute_command" => execute_command_tool(arguments)
    _ => "{\"error\": \"Unknown tool: " + name + "\"}"
  }
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
