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


## Session 4: 精简 Ops 与移除网络调试

**Date**: 2026-05-26
**Task**: 精简 Ops 与移除网络调试
**Package**: ThirdParty/Atoll
**Branch**: `codex/dev`

### Summary

保留 Ops 的 Brew 和 Environment 功能，移除 Network/Rockxy 以及旧 Ops 工具入口；完成 Trellis check，Xcode 阶段因本机仅安装 CommandLineTools 无法运行。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `dc2bdd8` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete
