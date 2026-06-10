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
]

///| Execute a tool by name with JSON arguments.
pub fn execute_tool(name : String, arguments : String) -> String {
  match name {
    "get_weather" => get_weather(arguments)
    _ => "{\"error\": \"Unknown tool: " + name + "\"}"
  }
}

///| Mock weather tool: always returns sunny 25°C.
fn get_weather(args : String) -> String {
  ignore(args)
  "{\"temperature\": 25, \"condition\": \"晴\"}"
}
