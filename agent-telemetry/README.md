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
let provider = @telemetry.init_from_env(
  id_generator=@telemetry.ProcessUniqueRandom,
)

// Option 2: manually select an exporter.
let config = @telemetry.TelemetryConfig::new(service_name="my-agent")
let provider = @telemetry.init_telemetry(
  config,
  @telemetry.Otlp("http://localhost:4318"),
  id_generator=@telemetry.ProcessUniqueRandom,
)

// Create a GenAI chat span.
let tracer = @telemetry.tracer("my-agent/llm")
let span = @telemetry.start_chat_span(
  tracer,
  provider_name="stepfun",
  model="step-3.7-flash",
  max_tokens=1024,
)
// ... send the request and obtain response_json ...
@telemetry.record_chat_response(span, response_json)
@telemetry.end_span_ok(span)
```

## Main API

| Scenario | Functions |
|---|---|
| General | `TelemetryConfig::new`, `init_telemetry`, `init_from_env`, `IdGeneratorOption`, `tracer`, `start_span`, `end_span`, `end_span_ok`, `end_span_error` |
| LLM chat | `start_chat_span`, `record_chat_usage`, `record_chat_response`, `set_chat_http_error` |
| Tool | `start_tool_span`, `record_tool_result`, `set_tool_error` |
| Agent turn | `start_agent_turn_span`, `record_turn_metrics`, `set_turn_max_tool_turns_error` |

## Instrumentation Guide

The library is designed to be inserted into your existing agent code with minimal changes. The general pattern is:

1. Get a tracer with `@telemetry.tracer("your-scope")`.
2. Start a span at the beginning of an operation.
3. Pass `parent_context=span.context()` to child operations so that LLM, tool, and agent spans form a single trace.
4. Record results, usage, or errors before ending the span.

The following examples are based on the `agent-observability` sample application.

### Instrumenting an LLM Chat Request

In your chat client, wrap the HTTP request in a `gen_ai.chat` span:

```moonbit
async fn chat(
  messages : Array[Message],
  parent_context? : @context.Context = @context.Context::empty(),
) -> LLMResponse {
  let tracer = @telemetry.tracer("my-agent/llm")
  let span = @telemetry.start_chat_span(
    tracer,
    provider_name="stepfun",
    model="step-3.7-flash",
    max_tokens=1024,
    input_messages~,        // optional: capture input messages
    parent_context~,        // optional: continue an existing trace
  )

  let (response, body) = @http.post(endpoint, request_json, headers~)

  guard response.code == 200 else {
    @telemetry.set_chat_http_error(span, response.code)
    @telemetry.end_span(span)
    abort("LLM request failed")
  }

  let data = body.json()
  if data is { "usage": usage_obj, .. } {
    @telemetry.record_chat_usage(span, usage_obj)
  }
  @telemetry.record_chat_response(span, data, output_messages~)
  @telemetry.end_span_ok(span)

  parse_response(data)
}
```

This produces a span named `gen_ai.chat` with attributes such as `gen_ai.provider.name`, `gen_ai.request.model`, `gen_ai.usage.input_tokens`, and `gen_ai.response.id`.

### Instrumenting Tool Execution

In your tool dispatcher, wrap each tool call in a `gen_ai.tool.execution` span:

```moonbit
pub async fn execute_tool(
  name : String,
  arguments : String,
  parent_context? : @context.Context = @context.Context::empty(),
) -> String {
  let tracer = @telemetry.tracer("my-agent/tools")
  let span = @telemetry.start_tool_span(
    tracer,
    name,
    arguments,
    parent_context~,
  )

  let result = run_the_tool(name, arguments)

  @telemetry.record_tool_result(span, result)
  @telemetry.end_span(span)
  result
}
```

`record_tool_result` automatically marks the span as error if the result string contains `"error"`. Use `set_tool_error` if you want to set a custom error description.

### Instrumenting an Agent Turn

In your agent's main loop, wrap one complete turn (user prompt → LLM → tools → final reply) in an `agent.turn` span:

```moonbit
pub async fn Agent::run(self : Agent, prompt : String) -> AgentTurnResult {
  let tracer = @telemetry.tracer("my-agent/agent")
  let span = @telemetry.start_agent_turn_span(
    tracer,
    prompt,
    self.max_tool_turns,
  )
  let parent_context = span.context()

  // ... run the LLM / tool loop using parent_context~ ...

  if hit_max_tool_turns {
    @telemetry.set_turn_max_tool_turns_error(span)
  }

  @telemetry.record_turn_metrics(span, turns, executed.length(), final_reply)
  @telemetry.end_span_ok(span)

  { reply: final_reply, tool_calls: executed }
}
```

The `parent_context` is passed to the LLM chat request and each tool execution, so the resulting trace shows the agent turn as the parent of its chat and tool spans.

### Propagating Trace Context

Always pass `parent_context=span.context()` when a function calls another instrumented function. This links the child span to the parent span and produces a single coherent trace. If no parent is available, the helpers default to an empty context.

## Environment Variables

`init_from_env` reads the following variables:

| Variable | Description | Default |
|---|---|---|
| `OTEL_SERVICE_NAME` | Service name | `agent-telemetry` |
| `OTEL_STDOUT` | Use the stdout exporter when set to `true` | `false` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP/HTTP endpoint | `http://localhost:4318` |

## Flushing and Shutting Down

`SdkTracerProvider::force_flush` and `shutdown` return `OTelSdkResult`. The library intentionally leaves error handling to the application so you can decide whether to log, retry, or abort.

A minimal CLI pattern is to print export failures to stdout:

```moonbit
fn format_error(err : @error.OTelSdkError) -> String {
  match err {
    AlreadyShutdown => "AlreadyShutdown"
    Timeout(ms) => "Timeout(\{ms}ms)"
    InvalidArgument(msg) => "InvalidArgument(\{msg})"
    InternalFailure(msg) => "InternalFailure(\{msg})"
    ExportFailure(name, msg) => "ExportFailure(\{name}, \{msg})"
  }
}

match provider.force_flush() {
  Ok(_) => ()
  Err(err) => @stdio.stdout.write("Telemetry flush failed: " + format_error(err) + "\n")
}

match provider.shutdown() {
  Ok(_) => ()
  Err(err) => @stdio.stdout.write("Telemetry shutdown failed: " + format_error(err) + "\n")
}
```

Always call `shutdown` before the process exits so pending spans are exported.

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
