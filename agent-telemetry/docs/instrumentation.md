# Instrumentation Guide

This guide shows how to instrument a MoonBit agent application with `cybershang/agent-telemetry`. The examples are based on the `agent-observability` sample application.

The library is designed to be inserted into your existing code with minimal changes. The general pattern is:

1. Get a tracer with `@telemetry.tracer("your-scope")`.
2. Start a span at the beginning of an operation.
3. Pass `parent_context=span.context()` to child operations so that LLM, tool, and agent spans form a single trace.
4. Record results, usage, or errors before ending the span.

## Instrumenting an LLM Chat Request

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

## Instrumenting Tool Execution

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

## Instrumenting an Agent Turn

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

## Propagating Trace Context

Always pass `parent_context=span.context()` when a function calls another instrumented function. This links the child span to the parent span and produces a single coherent trace. If no parent is available, the helpers default to an empty context.
