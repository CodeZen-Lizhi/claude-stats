import Foundation

enum SemanticTimelineGranularity: String, Codable, Hashable, Sendable {
    case day
    case week
    case month

    var displayName: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }

    func bucketStart(for date: Date, calendar: Calendar) -> Date {
        switch self {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .month:
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components) ?? calendar.startOfDay(for: date)
        }
    }
}

struct SemanticVisualizationSnapshot: Hashable, Sendable {
    static let atlasTermLimit = 80
    static let atlasEdgeLimit = 120
    static let bubbleTermLimit = 64
    static let wordCloudTermLimit = 80
    static let termsPerSessionForCooccurrence = 12

    let provider: ProviderKind
    let generatedAt: Date
    let nodes: [SemanticTermNode]
    let nodesByID: [String: SemanticTermNode]
    let kindSummaries: [SemanticKindSummary]
    let edges: [SemanticCooccurrenceEdge]
    let atlasNodes: [SemanticPositionedNode]
    let bubbleNodes: [SemanticPositionedNode]
    let wordCloudItems: [SemanticWordCloudItem]
    let timelineGranularity: SemanticTimelineGranularity
    let timelineKinds: [TranscriptTermKind]
    let timelinePoints: [SemanticTimelinePoint]

    var isEmpty: Bool { nodes.isEmpty }

    init(
        analysis: TranscriptAnalysisSnapshot,
        sessions: [Session],
        calendar: Calendar = .current
    ) {
        provider = analysis.provider
        generatedAt = analysis.generatedAt

        let sortedTerms = analysis.terms.sorted(by: Self.termSort)
        let nodes = Self.makeNodes(from: Array(sortedTerms.prefix(Self.atlasTermLimit)))
        self.nodes = nodes
        nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

        kindSummaries = Self.makeKindSummaries(from: sortedTerms, nodesByID: nodesByID)

        let pairCounts = Self.makePairCounts(
            from: analysis.sessionAnalyses,
            allowedNodeIDs: Set(nodes.map(\.id))
        )
        edges = Self.makeEdges(from: pairCounts)

        atlasNodes = Self.makeAtlasNodes(nodes: nodes, edges: edges)
        bubbleNodes = Self.makeBubbleNodes(nodes: Array(nodes.prefix(Self.bubbleTermLimit)))
        wordCloudItems = Self.makeWordCloudItems(nodes: Array(nodes.prefix(Self.wordCloudTermLimit)))

        let timeline = Self.makeTimeline(
            analysis: analysis,
            sessions: sessions,
            calendar: calendar
        )
        timelineGranularity = timeline.granularity
        timelineKinds = timeline.kinds
        timelinePoints = timeline.points
    }

    func node(for id: String?) -> SemanticTermNode? {
        guard let id else { return nil }
        return nodesByID[id]
    }

    func edgeCount(between firstID: String, and secondID: String) -> Int {
        let pair = Self.pairKey(firstID, secondID)
        return edges.first { Self.pairKey($0.sourceID, $0.targetID) == pair }?.count ?? 0
    }

    private static func makeNodes(from terms: [TranscriptTermStats]) -> [SemanticTermNode] {
        let scores = terms.map { log1p(max($0.tfidf, 0)) }
        let minScore = scores.min() ?? 0
        let maxScore = scores.max() ?? 0
        return terms.map { term in
            let raw = log1p(max(term.tfidf, 0))
            return SemanticTermNode(
                id: termID(canonical: term.canonical, kind: term.kind),
                canonical: term.canonical,
                displayName: term.displayName,
                kind: term.kind,
                frequency: term.frequency,
                documentFrequency: term.documentFrequency,
                tfidf: term.tfidf,
                score: normalized(raw, min: minScore, max: maxScore),
                examples: term.examples
            )
        }
    }

    private static func makeKindSummaries(
        from terms: [TranscriptTermStats],
        nodesByID: [String: SemanticTermNode]
    ) -> [SemanticKindSummary] {
        var buckets: [TranscriptTermKind: MutableKindSummary] = [:]
        for term in terms {
            let id = termID(canonical: term.canonical, kind: term.kind)
            var bucket = buckets[term.kind] ?? MutableKindSummary(kind: term.kind)
            bucket.termCount += 1
            bucket.frequency += term.frequency
            bucket.documentFrequency += term.documentFrequency
            bucket.tfidf += term.tfidf
            if bucket.topTermID == nil || term.tfidf > bucket.topScore {
                bucket.topTermID = nodesByID[id] == nil ? nil : id
                bucket.topScore = term.tfidf
            }
            buckets[term.kind] = bucket
        }

        return TranscriptTermKind.allCases.compactMap { kind in
            guard let bucket = buckets[kind] else { return nil }
            return SemanticKindSummary(
                kind: kind,
                termCount: bucket.termCount,
                frequency: bucket.frequency,
                documentFrequency: bucket.documentFrequency,
                tfidf: bucket.tfidf,
                topTermID: bucket.topTermID
            )
        }
    }

    private static func makePairCounts(
        from analyses: [TranscriptSessionAnalysis],
        allowedNodeIDs: Set<String>
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        for analysis in analyses {
            let ids = analysis.terms
                .sorted { lhs, rhs in
                    if lhs.weightedFrequency != rhs.weightedFrequency {
                        return lhs.weightedFrequency > rhs.weightedFrequency
                    }
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                .prefix(Self.termsPerSessionForCooccurrence)
                .map { termID(canonical: $0.canonical, kind: $0.kind) }
                .filter { allowedNodeIDs.contains($0) }
            let uniqueIDs = Array(Set(ids)).sorted()
            guard uniqueIDs.count >= 2 else { continue }
            for leftIndex in 0..<(uniqueIDs.count - 1) {
                for rightIndex in (leftIndex + 1)..<uniqueIDs.count {
                    counts[pairKey(uniqueIDs[leftIndex], uniqueIDs[rightIndex]), default: 0] += 1
                }
            }
        }
        return counts
    }

    private static func makeEdges(from pairCounts: [String: Int]) -> [SemanticCooccurrenceEdge] {
        let maxCount = max(pairCounts.values.max() ?? 1, 1)
        return pairCounts
            .compactMap { key, count -> SemanticCooccurrenceEdge? in
                let parts = key.components(separatedBy: "\u{1F}")
                guard parts.count == 2 else { return nil }
                return SemanticCooccurrenceEdge(
                    sourceID: parts[0],
                    targetID: parts[1],
                    count: count,
                    strength: Double(count) / Double(maxCount)
                )
            }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.id < $1.id
            }
            .prefix(Self.atlasEdgeLimit)
            .map { $0 }
    }

    private static func makeAtlasNodes(
        nodes: [SemanticTermNode],
        edges: [SemanticCooccurrenceEdge]
    ) -> [SemanticPositionedNode] {
        guard !nodes.isEmpty else { return [] }
        guard nodes.count > 1 else {
            return [SemanticPositionedNode(nodeID: nodes[0].id, x: 0.5, y: 0.5, radius: radius(for: nodes[0]))]
        }

        var positions = nodes.map { initialPosition(for: $0) }
        let indexByID = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.id, $0.offset) })

        for _ in 0..<180 {
            var deltas = Array(repeating: SemanticPoint.zero, count: positions.count)

            for left in 0..<(positions.count - 1) {
                for right in (left + 1)..<positions.count {
                    let dx = positions[left].x - positions[right].x
                    let dy = positions[left].y - positions[right].y
                    let distanceSquared = max(dx * dx + dy * dy, 0.0008)
                    let distance = sqrt(distanceSquared)
                    let force = 0.0009 / distanceSquared
                    let ux = dx / distance
                    let uy = dy / distance
                    deltas[left].x += ux * force
                    deltas[left].y += uy * force
                    deltas[right].x -= ux * force
                    deltas[right].y -= uy * force
                }
            }

            for edge in edges {
                guard let left = indexByID[edge.sourceID], let right = indexByID[edge.targetID] else { continue }
                let dx = positions[right].x - positions[left].x
                let dy = positions[right].y - positions[left].y
                let distance = max(sqrt(dx * dx + dy * dy), 0.001)
                let desired = 0.14 + (1.0 - edge.strength) * 0.08
                let force = (distance - desired) * 0.012 * max(edge.strength, 0.2)
                let ux = dx / distance
                let uy = dy / distance
                deltas[left].x += ux * force
                deltas[left].y += uy * force
                deltas[right].x -= ux * force
                deltas[right].y -= uy * force
            }

            for index in positions.indices {
                deltas[index].x += (0.5 - positions[index].x) * 0.006
                deltas[index].y += (0.5 - positions[index].y) * 0.006
                positions[index].x = (positions[index].x + deltas[index].x).clamped(to: -0.8...1.8)
                positions[index].y = (positions[index].y + deltas[index].y).clamped(to: -0.8...1.8)
            }
        }

        let normalized = normalize(points: positions, padding: 0.08)
        return zip(nodes, normalized).map { node, point in
            SemanticPositionedNode(nodeID: node.id, x: point.x, y: point.y, radius: radius(for: node))
        }
    }

    private static func makeBubbleNodes(nodes: [SemanticTermNode]) -> [SemanticPositionedNode] {
        guard !nodes.isEmpty else { return [] }
        let grouped = Dictionary(grouping: nodes, by: \.kind)
        let kinds = TranscriptTermKind.allCases.filter { grouped[$0]?.isEmpty == false }
        let columns = max(1, Int(ceil(sqrt(Double(kinds.count)))))
        let rows = max(1, Int(ceil(Double(kinds.count) / Double(columns))))
        var placed: [SemanticPositionedNode] = []

        for (kindIndex, kind) in kinds.enumerated() {
            let column = kindIndex % columns
            let row = kindIndex / columns
            let minX = Double(column) / Double(columns)
            let maxX = Double(column + 1) / Double(columns)
            let minY = Double(row) / Double(rows)
            let maxY = Double(row + 1) / Double(rows)
            let center = SemanticPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
            let width = maxX - minX
            let height = maxY - minY
            var groupPlaced: [SemanticPositionedNode] = []
            let sorted = (grouped[kind] ?? []).sorted(by: nodeSort)

            for (index, node) in sorted.enumerated() {
                let nodeRadius = min(radius(for: node) * 1.25, min(width, height) * 0.22)
                var candidate = center
                var attempt = 0
                while attempt < 220 {
                    let angle = Double(attempt) * 2.399963 + deterministicUnit(node.id) * .pi
                    let spiral = 0.018 * sqrt(Double(attempt))
                    candidate = SemanticPoint(
                        x: center.x + cos(angle) * spiral * width,
                        y: center.y + sin(angle) * spiral * height
                    )
                    let paddedX = candidate.x.clamped(to: (minX + nodeRadius)...(maxX - nodeRadius))
                    let paddedY = candidate.y.clamped(to: (minY + nodeRadius)...(maxY - nodeRadius))
                    candidate = SemanticPoint(x: paddedX, y: paddedY)
                    let collides = groupPlaced.contains { existing in
                        let existingRadius = existing.radius
                        let dx = existing.x - candidate.x
                        let dy = existing.y - candidate.y
                        return sqrt(dx * dx + dy * dy) < existingRadius + nodeRadius + 0.012
                    }
                    if !collides { break }
                    attempt += 1
                }
                if index == 0 {
                    candidate = center
                }
                groupPlaced.append(SemanticPositionedNode(nodeID: node.id, x: candidate.x, y: candidate.y, radius: nodeRadius))
            }
            placed += groupPlaced
        }
        return placed
    }

    private static func makeWordCloudItems(nodes: [SemanticTermNode]) -> [SemanticWordCloudItem] {
        nodes.map { node in
            SemanticWordCloudItem(
                nodeID: node.id,
                text: node.displayName,
                kind: node.kind,
                fontSize: 11 + node.score * 23,
                score: node.score
            )
        }
    }

    private static func makeTimeline(
        analysis: TranscriptAnalysisSnapshot,
        sessions: [Session],
        calendar: Calendar
    ) -> (granularity: SemanticTimelineGranularity, kinds: [TranscriptTermKind], points: [SemanticTimelinePoint]) {
        let sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let datedAnalyses = analysis.sessionAnalyses.compactMap { sessionAnalysis -> (Date, TranscriptSessionAnalysis)? in
            guard let session = sessionsByID[sessionAnalysis.sessionID] else { return nil }
            return (session.stats?.lastActivity ?? session.lastModified, sessionAnalysis)
        }
        guard let minDate = datedAnalyses.map(\.0).min(), let maxDate = datedAnalyses.map(\.0).max() else {
            return (.day, [], [])
        }

        let spanDays = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: minDate), to: calendar.startOfDay(for: maxDate)).day ?? 1)
        let granularity: SemanticTimelineGranularity = spanDays <= 32 ? .day : (spanDays <= 180 ? .week : .month)
        let corpusTerms = Dictionary(uniqueKeysWithValues: analysis.terms.map { (termID(canonical: $0.canonical, kind: $0.kind), $0) })

        struct MutablePoint {
            var value: Double = 0
            var topTermID: String?
            var topTermValue: Double = 0
        }

        var buckets: [String: MutablePoint] = [:]
        var bucketDates: [String: Date] = [:]
        var bucketKinds: [String: TranscriptTermKind] = [:]

        for (date, sessionAnalysis) in datedAnalyses {
            let bucketDate = granularity.bucketStart(for: date, calendar: calendar)
            for term in sessionAnalysis.terms.prefix(Self.termsPerSessionForCooccurrence) {
                let id = termID(canonical: term.canonical, kind: term.kind)
                let corpus = corpusTerms[id]
                let contribution = max(0.1, term.weightedFrequency) * log1p(max(corpus?.tfidf ?? term.weightedFrequency, 0.1))
                let key = "\(Int(bucketDate.timeIntervalSinceReferenceDate.rounded()))|\(term.kind.rawValue)"
                var point = buckets[key] ?? MutablePoint()
                point.value += contribution
                if contribution > point.topTermValue {
                    point.topTermID = id
                    point.topTermValue = contribution
                }
                buckets[key] = point
                bucketDates[key] = bucketDate
                bucketKinds[key] = term.kind
            }
        }

        let maxValue = max(buckets.values.map(\.value).max() ?? 1, 1)
        let points = buckets.compactMap { key, point -> SemanticTimelinePoint? in
            guard let date = bucketDates[key], let kind = bucketKinds[key] else { return nil }
            return SemanticTimelinePoint(
                date: date,
                kind: kind,
                value: point.value,
                score: point.value / maxValue,
                topTermID: point.topTermID
            )
        }
        .sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return kindIndex($0.kind) < kindIndex($1.kind)
        }
        let kinds = TranscriptTermKind.allCases.filter { kind in
            points.contains { $0.kind == kind }
        }
        return (granularity, kinds, points)
    }

    private static func initialPosition(for node: SemanticTermNode) -> SemanticPoint {
        let kind = Double(kindIndex(node.kind))
        let kindCount = Double(max(TranscriptTermKind.allCases.count, 1))
        let jitter = deterministicUnit(node.id)
        let angle = (kind / kindCount) * Double.pi * 2 + (jitter - 0.5) * 0.42
        let distance = 0.20 + deterministicUnit("distance|\(node.id)") * 0.24
        return SemanticPoint(x: 0.5 + cos(angle) * distance, y: 0.5 + sin(angle) * distance)
    }

    private static func normalize(points: [SemanticPoint], padding: Double) -> [SemanticPoint] {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max() else {
            return points
        }
        let width = max(maxX - minX, 0.001)
        let height = max(maxY - minY, 0.001)
        let scale = 1 - padding * 2
        return points.map { point in
            SemanticPoint(
                x: (padding + ((point.x - minX) / width) * scale).clamped(to: 0...1),
                y: (padding + ((point.y - minY) / height) * scale).clamped(to: 0...1)
            )
        }
    }

    private static func radius(for node: SemanticTermNode) -> Double {
        0.018 + node.score * 0.042
    }

    private static func normalized(_ value: Double, min: Double, max: Double) -> Double {
        guard max > min else { return 1 }
        return ((value - min) / (max - min)).clamped(to: 0...1)
    }

    static func termID(canonical: String, kind: TranscriptTermKind) -> String {
        "\(kind.rawValue)|\(canonical)"
    }

    static func pairKey(_ firstID: String, _ secondID: String) -> String {
        firstID < secondID ? "\(firstID)\u{1F}\(secondID)" : "\(secondID)\u{1F}\(firstID)"
    }

    private static func termSort(_ lhs: TranscriptTermStats, _ rhs: TranscriptTermStats) -> Bool {
        if lhs.tfidf != rhs.tfidf { return lhs.tfidf > rhs.tfidf }
        if lhs.frequency != rhs.frequency { return lhs.frequency > rhs.frequency }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private static func nodeSort(_ lhs: SemanticTermNode, _ rhs: SemanticTermNode) -> Bool {
        if lhs.tfidf != rhs.tfidf { return lhs.tfidf > rhs.tfidf }
        if lhs.frequency != rhs.frequency { return lhs.frequency > rhs.frequency }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private static func kindIndex(_ kind: TranscriptTermKind) -> Int {
        TranscriptTermKind.allCases.firstIndex(of: kind) ?? 0
    }

    private static func deterministicUnit(_ value: String) -> Double {
        Double(stableHash(value) % 10_000) / 10_000
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    private struct MutableKindSummary: Hashable {
        let kind: TranscriptTermKind
        var termCount = 0
        var frequency = 0
        var documentFrequency = 0
        var tfidf: Double = 0
        var topTermID: String?
        var topScore: Double = 0
    }
}

struct SemanticTermNode: Identifiable, Hashable, Sendable {
    let id: String
    let canonical: String
    let displayName: String
    let kind: TranscriptTermKind
    let frequency: Int
    let documentFrequency: Int
    let tfidf: Double
    let score: Double
    let examples: [TranscriptTermExample]
}

struct SemanticKindSummary: Identifiable, Hashable, Sendable {
    var id: TranscriptTermKind { kind }

    let kind: TranscriptTermKind
    let termCount: Int
    let frequency: Int
    let documentFrequency: Int
    let tfidf: Double
    let topTermID: String?
}

struct SemanticCooccurrenceEdge: Identifiable, Hashable, Sendable {
    var id: String { SemanticVisualizationSnapshot.pairKey(sourceID, targetID) }

    let sourceID: String
    let targetID: String
    let count: Int
    let strength: Double
}

struct SemanticPositionedNode: Identifiable, Hashable, Sendable {
    var id: String { nodeID }

    let nodeID: String
    let x: Double
    let y: Double
    let radius: Double
}

struct SemanticWordCloudItem: Identifiable, Hashable, Sendable {
    var id: String { nodeID }

    let nodeID: String
    let text: String
    let kind: TranscriptTermKind
    let fontSize: Double
    let score: Double
}

struct SemanticTimelinePoint: Identifiable, Hashable, Sendable {
    var id: String { "\(Int(date.timeIntervalSinceReferenceDate.rounded()))|\(kind.rawValue)" }

    let date: Date
    let kind: TranscriptTermKind
    let value: Double
    let score: Double
    let topTermID: String?
}

private struct SemanticPoint: Hashable {
    static let zero = SemanticPoint(x: 0, y: 0)

    var x: Double
    var y: Double
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
