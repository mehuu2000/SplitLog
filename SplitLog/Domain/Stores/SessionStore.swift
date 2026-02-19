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
    var state: SessionState
    var pauseStartedAt: Date?
    var lastLapActivationAt: Date?
    var completedPauseIntervals: [DateInterval]
}

struct StopwatchStorageSnapshot: Equatable, Codable, Sendable {
    static let currentSchemaVersion = 2

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

        if let schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) {
            self.schemaVersion = schemaVersion
            self.savedAt = try container.decode(Date.self, forKey: .savedAt)
            self.contexts = try container.decode([PersistedSessionContext].self, forKey: .contexts)
            self.sessionOrder = try container.decodeIfPresent([UUID].self, forKey: .sessionOrder)
                ?? self.contexts.map(\.session.id)
            self.selectedSessionID = try container.decodeIfPresent(UUID.self, forKey: .selectedSessionID)
            self.nextSessionNumber = try container.decode(Int.self, forKey: .nextSessionNumber)
            return
        }

        // Legacy payload support (before schemaVersion/savedAt/sessionOrder were introduced).
        let contexts = try container.decode([PersistedSessionContext].self, forKey: .contexts)
        self.schemaVersion = 1
        self.savedAt = Date()
        self.contexts = contexts
        self.sessionOrder = contexts.map(\.session.id)
        self.selectedSessionID = try container.decodeIfPresent(UUID.self, forKey: .selectedSessionID)
        self.nextSessionNumber = try container.decode(Int.self, forKey: .nextSessionNumber)
    }
}

protocol SessionStore: Sendable {
    func saveSnapshot(_ snapshot: StopwatchStorageSnapshot?) throws
    func loadSnapshot() throws -> StopwatchStorageSnapshot?
}
