# 非交互式单次运行模式设计

## 背景

当前 `cmd/main` 只提供交互式 REPL 入口。评审或 CI 场景下需要一个无需人工输入即可直接运行的示例，`TODO.md` 也将“增加非交互式 runnable example”列为建议改进项。

## 目标

为 `cmd/main` 增加 `--ask`（简写 `-a`）命令行选项，支持单次对话 + Tool Call 闭环后退出；未提供该选项时保持现有 REPL 行为不变。

## 设计

### 1. 命令行解析

- 在 `cmd/main/moon.pkg` 中引入 `moonbitlang/core/argparse`（MoonBit 内置标准库）。
- 使用 `@argparse.Command` 定义：
  - 选项 `--ask` / `-a`：单次运行的用户输入 query，类型为 `String?`，默认 `None`。
- 解析失败时由 `@argparse` 自动打印帮助信息并退出。

### 2. 运行模式分支

```text
if ask is Some(query) {
  单次运行路径
} else {
  现有 REPL 路径
}
```

#### 2.1 单次运行路径

1. 复用现有的 `settings`、`telemetry`、`client`、`agent` 初始化。
2. 调用 `agent.run(query)` 得到 `AgentTurnResult`。
3. 调用统一的 `print_turn(result)` 输出 tool call 记录和最终回复。
4. 调用 `provider.force_flush()` 与 `provider.shutdown()`，确保 OpenTelemetry span 完整导出。
5. 进程自然退出。

#### 2.2 REPL 路径

保持现有 `while true` 循环不变，仅把循环体内的输出逻辑提取为 `print_turn` 复用。

### 3. 输出格式

单次模式与 REPL 单轮输出完全一致：

```text
[Tool Call] get_weather({"city": "北京"})
[Tool Result] {"temperature": 25, "condition": "晴"}
北京今天天气很好...
```

Tool result 超过 200 字符时仍按现有逻辑截断显示。

### 4. 公共函数抽取

在 `cmd/main/main.mbt` 中新增私有辅助函数：

```moonbit
fn print_turn(turn : @agent.AgentTurnResult) -> Unit
```

负责打印 `[Tool Call]`、`[Tool Result]` 和 `turn.reply`，供单次模式和 REPL 共同使用。

### 5. 兼容性

| 命令 | 行为 |
|---|---|
| `moon run cmd/main` | 进入 REPL（不变） |
| `moon run cmd/main -- --ask "北京天气怎么样"` | 单次运行并退出 |
| `moon run cmd/main -- -a "北京天气怎么样"` | 同上 |

`exit` / `quit` 仅对 REPL 有效。

### 6. 测试策略

- `moon check` 验证类型正确。
- `moon test` 确保现有 48 个测试全部通过。
- 手动验证：
  1. 无参数启动进入 REPL。
  2. `--ask` 能触发 tool call 并输出结果。
  3. 单次运行结束后 OTLP exporter 成功刷新 span。

由于 main 函数依赖命令行参数和外部 LLM API，不做自动化单元测试。

## 影响范围

- `cmd/main/main.mbt`：增加 argparse 解析、模式分支、`print_turn` 辅助函数。
- `cmd/main/moon.pkg`：新增 `moonbitlang/core/argparse` 导入。
- 不改动 `agent.mbt`、`llm.mbt`、`tools.mbt` 等核心库。

## 验收标准

- [ ] `moon run cmd/main -- --ask "北京天气怎么样"` 能正确输出结果并退出。
- [ ] `moon run cmd/main` 仍进入 REPL。
- [ ] `moon check` 无新增错误。
- [ ] `moon test` 全部通过。
