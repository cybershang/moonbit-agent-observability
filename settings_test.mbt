// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///|
test "parse_int - valid integer" {
  debug_inspect(parse_int("42", 0), content="42")
  debug_inspect(parse_int("-5", 0), content="-5")
  debug_inspect(parse_int("0", 99), content="0")
}

///|
test "parse_int - empty string returns default" {
  debug_inspect(parse_int("", 100), content="100")
}

///|
test "parse_int - whitespace-only returns default" {
  debug_inspect(parse_int("   ", 100), content="100")
}

///|
test "parse_int - invalid string returns default" {
  debug_inspect(parse_int("not_a_number", 42), content="42")
  debug_inspect(parse_int("12abc", 42), content="42")
  debug_inspect(parse_int("abc12", 42), content="42")
}

///|
test "parse_int - trims whitespace" {
  debug_inspect(parse_int("  123  ", 0), content="123")
  debug_inspect(parse_int("\t456\n", 0), content="456")
}

///|
test "parse_int - large numbers" {
  debug_inspect(parse_int("2147483647", 0), content="2147483647")
  debug_inspect(parse_int("-2147483648", 0), content="-2147483648")
}

///|
test "parse_int - overflow falls back to default" {
  // Number larger than Int max
  debug_inspect(parse_int("999999999999999999", 0), content="0")
}
