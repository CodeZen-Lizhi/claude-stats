import Foundation
import Testing
@testable import ClaudeStats

@Suite("Semantic visualization snapshot")
struct SemanticVisualizationSnapshotTests {
    @Test("Applies top limits and aggregates kind summaries")
    func topLimitsAndKindSummaries() throws {
        let terms = (0..<90).map { index in
            Self.term(
                "Term \(index)",
                kind: index.isMultiple(of: 2) ? .framework : .command,
                frequency: index + 1,
                documentFrequency: 1,
                tfidf: Double(index + 1)
            )
        }
        let analysis = Self.snapshot(terms: terms, analyses: [])

        let visual = SemanticVisualizationSnapshot(analysis: analysis, sessions: [])

        #expect(visual.nodes.count == SemanticVisualizationSnapshot.atlasTermLimit)
        #expect(visual.atlasNodes.count == SemanticVisualizationSnapshot.atlasTermLimit)
        #expect(visual.bubbleNodes.count == SemanticVisualizationSnapshot.bubbleTermLimit)
        #expect(visual.wordCloudItems.count == SemanticVisualizationSnapshot.wordCloudTermLimit)
        #expect(visual.nodes.first?.canonical == "Term 89")
        #expect(visual.kindSummaries.first { $0.kind == .framework }?.termCount == 45)
        #expect(visual.kindSummaries.first { $0.kind == .command }?.termCount == 45)
    }

    @Test("Counts session-level co-occurrence from top terms")
    func cooccurrenceCountsTopTerms() throws {
        let terms = [
            Self.term("SwiftUI", kind: .framework, tfidf: 100),
            Self.term("AppKit", kind: .framework, tfidf: 80),
            Self.term("git status", kind: .command, tfidf: 60),
        ]
        let analyses = [
            Self.analysis(sessionID: "s1", terms: [
                Self.sessionTerm("SwiftUI", kind: .framework, frequency: 3),
                Self.sessionTerm("AppKit", kind: .framework, frequency: 2),
                Self.sessionTerm("git status", kind: .command, frequency: 1),
            ]),
            Self.analysis(sessionID: "s2", terms: [
                Self.sessionTerm("SwiftUI", kind: .framework, frequency: 1),
                Self.sessionTerm("AppKit", kind: .framework, frequency: 1),
            ]),
            Self.analysis(sessionID: "s3", terms: [
                Self.sessionTerm("AppKit", kind: .framework, frequency: 1),
                Self.sessionTerm("git status", kind: .command, frequency: 1),
            ]),
        ]
        let visual = SemanticVisualizationSnapshot(
            analysis: Self.snapshot(terms: terms, analyses: analyses),
            sessions: []
        )

        let swiftUI = SemanticVisualizationSnapshot.termID(canonical: "SwiftUI", kind: .framework)
        let appKit = SemanticVisualizationSnapshot.termID(canonical: "AppKit", kind: .framework)
        let gitStatus = SemanticVisualizationSnapshot.termID(canonical: "git status", kind: .command)

        #expect(visual.edgeCount(between: swiftUI, and: appKit) == 2)
        #expect(visual.edgeCount(between: appKit, and: gitStatus) == 2)
        #expect(visual.edgeCount(between: swiftUI, and: gitStatus) == 1)
        #expect(visual.edges.first?.count == 2)
    }

    @Test("Builds stable timeline buckets at day week and month granularity")
    func timelineBuckets() throws {
        let calendar = Calendar(identifier: .gregorian)
        let terms = [
            Self.term("SwiftUI", kind: .framework, tfidf: 100),
            Self.term("git status", kind: .command, tfidf: 70),
        ]
        let analyses = [
            Self.analysis(sessionID: "s1", terms: [Self.sessionTerm("SwiftUI", kind: .framework, frequency: 2)]),
            Self.analysis(sessionID: "s2", terms: [Self.sessionTerm("git status", kind: .command, frequency: 1)]),
        ]
        let base = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1)))

        let dayVisual = SemanticVisualizationSnapshot(
            analysis: Self.snapshot(terms: terms, analyses: analyses),
            sessions: [
                Self.session(id: "s1", date: base),
                Self.session(id: "s2", date: try #require(calendar.date(byAdding: .day, value: 10, to: base))),
            ],
            calendar: calendar
        )
        #expect(dayVisual.timelineGranularity == .day)
        #expect(dayVisual.timelinePoints.map(\.date).contains(calendar.startOfDay(for: base)))
        #expect(Set(dayVisual.timelineKinds) == Set([.framework, .command]))

        let weekVisual = SemanticVisualizationSnapshot(
            analysis: Self.snapshot(terms: terms, analyses: analyses),
            sessions: [
                Self.session(id: "s1", date: base),
                Self.session(id: "s2", date: try #require(calendar.date(byAdding: .day, value: 100, to: base))),
            ],
            calendar: calendar
        )
        #expect(weekVisual.timelineGranularity == .week)

        let monthVisual = SemanticVisualizationSnapshot(
            analysis: Self.snapshot(terms: terms, analyses: analyses),
            sessions: [
                Self.session(id: "s1", date: base),
                Self.session(id: "s2", date: try #require(calendar.date(byAdding: .day, value: 250, to: base))),
            ],
            calendar: calendar
        )
        #expect(monthVisual.timelineGranularity == .month)
    }

    @Test("Produces deterministic finite layout coordinates")
    func layoutCoordinatesAreStableAndFinite() throws {
        let terms = (0..<16).map { index in
            Self.term(
                "Node \(index)",
                kind: TranscriptTermKind.allCases[index % TranscriptTermKind.allCases.count],
                frequency: index + 1,
                documentFrequency: 1,
                tfidf: Double(100 - index)
            )
        }
        let analyses = [
            Self.analysis(sessionID: "s1", terms: terms.prefix(8).map { Self.sessionTerm($0.canonical, kind: $0.kind, frequency: 2) }),
            Self.analysis(sessionID: "s2", terms: terms.dropFirst(4).prefix(8).map { Self.sessionTerm($0.canonical, kind: $0.kind, frequency: 1) }),
        ]
        let analysis = Self.snapshot(terms: terms, analyses: analyses)
        let first = SemanticVisualizationSnapshot(analysis: analysis, sessions: [])
        let second = SemanticVisualizationSnapshot(analysis: analysis, sessions: [])

        #expect(first.atlasNodes == second.atlasNodes)
        #expect(first.bubbleNodes == second.bubbleNodes)
        for positioned in first.atlasNodes + first.bubbleNodes {
            #expect(positioned.x.isFinite)
            #expect(positioned.y.isFinite)
            #expect(positioned.radius.isFinite)
            #expect((0...1).contains(positioned.x))
            #expect((0...1).contains(positioned.y))
            #expect(positioned.radius > 0)
        }
    }

    @Test("Handles empty and single-term snapshots")
    func emptyAndSingleTermSnapshots() throws {
        let empty = SemanticVisualizationSnapshot(
            analysis: Self.snapshot(terms: [], analyses: []),
            sessions: []
        )
        #expect(empty.isEmpty)
        #expect(empty.atlasNodes.isEmpty)
        #expect(empty.timelinePoints.isEmpty)

        let single = SemanticVisualizationSnapshot(
            analysis: Self.snapshot(
                terms: [Self.term("SwiftUI", kind: .framework, tfidf: 12)],
                analyses: [Self.analysis(sessionID: "s1", terms: [Self.sessionTerm("SwiftUI", kind: .framework)])]
            ),
            sessions: [Self.session(id: "s1", date: Date(timeIntervalSince1970: 1_000))]
        )
        let positioned = try #require(single.atlasNodes.first)
        #expect(positioned.x == 0.5)
        #expect(positioned.y == 0.5)
        #expect(single.timelinePoints.count == 1)
    }

    private static let engine = TranscriptAnalysisEngineInfo(
        tokenizerID: "test-tokenizer",
        analysisVersion: "test-analysis",
        displayName: "Test",
        embeddingStatus: .notConfigured
    )

    private static func snapshot(
        terms: [TranscriptTermStats],
        analyses: [TranscriptSessionAnalysis]
    ) -> TranscriptAnalysisSnapshot {
        TranscriptAnalysisSnapshot(
            provider: .claude,
            generatedAt: Date(timeIntervalSince1970: 1_000),
            sessionCount: analyses.count,
            analyzedSessionCount: analyses.count,
            terms: terms,
            sessionAnalyses: analyses,
            engine: engine,
            analysisSignature: "test",
            runSummary: .empty
        )
    }

    private static func term(
        _ canonical: String,
        kind: TranscriptTermKind,
        frequency: Int = 1,
        documentFrequency: Int = 1,
        tfidf: Double
    ) -> TranscriptTermStats {
        TranscriptTermStats(
            canonical: canonical,
            displayName: canonical,
            kind: kind,
            aliases: [],
            frequency: frequency,
            documentFrequency: documentFrequency,
            tfidf: tfidf,
            roleCounts: TranscriptRoleCounts(),
            sourceCounts: TranscriptSourceCounts(),
            examples: []
        )
    }

    private static func analysis(
        sessionID: String,
        terms: [TranscriptSessionTerm]
    ) -> TranscriptSessionAnalysis {
        TranscriptSessionAnalysis(
            sessionID: sessionID,
            sessionTitle: sessionID,
            projectName: "Project",
            terms: terms
        )
    }

    private static func sessionTerm(
        _ canonical: String,
        kind: TranscriptTermKind,
        frequency: Int = 1,
        weight: Double = 1
    ) -> TranscriptSessionTerm {
        TranscriptSessionTerm(
            canonical: canonical,
            displayName: canonical,
            kind: kind,
            frequency: frequency,
            weight: weight,
            roleCounts: TranscriptRoleCounts(),
            sourceCounts: TranscriptSourceCounts(),
            example: nil
        )
    }

    private static func session(id: String, date: Date) -> Session {
        Session(
            id: id,
            externalID: id,
            provider: .claude,
            projectDirectoryName: "Project",
            filePath: "/tmp/\(id).jsonl",
            cwd: "/tmp/Project",
            lastModified: date,
            fileSize: 128,
            stats: nil
        )
    }
}
