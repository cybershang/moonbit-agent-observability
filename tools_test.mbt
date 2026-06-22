// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

// ============================================================================
// Black-box Tests for tools.mbt - Public API only
// ============================================================================

///|
test "tools array contains expected tools" {
  debug_inspect(tools.length(), content="3")
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
  debug_inspect(
    tools[2].name,
    content=(
      #|"lookup_city"
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
  assert_true(tool.description.contains("weather"))
  let params = tool.parameters.stringify()
  assert_true(params.contains("\"location_id\""))
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

///|
test "lookup_city tool has correct schema" {
  let tool = tools[2]
  debug_inspect(
    tool.name,
    content=(
      #|"lookup_city"
    ),
  )
  assert_true(tool.description.contains("location"))
  let params = tool.parameters.stringify()
  assert_true(params.contains("\"query\""))
  assert_true(params.contains("\"adm\""))
}
