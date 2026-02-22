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
    private enum PersistenceWriteMode {
        case queued
        case immediate
    }

    struct PersistenceErrorEvent: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    @Published private(set) var sessions: [WorkSession] = []
    @Published private(set) var selectedSessionID: UUID?

    @Published private(set) var state: SessionState = .idle
    @Published private(set) var session: WorkSession?
    @Published private(set) var laps: [WorkLap] = []
    @Published private(set) var selectedLapID: UUID?
    @Published private(set) var activeLapIDs: Set<UUID> = []
    @Published private(set) var clock: Date = Date()
    @Published private(set) var persistenceErrorEvent: PersistenceErrorEvent?

    private var timerCancellable: AnyCancellable?
    private let autoTick: Bool
    private let foregroundClockUpdateIntervalWithRing: TimeInterval = 1.0 / 15.0
    private let foregroundClockUpdateIntervalWithoutRing: TimeInterval = 1.0 / 5.0
    private let backgroundClockUpdateInterval: TimeInterval = 1.0
    private var isDisplayActive: Bool = false
    private var isTimelineRingVisible: Bool = true

    private var sessionContexts: [UUID: SessionContext] = [:]
    private var sessionOrder: [UUID] = []
    private var nextSessionNumber: Int = 1
    private var splitAccumulationMode: SplitAccumulationMode = .radio
    private let sessionStore: SessionStore?
    private var persistenceWriter: CoalescingSessionStoreWriter?
    private let restoreReferenceDate: Date?
    private(set) var lastPersistenceSucceeded: Bool = true

    private struct SessionContext: Codable, Sendable {
        var session: WorkSession
        var laps: [WorkLap]
        var selectedLapID: UUID?
        var activeLapIDs: Set<UUID>
        var state: SessionState
        var pauseStartedAt: Date?
        var lastDistributedWholeSeconds: Int
        var distributionCursor: Int
        var totalPausedDuration: TimeInterval
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
        if let sessionStore = self.sessionStore {
            self.persistenceWriter = CoalescingSessionStoreWriter(sessionStore: sessionStore) { [weak self] operation in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.lastPersistenceSucceeded = false
                    switch operation {
                    case .save:
                        self.reportPersistenceError("セッションデータの保存に失敗しました。")
                    case .clear:
                        self.reportPersistenceError("セッションデータの削除に失敗しました。")
                    }
                }
            }
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

    func setSplitAccumulationMode(_ mode: SplitAccumulationMode, at date: Date = Date()) {
        guard splitAccumulationMode != mode else { return }

        if
            let selectedSessionID,
            var context = sessionContexts[selectedSessionID],
            context.state == .running
        {
            distributePendingWholeSeconds(in: &context, until: date, mode: splitAccumulationMode)
            sessionContexts[selectedSessionID] = context
        }

        let previousMode = splitAccumulationMode
        splitAccumulationMode = mode

        if let selectedSessionID, var context = sessionContexts[selectedSessionID] {
            let previousOrder = distributionOrder(in: context, mode: previousMode)
            context.activeLapIDs = normalizedActiveLapIDs(
                context.activeLapIDs,
                in: context.laps,
                selectedLapID: context.selectedLapID,
                mode: mode
            )
            let newOrder = distributionOrder(in: context, mode: mode)
            context.distributionCursor = rebasedDistributionCursor(
                previousOrder: previousOrder,
                newOrder: newOrder,
                previousCursor: context.distributionCursor
            )
            if context.state == .running {
                context.lastDistributedWholeSeconds = wholeElapsedSeconds(in: context, at: date)
            }
            commitSelectedContextUpdate(context, for: selectedSessionID, at: date)
        } else {
            applySelectedContext()
        }
    }

    func toggleLapActive(lapID: UUID, at date: Date = Date()) {
        guard splitAccumulationMode == .checkbox else { return }
        guard
            let selectedSessionID,
            var context = sessionContexts[selectedSessionID],
            context.laps.contains(where: { $0.id == lapID })
        else {
            return
        }

        if context.state == .running {
            distributePendingWholeSeconds(in: &context, until: date)
        }

        let previousOrder = distributionOrder(in: context, mode: .checkbox)
        var activeLapIDs = normalizedActiveLapIDs(
            context.activeLapIDs,
            in: context.laps,
            selectedLapID: context.selectedLapID,
            mode: .checkbox
        )

        if activeLapIDs.contains(lapID) {
            guard activeLapIDs.count > 1 else {
                if context.state == .running {
                    context.lastDistributedWholeSeconds = wholeElapsedSeconds(in: context, at: date)
                }
                commitSelectedContextUpdate(context, for: selectedSessionID, at: date)
                return
            }
            activeLapIDs.remove(lapID)
        } else {
            activeLapIDs.insert(lapID)
        }

        context.activeLapIDs = activeLapIDs
        let newOrder = distributionOrder(in: context, mode: .checkbox)
        context.distributionCursor = rebasedDistributionCursor(
            previousOrder: previousOrder,
            newOrder: newOrder,
            previousCursor: context.distributionCursor
        )
        if context.state == .running {
            context.lastDistributedWholeSeconds = wholeElapsedSeconds(in: context, at: date)
        }
        commitSelectedContextUpdate(context, for: selectedSessionID, at: date)
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

        distributePendingWholeSeconds(in: &context, until: date)
        let previousOrder = distributionOrder(in: context)
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
        switch splitAccumulationMode {
        case .radio:
            context.activeLapIDs = [nextLap.id]
            context.distributionCursor = 0
        case .checkbox:
            // Keep every currently checked split as-is, then include the newly created split.
            // This prevents implicit unchecking when creating a new split in checkbox mode.
            let lapIDs = Set(context.laps.map(\.id))
            var activeLapIDs = context.activeLapIDs.intersection(lapIDs)
            if activeLapIDs.isEmpty {
                activeLapIDs = [nextLap.id]
            }
            activeLapIDs.insert(nextLap.id)
            context.activeLapIDs = activeLapIDs
            let newOrder = distributionOrder(in: context, mode: .checkbox)
            context.distributionCursor = rebasedDistributionCursor(
                previousOrder: previousOrder,
                newOrder: newOrder,
                previousCursor: context.distributionCursor
            )
        }
        context.lastDistributedWholeSeconds = wholeElapsedSeconds(in: context, at: date)

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
            distributePendingWholeSeconds(in: &context, until: date)
            context.selectedLapID = lapID
            if splitAccumulationMode == .radio {
                context.activeLapIDs = [lapID]
                context.distributionCursor = 0
            }
            context.lastDistributedWholeSeconds = wholeElapsedSeconds(in: context, at: date)
        } else if context.state == .paused || context.state == .stopped {
            context.selectedLapID = lapID
            if splitAccumulationMode == .radio {
                context.activeLapIDs = [lapID]
                context.distributionCursor = 0
            } else {
                let previousOrder = distributionOrder(in: context, mode: .checkbox)
                context.activeLapIDs = normalizedActiveLapIDs(
                    context.activeLapIDs,
                    in: context.laps,
                    selectedLapID: context.selectedLapID,
                    mode: .checkbox
                )
                let newOrder = distributionOrder(in: context, mode: .checkbox)
                context.distributionCursor = rebasedDistributionCursor(
                    previousOrder: previousOrder,
                    newOrder: newOrder,
                    previousCursor: context.distributionCursor
                )
            }
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

        distributePendingWholeSeconds(in: &context, until: date)
        context.state = .paused
        context.pauseStartedAt = date

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
            distributePendingWholeSeconds(in: &context, until: stoppedAt)
            context.pauseStartedAt = stoppedAt
        }

        context.state = .stopped

        commitSelectedContextUpdate(context, for: selectedSessionID, at: stoppedAt)
    }

    @discardableResult
    func resetToIdle() -> Bool {
        sessionContexts = [:]
        sessionOrder = []
        sessions = []
        selectedSessionID = nil
        nextSessionNumber = 1

        state = .idle
        session = nil
        laps = []
        selectedLapID = nil
        activeLapIDs = []
        clock = Date()
        stopClock()

        return removePersistedState(mode: .immediate)
    }

    func resetSelectedSession(at date: Date = Date()) {
        guard let selectedSessionID, var context = sessionContexts[selectedSessionID] else { return }

        context.state = .idle
        context.session.startedAt = date
        context.session.endedAt = nil
        context.laps = []
        context.selectedLapID = nil
        context.activeLapIDs = []
        context.pauseStartedAt = nil
        context.lastDistributedWholeSeconds = 0
        context.distributionCursor = 0
        context.totalPausedDuration = 0

        commitSelectedContextUpdate(context, for: selectedSessionID, at: date)
    }

    @discardableResult
    func clearAllLapsAndMemos(
        at date: Date = Date(),
        persistImmediately: Bool = false
    ) -> Bool {
        guard !sessionOrder.isEmpty else { return true }

        for sessionID in sessionOrder {
            guard var context = sessionContexts[sessionID] else { continue }
            context.state = .idle
            context.session.startedAt = date
            context.session.endedAt = nil
            context.laps = []
            context.selectedLapID = nil
            context.activeLapIDs = []
            context.pauseStartedAt = nil
            context.lastDistributedWholeSeconds = 0
            context.distributionCursor = 0
            context.totalPausedDuration = 0
            sessionContexts[sessionID] = context
        }

        if let selectedSessionID, sessionContexts[selectedSessionID] == nil {
            self.selectedSessionID = sessionOrder.first
        } else if selectedSessionID == nil {
            self.selectedSessionID = sessionOrder.first
        }

        commitSelectionUpdate(at: date, persist: false)
        if persistImmediately {
            return persistState(mode: .immediate)
        }
        persistState()
        return lastPersistenceSucceeded
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
            removePersistedState(mode: .immediate)
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
        setDisplayActive(isActive, showTimelineRing: isTimelineRingVisible)
    }

    func setDisplayActive(_ isActive: Bool, showTimelineRing: Bool) {
        let activityDidChange = isDisplayActive != isActive
        let ringVisibilityDidChange = isTimelineRingVisible != showTimelineRing
        guard activityDidChange || ringVisibilityDidChange else { return }
        isDisplayActive = isActive
        isTimelineRingVisible = showTimelineRing
        syncTimerForSelectedState()
    }

    func prepareForTermination(at date: Date = Date()) {
        guard !sessionContexts.isEmpty else { return }

        for sessionID in sessionOrder {
            guard var context = sessionContexts[sessionID], context.state == .running else { continue }
            distributePendingWholeSeconds(in: &context, until: date)
            context.state = .stopped
            context.pauseStartedAt = date
            sessionContexts[sessionID] = context
        }

        clock = date
        applySelectedContext()
        persistState(savedAt: date, mode: .immediate)
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

    func consumePersistenceErrorEvent(id: UUID) {
        guard persistenceErrorEvent?.id == id else { return }
        persistenceErrorEvent = nil
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
            activeLapIDs = []
            syncTimerForSelectedState()
            return
        }

        state = context.state
        session = context.session
        laps = context.laps
        selectedLapID = context.selectedLapID
        activeLapIDs = normalizedActiveLapIDs(
            context.activeLapIDs,
            in: context.laps,
            selectedLapID: context.selectedLapID,
            mode: splitAccumulationMode
        )
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
            activeLapIDs: [],
            state: .idle,
            pauseStartedAt: nil,
            lastDistributedWholeSeconds: 0,
            distributionCursor: 0,
            totalPausedDuration: 0
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
        context.activeLapIDs = [initialLap.id]
        context.state = .running
        context.pauseStartedAt = nil
        context.lastDistributedWholeSeconds = 0
        context.distributionCursor = 0
        context.totalPausedDuration = 0
    }

    private func stopRunningSessions(except keepSessionID: UUID?, at date: Date) {
        for id in sessionOrder {
            guard id != keepSessionID, var context = sessionContexts[id], context.state == .running else { continue }
            distributePendingWholeSeconds(in: &context, until: date)
            context.state = .stopped
            context.pauseStartedAt = date
            sessionContexts[id] = context
        }
    }

    private func resume(context: inout SessionContext, at date: Date) {
        guard context.state == .paused || context.state == .stopped else { return }
        let pausedAt = context.pauseStartedAt ?? date
        let resumedAt = max(date, pausedAt)
        context.totalPausedDuration += max(0, resumedAt.timeIntervalSince(pausedAt))
        context.pauseStartedAt = nil
        context.state = .running
        context.lastDistributedWholeSeconds = wholeElapsedSeconds(in: context, at: resumedAt)
        let order = distributionOrder(in: context)
        context.distributionCursor = normalizedDistributionCursor(context.distributionCursor, count: order.count)
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

    private func elapsedSession(in context: SessionContext, at referenceDate: Date) -> TimeInterval {
        if context.laps.isEmpty {
            return 0
        }

        let endDate = resolvedEndDate(for: context, referenceDate: referenceDate)
        return activeElapsed(in: context, from: context.session.startedAt, to: endDate)
    }

    private func elapsedLap(_ lap: WorkLap, in context: SessionContext, at referenceDate: Date) -> TimeInterval {
        var elapsed = max(0, floor(lap.accumulatedDuration))
        guard context.state == .running else { return elapsed }

        let pending = pendingDistribution(in: context, at: referenceDate)
        guard pending.delta > 0 else { return elapsed }
        guard let targetIndex = pending.order.firstIndex(of: lap.id) else { return elapsed }

        elapsed += TimeInterval(pending.hitCount(for: targetIndex))
        return elapsed
    }

    private struct PendingDistribution {
        let order: [UUID]
        let cursor: Int
        let delta: Int
        let currentWhole: Int

        func hitCount(for targetIndex: Int) -> Int {
            guard delta > 0, !order.isEmpty else { return 0 }
            guard targetIndex >= 0, targetIndex < order.count else { return 0 }

            let count = order.count
            let fullCycles = delta / count
            let remainder = delta % count
            let offset = (targetIndex - cursor + count) % count
            return fullCycles + (offset < remainder ? 1 : 0)
        }

        var nextCursor: Int {
            guard !order.isEmpty else { return 0 }
            return (cursor + (delta % order.count)) % order.count
        }
    }

    private func pendingDistribution(
        in context: SessionContext,
        at date: Date,
        mode: SplitAccumulationMode? = nil
    ) -> PendingDistribution {
        let effectiveMode = mode ?? splitAccumulationMode
        let currentWhole = wholeElapsedSeconds(in: context, at: date)
        let delta = max(0, currentWhole - context.lastDistributedWholeSeconds)
        let order = distributionOrder(in: context, mode: effectiveMode)
        let cursor = normalizedDistributionCursor(context.distributionCursor, count: order.count)
        return PendingDistribution(order: order, cursor: cursor, delta: delta, currentWhole: currentWhole)
    }

    private func distributePendingWholeSeconds(
        in context: inout SessionContext,
        until date: Date,
        mode: SplitAccumulationMode? = nil
    ) {
        guard context.state == .running else { return }
        let pending = pendingDistribution(in: context, at: date, mode: mode)
        guard pending.delta > 0 else { return }
        guard !pending.order.isEmpty else {
            context.lastDistributedWholeSeconds = pending.currentWhole
            context.distributionCursor = 0
            return
        }

        var lapIndexByID: [UUID: Int] = [:]
        lapIndexByID.reserveCapacity(context.laps.count)
        for (index, lap) in context.laps.enumerated() {
            lapIndexByID[lap.id] = index
        }

        for (index, lapID) in pending.order.enumerated() {
            let increment = pending.hitCount(for: index)
            guard increment > 0 else { continue }
            guard let lapIndex = lapIndexByID[lapID] else { continue }
            let base = floor(max(0, context.laps[lapIndex].accumulatedDuration))
            context.laps[lapIndex].accumulatedDuration = base + TimeInterval(increment)
        }

        context.lastDistributedWholeSeconds = pending.currentWhole
        context.distributionCursor = pending.nextCursor
    }

    private func wholeElapsedSeconds(in context: SessionContext, at date: Date) -> Int {
        max(0, Int(floor(elapsedSession(in: context, at: date))))
    }

    private func distributionOrder(in context: SessionContext, mode: SplitAccumulationMode? = nil) -> [UUID] {
        let effectiveMode = mode ?? splitAccumulationMode
        switch effectiveMode {
        case .radio:
            guard
                let selectedLapID = context.selectedLapID,
                context.laps.contains(where: { $0.id == selectedLapID })
            else {
                return []
            }
            return [selectedLapID]
        case .checkbox:
            let normalized = normalizedActiveLapIDs(
                context.activeLapIDs,
                in: context.laps,
                selectedLapID: context.selectedLapID,
                mode: .checkbox
            )
            return context.laps.compactMap { lap in
                normalized.contains(lap.id) ? lap.id : nil
            }
        }
    }

    private func normalizedDistributionCursor(_ cursor: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((cursor % count) + count) % count
    }

    private func rebasedDistributionCursor(
        previousOrder: [UUID],
        newOrder: [UUID],
        previousCursor: Int
    ) -> Int {
        guard !newOrder.isEmpty else { return 0 }
        guard !previousOrder.isEmpty else { return 0 }

        let normalizedPreviousCursor = normalizedDistributionCursor(previousCursor, count: previousOrder.count)
        let nextTargetID = previousOrder[normalizedPreviousCursor]
        if let newIndex = newOrder.firstIndex(of: nextTargetID) {
            return newIndex
        }
        return normalizedDistributionCursor(previousCursor, count: newOrder.count)
    }

    private func startClock() {
        let interval: TimeInterval
        if isDisplayActive {
            interval = isTimelineRingVisible
                ? foregroundClockUpdateIntervalWithRing
                : foregroundClockUpdateIntervalWithoutRing
        } else {
            interval = backgroundClockUpdateInterval
        }
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
        let pausedDuration = max(0, context.totalPausedDuration)

        return max(0, rawDuration - pausedDuration)
    }

    private func restorePersistedState() {
        guard let sessionStore else { return }
        let restoredSnapshot: StopwatchStorageSnapshot?
        do {
            restoredSnapshot = try sessionStore.loadSnapshot()
        } catch {
            lastPersistenceSucceeded = false
            reportPersistenceError("セッションデータの読み込みに失敗しました。")
            return
        }
        guard let restoredSnapshot else { return }
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

    @discardableResult
    private func persistState(
        savedAt: Date? = nil,
        mode: PersistenceWriteMode = .queued
    ) -> Bool {
        guard let sessionStore else {
            lastPersistenceSucceeded = true
            return true
        }

        let timestamp = savedAt ?? clock
        let payload = StopwatchStorageSnapshot(
            savedAt: timestamp,
            contexts: sessionOrder.compactMap { sessionContexts[$0] }.map { persistedContext(from: $0) },
            sessionOrder: sessionOrder,
            selectedSessionID: selectedSessionID,
            nextSessionNumber: nextSessionNumber
        )

        switch mode {
        case .queued:
            persistenceWriter?.enqueueSave(payload)
            lastPersistenceSucceeded = true
            return true
        case .immediate:
            if let persistenceWriter {
                switch persistenceWriter.performImmediateSave(payload) {
                case .success:
                    lastPersistenceSucceeded = true
                    return true
                case .failure:
                    lastPersistenceSucceeded = false
                    reportPersistenceError("セッションデータの保存に失敗しました。")
                    return false
                }
            } else {
                do {
                    try sessionStore.saveSnapshot(payload)
                    lastPersistenceSucceeded = true
                    return true
                } catch {
                    lastPersistenceSucceeded = false
                    reportPersistenceError("セッションデータの保存に失敗しました。")
                    return false
                }
            }
        }
    }

    @discardableResult
    private func removePersistedState(mode: PersistenceWriteMode = .queued) -> Bool {
        guard let sessionStore else {
            lastPersistenceSucceeded = true
            return true
        }

        switch mode {
        case .queued:
            persistenceWriter?.enqueueClear()
            lastPersistenceSucceeded = true
            return true
        case .immediate:
            if let persistenceWriter {
                switch persistenceWriter.performImmediateClear() {
                case .success:
                    lastPersistenceSucceeded = true
                    return true
                case .failure:
                    lastPersistenceSucceeded = false
                    reportPersistenceError("セッションデータの削除に失敗しました。")
                    return false
                }
            } else {
                do {
                    try sessionStore.saveSnapshot(nil)
                    lastPersistenceSucceeded = true
                    return true
                } catch {
                    lastPersistenceSucceeded = false
                    reportPersistenceError("セッションデータの削除に失敗しました。")
                    return false
                }
            }
        }
    }

    private func reportPersistenceError(_ message: String) {
        persistenceErrorEvent = PersistenceErrorEvent(message: message)
    }

    private func persistedContext(from context: SessionContext) -> PersistedSessionContext {
        let normalizedLaps = context.laps.map { lap -> WorkLap in
            var normalizedLap = lap
            normalizedLap.accumulatedDuration = TimeInterval(max(0, Int(floor(lap.accumulatedDuration))))
            return normalizedLap
        }

        return PersistedSessionContext(
            session: context.session,
            laps: normalizedLaps,
            selectedLapID: context.selectedLapID,
            activeLapIDs: context.activeLapIDs,
            state: context.state,
            pauseStartedAt: context.pauseStartedAt,
            lastLapActivationAt: nil,
            lastDistributedWholeSeconds: max(0, context.lastDistributedWholeSeconds),
            distributionCursor: max(0, context.distributionCursor),
            totalPausedDuration: context.totalPausedDuration,
            completedPauseIntervals: []
        )
    }

    private func sessionContext(from context: PersistedSessionContext) -> SessionContext {
        let normalizedLaps = context.laps
            .map { lap -> WorkLap in
                var normalizedLap = lap
                normalizedLap.accumulatedDuration = TimeInterval(max(0, Int(floor(lap.accumulatedDuration))))
                return normalizedLap
            }
            .sorted(by: { $0.index < $1.index })
        let selectedLapID = normalizedSelectedLapID(context.selectedLapID, in: normalizedLaps)
        let activeLapIDs = normalizedActiveLapIDs(
            context.activeLapIDs,
            in: normalizedLaps,
            selectedLapID: selectedLapID,
            mode: .checkbox
        )
        let distributedFromLaps = normalizedLaps.reduce(0) { partial, lap in
            partial + max(0, Int(floor(lap.accumulatedDuration)))
        }
        let lastDistributedWholeSeconds = max(context.lastDistributedWholeSeconds, distributedFromLaps)
        let distributionOrderCount = distributionOrder(
            laps: normalizedLaps,
            selectedLapID: selectedLapID,
            activeLapIDs: activeLapIDs,
            mode: .checkbox
        ).count

        return SessionContext(
            session: context.session,
            laps: normalizedLaps,
            selectedLapID: selectedLapID,
            activeLapIDs: activeLapIDs,
            state: context.state,
            pauseStartedAt: context.pauseStartedAt,
            lastDistributedWholeSeconds: lastDistributedWholeSeconds,
            distributionCursor: normalizedDistributionCursor(context.distributionCursor, count: distributionOrderCount),
            totalPausedDuration: max(0, context.totalPausedDuration)
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

    private func normalizedActiveLapIDs(
        _ activeLapIDs: Set<UUID>,
        in laps: [WorkLap],
        selectedLapID: UUID?,
        mode: SplitAccumulationMode
    ) -> Set<UUID> {
        guard !laps.isEmpty else { return [] }

        switch mode {
        case .radio:
            guard
                let selectedLapID,
                laps.contains(where: { $0.id == selectedLapID })
            else {
                return []
            }
            return [selectedLapID]
        case .checkbox:
            let lapIDs = Set(laps.map(\.id))
            let filtered = activeLapIDs.intersection(lapIDs)
            if !filtered.isEmpty {
                return filtered
            }
            if let selectedLapID, lapIDs.contains(selectedLapID) {
                return [selectedLapID]
            }
            if let newestLapID = laps.max(by: { $0.index < $1.index })?.id {
                return [newestLapID]
            }
            return []
        }
    }

    private func normalizedSnapshotForRestore(
        _ snapshot: StopwatchStorageSnapshot,
        restoreDate: Date
    ) -> StopwatchStorageSnapshot {
        var normalizedContexts: [PersistedSessionContext] = []
        normalizedContexts.reserveCapacity(snapshot.contexts.count)

        for persisted in snapshot.contexts {
            guard persisted.state == .running else {
                normalizedContexts.append(persisted)
                continue
            }

            // If the app terminated without a normal stop event, treat launch time as stop time (MVP rule).
            let resolvedStopDate = max(snapshot.savedAt, restoreDate)
            var restoredContext = sessionContext(from: persisted)
            let restoreMode = inferredRestoreMode(from: restoredContext)
            distributePendingWholeSeconds(in: &restoredContext, until: resolvedStopDate, mode: restoreMode)
            restoredContext.state = .stopped
            restoredContext.pauseStartedAt = resolvedStopDate
            normalizedContexts.append(persistedContext(from: restoredContext))
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

    private func inferredRestoreMode(from context: SessionContext) -> SplitAccumulationMode {
        let activeCount = normalizedActiveLapIDs(
            context.activeLapIDs,
            in: context.laps,
            selectedLapID: context.selectedLapID,
            mode: .checkbox
        ).count
        return activeCount > 1 ? .checkbox : .radio
    }

    private func distributionOrder(
        laps: [WorkLap],
        selectedLapID: UUID?,
        activeLapIDs: Set<UUID>,
        mode: SplitAccumulationMode
    ) -> [UUID] {
        switch mode {
        case .radio:
            guard
                let selectedLapID,
                laps.contains(where: { $0.id == selectedLapID })
            else {
                return []
            }
            return [selectedLapID]
        case .checkbox:
            let normalized = normalizedActiveLapIDs(
                activeLapIDs,
                in: laps,
                selectedLapID: selectedLapID,
                mode: .checkbox
            )
            return laps.compactMap { lap in
                normalized.contains(lap.id) ? lap.id : nil
            }
        }
    }
}

private final class CoalescingSessionStoreWriter {
    enum WriteOperation: Sendable {
        case save
        case clear
    }

    private enum PendingWrite {
        case save(StopwatchStorageSnapshot)
        case clear
    }

    private let sessionStore: SessionStore
    private let debounceInterval: TimeInterval
    private let onFailure: @Sendable (WriteOperation) -> Void
    private let queue = DispatchQueue(label: "SplitLog.persistence.writer", qos: .utility)

    private var pendingWrite: PendingWrite?
    private var scheduledFlush: DispatchWorkItem?

    init(
        sessionStore: SessionStore,
        debounceInterval: TimeInterval = 0.2,
        onFailure: @escaping @Sendable (WriteOperation) -> Void = { _ in }
    ) {
        self.sessionStore = sessionStore
        self.debounceInterval = debounceInterval
        self.onFailure = onFailure
    }

    func enqueueSave(_ snapshot: StopwatchStorageSnapshot) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingWrite = .save(snapshot)
            self.scheduleFlushLocked()
        }
    }

    func enqueueClear() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingWrite = .clear
            self.scheduleFlushLocked()
        }
    }

    func performImmediateSave(_ snapshot: StopwatchStorageSnapshot) -> Result<Void, Error> {
        queue.sync {
            self.cancelPendingLocked()
            return self.performLocked(.save(snapshot), reportFailure: false)
        }
    }

    func performImmediateClear() -> Result<Void, Error> {
        queue.sync {
            self.cancelPendingLocked()
            return self.performLocked(.clear, reportFailure: false)
        }
    }

    private func scheduleFlushLocked() {
        scheduledFlush?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.flushPendingLocked()
        }

        scheduledFlush = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func flushPendingLocked() {
        guard let pendingWrite else {
            scheduledFlush = nil
            return
        }

        self.pendingWrite = nil
        scheduledFlush = nil
        _ = performLocked(pendingWrite, reportFailure: true)
    }

    private func cancelPendingLocked() {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        pendingWrite = nil
    }

    private func performLocked(_ write: PendingWrite, reportFailure: Bool) -> Result<Void, Error> {
        do {
            switch write {
            case let .save(snapshot):
                try sessionStore.saveSnapshot(snapshot)
            case .clear:
                try sessionStore.saveSnapshot(nil)
            }
            return .success(())
        } catch {
            if reportFailure {
                switch write {
                case .save:
                    onFailure(.save)
                case .clear:
                    onFailure(.clear)
                }
            }
            return .failure(error)
        }
    }
}
