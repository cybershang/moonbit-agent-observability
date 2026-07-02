# agent-observability

本项目是一个基于 MoonBit 语言实现的 AI Agent，目标是对 Agent 的核心运行链路进行 OpenTelemetry 插桩，暴露可观测性数据（trace、span、event）。

**当前状态**：早期实现阶段。设计文档规划了 3 个核心模块（DialogueEngine、LLMGateway、ToolRouter）。

已实现：
- `LLMGateway`（`llm.mbt`）：完整的 HTTP 调用、Tool Call 检测与解析、多轮对话消息累积。
- `ToolRouter`（`tools.mbt`）：工具注册与执行框架，含 `get_weather`（mock）和 `execute_command`（安全受限的系统命令执行）两个工具。
- `DialogueEngine`（`cmd/main/main.mbt`）：REPL 主循环支持连续对话上下文和自动 Tool Call 闭环。
- OpenTelemetry 插桩（`agent.mbt`、`telemetry.mbt`）：基于 `moonbit-community/opentelemetry` 对 Agent 运行链路进行 trace/span 埋点，支持 OTLP/HTTP 导出到本地 Collector 或任意可配置端点。

## 技术栈

| 层级 | 技术 |
|---|---|
| 语言 | MoonBit |
| 构建工具 | `moon` CLI + `moonc` 编译器 |
| 运行时 | `moonbitlang/async` — 原生异步运行时（协程、事件循环、HTTP、FS） |
| 构建目标 | Native（`moon.mod` 中 `preferred_target = "native"`） |
| LLM 提供商 | StepFun API (`api.stepfun.com/v1/chat/completions`) |
| 可观测性 | OpenTelemetry（基于 `moonbit-community/opentelemetry`，OTLP/HTTP 导出） |

## 项目结构

```
agent-observability/
├── moon.mod                    # MoonBit 模块清单（模块名、版本、依赖）
├── moon.pkg                    # 根包配置（llm.mbt / tools.mbt 等的导入声明）
├── agent.mbt                   # Agent 核心：对话轮次、工具调用闭环、OpenTelemetry 埋点
├── llm.mbt                     # 核心库：LLMGateway（Tool、Message、ToolCall、LLMResponse、llm_request）
├── tools.mbt                   # 核心库：ToolRouter（工具定义、execute_tool、安全命令执行）
├── settings.mbt                # 应用配置（Settings、环境变量 / .env 读取）
├── telemetry.mbt               # OpenTelemetry 初始化（init_telemetry：resource、exporter、provider）
├── llm_test.mbt                # 异步测试
├── cmd/
│   └── main/
│       ├── moon.pkg            # 可执行包配置（is-main: true）
│       ├── main.mbt            # 入口：REPL 主循环
│       └── otel_id_generator.mbt  # 进程唯一的随机 Trace/Span ID 生成器
├── agent-telemetry/            # 内嵌的 OpenTelemetry 插桩库（独立模块 cybershang/agent-telemetry）
│   ├── lib.mbt                 # provider / tracer / span 生命周期辅助函数
│   ├── agent.mbt               # agent.turn span 辅助函数
│   ├── genai.mbt               # GenAI 语义约定 span 辅助函数
│   ├── tool.mbt                # tool execution span 辅助函数
│   └── ...
├── agent_implementation_prompt.md  # 设计规格说明书（中文）
├── README.md                   # 项目说明
├── .env                        # 环境变量（LLM_API_KEY、OTEL_EXPORTER_OTLP_ENDPOINT 等）
└── .mooncakes/                 # moon 下载的外部依赖缓存
```

## 双库开发模式

本项目采用**双库同仓开发**：

- **Agent 应用**在 `agent-observability/` 根目录下开发，模块名为 `cybershang/agent-observability`。
- **插桩库**在 `agent-observability/agent-telemetry/` 子目录下开发，模块名为 `cybershang/agent-telemetry`。

`agent-observability` 通过 `moon.mod` 依赖 `cybershang/agent-telemetry`。本地开发时，子目录 `agent-telemetry/` 作为工作区成员被优先使用；发布时，子目录中的模块单独发布到 mooncakes.io，版本号由它自己的 `agent-telemetry/moon.mod` 决定。

发布 `agent-telemetry` 时，在**独立的 GitHub 仓库** `cybershang/agent-telemetry` 中打 tag 触发 publish action，而不是在 `agent-observability` 仓库中打 tag。

## 构建与测试

### 构建

```bash
# 默认构建 native debug 目标
moon build

# 检查类型（不生成二进制）
moon check
```

### 测试

```bash
# 运行所有 async test
moon test
```

### 运行

```bash
# 需要设置 LLM_API_KEY
export LLM_API_KEY=your_key_here
# 或者写入 .env 文件
cat > .env <<EOF
LLM_API_KEY=your_key_here
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
EOF

# 运行 REPL
moon run cmd/main
```

## 开发约定

- **每次修改代码后必须运行 `moon fmt`**，确保代码格式一致后再提交。
- 使用 `moonbitlang/async` 提供的异步原语（`async fn`、 `@http`、 `@fs`、 `@process`）。
- 优先使用结构化类型（`struct Message`、`struct ToolCall`）而非裸 JSON，便于后续插桩。
- 工具执行安全：execute_command 拒绝 rm / mv / cp 等危险命令。
- 环境变量读取优先级：进程环境变量 > `.env` 文件 > 默认值。
- OTLP 端点可通过 `OTEL_EXPORTER_OTLP_ENDPOINT` 配置，默认 `http://localhost:4318`。

## 命名约定

- **禁止在类型名和函数名中使用模糊后缀/前缀**，例如 `Handle`、`Helper`、`Manager`、`Util`、`Info`、`Data`、`Processor` 等。这些词汇掩盖了真实的职责，使代码意图不清。
- 类型名应直接表达其聚合的内容或承担的角色，例如 `TelemetryProviders`（一组 provider）、`SpanExporter`（导出 span 的东西）、`BatchConfig`（批处理配置）。
- 函数名应使用动词或动词短语，直接描述行为，例如 `record_llm_latency`、`emit_log`、`spawn_background_tasks`、`build_resource`。
- 讨论设计方案时，使用**具体的类型名或函数名**，避免用“helper”“handle”“wrapper”这类概括性词汇指代代码实体。

## 测试理念

本项目测试坚持**真实环境优先**，反对为了通过测试而过度使用 mock。

- **用真家伙跑**：集成测试和冒烟测试优先调用真实 LLM API、真实工具执行和真实 OTLP 导出链路。只有在单元测试层面才使用纯内存对象或固定返回值。
- **不怕失败**：探索 AI 本身就是不断试错的过程。测试失败说明目标够高、场景够真实，而不是问题。我们要做的是让失败快速暴露、快速定位，而不是把它藏进 mock 里。
- **拒绝舒适圈**：如果所有测试都能在隔离环境里稳过，那说明测试覆盖的可能是已经被驯服的子集，没有真正验证系统的端到端行为。
- **冒烟测试必须端到端**：每次关键改动后，至少运行一次从用户输入 → LLM 调用 → Tool 执行 → 最终回复的完整链路，确保核心路径没有回归。

## 已知编译器警告

运行 `moon check` 时可能会看到若干 `unused_package` 警告，这些警告**不影响功能**，原因如下：

### 1. `moonbitlang/async` 报 unused

`moonbitlang/async` 包提供了 `async fn` / `async test` 语法支持。代码中确实使用了 `async fn`（如 `agent.mbt`）和 `async test`（如 `llm_test.mbt`），但 MoonBit 编译器的 `unused_package` 检测机制只看是否有 `@async.xxx` 形式的**显式调用**，不把 `async fn` 关键字本身算作"使用"。这是一个编译器行为特性，包本身**必须导入**。

### 2. 测试依赖报 unused（`@stdio`、`@debug`、`@sdk`、`@print`）

这些包在 `llm_test.mbt` 中被使用（如 `@stdio.stdout.write`、`@debug.debug`、`@sdk.tracer_provider_builder`、`@print.SpanExporter::new`），但 MoonBit 的 `moon.pkg` 是**包级别**的配置，测试文件和源码共享同一个 `moon.pkg`。编译器在检查"库包"的导入时，不把测试文件中的使用算作"库的使用"，因此报 unused。

MoonBit 目前不支持：
- 在单个 `.mbt` 文件内单独导入包
- 将测试文件放到独立子包（子包无法访问父包的私有成员）
- `test` 导入块来分离测试依赖

因此这些警告在当前 MoonBit 包结构下**无法消除**，CI 中已移除 `--deny-warn` 以避免因此失败。

## 远程仓库

### agent-observability（Agent 应用）

| 名称 | 地址 |
|---|---|
| `origin` (Gitlink) | `git@code.gitlink.org.cn:yingjie/agent-observability.git` |
| `github` | `git@github.com:cybershang/moonbit-agent-observability.git` |

### agent-telemetry（插桩库）

| 名称 | 地址 |
|---|---|
| `github` | `git@github.com:cybershang/agent-telemetry.git` |

`agent-telemetry` 的发布在独立仓库 `cybershang/agent-telemetry` 中进行，通过 push tag `v*` 触发 `.github/workflows/publish.yml` 发布到 mooncakes.io。

### 日常推送命令

```bash
# 推送到 GitHub
git push github master

# 推送到 Gitlink
git push origin master

# 同时推送到两个远程
git push origin master && git push github master
```
