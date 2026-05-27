# 诊断菜单栏应用偶发自动退出

## Goal

诊断并修复 Codex Statistics 在用户打开后过一段时间自动退出的问题，确认退出原因是崩溃、macOS Automatic Termination、Sparkle 更新流程、还是应用自身生命周期逻辑，并用可重复的反馈环验证修复。

## What I Already Know

- 用户反馈：打开软件后，会过一段时间自动退出，属于偶发问题。
- 这是 macOS `LSUIElement` 菜单栏应用，项目说明要求应用在无普通窗口时也必须驻留在菜单栏。
- 项目要求调试启动必须使用 `bash scripts/run-debug.sh`，避免 Launch Services 同 bundle id 多 app 冲突。
- 当前代码已有 `AppLifecyclePolicy`，启动时调用 `ProcessInfo.processInfo.disableAutomaticTermination(...)`，并在启动后 1 秒再次调用以抵消 AppKit 启动/窗口恢复阶段的策略变化。
- 当前测试只覆盖 `configureAutomaticTermination` 会调用一次禁用自动终止，没有覆盖启动后重申，也没有进程级存活回归测试。
- 工作区已有多处未提交改动，本任务不会回滚或混入无关改动。

## Assumptions

- 优先假设用户描述的“自动退出”可能是进程结束，不一定是崩溃；需要通过进程状态、统一日志和 crash report 区分。
- 若本地 debug build 无法短时间复现，需要提高复现率：循环启动、保持空闲、观察进程和系统日志。

## Requirements

- 建立一个能在本机运行的反馈环，至少能证明 debug build 在观察窗口内是否仍存活。
- 收集退出原因证据：退出码、crash report、统一日志、应用日志或系统 automatic termination 线索。
- 给出 3-5 个可证伪假设，并优先验证最可能原因。
- 如定位到代码缺陷，做最小且结构正确的修复。
- 如暂时无法复现，保留可复用的诊断方法和下一步所需证据。

## Acceptance Criteria

- [ ] `bash scripts/run-debug.sh` 能成功构建并从 canonical DerivedData 路径启动应用。
- [ ] 有一个进程存活监控或诊断脚本能记录应用 PID、观察时长和退出证据。
- [ ] 明确区分“崩溃退出”“用户/代码主动 terminate”“macOS 自动终止”“未复现”。
- [ ] 若修复代码，相关测试通过，并重新运行 `bash scripts/run-debug.sh`。

## Definition of Done

- 测试或诊断命令已运行，并记录关键结果。
- 临时 debug 日志或脚本被清理，除非明确保留为诊断工具。
- 修改范围仅限生命周期/诊断相关文件，避免触碰既有无关 WIP。

## Out of Scope

- 不处理已有会话删除、Git Activity、视图布局等无关未提交改动。
- 不改发布/签名/更新分发流程，除非证据显示自动退出由 Sparkle 更新路径直接触发。

## Technical Notes

- 相关文件：
  - `ClaudeStats/App/AppLifecyclePolicy.swift`
  - `ClaudeStats/App/AppDelegate.swift`
  - `ClaudeStatsTests/AppLifecyclePolicyTests.swift`
  - `scripts/run-debug.sh`
- 相关项目约束：
  - `Info.plist` 设置了 `LSUIElement = true` 和 `SUEnableAutomaticChecks = true`。
  - `AGENTS.md` 要求每轮代码改动后运行 `bash scripts/run-debug.sh`。
