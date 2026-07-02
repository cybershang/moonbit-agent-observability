# Agent 可观测性插桩说明

本文档描述 `agent-observability` 项目在 AI Agent 核心运行链路上的 OpenTelemetry 插桩位置、Span 命名、属性规范以及上下文传递方式。

---

## 1. Tracer 初始化

项目按模块划分了两个独立的 Tracer，均采用懒加载（lazy）单例模式：

| 模块 | 文件 | Tracer 名称 |
|---|---|---|
| Agent | `agent.mbt` | `yingjie/agent-observability/agent` |
| LLMGateway | `llm.mbt` | `yingjie/agent-observability/llm` |

```moonbit
// agent.mbt
fn get_agent_tracer() -> @trace.Tracer {
  match agent_tracer.val {
    Some(t) => t
    None => {
      let t = @otel.tracer(
        "yingjie/agent-observability/agent",
        version=Some("0.1.0"),
      )
      agent_tracer.val = Some(t)
      t
    }
  }
}
```

---

## 2. Agent 单轮对话（`Agent::run`）

**Span 名称**：`agent.turn`

**文件位置**：`agent.mbt:69`

### 2.1 创建 Span

- SpanKind: `Internal`
- 初始属性：
  - `agent.turn.input` — 用户输入 prompt
  - `agent.turn.max_tool_turns` — 最大工具调用轮数

### 2.2 上下文传递

MoonBit 没有隐式的异步上下文存储（async local storage），因此 trace context 必须作为显式参数逐层传递。这一设计也符合 **explicit is better than implicit** 的理念——函数的签名直接表明它依赖外部上下文，调用链路清晰可追踪。

`Agent::run` 创建 span 后，提取其上下文作为后续调用的 `parent_context`：

```moonbit
let span = tracer.build(builder)
let parent_context = span.context()
```

该 `parent_context` 被传递给：
- `client.chat(messages, tools, parent_context~)`
- `execute_tool(name, arguments, parent_context~)`

从而在 Jaeger 中形成完整的调用树。

### 2.3 结束 Span

循环结束后，根据结果设置状态和属性：

| 场景 | 状态 | 附加属性 |
|---|---|---|
| 正常结束 | `Status::ok()` | `agent.turn.actual_turns`、`agent.turn.tool_call_count`、`agent.turn.output` |
| 达到最大 tool turn 限制 | `Status::error("max_tool_turns_reached")` | 同上 |

---

## 3. LLM 请求（`Client::chat`）

**Span 名称**：`gen_ai.chat`

**文件位置**：`llm.mbt:138`

**SpanKind**: `Client`

该 Span 遵循 OpenTelemetry GenAI semantic conventions，覆盖一次完整的 LLM HTTP 请求。

### 3.1 请求侧属性

| 属性名 | 来源 |
|---|---|
| `gen_ai.operation.name` | 固定值 `"chat"` |
| `gen_ai.provider.name` | `self.provider_name` |
| `gen_ai.request.model` | `self.model` |
| `gen_ai.request.max_tokens` | `self.max_tokens` |
| `gen_ai.input.messages` | 当 `capture_content=true` 时记录完整输入消息 JSON |

### 3.2 响应侧属性

| 属性名 | 来源 |
|---|---|
| `gen_ai.usage.input_tokens` | `usage.prompt_tokens` |
| `gen_ai.usage.output_tokens` | `usage.completion_tokens` |
| `gen_ai.response.id` | 响应 `id` |
| `gen_ai.response.model` | 响应 `model` |
| `gen_ai.response.finish_reasons` | `finish_reason` |
| `gen_ai.output.messages` | 当 `capture_content=true` 时记录输出消息 JSON |

### 3.3 错误处理

当 HTTP 状态码非 200 时：

```moonbit
span.set_status(@trace.Status::error(description=Some("HTTP {code}")))
span.add_event("gen_ai.client.operation.exception", attributes=[
  @otel.KeyValue::new("exception.type", String(response.code.to_string())),
  @otel.KeyValue::new("exception.message", String("HTTP \{response.code}")),
])
span.end()
```

正常返回时设置 `Status::ok()` 并结束 span。

---

## 4. 工具执行（`execute_tool`）

**Span 名称**：`execute_tool {name}`（如 `execute_tool get_weather`）

**文件位置**：`agent.mbt:153`

**SpanKind**: `Internal`

### 4.1 属性

| 属性名 | 说明 |
|---|---|
| `gen_ai.tool.name` | 工具名称 |
| `gen_ai.tool.call.arguments` | 工具调用参数 JSON |
| `gen_ai.tool.call.result` | 工具执行结果 JSON |

### 4.2 状态

| 场景 | 状态 |
|---|---|
| 工具名未注册 | `Status::error("Unknown tool: ...")` |
| 执行结果包含 `"error"` | `Status::error("tool returned error")` |
| 执行成功 | `Status::ok()` |

---

## 5. 父子 Span 传递机制

所有关键异步函数都接受可选的 `parent_context` 参数：

```moonbit
pub async fn Client::chat(
  ...,
  parent_context? : @context.Context = @context.Context::empty(),
) -> LLMResponse

pub async fn execute_tool(
  name : String,
  arguments : String,
  parent_context? : @context.Context = @context.Context::empty(),
) -> String
```

内部通过 `tracer.build_with_context(builder, parent_context)` 创建子 span，保证 Trace 链路的连续性。

在 Jaeger 中可观察到如下调用树：

```
agent.turn
├── gen_ai.chat
│   └── execute_tool get_weather
│   └── execute_tool lookup_city
└── gen_ai.chat
```

---

## 6. 当前未插桩的环节

以下模块目前尚未添加业务级 Span，可根据需要扩展：

| 模块 | 文件 | 说明 |
|---|---|---|
| Settings 加载 | `settings.mbt` | 环境变量 / `.env` 读取，可补充 `settings.load` span |
| Telemetry 初始化 | `telemetry.mbt` | Provider/Exporter 构建，可补充 `telemetry.init` span |
| 工具注册 | `tools.mbt` | 静态工具定义，通常无需插桩 |
| ID 生成器 | `cmd/main/otel_id_generator.mbt` | 无业务语义，通常无需插桩 |

---

## 7. 相关文件

| 文件 | 职责 |
|---|---|
| `agent.mbt` | `agent.turn`、`gen_ai.tool.execution` span |
| `llm.mbt` | `gen_ai.chat` span及 GenAI semantic attributes |
| `telemetry.mbt` | OpenTelemetry provider、resource、exporter 初始化 |
| `cmd/main/otel_id_generator.mbt` | 进程唯一的随机 Trace/Span ID 生成器 |
| `cmd/main/main.mbt` | 全局 tracer provider 初始化、REPL 主循环、force_flush/shutdown |
