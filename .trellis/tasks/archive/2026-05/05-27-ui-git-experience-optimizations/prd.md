# brainstorm: 主窗口与 Git 体验优化

## Goal

优化主窗口布局、Git 页面信息架构、本地化和 Git 仓库来源规则，让 Codex Statistics 更聚焦“用户用 Codex 做过哪些 Git 项目”，并减少误解与噪音。

## What I already know

* 主窗口左侧栏当前是固定宽度，用户希望能左右拖拽调整。
* Git Inspector 当前包含 `Commit / Worktree / Repo`、Language Mix、Code Share、Top Committers 和 analyzed/skipped 摘要，用户认为这些不需要。
* Commit Inspector 需要新增分支信息。
* 中文设置下仍存在英文整句文案。
* “跟踪”页命名容易误解；该页实际用于配置 Git 仓库来源和 Git diff 偏好。
* 用户希望支持 JetBrains IDE（IntelliJ IDEA / WebStorm / PyCharm 等）作为仓库发现辅助来源。
* Git 页面不应展示所有编辑器历史项目；最终应聚焦有 Codex 使用记录的 Git 项目。

## Requirements

### 1. 主窗口左侧栏可调宽度

* 用户可以拖拽主窗口左侧栏与详情区之间的边界，左右调整宽度。
* 默认宽度保持现有视觉基准。
* 宽度应持久化，下次打开主窗口恢复用户设置。
* 侧栏隐藏时宽度为 0；再次显示时恢复用户上次宽度。
* 设置页侧栏暂不要求可调，除非实现时复用成本很低且不破坏现有体验。

### 2. Git Inspector 做减法

* 移除 `Worktree / Repo` 两个 Inspector 切换项。
* 移除 Language Mix、Code Share、Top Committers。
* 移除 `302 analyzed - 155 skipped - 2.06 MB` 这类分析摘要。
* 保留 Commit Inspector。
* Commit Inspector 新增分支信息，展示当前提交关联的本地/远端分支。
* 如果一个 commit 被多个分支包含，优先展示少量分支并提供 `+N` 概览。
* 如果查不到所属分支，显示明确 fallback，不留空。

### 3. 补齐中文本地化

* 设置页中文环境下不应出现整句英文说明。
* 专有名词如 Codex Statistics、GitHub、API、Token 可按产品术语保留，但整句说明必须中文化。
* 所有用户可见文案应走 `L10n.string(...)` 和 `Localizable.xcstrings`。

### 4. “跟踪”页重命名与解释

* “跟踪”改名为“仓库来源”或更清晰的等价名称。
* 页面说明明确：只读取本机工具历史和 Codex 本地记录，不上传数据。
* 编辑器来源不等于直接显示项目，只用于辅助发现候选仓库或来源标签。

### 5. Git 项目列表以 Codex 使用记录为主来源

* Git 页面项目应优先来自 Codex 使用记录，而不是所有编辑器历史项目。
* 主规则：从 `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` 读取 `session_meta.cwd`，再用 Git 解析仓库根目录并去重。
* 只要 Codex session 的 `cwd` 落在某个 Git 仓库内，该仓库就应出现在 Git 页面。
* 不做全盘扫描，不扫描大目录如 `~/Projects`、`~/Desktop`、`~/Downloads`。
* `.codex/` 项目目录痕迹可作为补充判断，但只在已知候选目录内检查，不全盘查找。
* Cursor / Windsurf / Trae / Qoder / JetBrains 等来源用于补充发现候选目录、匹配来源标签，或在 Codex 路径信息不完整时辅助匹配。
* Git 页面需要能说明某个仓库为什么出现，例如 `Codex CLI`、`Codex app`、`Cursor · Codex`、`JetBrains · Codex`。

### 6. 支持 JetBrains 仓库来源

* 新增 JetBrains 来源。
* 读取 JetBrains 最近项目记录，例如 `~/Library/Application Support/JetBrains/*/options/recentProjects.xml`。
* 解析最近项目路径后，识别其中的 Git 仓库。
* 默认关闭，用户手动开启。

### 7. 设置页瘦身：移除或隐藏低价值 Git 配置

用户截图中的四个配置需要按“是否仍有用户决策价值”处理：

* `Git 视图打开位置`
  * 现状：影响菜单栏面板中的 Git 入口是在面板内显示还是独立窗口打开。
  * 判断：当前主窗口已有 Git 页面，这个设置对普通用户含义不清，且与“仓库来源”设置混在一起。
  * 方案：从设置页隐藏；后台固定为更适合重型 Git UI 的默认行为。若实现时已有主窗口 Git 页面入口，应统一为打开主窗口 Git 页面；若仍保留菜单栏面板入口，则默认独立窗口，不暴露开关。
* `Diff 块粒度`
  * 现状：仍影响 diff 渲染，`Fine` 会把混合变更拆细，`Coarse` 会把每个变更区域保留为一个块。
  * 判断：功能仍有用，但作为全局设置太技术化。
  * 方案：从设置页隐藏；后台默认 `Fine`。如后续需要，可放到 diff 查看器内部作为临时视图切换，而不是全局设置。
* `语言引擎`
  * 现状：只是展示 `GitHub Linguist + scc`，没有可选项。
  * 判断：用户不能操作，且第 2 点会移除 Language Mix / Repo 统计面板。
  * 方案：从设置页删除；若后台仍有语言统计能力，仅作为内部实现，不展示配置。
* `统计范围`
  * 现状：控制 Repo 统计使用 `HEAD` 或 `Working Tree`。
  * 判断：第 2 点移除 Repo / Worktree / Language Mix 等统计后，该配置失去主要用户价值。
  * 方案：从设置页删除；后台固定 `HEAD`。如果未来恢复仓库统计，再在对应统计视图内部提供范围选择。

### 8. 参考 shadcn/ui 重塑原生 SwiftUI 视觉风格

* shadcn MCP 已配置 `@shadcn` registry，可作为组件结构、状态和视觉 token 的参考来源。
* 这是 macOS SwiftUI 原生 app，不能直接引入 React/Tailwind 组件。
* 方案是把 shadcn 的设计语言翻译成 SwiftUI 设计系统：
  * 更清晰的 token：background、foreground、muted、border、accent、destructive。
  * 统一控件语义：Button、Card、Badge、Tabs、Tooltip、Popover、Separator、Command/搜索式选择器。
  * 减少当前过重的圆角、阴影、渐变和低信息密度装饰。
  * 保留 macOS 原生质感和菜单栏 app 特性，不做 Web 风格硬套。
* 建议先做局部试点：设置页 + Git 页面。试点通过后再推广到 Dashboard / Usage / Sessions。
* 需要形成 SwiftUI 组件层，而不是在每个页面复制样式。

#### 8.1 SwiftUI 组件落地清单

* `AppButton`
  * 对标 shadcn `button`。
  * 支持 primary、secondary、ghost、destructive、icon-only、small/regular 尺寸。
  * 统一 hover、pressed、disabled 状态。
* `AppCard` / `SettingCard`
  * 对标 shadcn `card`。
  * 卡片圆角收敛到更克制的 8px 左右；减少厚重阴影和过强背景块。
  * 页面 section 不再套多层卡片，重复条目才用 card。
* `AppTabs` / `AppSegmentedTabs`
  * 对标 shadcn `tabs`。
  * 替换当前过重的 pill segmented 视觉，保留清晰 selected 状态和键盘可访问性。
* `AppBadge`
  * 对标 shadcn `badge`。
  * 用于 Git 分支、来源标签、状态标签，如 `Codex CLI`、`JetBrains`、`origin/main`。
* `AppSeparator`
  * 对标 shadcn `separator`。
  * 统一设置页、Git 面板、列表里的分割线强度。
* `AppTooltip` / Help affordance
  * 对标 shadcn `tooltip`。
  * 用于解释图标按钮、分支来源、仓库出现原因。
* `AppPopover`
  * 对标 shadcn `popover`。
  * 用于 `+N` 分支列表、仓库来源详情、轻量帮助内容。
* `AppSidebar`
  * 对标 shadcn `sidebar` 的信息架构，不照搬 Web 布局。
  * 支持可调宽度、选中状态、图标+文字、底部设置入口。

#### 8.2 页面试点范围

* 设置页
  * 改名后的“仓库来源”页优先试点。
  * 删除低价值全局配置后，页面只展示仓库来源、隐私说明和必要 Git 行为。
  * 统一 row/card/separator/button 风格。
* Git 页
  * Git Inspector 精简为 Commit-only。
  * 用 badge 展示分支、来源、状态。
  * 移除 Repo 统计后，右侧面板应更像信息面板，而不是报表面板。
* 主窗口 shell
  * 左侧栏支持拖拽。
  * 侧栏 hover/selected/disabled 状态与新 token 对齐。

#### 8.3 风格边界

* 不引入 WebView、React、Tailwind 或 shadcn 源码。
* 不把 macOS 原生控件全部重画；下拉、开关、窗口行为优先保留系统语义。
* 不做大面积营销页风格、超大 hero、装饰性渐变背景。
* 优先提升可读性、信息密度和一致性。

### 9. 菜单栏弹窗后续统一风格

* 菜单栏弹窗会跟随整体视觉系统统一，但不进入第一批改造。
* 原因：菜单栏弹窗是高频入口，尺寸小、信息密度高，贸然同步大改风险较高。
* 第一阶段先保持当前功能布局，避免影响使用。
* 第二阶段再按新的 SwiftUI 设计系统改造：
  * 保留小尺寸信息面板定位。
  * 保留核心区块：顶部状态、会话/用量/Git tabs、时间范围、指标卡、图表、底部设置/分享/退出。
  * 去掉过重的 bracket 装饰和偏旧的终端感。
  * 使用统一的 `AppButton`、`AppTabs`、`AppCard`、`AppSeparator`、`AppBadge`。
  * 视觉上与主窗口一致，但布局仍按菜单栏弹窗优化。

## Acceptance Criteria

* [ ] 主窗口左侧栏可拖拽调整，重启后保持宽度。
* [ ] Git Inspector 顶部不再出现 Worktree / Repo。
* [ ] Git Inspector 不再展示语言构成、代码归属、贡献者排行、analyzed/skipped 摘要。
* [ ] Commit Inspector 显示分支信息。
* [ ] 中文设置页无整句英文说明残留。
* [ ] “跟踪”页改为更准确的“仓库来源”语义，并说明只读本机数据。
* [ ] Git 页面只展示能从 Codex 使用记录归并出的 Git 仓库。
* [ ] 编辑器来源不会单独把未使用过 Codex 的项目加入 Git 页面。
* [ ] JetBrains 最近项目可作为辅助来源。
* [ ] 设置页不再展示 Git 视图打开位置、Diff 块粒度、语言引擎、统计范围这四个低价值全局配置。
* [ ] 后台仍以明确默认值运行：Diff 默认 `Fine`，统计范围默认 `HEAD`，语言统计引擎不作为用户配置暴露。
* [ ] 建立一套 shadcn-inspired SwiftUI token / 基础组件，不直接引入 React/Tailwind。
* [ ] 设置页和 Git 页完成首批视觉试点，控件状态、hover、disabled、selected 表现一致。
* [ ] 菜单栏弹窗暂不纳入首批改造；PRD 中记录为 Phase 2 范围。

## Definition of Done

* 相关 Swift 代码通过编译或至少完成项目脚本验证。
* 相关单测补充或更新。
* `Localizable.xcstrings` 可被 JSON 校验工具解析。
* `bash scripts/run-tests.sh`、`bash scripts/run-debug.sh` 按项目规则执行；若本机 Xcode 环境阻塞，记录具体阻塞。

## Out of Scope

* 不做全盘 Git 仓库扫描。
* 不上传本地项目路径、Git 信息或 Codex 会话数据。
* 不在本任务内重新设计完整 Git 分析页面。
* 不恢复已明确删掉的 Worktree / Repo 统计视图。

## Technical Notes

* 现有 Codex session 扫描逻辑位于 `ClaudeStats/Providers/Codex/CodexSessionScanner.swift`。
* Codex session 文件路径来自 `CodexPaths.sessionsDirectory`，默认是 `~/.codex/sessions`。
* 现有 Git 仓库解析逻辑位于 `ClaudeStats/Services/GitAnalyzer.swift`，通过 `git -C <cwd> rev-parse --show-toplevel` 归并仓库根目录。
* 现有 Git 来源配置位于 `ClaudeStats/Services/Git/GitWorkspaceSourceResolver.swift`。
* 现有 Git 页面 reload 会先收集 cwd，再调用 `GitAnalyzer.repos(forCwds:)`。
