# agent-telemetry TODO

## 📝 后续版本发布待办

### 发布 `cybershang/agent-telemetry@0.1.4`
- **状态**：⬜ 待处理
- **原因**：独立仓库 `cybershang/agent-telemetry` 的 `main` 分支已新增 `.env.example`，但当前 mooncakes 最新版本为 `0.1.3`，不包含该文件。
- **步骤**：
  1. 在 `agent-observability/agent-telemetry/moon.mod` 中将版本号 bump 到 `0.1.4`
  2. 同步修改到独立仓库 `cybershang/agent-telemetry`
  3. 在独立仓库打 tag `v0.1.4` 并 push，触发 publish action
