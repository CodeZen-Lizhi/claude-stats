import AppKit
import SwiftUI

struct ConfigurationTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fileKind: ProviderConfigFileKind
    var isEditable: Bool
    var onCursorChange: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.font = Self.editorFont
        textView.typingAttributes = context.coordinator.baseAttributes
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        context.coordinator.replaceText(in: textView, with: text, kind: fileKind)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        if textView.string != text {
            context.coordinator.replaceText(in: textView, with: text, kind: fileKind)
        } else {
            context.coordinator.applyHighlighting(to: textView, kind: fileKind)
        }
    }

    private static var editorFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ConfigurationTextEditor
        private var isProgrammaticChange = false
        private var lastHighlightedText = ""
        private var lastHighlightedKind: ProviderConfigFileKind?

        init(parent: ConfigurationTextEditor) {
            self.parent = parent
        }

        var baseAttributes: [NSAttributedString.Key: Any] {
            [
                .font: ConfigurationTextEditor.editorFont,
                .foregroundColor: NSColor.labelColor,
            ]
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticChange,
                  let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyHighlighting(to: textView, kind: parent.fileKind)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let cursor = cursorPosition(in: textView)
            parent.onCursorChange(cursor.line, cursor.column)
        }

        func replaceText(in textView: NSTextView, with text: String, kind: ProviderConfigFileKind) {
            let selectedRanges = textView.selectedRanges
            isProgrammaticChange = true
            textView.string = text
            isProgrammaticChange = false
            applyHighlighting(to: textView, kind: kind, force: true)
            textView.selectedRanges = clampedRanges(selectedRanges, textLength: (text as NSString).length)
        }

        func applyHighlighting(to textView: NSTextView, kind: ProviderConfigFileKind, force: Bool = false) {
            let string = textView.string
            guard force || string != lastHighlightedText || kind != lastHighlightedKind else { return }
            guard let storage = textView.textStorage else { return }

            let selectedRanges = textView.selectedRanges
            let fullRange = NSRange(location: 0, length: (string as NSString).length)

            storage.beginEditing()
            storage.setAttributes(baseAttributes, range: fullRange)
            switch kind {
            case .json:
                highlightJSON(in: storage, source: string)
            case .markdown:
                highlightMarkdown(in: storage, source: string)
            case .toml:
                highlightTOML(in: storage, source: string)
            case .text:
                break
            }
            storage.endEditing()

            textView.typingAttributes = baseAttributes
            textView.selectedRanges = clampedRanges(selectedRanges, textLength: fullRange.length)
            lastHighlightedText = string
            lastHighlightedKind = kind
        }

        private func highlightJSON(in storage: NSTextStorage, source: String) {
            addMatches(pattern: #""([^"\\]|\\.)*""#, color: .systemGreen, storage: storage, source: source)
            addMatches(pattern: #""([^"\\]|\\.)*"\s*:"#, color: .systemOrange, storage: storage, source: source)
            addMatches(pattern: #"\b(true|false|null)\b"#, color: .systemPurple, storage: storage, source: source)
            addMatches(pattern: #"(?<![A-Za-z0-9_])-?\b\d+(\.\d+)?([eE][+-]?\d+)?\b"#, color: .systemBlue, storage: storage, source: source)
        }

        private func highlightMarkdown(in storage: NSTextStorage, source: String) {
            addMatches(pattern: #"^#{1,6}\s.+$"#, color: .systemOrange, storage: storage, source: source, options: [.anchorsMatchLines])
            addMatches(pattern: #"^>\s?.+$"#, color: .systemGreen, storage: storage, source: source, options: [.anchorsMatchLines])
            addMatches(pattern: #"`[^`\n]+`"#, color: .systemPurple, storage: storage, source: source)
            addMatches(pattern: #"^```.*$"#, color: .systemPurple, storage: storage, source: source, options: [.anchorsMatchLines])
        }

        private func highlightTOML(in storage: NSTextStorage, source: String) {
            addMatches(pattern: #"^\s*\[[^\]]+\]"#, color: .systemOrange, storage: storage, source: source, options: [.anchorsMatchLines])
            addMatches(pattern: #"^[A-Za-z0-9_.-]+(?=\s*=)"#, color: .systemBlue, storage: storage, source: source, options: [.anchorsMatchLines])
            addMatches(pattern: #""([^"\\]|\\.)*""#, color: .systemGreen, storage: storage, source: source)
            addMatches(pattern: #"\b(true|false)\b"#, color: .systemPurple, storage: storage, source: source)
        }

        private func addMatches(
            pattern: String,
            color: NSColor,
            storage: NSTextStorage,
            source: String,
            options: NSRegularExpression.Options = []
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            let nsSource = source as NSString
            let range = NSRange(location: 0, length: nsSource.length)
            regex.enumerateMatches(in: source, range: range) { match, _, _ in
                guard let match else { return }
                storage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }

        private func clampedRanges(_ ranges: [NSValue], textLength: Int) -> [NSValue] {
            ranges.map { value in
                let range = value.rangeValue
                let location = min(range.location, textLength)
                let length = min(range.length, max(0, textLength - location))
                return NSValue(range: NSRange(location: location, length: length))
            }
        }

        private func cursorPosition(in textView: NSTextView) -> (line: Int, column: Int) {
            let source = textView.string as NSString
            let location = min(textView.selectedRange().location, source.length)
            let prefix = source.substring(to: location)
            let lines = prefix.components(separatedBy: .newlines)
            return (max(1, lines.count), (lines.last?.count ?? 0) + 1)
        }
    }
}
