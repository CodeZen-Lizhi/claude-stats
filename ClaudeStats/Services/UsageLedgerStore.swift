import Foundation

/// Persists billable usage independently from transcript files. Aggregate
/// usage reads from this ledger so deleting transcripts does not rewrite
/// history.
actor UsageLedgerStore {
    private let fileURL: URL
    private var snapshot: UsageLedgerSnapshot
    private var eventsBySessionID: [String: [UsageLedgerEvent]]
    private var parseStateBySessionID: [String: UsageLedgerParseState]
    private var eventKeys: Set<String>
    private var eventsAreDirty = false
    private var persistenceBatchDepth = 0
    private var hasDeferredPersistence = false

    init(fileURL: URL = UsageLedgerPaths.ledgerURL()) {
        self.fileURL = fileURL
        let snapshot = Self.load(from: fileURL)
        self.snapshot = snapshot
        self.eventsBySessionID = Dictionary(grouping: snapshot.events, by: \.sessionID)
        self.parseStateBySessionID = snapshot.parseStates.reduce(into: [:]) { states, state in
            states[state.sessionID] = state
        }
        self.eventKeys = Set(snapshot.events.map(\.eventKey))
    }

    func beginPersistenceBatch() {
        persistenceBatchDepth += 1
    }

    func endPersistenceBatch() {
        guard persistenceBatchDepth > 0 else { return }
        persistenceBatchDepth -= 1
        guard persistenceBatchDepth == 0, hasDeferredPersistence else { return }
        hasDeferredPersistence = false
        persistNow()
    }

    func events(provider: ProviderKind? = nil) -> [UsageLedgerEvent] {
        materializeEventsIfNeeded()
        let live = snapshot.events
        guard let provider else { return live }
        return live.filter { $0.provider == provider }
    }

    func stats(for session: Session, calendar: Calendar = .current) -> SessionStats? {
        let sessionEvents = (eventsBySessionID[session.id] ?? [])
            .sorted { $0.timestamp < $1.timestamp }
        guard let state = parseStateBySessionID[session.id],
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
        Set(parseStateBySessionID.values.filter(\.sourceExists).map(\.sessionID))
    }

    func parseState(for sessionID: String) -> UsageLedgerParseState? {
        parseStateBySessionID[sessionID]
    }

    func replaceEvents(for session: Session, stats: SessionStats, now: Date = .now) async {
        let newEvents = Self.events(from: stats, session: session)
        replaceIndexedEvents(for: session.id, with: newEvents)
        upsertParseState(for: session, stats: stats, sourceExists: true, eventCount: newEvents.count, now: now)
        persist()
    }

    func clearEvents(for session: Session, now: Date = .now) async {
        replaceIndexedEvents(for: session.id, with: [])
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
        if var state = parseStateBySessionID[session.id] {
            state.sourceExists = true
            state.lastSeenAt = now
            state.hasViewableTranscript = false
            upsertIndexedParseState(state)
        } else {
            upsertIndexedParseState(UsageLedgerParseState(
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
        let newEvents = result.events.filter { eventKeys.insert($0.eventKey).inserted }
        if !newEvents.isEmpty {
            eventsBySessionID[session.id, default: []].append(contentsOf: newEvents)
            eventsAreDirty = true
        }
        upsertParseState(for: session, append: result, parsedEventCount: result.events.count, sourceExists: true, now: now)
        persist()
    }

    func markSeen(_ sessions: [Session], now: Date = .now) async {
        let liveIDs = Set(sessions.map(\.id))
        var didChange = false
        for sessionID in Array(parseStateBySessionID.keys) {
            guard var state = parseStateBySessionID[sessionID] else { continue }
            let isLive = liveIDs.contains(sessionID)
            let wasLive = state.sourceExists
            if wasLive != isLive {
                state.sourceExists = isLive
                if isLive {
                    state.lastSeenAt = now
                }
                upsertIndexedParseState(state)
                didChange = true
            }
        }
        if didChange { persist() }
    }

    func syncParentSessionIDs(mapping: [String: String], liveSessionIDs: Set<String>) async {
        var didChange = false
        for sessionID in liveSessionIDs {
            guard let parentID = mapping[sessionID],
                  var events = eventsBySessionID[sessionID] else {
                continue
            }
            var sessionChanged = false
            for index in events.indices where events[index].parentSessionID != parentID {
                events[index].parentSessionID = parentID
                sessionChanged = true
            }
            if sessionChanged {
                eventsBySessionID[sessionID] = events
                didChange = true
            }
        }
        if didChange {
            eventsAreDirty = true
            persist()
        }
    }

    private func upsertParseState(for session: Session, stats: SessionStats, sourceExists: Bool, eventCount: Int, now: Date) {
        let offset = UInt64(max(session.fileSize, 0))
        if var state = parseStateBySessionID[session.id] {
            state.fileSize = session.fileSize
            state.lastModified = session.lastModified
            state.lastParsedByteOffset = offset
            state.eventCount = eventCount
            state.title = stats.title
            state.messageCount = stats.messageCount
            state.firstActivity = stats.firstActivity
            state.lastActivity = stats.lastActivity
            state.sourceExists = sourceExists
            state.lastSeenAt = now
            state.lastModel = stats.lastModel
            state.hasViewableTranscript = true
            upsertIndexedParseState(state)
        } else {
            upsertIndexedParseState(UsageLedgerParseState(
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
        if var state = parseStateBySessionID[session.id] {
            state.fileSize = Int64(min(result.lastParsedByteOffset, UInt64(Int64.max)))
            state.lastModified = session.lastModified
            state.lastParsedByteOffset = result.lastParsedByteOffset
            state.eventCount += parsedEventCount
            if let title = result.title {
                state.title = title
            }
            state.messageCount += result.messageCountDelta
            if let first = result.firstActivity {
                state.firstActivity = state.firstActivity.map { min($0, first) } ?? first
            }
            if let last = result.lastActivity {
                state.lastActivity = state.lastActivity.map { max($0, last) } ?? last
            }
            state.sourceExists = sourceExists
            state.lastSeenAt = now
            state.lastModel = result.lastModel
            state.hasViewableTranscript = true
            upsertIndexedParseState(state)
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
        guard persistenceBatchDepth == 0 else {
            hasDeferredPersistence = true
            return
        }
        persistNow()
    }

    private func persistNow() {
        do {
            materializeEventsIfNeeded()
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

    private func replaceIndexedEvents(for sessionID: String, with events: [UsageLedgerEvent]) {
        for event in eventsBySessionID[sessionID] ?? [] {
            eventKeys.remove(event.eventKey)
        }
        if events.isEmpty {
            eventsBySessionID.removeValue(forKey: sessionID)
        } else {
            eventsBySessionID[sessionID] = events
            eventKeys.formUnion(events.map(\.eventKey))
        }
        eventsAreDirty = true
    }

    private func upsertIndexedParseState(_ state: UsageLedgerParseState) {
        parseStateBySessionID[state.sessionID] = state
        if let index = snapshot.parseStates.firstIndex(where: { $0.sessionID == state.sessionID }) {
            snapshot.parseStates[index] = state
        } else {
            snapshot.parseStates.append(state)
        }
    }

    private func materializeEventsIfNeeded() {
        guard eventsAreDirty else { return }
        snapshot.events = eventsBySessionID.values
            .flatMap { $0 }
            .sorted {
                if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                return $0.eventKey < $1.eventKey
            }
        eventsAreDirty = false
    }

    private static func load(from url: URL) -> UsageLedgerSnapshot {
        guard let data = try? Data(contentsOf: url) else { return UsageLedgerSnapshot() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(UsageLedgerSnapshot.self, from: data)) ?? UsageLedgerSnapshot()
    }
}
