# agent-observability

本项目是一个基于 MoonBit 语言实现的 AI Agent，目标是对 Agent 的核心运行链路进行 OpenTelemetry 插桩，暴露可观测性数据（trace、span、event）。

**当前状态**：早期实现阶段。设计文档（`agent_implementation_prompt.md`）规划了 4 个模块（DialogueEngine、LLMGateway、ToolRouter、TaskScheduler）和一套自研 OTel SDK。

已实现：
- `LLMGateway`（`llm.mbt`）：完整的 HTTP 调用、Tool Call 检测与解析、多轮对话消息累积。
- `ToolRouter`（`tools.mbt`）：工具注册与执行框架，含 `get_weather`（mock）和 `execute_command`（安全受限的系统命令执行）两个工具。
- `DialogueEngine`（`cmd/main/main.mbt`）：REPL 主循环支持连续对话上下文和自动 Tool Call 闭环。

尚未实现：OpenTelemetry 插桩、TaskScheduler。

## 技术栈

| 层级 | 技术 |
|---|---|
| 语言 | MoonBit |
| 构建工具 | `moon` CLI + `moonc` 编译器 |
| 运行时 | `moonbitlang/async` — 原生异步运行时（协程、事件循环、HTTP、FS） |
| 构建目标 | Native（`moon.mod` 中 `preferred_target = "native"`） |
| LLM 提供商 | StepFun API (`api.stepfun.com/v1/chat/completions`) |
| 可观测性 | 规划中（OpenTelemetry），尚未实现 |

## 项目结构

```
agent-observability/
├── moon.mod                    # MoonBit 模块清单（模块名、版本、依赖）
├── moon.pkg                    # 根包配置（llm.mbt / tools.mbt 的导入声明）
├── llm.mbt                     # 核心库：LLMGateway（Tool、Message、ToolCall、LLMResponse、llm_request）
├── tools.mbt                   # 核心库：ToolRouter（工具定义、execute_tool、安全命令执行）
├── cmd/
│   └── main/
│       ├── moon.pkg            # 可执行包配置（is-main: true）
│       └── main.mbt            # 入口：REPL 主循环 + 异步测试
├── agent_implementation_prompt.md  # 设计规格说明书（中文）
├── README.md                   # 项目标题（当前仅一行）
├── .env                        # 环境变量（STEPFUN_API_KEY）
└── .mooncakes/                 # moon 下载的外部依赖缓存
```

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
# 需要设置 STEPFUN_API_KEY
export STEPFUN_API_KEY=your_key_here
# 或者写入 .env 文件
echo "STEPFUN_API_KEY=your_key_here" > .env

# 运行 REPL
moon run cmd/main
```

## 开发约定

- 使用 `moonbitlang/async` 提供的异步原语（`async fn`、 `@http`、 `@fs`、 `@process`）。
- 优先使用结构化类型（`struct Message`、`struct ToolCall`）而非裸 JSON，便于后续插桩。
- 工具执行安全：execute_command 拒绝 rm / mv / cp 等危险命令。
- API Key 读取优先级：`.env` 文件 > 环境变量。
