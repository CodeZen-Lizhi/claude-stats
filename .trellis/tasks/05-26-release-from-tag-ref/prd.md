# 支持从 tag 所在代码发布打包

## Goal

让 GitHub Actions release workflow 可以从触发 tag 对应的代码打包，而不是固定 checkout master。这样可以在 `codex/dev` 上打 tag 生成新版本 DMG/zip，不需要先合并到 master。

## Requirements

- Release workflow 的 checkout 步骤使用触发 workflow 的 ref。
- 保留现有 tag 触发、版本解析、构建、Release 发布逻辑。
- 避免从非 master tag 构建时把版本回写提交错误推入 master。

## Acceptance Criteria

- [ ] `.github/workflows/release.yml` 不再固定 checkout master 构建。
- [ ] 从非 master tag 发布时不会执行 “Commit version bump back to master”。
- [ ] workflow YAML 语法结构保持有效。

## Out of Scope

- 不修改应用代码。
- 不在本机编译 macOS app。
- 不安装 Xcode。
