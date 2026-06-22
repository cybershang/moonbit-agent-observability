// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

// ============================================================================
// White-box Tests for tools.mbt - Private functions
// ============================================================================

///|
async test "get_weather reports missing credentials when none configured" {
  // If credentials are present in the environment, skip the missing-credential
  // path to avoid making a real API call in this unit test.
  if qweather_configured() {
    return
  }
  let result = get_weather("{\"location_id\":\"101010100\"}")
  assert_true(result.contains("\"error\""))
  assert_true(result.contains("QWEATHER_TOKEN"))
}

///|
async test "lookup_city reports missing credentials when none configured" {
  if qweather_configured() {
    return
  }
  let result = lookup_city("{\"query\":\"Beijing\"}")
  assert_true(result.contains("\"error\""))
  assert_true(result.contains("QWEATHER_TOKEN"))
}

///|
test "url_encode - ascii alphanumeric preserved" {
  debug_inspect(url_encode("HelloWorld123"), content="\"HelloWorld123\"")
}

///|
test "url_encode - spaces and special chars" {
  debug_inspect(url_encode("a b+c"), content="\"a%20b%2Bc\"")
}

///|
test "url_encode - chinese characters" {
  debug_inspect(url_encode("北京"), content="\"%E5%8C%97%E4%BA%AC\"")
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
