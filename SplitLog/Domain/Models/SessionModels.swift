//
//  SessionModels.swift
//  SplitLog
//
//  Created by Codex on 2026/02/17.
//

import Foundation

enum SessionState: String, Codable, Sendable {
    case idle
    case running
    case paused
    case stopped
    case finished
}

struct WorkSession: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var title: String
    let startedAt: Date
    var endedAt: Date?
}

struct WorkLap: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let sessionId: UUID
    let index: Int
    let startedAt: Date
    var endedAt: Date?
    var accumulatedDuration: TimeInterval
    var label: String
}
