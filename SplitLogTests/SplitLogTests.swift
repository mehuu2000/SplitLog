//
//  SplitLogTests.swift
//  SplitLogTests
//
//  Created by 濱田真仁 on 2026/02/17.
//

import Foundation
import Testing
@testable import SplitLog

struct SplitLogTests {

    @MainActor
    @Test func startSession_startsRunningStateWithFirstLap() {
        let service = StopwatchService(autoTick: false)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        service.startSession(at: startedAt)

        #expect(service.state == .running)
        #expect(service.session?.startedAt == startedAt)
        #expect(service.session?.endedAt == nil)
        #expect(service.laps.count == 1)
        #expect(service.laps[0].index == 1)
        #expect(service.laps[0].label == "作業1")
        #expect(service.currentLap?.endedAt == nil)
    }

    @MainActor
    @Test func finishLap_closesCurrentLapAndStartsNextLap() {
        let service = StopwatchService(autoTick: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_040)
        service.startSession(at: t0)

        service.finishLap(at: t1)

        #expect(service.laps.count == 2)
        #expect(service.laps[0].endedAt == t1)
        #expect(service.laps[1].index == 2)
        #expect(service.laps[1].startedAt == t1)
        #expect(service.laps[1].endedAt == nil)
        #expect(service.elapsedLap(service.laps[0]) == 40)
    }

    @MainActor
    @Test func finishSession_closesCurrentLapAndSession() {
        let service = StopwatchService(autoTick: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_020)
        let t2 = Date(timeIntervalSince1970: 1_050)
        service.startSession(at: t0)
        service.finishLap(at: t1)

        service.finishSession(at: t2)

        #expect(service.state == .finished)
        #expect(service.session?.endedAt == t2)
        #expect(service.completedLaps.count == 2)
        #expect(service.currentLap == nil)
        #expect(service.elapsedSession() == 50)
    }

    @MainActor
    @Test func startSession_afterFinished_restartsAsNewSession() {
        let service = StopwatchService(autoTick: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_030)
        let t2 = Date(timeIntervalSince1970: 2_000)

        service.startSession(at: t0)
        service.finishSession(at: t1)
        service.startSession(at: t2)

        #expect(service.state == .running)
        #expect(service.session?.startedAt == t2)
        #expect(service.session?.endedAt == nil)
        #expect(service.laps.count == 1)
        #expect(service.laps[0].index == 1)
    }

    @MainActor
    @Test func updateLapLabel_allowsEditingDuringRunning() {
        let service = StopwatchService(autoTick: false)
        let startedAt = Date(timeIntervalSince1970: 1_000)
        service.startSession(at: startedAt)
        guard let lapID = service.currentLap?.id else {
            Issue.record("currentLap should exist after starting a session")
            return
        }

        service.updateLapLabel(lapID: lapID, label: "要件整理")
        #expect(service.laps[0].label == "要件整理")

        service.updateLapLabel(lapID: lapID, label: "")
        #expect(service.laps[0].label == "作業1")
    }

    @MainActor
    @Test func pauseAndResume_excludesPausedDurationFromElapsedTime() {
        let service = StopwatchService(autoTick: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_010)
        let t2 = Date(timeIntervalSince1970: 1_030)
        let t3 = Date(timeIntervalSince1970: 1_050)

        service.startSession(at: t0)
        service.pauseSession(at: t1)
        #expect(service.state == .paused)

        service.resumeSession(at: t2)
        #expect(service.state == .running)

        #expect(service.elapsedSession(at: t3) == 30)
        #expect(service.elapsedCurrentLap(at: t3) == 30)
    }

    @MainActor
    @Test func finishSession_whilePaused_usesPauseTimeAsSessionEnd() {
        let service = StopwatchService(autoTick: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let pausedAt = Date(timeIntervalSince1970: 1_015)
        let finishTappedAt = Date(timeIntervalSince1970: 1_060)

        service.startSession(at: t0)
        service.pauseSession(at: pausedAt)
        service.finishSession(at: finishTappedAt)

        #expect(service.state == .finished)
        #expect(service.session?.endedAt == pausedAt)
        #expect(service.elapsedSession() == 15)
    }

    @MainActor
    @Test func pauseAndResume_keepsCompletedLapDurationConsistent() {
        let service = StopwatchService(autoTick: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_010)
        let t2 = Date(timeIntervalSince1970: 1_015)
        let t3 = Date(timeIntervalSince1970: 1_025)
        let t4 = Date(timeIntervalSince1970: 1_040)

        service.startSession(at: t0)
        service.finishLap(at: t1) // lap1 completed
        service.pauseSession(at: t2)
        service.resumeSession(at: t3)
        service.finishSession(at: t4)

        #expect(service.completedLaps.count == 2)
        #expect(service.elapsedLap(service.completedLaps[0]) == 10)
        #expect(service.elapsedLap(service.completedLaps[1]) == 20)
        #expect(service.elapsedSession() == 30)
    }

}
