import Foundation

struct CppJiebaResourceLocator: Sendable {
    static func dictionaryDirectoryURL(bundle: Bundle = .main) -> URL? {
        guard let resourceURL = bundle.resourceURL else { return nil }
        let url = resourceURL.appendingPathComponent("CppJieba", isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("jieba.dict.utf8").path) else {
            return nil
        }
        return url
    }
}

actor JiebaTokenizer {
    private let bridge: CppJiebaTokenizerBridge?
    private var insertedWords: Set<String> = []

    init(dictionaryDirectoryURL: URL? = CppJiebaResourceLocator.dictionaryDirectoryURL()) {
        if let dictionaryDirectoryURL {
            bridge = CppJiebaTokenizerBridge(
                dictionaryDirectory: dictionaryDirectoryURL.path,
                userDictionaryPath: nil
            )
        } else {
            bridge = nil
        }
    }

    var isAvailable: Bool { bridge != nil }

    func insertUserWords(_ words: [String]) {
        let fresh = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !insertedWords.contains($0) }
        guard !fresh.isEmpty else { return }
        insertedWords.formUnion(fresh)
        bridge?.insertUserWords(fresh)
    }

    func cut(_ text: String, forSearch: Bool = false) -> [String] {
        if let bridge {
            return bridge.cut(text, hmm: true, forSearch: forSearch)
        }
        return Self.fallbackTokens(text)
    }

    private static func fallbackTokens(_ text: String) -> [String] {
        let runs = text.unicodeScalars.split { scalar in
            !isCJK(scalar)
        }
        var out: [String] = []
        for run in runs {
            let chars = run.map(String.init)
            if chars.count <= 1 {
                out += chars
                continue
            }
            out.append(chars.joined())
            if chars.count >= 2 {
                for i in 0..<(chars.count - 1) {
                    out.append(chars[i] + chars[i + 1])
                }
            }
            if chars.count >= 3 {
                for i in 0..<(chars.count - 2) {
                    out.append(chars[i] + chars[i + 1] + chars[i + 2])
                }
            }
        }
        return out
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(Int(scalar.value))
            || (0x3400...0x4DBF).contains(Int(scalar.value))
            || (0xF900...0xFAFF).contains(Int(scalar.value))
    }
}
