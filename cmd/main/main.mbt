// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///|
async fn main {
  let ask = parse_ask_arg()
  let settings = @agent.Settings::from_env()

  // Initialize the global OpenTelemetry providers from env.
  // Use ProcessUniqueRandom to avoid duplicate trace/span IDs across restarts.
  let providers = @telemetry.init_from_env(
    service_name="agent-observability",
    id_generator=@telemetry.ProcessUniqueRandom,
  )

  // Create the client and agent from settings
  let client = @agent.Client::from_settings(settings)
  let agent = @agent.Agent::new(
    client,
    tools=@agent.tools,
    max_tool_turns=settings.max_tool_turns,
  )

  @async.with_task_group(group => {
    // Metrics and logs need background tasks to flush periodically.
    providers.spawn_background_tasks(group)

    match ask {
      Some(query) => {
        // Non-interactive mode: run a single turn and exit.
        let turn = agent.run(query)
        print_turn(turn)
        providers.force_flush()
      }
      None =>
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
          print_turn(turn)

          // Ensure spans/metrics/logs are flushed after each turn.
          providers.force_flush()
        }
    }

    // Gracefully shut down all providers so pending telemetry is exported.
    providers.shutdown()
  })
}

///|
/// Parse the `--ask` / `-a` command-line option for non-interactive mode.
fn parse_ask_arg() -> String? {
  let matches = @argparse.Command(
    "agent-observability",
    about="An observable AI Agent built with MoonBit.",
    options=[
      OptionArg(
        "ask",
        short='a',
        about="Run a single query in non-interactive mode and exit.",
      ),
    ],
  ).parse() catch {
    _ => return None
  }
  match matches.values {
    { "ask": [query], .. } => Some(query)
    _ => None
  }
}

///|
/// Print the result of a single agent turn, including any tool calls and the reply.
async fn print_turn(turn : @agent.AgentTurnResult) -> Unit {
  for record in turn.tool_calls {
    @stdio.stdout.write(
      "\n[Tool Call] " + record.call.name + "(" + record.call.arguments + ")\n",
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
