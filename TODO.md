# TODO

## 🔴 比赛提交前必须处理

### 1. 分支合并：`greptime` → `master`

- **问题**：当前开发工作全部在 `greptime` 分支上（比 `master` 领先 51 个提交），但 GitHub 和 Gitlink 的默认分支都是 `master`。
- **操作**：将 `greptime` 合并到 `master`，push 到两个远程仓库。
- **注意**：合并后确认 `master` 分支在所有远程仓库（GitHub + Gitlink）都已更新，且设为默认分支。

```bash
git checkout master
git merge greptime
git push github master
git push origin master
```

### 2. 确认远程仓库状态

- 确保 GitHub 和 Gitlink 上的 `master` 分支内容一致
- 确认 GitHub Action CI 在 `master` 上通过
- **不要求** `master` 以外的分支（如 `greptime`）有 CI 绿标

---

## 🟡 agent-telemetry 发布

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

- [ ] 检查和更新所有文档中的过时内容（如 API 命名变更后 README 是否同步）
- [ ] 确认 `proposal.md` 和 `report.md` 的内容与最终代码一致
- [ ] 提交前运行一次完整的 `moon test`，确认 76/77 通过（1 个 LLM API Key 相关失败为预期）
