//
//  AppSettings.swift
//  SplitLog
//
//  Created by Codex on 2026/02/20.
//

import Foundation

enum ThemeMode: String, Codable, CaseIterable, Sendable {
    case color
    case monochrome
}

struct AppSettings: Equatable, Codable, Sendable {
    var themeMode: ThemeMode
    var showTimelineRing: Bool

    init(themeMode: ThemeMode = .color, showTimelineRing: Bool = true) {
        self.themeMode = themeMode
        self.showTimelineRing = showTimelineRing
    }

    static let `default` = AppSettings()
}
