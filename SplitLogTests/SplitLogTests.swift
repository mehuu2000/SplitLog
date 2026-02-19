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
        #expect(service.currentLap?.id == service.laps[0].id)
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
        #expect(service.currentLap?.id == service.laps[1].id)
        #expect(service.elapsedLap(service.laps[0]) == 40)
    }

    @MainActor
    @Test func selectLap_whileRunning_switchesElapsedTargetLap() {
        let service = StopwatchService(autoTick: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_010)
        let t2 = Date(timeIntervalSince1970: 1_020)
        let t3 = Date(timeIntervalSince1970: 1_030)

        service.startSession(at: t0)
        service.finishLap(at: t1) // lap2 selected and running
        service.selectLap(lapID: service.laps[0].id, at: t2)

        #expect(service.currentLap?.id == service.laps[0].id)
        #expect(service.elapsedLap(service.laps[0], at: t3) == 20)
        #expect(service.elapsedLap(service.laps[1], at: t3) == 10)
        #expect(service.elapsedSession(at: t3) == 30)
    }

    @MainActor
    @Test func finishLap_fromOlderSelectedLap_createsNextMaxIndexLap() {
        let service = StopwatchService(autoTick: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_010)
        let t2 = Date(timeIntervalSince1970: 1_020)
        let t3 = Date(timeIntervalSince1970: 1_030)
        let t4 = Date(timeIntervalSince1970: 1_040)

        service.startSession(at: t0)     // lap1
        service.finishLap(at: t1)        // lap2
        service.finishLap(at: t2)        // lap3
        service.selectLap(lapID: service.laps[0].id, at: t3) // select lap1

        service.finishLap(at: t4)

        #expect(service.laps.count == 4)
        #expect(service.laps.map(\.index) == [1, 2, 3, 4])
        #expect(service.currentLap?.index == 4)
    }

    @MainActor
    @Test func selectLap_whileStopped_appliesSelectionOnResume() {
        let service = StopwatchService(autoTick: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_010)
        let t2 = Date(timeIntervalSince1970: 1_020)
        let t3 = Date(timeIntervalSince1970: 1_030)
        let t4 = Date(timeIntervalSince1970: 1_040)
        let t5 = Date(timeIntervalSince1970: 1_050)

        service.startSession(at: t0)
        service.finishLap(at: t1) // lap2 selected
        service.finishSession(at: t2) // stopped while lap2 selected
        service.selectLap(lapID: service.laps[0].id, at: t3) // switch during stopped
        service.resumeSession(at: t4)

        #expect(service.currentLap?.id == service.laps[0].id)
        #expect(service.elapsedLap(service.laps[0], at: t5) == 20)
        #expect(service.elapsedLap(service.laps[1], at: t5) == 10)
        #expect(service.elapsedSession(at: t5) == 30)
    }

    @MainActor
    @Test func finishSession_stopsSessionAndAllowsResume() {
        let service = StopwatchService(autoTick: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_020)
        let t2 = Date(timeIntervalSince1970: 1_050)
        let t3 = Date(timeIntervalSince1970: 1_100)
        let t4 = Date(timeIntervalSince1970: 1_120)
        service.startSession(at: t0)
        service.finishLap(at: t1)

        service.finishSession(at: t2)

        #expect(service.state == .stopped)
        #expect(service.session?.endedAt == nil)
        #expect(service.completedLaps.count == 1)
        #expect(service.currentLap?.endedAt == nil)
        #expect(service.elapsedSession(at: t4) == 50)

        service.resumeSession(at: t3)
        #expect(service.state == .running)
        #expect(service.elapsedSession(at: t4) == 70)
    }

    @MainActor
    @Test func startSession_afterStopped_resumesCurrentSession() {
        let service = StopwatchService(autoTick: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_030)
        let t2 = Date(timeIntervalSince1970: 1_040)
        let t3 = Date(timeIntervalSince1970: 1_100)
        let t4 = Date(timeIntervalSince1970: 1_110)

        service.startSession(at: t0)
        let sessionID = service.session?.id
        service.finishLap(at: t1)
        service.finishSession(at: t2)
        service.startSession(at: t3)

        #expect(service.state == .running)
        #expect(service.session?.id == sessionID)
        #expect(service.session?.endedAt == nil)
        #expect(service.laps.count == 2)
        #expect(service.currentLap?.index == 2)
        #expect(service.elapsedSession(at: t4) == 50)
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
    @Test func finishSession_whilePaused_staysStoppedUntilResume() {
        let service = StopwatchService(autoTick: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let pausedAt = Date(timeIntervalSince1970: 1_015)
        let stopTappedAt = Date(timeIntervalSince1970: 1_060)
        let resumedAt = Date(timeIntervalSince1970: 1_080)
        let checkAt = Date(timeIntervalSince1970: 1_090)

        service.startSession(at: t0)
        service.pauseSession(at: pausedAt)
        service.finishSession(at: stopTappedAt)

        #expect(service.state == .stopped)
        #expect(service.session?.endedAt == nil)
        #expect(service.elapsedSession(at: checkAt) == 15)

        service.resumeSession(at: resumedAt)
        #expect(service.state == .running)
        #expect(service.elapsedSession(at: checkAt) == 25)
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

        #expect(service.state == .stopped)
        #expect(service.completedLaps.count == 1)
        #expect(service.elapsedLap(service.completedLaps[0]) == 10)
        #expect(service.elapsedCurrentLap(at: t4) == 20)
        #expect(service.elapsedSession() == 30)
    }

}
