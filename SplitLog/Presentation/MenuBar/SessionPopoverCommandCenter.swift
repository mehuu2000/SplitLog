//
//  SessionPopoverCommandCenter.swift
//  SplitLog
//
//  Created by Codex on 2026/03/15.
//

import Combine
import Foundation

@MainActor
final class SessionPopoverCommandCenter: ObservableObject {
    struct CommandRequest: Identifiable, Equatable {
        let id = UUID()
        let command: Command
    }

    enum Command: Equatable {
        case openCurrentLapMemo
        case revealSelectedLap
    }

    @Published private(set) var commandRequest: CommandRequest?

    func send(_ command: Command) {
        commandRequest = CommandRequest(command: command)
    }

    func consume(id: UUID) {
        guard commandRequest?.id == id else { return }
        commandRequest = nil
    }
}
