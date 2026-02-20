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

enum SummaryTimeFormat: String, Codable, CaseIterable, Sendable {
    case decimalHours
    case hourMinute
}

enum SummaryMemoFormat: String, Codable, CaseIterable, Sendable {
    case bulleted
    case plain
}

struct AppSettings: Equatable, Codable, Sendable {
    var themeMode: ThemeMode
    var showTimelineRing: Bool
    var summaryTimeFormat: SummaryTimeFormat
    var summaryMemoFormat: SummaryMemoFormat

    init(
        themeMode: ThemeMode = .color,
        showTimelineRing: Bool = true,
        summaryTimeFormat: SummaryTimeFormat = .decimalHours,
        summaryMemoFormat: SummaryMemoFormat = .bulleted
    ) {
        self.themeMode = themeMode
        self.showTimelineRing = showTimelineRing
        self.summaryTimeFormat = summaryTimeFormat
        self.summaryMemoFormat = summaryMemoFormat
    }

    static let `default` = AppSettings()

    private enum CodingKeys: String, CodingKey {
        case themeMode
        case showTimelineRing
        case summaryTimeFormat
        case summaryMemoFormat
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.themeMode = try container.decodeIfPresent(ThemeMode.self, forKey: .themeMode) ?? .color
        self.showTimelineRing = try container.decodeIfPresent(Bool.self, forKey: .showTimelineRing) ?? true
        self.summaryTimeFormat = try container.decodeIfPresent(SummaryTimeFormat.self, forKey: .summaryTimeFormat) ?? .decimalHours
        self.summaryMemoFormat = try container.decodeIfPresent(SummaryMemoFormat.self, forKey: .summaryMemoFormat) ?? .bulleted
    }
}
