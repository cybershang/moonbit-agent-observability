// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

// ============================================================================
// End-to-End Smoke Test for Agent::run
//
// This test exercises the full agent loop against the real LLM API:
//   user input -> LLM chat -> tool call detection -> tool execution
//   -> tool results fed back -> final assistant reply.
//
// It intentionally does NOT mock the provider. See AGENTS.md "测试理念".
// ============================================================================

///|
async test "Agent end-to-end smoke test with weather tool call" {
  // Setup OTel with print exporter so spans are visible without a collector.
  let exporter = @print.SpanExporter::new()
  let provider = @sdk.tracer_provider_builder()
    .with_simple_exporter(exporter.into_span_exporter())
    .build()
  @sdk.set_tracer_provider(provider)

  // Load credentials the same way the REPL does.
  let settings = Settings::from_env()
  let client = Client::from_settings(settings)
  let agent = Agent::new(client, tools~, max_tool_turns=settings.max_tool_turns)

  // Run a prompt that should trigger the get_weather tool.
  let turn = agent.run("北京今天天气怎么样？")

  // Verify the agent actually used the tool.
  assert_true(turn.tool_calls.length() > 0)
  let first_call = turn.tool_calls[0].call
  assert_true(first_call.name == "get_weather")
  assert_true(first_call.arguments.contains("北京"))

  // Verify a final text reply was produced.
  assert_true(turn.reply.length() > 0)
  @debug.debug(turn)

  ignore(provider.shutdown())
}
