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
    var startedAt: Date
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
    var memo: String

    init(
        id: UUID,
        sessionId: UUID,
        index: Int,
        startedAt: Date,
        endedAt: Date?,
        accumulatedDuration: TimeInterval,
        label: String,
        memo: String = ""
    ) {
        self.id = id
        self.sessionId = sessionId
        self.index = index
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.accumulatedDuration = accumulatedDuration
        self.label = label
        self.memo = memo
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionId
        case index
        case startedAt
        case endedAt
        case accumulatedDuration
        case label
        case memo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        index = try container.decode(Int.self, forKey: .index)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        accumulatedDuration = try container.decode(TimeInterval.self, forKey: .accumulatedDuration)
        label = try container.decode(String.self, forKey: .label)
        memo = try container.decodeIfPresent(String.self, forKey: .memo) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(index, forKey: .index)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encode(accumulatedDuration, forKey: .accumulatedDuration)
        try container.encode(label, forKey: .label)
        try container.encode(memo, forKey: .memo)
    }
}
