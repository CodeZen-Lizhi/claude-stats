# 打包当前 codex/dev 构建

## Goal

把当前 `codex/dev` 已推送代码打包成发布产物，并在 CI 失败时修复阻塞打包的问题。

## What I Already Know

- `codex/dev` 已推送到远端，HEAD 为 `5f061a7`。
- 本机只有 Command Line Tools，没有可用 Xcode，无法本地执行 macOS Release 打包。
- `.github/workflows/release.yml` 支持推 semver tag 触发远端 Release workflow。
- 已推送 tag `v1.7.13`，远端 workflow 在 `Build app and package artifacts` 步骤失败，annotation 为 exit code 65。

## Assumptions

- 本次打包目标版本使用最新 tag 后的下一个 patch 版本，即 `v1.7.13`。
- 如果失败原因来自本次 Swift 改动或发布脚本，需要修复代码后推送新的 patch tag 触发打包；`v1.7.13` 到 `v1.7.20` 已失败，下一次重试使用 `v1.7.21`，不改写已推送 tag。

## Requirements

- 确认远端分支代码已推送。
- 通过 GitHub Actions Release workflow 打包当前代码。
- 如 CI 编译失败，修复阻塞打包的最小代码问题并重新触发打包。
- 不引入与打包无关的功能变更。

## Acceptance Criteria

- [ ] 远端存在用于打包的 semver tag。
- [ ] Release workflow 成功完成。
- [ ] GitHub Release 生成 DMG/zip 产物，或明确记录无法完成的外部阻塞。

## Definition of Done

- 相关修复提交并推送。
- 打包 tag 推送到远端。
- CI 状态已核对。

## Out of Scope

- 不安装本机 Xcode。
- 不调整签名/notarization secrets。
- 不修改发布版本策略，除非打包失败要求。

## Technical Notes

- 本机 `xcode-select -p` 为 `/Library/Developer/CommandLineTools`，`xcodebuild` 不可用。
- Release workflow 使用 `macos-26` 并选择 Xcode 26.4.x。
