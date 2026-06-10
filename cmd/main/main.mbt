// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///|
async fn main {
  let settings = @agent.Settings::from_env()

  // Initialize OpenTelemetry SDK only when OTEL_STDOUT=true
  if settings.otel_stdout {
    let exporter = @print.SpanExporter::new()
    let provider = @sdk.tracer_provider_builder()
      .with_simple_exporter(exporter.into_span_exporter())
      .build()
    @sdk.set_tracer_provider(provider)
  }

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

    let turn = agent.run(prompt)
    for record in turn.tool_calls {
      @stdio.stdout.write("\n[Tool Call] " + record.call.name + "(" + record.call.arguments + ")\n")
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
}
