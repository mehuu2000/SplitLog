//
//  StopwatchService.swift
//  SplitLog
//
//  Created by Codex on 2026/02/17.
//

import Combine
import Foundation

@MainActor
final class StopwatchService: ObservableObject {
    @Published private(set) var sessions: [WorkSession] = []
    @Published private(set) var selectedSessionID: UUID?

    @Published private(set) var state: SessionState = .idle
    @Published private(set) var session: WorkSession?
    @Published private(set) var laps: [WorkLap] = []
    @Published private(set) var selectedLapID: UUID?
    @Published private(set) var clock: Date = Date()

    private var timerCancellable: AnyCancellable?
    private let autoTick: Bool
    private let foregroundClockUpdateInterval: TimeInterval = 1.0 / 60.0
    private let backgroundClockUpdateInterval: TimeInterval = 1.0
    private var isDisplayActive: Bool = false

    private var sessionContexts: [UUID: SessionContext] = [:]
    private var sessionOrder: [UUID] = []
    private var nextSessionNumber: Int = 1
    private let sessionStore: SessionStore?
    private let restoreReferenceDate: Date?

    private struct SessionContext: Codable, Sendable {
        var session: WorkSession
        var laps: [WorkLap]
        var selectedLapID: UUID?
        var state: SessionState
        var pauseStartedAt: Date?
        var lastLapActivationAt: Date?
        var completedPauseIntervals: [DateInterval]
    }

    init(
        autoTick: Bool = true,
        persistenceEnabled: Bool = true,
        sessionStore: SessionStore? = nil,
        restoreReferenceDate: Date? = nil
    ) {
        self.autoTick = autoTick
        self.restoreReferenceDate = restoreReferenceDate
        if let sessionStore {
            self.sessionStore = sessionStore
        } else if persistenceEnabled {
            self.sessionStore = FileSessionStore()
        } else {
            self.sessionStore = nil
        }
        restorePersistedState()
        applySelectedContext()
    }

    var currentLap: WorkLap? {
        guard let selectedLapID else { return nil }
        return laps.first(where: { $0.id == selectedLapID })
    }

    var completedLaps: [WorkLap] {
        laps.filter { $0.id != selectedLapID }
    }

    func addSession(at date: Date = Date()) {
        stopRunningSessions(except: nil, at: date)

        let context = makeIdleSessionContext(at: date)
        sessionContexts[context.session.id] = context
        sessionOrder.insert(context.session.id, at: 0)
        selectedSessionID = context.session.id
        commitSelectionUpdate(at: date)
    }

    func selectSession(sessionID: UUID, at date: Date = Date()) {
        guard sessionContexts[sessionID] != nil else { return }
        guard selectedSessionID != sessionID else { return }

        // Session switch must freeze elapsed time of the previously running session.
        stopRunningSessions(except: sessionID, at: date)

        selectedSessionID = sessionID
        commitSelectionUpdate(at: date)
    }

    func sessionState(for sessionID: UUID) -> SessionState {
        sessionContexts[sessionID]?.state ?? .idle
    }

    func startSession(at date: Date = Date()) {
        guard let selectedSessionID, var context = sessionContexts[selectedSessionID] else {
            let newContext = makeRunningSessionContext(at: date)
            sessionContexts[newContext.session.id] = newContext
            sessionOrder.insert(newContext.session.id, at: 0)
            selectedSessionID = newContext.session.id
            commitSelectionUpdate(at: date)
            return
        }

        switch context.state {
        case .running:
            return
        case .paused, .stopped:
            if context.laps.isEmpty {
                stopRunningSessions(except: context.session.id, at: date)
                activateIdleSession(&context, at: date)
                sessionContexts[selectedSessionID] = context
                break
            }
            stopRunningSessions(except: context.session.id, at: date)
            resume(context: &context, at: date)
            sessionContexts[selectedSessionID] = context
        case .idle, .finished:
            stopRunningSessions(except: context.session.id, at: date)
            activateIdleSession(&context, at: date)
            sessionContexts[selectedSessionID] = context
        }

        commitSelectedContextUpdate(context, for: selectedSessionID, at: date)
    }

    func finishLap(at date: Date = Date()) {
        guard
            let selectedSessionID,
            var context = sessionContexts[selectedSessionID],
            context.state == .running
        else {
            return
        }
        guard let selectedLapID = context.selectedLapID, let currentIndex = context.laps.firstIndex(where: { $0.id == selectedLapID }) else {
            return
        }

        accumulateActiveDuration(in: &context, until: date)
        if context.laps[currentIndex].endedAt == nil {
            context.laps[currentIndex].endedAt = date
        }

        let nextIndex = (context.laps.map(\.index).max() ?? 0) + 1
        let nextLap = WorkLap(
            id: UUID(),
            sessionId: context.session.id,
            index: nextIndex,
            startedAt: date,
            endedAt: nil,
            accumulatedDuration: 0,
            label: defaultLapLabel(for: nextIndex)
        )
        context.laps.append(nextLap)
        context.selectedLapID = nextLap.id
        context.lastLapActivationAt = date

        commitSelectedContextUpdate(context, for: selectedSessionID, at: date)
    }

    func selectLap(lapID: UUID, at date: Date = Date()) {
        guard
            let selectedSessionID,
            var context = sessionContexts[selectedSessionID],
            context.laps.contains(where: { $0.id == lapID }),
            context.selectedLapID != lapID
        else {
            return
        }

        if context.state == .running {
            accumulateActiveDuration(in: &context, until: date)
            context.selectedLapID = lapID
            context.lastLapActivationAt = date
        } else if context.state == .paused || context.state == .stopped {
            context.selectedLapID = lapID
        } else {
            return
        }

        commitSelectedContextUpdate(context, for: selectedSessionID, at: date)
    }

    func pauseSession(at date: Date = Date()) {
        guard
            let selectedSessionID,
            var context = sessionContexts[selectedSessionID],
            context.state == .running
        else {
            return
        }

        accumulateActiveDuration(in: &context, until: date)
        context.state = .paused
        context.pauseStartedAt = date
        context.lastLapActivationAt = nil

        commitSelectedContextUpdate(context, for: selectedSessionID, at: date)
    }

    func resumeSession(at date: Date = Date()) {
        guard
            let selectedSessionID,
            var context = sessionContexts[selectedSessionID],
            context.state == .paused || context.state == .stopped
        else {
            return
        }

        stopRunningSessions(except: context.session.id, at: date)
        resume(context: &context, at: date)

        commitSelectedContextUpdate(context, for: selectedSessionID, at: date)
    }

    func finishSession(at date: Date = Date()) {
        guard
            let selectedSessionID,
            var context = sessionContexts[selectedSessionID],
            context.state == .running || context.state == .paused
        else {
            return
        }

        let stoppedAt: Date
        if context.state == .paused, let pausedAt = context.pauseStartedAt {
            stoppedAt = pausedAt
        } else {
            stoppedAt = date
            accumulateActiveDuration(in: &context, until: stoppedAt)
            context.pauseStartedAt = stoppedAt
        }

        context.state = .stopped
        context.lastLapActivationAt = nil

        commitSelectedContextUpdate(context, for: selectedSessionID, at: stoppedAt)
    }

    func resetToIdle() {
        sessionContexts = [:]
        sessionOrder = []
        sessions = []
        selectedSessionID = nil
        nextSessionNumber = 1

        state = .idle
        session = nil
        laps = []
        selectedLapID = nil
        clock = Date()
        stopClock()

        removePersistedState()
    }

    func resetSelectedSession(at date: Date = Date()) {
        guard let selectedSessionID, var context = sessionContexts[selectedSessionID] else { return }

        context.state = .idle
        context.session.startedAt = date
        context.session.endedAt = nil
        context.laps = []
        context.selectedLapID = nil
        context.pauseStartedAt = nil
        context.lastLapActivationAt = nil
        context.completedPauseIntervals = []

        commitSelectedContextUpdate(context, for: selectedSessionID, at: date)
    }

    func clearAllLapsAndMemos(at date: Date = Date()) {
        guard !sessionOrder.isEmpty else { return }

        for sessionID in sessionOrder {
            guard var context = sessionContexts[sessionID] else { continue }
            context.state = .idle
            context.session.startedAt = date
            context.session.endedAt = nil
            context.laps = []
            context.selectedLapID = nil
            context.pauseStartedAt = nil
            context.lastLapActivationAt = nil
            context.completedPauseIntervals = []
            sessionContexts[sessionID] = context
        }

        if let selectedSessionID, sessionContexts[selectedSessionID] == nil {
            self.selectedSessionID = sessionOrder.first
        } else if selectedSessionID == nil {
            self.selectedSessionID = sessionOrder.first
        }

        commitSelectionUpdate(at: date)
    }

    func deleteSelectedSession(at date: Date = Date()) {
        guard let selectedSessionID else { return }
        guard let removedIndex = sessionOrder.firstIndex(of: selectedSessionID) else { return }

        sessionContexts.removeValue(forKey: selectedSessionID)
        sessionOrder.removeAll { $0 == selectedSessionID }

        if sessionOrder.isEmpty {
            self.selectedSessionID = nil
            nextSessionNumber = 1
            clock = date
            applySelectedContext()
            removePersistedState()
            return
        }

        let preferredIndex = max(0, removedIndex - 1)
        self.selectedSessionID = sessionOrder[preferredIndex]
        commitSelectionUpdate(at: date)
    }

    func updateLapLabel(lapID: UUID, label: String) {
        guard
            let selectedSessionID,
            var context = sessionContexts[selectedSessionID],
            let index = context.laps.firstIndex(where: { $0.id == lapID })
        else {
            return
        }

        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            context.laps[index].label = defaultLapLabel(for: context.laps[index].index)
        } else {
            context.laps[index].label = trimmed
        }

        sessionContexts[selectedSessionID] = context
        applySelectedContext()
        persistState()
    }

    func updateLapMemo(lapID: UUID, memo: String) {
        guard
            let selectedSessionID,
            var context = sessionContexts[selectedSessionID],
            let index = context.laps.firstIndex(where: { $0.id == lapID })
        else {
            return
        }

        context.laps[index].memo = memo
        sessionContexts[selectedSessionID] = context
        applySelectedContext()
        persistState()
    }

    func updateSessionTitle(sessionID: UUID, title: String) {
        guard var context = sessionContexts[sessionID] else { return }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        context.session.title = trimmed
        sessionContexts[sessionID] = context
        applySelectedContext()
        persistState()
    }

    func setDisplayActive(_ isActive: Bool) {
        guard isDisplayActive != isActive else { return }
        isDisplayActive = isActive
        syncTimerForSelectedState()
    }

    func prepareForTermination(at date: Date = Date()) {
        guard !sessionContexts.isEmpty else { return }

        for sessionID in sessionOrder {
            guard var context = sessionContexts[sessionID], context.state == .running else { continue }
            accumulateActiveDuration(in: &context, until: date)
            context.state = .stopped
            context.pauseStartedAt = date
            context.lastLapActivationAt = nil
            sessionContexts[sessionID] = context
        }

        clock = date
        applySelectedContext()
        persistState(savedAt: date)
    }

    func elapsedSession(at referenceDate: Date? = nil) -> TimeInterval {
        guard let context = currentContext else { return 0 }
        return elapsedSession(in: context, at: referenceDate ?? clock)
    }

    func elapsedSession(for sessionID: UUID, at referenceDate: Date? = nil) -> TimeInterval {
        guard let context = sessionContexts[sessionID] else { return 0 }
        return elapsedSession(in: context, at: referenceDate ?? clock)
    }

    func elapsedCurrentLap(at referenceDate: Date? = nil) -> TimeInterval {
        guard let currentLap else { return 0 }
        return elapsedLap(currentLap, at: referenceDate)
    }

    func elapsedLap(_ lap: WorkLap, at referenceDate: Date? = nil) -> TimeInterval {
        guard let context = currentContext else { return max(0, lap.accumulatedDuration) }
        return elapsedLap(lap, in: context, at: referenceDate ?? clock)
    }

    func activeTimelineOffset(at date: Date) -> TimeInterval {
        guard let context = currentContext else { return 0 }
        let clampedDate = pausedClampedReferenceDate(for: context, date)
        return activeElapsed(in: context, from: context.session.startedAt, to: clampedDate)
    }

    private var currentContext: SessionContext? {
        guard let selectedSessionID else { return nil }
        return sessionContexts[selectedSessionID]
    }

    private func commitSelectedContextUpdate(
        _ context: SessionContext,
        for sessionID: UUID,
        at date: Date,
        persist: Bool = true
    ) {
        sessionContexts[sessionID] = context
        commitSelectionUpdate(at: date, persist: persist)
    }

    private func commitSelectionUpdate(at date: Date, persist: Bool = true) {
        clock = date
        applySelectedContext()
        if persist {
            persistState()
        }
    }

    private func applySelectedContext() {
        refreshSessionList()

        guard let selectedSessionID, let context = sessionContexts[selectedSessionID] else {
            state = .idle
            session = nil
            laps = []
            selectedLapID = nil
            syncTimerForSelectedState()
            return
        }

        state = context.state
        session = context.session
        laps = context.laps
        selectedLapID = context.selectedLapID
        syncTimerForSelectedState()
    }

    private func refreshSessionList() {
        sessions = sessionOrder.compactMap { sessionContexts[$0]?.session }
    }

    private func makeRunningSessionContext(at date: Date) -> SessionContext {
        var context = makeIdleSessionContext(at: date)
        activateIdleSession(&context, at: date)
        return context
    }

    private func makeIdleSessionContext(at date: Date) -> SessionContext {
        let sessionID = UUID()
        let sessionTitle = defaultSessionTitle(at: date)
        nextSessionNumber += 1

        let session = WorkSession(
            id: sessionID,
            title: sessionTitle,
            startedAt: date,
            endedAt: nil
        )

        return SessionContext(
            session: session,
            laps: [],
            selectedLapID: nil,
            state: .idle,
            pauseStartedAt: nil,
            lastLapActivationAt: nil,
            completedPauseIntervals: []
        )
    }

    private func activateIdleSession(_ context: inout SessionContext, at date: Date) {
        let initialLap = WorkLap(
            id: UUID(),
            sessionId: context.session.id,
            index: 1,
            startedAt: date,
            endedAt: nil,
            accumulatedDuration: 0,
            label: defaultLapLabel(for: 1)
        )

        context.session.startedAt = date
        context.session.endedAt = nil
        context.laps = [initialLap]
        context.selectedLapID = initialLap.id
        context.state = .running
        context.pauseStartedAt = nil
        context.lastLapActivationAt = date
        context.completedPauseIntervals = []
    }

    private func stopRunningSessions(except keepSessionID: UUID?, at date: Date) {
        for id in sessionOrder {
            guard id != keepSessionID, var context = sessionContexts[id], context.state == .running else { continue }
            accumulateActiveDuration(in: &context, until: date)
            context.state = .stopped
            context.pauseStartedAt = date
            context.lastLapActivationAt = nil
            sessionContexts[id] = context
        }
    }

    private func resume(context: inout SessionContext, at date: Date) {
        guard context.state == .paused || context.state == .stopped else { return }
        let pausedAt = context.pauseStartedAt ?? date
        let resumedAt = max(date, pausedAt)
        context.completedPauseIntervals.append(DateInterval(start: pausedAt, end: resumedAt))
        context.pauseStartedAt = nil
        context.state = .running
        context.lastLapActivationAt = resumedAt
    }

    private func defaultLapLabel(for index: Int) -> String {
        "作業\(index)"
    }

    private func defaultSessionTitle(at date: Date) -> String {
        let baseTitle = sessionDateTitlePrefix(for: date)
        let sameDateTitles = sessionOrder
            .compactMap { sessionContexts[$0]?.session.title }
            .filter { isSameDateSessionTitle($0, baseTitle: baseTitle) }

        guard !sameDateTitles.isEmpty else {
            return baseTitle
        }

        var usedSuffixIndexes: Set<Int> = []
        for title in sameDateTitles {
            guard title != baseTitle else { continue }
            let suffix = String(title.dropFirst(baseTitle.count + 1))
            if let index = sessionTitleSuffixIndex(from: suffix) {
                usedSuffixIndexes.insert(index)
            }
        }

        var nextSuffixIndex = 1
        while usedSuffixIndexes.contains(nextSuffixIndex) {
            nextSuffixIndex += 1
        }

        return "\(baseTitle)-\(sessionTitleSuffix(for: nextSuffixIndex))"
    }

    private func sessionDateTitlePrefix(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return "\(year)/\(month)/\(day)"
    }

    private func isSameDateSessionTitle(_ title: String, baseTitle: String) -> Bool {
        if title == baseTitle {
            return true
        }

        guard title.hasPrefix(baseTitle + "-") else {
            return false
        }

        let suffix = String(title.dropFirst(baseTitle.count + 1))
        return sessionTitleSuffixIndex(from: suffix) != nil
    }

    private func sessionTitleSuffix(for index: Int) -> String {
        guard index > 0 else { return "A" }

        var value = index
        var suffixScalars: [UnicodeScalar] = []
        while value > 0 {
            let zeroBased = (value - 1) % 26
            suffixScalars.append(UnicodeScalar(65 + zeroBased)!)
            value = (value - 1) / 26
        }

        return String(String.UnicodeScalarView(suffixScalars.reversed()))
    }

    private func sessionTitleSuffixIndex(from suffix: String) -> Int? {
        guard !suffix.isEmpty else { return nil }

        var result = 0
        for scalar in suffix.uppercased().unicodeScalars {
            guard scalar.value >= 65 && scalar.value <= 90 else {
                return nil
            }
            result = (result * 26) + Int(scalar.value - 64)
        }

        return result > 0 ? result : nil
    }

    private func accumulateActiveDuration(in context: inout SessionContext, until date: Date) {
        guard context.state == .running else { return }
        guard let selectedLapID = context.selectedLapID, let lastLapActivationAt = context.lastLapActivationAt else { return }
        guard let lapIndex = context.laps.firstIndex(where: { $0.id == selectedLapID }) else { return }
        guard date > lastLapActivationAt else { return }

        context.laps[lapIndex].accumulatedDuration += date.timeIntervalSince(lastLapActivationAt)
        context.lastLapActivationAt = date
    }

    private func elapsedSession(in context: SessionContext, at referenceDate: Date) -> TimeInterval {
        if context.laps.isEmpty {
            return 0
        }

        let endDate = resolvedEndDate(for: context, referenceDate: referenceDate)
        return activeElapsed(in: context, from: context.session.startedAt, to: endDate)
    }

    private func elapsedLap(_ lap: WorkLap, in context: SessionContext, at referenceDate: Date) -> TimeInterval {
        var elapsed = max(0, lap.accumulatedDuration)
        guard context.state == .running, context.selectedLapID == lap.id, let lastLapActivationAt = context.lastLapActivationAt else {
            return elapsed
        }

        elapsed += max(0, referenceDate.timeIntervalSince(lastLapActivationAt))
        return max(0, elapsed)
    }

    private func startClock() {
        let interval = isDisplayActive ? foregroundClockUpdateInterval : backgroundClockUpdateInterval
        stopClock()
        timerCancellable = Timer
            .publish(every: interval, tolerance: interval * 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                self?.clock = now
            }
    }

    private func stopClock() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func syncTimerForSelectedState() {
        guard autoTick else { return }

        if state == .running {
            startClock()
        } else {
            stopClock()
        }
    }

    private func resolvedEndDate(for context: SessionContext, referenceDate: Date) -> Date {
        if let endedAt = context.session.endedAt {
            return endedAt
        }

        return pausedClampedReferenceDate(for: context, referenceDate)
    }

    private func pausedClampedReferenceDate(for context: SessionContext, _ date: Date) -> Date {
        guard (context.state == .paused || context.state == .stopped), let pauseStartedAt = context.pauseStartedAt else {
            return date
        }
        return min(date, pauseStartedAt)
    }

    private func activeElapsed(in context: SessionContext, from start: Date, to end: Date) -> TimeInterval {
        guard end > start else { return 0 }

        let rawDuration = end.timeIntervalSince(start)
        let pausedDuration = context.completedPauseIntervals.reduce(0) { partial, interval in
            partial + overlapDuration(start: start, end: end, interval: interval)
        }

        return max(0, rawDuration - pausedDuration)
    }

    private func overlapDuration(start: Date, end: Date, interval: DateInterval) -> TimeInterval {
        let overlapStart = max(start, interval.start)
        let overlapEnd = min(end, interval.end)
        return max(0, overlapEnd.timeIntervalSince(overlapStart))
    }

    private func restorePersistedState() {
        guard let sessionStore else { return }
        guard let restoredSnapshot = try? sessionStore.loadSnapshot() else { return }
        let restored = normalizedSnapshotForRestore(
            restoredSnapshot,
            restoreDate: restoreReferenceDate ?? Date()
        )
        var restoredContexts: [UUID: SessionContext] = [:]
        var restoredContextOrder: [UUID] = []
        var restoredOrder: [UUID] = []
        var seenOrderedSessionIDs: Set<UUID> = []

        for persistedContext in restored.contexts {
            let context = sessionContext(from: persistedContext)
            let id = context.session.id
            guard restoredContexts[id] == nil else { continue }
            restoredContexts[id] = context
            restoredContextOrder.append(id)
        }

        for sessionID in restored.sessionOrder where restoredContexts[sessionID] != nil {
            guard seenOrderedSessionIDs.insert(sessionID).inserted else { continue }
            restoredOrder.append(sessionID)
        }

        for sessionID in restoredContextOrder where seenOrderedSessionIDs.insert(sessionID).inserted {
            restoredOrder.append(sessionID)
        }

        sessionContexts = restoredContexts
        sessionOrder = restoredOrder
        nextSessionNumber = max(1, restored.nextSessionNumber)

        if let selected = restored.selectedSessionID, sessionContexts[selected] != nil {
            selectedSessionID = selected
        } else {
            selectedSessionID = sessionOrder.first
        }
    }

    private func persistState(savedAt: Date? = nil) {
        guard let sessionStore else { return }

        let timestamp = savedAt ?? clock
        let payload = StopwatchStorageSnapshot(
            savedAt: timestamp,
            contexts: sessionOrder.compactMap { sessionContexts[$0] }.map { persistedContext(from: $0) },
            sessionOrder: sessionOrder,
            selectedSessionID: selectedSessionID,
            nextSessionNumber: nextSessionNumber
        )

        do {
            try sessionStore.saveSnapshot(payload)
        } catch {
            // Keep runtime behavior unchanged even if persistence fails.
        }
    }

    private func removePersistedState() {
        guard let sessionStore else { return }
        try? sessionStore.saveSnapshot(nil)
    }

    private func persistedContext(from context: SessionContext) -> PersistedSessionContext {
        PersistedSessionContext(
            session: context.session,
            laps: context.laps,
            selectedLapID: context.selectedLapID,
            state: context.state,
            pauseStartedAt: context.pauseStartedAt,
            lastLapActivationAt: context.lastLapActivationAt,
            completedPauseIntervals: context.completedPauseIntervals
        )
    }

    private func sessionContext(from context: PersistedSessionContext) -> SessionContext {
        let selectedLapID = normalizedSelectedLapID(context.selectedLapID, in: context.laps)
        return SessionContext(
            session: context.session,
            laps: context.laps,
            selectedLapID: selectedLapID,
            state: context.state,
            pauseStartedAt: context.pauseStartedAt,
            lastLapActivationAt: context.lastLapActivationAt,
            completedPauseIntervals: context.completedPauseIntervals
        )
    }

    private func normalizedSelectedLapID(_ selectedLapID: UUID?, in laps: [WorkLap]) -> UUID? {
        guard !laps.isEmpty else { return nil }

        if let selectedLapID, laps.contains(where: { $0.id == selectedLapID }) {
            return selectedLapID
        }

        if let unfinishedLapID = laps
            .filter({ $0.endedAt == nil })
            .max(by: { $0.index < $1.index })?
            .id
        {
            return unfinishedLapID
        }

        return laps.max(by: { $0.index < $1.index })?.id
    }

    private func normalizedSnapshotForRestore(
        _ snapshot: StopwatchStorageSnapshot,
        restoreDate: Date
    ) -> StopwatchStorageSnapshot {
        var normalizedContexts: [PersistedSessionContext] = []
        normalizedContexts.reserveCapacity(snapshot.contexts.count)

        for persistedContext in snapshot.contexts {
            var context = persistedContext
            guard context.state == .running else {
                normalizedContexts.append(context)
                continue
            }

            // If the app terminated without a normal stop event, treat launch time as stop time (MVP rule).
            let resolvedStopDate = max(snapshot.savedAt, restoreDate)

            if
                let selectedLapID = context.selectedLapID,
                let lastLapActivationAt = context.lastLapActivationAt,
                resolvedStopDate > lastLapActivationAt,
                let lapIndex = context.laps.firstIndex(where: { $0.id == selectedLapID })
            {
                context.laps[lapIndex].accumulatedDuration += resolvedStopDate.timeIntervalSince(lastLapActivationAt)
            }

            context.state = .stopped
            context.pauseStartedAt = resolvedStopDate
            context.lastLapActivationAt = nil
            normalizedContexts.append(context)
        }

        return StopwatchStorageSnapshot(
            schemaVersion: snapshot.schemaVersion,
            savedAt: snapshot.savedAt,
            contexts: normalizedContexts,
            sessionOrder: snapshot.sessionOrder,
            selectedSessionID: snapshot.selectedSessionID,
            nextSessionNumber: snapshot.nextSessionNumber
        )
    }
}
