import Foundation

/// Persists billable usage independently from transcript files. Aggregate
/// usage reads from this ledger so deleting transcripts does not rewrite
/// history.
actor UsageLedgerStore {
    private let fileURL: URL
    private var snapshot: UsageLedgerSnapshot

    init(fileURL: URL = UsageLedgerPaths.ledgerURL()) {
        self.fileURL = fileURL
        self.snapshot = Self.load(from: fileURL)
    }

    func events(provider: ProviderKind? = nil) -> [UsageLedgerEvent] {
        let live = snapshot.events
        guard let provider else { return live }
        return live.filter { $0.provider == provider }
    }

    func stats(for session: Session, calendar: Calendar = .current) -> SessionStats? {
        let sessionEvents = snapshot.events
            .filter { $0.sessionID == session.id }
            .sorted { $0.timestamp < $1.timestamp }
        guard let state = snapshot.parseStates.first(where: { $0.sessionID == session.id }),
              state.hasViewableTranscript != false,
              !sessionEvents.isEmpty || state.messageCount > 0 else {
            return nil
        }
        return Self.stats(
            title: state.title ?? session.projectDisplayName,
            messageCount: state.messageCount,
            firstActivity: state.firstActivity,
            lastActivity: state.lastActivity,
            events: sessionEvents,
            calendar: calendar,
            lastModel: state.lastModel
        )
    }

    func visibleSessionIDs() -> Set<String> {
        Set(snapshot.parseStates.filter(\.sourceExists).map(\.sessionID))
    }

    func parseState(for sessionID: String) -> UsageLedgerParseState? {
        snapshot.parseStates.first { $0.sessionID == sessionID }
    }

    func replaceEvents(for session: Session, stats: SessionStats, now: Date = .now) async {
        let newEvents = Self.events(from: stats, session: session)
        snapshot.events.removeAll { $0.sessionID == session.id }
        snapshot.events.append(contentsOf: newEvents)
        upsertParseState(for: session, stats: stats, sourceExists: true, eventCount: newEvents.count, now: now)
        persist()
    }

    func clearEvents(for session: Session, now: Date = .now) async {
        snapshot.events.removeAll { $0.sessionID == session.id }
        let empty = SessionStats(
            title: session.projectDisplayName,
            messageCount: 0,
            firstActivity: nil,
            lastActivity: nil,
            models: [],
            timeline: []
        )
        upsertParseState(for: session, stats: empty, sourceExists: true, eventCount: 0, now: now)
        persist()
    }

    func markUnviewable(for session: Session, now: Date = .now) async {
        if let index = snapshot.parseStates.firstIndex(where: { $0.sessionID == session.id }) {
            snapshot.parseStates[index].sourceExists = true
            snapshot.parseStates[index].lastSeenAt = now
            snapshot.parseStates[index].hasViewableTranscript = false
        } else {
            snapshot.parseStates.append(UsageLedgerParseState(
                sessionID: session.id,
                provider: session.provider,
                sourcePath: session.filePath,
                fileSize: session.fileSize,
                lastModified: session.lastModified,
                lastParsedByteOffset: UInt64(max(session.fileSize, 0)),
                eventCount: 0,
                title: nil,
                messageCount: 0,
                firstActivity: nil,
                lastActivity: nil,
                sourceExists: true,
                lastSeenAt: now,
                lastModel: nil,
                hasViewableTranscript: false
            ))
        }
        persist()
    }

    func appendEvents(for session: Session, result: UsageLedgerAppendResult, now: Date = .now) async {
        let existingKeys = Set(snapshot.events.map(\.eventKey))
        let newEvents = result.events.filter { !existingKeys.contains($0.eventKey) }
        snapshot.events.append(contentsOf: newEvents)
        upsertParseState(for: session, append: result, parsedEventCount: result.events.count, sourceExists: true, now: now)
        persist()
    }

    func markSeen(_ sessions: [Session], now: Date = .now) async {
        let liveIDs = Set(sessions.map(\.id))
        for index in snapshot.parseStates.indices {
            snapshot.parseStates[index].sourceExists = liveIDs.contains(snapshot.parseStates[index].sessionID)
            if snapshot.parseStates[index].sourceExists {
                snapshot.parseStates[index].lastSeenAt = now
            }
        }
        persist()
    }

    func syncParentSessionIDs(mapping: [String: String], liveSessionIDs: Set<String>) async {
        var didChange = false
        for index in snapshot.events.indices where liveSessionIDs.contains(snapshot.events[index].sessionID) {
            guard let parentID = mapping[snapshot.events[index].sessionID],
                  snapshot.events[index].parentSessionID != parentID else {
                continue
            }
            snapshot.events[index].parentSessionID = parentID
            didChange = true
        }
        if didChange { persist() }
    }

    private func upsertParseState(for session: Session, stats: SessionStats, sourceExists: Bool, eventCount: Int, now: Date) {
        let offset = UInt64(max(session.fileSize, 0))
        if let index = snapshot.parseStates.firstIndex(where: { $0.sessionID == session.id }) {
            snapshot.parseStates[index].fileSize = session.fileSize
            snapshot.parseStates[index].lastModified = session.lastModified
            snapshot.parseStates[index].lastParsedByteOffset = offset
            snapshot.parseStates[index].eventCount = eventCount
            snapshot.parseStates[index].title = stats.title
            snapshot.parseStates[index].messageCount = stats.messageCount
            snapshot.parseStates[index].firstActivity = stats.firstActivity
            snapshot.parseStates[index].lastActivity = stats.lastActivity
            snapshot.parseStates[index].sourceExists = sourceExists
            snapshot.parseStates[index].lastSeenAt = now
            snapshot.parseStates[index].lastModel = stats.lastModel
            snapshot.parseStates[index].hasViewableTranscript = true
        } else {
            snapshot.parseStates.append(UsageLedgerParseState(
                sessionID: session.id,
                provider: session.provider,
                sourcePath: session.filePath,
                fileSize: session.fileSize,
                lastModified: session.lastModified,
                lastParsedByteOffset: offset,
                eventCount: eventCount,
                title: stats.title,
                messageCount: stats.messageCount,
                firstActivity: stats.firstActivity,
                lastActivity: stats.lastActivity,
                sourceExists: sourceExists,
                lastSeenAt: now,
                lastModel: stats.lastModel,
                hasViewableTranscript: true
            ))
        }
    }

    private func upsertParseState(
        for session: Session,
        append result: UsageLedgerAppendResult,
        parsedEventCount: Int,
        sourceExists: Bool,
        now: Date
    ) {
        if let index = snapshot.parseStates.firstIndex(where: { $0.sessionID == session.id }) {
            snapshot.parseStates[index].fileSize = Int64(min(result.lastParsedByteOffset, UInt64(Int64.max)))
            snapshot.parseStates[index].lastModified = session.lastModified
            snapshot.parseStates[index].lastParsedByteOffset = result.lastParsedByteOffset
            snapshot.parseStates[index].eventCount += parsedEventCount
            if let title = result.title {
                snapshot.parseStates[index].title = title
            }
            snapshot.parseStates[index].messageCount += result.messageCountDelta
            if let first = result.firstActivity {
                let existing = snapshot.parseStates[index].firstActivity
                snapshot.parseStates[index].firstActivity = existing.map { min($0, first) } ?? first
            }
            if let last = result.lastActivity {
                let existing = snapshot.parseStates[index].lastActivity
                snapshot.parseStates[index].lastActivity = existing.map { max($0, last) } ?? last
            }
            snapshot.parseStates[index].sourceExists = sourceExists
            snapshot.parseStates[index].lastSeenAt = now
            snapshot.parseStates[index].lastModel = result.lastModel
            snapshot.parseStates[index].hasViewableTranscript = true
        } else {
            let stats = Self.stats(
                title: result.title ?? session.projectDisplayName,
                messageCount: result.messageCountDelta,
                firstActivity: result.firstActivity,
                lastActivity: result.lastActivity,
                events: result.events,
                calendar: .current,
                lastModel: result.lastModel
            )
            upsertParseState(for: session, stats: stats, sourceExists: sourceExists, eventCount: result.events.count, now: now)
        }
    }

    private static func stats(
        title: String,
        messageCount: Int,
        firstActivity: Date?,
        lastActivity: Date?,
        events: [UsageLedgerEvent],
        calendar: Calendar,
        lastModel: String? = nil
    ) -> SessionStats {
        var perModel: [String: (count: Int, usage: TokenUsage, cost: CostEstimate)] = [:]
        var perModelHourly: [String: [Date: TokenUsage]] = [:]
        let billableMessages = events.map { event in
            BillableMessage(
                hash: event.eventKey,
                model: event.model,
                usage: event.usage,
                cost: event.cost,
                timestamp: event.timestamp
            )
        }

        for event in events {
            var acc = perModel[event.model] ?? (0, .zero, .zero)
            acc.count += 1
            acc.usage += event.usage
            acc.cost += event.cost
            perModel[event.model] = acc

            let hour = calendar.dateInterval(of: .hour, for: event.timestamp)?.start
                ?? calendar.startOfDay(for: event.timestamp)
            perModelHourly[event.model, default: [:]][hour, default: .zero] += event.usage
        }

        let models = perModel
            .map { ModelUsage(model: $0.key, messageCount: $0.value.count, usage: $0.value.usage, costEstimate: $0.value.cost) }
            .sorted { $0.usage.total > $1.usage.total }
        let timeline = perModelHourly
            .flatMap { model, byHour in byHour.map { ModelBucket(model: model, start: $0.key, usage: $0.value) } }
            .sorted { $0.start < $1.start }

        return SessionStats(
            title: title,
            messageCount: messageCount,
            firstActivity: firstActivity ?? events.map(\.timestamp).min(),
            lastActivity: lastActivity ?? events.map(\.timestamp).max(),
            models: models,
            timeline: timeline,
            billableMessages: billableMessages,
            lastModel: lastModel
        )
    }

    private static func events(from stats: SessionStats, session: Session) -> [UsageLedgerEvent] {
        if !stats.billableMessages.isEmpty {
            return stats.billableMessages.enumerated().compactMap { index, bill in
                guard let timestamp = bill.timestamp else { return nil }
                return UsageLedgerEvent(
                    eventKey: bill.hash ?? "\(session.provider.rawValue)|\(session.id)|\(index)|\(Int(timestamp.timeIntervalSince1970))",
                    sessionID: session.id,
                    provider: session.provider,
                    model: bill.model,
                    timestamp: timestamp,
                    usage: bill.usage,
                    cost: bill.cost,
                    sourcePath: session.filePath,
                    sequenceIndex: index,
                    parentSessionID: session.agentInfo?.parentSessionID
                )
            }
        }

        let timestamp = stats.lastActivity ?? session.lastModified
        return stats.models.enumerated().map { index, model in
            UsageLedgerEvent(
                eventKey: "\(session.provider.rawValue)|\(session.id)|legacy|\(index)",
                sessionID: session.id,
                provider: session.provider,
                model: model.model,
                timestamp: timestamp,
                usage: model.usage,
                cost: model.costEstimate,
                sourcePath: session.filePath,
                sequenceIndex: index,
                parentSessionID: session.agentInfo?.parentSessionID
            )
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            Log.store.error("Failed to persist usage ledger: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> UsageLedgerSnapshot {
        guard let data = try? Data(contentsOf: url) else { return UsageLedgerSnapshot() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(UsageLedgerSnapshot.self, from: data)) ?? UsageLedgerSnapshot()
    }
}
