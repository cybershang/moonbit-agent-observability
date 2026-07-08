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

// ============================================================================
// Security tests for execute_command
// ============================================================================

///|
test "extract_base_command - simple command" {
  debug_inspect(extract_base_command("ls -la"), content="\"ls\"")
}

///|
test "extract_base_command - absolute path" {
  debug_inspect(extract_base_command("/bin/echo hello"), content="\"echo\"")
}

///|
test "extract_base_command - relative path" {
  debug_inspect(extract_base_command("./foo --help"), content="\"foo\"")
}

///|
test "extract_base_command - sudo prefix stripped" {
  debug_inspect(extract_base_command("sudo rm -rf /"), content="\"rm\"")
}

///|
test "extract_base_command - doas prefix stripped" {
  debug_inspect(extract_base_command("doas ls /root"), content="\"ls\"")
}

///|
test "extract_base_command - deeply nested path" {
  debug_inspect(
    extract_base_command("/usr/local/bin/python3 script.py"),
    content="\"python3\"",
  )
}

///|
test "extract_base_command - sudo with absolute path" {
  debug_inspect(extract_base_command("sudo /usr/bin/rm -rf"), content="\"rm\"")
}

///|
test "extract_base_command - single word" {
  debug_inspect(extract_base_command("pwd"), content="\"pwd\"")
}

///|
test "is_command_forbidden - rm is forbidden" {
  assert_true(is_command_forbidden("rm"))
}

///|
test "is_command_forbidden - mv is forbidden" {
  assert_true(is_command_forbidden("mv"))
}

///|
test "is_command_forbidden - cp is forbidden" {
  assert_true(is_command_forbidden("cp"))
}

///|
test "is_command_forbidden - chmod is forbidden" {
  assert_true(is_command_forbidden("chmod"))
}

///|
test "is_command_forbidden - curl is forbidden" {
  assert_true(is_command_forbidden("curl"))
}

///|
test "is_command_forbidden - wget is forbidden" {
  assert_true(is_command_forbidden("wget"))
}

///|
test "is_command_forbidden - sudo is forbidden" {
  assert_true(is_command_forbidden("sudo"))
}

///|
test "is_command_forbidden - python3 is forbidden" {
  assert_true(is_command_forbidden("python3"))
}

///|
test "is_command_forbidden - apt is forbidden" {
  assert_true(is_command_forbidden("apt"))
}

///|
test "is_command_forbidden - systemctl is forbidden" {
  assert_true(is_command_forbidden("systemctl"))
}

///|
test "is_command_forbidden - mount is forbidden" {
  assert_true(is_command_forbidden("mount"))
}

///|
test "is_command_forbidden - gcc is forbidden" {
  assert_true(is_command_forbidden("gcc"))
}

///|
test "is_command_forbidden - bash is forbidden" {
  assert_true(is_command_forbidden("bash"))
}

///|
test "is_command_forbidden - eval is forbidden" {
  assert_true(is_command_forbidden("eval"))
}

///|
test "is_command_forbidden - npm is forbidden" {
  assert_true(is_command_forbidden("npm"))
}

///|
test "is_command_forbidden - ls is allowed" {
  assert_false(is_command_forbidden("ls"))
}

///|
test "is_command_forbidden - cat is allowed" {
  assert_false(is_command_forbidden("cat"))
}

///|
test "is_command_forbidden - echo is allowed" {
  assert_false(is_command_forbidden("echo"))
}

///|
test "is_command_forbidden - date is allowed" {
  assert_false(is_command_forbidden("date"))
}

///|
test "is_command_forbidden - uname is allowed" {
  assert_false(is_command_forbidden("uname"))
}

///|
test "is_command_forbidden - head is allowed" {
  assert_false(is_command_forbidden("head"))
}

///|
test "is_command_forbidden - tail is allowed" {
  assert_false(is_command_forbidden("tail"))
}

///|
test "is_command_forbidden - grep is allowed" {
  assert_false(is_command_forbidden("grep"))
}

///|
test "is_command_forbidden - which is allowed" {
  assert_false(is_command_forbidden("which"))
}

///|
test "is_command_forbidden - whoami is allowed" {
  assert_false(is_command_forbidden("whoami"))
}

///|
test "is_command_forbidden - id is allowed" {
  assert_false(is_command_forbidden("id"))
}

///|
test "is_command_forbidden - free is allowed" {
  assert_false(is_command_forbidden("free"))
}

///|
test "is_command_forbidden - uptime is allowed" {
  assert_false(is_command_forbidden("uptime"))
}

///|
test "find_dangerous_operator - pipe" {
  let result = find_dangerous_operator("echo hello | grep world")
  assert_true(result is Some(_))
}

///|
test "find_dangerous_operator - semicolon" {
  let result = find_dangerous_operator("echo hello; rm -rf /")
  assert_true(result is Some(_))
}

///|
test "find_dangerous_operator - and chain" {
  let result = find_dangerous_operator("echo hello && rm -rf /")
  assert_true(result is Some(_))
}

///|
test "find_dangerous_operator - output redirect" {
  let result = find_dangerous_operator("echo data > /tmp/file")
  assert_true(result is Some(_))
}

///|
test "find_dangerous_operator - append redirect" {
  let result = find_dangerous_operator("echo data >> /tmp/file")
  assert_true(result is Some(_))
}

///|
test "find_dangerous_operator - command substitution" {
  let result = find_dangerous_operator("echo $(whoami)")
  assert_true(result is Some(_))
}

///|
test "find_dangerous_operator - backtick substitution" {
  let result = find_dangerous_operator("echo `whoami`")
  assert_true(result is Some(_))
}

///|
test "find_dangerous_operator - input redirect" {
  let result = find_dangerous_operator("cat < /etc/passwd")
  assert_true(result is Some(_))
}

///|
test "find_dangerous_operator - background" {
  let result = find_dangerous_operator("sleep 10 &")
  assert_true(result is Some(_))
}

///|
test "find_dangerous_operator - clean command returns None" {
  let result = find_dangerous_operator("echo hello world")
  assert_true(result is None)
}

///|
test "find_dangerous_operator - ls with flags returns None" {
  let result = find_dangerous_operator("ls -la /tmp")
  assert_true(result is None)
}

///|
async test "execute_command blocks rm" {
  let result = execute_command_tool("{\"command\": \"rm -rf /tmp/x\"}")
  assert_true(result.contains("\"error\""))
  assert_true(result.contains("Forbidden command"))
}

///|
async test "execute_command blocks /bin/rm" {
  let result = execute_command_tool("{\"command\": \"/bin/rm -rf /tmp/x\"}")
  assert_true(result.contains("\"error\""))
  assert_true(result.contains("Forbidden command"))
}

///|
async test "execute_command blocks sudo rm" {
  let result = execute_command_tool("{\"command\": \"sudo rm -rf /\"}")
  assert_true(result.contains("\"error\""))
}

///|
async test "execute_command blocks pipe operator" {
  let result = execute_command_tool("{\"command\": \"echo test | grep test\"}")
  assert_true(result.contains("\"error\""))
  assert_true(result.contains("shell operator"))
}

///|
async test "execute_command blocks semicolon chaining" {
  let result = execute_command_tool("{\"command\": \"echo hi; rm file\"}")
  assert_true(result.contains("\"error\""))
}

///|
async test "execute_command blocks redirect" {
  let result = execute_command_tool("{\"command\": \"echo data > file\"}")
  assert_true(result.contains("\"error\""))
}

///|
async test "execute_command blocks command substitution" {
  let result = execute_command_tool("{\"command\": \"echo $(whoami)\"}")
  assert_true(result.contains("\"error\""))
}

///|
async test "execute_command allows echo" {
  let result = execute_command_tool("{\"command\": \"echo hello world\"}")
  assert_true(result.contains("\"exit_code\""))
  assert_true(result.contains("hello world"))
}

///|
async test "execute_command allows pwd" {
  let result = execute_command_tool("{\"command\": \"pwd\"}")
  assert_true(result.contains("\"exit_code\""))
  assert_true(result.contains("/"))
}

///|
async test "execute_command allows ls" {
  let result = execute_command_tool("{\"command\": \"ls\"}")
  assert_true(result.contains("\"exit_code\""))
}

///|
async test "execute_command blocks curl" {
  let result = execute_command_tool(
    "{\"command\": \"curl http://example.com\"}",
  )
  assert_true(result.contains("\"error\""))
}

///|
async test "execute_command blocks chmod" {
  let result = execute_command_tool("{\"command\": \"chmod +x script.sh\"}")
  assert_true(result.contains("\"error\""))
}

///|
async test "execute_command blocks python3" {
  let result = execute_command_tool("{\"command\": \"python3 -c 'print(1)'\"}")
  assert_true(result.contains("\"error\""))
}

///|
async test "execute_command blocks bash" {
  let result = execute_command_tool("{\"command\": \"bash -c 'echo hi'\"}")
  assert_true(result.contains("\"error\""))
}

///|
async test "execute_command blocks npm" {
  let result = execute_command_tool("{\"command\": \"npm install\"}")
  assert_true(result.contains("\"error\""))
}

///|
async test "execute_command blocks eval" {
  let result = execute_command_tool("{\"command\": \"eval ls\"}")
  assert_true(result.contains("\"error\""))
}

///|
async test "execute_command blocks systemctl" {
  let result = execute_command_tool("{\"command\": \"systemctl status ssh\"}")
  assert_true(result.contains("\"error\""))
}

///|
async test "execute_command with empty args returns error" {
  let result = execute_command_tool("{}")
  assert_true(result.contains("\"error\""))
}

///|
async test "execute_command with invalid json returns error" {
  let result = execute_command_tool("not json")
  assert_true(result.contains("\"error\""))
}
