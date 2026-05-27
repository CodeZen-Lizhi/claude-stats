# 会话删除功能：单个/批量删除 transcript，保留统计记录

## Goal

为 Codex Statistics 增加会话删除能力。删除目标是原始 transcript 会话内容；token、费用、Dashboard、菜单栏、Git 仓库来源、Git 关联/归因等历史统计记录必须保留。删除方式固定为把原始 transcript 移到系统废纸篓；App 不额外备份完整 transcript，避免“换个地方存一份等于没删”。

## Requirements

* 支持单个会话删除：会话 row 右键菜单和详情页删除按钮。
* 支持批量删除：会话侧栏进入选择模式，勾选多个会话后一次删除。
* 支持项目组批量删除：项目组右键“删除此项目组会话”，作用于该组当前所有会话。
* 支持搜索结果批量删除：选择模式下可“全选当前筛选结果”，不误选隐藏结果。
* 删除确认弹窗说明：transcript 会移到废纸篓；token、费用、Dashboard、Git 等历史统计记录保留；不会删除项目目录、Git 仓库、Codex 配置目录。
* 删除成功后，原始 transcript 从原路径消失，被删除会话不再出现在会话列表/详情页。
* 删除不清理 `UsageLedgerEvent`，历史 token/cost/趋势继续可见。
* 删除后 Git 相关功能仍可使用该会话的必要元数据：仓库来源、Git 关联图、Commit AI 用量不能因为最后一条 live session 被删而丢失。
* 子 agent：删除父会话时，已折叠 child session 默认一并从会话列表隐藏，但统计保留；删除 child 会话时，父会话保留，历史统计保留。
* 批量删除失败时，成功项保持已删除，失败项留在列表；UI 显示失败数量和首个失败原因，不自动回滚。

## Acceptance Criteria

* [ ] 单个删除后，transcript 原路径消失或被移到废纸篓，会话列表不再显示该 session。
* [ ] 批量删除后，成功项从列表消失，失败项保留，选择模式清空。
* [ ] 项目组删除只删除该组会话；搜索结果全选只选当前筛选结果。
* [ ] 删除前后 `summary(.allTime)` token/cost 保持历史记录。
* [ ] Dashboard、Usage、菜单栏 token/费用保留历史记录。
* [ ] 删除最后一个 repo session 后，Git 页仍保留该 repo 来源和历史归因。
* [ ] Commit Inspector AI 用量仍可显示历史用量。
* [ ] 删除父会话时 child 不变成孤儿会话，统计保留。
* [ ] 删除 child 时父会话仍存在，统计保留。
* [ ] 移到废纸篓失败不写 deleted record；deleted record 写入失败时不把 UI 标记为已删除。

## Definition of Done

* Tests added/updated for single delete, batch delete, statistics retention, deleted-session Git metadata, and failure handling where practical.
* `python3 -m json.tool ClaudeStats/Localization/Localizable.xcstrings`
* `git diff --check`
* `bash scripts/run-tests.sh`
* `bash scripts/run-debug.sh` where local Xcode allows it; record CommandLineTools blockage if present.

## Technical Approach

* Add `DeletedSessionRecord` / `DeletedSessionStore` under App Support. It stores non-conversation metadata only: session id, provider, cwd, project, source path, deletion time, child session ids, parent session id, and any fields needed to keep Git attribution working. It must not store full transcript content.
* Add `SessionStore.deleteSession(_:)` and `deleteSessions(_:)`. The store writes deleted records first, moves transcript files to Trash, refreshes sessions, and returns a result summary. If trashing fails, that session should not be recorded as deleted.
* During refresh, filter discovered sessions by deleted ids/source paths before assigning visible `sessions`, while keeping ledger events untouched.
* Expose deleted-session metadata alongside live sessions for Git-related consumers. Usage and Dashboard continue to read ledger events, so they naturally retain token/cost history.
* Update Session UI state to support selection mode, selected ids, per-row checkboxes, group delete, current-filter selection, confirmation dialogs, and post-delete navigation cleanup.
* Localize all visible delete labels, confirmation text, failure messages, and selection-mode controls.

## Decision (ADR-lite)

**Context**: Session transcript files are raw conversation records; usage and cost are persisted separately in the ledger and intentionally survive missing transcripts. Git currently uses live session cwd/timeline, so deleting transcript files would otherwise remove repository context.

**Decision**: Delete transcript files by moving them to the system Trash, persist minimal deleted-session metadata, and retain ledger events/history.

**Consequences**: Users get real deletion of conversation content without losing historical statistics. The app must maintain a deleted-session metadata index so Git history and repo attribution remain stable after deletion.

## Out of Scope

* Restoring deleted sessions from inside the app.
* Permanent deletion / emptying Trash.
* Extra full transcript backup inside the app.
* Deleting project directories, Git repos, Codex config, or cloud history.

## Research References

* [`research/session-deletion-data-flow.md`](research/session-deletion-data-flow.md) — 当前 ledger 会保留已消失 transcript 的历史用量，因此删除 transcript 可以保留 token/cost，但 Git 需要额外 deleted metadata。

## Technical Notes

* 已检查：`SessionStore.refresh()`、`UsageLedgerStore`、`UsageSummary`、`DashboardViewModel`、`UsageViewModel`、`GitActivityViewModel`、`GitRepoWorkspaceView`、`SessionSidebarColumn`、`SessionRow`。
* 当前已有测试 `SessionStoreTests.deletedTranscriptDoesNotRemoveLedgerTotals` 证明 transcript 消失后 ledger usage 保留，符合最终需求。
