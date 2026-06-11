// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

// ============================================================================
// Black-box Tests for tools.mbt - Public API only
// ============================================================================

///|
test "tools array contains expected tools" {
  debug_inspect(tools.length(), content="2")
  debug_inspect(
    tools[0].name,
    content=(
      #|"get_weather"
    ),
  )
  debug_inspect(
    tools[1].name,
    content=(
      #|"execute_command"
    ),
  )
}

///|
test "get_weather tool has correct schema" {
  let tool = tools[0]
  debug_inspect(
    tool.name,
    content=(
      #|"get_weather"
    ),
  )
  assert_true(tool.description.contains("天气"))
  let params = tool.parameters.stringify()
  assert_true(params.contains("\"city\""))
  assert_true(params.contains("\"required\""))
}

///|
test "execute_command tool has correct schema" {
  let tool = tools[1]
  debug_inspect(
    tool.name,
    content=(
      #|"execute_command"
    ),
  )
  assert_true(tool.description.contains("shell"))
  let params = tool.parameters.stringify()
  assert_true(params.contains("\"command\""))
}
