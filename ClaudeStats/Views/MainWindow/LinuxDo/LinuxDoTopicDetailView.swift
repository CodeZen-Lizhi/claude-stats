import AppKit
import SwiftUI

private enum LinuxDoDetailLayout {
    static let contentLeading: CGFloat = 84
    static let contentTrailing: CGFloat = 24
    static let contentMaxWidth: CGFloat = 848
    static let avatarColumnWidth: CGFloat = 48
    static let avatarSpacing: CGFloat = 14
    static var postRowLeading: CGFloat { contentLeading - avatarColumnWidth - avatarSpacing }
    static var headerLeading: CGFloat { postRowLeading }
    static var headerMaxWidth: CGFloat { contentMaxWidth + avatarColumnWidth + avatarSpacing }
    static var totalMaxWidth: CGFloat { contentLeading + contentMaxWidth + contentTrailing }
}

struct LinuxDoTopicDetailView: View {
    @Bindable var store: LinuxDoStore
    @State private var visiblePostNumber = 1

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
                HStack(spacing: 0) {
                    topicScroll(detail: detail, state: state, topicID: topicID)
                    Rectangle()
                        .fill(Color.stxStroke)
                        .frame(width: 1)
                    LinuxDoTimelineRail(
                        currentFloor: visiblePostNumber,
                        totalFloors: max(detail.stream.count, detail.postsCount, detail.posts.count),
                        isLoading: state.isJumping || state.isLoadingMore
                    ) { floor in
                        Task { await store.jumpToPostIndex(topicID: topicID, index: floor - 1) }
                    }
                    .frame(width: 72)
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

    private func topicScroll(detail: LinuxDoTopicDetail, state: LinuxDoTopicDetailState, topicID: Int) -> some View {
        ScrollViewReader { proxy in
            AppScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let error = state.error {
                        LinuxDoInlineError(message: error)
                            .padding(.leading, LinuxDoDetailLayout.contentLeading)
                            .padding(.trailing, LinuxDoDetailLayout.contentTrailing)
                            .padding(.top, 14)
                    }
                    if let warning = state.timelineWarning {
                        LinuxDoInlineError(message: warning)
                            .padding(.leading, LinuxDoDetailLayout.contentLeading)
                            .padding(.trailing, LinuxDoDetailLayout.contentTrailing)
                            .padding(.top, 14)
                    }
                    ForEach(detail.posts) { post in
                        LinuxDoPostView(
                            post: post,
                            contentBlocks: store.contentBlocks(for: post),
                            isTopicOwner: post.postNumber == 1,
                            repliesState: state.replyStates[post.id] ?? LinuxDoPostRepliesState(),
                            replyComposer: state.replyComposers[post.id] ?? LinuxDoComposerState(),
                            replyDraft: Binding(
                                get: { store.topicStates[topicID]?.replyComposers[post.id]?.raw ?? "" },
                                set: { store.setReplyDraft(topicID: topicID, postID: post.id, raw: $0) }
                            ),
                            emojiURL: { store.emojiURL(for: $0) },
                            isLikePending: state.pendingLikePostIDs.contains(post.id),
                            isReactionPending: state.pendingReactionPostIDs.contains(post.id),
                            canWrite: store.canWriteForum,
                            onToggleReplies: { store.toggleReplies(topicID: topicID, postID: post.id) },
                            onBeginReply: { store.beginReply(topicID: topicID, postID: post.id) },
                            onCancelReply: { store.cancelReply(topicID: topicID, postID: post.id) },
                            onSubmitReply: { Task { await store.submitReply(topicID: topicID, postID: post.id) } },
                            onToggleLike: { Task { await store.toggleLike(topicID: topicID, postID: post.id) } },
                            onToggleReaction: { reactionID in Task { await store.toggleReaction(topicID: topicID, postID: post.id, reactionID: reactionID) } },
                            onOpenInBrowser: {
                                if let url = post.postURL ?? detail.topicURL {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        )
                            .padding(.leading, LinuxDoDetailLayout.postRowLeading)
                            .padding(.trailing, LinuxDoDetailLayout.contentTrailing)
                            .id(post.id)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: LinuxDoPostVisibilityPreference.self,
                                        value: [LinuxDoPostVisibility(
                                            id: post.id,
                                            postNumber: post.postNumber,
                                            minY: geometry.frame(in: .named("linuxdo-topic-scroll")).minY
                                        )]
                                    )
                                }
                            }
                            .onAppear {
                                if post.id == detail.posts.last?.id, state.hasMorePosts {
                                    Task { await store.loadMorePosts(topicID: topicID) }
                                }
                            }
                    }
                    if state.hasMorePosts {
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
                        .frame(maxWidth: LinuxDoDetailLayout.contentMaxWidth)
                        .padding(.leading, LinuxDoDetailLayout.contentLeading)
                        .padding(.trailing, LinuxDoDetailLayout.contentTrailing)
                        .padding(.vertical, 18)
                    }
                }
                .frame(maxWidth: LinuxDoDetailLayout.totalMaxWidth, alignment: .leading)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .coordinateSpace(name: "linuxdo-topic-scroll")
            .onPreferenceChange(LinuxDoPostVisibilityPreference.self) { values in
                updateVisiblePost(values)
            }
            .onChange(of: state.scrollTargetPostID, initial: true) { _, postID in
                guard let postID else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(postID, anchor: .top)
                }
                store.consumeScrollTarget(topicID: topicID, postID: postID)
            }
        }
    }

    private func updateVisiblePost(_ values: [LinuxDoPostVisibility]) {
        guard let visible = values.min(by: { abs($0.minY - 12) < abs($1.minY - 12) }) else { return }
        let nextPostNumber = max(1, visible.postNumber)
        guard nextPostNumber != visiblePostNumber else { return }
        visiblePostNumber = nextPostNumber
    }

    private func header(detail: LinuxDoTopicDetail, state: LinuxDoTopicDetailState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.displayTitle)
                .font(.sora(18, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Label("\(detail.postsCount)", systemImage: "text.bubble")
                Label("\(detail.posts.count) loaded", systemImage: "tray.and.arrow.down")
                if state.isStale {
                    Label("Stale", systemImage: "clock.badge.exclamationmark")
                }
                if state.isJumping {
                    Label("Jumping", systemImage: "arrow.up.and.down")
                }
            }
            .font(.sora(10).monospacedDigit())
            .foregroundStyle(Color.stxMuted)

            if !detail.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(detail.tags.prefix(6), id: \.self) { tag in
                        Text(tag)
                            .font(.sora(9, weight: .medium))
                            .foregroundStyle(Color.stxAccent)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(Color.stxAccent.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: LinuxDoDetailLayout.headerMaxWidth, alignment: .leading)
        .padding(.leading, LinuxDoDetailLayout.headerLeading)
        .padding(.trailing, LinuxDoDetailLayout.contentTrailing)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LinuxDoPostView: View {
    let post: LinuxDoPost
    let contentBlocks: [LinuxDoContentBlock]
    let isTopicOwner: Bool
    let repliesState: LinuxDoPostRepliesState
    let replyComposer: LinuxDoComposerState
    @Binding var replyDraft: String
    let emojiURL: (String) -> URL?
    let isLikePending: Bool
    let isReactionPending: Bool
    let canWrite: Bool
    let onToggleReplies: () -> Void
    let onBeginReply: () -> Void
    let onCancelReply: () -> Void
    let onSubmitReply: () -> Void
    let onToggleLike: () -> Void
    let onToggleReaction: (String) -> Void
    let onOpenInBrowser: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            LinuxDoPostAvatarColumn(post: post, isTopicOwner: isTopicOwner)

            VStack(alignment: .leading, spacing: 11) {
                LinuxDoPostHeader(post: post, isTopicOwner: isTopicOwner)

                LinuxDoPostBody(contentBlocks: contentBlocks)

                LinuxDoReactionChipRow(
                    reactions: post.visibleReactions,
                    currentUserReaction: post.currentUserReaction,
                    emojiURL: emojiURL,
                    isPending: isReactionPending,
                    onToggleReaction: onToggleReaction
                )

                LinuxDoPostActionBar(
                    post: post,
                    repliesState: repliesState,
                    isLikePending: isLikePending,
                    isReactionPending: isReactionPending,
                    canWrite: canWrite,
                    emojiURL: emojiURL,
                    onToggleReplies: onToggleReplies,
                    onBeginReply: onBeginReply,
                    onToggleLike: onToggleLike,
                    onToggleReaction: onToggleReaction,
                    onOpenInBrowser: onOpenInBrowser
                )

                LinuxDoPostReplyPreviewList(
                    repliesState: repliesState,
                    contentBlocks: { LinuxDoContentParser.blocks(from: $0.cookedHTML) }
                )

                if replyComposer.isPresented {
                    LinuxDoComposer(
                        title: "Reply to #\(post.postNumber)",
                        placeholder: "Write a reply",
                        raw: $replyDraft,
                        isSubmitting: replyComposer.isSubmitting,
                        error: replyComposer.error,
                        canSubmit: replyComposer.canSubmitReply,
                        submitTitle: "Reply",
                        onCancel: onCancelReply,
                        onSubmit: onSubmitReply
                    )
                }
            }
            .padding(.bottom, 16)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
            }
        }
        .padding(.top, 18)
    }
}

private struct LinuxDoPostAvatarColumn: View {
    let post: LinuxDoPost
    let isTopicOwner: Bool

    var body: some View {
        VStack(spacing: 8) {
            AsyncImage(url: post.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(Color.stxMuted)
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.stxAccent.opacity(isTopicOwner ? 0.45 : 0.18), lineWidth: 1))

            Text("#\(post.postNumber)")
                .font(.sora(9).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
        }
        .frame(width: 48)
    }
}

private struct LinuxDoPostHeader: View {
    let post: LinuxDoPost
    let isTopicOwner: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(post.displayAuthorName)
                .font(.sora(12, weight: .semibold))
            if isTopicOwner {
                Text("OP")
                    .font(.sora(8, weight: .bold))
                    .foregroundStyle(Color.stxAccent)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(Color.stxAccent.opacity(0.12), in: Capsule())
            }
            if let replyTo = post.replyToPostNumber {
                Text("replying to #\(replyTo)")
                    .font(.sora(9))
                    .foregroundStyle(Color.stxMuted)
            }
            Spacer(minLength: 0)
            Text(post.createdAt.map { Format.relativeDate($0) } ?? "Unknown time")
                .font(.sora(9))
                .foregroundStyle(Color.stxMuted)
        }
    }
}

private struct LinuxDoPostBody: View {
    let contentBlocks: [LinuxDoContentBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(contentBlocks) { block in
                LinuxDoContentBlockView(block: block)
            }
        }
    }
}

private struct LinuxDoReactionChipRow: View {
    let reactions: [LinuxDoReaction]
    let currentUserReaction: String?
    let emojiURL: (String) -> URL?
    let isPending: Bool
    let onToggleReaction: (String) -> Void

    var body: some View {
        if !reactions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(reactions) { reaction in
                        Button {
                            onToggleReaction(reaction.id)
                        } label: {
                            HStack(spacing: 5) {
                                LinuxDoReactionGlyph(
                                    reactionID: reaction.id,
                                    displayText: reaction.displayText,
                                    imageURL: emojiURL(reaction.id),
                                    size: 18
                                )
                                Text("\(reaction.count)")
                                    .font(.sora(10, weight: .semibold).monospacedDigit())
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(chipBackground(for: reaction), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isPending)
                        .help("React with \(reaction.id)")
                    }
                }
            }
        }
    }

    private func chipBackground(for reaction: LinuxDoReaction) -> Color {
        currentUserReaction == reaction.id ? Color.stxAccent.opacity(0.18) : Color.primary.opacity(0.055)
    }
}

private struct LinuxDoPostActionBar: View {
    let post: LinuxDoPost
    let repliesState: LinuxDoPostRepliesState
    let isLikePending: Bool
    let isReactionPending: Bool
    let canWrite: Bool
    let emojiURL: (String) -> URL?
    let onToggleReplies: () -> Void
    let onBeginReply: () -> Void
    let onToggleLike: () -> Void
    let onToggleReaction: (String) -> Void
    let onOpenInBrowser: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleLike) {
                Label("\(post.effectiveLikeCount)", systemImage: post.isLikedByCurrentUser ? "heart.fill" : "heart")
                    .foregroundStyle(post.isLikedByCurrentUser ? .red : Color.stxMuted)
            }
            .disabled(!canWrite || isLikePending || !post.canToggleLike)
            .help(canWrite ? "Like" : "Sign in with a browser session to like")

            Button(action: onBeginReply) {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
            .disabled(!canWrite)
            .help(canWrite ? "Reply" : "Sign in with a browser session to reply")

            if post.replyCount > 0 || repliesState.hasLoaded {
                Button(action: onToggleReplies) {
                    Label(
                        repliesState.isExpanded ? "Hide \(max(post.replyCount, repliesState.replies.count))" : "\(max(post.replyCount, repliesState.replies.count)) replies",
                        systemImage: repliesState.isExpanded ? "chevron.up" : "chevron.down"
                    )
                }
                .disabled(repliesState.isLoading)
                .help(repliesState.isExpanded ? "Hide replies" : "Show replies")
            }

            Menu {
                ForEach(LinuxDoReactionCatalog.defaultReactionIDs, id: \.self) { reactionID in
                    Button {
                        onToggleReaction(reactionID)
                    } label: {
                        HStack {
                            LinuxDoReactionGlyph(
                                reactionID: reactionID,
                                displayText: LinuxDoReactionCatalog.displayText(for: reactionID),
                                imageURL: emojiURL(reactionID),
                                size: 16
                            )
                            Text(reactionID)
                        }
                    }
                }
            } label: {
                Image(systemName: "face.smiling")
                    .frame(width: 18, height: 18)
            }
            .disabled(!canWrite || isReactionPending)
            .help(canWrite ? "Add reaction" : "Sign in with a browser session to react")

            if post.reads > 0 {
                Label("\(post.reads)", systemImage: "eye")
                    .foregroundStyle(Color.stxMuted)
            }

            Spacer(minLength: 0)

            Button(action: onOpenInBrowser) {
                Image(systemName: "safari")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.stxMuted)
            .help("Open in browser")
        }
        .buttonStyle(.plain)
        .font(.sora(10).monospacedDigit())
        .foregroundStyle(Color.stxMuted)
    }
}

private struct LinuxDoReactionGlyph: View {
    let reactionID: String
    let displayText: String
    let imageURL: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(reactionID))
    }

    private var fallback: some View {
        Text(displayText)
            .font(.sora(size - 2))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

private struct LinuxDoPostReplyPreviewList: View {
    let repliesState: LinuxDoPostRepliesState
    let contentBlocks: (LinuxDoPost) -> [LinuxDoContentBlock]

    var body: some View {
        if repliesState.isExpanded {
            VStack(alignment: .leading, spacing: 0) {
                if repliesState.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading replies")
                            .font(.sora(10))
                            .foregroundStyle(Color.stxMuted)
                    }
                    .padding(.vertical, 8)
                }

                if let error = repliesState.error {
                    LinuxDoInlineError(message: error)
                        .padding(.vertical, 8)
                }

                ForEach(repliesState.replies) { reply in
                    LinuxDoReplyPreviewRow(reply: reply, contentBlocks: contentBlocks(reply))
                }
            }
            .padding(.top, 4)
        }
    }
}

private struct LinuxDoReplyPreviewRow: View {
    let reply: LinuxDoPost
    let contentBlocks: [LinuxDoContentBlock]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(reply.effectiveLikeCount)")
                .font(.sora(10, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
                .frame(width: 28, alignment: .trailing)
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.stxMuted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(reply.textPreview)
                        .font(.sora(11, weight: .medium))
                        .lineLimit(2)
                    Text("–")
                        .foregroundStyle(Color.stxMuted)
                    Text(reply.displayAuthorName)
                        .foregroundStyle(Color.stxAccent)
                    Text(reply.createdAt.map { Format.relativeDate($0) } ?? "")
                        .foregroundStyle(Color.stxMuted)
                }
                .font(.sora(10))

                if contentBlocks.count > 1 {
                    Text(contentBlocks.dropFirst().map { plainText($0) }.joined(separator: " "))
                        .font(.sora(10))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
        }
    }

    private func plainText(_ block: LinuxDoContentBlock) -> String {
        switch block.kind {
        case .paragraph(let nodes), .heading(_, let nodes):
            nodes.map(\.plainPreview).joined()
        case .quote(_, let blocks), .details(_, let blocks), .spoiler(let blocks):
            blocks.map(plainText).joined(separator: " ")
        case .codeBlock(_, let code), .rawHTML(let code):
            code
        case .list(_, let items):
            items.flatMap(\.blocks).map(plainText).joined(separator: " ")
        case .image, .onebox, .table, .divider:
            ""
        }
    }
}

private struct LinuxDoComposer: View {
    let title: String
    let placeholder: String
    @Binding var raw: String
    let isSubmitting: Bool
    let error: String?
    let canSubmit: Bool
    let submitTitle: String
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.sora(11, weight: .semibold))
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .controlSize(.small)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $raw)
                    .font(.sora(12))
                    .frame(minHeight: 84)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                if raw.isEmpty {
                    Text(placeholder)
                        .font(.sora(12))
                        .foregroundStyle(Color.stxMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .padding(6)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            }

            if let error {
                LinuxDoInlineError(message: error)
            }

            HStack {
                Spacer(minLength: 0)
                Button {
                    onSubmit()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(submitTitle, systemImage: "paperplane")
                    }
                }
                .controlSize(.small)
                .disabled(!canSubmit)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
        .onAppear {
            isFocused = true
        }
    }
}

private struct LinuxDoContentBlockView: View {
    let block: LinuxDoContentBlock

    var body: some View {
        switch block.kind {
        case .paragraph(let nodes):
            LinuxDoInlineText(nodes: nodes)
                .font(.sora(12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let nodes):
            LinuxDoInlineText(nodes: nodes)
                .font(.sora(headingSize(for: level), weight: .semibold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 4 : 2)
        case .quote(let attribution, let blocks):
            VStack(alignment: .leading, spacing: 8) {
                if let attribution {
                    HStack(spacing: 6) {
                        if let avatarURL = attribution.avatarURL {
                            AsyncImage(url: avatarURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "quote.bubble")
                                    .foregroundStyle(Color.stxMuted)
                            }
                            .frame(width: 18, height: 18)
                            .clipShape(Circle())
                        }
                        Text(attribution.username ?? attribution.topicTitle ?? "Quote")
                            .font(.sora(10, weight: .semibold))
                            .foregroundStyle(Color.stxMuted)
                    }
                }
                ForEach(blocks) { child in
                    LinuxDoContentBlockView(block: child)
                }
            }
            .padding(.vertical, 8)
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.stxAccent.opacity(0.45)).frame(width: 3)
            }
        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 0) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.sora(9, weight: .semibold))
                        .foregroundStyle(Color.stxMuted)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                }
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(code)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                }
            }
            .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 8) {
                        Text(ordered ? "\(index + 1)." : "-")
                            .font(.sora(12).monospacedDigit())
                            .foregroundStyle(Color.stxMuted)
                            .frame(width: ordered ? 26 : 14, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(items[index].blocks) { itemBlock in
                                LinuxDoContentBlockView(block: itemBlock)
                            }
                        }
                    }
                }
            }
        case .image(let url, let alt, _, _, let linkURL):
            Button {
                NSWorkspace.shared.open(linkURL ?? url)
            } label: {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                        .controlSize(.small)
                        .frame(height: 90)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: 460)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(alt ?? "LinuxDo image")
            }
            .buttonStyle(.plain)
        case .onebox(let onebox):
            LinuxDoOneboxView(onebox: onebox)
        case .table(let headers, let rows):
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    if !headers.isEmpty {
                        GridRow {
                            ForEach(headers.indices, id: \.self) { index in
                                tableCell(headers[index], isHeader: true)
                            }
                        }
                    }
                    ForEach(rows.indices, id: \.self) { rowIndex in
                        GridRow {
                            ForEach(rows[rowIndex].indices, id: \.self) { columnIndex in
                                tableCell(rows[rowIndex][columnIndex], isHeader: false)
                            }
                        }
                    }
                }
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 6))
            }
        case .details(let summary, let blocks):
            LinuxDoDisclosureBlockView(summary: summary, blocks: blocks, icon: "chevron.right")
        case .spoiler(let blocks):
            LinuxDoDisclosureBlockView(summary: [.text("Spoiler")], blocks: blocks, icon: "eye.slash")
        case .divider:
            StxRule()
                .padding(.vertical, 5)
        case .rawHTML(let text):
            Text(text)
                .font(.sora(12))
                .foregroundStyle(Color.stxMuted)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: 20
        case 2: 17
        case 3: 15
        default: 13
        }
    }

    private func tableCell(_ blocks: [LinuxDoContentBlock], isHeader: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(blocks) { block in
                LinuxDoContentBlockView(block: block)
            }
        }
        .font(isHeader ? .sora(11, weight: .semibold) : .sora(11))
        .padding(8)
        .frame(minWidth: 120, alignment: .topLeading)
        .border(Color.primary.opacity(0.12), width: 0.5)
    }
}

private struct LinuxDoInlineText: View {
    let nodes: [LinuxDoInlineNode]

    var body: some View {
        Text(Self.attributedString(from: nodes))
            .environment(\.openURL, OpenURLAction { url in
                NSWorkspace.shared.open(url)
                return .handled
            })
    }

    private static func attributedString(from nodes: [LinuxDoInlineNode]) -> AttributedString {
        var result = AttributedString()
        append(nodes, to: &result)
        return result
    }

    private static func append(_ nodes: [LinuxDoInlineNode], to result: inout AttributedString) {
        for node in nodes {
            switch node {
            case .text(let text):
                result.append(AttributedString(text))
            case .strong(let children), .emphasis(let children), .strikethrough(let children), .spoiler(let children):
                append(children, to: &result)
            case .code(let text):
                var run = AttributedString(text)
                run.font = .system(.caption, design: .monospaced)
                run.backgroundColor = Color.primary.opacity(0.08)
                result.append(run)
            case .link(let url, let children):
                var run = attributedString(from: children)
                run.link = url
                run.foregroundColor = Color.stxAccent
                result.append(run)
            case .image(_, let alt, _, _, let isEmoji):
                result.append(AttributedString(isEmoji ? (alt ?? "") : (alt ?? "[image]")))
            case .mention(let username, let url):
                var run = AttributedString("@\(username)")
                run.foregroundColor = Color.stxAccent
                if let url { run.link = url }
                result.append(run)
            case .hashtag(let text, let url):
                var run = AttributedString(text.hasPrefix("#") ? text : "#\(text)")
                run.foregroundColor = Color.stxAccent
                if let url { run.link = url }
                result.append(run)
            case .lineBreak:
                result.append(AttributedString("\n"))
            }
        }
    }
}

private struct LinuxDoOneboxView: View {
    let onebox: LinuxDoOnebox

    var body: some View {
        Button {
            if let url = onebox.url {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if let imageURL = onebox.imageURL {
                    AsyncImage(url: imageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.primary.opacity(0.05)
                    }
                    .frame(width: 72, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(onebox.title ?? onebox.url?.host() ?? "Link")
                        .font(.sora(12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let description = onebox.description, !description.isEmpty {
                        Text(description)
                            .font(.sora(10))
                            .foregroundStyle(Color.stxMuted)
                            .lineLimit(2)
                    }
                    if let url = onebox.url {
                        Text(url.host() ?? url.absoluteString)
                            .font(.sora(9))
                            .foregroundStyle(Color.stxAccent)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(onebox.url == nil)
    }
}

private struct LinuxDoDisclosureBlockView: View {
    let summary: [LinuxDoInlineNode]
    let blocks: [LinuxDoContentBlock]
    let icon: String
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(blocks) { block in
                    LinuxDoContentBlockView(block: block)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
                LinuxDoInlineText(nodes: summary)
                    .font(.sora(11, weight: .medium))
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct LinuxDoTimelineRail: View {
    let currentFloor: Int
    let totalFloors: Int
    let isLoading: Bool
    let onJump: (Int) -> Void

    var body: some View {
        VStack(spacing: 10) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.stxMuted)
            }
            Text("\(min(currentFloor, totalFloors))")
                .font(.sora(14, weight: .semibold).monospacedDigit())
            Text("/ \(max(totalFloors, 1))")
                .font(.sora(9).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    Capsule()
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 4)
                    Capsule()
                        .fill(Color.stxAccent.opacity(0.75))
                        .frame(width: 4, height: handleY(in: geometry.size.height) + 8)
                    Circle()
                        .fill(Color.stxAccent)
                        .frame(width: 14, height: 14)
                        .offset(y: handleY(in: geometry.size.height))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            onJump(floor(at: value.location.y, height: geometry.size.height))
                        }
                )
            }
            .frame(minHeight: 150)
            Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.018))
    }

    private func handleY(in height: CGFloat) -> CGFloat {
        guard totalFloors > 1 else { return 0 }
        let ratio = CGFloat(max(0, min(currentFloor - 1, totalFloors - 1))) / CGFloat(totalFloors - 1)
        return max(0, min(height - 14, ratio * (height - 14)))
    }

    private func floor(at y: CGFloat, height: CGFloat) -> Int {
        guard totalFloors > 1, height > 14 else { return 1 }
        let ratio = max(0, min(1, y / max(1, height - 14)))
        return max(1, min(totalFloors, Int((ratio * CGFloat(totalFloors - 1)).rounded()) + 1))
    }
}

private struct LinuxDoPostVisibility: Equatable {
    let id: Int
    let postNumber: Int
    let minY: CGFloat
}

private extension LinuxDoInlineNode {
    var plainPreview: String {
        switch self {
        case .text(let text), .code(let text):
            text
        case .strong(let children), .emphasis(let children), .strikethrough(let children), .spoiler(let children):
            children.map(\.plainPreview).joined()
        case .link(_, let children):
            children.map(\.plainPreview).joined()
        case .image(_, let alt, _, _, _):
            alt ?? ""
        case .mention(let username, _):
            "@\(username)"
        case .hashtag(let text, _):
            text
        case .lineBreak:
            "\n"
        }
    }
}

private struct LinuxDoPostVisibilityPreference: PreferenceKey {
    static let defaultValue: [LinuxDoPostVisibility] = []

    static func reduce(value: inout [LinuxDoPostVisibility], nextValue: () -> [LinuxDoPostVisibility]) {
        value.append(contentsOf: nextValue())
    }
}
