# MoonBit 智能体可观测方案 — 结项报告

## 项目概述

本项目产出 **两个可交付物**：

| 交付物 | 模块名 | 说明 |
|---|---|---|
| **Agent 示例应用** | `cybershang/agent-observability` | 基于 MoonBit 的 AI Agent，演示完整的对话、工具调用、OTel 插桩链路 |
| **可复用插桩库** | `cybershang/agent-telemetry` | 将 OTel 初始化、tracer 管理、span 生命周期以及 GenAI/Tool/Agent 语义约定封装成独立 MoonBit 包，**已发布到 mooncakes.io** |

两个项目本身就是一个完整的叙事：**先通过实战造一个 Agent，从 0 到 1 积累插桩经验，再将其中的通用能力沉淀为独立库，让社区可以直接复用。**

---

## 核心贡献：agent-telemetry

### 它解决了什么问题

MoonBit 社区此前**没有任何**面向 AI Agent 可观测性的基础设施。如果开发者想为自己的 Agent 接入 OpenTelemetry，需要：

1. 理解 OTel SDK 的 provider / tracer / span / attribute 等底层概念
2. 手动处理 SDK 的初始化与导出配置
3. 手动拼接 GenAI 语义约定的属性键值对（如 `gen_ai.operation.name`、`gen_ai.request.model`、`gen_ai.tool.name` 等）
4. 确保 trace context 在异步调用链中正确传递
5. 编写重复的 span 生命周期代码（start → set attributes → end）

**`agent-telemetry` 将上述所有负担封装为几行语义化的函数调用。**

### 对比：为什么不能做到"一行代码自动插桩"

在 Python、JavaScript 等**动态语言**中，OpenTelemetry 可以通过 **monkey patching** 在运行时替换 HTTP 客户端、函数调用等核心方法，实现零侵入自动插桩：

```python
# Python: 一行代码自动插桩所有 LLM 调用
from opentelemetry.instrumentation.openai import OpenAIInstrumentor
OpenAIInstrumentor().instrument()
```

**MoonBit 是编译型语言**，没有运行时动态替换方法的能力（类似于 Go、Rust、Java 等）。这意味着插桩必须是**显式（explicit）** 的——开发者在每个需要记录 trace 的地方主动调用插桩函数。

这在设计上其实是一种**取舍**：
- 动态语言的"一行代码自动插桩"方便，但代价是隐式的性能开销（所有调用都被 wrap）、不可预测的行为（可能 hook 到不该 hook 的地方）、以及调试困难（堆栈被框架污染）。
- 编译型语言的显式插桩虽然需要多写几行，但**调用链路完全透明、性能开销精确可控、行为可预测**。

**`agent-telemetry` 做的就是将这"几行代码"压缩到最少，把 GenAI 语义约定标准化，让开发者不需要了解 OTel 底层细节就能写出符合行业标准的插桩代码。**

### 使用对比

**如果不使用 agent-telemetry**，开发者需要这样写：

```moonbit
// 手动拼接 OTel 原生 API
let tracer = @otel.tracer("my-agent/llm", version=Some("0.1.0"))
let builder = tracer.span_builder("gen_ai.chat")
builder.span_kind = Some(@trace.Client)
let attrs = [
  @otel.KeyValue::new("gen_ai.operation.name", String("chat")),
  @otel.KeyValue::new("gen_ai.provider.name", String(provider)),
  @otel.KeyValue::new("gen_ai.request.model", String(model)),
  @otel.KeyValue::new("gen_ai.request.max_tokens", Int64(max_tokens)),
]
let span = builder.start_with_attributes(tracer, attrs)
// ... 业务代码 ...
span.set_attribute(@otel.KeyValue::new("gen_ai.response.id", String(id)))
span.set_status(@trace.Status::ok())
span.end()
```

**使用 agent-telemetry**：

```moonbit
let tracer = @telemetry.tracer("my-agent/llm")
let span = @telemetry.start_chat_span(
  tracer, provider_name="stepfun", model="step-3.7-flash", max_tokens=1024,
)
// ... 业务代码 ...
@telemetry.set_response(span, response_json)
@telemetry.end_span(span)
```

**节省的代码不仅仅是行数，更是心智负担**——开发者不需要知道 `gen_ai.operation.name` 这个字符串、不需要知道 SpanKind 是什么、不需要知道如何设置状态码。所有这些都由库在背后按 OpenTelemetry GenAI 语义约定处理。

### 已实现的 API 全景

#### Provider 生命周期（`lib.mbt`）

| 函数 | 作用 |
|---|---|
| `TelemetryConfig::new()` | 创建配置（service name） |
| `init_telemetry()` | 初始化所有 provider（trace / metrics / logs） |
| `init_from_env()` | 从环境变量零配置初始化 |
| `tracer()` / `meter()` / `logger()` | 懒加载获取对应 provider |
| `spawn_background_tasks()` | 启动 metrics / logs 后台导出协程 |
| `force_flush()` / `shutdown()` | 优雅关闭 |

#### GenAI 语义约定（`genai.mbt`）

| 函数 | 设置的标准 OTel 属性 |
|---|---|
| `start_chat_span()` | `gen_ai.operation.name`、`gen_ai.provider.name`、`gen_ai.request.model`、`gen_ai.request.max_tokens`、`server.address` |
| `set_response()` | `gen_ai.response.id`、`gen_ai.response.model`、`gen_ai.response.finish_reason` |
| `set_usage()` | `gen_ai.usage.input_tokens`、`gen_ai.usage.output_tokens` |
| `set_http_error()` | `error.type` + event: `llm.http_error` |

#### Tool 执行（`tool.mbt`）

| 函数 | 设置的标准 OTel 属性 |
|---|---|
| `start_tool_span()` | `gen_ai.tool.name`、`gen_ai.tool.call.arguments` |
| `set_tool_result()` | `gen_ai.tool.call.result` + Status |
| `set_tool_error()` | 错误描述 + Status |

#### Agent 编排（`agent.mbt`）

| 函数 | 设置的属性 |
|---|---|
| `start_agent_turn_span()` | `agent.turn.input`、`agent.turn.max_tool_turns` |
| `set_turn()` | `agent.turn.actual_turns`、`agent.turn.tool_call_count`、`agent.turn.output` |
| `set_turn_exhausted()` | 标记超轮次终止 |

#### Metrics（`metrics.mbt`）

| 函数 | 指标 |
|---|---|
| `record_llm_latency()` | `gen_ai.client.operation.duration`（Histogram） |
| `record_usage()` | `gen_ai.client.token.usage`（Histogram） |
| `record_tool_call()` | `agent.tool.calls_total`（Counter） |
| `record_turn()` | `agent.turn.total`（Counter） |

#### Logs（`logs.mbt`）

| 函数 | 作用 |
|---|---|
| `emit_log()` / `log_info()` / `log_warn()` / `log_error()` | 结构化日志，支持 trace context 关联 |
| `log_conversation_message()` | 对话消息专用日志路由 |

---

## Agent 示例应用

在插桩库之上，项目提供了一个完整的 Agent 示例应用，展示：

- 多轮对话与上下文累积
- 自动 Tool Call 闭环（LLM 请求 → 检测 tool_calls → 执行工具 → 结果返回 LLM → 最终回复）
- 真实工具：和风天气查询（`get_weather`、`lookup_city`）+ 安全受限的命令执行
- 完整的 OTel trace 结构：

```
agent.turn
├── gen_ai.chat              # 第 1 轮：用户输入 → LLM 返回 tool_calls
├── gen_ai.tool.execution    # 工具执行（如 get_weather）
└── gen_ai.chat              # 第 2 轮：工具结果 → LLM 返回最终回复
```

### 可观测后端集成

项目提供了完整的 GreptimeDB + Grafana 部署配置（`deploy/greptime/`）：

- `docker-compose.yml` — GreptimeDB + Grafana 一键部署
- `flows.sql` / `pricing.sql` — OTel trace 管道配置 + 模型定价表
- Grafana 面板（`genai.json`）— 可观测性仪表盘，展示 LLM 调用耗时、token 消耗、工具调用统计等

---

## 技术边界与说明

### 为什么不需要"更多功能"

| 常见期望 | 说明 |
|---|---|
| "为什么不能自动插桩所有函数？" | MoonBit 是编译型语言，不支持 monkey patching。这是编译型语言的共性（Go、Rust、Java 同理），而非项目局限 |
| "为什么不是完整 OTel 实现？" | `agent-telemetry` **不是** OTel SDK 的替代品，而是**在 `moonbit-community/opentelemetry` 之上的一层语义封装**。OTel SDK 本身已经有社区维护 |
| "为什么指标只有 4 个？" | 指标按 Agent 场景的最小有用集设计：LLM 延迟、token 消耗、工具调用次数、对话轮次。开发者可根据需要自行扩展 |
| "后面还会加什么？" | 见下方"展望" |

### 展望（非当前实现，但设计已预留扩展点）

- **非交互式 Ask 模式**（已在 `docs/superpowers/specs/` 中有设计文档）：将 Agent 作为纯函数调用，适合 CI/CD 集成
- **工具调用统计面板**（已在 `docs/superpowers/specs/` 中有设计文档）：Grafana 中展示各工具调用频率、成功率、平均耗时

---

## 数据说话

| 指标 | 数值 |
|---|---|
| MoonBit 源码行数 | ~5,800 行（主项目 ~3,900 + 插桩库 ~1,900） |
| 源文件数 | 25 个 `.mbt` 文件 |
| 测试总数 | 77 个（76 通过，1 个需 LLM API Key） |
| `moon check` | ✅ 通过，无类型错误 |
| CI | ✅ GitHub Actions（check / fmt / test / info） |
| mooncakes.io 发布 | ✅ `cybershang/agent-telemetry@0.1.4` |
| 提交历史 | 178 次提交，自 2026-05-29 起持续活跃 |
| 部署配置 | GreptimeDB + Grafana 一键 Docker Compose |

---

## 总结

本项目不是在造一个"更大"的框架，而是在解决一个**具体且真实的问题**：**MoonBit 生态中缺少面向 AI Agent 的可观测性基础设施**。

`agent-telemetry` 的核心价值不是代码行数，而是**将 OpenTelemetry GenAI 语义约定带到 MoonBit 世界**，让该生态中的 Agent 开发者能以最小的学习成本和代码量获得符合行业标准的可观测性能力。

这是一个**基础设施类**的项目——它的贡献不在功能的"多"，而在**抽象层次的正确性**和**理念的传播**——帮助 MoonBit 开发者了解和实践 Agent 可观测性。
