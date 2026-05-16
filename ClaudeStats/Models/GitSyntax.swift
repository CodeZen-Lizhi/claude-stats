import Foundation

enum GitSyntaxKind: String, Codable, Sendable {
    case general
    case code
}

struct GitSyntaxDefinition: Codable, Sendable {
    let kind: GitSyntaxKind
    let fileMap: GitSyntaxFileMap
    let comment: GitSyntaxComment?
    let stringDelimiters: [GitSyntaxStringDelimiter]
}

struct GitSyntaxFileMap: Codable, Sendable {
    let extensions: [String]
    let filenames: [String]
    let interpreters: [String]
}

struct GitSyntaxComment: Codable, Sendable {
    struct Inline: Codable, Sendable {
        let begin: String
        let leadingOnly: Bool
    }

    struct Block: Codable, Sendable, Hashable {
        let begin: String
        let end: String
        let isNestable: Bool
    }

    let inlines: [Inline]
    let blocks: [Block]
}

struct GitSyntaxStringDelimiter: Codable, Sendable, Hashable {
    let begin: String
    let end: String
    let isMultiline: Bool
    let escapeCharacter: String?
}

struct GitSyntaxCatalog: Sendable {
    let definitions: [String: GitSyntaxDefinition]
    private let mappingTable: GitSyntaxMappingTable

    init(definitions: [String: GitSyntaxDefinition]) {
        self.definitions = definitions
        self.mappingTable = GitSyntaxMappingTable(definitions: definitions)
    }

    static func bundled(bundle: Bundle = .main) -> GitSyntaxCatalog {
        guard let url = bundle.url(forResource: "GitSyntaxMap", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let definitions = try? JSONDecoder().decode([String: GitSyntaxDefinition].self, from: data) else {
            Log.git.error("GitSyntaxMap.json could not be loaded; git code statistics will be empty")
            return GitSyntaxCatalog(definitions: [:])
        }
        return GitSyntaxCatalog(definitions: definitions)
    }

    func definition(forPath path: String, contentPrefix: String) -> (name: String, definition: GitSyntaxDefinition)? {
        guard let name = mappingTable.syntaxName(forPath: path, content: contentPrefix),
              let definition = definitions[name] else {
            return nil
        }
        return (name, definition)
    }
}

struct GitSyntaxMappingTable: Sendable, Equatable {
    private let extensions: [String: [String]]
    private let filenames: [String: [String]]
    private let interpreters: [String: [String]]

    init(definitions: [String: GitSyntaxDefinition]) {
        let names = definitions.keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        var extensions: [String: [String]] = [:]
        var filenames: [String: [String]] = [:]
        var interpreters: [String: [String]] = [:]

        for name in names {
            guard let map = definitions[name]?.fileMap else { continue }
            for item in map.extensions {
                extensions[item.lowercased(), default: []].append(name)
            }
            for item in map.filenames {
                filenames[item, default: []].append(name)
            }
            for item in map.interpreters {
                interpreters[item, default: []].append(name)
            }
        }

        self.extensions = extensions
        self.filenames = filenames
        self.interpreters = interpreters
    }

    func syntaxName(forPath path: String, content: String) -> String? {
        syntaxName(forFilename: (path as NSString).lastPathComponent)
            ?? syntaxName(forContent: content)
    }

    func syntaxName(forFilename filename: String) -> String? {
        if let name = filenames[filename]?.first {
            return name
        }

        let pathExtension = (filename as NSString).pathExtension
        guard !pathExtension.isEmpty else { return nil }
        return extensions[pathExtension.lowercased()]?.first
    }

    func syntaxName(forContent content: String) -> String? {
        if let interpreter = Self.scanInterpreterInShebang(content),
           let name = interpreters[interpreter]?.first ?? interpreters[interpreter.lowercased()]?.first {
            return name
        }

        if content.hasPrefix("<?xml ") {
            return "XML"
        }

        return nil
    }

    static func scanInterpreterInShebang(_ source: String) -> String? {
        guard source.hasPrefix("#!") else { return nil }
        let line = source.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let body = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }

        var pieces = body.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let executable = pieces.first else { return nil }
        let interpreter = (executable as NSString).lastPathComponent
        if interpreter != "env" {
            return interpreter
        }

        pieces.removeFirst()
        while let first = pieces.first, first.hasPrefix("-") {
            pieces.removeFirst()
            if first == "-S" { break }
        }
        return pieces.first
    }
}

