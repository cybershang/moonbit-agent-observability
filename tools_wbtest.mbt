// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

// ============================================================================
// White-box Tests for tools.mbt - Private functions
// ============================================================================

///|
test "get_weather returns valid JSON" {
  let result = get_weather("{\"city\":\"Beijing\"}")
  assert_true(result.contains("\"temperature\""))
  assert_true(result.contains("\"condition\""))
  assert_true(result.contains("晴"))
}

///|
test "get_weather ignores arguments" {
  // get_weather is a mock that ignores all arguments
  let result1 = get_weather("{}")
  let result2 = get_weather("{\"city\":\"Shanghai\"}")
  debug_inspect(
    result1,
    content=(
      #|"{\"temperature\": 25, \"condition\": \"晴\"}"
    ),
  )
  ignore(result2)
}

///|
test "escape_json - basic string" {
  let result = escape_json("hello")
  debug_inspect(
    result,
    content=(
      #|"hello"
    ),
  )
}

///|
test "escape_json - escapes quotes" {
  let result = escape_json("say \"hello\"")
  debug_inspect(
    result,
    content=(
      #|"say \\\"hello\\\""
    ),
  )
}

///|
test "escape_json - escapes backslash" {
  let result = escape_json("path\\to\\file")
  debug_inspect(
    result,
    content=(
      #|"path\\\\to\\\\file"
    ),
  )
}

///|
test "escape_json - escapes newlines" {
  let result = escape_json("line1\nline2")
  debug_inspect(
    result,
    content=(
      #|"line1\\nline2"
    ),
  )
}

///|
test "escape_json - escapes tabs" {
  let result = escape_json("col1\tcol2")
  debug_inspect(
    result,
    content=(
      #|"col1\\tcol2"
    ),
  )
}

///|
test "escape_json - escapes carriage return" {
  let result = escape_json("line1\rline2")
  debug_inspect(
    result,
    content=(
      #|"line1\\rline2"
    ),
  )
}

///|
test "escape_json - combined special chars" {
  let result = escape_json("a\tb\nc\\d\"e")
  debug_inspect(
    result,
    content=(
      #|"a\\tb\\nc\\\\d\\\"e"
    ),
  )
}

///|
test "escape_json - empty string" {
  let result = escape_json("")
  debug_inspect(
    result,
    content=(
      #|""
    ),
  )
}

///|
test "escape_json - unicode characters preserved" {
  let result = escape_json("你好世界 🌍")
  debug_inspect(
    result,
    content=(
      #|"你好世界 🌍"
    ),
  )
}

///|
async test "execute_command handles non-utf8 stdout" {
  let result = execute_command_tool(
    "{\"command\": \"printf '\\\\xFF\\\\xFE'\"}",
  )
  // Should not crash on non-UTF-8 output; result contains replacement chars or
  // the command output in some form.
  assert_true(result.contains("exit_code"))
}
