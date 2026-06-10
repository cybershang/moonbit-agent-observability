// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///| Available tools for the LLM.
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
        "command": { "type": "string", "description": "要执行的 shell 命令（例如: ls -la）" },
      },
      "required": ["command"],
    },
  ),
]
