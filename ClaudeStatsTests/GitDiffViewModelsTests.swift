import Foundation
import Testing
@testable import ClaudeStats

@Suite("Git diff viewer models")
struct GitDiffViewModelsTests {
    @Test("Structured diff groups context and adjacent change blocks")
    func structuredDiffGroupsChangeBlocks() throws {
        let diff = fileDiff("""
        diff --git a/A.swift b/A.swift
        index 111..222 100644
        --- a/A.swift
        +++ b/A.swift
        @@ -10,4 +10,5 @@
         let before = true
        -let a = 1
        -let b = 2
        +let a = 1
        +let b = 3
        +let c = 4
         return before
        """)

        let structured = StructuredFileDiff.build(from: diff)
        #expect(structured.fileHeaders.count == 4)
        #expect(structured.hunks.count == 1)
        let hunk = try #require(structured.hunks.first)
        #expect(hunk.oldStart == 10)
        #expect(hunk.newStart == 10)
        #expect(hunk.segments.map(\.kind) == [.context, .change, .context])

        let change = try #require(hunk.segments.first { $0.kind == .change }?.change)
        #expect(change.oldLines.count == 2)
        #expect(change.newLines.count == 3)
        #expect(change.linePairs.map(\.kind) == [.modified, .modified, .inserted])
        #expect(change.linePairs[1].oldLine?.inlineSpans.isEmpty == false)
        #expect(change.linePairs[1].newLine?.inlineSpans.isEmpty == false)
    }

    @Test("Structured diff handles pure additions, pure deletions and newline markers")
    func structuredDiffHandlesPureChanges() throws {
        let diff = fileDiff("""
        diff --git a/A.swift b/A.swift
        index 111..222 100644
        --- a/A.swift
        +++ b/A.swift
        @@ -1,3 +1,4 @@
        -removed
         kept
        +added
        +last
        \\ No newline at end of file
        """)

        let structured = StructuredFileDiff.build(from: diff)
        let segments = try #require(structured.hunks.first?.segments)
        #expect(segments.map(\.kind) == [.change, .context, .change, .context])
        #expect(segments[0].change?.linePairs.map(\.kind) == [.deleted])
        #expect(segments[2].change?.linePairs.map(\.kind) == [.inserted, .inserted])
        #expect(segments[3].contextLines.first?.oldLine == nil)
    }

    @Test("Structured diff preserves multiple hunks")
    func structuredDiffPreservesMultipleHunks() throws {
        let structured = StructuredFileDiff.build(from: fileDiff("""
        @@ -1,2 +1,2 @@
         first
        -old one
        +new one
        @@ -20,2 +20,2 @@
         second
        -old two
        +new two
        """))

        #expect(structured.hunks.count == 2)
        #expect(structured.hunks.map(\.oldStart) == [1, 20])
        #expect(structured.hunks.map(\.newStart) == [1, 20])
    }

    @Test("Binary diff preserves binary state")
    func binaryDiffPreservesState() {
        let structured = StructuredFileDiff.build(from: FileDiff(path: "logo.png", isBinary: true, lines: []))
        #expect(structured.isBinary)
        #expect(!structured.isEmpty)
    }

    @Test("Fluid sync map keeps equal height blocks at the same offset")
    func fluidSyncMapEqualHeights() throws {
        let structured = StructuredFileDiff.build(from: fileDiff("""
        @@ -1,1 +1,1 @@
        -let a = 1
        +let a = 2
        """))
        let map = FluidSyncMap.build(from: structured, lineHeight: 10)
        let offsets = map.offsets(for: 15)
        #expect(close(offsets.oldY, 15))
        #expect(close(offsets.newY, 15))
    }

    @Test("Fluid sync map advances taller side faster inside mismatched blocks")
    func fluidSyncMapMismatchedHeights() {
        let structured = StructuredFileDiff.build(from: fileDiff("""
        @@ -1,1 +1,3 @@
        -old
        +new one
        +new two
        +new three
        """))
        let map = FluidSyncMap.build(from: structured, lineHeight: 10)
        let offsets = map.offsets(for: 25)
        #expect(offsets.oldY >= 10 && offsets.oldY <= 20)
        #expect(offsets.newY >= 10 && offsets.newY <= 40)
        #expect(offsets.newY - 10 > offsets.oldY - 10)
    }

    @Test("Fluid sync map pins missing side for pure insertions")
    func fluidSyncMapPinsInsertionAnchor() {
        let structured = StructuredFileDiff.build(from: fileDiff("""
        @@ -1,1 +1,3 @@
         kept
        +new one
        +new two
        """))
        let map = FluidSyncMap.build(from: structured, lineHeight: 10)
        let offsets = map.offsets(for: 25)
        #expect(close(offsets.oldY, 20))
        #expect(offsets.newY > 20)
    }

    @Test("Fluid sync map pins missing side for pure deletions")
    func fluidSyncMapPinsDeletionAnchor() {
        let structured = StructuredFileDiff.build(from: fileDiff("""
        @@ -1,3 +1,1 @@
         kept
        -old one
        -old two
        """))
        let map = FluidSyncMap.build(from: structured, lineHeight: 10)
        let offsets = map.offsets(for: 25)
        #expect(offsets.oldY > 20)
        #expect(close(offsets.newY, 20))
    }

    @Test("Fluid sync map offsets are monotonic")
    func fluidSyncMapIsMonotonic() {
        let structured = StructuredFileDiff.build(from: fileDiff("""
        @@ -1,2 +1,4 @@
         kept
        -old
        +new one
        +new two
        +new three
        """))
        let map = FluidSyncMap.build(from: structured, lineHeight: 10)
        var previous = FluidSyncMap.Offsets(oldY: 0, newY: 0)
        for y in stride(from: 0.0, through: map.virtualHeight, by: 2.5) {
            let offsets = map.offsets(for: y)
            #expect(offsets.oldY >= previous.oldY)
            #expect(offsets.newY >= previous.newY)
            previous = offsets
        }
    }

    @Test("Low similarity replacements are not forced into modified pairs")
    func lowSimilarityLinesStaySeparate() throws {
        let structured = StructuredFileDiff.build(from: fileDiff("""
        @@ -1,1 +1,1 @@
        -abc
        +xyz
        """))
        let change = try #require(structured.hunks.first?.segments.first?.change)
        #expect(change.linePairs.map(\.kind) == [.deleted, .inserted])
    }

    @Test("Repeated similar line pairing remains monotonic")
    func repeatedSimilarLinePairingIsMonotonic() throws {
        let structured = StructuredFileDiff.build(from: fileDiff("""
        @@ -1,2 +1,2 @@
        -let firstProvider = alpha
        -let secondProvider = beta
        +let secondProvider = beta
        +let firstProvider = alpha
        """))
        let change = try #require(structured.hunks.first?.segments.first?.change)
        let modified = change.linePairs.compactMap { pair -> (old: Int, new: Int)? in
            guard pair.kind == .modified,
                  let oldLine = pair.oldLine?.oldLine,
                  let newLine = pair.newLine?.newLine else {
                return nil
            }
            return (oldLine, newLine)
        }

        var isMonotonic = true
        for index in modified.indices.dropFirst() {
            let previous = modified[modified.index(before: index)]
            let current = modified[index]
            if current.old < previous.old || (current.old == previous.old && current.new < previous.new) {
                isMonotonic = false
            }
        }
        #expect(isMonotonic)
    }

    @Test("Inline diff highlights token replacements")
    func inlineDiffHighlightsReplacement() {
        let spans = InlineDiffBuilder().spans(old: "let name = oldValue", new: "let name = newValue")
        #expect(!spans.old.isEmpty)
        #expect(!spans.new.isEmpty)
    }

    @Test("Inline diff highlights token insertions")
    func inlineDiffHighlightsInsertion() {
        let spans = InlineDiffBuilder().spans(old: "call(a)", new: "call(a, b)")
        #expect(spans.old.isEmpty)
        #expect(!spans.new.isEmpty)
    }

    @Test("Inline diff highlights token deletions")
    func inlineDiffHighlightsDeletion() {
        let spans = InlineDiffBuilder().spans(old: "call(a, b)", new: "call(a)")
        #expect(!spans.old.isEmpty)
        #expect(spans.new.isEmpty)
    }

    private func fileDiff(_ patch: String) -> FileDiff {
        FileDiff(path: "A.swift", isBinary: false, lines: GitAnalyzer.parseUnifiedDiff(patch))
    }

    private func close(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.0001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}
