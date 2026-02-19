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
    @Published private(set) var clock: Date = Date()

    private var timerCancellable: AnyCancellable?
    private let autoTick: Bool
    private let foregroundClockUpdateInterval: TimeInterval = 1.0 / 60.0
    private let backgroundClockUpdateInterval: TimeInterval = 1.0
    private var isDisplayActive: Bool = false
    private var pauseStartedAt: Date?
    private var completedPauseIntervals: [DateInterval] = []

    init(autoTick: Bool = true) {
        self.autoTick = autoTick
    }

    var currentLap: WorkLap? {
        laps.last(where: { $0.endedAt == nil })
    }

    var completedLaps: [WorkLap] {
        laps.filter { $0.endedAt != nil }
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
        session = WorkSession(id: sessionId, startedAt: date, endedAt: nil)
        laps = [
            WorkLap(
                id: UUID(),
                sessionId: sessionId,
                index: 1,
                startedAt: date,
                endedAt: nil,
                label: defaultLapLabel(for: 1)
            )
        ]
        state = .running
        pauseStartedAt = nil
        completedPauseIntervals = []
        clock = date

        if autoTick {
            startClock()
        }
    }

    func finishLap(at date: Date = Date()) {
        guard state == .running, let activeSession = session else { return }
        guard let currentIndex = laps.lastIndex(where: { $0.endedAt == nil }) else { return }

        laps[currentIndex].endedAt = date

        let nextIndex = laps[currentIndex].index + 1
        laps.append(
            WorkLap(
                id: UUID(),
                sessionId: activeSession.id,
                index: nextIndex,
                startedAt: date,
                endedAt: nil,
                label: defaultLapLabel(for: nextIndex)
            )
        )
        clock = date
    }

    func pauseSession(at date: Date = Date()) {
        guard state == .running else { return }
        state = .paused
        pauseStartedAt = date
        clock = date
        stopClock()
    }

    func resumeSession(at date: Date = Date()) {
        guard (state == .paused || state == .stopped), let pausedAt = pauseStartedAt else { return }
        let resumedAt = max(date, pausedAt)
        completedPauseIntervals.append(DateInterval(start: pausedAt, end: resumedAt))

        pauseStartedAt = nil
        state = .running
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
            pauseStartedAt = stoppedAt
        }

        state = .stopped
        clock = stoppedAt
        stopClock()
    }

    func resetToIdle() {
        state = .idle
        session = nil
        laps = []
        pauseStartedAt = nil
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
        let endDate = resolvedEndDate(endedAt: lap.endedAt, referenceDate: referenceDate)
        return activeElapsed(from: lap.startedAt, to: endDate)
    }

    func activeTimelineOffset(at date: Date) -> TimeInterval {
        guard let session else { return 0 }
        let clampedDate = pausedClampedReferenceDate(date)
        return activeElapsed(from: session.startedAt, to: clampedDate)
    }

    private func defaultLapLabel(for index: Int) -> String {
        "作業\(index)"
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
