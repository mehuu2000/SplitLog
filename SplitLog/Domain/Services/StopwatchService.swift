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
    private let persistenceURL: URL?

    private struct SessionContext: Codable, Sendable {
        var session: WorkSession
        var laps: [WorkLap]
        var selectedLapID: UUID?
        var state: SessionState
        var pauseStartedAt: Date?
        var lastLapActivationAt: Date?
        var completedPauseIntervals: [DateInterval]
    }

    private struct PersistedState: Codable {
        var contexts: [SessionContext]
        var selectedSessionID: UUID?
        var nextSessionNumber: Int
    }

    init(autoTick: Bool = true, persistenceEnabled: Bool = true) {
        self.autoTick = autoTick
        self.persistenceURL = persistenceEnabled ? Self.makePersistenceURL() : nil
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
        sessionOrder.append(context.session.id)
        selectedSessionID = context.session.id
        clock = date

        applySelectedContext()
        persistState()
    }

    func selectSession(sessionID: UUID, at date: Date = Date()) {
        guard sessionContexts[sessionID] != nil else { return }
        guard selectedSessionID != sessionID else { return }

        // Session switch must freeze elapsed time of the previously running session.
        stopRunningSessions(except: sessionID, at: date)

        selectedSessionID = sessionID
        clock = date
        applySelectedContext()
        persistState()
    }

    func sessionState(for sessionID: UUID) -> SessionState {
        sessionContexts[sessionID]?.state ?? .idle
    }

    func startSession(at date: Date = Date()) {
        guard let selectedSessionID, var context = sessionContexts[selectedSessionID] else {
            let newContext = makeRunningSessionContext(at: date)
            sessionContexts[newContext.session.id] = newContext
            sessionOrder.append(newContext.session.id)
            selectedSessionID = newContext.session.id
            clock = date
            applySelectedContext()
            persistState()
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

        clock = date
        applySelectedContext()
        persistState()
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

        sessionContexts[selectedSessionID] = context
        clock = date
        applySelectedContext()
        persistState()
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

        sessionContexts[selectedSessionID] = context
        clock = date
        applySelectedContext()
        persistState()
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

        sessionContexts[selectedSessionID] = context
        clock = date
        applySelectedContext()
        persistState()
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

        sessionContexts[selectedSessionID] = context
        clock = date
        applySelectedContext()
        persistState()
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

        sessionContexts[selectedSessionID] = context
        clock = stoppedAt
        applySelectedContext()
        persistState()
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

    func setDisplayActive(_ isActive: Bool) {
        guard isDisplayActive != isActive else { return }
        isDisplayActive = isActive
        syncTimerForSelectedState()
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
        let sessionTitle = defaultSessionTitle(for: nextSessionNumber)
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

    private func defaultSessionTitle(for number: Int) -> String {
        "セッション\(number)"
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
        guard let persistenceURL else { return }
        guard let data = try? Data(contentsOf: persistenceURL) else { return }
        guard let restored = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }

        var restoredContexts: [UUID: SessionContext] = [:]
        var restoredOrder: [UUID] = []

        for context in restored.contexts {
            let id = context.session.id
            guard restoredContexts[id] == nil else { continue }
            restoredContexts[id] = context
            restoredOrder.append(id)
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

    private func persistState() {
        guard let persistenceURL else { return }

        let payload = PersistedState(
            contexts: sessionOrder.compactMap { sessionContexts[$0] },
            selectedSessionID: selectedSessionID,
            nextSessionNumber: nextSessionNumber
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            // Keep runtime behavior unchanged even if persistence fails.
        }
    }

    private func removePersistedState() {
        guard let persistenceURL else { return }
        try? FileManager.default.removeItem(at: persistenceURL)
    }

    private static func makePersistenceURL() -> URL? {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let directory = appSupportURL.appendingPathComponent("SplitLog", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        return directory.appendingPathComponent("sessions.json")
    }
}
