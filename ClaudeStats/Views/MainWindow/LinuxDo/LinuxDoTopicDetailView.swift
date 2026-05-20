import AppKit
import SwiftUI

struct LinuxDoTopicDetailView: View {
    @Bindable var store: LinuxDoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let topicID = store.selectedTopicID, let state = store.topicStates[topicID] {
                detail(state: state, topicID: topicID)
            } else {
                ContentUnavailableView {
                    Label("Select a Topic", systemImage: "text.bubble")
                } description: {
                    Text("Choose a LinuxDo topic to read it here.")
                }
                .font(.sora(12))
            }
        }
    }

    @ViewBuilder
    private func detail(state: LinuxDoTopicDetailState, topicID: Int) -> some View {
        if state.isLoading && state.detail == nil {
            VStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else if let detail = state.detail {
            VStack(alignment: .leading, spacing: 0) {
                header(detail: detail, state: state)
                StxRule()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if let error = state.error {
                            LinuxDoInlineError(message: error)
                        }
                        ForEach(detail.posts) { post in
                            LinuxDoPostView(post: post)
                        }
                        if !state.remainingPostIDs.isEmpty {
                            Button {
                                Task { await store.loadMorePosts(topicID: topicID) }
                            } label: {
                                if state.isLoadingMore {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Load More Posts", systemImage: "arrow.down.circle")
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                    }
                    .padding(18)
                }
            }
        } else {
            ContentUnavailableView {
                Label("Topic Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(state.error ?? "Linux.do did not return this topic.")
            }
            .font(.sora(12))
        }
    }

    private func header(detail: LinuxDoTopicDetail, state: LinuxDoTopicDetailState) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(detail.displayTitle)
                    .font(.sora(18, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Label("\(detail.postsCount)", systemImage: "text.bubble")
                    if state.isStale {
                        Label("Stale", systemImage: "clock.badge.exclamationmark")
                    }
                }
                .font(.sora(10).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 8)
            if let url = detail.topicURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open", systemImage: "safari")
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct LinuxDoPostView: View {
    let post: LinuxDoPost

    private var blocks: [LinuxDoContentBlock] {
        LinuxDoContentParser.blocks(from: post.cookedHTML)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                AsyncImage(url: post.avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(Color.stxMuted)
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.name?.isEmpty == false ? post.name! : "@\(post.username)")
                        .font(.sora(12, weight: .semibold))
                    Text("#\(post.postNumber) - \(post.createdAt.map { Format.relativeDate($0) } ?? "Unknown time")")
                        .font(.sora(9))
                        .foregroundStyle(Color.stxMuted)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 9) {
                ForEach(blocks) { block in
                    LinuxDoContentBlockView(block: block)
                }
            }
            .padding(.leading, 36)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.035))
        }
    }
}

private struct LinuxDoContentBlockView: View {
    let block: LinuxDoContentBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .font(.sora(12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .quote(let text):
            Text(text)
                .font(.sora(12))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.stxAccent.opacity(0.4)).frame(width: 3)
                }
                .textSelection(.enabled)
        case .code(let text):
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("-")
                        Text(item)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.sora(12))
                }
            }
        case .image(let url):
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                ProgressView()
                    .controlSize(.small)
                    .frame(height: 80)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        case .link(let title, let url):
            Link(destination: url) {
                Label(title, systemImage: "link")
                    .font(.sora(12))
            }
        }
    }
}
