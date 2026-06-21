# OSC 2026 提交前待办事项

> 由 `osc2026-guide` 技能自查生成，记录当前仓库提交到 MoonBit 国产开源生态大赛前需要处理的问题和改进建议。

---

## 🟡 提交前建议处理

### 1. 清理 `moon.pkg` 中未使用的包导入
- **状态**：✅ 已清理到最低限度
- **原因**：`async` 与 `@sdk` 等包因 `async test` 和测试文件使用而无法移除；MoonBit 不支持文件级 import，因此这些警告属于已知且无害。
- **现状**：根包剩余 2~3 条 `unused_package` 警告，功能无影响，CI 已移除 `--deny-warn`。

---

## 🟢 建议改进（提升项目质量和评审印象）

### 2. 增加非交互式 runnable example
- **状态**：✅ 已完成
- **说明**：`cmd/main/main.mbt` 已支持 `--ask` 非交互模式，README 已补充使用示例：`moon run cmd/main -- --ask "北京今天天气怎么样？"`

### 2.5 优化 telemetry 初始化 API
- **状态**：✅ 已完成
- **说明**：
  - `agent-telemetry` 提供 `ExporterType` 枚举（`Stdout` / `Otlp(String)` / `Custom` / `NoOp`）
  - 提供 `IdGeneratorOption` 枚举（`SdkDefault` / `ProcessUniqueRandom` / `Custom`）
  - 提供 `init_from_env` 一键从 `OTEL_STDOUT`、`OTEL_SERVICE_NAME`、`OTEL_EXPORTER_OTLP_ENDPOINT` 初始化
  - 应用层入口只需一行 `@telemetry.init_from_env(service_name=..., id_generator=@telemetry.ProcessUniqueRandom)`
  - 原 `telemetry.mbt` 与 `cmd/main/otel_id_generator.mbt` 已删除，彻底把初始化逻辑收进库里

### 3. 考虑扩展源码规模或明确项目定位
- **现状**：约 2292 行 MoonBit 源码（21 个 `.mbt` 文件），其中 `agent-telemetry` 库约占 700 行
- **参考**：章程给出的项目规模参考为 **4~10k 有效 MoonBit 代码行**
- **建议**：
  - 本项目核心目标是沉淀 `agent-telemetry` 可复用插桩库，演示应用作为使用示例
  - 可在项目提案中明确说明：本项目作为**可观测性基础设施**的定位价值，强调库的接口设计、测试覆盖与 mooncakes.io 发布

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
| `moon test` | ✅ agent-telemetry 库 15 passed；根应用集成测试需 LLM_API_KEY |
| telemetry API | ✅ `init_from_env` / `ExporterType`（含 `Otlp`）已实现 |
| Git 提交数 | ✅ 44 commits（全部在 2026-04-29 之后） |
| LICENSE 文件 | ✅ Mulan PSL v2 |
| README 文档 | ✅ 已更新双包结构 |
| 远程仓库 | ✅ 已有 Gitlink + GitHub 双远程 |
| OTLP 端点可配置 | ✅ 默认 `http://localhost:4318`，支持 `.env` 覆盖 |
| 源码规模 | ✅ ~2292 行，21 个 `.mbt` 文件 |
| mooncakes.io 发布 | ✅ 已发布 `cybershang/agent-telemetry@0.0.1` |

---

## 📝 后续版本发布待办

### 发布 `cybershang/agent-telemetry@0.1.4`
- **状态**：⬜ 待处理
- **原因**：独立仓库 `cybershang/agent-telemetry` 的 `main` 分支已新增 `.env.example`，但当前 mooncakes 最新版本为 `0.1.3`，不包含该文件。
- **步骤**：
  1. 在 `agent-observability/agent-telemetry/moon.mod` 中将版本号 bump 到 `0.1.4`
  2. 同步修改到独立仓库 `cybershang/agent-telemetry`
  3. 在独立仓库打 tag `v0.1.4` 并 push，触发 publish action
