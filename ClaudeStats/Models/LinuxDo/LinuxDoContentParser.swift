import Foundation

enum LinuxDoContentParser {
    static func blocks(from cookedHTML: String) -> [LinuxDoContentBlock] {
        var html = cookedHTML
        let codeBlocks = extract(pattern: #"<pre><code[^>]*>(.*?)</code></pre>"#, from: html)
        html = remove(pattern: #"<pre><code[^>]*>.*?</code></pre>"#, from: html)

        let quotes = extract(pattern: #"<blockquote[^>]*>(.*?)</blockquote>"#, from: html)
        html = remove(pattern: #"<blockquote[^>]*>.*?</blockquote>"#, from: html)

        let images = imageURLs(from: html)
        html = remove(pattern: #"<img[^>]+>"#, from: html)

        var blocks: [LinuxDoContentBlock] = []
        for quote in quotes where !quote.htmlStrippedAndDecoded.isEmpty {
            blocks.append(.quote(quote.htmlStrippedAndDecoded))
        }
        for code in codeBlocks where !code.htmlStrippedAndDecoded.isEmpty {
            blocks.append(.code(code.htmlStrippedAndDecoded))
        }
        for list in lists(from: html) where !list.isEmpty {
            blocks.append(.list(list))
        }
        for image in images {
            blocks.append(.image(image))
        }

        let paragraphs = html
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
            .components(separatedBy: .newlines)
            .map(\.htmlStrippedAndDecoded)
            .filter { !$0.isEmpty }

        blocks.append(contentsOf: paragraphs.map { .paragraph($0) })
        return blocks.isEmpty ? [.paragraph(cookedHTML.htmlStrippedAndDecoded)] : blocks
    }

    private static func extract(pattern: String, from html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
        }
    }

    private static func remove(pattern: String, from html: String) -> String {
        html.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
    }

    private static func imageURLs(from html: String) -> [URL] {
        guard let regex = try? NSRegularExpression(pattern: #"<img[^>]+src=["']([^"']+)["'][^>]*>"#, options: [.caseInsensitive]) else {
            return []
        }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: html) else { return nil }
            return LinuxDoURLResolver.url(from: String(html[range]))
        }
    }

    private static func lists(from html: String) -> [[String]] {
        extract(pattern: #"<(?:ul|ol)[^>]*>(.*?)</(?:ul|ol)>"#, from: html)
            .map { listHTML in
                extract(pattern: #"<li[^>]*>(.*?)</li>"#, from: listHTML)
                    .map(\.htmlStrippedAndDecoded)
                    .filter { !$0.isEmpty }
            }
            .filter { !$0.isEmpty }
    }
}

