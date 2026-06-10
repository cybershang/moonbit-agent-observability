# agent-observability

基于 MoonBit 实现的精简 AI Agent，演示 Agent 核心运行链路的 OpenTelemetry 可观测性插桩。

## 演示Demo
- 实现了基础的交互和LLM插桩:https://www.bilibili.com/video/BV1n4EZ61EmU

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│                        User / API                            │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  ┌────────────── DialogueEngine ──────────────┐             │
│  │  • 多轮对话状态管理                           │             │
│  │  • 上下文窗口累积                             │             │
│  │  • 自动 Tool Call 闭环                       │             │
│  └──────────────────┬──────────────────────────┘             │
│                     │                                        │
│  ┌──────────────────▼──────────────────────────┐             │
│  │  ┌────────── LLMGateway ────────┐           │             │
│  │  │  • HTTP RPC 封装              │           │             │
│  │  │  • 请求/响应 JSON 序列化       │           │             │
│  │  │  • Tool Call 检测与解析        │           │             │
│  │  └──────────────┬───────────────┘           │             │
│  │                 │                            │             │
│  │  ┌──────────────▼───────────────┐           │             │
│  │  │  StepFun API                 │           │             │
│  │  │  api.stepfun.com/v1/...      │           │             │
│  │  └──────────────────────────────┘           │             │
│  └─────────────────────────────────────────────┘             │
│                     │                                        │
│  ┌──────────────────▼──────────────────────────┐             │
│  │  ┌────────── ToolRouter ───────┐            │             │
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
│  [TaskScheduler]  — 尚未实现                                  │
│  [OpenTelemetry]  — 尚未实现（trace/span/event 插桩）          │
└─────────────────────────────────────────────────────────────┘
```

## 核心模块

| 模块 | 文件 | 职责 |
|---|---|---|
| **DialogueEngine** | `cmd/main/main.mbt` | REPL 主循环，维护对话历史，自动处理多轮 Tool Call |
| **LLMGateway** | `llm.mbt` | 封装 StepFun API 调用，管理 `Message` / `ToolCall` / `LLMResponse` 类型 |
| **ToolRouter** | `tools.mbt` | 工具注册表与安全执行器，含 `get_weather` 和 `execute_command` |

## 快速开始

### 依赖

- [MoonBit](https://www.moonbitlang.com/) 工具链
- Linux 系统需安装 `build-essential`（提供 C 头文件用于 native 编译）

### 运行

```bash
# 设置 API Key
export STEPFUN_API_KEY=your_key_here
# 或写入 .env 文件
echo "STEPFUN_API_KEY=your_key_here" > .env

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

## 项目结构

```
agent-observability/
├── moon.mod                    # MoonBit 模块清单
├── moon.pkg                    # 根包导入声明
├── llm.mbt                     # LLMGateway：类型定义 + HTTP 封装
├── tools.mbt                   # ToolRouter：工具注册 + 安全执行
├── cmd/
│   └── main/
│       ├── moon.pkg            # 可执行包配置
│       └── main.mbt            # REPL 入口 + 异步测试
├── agent_implementation_prompt.md  # 完整设计规格
└── AGENTS.md                   # 开发指南与约定
```

## 技术栈

| 层级 | 技术 |
|---|---|
| 语言 | MoonBit |
| 运行时 | `moonbitlang/async` — 原生异步运行时 |
| 构建目标 | Native |
| LLM 提供商 | StepFun API |
| 可观测性 | OpenTelemetry（规划中） |
