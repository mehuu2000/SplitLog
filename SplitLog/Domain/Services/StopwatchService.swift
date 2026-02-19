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
    private var pauseStartedAt: Date?
    private var lastLapActivationAt: Date?
    private var completedPauseIntervals: [DateInterval] = []

    init(autoTick: Bool = true) {
        self.autoTick = autoTick
    }

    var currentLap: WorkLap? {
        guard let selectedLapID else { return nil }
        return laps.first(where: { $0.id == selectedLapID })
    }

    var completedLaps: [WorkLap] {
        laps.filter { $0.id != selectedLapID }
    }

    func startSession(at date: Date = Date()) {
        switch state {
        case .running:
            return
        case .paused, .stopped:
            resumeSession(at: date)
            return
        case .idle, .finished:
            break
        }

        let sessionId = UUID()
        let initialLap = WorkLap(
            id: UUID(),
            sessionId: sessionId,
            index: 1,
            startedAt: date,
            endedAt: nil,
            accumulatedDuration: 0,
            label: defaultLapLabel(for: 1)
        )

        session = WorkSession(id: sessionId, startedAt: date, endedAt: nil)
        laps = [initialLap]
        selectedLapID = initialLap.id
        state = .running
        pauseStartedAt = nil
        lastLapActivationAt = date
        completedPauseIntervals = []
        clock = date

        if autoTick {
            startClock()
        }
    }

    func finishLap(at date: Date = Date()) {
        guard state == .running, let activeSession = session else { return }
        guard let selectedLapID, let currentIndex = laps.firstIndex(where: { $0.id == selectedLapID }) else { return }

        accumulateActiveDuration(until: date)
        if laps[currentIndex].endedAt == nil {
            laps[currentIndex].endedAt = date
        }

        let nextIndex = (laps.map(\.index).max() ?? 0) + 1
        let nextLap = WorkLap(
            id: UUID(),
            sessionId: activeSession.id,
            index: nextIndex,
            startedAt: date,
            endedAt: nil,
            accumulatedDuration: 0,
            label: defaultLapLabel(for: nextIndex)
        )
        laps.append(nextLap)
        self.selectedLapID = nextLap.id
        lastLapActivationAt = date
        clock = date
    }

    func selectLap(lapID: UUID, at date: Date = Date()) {
        guard laps.contains(where: { $0.id == lapID }) else { return }
        guard selectedLapID != lapID else { return }

        if state == .running {
            accumulateActiveDuration(until: date)
            selectedLapID = lapID
            lastLapActivationAt = date
            clock = date
            return
        }

        if state == .paused || state == .stopped {
            selectedLapID = lapID
            clock = date
        }
    }

    func pauseSession(at date: Date = Date()) {
        guard state == .running else { return }
        accumulateActiveDuration(until: date)
        state = .paused
        pauseStartedAt = date
        lastLapActivationAt = nil
        clock = date
        stopClock()
    }

    func resumeSession(at date: Date = Date()) {
        guard (state == .paused || state == .stopped), let pausedAt = pauseStartedAt else { return }
        let resumedAt = max(date, pausedAt)
        completedPauseIntervals.append(DateInterval(start: pausedAt, end: resumedAt))

        pauseStartedAt = nil
        state = .running
        lastLapActivationAt = resumedAt
        clock = resumedAt

        if autoTick {
            startClock()
        }
    }

    func finishSession(at date: Date = Date()) {
        guard (state == .running || state == .paused), session != nil else { return }

        let stoppedAt: Date
        if state == .paused, let pausedAt = pauseStartedAt {
            stoppedAt = pausedAt
        } else {
            stoppedAt = date
            accumulateActiveDuration(until: stoppedAt)
            pauseStartedAt = stoppedAt
        }

        state = .stopped
        lastLapActivationAt = nil
        clock = stoppedAt
        stopClock()
    }

    func resetToIdle() {
        state = .idle
        session = nil
        laps = []
        selectedLapID = nil
        pauseStartedAt = nil
        lastLapActivationAt = nil
        completedPauseIntervals = []
        clock = Date()
        stopClock()
    }

    func updateLapLabel(lapID: UUID, label: String) {
        guard let index = laps.firstIndex(where: { $0.id == lapID }) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            laps[index].label = defaultLapLabel(for: laps[index].index)
            return
        }

        laps[index].label = trimmed
    }

    func setDisplayActive(_ isActive: Bool) {
        guard isDisplayActive != isActive else { return }
        isDisplayActive = isActive

        guard autoTick, state == .running else { return }
        startClock()
    }

    func elapsedSession(at referenceDate: Date? = nil) -> TimeInterval {
        guard let session else { return 0 }
        let endDate = resolvedEndDate(endedAt: session.endedAt, referenceDate: referenceDate)
        return activeElapsed(from: session.startedAt, to: endDate)
    }

    func elapsedCurrentLap(at referenceDate: Date? = nil) -> TimeInterval {
        guard let currentLap else { return 0 }
        return elapsedLap(currentLap, at: referenceDate)
    }

    func elapsedLap(_ lap: WorkLap, at referenceDate: Date? = nil) -> TimeInterval {
        var elapsed = max(0, lap.accumulatedDuration)
        guard state == .running, selectedLapID == lap.id, let lastLapActivationAt else {
            return elapsed
        }

        let reference = referenceDate ?? clock
        elapsed += max(0, reference.timeIntervalSince(lastLapActivationAt))
        return max(0, elapsed)
    }

    func activeTimelineOffset(at date: Date) -> TimeInterval {
        guard let session else { return 0 }
        let clampedDate = pausedClampedReferenceDate(date)
        return activeElapsed(from: session.startedAt, to: clampedDate)
    }

    private func defaultLapLabel(for index: Int) -> String {
        "作業\(index)"
    }

    private func accumulateActiveDuration(until date: Date) {
        guard state == .running else { return }
        guard let selectedLapID, let lastLapActivationAt else { return }
        guard let lapIndex = laps.firstIndex(where: { $0.id == selectedLapID }) else { return }
        guard date > lastLapActivationAt else { return }

        laps[lapIndex].accumulatedDuration += date.timeIntervalSince(lastLapActivationAt)
        self.lastLapActivationAt = date
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

    private func resolvedEndDate(endedAt: Date?, referenceDate: Date?) -> Date {
        if let endedAt {
            return endedAt
        }

        return pausedClampedReferenceDate(referenceDate ?? clock)
    }

    private func pausedClampedReferenceDate(_ date: Date) -> Date {
        guard (state == .paused || state == .stopped), let pauseStartedAt else { return date }
        return min(date, pauseStartedAt)
    }

    private func activeElapsed(from start: Date, to end: Date) -> TimeInterval {
        guard end > start else { return 0 }

        let rawDuration = end.timeIntervalSince(start)
        let pausedDuration = completedPauseIntervals.reduce(0) { partial, interval in
            partial + overlapDuration(start: start, end: end, interval: interval)
        }

        return max(0, rawDuration - pausedDuration)
    }

    private func overlapDuration(start: Date, end: Date, interval: DateInterval) -> TimeInterval {
        let overlapStart = max(start, interval.start)
        let overlapEnd = min(end, interval.end)
        return max(0, overlapEnd.timeIntervalSince(overlapStart))
    }
}
