import SwiftUI
import AppKit

/// Detail pane shown when the user picks a session from the sidebar tree.
/// The layout uses the same `StatCard` + `ModelTable` visual language as the
/// Dashboard so the main window reads as one coherent surface.
///
/// Values are read fresh from the session every render — no view model, since
/// the underlying stats are already cached on ``Session/stats`` by
/// ``SessionStore``. If `stats` is `nil` (transcript hasn't been parsed yet
/// or failed to parse), the view shows a thin placeholder.
struct SessionDetailView: View {
    @Environment(AppEnvironment.self) private var env
    let session: Session
    var onDelete: ((Session) -> Void)?
    @State private var transcriptMessages: [SessionTranscriptMessage] = []
    @State private var transcriptIsLoading = false
    @State private var transcriptSearchText = ""
    @State private var selectedSearchOrdinal: Int?

    private var transcriptSearchIndex: TranscriptSearchIndex {
        TranscriptSearchIndex.make(messages: transcriptMessages, query: transcriptSearchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let stats = session.stats {
                statCards(stats)
                modelBreakdown(stats)
            } else {
                missingStatsPlaceholder
            }

            metadataPanel
            transcriptSection
            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: session.id) {
            await loadTranscript()
        }
        .onChange(of: transcriptSearchText) { _, _ in
            selectedSearchOrdinal = transcriptSearchIndex.isEmpty ? nil : 0
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.stxMuted)
                Text(session.projectDisplayName)
                    .font(.sora(11, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(Color.stxMuted)
            }

            Text(session.stats?.title.nonEmpty ?? session.titleFallback ?? session.externalID)
                .font(.sora(22, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let cwd = session.cwd, !cwd.isEmpty {
                Text(cwd)
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Stat cards

    @ViewBuilder
    private func statCards(_ stats: SessionStats) -> some View {
        let includeCache = env.preferences.includeCacheInTokens
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatCard(label: L10n.string("session.stat.total_tokens", defaultValue: "TOTAL TOKENS"),
                         value: Format.tokens(stats.totalTokens(includingCacheRead: includeCache)))
                StatCard(label: L10n.string("session.stat.estimated_cost", defaultValue: "ESTIMATED COST"),
                         value: Format.cost(stats.totalCost(for: env.preferences.costEstimationMode)))
                StatCard(label: L10n.string("usage.stat.requests", defaultValue: "REQUESTS"),
                         value: "\(stats.messageCount)")
                StatCard(label: L10n.string("session.stat.last_activity", defaultValue: "LAST ACTIVITY"),
                         value: Format.relativeDate(stats.lastActivity ?? session.lastModified),
                         animatesNumericValue: false)
            }
        }
    }

    // MARK: - Model breakdown

    @ViewBuilder
    private func modelBreakdown(_ stats: SessionStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BY MODEL")
                .font(.sora(10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.stxMuted)
            ModelTable(
                models: stats.models,
                includeCacheInTotals: env.preferences.includeCacheInTokens,
                displayName: { env.store.displayName(forModel: $0, provider: session.provider) }
            )
        }
    }

    // MARK: - Metadata

    private var metadataPanel: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], alignment: .leading, spacing: 10) {
            let firstModelID = session.stats?.models.first?.model
            metadataCell("MODEL", firstModelID.map {
                env.store.displayName(forModel: $0, provider: session.provider)
            } ?? "--")
            metadataCell("DURATION", sessionDuration.map(Format.duration) ?? "--")
            metadataCell("FILE SIZE", Format.bytes(Int(session.fileSize)))
            metadataCell("START", session.stats?.firstActivity.map(Format.shortDate) ?? "--")
            metadataCell("END", session.stats?.lastActivity.map(Format.shortDate) ?? "--")
        }
    }

    private var sessionDuration: TimeInterval? {
        guard let first = session.stats?.firstActivity, let last = session.stats?.lastActivity else { return nil }
        return last.timeIntervalSince(first)
    }

    private func metadataCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.sora(9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Color.stxMuted)
            Text(value)
                .font(.sora(11).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(.compactCard(radius: 8), padding: nil)
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("CONVERSATION")
                    .font(.sora(10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.stxMuted)

                Spacer(minLength: 0)

                transcriptSearchControls

                if transcriptIsLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                } else if !transcriptMessages.isEmpty {
                    Text(L10n.requestCount(session.stats?.messageCount ?? transcriptMessages.count))
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }
            }

            if transcriptIsLoading && transcriptMessages.isEmpty {
                transcriptPlaceholder(L10n.string("session.transcript.loading",
                                                  defaultValue: "Loading transcript…"))
            } else if transcriptMessages.isEmpty {
                transcriptPlaceholder(L10n.string("session.transcript.empty",
                                                  defaultValue: "No readable conversation content found in this transcript."))
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(transcriptMessages) { message in
                        let messageMatches = transcriptSearchIndex.matches(for: message.id)
                        TranscriptMessageRow(
                            message: message,
                            matches: messageMatches,
                            isSelectedMatch: selectedSearchOrdinal.flatMap {
                                transcriptSearchIndex.matches.indices.contains($0)
                                    ? transcriptSearchIndex.matches[$0].messageID == message.id
                                    : false
                            } ?? false,
                            modelDisplayName: message.model.map {
                                env.store.displayName(forModel: $0, provider: session.provider)
                            }
                        )
                    }
                }
            }
        }
    }

    private var transcriptSearchControls: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.stxMuted)
            TextField("Search transcript", text: $transcriptSearchText)
                .textFieldStyle(.plain)
                .font(.sora(11))
                .frame(width: 180)
            if !transcriptSearchText.isEmpty {
                Text(searchCountLabel)
                    .font(.sora(9).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
                    .frame(minWidth: 44, alignment: .trailing)
                Button {
                    stepSearch(-1)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(transcriptSearchIndex.isEmpty)
                .help("Previous match")
                Button {
                    stepSearch(1)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(transcriptSearchIndex.isEmpty)
                .help("Next match")
                Button {
                    transcriptSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Clear transcript search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
    }

    private var searchCountLabel: String {
        guard !transcriptSearchIndex.isEmpty, let selectedSearchOrdinal else {
            return "0/0"
        }
        return "\(selectedSearchOrdinal + 1)/\(transcriptSearchIndex.count)"
    }

    private func stepSearch(_ delta: Int) {
        guard !transcriptSearchIndex.isEmpty else { return }
        let current = selectedSearchOrdinal ?? 0
        selectedSearchOrdinal = (current + delta + transcriptSearchIndex.count) % transcriptSearchIndex.count
    }

    private func transcriptPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.sora(12))
            .foregroundStyle(Color.stxMuted)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appSurface(.compactCard(radius: 8), padding: nil)
    }

    private func loadTranscript() async {
        transcriptIsLoading = true
        let messages = await env.store.transcriptMessages(for: session)
        guard !Task.isCancelled else { return }
        transcriptMessages = messages
        selectedSearchOrdinal = transcriptSearchIndex.isEmpty ? nil : 0
        transcriptIsLoading = false
    }

    // MARK: - Missing stats placeholder

    private var missingStatsPlaceholder: some View {
        Text(L10n.string("session.stats.not_parsed",
                         defaultValue: "Transcript stats haven't been parsed yet."))
            .font(.sora(12))
            .foregroundStyle(Color.stxMuted)
            .appSurface(.mainWindowCard, padding: 16)
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.filePath)])
            } label: {
                Label("Reveal Transcript", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.bordered)

            if let cwd = session.cwd, FileManager.default.fileExists(atPath: cwd) {
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
                } label: {
                    Label("Open Project Folder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)

            if let onDelete {
                Button(role: .destructive) {
                    onDelete(session)
                } label: {
                    Label(L10n.string("sessions.delete.single.button", defaultValue: "Delete Session"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .font(.sora(11))
    }
}

private struct TranscriptMessageRow: View {
    let message: SessionTranscriptMessage
    let matches: [TranscriptSearchMatch]
    let isSelectedMatch: Bool
    let modelDisplayName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(message.role.displayName, systemImage: message.role.symbol)
                    .font(.sora(10, weight: .semibold))
                    .foregroundStyle(message.role.accentColor)

                if let modelDisplayName {
                    Text(modelDisplayName)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }

                Spacer(minLength: 0)

                if let timestamp = message.timestamp {
                    Text(Format.shortDate(timestamp))
                        .font(.sora(10).monospacedDigit())
                        .foregroundStyle(Color.stxMuted)
                }
            }

            TranscriptMessageBody(text: message.text, role: message.role, matches: matches)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSurface(message.role == .tool ? .mainWindowCard : .compactCard(radius: 8), padding: nil)
        .overlay {
            if isSelectedMatch {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.stxAccent.opacity(0.9), lineWidth: 1.2)
            }
        }
    }
}

private struct TranscriptMessageBody: View {
    let text: String
    let role: SessionTranscriptMessage.Role
    let matches: [TranscriptSearchMatch]

    private var blocks: [TranscriptContentBlock] {
        TranscriptContentBlock.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                switch block.kind {
                case .markdown:
                    Text(highlighted(block.text, absoluteStart: block.absoluteStart))
                        .font(.sora(12))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let language):
                    VStack(alignment: .leading, spacing: 6) {
                        if let language, !language.isEmpty {
                            Text(language.uppercased())
                                .font(.sora(9, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(Color.stxMuted)
                        }
                        Text(highlighted(block.text, absoluteStart: block.absoluteStart))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.stxStroke.opacity(0.7), lineWidth: 1))
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if role == .tool {
                Text("TOOL DETAIL")
                    .font(.sora(8, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.stxMuted.opacity(0.7))
            }
        }
    }

    private func highlighted(_ text: String, absoluteStart: String.Index) -> AttributedString {
        var attributed = matches.isEmpty
            ? ((try? AttributedString(markdown: text)) ?? AttributedString(text))
            : AttributedString(text)
        guard !matches.isEmpty else { return attributed }
        let source = self.text
        for match in matches {
            guard match.range.lowerBound >= absoluteStart else { continue }
            let relativeLower = source.distance(from: absoluteStart, to: match.range.lowerBound)
            let relativeUpper = source.distance(from: absoluteStart, to: match.range.upperBound)
            guard relativeLower >= 0, relativeUpper <= text.count else {
                continue
            }
            let lower = attributed.index(attributed.startIndex, offsetByCharacters: relativeLower)
            let upper = attributed.index(attributed.startIndex, offsetByCharacters: relativeUpper)
            attributed[lower..<upper].foregroundColor = .black
            attributed[lower..<upper].backgroundColor = .stxAccent.opacity(0.75)
        }
        return attributed
    }
}

private struct TranscriptContentBlock: Identifiable {
    enum Kind {
        case markdown
        case code(language: String?)
    }

    let id = UUID()
    let kind: Kind
    let text: String
    let absoluteStart: String.Index

    static func parse(_ text: String) -> [TranscriptContentBlock] {
        var blocks: [TranscriptContentBlock] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            guard let fenceStart = text[cursor...].range(of: "```") else {
                appendMarkdown(String(text[cursor...]), start: cursor, to: &blocks)
                break
            }

            if fenceStart.lowerBound > cursor {
                appendMarkdown(String(text[cursor..<fenceStart.lowerBound]), start: cursor, to: &blocks)
            }

            var language: String?
            let lineEnd = text[fenceStart.upperBound...].firstIndex(of: "\n") ?? text.endIndex
            let languageText = text[fenceStart.upperBound..<lineEnd].trimmingCharacters(in: .whitespacesAndNewlines)
            if !languageText.isEmpty { language = languageText }

            let codeStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
            if let fenceEnd = text[codeStart...].range(of: "```") {
                blocks.append(
                    TranscriptContentBlock(
                        kind: .code(language: language),
                        text: String(text[codeStart..<fenceEnd.lowerBound]).trimmingCharacters(in: .newlines),
                        absoluteStart: codeStart
                    )
                )
                cursor = fenceEnd.upperBound
            } else {
                appendMarkdown(String(text[fenceStart.lowerBound...]), start: fenceStart.lowerBound, to: &blocks)
                break
            }
        }

        return blocks.isEmpty ? [TranscriptContentBlock(kind: .markdown, text: text, absoluteStart: text.startIndex)] : blocks
    }

    private static func appendMarkdown(_ text: String, start: String.Index, to blocks: inout [TranscriptContentBlock]) {
        let trimmed = text.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return }
        blocks.append(TranscriptContentBlock(kind: .markdown, text: trimmed, absoluteStart: start))
    }
}

private extension SessionTranscriptMessage.Role {
    var symbol: String {
        switch self {
        case .user: "person"
        case .assistant: "sparkles"
        case .tool: "wrench.and.screwdriver"
        case .system: "gearshape"
        }
    }

    var accentColor: Color {
        switch self {
        case .user: .stxAccent
        case .assistant: .primary
        case .tool: .stxMuted
        case .system: .stxMuted
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

#if DEBUG
#Preview {
    SessionDetailView(session: Session.previewSamples.first!)
        .environment(AppEnvironment.preview())
        .padding(24)
        .frame(width: 760, height: 600)
        .background(Color.stxBackground)
}
#endif
