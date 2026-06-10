# agent-observability

基于 MoonBit 实现的精简 AI Agent，演示 Agent 核心运行链路的 OpenTelemetry 可观测性插桩。

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

```
┌─────────────────────────────────────────────────────────────┐
│                        User / API                            │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  ┌────────────── Agent ───────────────────────┐             │
│  │  • 多轮对话状态管理                           │             │
│  │  • 上下文窗口累积                             │             │
│  │  • 自动 Tool Call 闭环（最多 10 轮）          │             │
│  │  • 工具执行记录返回                           │             │
│  └──────────────────┬──────────────────────────┘             │
│                     │                                        │
│  ┌──────────────────▼──────────────────────────┐             │
│  │  ┌────────── Client ──────────┐             │             │
│  │  │  • 通用 GenAI 提供商封装     │             │             │
│  │  │  • HTTP RPC 调用            │             │             │
│  │  │  • 请求/响应 JSON 序列化     │             │             │
│  │  │  • OpenTelemetry GenAI 插桩  │             │             │
│  │  └──────────────┬─────────────┘             │             │
│  │                 │                            │             │
│  │  ┌──────────────▼───────────────┐           │             │
│  │  │  GenAI Provider API          │           │             │
│  │  │  （默认 StepFun API）         │           │             │
│  │  └──────────────────────────────┘           │             │
│  └─────────────────────────────────────────────┘             │
│                     │                                        │
│  ┌──────────────────▼──────────────────────────┐             │
│  │  ┌────────── ToolRegistry ────┐            │             │
│  │  │  • 工具注册与路由            │            │             │
│  │  │  • 参数解析与执行            │            │             │
│  │  │  • 安全策略（命令白名单）     │            │             │
│  │  └──────────────┬──────────────┘            │             │
│  │                 │                            │             │
│  │  ┌──────────────▼──────────────┐            │             │
│  │  │  External Tools              │            │             │
│  │  │  • get_weather (mock)        │            │             │
│  │  │  • execute_command (safe)    │            │             │
│  │  └─────────────────────────────┘            │             │
│  └─────────────────────────────────────────────┘             │
│                                                              │
│  [OpenTelemetry]  — 已实现（trace/span/event 插桩）           │
└─────────────────────────────────────────────────────────────┘
```

## 核心模块

| 模块 | 文件 | 职责 |
|---|---|---|
| **Agent** | `agent.mbt` | 对话编排：维护消息历史、自动 tool call 循环、返回结构化结果 |
| **Client** | `llm.mbt` | 通用 GenAI 客户端：封装 HTTP 调用、管理消息类型、OTel GenAI 插桩 |
| **ToolRegistry** | `tools.mbt` | 工具定义表，供 Agent 注册到 LLM |
| **Settings** | `settings.mbt` | `.env` 文件读取辅助 |
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

### 运行

```bash
# 检查类型
moon check

# 运行 REPL
moon run cmd/main
```

### 测试

```bash
# 运行所有 async test
moon test
```

## Agent Observability

当前项目已实现针对 **LLM Proxy（`Client::chat`）** 的 OpenTelemetry 插桩，覆盖以下 GenAI 语义约定：

- **Span**：`gen_ai.chat`
  - `gen_ai.operation.name` = `chat`
  - `gen_ai.provider.name` = 配置的提供商名称
  - `gen_ai.request.model` = 当前请求模型
  - `gen_ai.request.max_tokens` = 最大 token 数
  - `gen_ai.usage.input_tokens` / `gen_ai.usage.output_tokens` = 用量（从响应解析）
  - `gen_ai.response.finish_reasons` = 响应结束原因
- **Events**：
  - `gen_ai.tool.call`：记录 LLM 请求的 tool call ID 与名称
  - `gen_ai.user.message` / `gen_ai.assistant.message`：当 `CAPTURE_CONTENT=true` 时记录消息内容

通过设置 `OTEL_STDOUT=true` 可在 stdout 查看 trace 输出；设置 `CAPTURE_CONTENT=true` 可开启消息内容采集（默认关闭，避免敏感信息泄露）。

Agent 编排层（`Agent::run`）与工具执行层的 trace 插桩尚未实现，后续计划补充：
- Agent turn 级别的 span
- Tool 执行 span（含执行耗时、结果状态）
- 多轮对话状态事件

## 项目结构

```
agent-observability/
├── moon.mod                    # MoonBit 模块清单
├── moon.pkg                    # 根包导入声明
├── llm.mbt                     # Client：类型定义 + HTTP 封装 + OTel 插桩
├── llm_test.mbt                # Client 白盒测试
├── agent.mbt                   # Agent：对话编排 + tool 执行
├── tools.mbt                   # ToolRegistry：工具定义
├── settings.mbt                # .env 读取辅助
├── .env.example                # 配置模板
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

## 许可证

本项目采用 [木兰宽松许可证，第 2 版](http://license.coscl.org.cn/MulanPSL2)（Mulan PSL v2）开源许可。
Copyright (c) 2026 Yingjie Shang
