// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///|
async fn main {
  // Initialize OpenTelemetry SDK only when OTEL_STDOUT=true
  let otel_stdout = @env.get_env_var("OTEL_STDOUT").unwrap_or_else(fn() { "" })
  if otel_stdout.to_lower() == "true" {
    let exporter = @print.SpanExporter::new()
    let provider = @sdk.tracer_provider_builder()
      .with_simple_exporter(exporter.into_span_exporter())
      .build()
    @sdk.set_tracer_provider(provider)
  }

  // Create a StepFun client
  let api_key = @agent.read_dotenv("STEPFUN_API_KEY").unwrap_or_else(fn() {
    @env.get_env_var("STEPFUN_API_KEY").unwrap_or_else(fn() { "" })
  })
  let client = @agent.Client::new(
    provider_name="stepfun",
    base_url="https://api.stepfun.com/v1",
    model="step-3.7-flash",
    api_key~,
  )

  // Create the agent with available tools
  let agent = @agent.Agent::new(client, tools=@agent.tools)

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
