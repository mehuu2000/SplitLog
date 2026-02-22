//
//  SessionStore.swift
//  SplitLog
//
//  Created by Codex on 2026/02/17.
//

import Foundation

struct SessionRecord: Identifiable, Equatable, Codable, Sendable {
    let session: WorkSession
    let laps: [WorkLap]

    var id: UUID { session.id }
}

struct ActiveSessionSnapshot: Equatable, Codable, Sendable {
    let session: WorkSession
    let laps: [WorkLap]
    let capturedAt: Date
}

struct PersistedSessionContext: Equatable, Codable, Sendable {
    var session: WorkSession
    var laps: [WorkLap]
    var selectedLapID: UUID?
    var activeLapIDs: Set<UUID>
    var state: SessionState
    var pauseStartedAt: Date?
    var lastDistributedWholeSeconds: Int
    var distributionCursor: Int
    var totalPausedDuration: TimeInterval

    init(
        session: WorkSession,
        laps: [WorkLap],
        selectedLapID: UUID?,
        activeLapIDs: Set<UUID>,
        state: SessionState,
        pauseStartedAt: Date?,
        lastDistributedWholeSeconds: Int,
        distributionCursor: Int,
        totalPausedDuration: TimeInterval
    ) {
        self.session = session
        self.laps = laps
        self.selectedLapID = selectedLapID
        self.activeLapIDs = activeLapIDs
        self.state = state
        self.pauseStartedAt = pauseStartedAt
        self.lastDistributedWholeSeconds = max(0, lastDistributedWholeSeconds)
        self.distributionCursor = max(0, distributionCursor)
        self.totalPausedDuration = max(0, totalPausedDuration)
    }

    private enum CodingKeys: String, CodingKey {
        case session
        case laps
        case selectedLapID
        case activeLapIDs
        case state
        case pauseStartedAt
        case lastDistributedWholeSeconds
        case distributionCursor
        case totalPausedDuration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        session = try container.decode(WorkSession.self, forKey: .session)
        laps = try container.decode([WorkLap].self, forKey: .laps)
        selectedLapID = try container.decodeIfPresent(UUID.self, forKey: .selectedLapID)
        activeLapIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .activeLapIDs) ?? []
        state = try container.decode(SessionState.self, forKey: .state)
        pauseStartedAt = try container.decodeIfPresent(Date.self, forKey: .pauseStartedAt)
        lastDistributedWholeSeconds = max(0, try container.decodeIfPresent(Int.self, forKey: .lastDistributedWholeSeconds) ?? 0)
        distributionCursor = max(0, try container.decodeIfPresent(Int.self, forKey: .distributionCursor) ?? 0)
        totalPausedDuration = max(0, try container.decodeIfPresent(TimeInterval.self, forKey: .totalPausedDuration) ?? 0)
    }
}

struct StopwatchStorageSnapshot: Equatable, Codable, Sendable {
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var savedAt: Date
    var contexts: [PersistedSessionContext]
    var sessionOrder: [UUID]
    var selectedSessionID: UUID?
    var nextSessionNumber: Int

    init(
        schemaVersion: Int = StopwatchStorageSnapshot.currentSchemaVersion,
        savedAt: Date,
        contexts: [PersistedSessionContext],
        sessionOrder: [UUID],
        selectedSessionID: UUID?,
        nextSessionNumber: Int
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.contexts = contexts
        self.sessionOrder = sessionOrder
        self.selectedSessionID = selectedSessionID
        self.nextSessionNumber = nextSessionNumber
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case savedAt
        case contexts
        case sessionOrder
        case selectedSessionID
        case nextSessionNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? StopwatchStorageSnapshot.currentSchemaVersion
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        contexts = try container.decode([PersistedSessionContext].self, forKey: .contexts)
        sessionOrder = try container.decode([UUID].self, forKey: .sessionOrder)
        selectedSessionID = try container.decodeIfPresent(UUID.self, forKey: .selectedSessionID)
        nextSessionNumber = try container.decode(Int.self, forKey: .nextSessionNumber)
    }
}

protocol SessionStore: Sendable {
    func saveSnapshot(_ snapshot: StopwatchStorageSnapshot?) throws
    func loadSnapshot() throws -> StopwatchStorageSnapshot?
}
