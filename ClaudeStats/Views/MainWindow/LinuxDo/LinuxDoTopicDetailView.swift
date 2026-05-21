import AppKit
import SwiftUI

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
                            .padding(.horizontal, 24)
                            .padding(.top, 14)
                    }
                    if let warning = state.timelineWarning {
                        LinuxDoInlineError(message: warning)
                            .padding(.horizontal, 24)
                            .padding(.top, 14)
                    }
                    ForEach(detail.posts) { post in
                        LinuxDoPostView(post: post, isTopicOwner: post.postNumber == 1)
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
                                if post.id == detail.posts.last?.id, !state.remainingPostIDs.isEmpty {
                                    Task { await store.loadMorePosts(topicID: topicID) }
                                }
                            }
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
                        .padding(.vertical, 18)
                    }
                }
                .frame(maxWidth: 848, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .top)
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
        visiblePostNumber = max(1, visible.postNumber)
    }

    private func header(detail: LinuxDoTopicDetail, state: LinuxDoTopicDetailState) -> some View {
        HStack(alignment: .top, spacing: 12) {
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
    let isTopicOwner: Bool

    private var blocks: [LinuxDoContentBlock] {
        LinuxDoContentParser.blocks(from: post.cookedHTML)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
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

            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(post.name?.isEmpty == false ? post.name! : "@\(post.username)")
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

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(blocks) { block in
                        LinuxDoContentBlockView(block: block)
                    }
                }

                HStack(spacing: 12) {
                    if post.likeCount > 0 {
                        Label("\(post.likeCount)", systemImage: "heart")
                    }
                    if post.replyCount > 0 {
                        Label("\(post.replyCount)", systemImage: "arrowshape.turn.up.left")
                    }
                    if post.reads > 0 {
                        Label("\(post.reads)", systemImage: "eye")
                    }
                    Spacer(minLength: 0)
                }
                .font(.sora(9).monospacedDigit())
                .foregroundStyle(Color.stxMuted)
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

private struct LinuxDoPostVisibilityPreference: PreferenceKey {
    static let defaultValue: [LinuxDoPostVisibility] = []

    static func reduce(value: inout [LinuxDoPostVisibility], nextValue: () -> [LinuxDoPostVisibility]) {
        value.append(contentsOf: nextValue())
    }
}
