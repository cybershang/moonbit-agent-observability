# TODO

## � agent-telemetry 发布

### 发布 `cybershang/agent-telemetry@0.1.4`

`agent-telemetry/moon.mod` 中版本已是 `0.1.4`，需要在独立仓库打 tag 发布：

```bash
cd /path/to/cybershang/agent-telemetry
git tag v0.1.4
git push github v0.1.4
```

触发 GitHub Action publish 到 mooncakes.io。

---

## 🟢 建议优化

- [x] 检查和更新所有文档中的过时内容（如 API 命名变更后 README 是否同步）
- [x] 确认 `proposal.md` 和 `report.md` 的内容与最终代码一致
- [x] 分支重构：从 `greptime` 创建 `main`，设为默认分支，清理旧分支
- [x] 确认远程仓库状态（GitHub + Gitlink 默认分支均为 `main`，内容一致）
- [ ] 提交前运行一次完整的 `moon test`，确认 76/77 通过（1 个 LLM API Key 相关失败为预期）
