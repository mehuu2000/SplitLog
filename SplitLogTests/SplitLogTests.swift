//
//  SplitLogTests.swift
//  SplitLogTests
//
//  Created by 濱田真仁 on 2026/02/17.
//

import Foundation
import Testing
@testable import SplitLog

private final class InMemorySessionStore: @unchecked Sendable, SessionStore {
    private var snapshot: StopwatchStorageSnapshot?

    func saveSnapshot(_ snapshot: StopwatchStorageSnapshot?) throws {
        self.snapshot = snapshot
    }

    func loadSnapshot() throws -> StopwatchStorageSnapshot? {
        snapshot
    }

    func overwriteSnapshot(_ snapshot: StopwatchStorageSnapshot?) {
        self.snapshot = snapshot
    }
}

struct SplitLogTests {
    private func expectedSessionTitlePrefix(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return "\(year)/\(month)/\(day)"
    }

    private func makeIsolatedUserDefaults() -> (userDefaults: UserDefaults, suiteName: String) {
        let suiteName = "SplitLogTests.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            fatalError("failed to create isolated UserDefaults suite")
        }
        return (userDefaults, suiteName)
    }

    @MainActor
    private func waitForCoalescedPersistence() async {
        try? await Task.sleep(nanoseconds: 350_000_000)
    }

    @MainActor
    @Test func startSession_startsRunningStateWithFirstLap() {
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
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
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
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
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
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
    @Test func checkboxMode_distributesElapsedAcrossCheckedLaps() {
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_010)
        let t2 = Date(timeIntervalSince1970: 1_016)

        service.startSession(at: t0)
        service.finishLap(at: t1) // lap2 selected/running

        let lap1ID = service.laps[0].id
        let lap2ID = service.laps[1].id

        service.setSplitAccumulationMode(.checkbox, at: t1)
        service.toggleLapActive(lapID: lap1ID, at: t1) // lap1 + lap2

        #expect(service.activeLapIDs == Set([lap1ID, lap2ID]))
        #expect(service.elapsedLap(service.laps[0], at: t2) == 13)
        #expect(service.elapsedLap(service.laps[1], at: t2) == 3)
        #expect(service.elapsedSession(at: t2) == 16)
    }

    @MainActor
    @Test func checkboxMode_finishLap_keepsExistingChecksAndAddsNewLapCheck() {
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_010)
        let t2 = Date(timeIntervalSince1970: 1_020)

        service.startSession(at: t0)
        service.finishLap(at: t1) // lap2 selected/running

        let lap1ID = service.laps[0].id
        let lap2ID = service.laps[1].id
        service.setSplitAccumulationMode(.checkbox, at: t1)
        service.toggleLapActive(lapID: lap1ID, at: t1) // lap1 + lap2

        service.finishLap(at: t2)

        let lap3ID = service.laps[2].id
        #expect(service.activeLapIDs == Set([lap1ID, lap2ID, lap3ID]))
        #expect(service.selectedLapID == lap3ID)
    }

    @MainActor
    @Test func finishLap_fromOlderSelectedLap_createsNextMaxIndexLap() {
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
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
    @Test func addSession_createsNewSessionAndKeepsOnlyOneRunning() {
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_010)
        let t2 = Date(timeIntervalSince1970: 1_020)
        let t3 = Date(timeIntervalSince1970: 1_030)

        service.startSession(at: t0)
        let firstID = service.session?.id
        service.addSession(at: t1)
        let secondID = service.session?.id

        #expect(service.sessions.count == 2)
        #expect(firstID != nil)
        #expect(secondID != nil)
        #expect(firstID != secondID)
        #expect(service.state == .idle)

        if let firstID {
            service.selectSession(sessionID: firstID, at: t2)
            #expect(service.state == .stopped)
            #expect(service.elapsedSession(at: t3) == 10)
        }

        if let secondID {
            #expect(service.sessionState(for: secondID) == .idle)
            #expect(service.elapsedSession(for: secondID, at: t3) == 0)
        }
    }

    @MainActor
    @Test func addSession_usesDateBasedDefaultTitleAndSuffixesOnlyWhenDuplicated() {
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
        let calendar = Calendar.current
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = t0.addingTimeInterval(60)
        let t2 = t0.addingTimeInterval(120)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: t0) ?? t0.addingTimeInterval(86_400)

        let day0Prefix = expectedSessionTitlePrefix(for: t0)
        let day1Prefix = expectedSessionTitlePrefix(for: nextDay)

        service.addSession(at: t0)
        #expect(service.session?.title == day0Prefix)

        service.addSession(at: t1)
        #expect(service.session?.title == "\(day0Prefix)-A")

        service.addSession(at: t2)
        #expect(service.session?.title == "\(day0Prefix)-B")

        service.addSession(at: nextDay)
        #expect(service.session?.title == day1Prefix)
    }

    @MainActor
    @Test func startSession_onStoppedSelection_resumesItAndStopsAnotherRunningSession() {
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_010)
        let t2 = Date(timeIntervalSince1970: 1_020)
        let t3 = Date(timeIntervalSince1970: 1_030)
        let t4 = Date(timeIntervalSince1970: 1_040)
        let t5 = Date(timeIntervalSince1970: 1_050)

        service.startSession(at: t0)
        guard let firstID = service.session?.id else {
            Issue.record("first session should exist")
            return
        }

        service.finishSession(at: t1)   // first stopped
        service.addSession(at: t2)      // second idle (not started yet)
        guard let secondID = service.session?.id else {
            Issue.record("second session should exist")
            return
        }

        service.selectSession(sessionID: firstID, at: t3)
        #expect(service.state == .stopped)

        service.startSession(at: t4)    // first resume, second should stop
        #expect(service.state == .running)
        #expect(service.session?.id == firstID)
        #expect(service.sessionState(for: secondID) == .idle)

        service.selectSession(sessionID: secondID, at: t5)
        #expect(service.elapsedSession(at: t5) == 0)
    }

    @MainActor
    @Test func selectSession_stopsPreviouslyRunningSessionElapsedTime() {
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_010)
        let t2 = Date(timeIntervalSince1970: 1_020)
        let t3 = Date(timeIntervalSince1970: 1_030)
        let t4 = Date(timeIntervalSince1970: 1_040)

        service.startSession(at: t0)            // session1 running
        guard let session1ID = service.session?.id else {
            Issue.record("session1 should exist")
            return
        }

        service.addSession(at: t1)              // session2 idle, session1 stopped
        guard let session2ID = service.session?.id else {
            Issue.record("session2 should exist")
            return
        }

        service.selectSession(sessionID: session1ID, at: t2)
        service.startSession(at: t2)            // session1 running again
        service.selectSession(sessionID: session2ID, at: t3) // should stop session1 at t3

        #expect(service.sessionState(for: session1ID) == .stopped)
        #expect(service.elapsedSession(for: session1ID, at: t4) == 20)
        #expect(service.state == .idle)
    }

    @MainActor
    @Test func selectLap_whileStopped_appliesSelectionOnResume() {
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
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
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
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
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
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
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
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
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
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
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
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
    @Test func resetSelectedSession_resetsOnlyCurrentSession() {
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_010)
        let t2 = Date(timeIntervalSince1970: 1_020)
        let t3 = Date(timeIntervalSince1970: 1_030)

        service.startSession(at: t0)
        guard let session1ID = service.session?.id else {
            Issue.record("session1 should exist")
            return
        }

        service.finishSession(at: t1)
        service.addSession(at: t2)
        guard let session2ID = service.session?.id else {
            Issue.record("session2 should exist")
            return
        }
        service.startSession(at: t2)
        service.finishSession(at: t3)

        service.selectSession(sessionID: session1ID, at: t3)
        service.resetSelectedSession(at: t3)

        #expect(service.session?.id == session1ID)
        #expect(service.state == .idle)
        #expect(service.laps.isEmpty)
        #expect(service.elapsedSession(at: t3) == 0)

        #expect(service.sessionState(for: session2ID) == .stopped)
        #expect(service.elapsedSession(for: session2ID, at: t3) == 10)
    }

    @MainActor
    @Test func deleteSelectedSession_removesOnlyCurrentSession() {
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_010)

        service.startSession(at: t0)
        guard let session1ID = service.session?.id else {
            Issue.record("session1 should exist")
            return
        }

        service.addSession(at: t1)
        guard let session2ID = service.session?.id else {
            Issue.record("session2 should exist")
            return
        }

        service.deleteSelectedSession(at: t1)

        #expect(service.sessions.count == 1)
        #expect(service.selectedSessionID == session1ID)
        #expect(service.session?.id == session1ID)
        #expect(service.sessions.contains(where: { $0.id == session2ID }) == false)
    }

    @MainActor
    @Test func deleteSelectedSession_selectsNewerNeighborWhenAvailable() {
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_010)
        let t2 = Date(timeIntervalSince1970: 1_020)
        let t3 = Date(timeIntervalSince1970: 1_030)

        service.addSession(at: t0)
        guard let session1ID = service.session?.id else {
            Issue.record("session1 should exist")
            return
        }
        service.addSession(at: t1)
        guard let session2ID = service.session?.id else {
            Issue.record("session2 should exist")
            return
        }
        service.addSession(at: t2)
        guard let session3ID = service.session?.id else {
            Issue.record("session3 should exist")
            return
        }

        service.selectSession(sessionID: session2ID, at: t3)
        service.deleteSelectedSession(at: t3)

        #expect(service.sessions.count == 2)
        #expect(service.selectedSessionID == session3ID)
        #expect(service.session?.id == session3ID)
        #expect(service.sessions.contains(where: { $0.id == session2ID }) == false)
        #expect(service.sessions.contains(where: { $0.id == session1ID }))
    }

    @MainActor
    @Test func pauseAndResume_keepsCompletedLapDurationConsistent() {
        let service = StopwatchService(autoTick: false, persistenceEnabled: false)
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

    @MainActor
    @Test func restore_runningSnapshot_isNormalizedToStoppedAtRelaunchTime() async {
        let store = InMemorySessionStore()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_010)
        let relaunchAt = Date(timeIntervalSince1970: 1_050)
        let checkAt = Date(timeIntervalSince1970: 1_200)

        let source = StopwatchService(autoTick: false, sessionStore: store)
        source.startSession(at: t0)
        source.finishLap(at: t1) // persists while still running
        await waitForCoalescedPersistence()

        let restored = StopwatchService(
            autoTick: false,
            sessionStore: store,
            restoreReferenceDate: relaunchAt
        )

        #expect(restored.state == .stopped)
        #expect(restored.laps.count == 2)
        #expect(restored.currentLap?.index == 2)
        #expect(restored.elapsedSession(at: checkAt) == 50)
        #expect(restored.elapsedCurrentLap(at: checkAt) == 40)
    }

    @MainActor
    @Test func prepareForTermination_flushesLatestElapsedTimeToStore() {
        let store = InMemorySessionStore()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_015)
        let checkAt = Date(timeIntervalSince1970: 1_200)

        let source = StopwatchService(autoTick: false, sessionStore: store)
        source.startSession(at: t0)
        source.prepareForTermination(at: t1)

        let restored = StopwatchService(autoTick: false, sessionStore: store)

        #expect(restored.state == .stopped)
        #expect(restored.elapsedSession(at: checkAt) == 15)
        #expect(restored.elapsedCurrentLap(at: checkAt) == 15)
    }

    @MainActor
    @Test func updateLapMemo_persistsAndRestoresMemoText() async throws {
        let store = InMemorySessionStore()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let memo = "次回はここから再開"

        let source = StopwatchService(autoTick: false, sessionStore: store)
        source.startSession(at: t0)
        let lapID = try #require(source.currentLap?.id)
        source.updateLapMemo(lapID: lapID, memo: memo)
        await waitForCoalescedPersistence()

        let restored = StopwatchService(autoTick: false, sessionStore: store)
        #expect(restored.currentLap?.memo == memo)
    }

    @MainActor
    @Test func updateSessionTitle_persistsAndRestoresTitle() async throws {
        let store = InMemorySessionStore()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let title = "朝の集中作業"

        let source = StopwatchService(autoTick: false, sessionStore: store)
        source.startSession(at: t0)
        let sessionID = try #require(source.session?.id)
        source.updateSessionTitle(sessionID: sessionID, title: title)
        await waitForCoalescedPersistence()

        let restored = StopwatchService(autoTick: false, sessionStore: store)
        #expect(restored.session?.title == title)
    }

    @MainActor
    @Test func restore_duplicateSessionOrder_isDeduplicatedKeepingFirstSeenOrder() {
        let store = InMemorySessionStore()
        let t0 = Date(timeIntervalSince1970: 1_000)

        let session1 = WorkSession(id: UUID(), title: "セッション1", startedAt: t0, endedAt: nil)
        let session2 = WorkSession(id: UUID(), title: "セッション2", startedAt: t0, endedAt: nil)

        let context1 = PersistedSessionContext(
            session: session1,
            laps: [],
            selectedLapID: nil,
            activeLapIDs: [],
            state: .idle,
            pauseStartedAt: nil,
            lastLapActivationAt: nil,
            lastDistributedWholeSeconds: 0,
            distributionCursor: 0,
            totalPausedDuration: 0,
            completedPauseIntervals: []
        )
        let context2 = PersistedSessionContext(
            session: session2,
            laps: [],
            selectedLapID: nil,
            activeLapIDs: [],
            state: .idle,
            pauseStartedAt: nil,
            lastLapActivationAt: nil,
            lastDistributedWholeSeconds: 0,
            distributionCursor: 0,
            totalPausedDuration: 0,
            completedPauseIntervals: []
        )

        store.overwriteSnapshot(
            StopwatchStorageSnapshot(
                savedAt: t0,
                contexts: [context1, context2],
                sessionOrder: [session2.id, session2.id, session1.id, session2.id],
                selectedSessionID: session2.id,
                nextSessionNumber: 3
            )
        )

        let restored = StopwatchService(autoTick: false, sessionStore: store)

        #expect(restored.sessions.count == 2)
        #expect(restored.sessions.map(\.id) == [session2.id, session1.id])
    }

    @MainActor
    @Test func restore_invalidSelectedLapID_fallsBackToValidLapAndAllowsFinishLap() {
        let store = InMemorySessionStore()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_010)
        let t2 = Date(timeIntervalSince1970: 1_020)
        let t3 = Date(timeIntervalSince1970: 1_030)
        let t4 = Date(timeIntervalSince1970: 1_040)

        let sessionID = UUID()
        let session = WorkSession(id: sessionID, title: "セッション1", startedAt: t0, endedAt: nil)
        let lap1 = WorkLap(
            id: UUID(),
            sessionId: sessionID,
            index: 1,
            startedAt: t0,
            endedAt: t1,
            accumulatedDuration: 10,
            label: "作業1"
        )
        let lap2 = WorkLap(
            id: UUID(),
            sessionId: sessionID,
            index: 2,
            startedAt: t1,
            endedAt: nil,
            accumulatedDuration: 10,
            label: "作業2"
        )

        let corruptedContext = PersistedSessionContext(
            session: session,
            laps: [lap1, lap2],
            selectedLapID: UUID(), // not found in laps
            activeLapIDs: [],
            state: .stopped,
            pauseStartedAt: t2,
            lastLapActivationAt: nil,
            lastDistributedWholeSeconds: 20,
            distributionCursor: 0,
            totalPausedDuration: 0,
            completedPauseIntervals: []
        )

        store.overwriteSnapshot(
            StopwatchStorageSnapshot(
                savedAt: t2,
                contexts: [corruptedContext],
                sessionOrder: [sessionID],
                selectedSessionID: sessionID,
                nextSessionNumber: 2
            )
        )

        let restored = StopwatchService(autoTick: false, sessionStore: store)
        #expect(restored.currentLap?.id == lap2.id)

        restored.resumeSession(at: t3)
        restored.finishLap(at: t4)

        #expect(restored.state == .running)
        #expect(restored.laps.count == 3)
        #expect(restored.currentLap?.index == 3)
    }

    @MainActor
    @Test func appSettingsStore_withoutStoredValue_usesDefaults() {
        let isolated = makeIsolatedUserDefaults()
        defer { isolated.userDefaults.removePersistentDomain(forName: isolated.suiteName) }

        let store = AppSettingsStore(userDefaults: isolated.userDefaults, storageKey: "app_settings_test")

        #expect(store.themeMode == .color)
        #expect(store.showTimelineRing == true)
        #expect(store.settings == .default)
    }

    @MainActor
    @Test func appSettingsStore_themeMode_isPersistedAndRestored() throws {
        let isolated = makeIsolatedUserDefaults()
        defer { isolated.userDefaults.removePersistentDomain(forName: isolated.suiteName) }
        let storageKey = "app_settings_test"

        let source = AppSettingsStore(userDefaults: isolated.userDefaults, storageKey: storageKey)
        source.setThemeMode(.monochrome)

        let storedData = try #require(isolated.userDefaults.data(forKey: storageKey))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: storedData)
        #expect(decoded.themeMode == .monochrome)
        #expect(decoded.showTimelineRing == true)

        let restored = AppSettingsStore(userDefaults: isolated.userDefaults, storageKey: storageKey)
        #expect(restored.themeMode == .monochrome)
        #expect(restored.showTimelineRing == true)
    }

    @MainActor
    @Test func appSettingsStore_showTimelineRing_isPersistedAndRestored() throws {
        let isolated = makeIsolatedUserDefaults()
        defer { isolated.userDefaults.removePersistentDomain(forName: isolated.suiteName) }
        let storageKey = "app_settings_test"

        let source = AppSettingsStore(userDefaults: isolated.userDefaults, storageKey: storageKey)
        source.setShowTimelineRing(false)

        let storedData = try #require(isolated.userDefaults.data(forKey: storageKey))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: storedData)
        #expect(decoded.showTimelineRing == false)
        #expect(decoded.themeMode == .color)

        let restored = AppSettingsStore(userDefaults: isolated.userDefaults, storageKey: storageKey)
        #expect(restored.showTimelineRing == false)
        #expect(restored.themeMode == .color)
    }

    @MainActor
    @Test func appSettingsStore_update_reflectsBothSettingsAndPersists() {
        let isolated = makeIsolatedUserDefaults()
        defer { isolated.userDefaults.removePersistentDomain(forName: isolated.suiteName) }
        let storageKey = "app_settings_test"

        let source = AppSettingsStore(userDefaults: isolated.userDefaults, storageKey: storageKey)
        source.update(AppSettings(themeMode: .monochrome, showTimelineRing: false))

        #expect(source.themeMode == .monochrome)
        #expect(source.showTimelineRing == false)

        let restored = AppSettingsStore(userDefaults: isolated.userDefaults, storageKey: storageKey)
        #expect(restored.themeMode == .monochrome)
        #expect(restored.showTimelineRing == false)
    }

}
