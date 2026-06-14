// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///|
/// OpenTelemetry tracer for the ToolRouter module.
let tools_tracer : Ref[@trace.Tracer?] = Ref(None)

///|
/// Get or create the ToolRouter tracer.
fn get_tools_tracer() -> @trace.Tracer {
  match tools_tracer.val {
    Some(t) => t
    None => {
      let t = @otel.tracer(
        "yingjie/agent-observability/tools",
        version=Some("0.1.0"),
      )
      tools_tracer.val = Some(t)
      t
    }
  }
}

///|
/// Available tools for the LLM.
pub let tools : Array[Tool] = [
  Tool::new(
    name="get_weather",
    description="获取指定城市的当前天气",
    parameters={
      "type": "object",
      "properties": {
        "city": { "type": "string", "description": "城市名称" },
      },
      "required": ["city"],
    },
  ),
  Tool::new(
    name="execute_command",
    description="在系统 shell 中执行命令，返回标准输出。注意：只能执行安全的只读命令（如 ls, cat, echo, pwd 等），禁止执行会修改系统的命令（如 rm, mv, write 等）。",
    parameters={
      "type": "object",
      "properties": {
        "command": {
          "type": "string",
          "description": "要执行的 shell 命令（例如: ls -la）",
        },
      },
      "required": ["command"],
    },
  ),
]

///|
/// Execute a tool by name with JSON arguments.
pub async fn execute_tool(
  name : String,
  arguments : String,
  parent_context? : @context.Context = @context.Context::empty(),
) -> String {
  let tracer = get_tools_tracer()
  let builder = tracer
    .span_builder("gen_ai.tool.execution")
    .with_kind(@trace.Internal)
    .with_attributes([
      @otel.KeyValue::new("gen_ai.tool.name", String(name)),
      @otel.KeyValue::new("gen_ai.tool.call.arguments", String(arguments)),
    ])
  let span = tracer.build_with_context(builder, parent_context)

  let result = match name {
    "get_weather" => get_weather(arguments)
    "execute_command" => execute_command_tool(arguments)
    _ => {
      span.set_status(
        @trace.Status::error(description=Some("Unknown tool: " + name)),
      )
      "{\"error\": \"Unknown tool: " + name + "\"}"
    }
  }

  // Record whether the result indicates an error
  if result.contains("\"error\"") {
    span.set_status(
      @trace.Status::error(description=Some("tool returned error")),
    )
  } else {
    span.set_status(@trace.Status::ok())
  }
  span.set_attribute(
    @otel.KeyValue::new("gen_ai.tool.call.result", String(result)),
  )
  span.end()

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
  // Run command and collect output
  let (code, stdout, _stderr) = @process.collect_output("sh", ["-c", command])
  let output = stdout.text()
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
