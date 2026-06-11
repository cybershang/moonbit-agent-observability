# OSC 2026 提交前待办事项

> 由 `osc2026-guide` 技能自查生成，记录当前仓库提交到 MoonBit 国产开源生态大赛前需要处理的问题和改进建议。

---

## 🟡 提交前建议处理

### 1. 清理 `moon.pkg` 中未使用的包导入
- **状态**：⚠️ 无法修复（MoonBit 编译器限制）
- **原因**：`llm_test.mbt` 与源码共享同一个 `moon.pkg`（MoonBit 不支持文件级 import 或独立测试子包），测试中使用的 `@sdk`、`@print`、`@stdio` 必须保留在根包导入中。实际验证：删除这 3 个包后 `moon check` 报 8 个编译错误。
- **现状**：4 条 `unused_package` 警告（`moonbitlang/async`、`stdio`、`sdk`、`print`），功能无影响，CI 已移除 `--deny-warn`。

---

## 🟢 建议改进（提升项目质量和评审印象）

### 2. 增加非交互式 runnable example
- **现状**：目前只有 `cmd/main` 一个 REPL 入口，需要人工交互
- **建议**：增加一个非交互式示例（如单次对话 + tool call 的演示），方便评审快速体验核心功能
- **可选**：也可以将 REPL 的某次典型对话输出截图放入 README

### 3. 考虑扩展源码规模或明确项目定位
- **现状**：约 971 行 MoonBit 源码（7 个 `.mbt` 文件）
- **参考**：章程给出的项目规模参考为 **4~10k 有效 MoonBit 代码行**
- **建议**：
  - 如果时间和精力允许，可考虑扩展功能模块（如 TaskScheduler、更多工具示例、更完整的测试覆盖）
  - 或在项目提案中明确说明本项目作为**可观测性基础设施/演示框架**的定位价值，强调质量而非单纯代码量

---

## 📋 提交材料确认清单

- [ ] 项目提案/申报书（项目名称、摘要、方向、应用场景、核心功能、实现计划、预期交付物）
- [x] GitHub 仓库链接（已有：`github.com/cybershang/moonbit-agent-observability`，双远程同步）
- [ ] Gitlink 仓库链接（已有：`git@code.gitlink.org.cn:yingjie/agent-observability.git`）
- [ ] 开源合规声明（本项目为原创，无上游依赖代码，无需额外声明）

---

## 📊 当前项目状态速览

| 检查项 | 状态 |
|---|---|
| MoonBit 工具链 | ✅ `moon 0.1.20260608`, `moonc v0.10.0` |
| `moon check` | ✅ 0 errors |
| `moon test` | ✅ 2 passed, 0 failed（CI 已通过） |
| Git 提交数 | ✅ 44 commits（全部在 2026-04-29 之后） |
| LICENSE 文件 | ✅ Mulan PSL v2 |
| README 文档 | ✅ 较完整 |
| 远程仓库 | ✅ 已有 Gitlink + GitHub 双远程 |
| OTLP 端点可配置 | ✅ 默认 `http://localhost:4318`，支持 `.env` 覆盖 |
| 源码规模 | ⚠️ ~971 行，7 个 `.mbt` 文件 |
