// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///| Read an environment variable, falling back to the `.env` file.
async fn env(key : String, default~ : String = "") -> String {
  @agent.read_dotenv(key).unwrap_or_else(fn() {
    @env.get_env_var(key).unwrap_or_else(fn() { default })
  })
}

///| Parse an integer from a string, returning the default on failure.
fn parse_int(s : String, default : Int) -> Int {
  match s.trim() {
    "" => default
    text =>
      try {
        @string.parse_int(text)
      } catch {
        _ => default
      }
  }
}

///|
async fn main {
  // Initialize OpenTelemetry SDK only when OTEL_STDOUT=true
  let otel_stdout = env("OTEL_STDOUT")
  if otel_stdout.to_lower() == "true" {
    let exporter = @print.SpanExporter::new()
    let provider = @sdk.tracer_provider_builder()
      .with_simple_exporter(exporter.into_span_exporter())
      .build()
    @sdk.set_tracer_provider(provider)
  }

  // Load LLM configuration from environment / .env
  let api_key = env("LLM_API_KEY")
  let provider_name = env("LLM_PROVIDER", default="stepfun")
  let base_url = env("LLM_BASE_URL", default="https://api.stepfun.com/v1")
  let model = env("LLM_MODEL", default="step-3.7-flash")
  let max_tokens = parse_int(env("LLM_MAX_TOKENS", default="1024"), 1024)
  let max_tool_turns = parse_int(env("AGENT_MAX_TOOL_TURNS", default="10"), 10)

  // Create the client and agent
  let client = @agent.Client::new(
    provider_name~,
    base_url~,
    model~,
    api_key~,
    max_tokens~,
  )
  let agent = @agent.Agent::new(client, tools=@agent.tools, max_tool_turns~)

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
