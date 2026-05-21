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
        case "blockquote", "aside":
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
        case "code":
            return [.code(try element.text(trimAndNormaliseWhitespace: false))]
        case "strong", "b":
            return [.strong(try inlineChildren(from: element, path: path))]
        case "em", "i":
            return [.emphasis(try inlineChildren(from: element, path: path))]
        case "s", "strike", "del":
            return [.strikethrough(try inlineChildren(from: element, path: path))]
        case "a":
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
            guard let url = resolvedURL(try? element.attr("src")) else { return [] }
            return [.image(
                url: url,
                alt: optionalAttribute("alt", from: element),
                width: integerAttribute("width", from: element),
                height: integerAttribute("height", from: element),
                isEmoji: element.hasClass("emoji") || optionalAttribute("src", from: element)?.contains("/emoji/") == true
            )]
        default:
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
            let childBlocks = try blocks(from: child.getChildNodes(), path: "\(path).li\(index)")
            if childBlocks.isEmpty {
                let inline = try inlineNodes(from: child, path: "\(path).li\(index).inline")
                return Self.isEmpty(inline) ? nil : LinuxDoListItem(blocks: [block(.paragraph(inline), path: "\(path).li\(index).p")])
            }
            return LinuxDoListItem(blocks: childBlocks)
        }
    }

    private mutating func table(from element: Element, path: String) throws -> LinuxDoContentBlockKind {
        var headers: [[LinuxDoContentBlock]] = []
        var rows: [[[LinuxDoContentBlock]]] = []
        let tableRows = try element.select("tr").array()

        for (rowIndex, row) in tableRows.enumerated() {
            let headerCells = try row.select("th").array()
            if !headerCells.isEmpty {
                headers.append(contentsOf: try headerCells.enumerated().map { cellIndex, cell in
                    let cellBlocks = try blocks(from: cell.getChildNodes(), path: "\(path).h\(rowIndex).\(cellIndex)")
                    return cellBlocks.isEmpty ? [block(.paragraph([.text(try cell.text())]), path: "\(path).h\(rowIndex).\(cellIndex).p")] : cellBlocks
                })
                continue
            }

            let cells = try row.select("td").array()
            guard !cells.isEmpty else { continue }
            rows.append(try cells.enumerated().map { cellIndex, cell in
                let cellBlocks = try blocks(from: cell.getChildNodes(), path: "\(path).r\(rowIndex).\(cellIndex)")
                return cellBlocks.isEmpty ? [block(.paragraph([.text(try cell.text())]), path: "\(path).r\(rowIndex).\(cellIndex).p")] : cellBlocks
            })
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
        guard let image, let url = resolvedURL(try? image.attr("src")) else { return nil }
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
        let selectedTitle = try element.select(".title, cite, .quote-info").first()?.text().nilIfBlank
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
        return LinuxDoQuoteAttribution(username: username, avatarURL: avatarURL, topicTitle: topicTitle, topicURL: topicURL)
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
        return copy.filter { !$0.isWhitespaceOnly }
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
        case .strong(let children), .emphasis(let children), .strikethrough(let children), .spoiler(let children):
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
