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

protocol SessionStore: Sendable {
    func saveCompletedSession(_ record: SessionRecord) async throws
    func fetchCompletedSessions() async throws -> [SessionRecord]
    func saveActiveSessionSnapshot(_ snapshot: ActiveSessionSnapshot?) async throws
    func loadActiveSessionSnapshot() async throws -> ActiveSessionSnapshot?
}
