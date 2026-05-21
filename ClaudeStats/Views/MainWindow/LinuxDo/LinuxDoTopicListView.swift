import SwiftUI

struct LinuxDoTopicListView: View {
    @Bindable var store: LinuxDoStore

    private var state: LinuxDoListState {
        store.currentListState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            listHeader
            StxRule()
            content
        }
        .background(Color.primary.opacity(0.018))
    }

    private var listHeader: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.selectedFeed.title)
                    .font(.sora(15, weight: .semibold))
                    .lineLimit(1)
                if let lastFetchedAt = state.lastFetchedAt {
                    Text("Updated \(Format.relativeDate(lastFetchedAt))")
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                } else {
                    Text("Linux.do")
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                }
            }
            Spacer(minLength: 8)
            if state.isLoading || state.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if state.isLoading && state.topics.isEmpty {
            VStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else if state.topics.isEmpty {
            ContentUnavailableView {
                Label("No Topics", systemImage: "tray")
            } description: {
                Text(state.error ?? "Nothing to show for this feed yet.")
            }
            .font(.sora(12))
        } else {
            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let error = state.error {
                        LinuxDoInlineError(message: error)
                            .padding(12)
                    }
                    ForEach(state.topics) { topic in
                        LinuxDoTopicRow(topic: topic, isSelected: store.selectedTopicID == topic.id) {
                            store.selectTopic(topic)
                        }
                        .onAppear {
                            if topic.id == state.topics.last?.id {
                                Task { await store.loadMoreCurrentFeed() }
                            }
                        }
                        StxRule()
                    }
                    if state.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                    }
                }
            }
        }
    }
}

private struct LinuxDoTopicRow: View {
    let topic: LinuxDoTopicSummary
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Text(topic.displayTitle)
                    .font(.sora(12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !topic.displayExcerpt.isEmpty {
                    Text(topic.displayExcerpt)
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    stat("bubble.left", topic.replyCount)
                    stat("eye", topic.views)
                    stat("heart", topic.likeCount)
                    Spacer(minLength: 4)
                    if let date = topic.lastPostedAt ?? topic.bumpedAt ?? topic.createdAt {
                        Text(Format.relativeDate(date))
                            .font(.sora(9))
                            .foregroundStyle(Color.stxMuted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    Rectangle().fill(Color.stxAccent.opacity(0.11))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func stat(_ symbol: String, _ value: Int) -> some View {
        Label("\(value)", systemImage: symbol)
            .font(.sora(9).monospacedDigit())
            .foregroundStyle(Color.stxMuted)
            .labelStyle(.titleAndIcon)
    }
}

struct LinuxDoInlineError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.sora(11))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}
