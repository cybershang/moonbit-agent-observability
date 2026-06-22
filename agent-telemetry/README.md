# agent-telemetry

OpenTelemetry instrumentation library for MoonBit Agent / LLM / Tool scenarios.

It wraps the boilerplate OTel tracer / span / attribute code into business-semantic helpers, so agent developers only need to decide when to create spans and what business data to record.

## Design Layers

- **Thin wrapper** (`lib.mbt`): provider initialization, tracer cache, span lifecycle helpers such as `start_span` / `end_span`.
- **Semantic wrapper** (`genai.mbt`, `tool.mbt`, `agent.mbt`): sets attributes according to the OpenTelemetry GenAI semantic conventions, covering chat, tool execution, and agent turn spans.

## Quick Start

```bash
moon add cybershang/agent-telemetry
```

```moonbit
// Option 1: one-line initialization from environment variables.
// Reads OTEL_SERVICE_NAME, OTEL_STDOUT, and OTEL_EXPORTER_OTLP_ENDPOINT.
// Use ProcessUniqueRandom to avoid duplicate trace/span IDs across restarts.
let providers = @telemetry.init_from_env(
  id_generator=@telemetry.ProcessUniqueRandom,
)

// Option 2: manually select an exporter.
let config = @telemetry.TelemetryConfig::new(service_name="my-agent")
let providers = @telemetry.init_telemetry(
  config,
  @telemetry.Otlp("http://localhost:4318"),
  id_generator=@telemetry.ProcessUniqueRandom,
)

// Metrics and logs need background tasks.
@async.with_task_group((group) => {
  providers.spawn_background_tasks(group)

  // Create a GenAI chat span.
  let tracer = @telemetry.tracer("my-agent/llm")
  let meter = @telemetry.meter("my-agent/llm")
  let span = @telemetry.start_chat_span(
    tracer,
    provider_name="stepfun",
    model="step-3.7-flash",
    max_tokens=1024,
  )
  // ... send the request and obtain response_json ...
  @telemetry.record_llm_call(meter, "stepfun", "step-3.7-flash", success=true)
  @telemetry.record_chat_response(span, response_json)
  @telemetry.end_span_ok(span)

  providers.force_flush()
  providers.shutdown()
})
```

## Main API

| Scenario | Functions |
|---|---|
| General | `TelemetryConfig::new`, `init_telemetry`, `init_from_env`, `TelemetryProviders`, `IdGeneratorOption`, `tracer`, `meter`, `logger`, `start_span`, `end_span`, `end_span_ok`, `end_span_error` |
| LLM chat | `start_chat_span`, `record_chat_usage`, `record_chat_response`, `set_chat_http_error` |
| Tool | `start_tool_span`, `record_tool_result`, `set_tool_error` |
| Agent turn | `start_agent_turn_span`, `record_turn_metrics`, `set_turn_max_tool_turns_error` |
| Metrics | `record_llm_call`, `record_llm_latency`, `record_tool_call`, `record_turn_count` |
| Logs | `emit_log`, `log_info`, `log_warn`, `log_error` |

## Instrumentation Guide

See [docs/instrumentation.md](docs/instrumentation.md) for a step-by-step guide that shows how to instrument LLM chat requests, tool executions, and agent turns using the `agent-observability` sample application as a reference.

## Environment Variables

`init_from_env` reads the following variables:

| Variable | Description | Default |
|---|---|---|
| `OTEL_SERVICE_NAME` | Service name | `agent-telemetry` |
| `OTEL_STDOUT` | Use the stdout exporter when set to `true` | `false` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP/HTTP endpoint | `http://localhost:4318` |

## Flushing and Shutting Down

`TelemetryProviders` exposes `force_flush()` and `shutdown()` methods that flush/shutdown all three providers (traces, metrics, logs) and print any errors to stdout.

```moonbit
providers.force_flush()
providers.shutdown()
```

Always call `shutdown` before the process exits so pending telemetry is exported.

## ID Generator Option

The `id_generator` parameter of `init_telemetry` / `init_from_env` supports:

| Option | Description |
|---|---|
| `@telemetry.SdkDefault` | Use the SDK default `RandomIdGenerator` |
| `@telemetry.ProcessUniqueRandom` | Generate a process-unique seed from the current timestamp and a counter, avoiding duplicate trace/span IDs across restarts |
| `@telemetry.Custom(generator)` | Provide your own `IdGenerator` |

## Target Backend

This library depends on `opentelemetry/otlp`, whose `async/http` and `async/socket` interfaces are **native-only**. Therefore `moon.mod` declares `preferred_target = "native"`. Projects using this library should also run and test with `--target native`.

## Example Project

A complete agent example using this library can be found at:

[github.com/cybershang/moonbit-agent-observability](https://github.com/cybershang/moonbit-agent-observability)

## Testing

```bash
moon test -p cybershang/agent-telemetry --target native
```

## License

Mulan PSL v2
