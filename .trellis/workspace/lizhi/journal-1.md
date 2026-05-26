# Journal - lizhi (Part 1)

> AI development session journal
> Started: 2026-05-25

---



## Session 1: Remove Dictionary and review Codex-only merge

**Date**: 2026-05-25
**Task**: Remove Dictionary and review Codex-only merge
**Package**: ThirdParty/ghostty
**Branch**: `codex/dev`

### Summary

Removed the Dictionary / Technical Terms feature, verified the generic transcript-analysis path, reviewed the Codex-only provider cleanup merge, and updated Trellis task records with the fork decisions.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `f0372ec` | (see git log) |
| `e2af669` | (see git log) |
| `12816a7` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 2: Diagnose packaged app background exit

**Date**: 2026-05-25
**Task**: Diagnose packaged app background exit
**Package**: ThirdParty/Atoll
**Branch**: `codex/dev`

### Summary

Diagnosed packaged Claude Stats exiting while idle, added a resident menu-bar lifecycle policy that disables and reasserts AppKit Automatic Termination, documented the LSUIElement contract, and added regression coverage for the policy.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `4d5ce47` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 3: 移除废弃功能

**Date**: 2026-05-25
**Task**: 移除废弃功能
**Package**: ThirdParty/Atoll
**Branch**: `codex/dev`

### Summary

删除设置里的终端、LinuxDo、排行榜、Local AI、Dictionary 相关功能入口和实现，移除 Ghostty/llama 子模块与构建链路，同步文档和 Trellis 包配置；可用检查已通过，完整 Xcode 构建受本机环境阻塞。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `7d77383` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 4: 云端重打 v1.7.6 安装包

**Date**: 2026-05-26
**Task**: 云端重打 v1.7.6 安装包
**Package**: ThirdParty/Atoll
**Branch**: `codex/release-ci-fix`

### Summary

将发布流程改为按标签 ref 构建，补齐 Atoll 终端占位视图并清理裁剪功能后的残留编译错误；重新推送 v1.7.6 标签后，GitHub Actions 已成功生成源仓库 DMG/zip，DMG 已下载到本机 Downloads。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `1730d90` | (see git log) |
| `fa92cb8` | (see git log) |
| `03c4384` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 5: 修复 OPS 环境工具检测

**Date**: 2026-05-26
**Task**: 修复 OPS 环境工具检测
**Package**: ThirdParty/Atoll
**Branch**: `codex/release-ci-fix`

### Summary

修复 OPS Environment 在 GUI 启动环境下检测 npm 和用户级工具目录的问题：版本探测会把已解析可执行文件目录放入 PATH，并补充 OrbStack、Volta、nvm 等常见用户工具目录扫描；新增对应 OPS 测试。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `66764e9` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete
