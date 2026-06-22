# agent-observability

[![Check & Test](https://github.com/cybershang/moonbit-agent-observability/actions/workflows/ci.yml/badge.svg)](https://github.com/cybershang/moonbit-agent-observability/actions/workflows/ci.yml)

基于 MoonBit 实现的精简 AI Agent，演示 Agent 核心运行链路的 OpenTelemetry 可观测性插桩。

本项目同时包含可复用的 `agent-telemetry` 库：把原本散落在业务代码中的 OTel 初始化、tracer 管理、span 生命周期以及 GenAI/Tool/Agent 语义约定封装成独立 MoonBit 包，方便其他 Agent 项目直接引用。

## 演示Demo
### 实现了基础的交互和LLM插桩
视频：https://www.bilibili.com/video/BV1n4EZ61EmU

Agent基础交互，包含多轮对话和工具调用:
<img src="https://img.yingjie.dev/file/yingjie-blog/WindowsTerminal_BsUDSmrWHe_1781130355777_38jqds.avif"/>

使用OTEL_STDOUT开启遥测信号回显：
<img src="https://img.yingjie.dev/file/yingjie-blog/WindowsTerminal_nJ6LiuPjdN_1781130454369_0k4jcv.avif"/>

使用CAPTURE_CONTENT开启对用户输入和LLM响应的采集：
<img src="https://img.yingjie.dev/file/yingjie-blog/WindowsTerminal_6gHMJ2j9Fm_1781130539691_rc140m.avif"/>


## Agent架构

```mermaid
flowchart TD
    User["👤 User / API"]

    subgraph Agent["🧠 Agent"]
        direction TB
        A1["多轮对话状态管理"]
        A2["上下文窗口累积"]
        A3["自动 Tool Call 闭环（≤10 轮）"]
        A4["工具执行记录返回"]
    end

    subgraph Client["🔌 Client（LLMGateway）"]
        C1["通用 GenAI 提供商封装"]
        C2["HTTP RPC 调用"]
        C3["请求 / 响应 JSON 序列化"]
        C4["OpenTelemetry GenAI 插桩"]
    end

    API["☁️ GenAI Provider API<br/>（默认 StepFun）"]

    subgraph TR["🔧 ToolRegistry"]
        T1["工具注册与路由"]
        T2["参数解析与执行"]
        T3["安全策略（命令白名单）"]
    end

    subgraph Tools["🛠️ External Tools"]
        TW["🌤️ get_weather / lookup_city（QWeather）"]
        TC["💻 execute_command（安全受限）"]
    end

    OTel["📊 OpenTelemetry<br/>trace / span / event 插桩"]

    User --> Agent
    Agent --> Client
    Client --> API
    Agent --> TR
    TR --> Tools

    OTel -.->|全链路插桩| Agent
    OTel -.->|GenAI 语义约定| Client
    OTel -.-> TR
```

## 核心模块

| 模块 | 文件 | 职责 |
|---|---|---|
| **Agent** | `agent.mbt` | 对话编排：维护消息历史、自动 tool call 循环、返回结构化结果 |
| **Client** | `llm.mbt` | 通用 GenAI 客户端：封装 HTTP 调用、管理消息类型、OTel GenAI 插桩 |
| **ToolRegistry** | `tools.mbt` | 工具定义表，供 Agent 注册到 LLM |
| **Settings** | `settings.mbt` | 集中管理所有运行时配置：`Settings` struct + `from_env()` |
| **Telemetry Lib** | `agent-telemetry/` | 可复用插桩库：provider 初始化、tracer、GenAI/Tool/Agent 语义 helper |
| **REPL 入口** | `cmd/main/main.mbt` | 配置加载、初始化 OTel、启动交互循环 |

## 快速开始

### 依赖

- [MoonBit](https://www.moonbitlang.com/) 工具链
- Linux 系统需安装 `build-essential`（提供 C 头文件用于 native 编译）

### 配置

复制示例配置并编辑：

```bash
cp .env.example .env
# 编辑 .env，填入你的 API Key
```

支持的配置项（环境变量或 `.env` 文件均可）：

| 变量 | 说明 | 默认值 |
|---|---|---|
| `LLM_API_KEY` | GenAI 提供商 API Key | 必填 |
| `LLM_PROVIDER` | 提供商标识（用于 OTel） | `stepfun` |
| `LLM_BASE_URL` | 聊天补全 API 基础 URL | `https://api.stepfun.com/v1` |
| `LLM_MODEL` | 模型名称 | `step-3.7-flash` |
| `LLM_MAX_TOKENS` | 每次请求最大 token 数 | `1024` |
| `AGENT_MAX_TOOL_TURNS` | Agent 自动 tool call 最大轮数 | `10` |
| `OTEL_STDOUT` | 是否输出 OTel trace 到 stdout | `false` |
| `CAPTURE_CONTENT` | 是否在 span 中采集用户/助手消息内容 | `false` |
| `QWEATHER_TOKEN` | 和风天气 JWT Token（新 Platform API） | 必填 |
| `QWEATHER_API_KEY` | 和风天气旧版 Web API Key（作为 `QWEATHER_TOKEN` 的 fallback） | - |
| `QWEATHER_API_HOST` | 和风天气 API 主机，标准订阅用 `https://api.qweather.com`，开发版用 `https://devapi.qweather.com` | `https://devapi.qweather.com` |

所有配置在运行时被加载到 `Settings` 结构体中，随后传递给 `Client` 与 `Agent`，避免在业务代码中散落环境变量读取逻辑。`QWEATHER_*` 配置由 `tools.mbt` 在工具执行时读取。

### 运行

```bash
# 检查类型
moon check

# 运行 REPL
moon run cmd/main

# 非交互式单次运行（适合 CI / 演示 / 脚本）
moon run cmd/main -- --ask "北京今天天气怎么样？"
```

### 测试

```bash
# 运行所有 async test
moon test
```

## Agent Observability

当前项目已实现 **Agent 全链路**的 OpenTelemetry 插桩，Trace 结构如下：

```
agent.turn                    # Agent 编排层：一次完整的用户交互
├── gen_ai.chat             # 第 1 轮 LLM 调用（返回 tool_calls）
├── gen_ai.tool.execution   # 工具执行（如 get_weather）
└── gen_ai.chat             # 第 2 轮 LLM 调用（返回最终回复）
```

### Span 详情

**`agent.turn`**（Agent 编排层）
- `agent.turn.input` = 用户输入
- `agent.turn.max_tool_turns` = 最大允许轮数
- `agent.turn.actual_turns` = 实际执行轮数
- `agent.turn.tool_call_count` = 本 turn 执行的工具调用次数
- `agent.turn.output` = 最终回复
- 达到轮数上限时 `Status=Error`

**`gen_ai.chat`**（LLM Proxy 层）
- `gen_ai.operation.name` = `chat`
- `gen_ai.provider.name` = 配置的提供商名称
- `gen_ai.request.model` / `gen_ai.request.max_tokens`
- `gen_ai.usage.input_tokens` / `gen_ai.usage.output_tokens`
- `gen_ai.response.id` / `gen_ai.response.model` / `gen_ai.response.finish_reasons`
- `gen_ai.input.messages` / `gen_ai.output.messages`（当 `CAPTURE_CONTENT=true`）

**`gen_ai.tool.execution`**（工具执行层）
- `gen_ai.tool.name` = 工具名称
- `gen_ai.tool.call.arguments` = 调用参数
- `gen_ai.tool.call.result` = 执行结果
- 未知工具或执行出错时 `Status=Error`

通过设置 `OTEL_STDOUT=true` 可在 stdout 查看 trace 输出；设置 `CAPTURE_CONTENT=true` 可开启消息内容采集（默认关闭，避免敏感信息泄露）。

默认情况下，应用通过 **OTLP/HTTP** 将 trace 导出到 `http://localhost:4318`，可直接对接本地 OpenTelemetry Collector。

### 本地可观测性栈

项目提供了最小化的本地 Collector + Jaeger 组合：

```bash
cd deploy/minimum
docker compose up -d
```

启动后：
- OTLP HTTP receiver: `http://localhost:4318`
- OTLP gRPC receiver: `http://localhost:4317`
- Jaeger UI: `http://localhost:16686`

运行 REPL 并导出 trace 到 Collector（保持 `.env` 中 `OTEL_STDOUT=false` 或直接覆盖环境变量）：

```bash
OTEL_STDOUT=false moon run cmd/main
```

发送一条消息后，打开 http://localhost:16686 即可在 Jaeger 中查看 `gen_ai.chat` span 及完整属性。Service 名称为 `agent-observability`（可通过 `OTEL_SERVICE_NAME` 环境变量覆盖）。

Batch Span Processor 针对交互式 REPL 做了调优：
- `max_queue_size=64`
- `max_export_batch_size=16`
- `scheduled_delay_millis=1000`
- `export_timeout_millis=5000`

这样 span 会在 1 秒内或累积 16 条时被批量发送，退出前还会显式 `force_flush()` + `shutdown()`，避免数据丢失。你也可以通过标准环境变量覆盖：
- `OTEL_BSP_MAX_QUEUE_SIZE`
- `OTEL_BSP_MAX_EXPORT_BATCH_SIZE`
- `OTEL_BSP_SCHEDULE_DELAY`
- `OTEL_BSP_EXPORT_TIMEOUT`

Agent 编排层（`Agent::run`）与工具执行层的 trace 插桩已完整实现：
- ✅ **Agent turn 级别 span**（`agent.turn`）：记录输入/输出、实际工具调用轮数、最大允许轮数
- ✅ **Tool 执行 span**（`gen_ai.tool.execution`）：记录工具名称、调用参数、执行结果、错误状态

## `agent-telemetry` 库

仓库中的 `agent-telemetry/` 是一个独立的 MoonBit 包，封装了 Agent/LLM/Tool 场景的 OpenTelemetry 插桩。原 `agent-observability` 应用已改用此库实现。

### 安装

```bash
moon add cybershang/agent-telemetry
```

### 使用示例

#### 一键从环境变量初始化

```moonbit
let provider = @telemetry.init_from_env(
  service_name="my-agent",
  id_generator=@telemetry.ProcessUniqueRandom,
)
```

配合环境变量：

```bash
OTEL_STDOUT=true moon run cmd/main
```

#### 显式选择 exporter

```moonbit
let config = @telemetry.TelemetryConfig::new(service_name="my-agent")
let provider = @telemetry.init_telemetry(
  config,
  @telemetry.Stdout,
  id_generator=@telemetry.ProcessUniqueRandom,
)
```

#### 使用 OTLP exporter

```moonbit
let provider = @telemetry.init_telemetry(
  config,
  @telemetry.Otlp("http://localhost:4318"),
  id_generator=@telemetry.ProcessUniqueRandom,
)
```

#### 使用自定义 exporter / ID generator

```moonbit
let provider = @telemetry.init_telemetry(
  config,
  @telemetry.Custom(my_exporter),
  id_generator=@telemetry.Custom(my_id_generator),
)
```

#### 创建 GenAI chat span

```moonbit
let tracer = @telemetry.tracer("my-agent/llm")
let span = @telemetry.start_chat_span(
  tracer,
  provider_name="stepfun",
  model="step-3.7-flash",
  max_tokens=1024,
)
// ... 发起 HTTP 请求、拿到响应 ...
@telemetry.record_chat_response(span, response_json)
@telemetry.end_span_ok(span)
```

### 提供的语义 helper

| 场景 | 主要函数 | 说明 |
|---|---|---|
| Provider 初始化 | `init_from_env` / `init_telemetry` | 环境变量一键启动；显式选择 exporter 与 `IdGeneratorOption` |
| 通用 span 生命周期 | `start_span` / `end_span` / `end_span_ok` / `end_span_error` | 薄封装，管理 tracer 缓存和 span 状态 |
| LLM chat | `start_chat_span` / `record_chat_usage` / `record_chat_response` / `set_chat_http_error` | 按 OTel GenAI semantic conventions 设置属性 |
| Tool 执行 | `start_tool_span` / `record_tool_result` / `set_tool_error` | 记录工具名、参数、结果、错误 |
| Agent turn | `start_agent_turn_span` / `record_turn_metrics` / `set_turn_max_tool_turns_error` | 记录输入/输出、轮数、工具调用次数 |

> **注意**：`agent-telemetry` 默认目标后端为 `native`，因为 `opentelemetry/otlp` 依赖的 `async/http`、`async/socket` 接口只在 native 后端可用。

## 项目结构

```
agent-observability/
├── moon.mod                    # MoonBit 工作区/模块清单
├── moon.pkg                    # 根包（演示应用）导入声明
├── moon.work                   # 工作区成员声明
├── llm.mbt                     # Client：类型定义 + HTTP 封装（使用 agent-telemetry）
├── llm_test.mbt                # Client 白盒测试
├── agent.mbt                   # Agent：对话编排 + tool 执行（使用 agent-telemetry）
├── agent_test.mbt              # Agent 端到端冒烟测试（真实 LLM API）
├── tools.mbt                   # ToolRegistry：工具定义（使用 agent-telemetry）
├── cmd/main/main.mbt           # 入口：一行 `@telemetry.init_from_env` 完成遥测初始化
├── settings.mbt                # Settings：集中配置管理 + .env 读取辅助
├── agent-telemetry/            # 可复用插桩库（独立 MoonBit 包）
│   ├── moon.mod
│   ├── moon.pkg
│   ├── lib.mbt                 # provider 初始化、tracer 缓存、span 生命周期
│   ├── genai.mbt               # GenAI chat 语义 helper
│   ├── tool.mbt                # Tool execution 语义 helper
│   ├── agent.mbt               # Agent turn 语义 helper
│   └── *_test.mbt              # 库单元测试
├── .env.example                # 配置模板
├── deploy/
│   └── minimum/                # 本地最小化 OTel Collector + Jaeger
│       ├── docker-compose.yml
│       └── otel-collector-config.yml
├── cmd/
│   └── main/
│       ├── moon.pkg            # 可执行包配置
│       └── main.mbt            # REPL 入口
└── AGENTS.md                   # 开发指南与约定
```

## 技术栈

| 层级 | 技术 |
|---|---|
| 语言 | MoonBit |
| 运行时 | `moonbitlang/async` — 原生异步运行时 |
| 构建目标 | Native |
| 默认 LLM 提供商 | StepFun API |
| 可观测性 | OpenTelemetry（已实现） |

## 已知问题

### `moon check` 中的 `unused_package` 警告

运行 `moon check` 时可能会出现若干 `unused_package` 警告，**不影响功能**，原因如下：

1. **`moonbitlang/async` 报 unused**：`async fn` / `async test` 语法需要此包，但编译器只检测 `@async.xxx` 显式调用，不把关键字本身算作"使用"。
2. **测试依赖报 unused**（`@sdk` 等）：这些包在测试文件中使用，但 MoonBit 的 `moon.pkg` 是包级配置，编译器不把测试文件中的使用算作"库的使用"。
3. `agent-telemetry` 包与根应用通过 `moon.work` 组成工作区；根应用导入本地 `cybershang/agent-telemetry` 包。
4. **`agent-telemetry` 默认后端为 native**：`opentelemetry/otlp` 依赖的 `async/http`、`async/socket` 接口只在 native 后端可用，因此库模块声明了 `preferred_target = "native"`。

MoonBit 目前不支持文件级导入或独立的测试子包，因此这些警告在当前结构下无法消除。CI 已移除 `--deny-warn` 以避免因此失败。

## 许可证

本项目采用 [木兰宽松许可证，第 2 版](http://license.coscl.org.cn/MulanPSL2)（Mulan PSL v2）开源许可。
Copyright (c) 2026 Yingjie Shang
