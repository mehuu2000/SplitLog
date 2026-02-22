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

enum SplitAccumulationMode: String, Codable, CaseIterable, Sendable {
    case radio
    case checkbox
}

struct AppSettings: Equatable, Codable, Sendable {
    var themeMode: ThemeMode
    var showTimelineRing: Bool
    var timelineRingHoursPerCycle: Int
    var summaryTimeFormat: SummaryTimeFormat
    var summaryMemoFormat: SummaryMemoFormat
    var splitAccumulationMode: SplitAccumulationMode

    init(
        themeMode: ThemeMode = .color,
        showTimelineRing: Bool = true,
        timelineRingHoursPerCycle: Int = 3,
        summaryTimeFormat: SummaryTimeFormat = .decimalHours,
        summaryMemoFormat: SummaryMemoFormat = .bulleted,
        splitAccumulationMode: SplitAccumulationMode = .radio
    ) {
        self.themeMode = themeMode
        self.showTimelineRing = showTimelineRing
        self.timelineRingHoursPerCycle = max(1, timelineRingHoursPerCycle)
        self.summaryTimeFormat = summaryTimeFormat
        self.summaryMemoFormat = summaryMemoFormat
        self.splitAccumulationMode = splitAccumulationMode
    }

    static let `default` = AppSettings()

    private enum CodingKeys: String, CodingKey {
        case themeMode
        case showTimelineRing
        case timelineRingHoursPerCycle
        case summaryTimeFormat
        case summaryMemoFormat
        case splitAccumulationMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.themeMode = try container.decodeIfPresent(ThemeMode.self, forKey: .themeMode) ?? .color
        self.showTimelineRing = try container.decodeIfPresent(Bool.self, forKey: .showTimelineRing) ?? true
        self.timelineRingHoursPerCycle = max(1, try container.decodeIfPresent(Int.self, forKey: .timelineRingHoursPerCycle) ?? 3)
        self.summaryTimeFormat = try container.decodeIfPresent(SummaryTimeFormat.self, forKey: .summaryTimeFormat) ?? .decimalHours
        self.summaryMemoFormat = try container.decodeIfPresent(SummaryMemoFormat.self, forKey: .summaryMemoFormat) ?? .bulleted
        self.splitAccumulationMode = try container.decodeIfPresent(SplitAccumulationMode.self, forKey: .splitAccumulationMode) ?? .radio
    }
}
