import Foundation
import SwiftSoup

enum LinuxDoContentParser {
    static func blocks(from cookedHTML: String) -> [LinuxDoContentBlock] {
        var parser = LinuxDoContentDOMParser()
        return parser.parse(cookedHTML)
    }
}

private struct LinuxDoContentDOMParser {
    private var blockCounter = 0

    mutating func parse(_ cookedHTML: String) -> [LinuxDoContentBlock] {
        do {
            let document = try SwiftSoup.parseBodyFragment(cookedHTML, LinuxDoURLResolver.baseURL.absoluteString)
            guard let body = document.body() else { return [] }
            let blocks = try blocks(from: body.getChildNodes(), path: "body")
            return blocks.isEmpty ? [block(.rawHTML(cookedHTML.htmlStrippedAndDecoded), path: "body.raw")] : blocks
        } catch {
            return [block(.rawHTML(cookedHTML.htmlStrippedAndDecoded), path: "body.raw")]
        }
    }

    private mutating func blocks(from nodes: [Node], path: String) throws -> [LinuxDoContentBlock] {
        var result: [LinuxDoContentBlock] = []
        var inlineBuffer: [LinuxDoInlineNode] = []

        func flushInlineBuffer() {
            let trimmed = Self.trimmed(inlineBuffer)
            if !Self.isEmpty(trimmed) {
                result.append(block(.paragraph(trimmed), path: "\(path).p\(result.count)"))
            }
            inlineBuffer.removeAll()
        }

        for (index, node) in nodes.enumerated() {
            let childPath = "\(path).\(index)"
            if let text = node as? TextNode {
                let value = Self.normalizedInlineText(text.getWholeText())
                if !value.isEmpty {
                    inlineBuffer.append(.text(value))
                }
                continue
            }

            guard let element = node as? Element else { continue }
            if isBlockElement(element) {
                flushInlineBuffer()
                result.append(contentsOf: try blockElements(from: element, path: childPath))
            } else {
                inlineBuffer.append(contentsOf: try inlineNodes(from: element, path: childPath))
            }
        }

        flushInlineBuffer()
        return result
    }

    private mutating func blockElements(from element: Element, path: String) throws -> [LinuxDoContentBlock] {
        let tag = element.tagNameNormal()

        if let event = postEvent(from: element) {
            return [block(.event(event), path: path)]
        }
        if let callout = try calloutBlock(from: element, path: path) {
            return [callout]
        }
        if let onebox = try onebox(from: element) {
            return [block(.onebox(onebox), path: path)]
        }
        if let image = try imageBlock(from: element, path: path) {
            return [image]
        }

        switch tag {
        case "p":
            let inline = Self.trimmed(try inlineNodes(from: element, path: path))
            return paragraphBlocks(from: inline, path: path)
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(tag.dropFirst()) ?? 3
            let inline = Self.trimmed(try inlineNodes(from: element, path: path))
            return Self.isEmpty(inline) ? [] : [block(.heading(level: level, content: inline), path: path)]
        case "aside":
            if element.hasClass("quote") {
                return try discourseQuoteBlocks(from: element, path: path)
            }
            return try blocks(from: element.getChildNodes(), path: path)
        case "blockquote":
            let attribution = try quoteAttribution(from: element)
            let childBlocks = try blocks(from: element.getChildNodes(), path: "\(path).quote")
            return childBlocks.isEmpty ? [] : [block(.quote(attribution: attribution, blocks: childBlocks), path: path)]
        case "pre":
            return [block(.codeBlock(language: try codeLanguage(from: element), code: try codeText(from: element)), path: path)]
        case "ul", "ol":
            return [block(.list(ordered: tag == "ol", items: try listItems(from: element, path: path)), path: path)]
        case "table":
            return [block(try table(from: element, path: path), path: path)]
        case "details":
            return [block(try details(from: element, path: path), path: path)]
        case "hr":
            return [block(.divider, path: path)]
        default:
            if isSpoiler(element) {
                let childBlocks = try blocks(from: element.getChildNodes(), path: "\(path).spoiler")
                return [block(.spoiler(childBlocks), path: path)]
            }
            return try blocks(from: element.getChildNodes(), path: path)
        }
    }

    private mutating func inlineNodes(from element: Element, path: String) throws -> [LinuxDoInlineNode] {
        let tag = element.tagNameNormal()
        switch tag {
        case "br":
            return [.lineBreak]
        case "input":
            return []
        case "code":
            return [.code(try element.text(trimAndNormaliseWhitespace: false))]
        case "kbd":
            return [.keyboard(try inlineChildren(from: element, path: path))]
        case "mark":
            return [.highlight(try inlineChildren(from: element, path: path))]
        case "sub":
            return [.subscript(try inlineChildren(from: element, path: path))]
        case "sup":
            return [.superscript(try inlineChildren(from: element, path: path))]
        case "strong", "b":
            return [.strong(try inlineChildren(from: element, path: path))]
        case "em", "i":
            return [.emphasis(try inlineChildren(from: element, path: path))]
        case "s", "strike", "del":
            return [.strikethrough(try inlineChildren(from: element, path: path))]
        case "a":
            if isEmptyAnchor(element) {
                return []
            }
            if element.hasClass("mention"),
               let username = try element.text().split(separator: "@").last.map(String.init) {
                return [.mention(username: username, url: resolvedURL(try? element.attr("href")))]
            }
            if element.hasClass("hashtag-cooked") || element.hasClass("discourse-tag") {
                let text = try element.text()
                return [.hashtag(text: text, url: resolvedURL(try? element.attr("href")))]
            }
            if let url = resolvedURL(try? element.attr("href")) {
                let children = try inlineChildren(from: element, path: path)
                return [.link(url: url, children: Self.isEmpty(children) ? [.text(url.absoluteString)] : children)]
            }
            return try inlineChildren(from: element, path: path)
        case "img":
            guard !element.hasClass("avatar") else { return [] }
            guard let url = resolvedURL(try? element.attr("src")) else { return [] }
            return [.image(
                url: url,
                alt: optionalAttribute("alt", from: element),
                width: integerAttribute("width", from: element),
                height: integerAttribute("height", from: element),
                isEmoji: element.hasClass("emoji") || optionalAttribute("src", from: element)?.contains("/emoji/") == true
            )]
        default:
            if shouldSkipChrome(element) {
                return []
            }
            if isSpoiler(element) {
                return [.spoiler(try inlineChildren(from: element, path: path))]
            }
            return try inlineChildren(from: element, path: path)
        }
    }

    private mutating func inlineChildren(from element: Element, path: String) throws -> [LinuxDoInlineNode] {
        var nodes: [LinuxDoInlineNode] = []
        for (index, child) in element.getChildNodes().enumerated() {
            if let text = child as? TextNode {
                let value = Self.normalizedInlineText(text.getWholeText())
                if !value.isEmpty {
                    nodes.append(.text(value))
                }
            } else if let childElement = child as? Element {
                nodes.append(contentsOf: try inlineNodes(from: childElement, path: "\(path).i\(index)"))
            } else if let data = child as? DataNode {
                let value = Self.normalizedInlineText(data.getWholeData())
                if !value.isEmpty {
                    nodes.append(.text(value))
                }
            }
        }
        return nodes
    }

    private mutating func paragraphBlocks(from nodes: [LinuxDoInlineNode], path: String) -> [LinuxDoContentBlock] {
        var result: [LinuxDoContentBlock] = []
        var inlineBuffer: [LinuxDoInlineNode] = []

        func flushInlineBuffer() {
            let trimmed = Self.trimmed(inlineBuffer)
            if !Self.isEmpty(trimmed) {
                result.append(block(.paragraph(trimmed), path: "\(path).p\(result.count)"))
            }
            inlineBuffer.removeAll()
        }

        for (index, node) in nodes.enumerated() {
            if let image = promotedImage(from: node) {
                flushInlineBuffer()
                result.append(block(.image(
                    url: image.url,
                    alt: image.alt,
                    width: image.width,
                    height: image.height,
                    linkURL: image.linkURL
                ), path: "\(path).image\(index)"))
            } else {
                inlineBuffer.append(node)
            }
        }

        flushInlineBuffer()
        return result
    }

    private func promotedImage(from node: LinuxDoInlineNode) -> (url: URL, alt: String?, width: Int?, height: Int?, linkURL: URL?)? {
        switch node {
        case .image(let url, let alt, let width, let height, let isEmoji):
            guard !isEmoji else { return nil }
            return (url, alt, width, height, nil)
        case .link(let linkURL, let children):
            guard children.count == 1,
                  case .image(let url, let alt, let width, let height, let isEmoji) = children[0],
                  !isEmoji else {
                return nil
            }
            return (url, alt, width, height, linkURL)
        default:
            return nil
        }
    }

    private mutating func listItems(from element: Element, path: String) throws -> [LinuxDoListItem] {
        try element.children().array().enumerated().compactMap { index, child in
            guard child.tagNameNormal() == "li" else { return nil }
            let itemID = "\(path).li\(index)"
            let taskState = try taskState(from: child)
            let childBlocks = try blocks(from: child.getChildNodes(), path: "\(path).li\(index)")
            if childBlocks.isEmpty {
                let inline = try inlineNodes(from: child, path: "\(path).li\(index).inline")
                return Self.isEmpty(inline) ? nil : LinuxDoListItem(
                    id: itemID,
                    taskState: taskState,
                    blocks: [block(.paragraph(inline), path: "\(path).li\(index).p")]
                )
            }
            return LinuxDoListItem(id: itemID, taskState: taskState, blocks: childBlocks)
        }
    }

    private mutating func table(from element: Element, path: String) throws -> LinuxDoContentBlockKind {
        var headers: [LinuxDoTableCell] = []
        var rows: [LinuxDoTableRow] = []
        let tableRows = try element.select("tr").array()

        for (rowIndex, row) in tableRows.enumerated() {
            let headerCells = try row.select("th").array()
            if !headerCells.isEmpty {
                headers.append(contentsOf: try headerCells.enumerated().map { cellIndex, cell in
                    let cellBlocks = try blocks(from: cell.getChildNodes(), path: "\(path).h\(rowIndex).\(cellIndex)")
                    return LinuxDoTableCell(
                        id: "\(path).h\(rowIndex).\(cellIndex)",
                        blocks: cellBlocks.isEmpty ? [block(.paragraph([.text(try cell.text())]), path: "\(path).h\(rowIndex).\(cellIndex).p")] : cellBlocks
                    )
                })
                continue
            }

            let cells = try row.select("td").array()
            guard !cells.isEmpty else { continue }
            let rowCells = try cells.enumerated().map { cellIndex, cell in
                let cellBlocks = try blocks(from: cell.getChildNodes(), path: "\(path).r\(rowIndex).\(cellIndex)")
                return LinuxDoTableCell(
                    id: "\(path).r\(rowIndex).\(cellIndex)",
                    blocks: cellBlocks.isEmpty ? [block(.paragraph([.text(try cell.text())]), path: "\(path).r\(rowIndex).\(cellIndex).p")] : cellBlocks
                )
            }
            rows.append(LinuxDoTableRow(id: "\(path).r\(rowIndex)", cells: rowCells))
        }
        return .table(headers: headers, rows: rows)
    }

    private mutating func details(from element: Element, path: String) throws -> LinuxDoContentBlockKind {
        var summary: [LinuxDoInlineNode] = []
        var contentNodes: [Node] = []
        for child in element.getChildNodes() {
            if let childElement = child as? Element, childElement.tagNameNormal() == "summary" {
                summary = try inlineChildren(from: childElement, path: "\(path).summary")
            } else {
                contentNodes.append(child)
            }
        }
        return .details(summary: summary.isEmpty ? [.text("Details")] : summary, blocks: try blocks(from: contentNodes, path: "\(path).details"))
    }

    private func codeText(from element: Element) throws -> String {
        if let code = try element.select("code").first() {
            return code.wholeTextPreservingNewlines
        }
        return element.wholeTextPreservingNewlines
    }

    private func codeLanguage(from element: Element) throws -> String? {
        guard let code = try element.select("code").first() else { return nil }
        let classes = (try? code.className()) ?? ""
        return classes
            .split(separator: " ")
            .compactMap { item -> String? in
                if item.hasPrefix("language-") {
                    return String(item.dropFirst("language-".count))
                }
                if item.hasPrefix("lang-") {
                    return String(item.dropFirst("lang-".count))
                }
                return nil
            }
            .first
    }

    private mutating func imageBlock(from element: Element, path: String) throws -> LinuxDoContentBlock? {
        let tag = element.tagNameNormal()
        let image: Element?
        let linkURL: URL?
        if tag == "img" {
            image = element
            linkURL = nil
        } else if tag == "a", let img = try element.select("img").first() {
            image = img
            linkURL = resolvedURL(try? element.attr("href"))
        } else if element.hasClass("lightbox-wrapper") || element.hasClass("lightbox") {
            image = try element.select("img").first()
            linkURL = try element.select("a").first().flatMap { resolvedURL(try? $0.attr("href")) }
        } else {
            return nil
        }
        guard let image,
              !image.hasClass("avatar"),
              !image.hasClass("emoji"),
              let url = resolvedURL(try? image.attr("src")) else { return nil }
        return block(.image(
            url: url,
            alt: optionalAttribute("alt", from: image),
            width: integerAttribute("width", from: image),
            height: integerAttribute("height", from: image),
            linkURL: linkURL
        ), path: path)
    }

    private func onebox(from element: Element) throws -> LinuxDoOnebox? {
        guard element.hasClass("onebox") || element.hasClass("aside-onebox") || element.hasClass("onebox-result") else {
            return nil
        }
        let firstLink = try element.select("a[href]").first()
        let title = try element.select("header a, h3 a, h4 a, .onebox-title, a[href]").first()?.text()
        let description = try element.select(".onebox-body, article, p").first()?.text()
        let image = try element.select("img").first()
        let favicon = try element.select(".favicon, img[width=16], img[height=16]").first()
        return LinuxDoOnebox(
            url: firstLink.flatMap { resolvedURL(try? $0.attr("href")) },
            title: title?.nilIfBlank,
            description: description?.nilIfBlank,
            imageURL: image.flatMap { resolvedURL(try? $0.attr("src")) },
            faviconURL: favicon.flatMap { resolvedURL(try? $0.attr("src")) }
        )
    }

    private func quoteAttribution(from element: Element) throws -> LinuxDoQuoteAttribution? {
        let selectedTitle = try quoteTitleText(from: element.select(".title, cite, .quote-info").first())
        let username = optionalAttribute("data-username", from: element)
            ?? optionalAttribute("data-user-card", from: element)
            ?? selectedTitle
        let avatarURL = try element.select("img.avatar").first().flatMap { resolvedURL(try? $0.attr("src")) }
        let topicLink = try element.select("a[href]").first()
        let topicURL = topicLink.flatMap { resolvedURL(try? $0.attr("href")) }
        let topicTitle = try topicLink?.text().nilIfBlank
        if username == nil, avatarURL == nil, topicTitle == nil, topicURL == nil {
            return nil
        }
        return LinuxDoQuoteAttribution(
            username: username,
            displayName: selectedTitle,
            avatarURL: avatarURL,
            topicTitle: topicTitle,
            topicURL: topicURL,
            source: .blockquote
        )
    }

    private mutating func discourseQuoteBlocks(from element: Element, path: String) throws -> [LinuxDoContentBlock] {
        let attribution = try discourseQuoteAttribution(from: element)
        let bodyNodes = try discourseQuoteBodyNodes(from: element)
        let childBlocks = try blocks(from: bodyNodes, path: "\(path).quote")
        return childBlocks.isEmpty ? [] : [block(.quote(attribution: attribution, blocks: childBlocks), path: path)]
    }

    private func discourseQuoteAttribution(from element: Element) throws -> LinuxDoQuoteAttribution? {
        let titleElement = try element.select(".title, .quote-info, cite").first()
        let title = try quoteTitleText(from: titleElement)
        let username = optionalAttribute("data-username", from: element)
            ?? optionalAttribute("data-user-card", from: element)
            ?? title
        var avatarURL = try titleElement?.select("img.avatar").first().flatMap { resolvedURL(try? $0.attr("src")) }
        if avatarURL == nil {
            for child in element.children().array() where child.hasClass("title") {
                avatarURL = try child.select("img.avatar").first().flatMap { resolvedURL(try? $0.attr("src")) }
                if avatarURL != nil { break }
            }
        }
        let topicID = optionalAttribute("data-topic", from: element).flatMap(Int.init)
        let postNumber = optionalAttribute("data-post", from: element).flatMap(Int.init)
        let titleLinkURL = try titleElement?.select("a[href]").first().flatMap { resolvedURL(try? $0.attr("href")) }
        let topicURL = topicID.flatMap { resolvedURL("/t/topic/\($0)") } ?? titleLinkURL
        let postURL = topicID.flatMap { topicID in
            postNumber.flatMap { resolvedURL("/t/topic/\(topicID)/\($0)") }
        } ?? titleLinkURL
        if username == nil, title == nil, avatarURL == nil, topicURL == nil, postURL == nil {
            return nil
        }
        return LinuxDoQuoteAttribution(
            username: username,
            displayName: title,
            avatarURL: avatarURL,
            topicTitle: nil,
            topicURL: topicURL,
            postNumber: postNumber,
            postURL: postURL,
            source: .discourseAside
        )
    }

    private func quoteTitleText(from element: Element?) throws -> String? {
        guard let element else { return nil }
        return cleanedQuoteTitle(try quoteTitleText(from: element as Node))
    }

    private func quoteTitleText(from node: Node) throws -> String {
        if let text = node as? TextNode {
            return text.getWholeText()
        }
        if let data = node as? DataNode {
            return data.getWholeData()
        }
        guard let element = node as? Element else { return "" }
        if shouldSkipChrome(element) {
            return ""
        }
        if element.tagNameNormal() == "img", element.hasClass("avatar") {
            return ""
        }
        return try element.getChildNodes()
            .map { try quoteTitleText(from: $0) }
            .joined()
    }

    private func discourseQuoteBodyNodes(from element: Element) throws -> [Node] {
        if let blockquote = element.children().array().first(where: { $0.tagNameNormal() == "blockquote" }) {
            return blockquote.getChildNodes()
        }
        return element.getChildNodes().filter { node in
            guard let child = node as? Element else { return true }
            return !child.hasClass("title") && !shouldSkipChrome(child)
        }
    }

    private mutating func calloutBlock(from element: Element, path: String) throws -> LinuxDoContentBlock? {
        if element.tagNameNormal() == "blockquote",
           let callout = try markdownCallout(from: element, path: path) {
            return callout
        }
        guard let style = classCalloutStyle(from: element) else { return nil }
        var childBlocks = try blocks(from: element.getChildNodes(), path: "\(path).callout")
        let title = consumeLeadingCalloutTitle(from: &childBlocks, style: style)
        return block(.callout(LinuxDoCallout(
            style: style,
            title: title ?? defaultCalloutTitle(for: style),
            blocks: childBlocks
        )), path: path)
    }

    private mutating func markdownCallout(from element: Element, path: String) throws -> LinuxDoContentBlock? {
        var childBlocks = try blocks(from: element.getChildNodes(), path: "\(path).callout")
        guard let first = childBlocks.first,
              case .paragraph(let nodes) = first.kind,
              let style = markerCalloutStyle(from: nodes) else {
            return nil
        }
        childBlocks[0] = LinuxDoContentBlock(id: first.id, kind: .paragraph(nodesRemovingCalloutMarker(from: nodes)))
        childBlocks = childBlocks.filter { block in
            if case .paragraph(let nodes) = block.kind {
                return !Self.isEmpty(nodes)
            }
            return true
        }
        return block(.callout(LinuxDoCallout(
            style: style,
            title: defaultCalloutTitle(for: style),
            blocks: childBlocks
        )), path: path)
    }

    private func postEvent(from element: Element) -> LinuxDoPostEvent? {
        guard element.hasClass("discourse-post-event") else { return nil }
        return LinuxDoPostEvent(
            name: optionalAttribute("data-name", from: element),
            startsAt: optionalAttribute("data-start", from: element),
            endsAt: optionalAttribute("data-end", from: element),
            timezone: optionalAttribute("data-timezone", from: element),
            status: optionalAttribute("data-status", from: element)
        )
    }

    private func isBlockElement(_ element: Element) -> Bool {
        let tag = element.tagNameNormal()
        if ["p", "div", "section", "article", "aside", "blockquote", "pre", "ul", "ol", "li", "table", "thead", "tbody", "tr", "td", "th", "details", "summary", "hr", "figure"].contains(tag) {
            return true
        }
        if tag.count == 2, tag.first == "h", Int(String(tag.dropFirst())) != nil {
            return true
        }
        return tag == "img" || element.hasClass("onebox") || element.hasClass("lightbox-wrapper")
    }

    private func isSpoiler(_ element: Element) -> Bool {
        element.hasClass("spoiler")
            || element.hasClass("spoiler-alert")
            || element.hasClass("blurred")
            || element.hasClass("inline-spoiler")
    }

    private func isEmptyAnchor(_ element: Element) -> Bool {
        guard element.tagNameNormal() == "a" else { return false }
        let href = optionalAttribute("href", from: element) ?? ""
        let name = optionalAttribute("name", from: element)
        return element.hasClass("anchor")
            || (href.hasPrefix("#") && ((try? element.text().nilIfBlank) == nil))
            || (name != nil && ((try? element.text().nilIfBlank) == nil))
    }

    private func shouldSkipChrome(_ element: Element) -> Bool {
        element.hasClass("quote-controls")
            || element.hasClass("quote-button")
            || element.hasClass("quote-toggle")
            || element.hasClass("expand-quote")
    }

    private func taskState(from element: Element) throws -> LinuxDoTaskState? {
        guard let input = try element.select("input[type=checkbox]").first() else { return nil }
        return input.hasAttr("checked") ? .checked : .unchecked
    }

    private func classCalloutStyle(from element: Element) -> LinuxDoCalloutStyle? {
        let classes = classTokens(from: element)
        guard classes.contains("alert")
            || classes.contains("markdown-alert")
            || classes.contains("md-alert")
            || classes.contains(where: { $0.hasPrefix("alert-") || $0.hasPrefix("markdown-alert-") || $0.hasPrefix("md-alert-") })
        else {
            return nil
        }
        return calloutStyle(from: classes) ?? .generic
    }

    private func calloutStyle(from classes: [String]) -> LinuxDoCalloutStyle? {
        if classes.contains(where: { $0.contains("danger") || $0.contains("error") }) { return .danger }
        if classes.contains(where: { $0.contains("warning") || $0.contains("caution") }) { return .warning }
        if classes.contains(where: { $0.contains("important") }) { return .important }
        if classes.contains(where: { $0.contains("tip") || $0.contains("success") }) { return .tip }
        if classes.contains(where: { $0.contains("note") || $0.contains("info") }) { return .note }
        return nil
    }

    private func classTokens(from element: Element) -> [String] {
        ((try? element.className()) ?? "")
            .split(separator: " ")
            .map { $0.lowercased() }
    }

    private func markerCalloutStyle(from nodes: [LinuxDoInlineNode]) -> LinuxDoCalloutStyle? {
        guard let marker = calloutMarker(from: nodes) else { return nil }
        switch marker {
        case "note": return .note
        case "tip": return .tip
        case "important": return .important
        case "warning", "caution": return .warning
        case "danger", "error": return .danger
        default: return .generic
        }
    }

    private func calloutMarker(from nodes: [LinuxDoInlineNode]) -> String? {
        let text = nodes.map(\.plainHTMLText).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("[!"), let end = text.firstIndex(of: "]") else { return nil }
        return String(text[text.index(text.startIndex, offsetBy: 2)..<end]).lowercased()
    }

    private func nodesRemovingCalloutMarker(from nodes: [LinuxDoInlineNode]) -> [LinuxDoInlineNode] {
        var mutable = nodes
        for index in mutable.indices {
            guard case .text(let text) = mutable[index],
                  let markerStart = text.range(of: "[!"),
                  markerStart.lowerBound == text.startIndex,
                  let markerEnd = text[markerStart.upperBound...].firstIndex(of: "]") else {
                continue
            }
            let remainderStart = text.index(after: markerEnd)
            let remainder = String(text[remainderStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            mutable[index] = .text(remainder)
            return Self.trimmed(mutable)
        }
        return nodes
    }

    private func consumeLeadingCalloutTitle(from blocks: inout [LinuxDoContentBlock], style: LinuxDoCalloutStyle) -> String? {
        guard let first = blocks.first, case .paragraph(let nodes) = first.kind else { return nil }
        let text = nodes.map(\.plainHTMLText).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultTitle = defaultCalloutTitle(for: style)
        guard text.caseInsensitiveCompare(defaultTitle) == .orderedSame else { return nil }
        blocks.removeFirst()
        return text
    }

    private func defaultCalloutTitle(for style: LinuxDoCalloutStyle) -> String {
        switch style {
        case .note: return "Note"
        case .tip: return "Tip"
        case .important: return "Important"
        case .warning: return "Warning"
        case .danger: return "Danger"
        case .generic: return "Notice"
        }
    }

    private func cleanedQuoteTitle(_ title: String?) -> String? {
        guard var title = title?.nilIfBlank else { return nil }
        title = title
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while title.last == ":" || title.last == "：" {
            title.removeLast()
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return title.nilIfBlank
    }

    private mutating func block(_ kind: LinuxDoContentBlockKind, path: String) -> LinuxDoContentBlock {
        blockCounter += 1
        return LinuxDoContentBlock(id: "\(path).\(blockCounter)", kind: kind)
    }

    private func resolvedURL(_ raw: String?) -> URL? {
        LinuxDoURLResolver.url(from: raw)
    }

    private func optionalAttribute(_ name: String, from element: Element) -> String? {
        (try? element.attr(name))?.nilIfBlank
    }

    private func integerAttribute(_ name: String, from element: Element) -> Int? {
        optionalAttribute(name, from: element).flatMap(Int.init)
    }

    private static func normalizedInlineText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\u{00a0}", with: " ")
    }

    private static func trimmed(_ nodes: [LinuxDoInlineNode]) -> [LinuxDoInlineNode] {
        var copy = nodes
        while let first = copy.first, first.isWhitespaceOnly {
            copy.removeFirst()
        }
        while let last = copy.last, last.isWhitespaceOnly {
            copy.removeLast()
        }
        if let first = copy.first, case .text(let text) = first {
            copy[0] = .text(text.trimmingLeadingWhitespace)
        }
        if let last = copy.last, case .text(let text) = last {
            copy[copy.count - 1] = .text(text.trimmingTrailingWhitespace)
        }
        return copy
    }

    private static func isEmpty(_ nodes: [LinuxDoInlineNode]) -> Bool {
        nodes.allSatisfy(\.isWhitespaceOnly)
    }
}

private extension Element {
    var wholeTextPreservingNewlines: String {
        getChildNodes()
            .map { node -> String in
                if let text = node as? TextNode { return text.getWholeText() }
                if let data = node as? DataNode { return data.getWholeData() }
                if let element = node as? Element { return element.wholeTextPreservingNewlines }
                return ""
            }
            .joined()
    }
}

private extension LinuxDoInlineNode {
    var plainHTMLText: String {
        switch self {
        case .text(let text), .code(let text):
            return text
        case .strong(let children),
             .emphasis(let children),
             .strikethrough(let children),
             .highlight(let children),
             .keyboard(let children),
             .subscript(let children),
             .superscript(let children),
             .spoiler(let children):
            return children.map(\.plainHTMLText).joined()
        case .link(_, let children):
            return children.map(\.plainHTMLText).joined()
        case .image(_, let alt, _, _, _):
            return alt ?? ""
        case .mention(let username, _):
            return "@\(username)"
        case .hashtag(let text, _):
            return text
        case .lineBreak:
            return "\n"
        }
    }
}

private extension Elements {
    func array() -> [Element] {
        (0..<size()).map { get($0) }
    }
}

private extension LinuxDoInlineNode {
    var isWhitespaceOnly: Bool {
        switch self {
        case .text(let text), .code(let text):
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .strong(let children),
             .emphasis(let children),
             .strikethrough(let children),
             .highlight(let children),
             .keyboard(let children),
             .subscript(let children),
             .superscript(let children),
             .spoiler(let children):
            children.allSatisfy(\.isWhitespaceOnly)
        case .lineBreak:
            true
        case .link, .image, .mention, .hashtag:
            false
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmingLeadingWhitespace: String {
        String(drop(while: { $0.isWhitespace }))
    }

    var trimmingTrailingWhitespace: String {
        var copy = self
        while copy.last?.isWhitespace == true {
            copy.removeLast()
        }
        return copy
    }
}
