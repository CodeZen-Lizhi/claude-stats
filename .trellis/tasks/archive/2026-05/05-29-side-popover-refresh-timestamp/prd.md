# 调整侧边弹窗刷新入口与更新时间文案

## Goal

优化侧边浮动统计弹窗的操作区：去掉底部按钮，把刷新入口放到弹窗上方，并修正刚刷新后显示“已更新 0 秒后”的文案问题。

## What I already know

* 用户截图标出了侧边弹窗底部的四个按钮，要求都删除。
* 用户要求保留刷新能力，但把刷新按钮挪到上方。
* 当前 `FloatingStatsPanelView` 的底部按钮由 `actionButtons` 渲染，包含刷新、主窗口、Git、设置。
* 当前更新时间使用 `Format.relativeDate(refreshed)`，中文环境下刚刷新或时间轻微偏未来时可能显示“0 秒后”。

## Requirements

* 侧边浮动弹窗展开后不再显示底部按钮区。
* 刷新按钮移动到弹窗头部区域，刷新时仍禁用并显示忙碌态。
* 更新时间在刚刷新或刷新时间略晚于当前时间时显示“刚刚更新”，不显示“0 秒后”。
* 保持浮动弹窗可拖拽，不破坏现有 Codex 状态和指标展示。

## Acceptance Criteria

* [ ] 展开侧边浮动弹窗时，底部不再出现四个操作按钮。
* [ ] 头部能看到刷新按钮，点击后触发 `env.store.refresh()`。
* [ ] 刚刷新后文案显示为自然文本，不出现“已更新 0 秒后”。
* [ ] 项目按 `scripts/run-debug.sh` 构建并启动成功。

## Definition of Done

* 代码改动聚焦在浮动弹窗 UI 和更新时间文案。
* 运行项目要求的 debug 构建脚本。
* 完成改后静态自检。

## Out of Scope

* 不调整菜单栏主下拉面板。
* 不新增新的设置项或偏好。
* 不改动主窗口页面布局。

## Technical Notes

* 主要文件：`ClaudeStats/Views/FloatingStats/FloatingStatsPanelView.swift`。
* 动画分段定义在 `ClaudeStats/Views/FloatingStats/FloatingStatsContentAnimation.swift`。
