// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///|
async fn main {
  let settings = @agent.Settings::from_env()

  // Initialize OpenTelemetry SDK
  // OTEL_STDOUT=true uses the print exporter; otherwise use OTLP/HTTP to the local collector.
  let provider = if settings.otel_stdout {
    let exporter = @print.SpanExporter::new()
    @sdk.tracer_provider_builder()
      .with_simple_exporter(exporter.into_span_exporter())
      .build()
  } else {
    match @otlp.SpanExporter::builder().with_http().build() {
      Ok(exporter) =>
        @sdk.tracer_provider_builder()
          .with_batch_exporter(exporter.into_span_exporter())
          .build()
      Err(err) => {
        let err_text = match err {
          InvalidConfig(key, msg) => "InvalidConfig(\{key}, \{msg})"
          UnsupportedProtocol(p) => "UnsupportedProtocol(\{p})"
          UnsupportedCompressionAlgorithm(a) => "UnsupportedCompressionAlgorithm(\{a})"
        }
        @stdio.stdout.write("Failed to build OTLP exporter: " + err_text + "\n")
        @sdk.tracer_provider_builder().build()
      }
    }
  }
  @sdk.set_tracer_provider(provider)

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

  // Gracefully shut down the tracer provider so pending spans are exported.
  ignore(provider.shutdown())
}
