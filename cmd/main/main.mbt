// Copyright (c) 2026 Yingjie Shang
// agent-observability is licensed under Mulan PSL v2.

///| Per-process counter to keep seeds unique even if called multiple times.
let seed_counter : Ref[Int] = Ref(0)

///| Build a 32-byte seed from the current timestamp and a process counter.
///
/// The SDK's default RandomIdGenerator uses a fixed ChaCha8 seed, which causes
/// duplicate trace/span IDs across process restarts. Mixing in the current
/// nanosecond timestamp and a per-process counter ensures every process
/// produces unique IDs.
async fn make_seed() -> Bytes {
  let (code, stdout, _stderr) = @process.collect_output("date", ["+%s%N"])
  let timestamp = if code == 0 {
    stdout.text().trim().to_owned()
  } else {
    "0"
  }
  let counter = seed_counter.val
  seed_counter.val = seed_counter.val + 1
  let text =
    "seed-" +
    counter.to_string() +
    "-" +
    timestamp +
    "-abcdefghijklmnopqrstuvwx"
  // Take exactly 32 bytes; pad with '0' if shorter.
  let mut padded = ""
  for i = 0; i < 32; i = i + 1 {
    if i < text.length() {
      padded = padded + text[i:i + 1].to_owned()
    } else {
      padded = padded + "0"
    }
  }
  let bytes : Array[Byte] = []
  for ch in padded {
    bytes.push(ch.to_int().to_byte())
  }
  Bytes::from_iter(bytes.iter())
}

///| Create an IdGenerator with a process-unique seed.
async fn make_random_id_generator() -> @sdktrace.IdGenerator {
  let seed = make_seed()
  let random = @random.Rand::chacha8(seed=seed)
  @sdktrace.IdGenerator::new(
    fn() {
      match @common.TraceId::from_hex(random_hex_32(random)) {
        Some(id) => id
        None => @common.TraceId::invalid()
      }
    },
    fn() {
      match @common.SpanId::from_hex(random_hex_16(random)) {
        Some(id) => id
        None => @common.SpanId::invalid()
      }
    },
  )
}

///| Generate a 32-character hex string (16 bytes).
fn random_hex_32(random : @random.Rand) -> String {
  random_hex_16(random) + random_hex_16(random)
}

///| Generate a 16-character hex string (8 bytes).
fn random_hex_16(random : @random.Rand) -> String {
  random.uint64().to_string(radix=16).pad_start(16, '0')
}

async fn main {
  let settings = @agent.Settings::from_env()

  // Build the OTel resource.
  // Default detectors pick up OTEL_SERVICE_NAME / OTEL_RESOURCE_ATTRIBUTES.
  // If no service.name is provided, fall back to "agent-observability".
  let resource = {
    let base = @resource.Resource::builder().build()
    match @env.get_env_var("OTEL_SERVICE_NAME") {
      Some(_) => base
      None => base.merge(
        @resource.Resource::new([
          @common.KeyValue::new("service.name", String("agent-observability")),
        ]),
      )
    }
  }

  // Configure a REPL-friendly batch processor:
  // small batches, short scheduled delay, so spans show up in Jaeger quickly.
  let batch_config = @sdktrace.BatchConfig::new(
    max_queue_size=64,
    max_export_batch_size=16,
    scheduled_delay_millis=1000,
    export_timeout_millis=5000,
  )

  // Initialize OpenTelemetry SDK
  // OTEL_STDOUT=true uses the print exporter; otherwise use OTLP/HTTP to the local collector.
  // Use a fresh random ID generator seeded from the current timestamp so trace/span IDs
  // are unique across process restarts.
  let id_generator = make_random_id_generator()
  let provider = if settings.otel_stdout {
    let exporter = @print.SpanExporter::new()
    @sdk.tracer_provider_builder()
      .with_resource(resource)
      .with_id_generator(id_generator)
      .with_simple_exporter(exporter.into_span_exporter())
      .build()
  } else {
    match @otlp.SpanExporter::builder().with_http().build() {
      Ok(exporter) =>
        @sdk.tracer_provider_builder()
          .with_resource(resource)
          .with_id_generator(id_generator)
          .with_batch_exporter(
            exporter.into_span_exporter(),
            config=batch_config,
          )
          .build()
      Err(err) => {
        let err_text = match err {
          InvalidConfig(key, msg) => "InvalidConfig(\{key}, \{msg})"
          UnsupportedProtocol(p) => "UnsupportedProtocol(\{p})"
          UnsupportedCompressionAlgorithm(a) => "UnsupportedCompressionAlgorithm(\{a})"
        }
        @stdio.stdout.write("Failed to build OTLP exporter: " + err_text + "\n")
        @sdk.tracer_provider_builder()
          .with_resource(resource)
          .with_id_generator(id_generator)
          .build()
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
