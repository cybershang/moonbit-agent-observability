// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///| Tool registry

///|
/// A tool handler takes a JSON arguments string and returns a result string.
pub type ToolHandler = async (String) -> String

///|
/// A tool definition bundled with its runtime handler.
pub struct RegisteredTool {
  tool : Tool
  handler : ToolHandler
}

///|
/// Single source of truth for all available tools.
let registered_tools : Array[RegisteredTool] = [
  {
    tool: Tool::new(
      name="get_weather",
      description="Get the current weather for a specified city.",
      parameters={
        "type": "object",
        "properties": {
          "city": { "type": "string", "description": "City name" },
        },
        "required": ["city"],
      },
    ),
    handler: fn(args : String) -> String { get_weather(args) },
  },
  {
    tool: Tool::new(
      name="execute_command",
      description="Execute a command in the system shell and return stdout. Only safe read-only commands (e.g. ls, cat, echo, pwd) are allowed; commands that modify the system (e.g. rm, mv, cp, write) are forbidden.",
      parameters={
        "type": "object",
        "properties": {
          "command": {
            "type": "string",
            "description": "The shell command to execute (e.g. ls -la)",
          },
        },
        "required": ["command"],
      },
    ),
    handler: execute_command_tool,
  },
]

///|
/// Tool definitions exposed to the LLM.
pub let tools : Array[Tool] = registered_tools.map(fn(r) { r.tool })

///|
/// Registry mapping tool names to their handlers.
let tool_registry : Map[String, ToolHandler] = Map::from_array(
  registered_tools.map(fn(r) { (r.tool.name, r.handler) }),
)

///|
/// Execute a tool by name with JSON arguments.
pub async fn execute_tool(
  name : String,
  arguments : String,
  parent_context? : @context.Context = @context.Context::empty(),
) -> String {
  let tracer = @telemetry.tracer("cybershang/agent-observability/tools")
  let meter = @telemetry.meter("cybershang/agent-observability/tools")
  let span = @telemetry.start_tool_span(
    tracer,
    name,
    arguments,
    parent_context~,
  )

  @telemetry.set_int_attribute(
    span,
    "app.tool.arguments_length",
    arguments.length().to_int64(),
  )
  @telemetry.set_bool_attribute(
    span,
    "app.tool.unknown",
    tool_registry.get(name) is None,
  )

  let result = match tool_registry.get(name) {
    Some(handler) => handler(arguments)
    None => "{\"error\": \"Unknown tool: " + name + "\"}"
  }

  let success = !result.contains("\"error\"")
  @telemetry.record_tool_call(meter, name, success~)
  if !success {
    @telemetry.log_error(
      "cybershang/agent-observability/tools",
      "Tool \{name} returned error: " + result,
      trace_context=Some(span.span_context()),
    )
  }

  @telemetry.record_tool_result(span, result)
  @telemetry.end_span(span)

  result
}

///|
/// Mock weather tool: always returns sunny 25°C.
fn get_weather(args : String) -> String {
  ignore(args)
  "{\"temperature\": 25, \"condition\": \"晴\"}"
}

///|
/// Execute a shell command and return stdout as string.
async fn execute_command_tool(args_json : String) -> String {
  let args = @json.parse(args_json) catch {
    _ => return "{\"error\": \"Invalid JSON arguments\"}"
  }
  let command = if args is { "command": String(cmd), .. } {
    cmd
  } else {
    return "{\"error\": \"Missing 'command' field\"}"
  }
  // Security: reject dangerous commands
  let forbidden = [
    "rm", "mv", "cp", "dd", "mkfs", "fdisk", "format", "del", "rd", "rmdir",
  ]
  let cmd_lower = command.trim().to_lower()
  for bad in forbidden {
    if cmd_lower.has_prefix(bad + " ") || cmd_lower == bad {
      return "{\"error\": \"Forbidden command: " + bad + "\"}"
    }
  }
  // Run command and collect output. Use lossy UTF-8 decoding so commands that
  // emit binary data (e.g. `cat` on a non-text file) do not crash the agent.
  let (code, stdout, _stderr) = @process.collect_output("sh", ["-c", command])
  let output = @utf8.decode_lossy(stdout.binary())
  "{\"exit_code\": " +
  code.to_string() +
  ", \"output\": \"" +
  escape_json(output) +
  "\"}"
}

///|
/// Escape special characters in a JSON string value.
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
