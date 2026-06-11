// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///|
async fn main {
  let settings = @agent.Settings::from_env()

  // Use a fresh random ID generator seeded from the current timestamp so trace/span IDs
  // are unique across process restarts.
  let id_generator = make_random_id_generator()

  // Initialize the global OpenTelemetry tracer provider.
  let provider = @agent.init_telemetry(settings, id_generator)

  // Create the client and agent from settings
  let client = @agent.Client::from_settings(settings)
  let agent = @agent.Agent::new(
    client,
    tools=@agent.tools,
    max_tool_turns=settings.max_tool_turns,
  )

  // REPL with continuous dialogue
  while true {
    @stdio.stdout.write("> ")
    let prompt = match @stdio.stdin.read_until("\n") {
      Some(line) => line.trim(char_set="\r\n").to_owned()
      None => break
    }
    if prompt == "exit" || prompt == "quit" {
      break
    }

    // Ensure spans are flushed to the OTLP collector after each turn.
    // This is especially important for the batch exporter so telemetry
    // is not lost when the process exits shortly after the loop.
    ignore(provider.force_flush())

    let turn = agent.run(prompt)
    for record in turn.tool_calls {
      @stdio.stdout.write(
        "\n[Tool Call] " +
        record.call.name +
        "(" +
        record.call.arguments +
        ")\n",
      )
      let display_result = if record.result.length() > 200 {
        record.result[:200].to_owned() + "... (truncated)"
      } else {
        record.result
      }
      @stdio.stdout.write("[Tool Result] " + display_result + "\n")
    }
    @stdio.stdout.write(turn.reply)
    @stdio.stdout.write("\n")
  }

  // Gracefully shut down the tracer provider so pending spans are exported.
  ignore(provider.shutdown())
}
