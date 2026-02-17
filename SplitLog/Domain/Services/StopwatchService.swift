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
        guard state != .running else { return }

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

    func finishSession(at date: Date = Date()) {
        guard state == .running, var activeSession = session else { return }

        if let currentIndex = laps.lastIndex(where: { $0.endedAt == nil }) {
            laps[currentIndex].endedAt = date
        }

        activeSession.endedAt = date
        session = activeSession
        state = .finished
        clock = date
        stopClock()
    }

    func resetToIdle() {
        state = .idle
        session = nil
        laps = []
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
        let endDate = session.endedAt ?? referenceDate ?? clock
        return max(0, endDate.timeIntervalSince(session.startedAt))
    }

    func elapsedCurrentLap(at referenceDate: Date? = nil) -> TimeInterval {
        guard let currentLap else { return 0 }
        let endDate = currentLap.endedAt ?? referenceDate ?? clock
        return max(0, endDate.timeIntervalSince(currentLap.startedAt))
    }

    func elapsedLap(_ lap: WorkLap, at referenceDate: Date? = nil) -> TimeInterval {
        let endDate = lap.endedAt ?? referenceDate ?? clock
        return max(0, endDate.timeIntervalSince(lap.startedAt))
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
}
