# OSC 2026 提交前待办事项

> 由 `osc2026-guide` 技能自查生成，记录当前仓库提交到 MoonBit 国产开源生态大赛前需要处理的问题和改进建议。

---

## 🔴 提交前必须处理

### 1. 修复 `moon.mod` 中的 license 字段与 LICENSE 文件不一致
- **问题**：`moon.mod` 中写 `license = "Apache-2.0"`，但实际 `LICENSE` 文件是**木兰宽松许可证 第2版（Mulan PSL v2）**
- **影响**：mooncakes.io 发布时许可证信息错误，也可能给评审留下不一致的印象
- **修复**：将 `moon.mod` 中的 `license` 改为 `"MulanPSL-2.0"`

---

## 🟡 提交前建议处理

### 2. 清理 `moon.pkg` 中未使用的包导入
- **问题**：根 `moon.pkg` 中导入了大量未使用的包，产生 14 条 `unused_package` 警告
  - `moonbitlang/async` / `@async`
  - `moonbitlang/async/stdio` / `@stdio`
  - `moonbitlang/core/debug` / `@debug`
  - `moonbit-community/opentelemetry/sdk` / `@sdk`
  - `moonbit-community/opentelemetry/sdk/trace` / `@sdktrace`
  - `moonbit-community/opentelemetry/sdk/error` / `@error`
  - `moonbit-community/opentelemetry/print` / `@print`
- **影响**：编译警告噪音大，影响项目精细度印象
- **修复**：删除根 `moon.pkg` 中实际未引用的包，只保留真正使用的

### 3. 清理 `cmd/main/moon.pkg` 中未使用的 alias
- **问题**：`moonbitlang/async @async` 被导入但无使用
- **修复**：删除该 unused import

---

## 🟢 建议改进（提升项目质量和评审印象）

### 4. 增加 GitHub Actions CI 配置
- **建议**：添加 `.github/workflows/ci.yml`，至少包含 `moon check` 和 `moon test`
- **收益**：体现工程化意识，让评审可以直接看到 CI 通过状态

### 5. 增加非交互式 runnable example
- **现状**：目前只有 `cmd/main` 一个 REPL 入口，需要人工交互
- **建议**：增加一个非交互式示例（如单次对话 + tool call 的演示），方便评审快速体验核心功能
- **可选**：也可以将 REPL 的某次典型对话输出截图放入 README

### 6. 统一 README 中的许可证声明
- **现状**：README 正文写"木兰宽松许可证，第 2 版"，与 `LICENSE` 文件一致
- **注意**：修复 issue #1 后自然统一，无需额外改动

### 7. 考虑扩展源码规模或明确项目定位
- **现状**：约 971 行 MoonBit 源码（7 个 `.mbt` 文件）
- **参考**：章程给出的项目规模参考为 **4~10k 有效 MoonBit 代码行**
- **建议**：
  - 如果时间和精力允许，可考虑扩展功能模块（如 TaskScheduler、更多工具示例、更完整的测试覆盖）
  - 或在项目提案中明确说明本项目作为**可观测性基础设施/演示框架**的定位价值，强调质量而非单纯代码量

---

## 📋 提交材料确认清单

- [ ] 项目提案/申报书（项目名称、摘要、方向、应用场景、核心功能、实现计划、预期交付物）
- [ ] GitHub 仓库链接（当前仅有 Gitlink，需确认是否已创建 GitHub 仓库并同步）
- [ ] Gitlink 仓库链接（已有：`git@code.gitlink.org.cn:yingjie/agent-observability.git`）
- [ ] 开源合规声明（本项目为原创，无上游依赖代码，无需额外声明）

---

## 📊 当前项目状态速览

| 检查项 | 状态 |
|---|---|
| MoonBit 工具链 | ✅ `moon 0.1.20260608`, `moonc v0.10.0` |
| `moon check` | ✅ 0 errors |
| `moon test` | ✅ 2 passed, 0 failed |
| Git 提交数 | ✅ 44 commits（全部在 2026-04-29 之后） |
| LICENSE 文件 | ✅ Mulan PSL v2 |
| README 文档 | ✅ 较完整 |
| 远程仓库 | ⚠️ 仅 Gitlink，需确认 GitHub 仓库 |
| 源码规模 | ⚠️ ~971 行，7 个 `.mbt` 文件 |
