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
    var timelineRingHoursPerCycle: Int
    var summaryTimeFormat: SummaryTimeFormat
    var summaryMemoFormat: SummaryMemoFormat
    var defaultSplitAccumulationMode: SplitAccumulationMode

    init(
        themeMode: ThemeMode = .color,
        timelineRingHoursPerCycle: Int = 3,
        summaryTimeFormat: SummaryTimeFormat = .decimalHours,
        summaryMemoFormat: SummaryMemoFormat = .bulleted,
        defaultSplitAccumulationMode: SplitAccumulationMode = .radio
    ) {
        self.themeMode = themeMode
        self.timelineRingHoursPerCycle = max(1, timelineRingHoursPerCycle)
        self.summaryTimeFormat = summaryTimeFormat
        self.summaryMemoFormat = summaryMemoFormat
        self.defaultSplitAccumulationMode = defaultSplitAccumulationMode
    }

    static let `default` = AppSettings()

    private enum CodingKeys: String, CodingKey {
        case themeMode
        case timelineRingHoursPerCycle
        case summaryTimeFormat
        case summaryMemoFormat
        case defaultSplitAccumulationMode
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case splitAccumulationMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        self.themeMode = try container.decodeIfPresent(ThemeMode.self, forKey: .themeMode) ?? .color
        self.timelineRingHoursPerCycle = max(1, try container.decodeIfPresent(Int.self, forKey: .timelineRingHoursPerCycle) ?? 3)
        self.summaryTimeFormat = try container.decodeIfPresent(SummaryTimeFormat.self, forKey: .summaryTimeFormat) ?? .decimalHours
        self.summaryMemoFormat = try container.decodeIfPresent(SummaryMemoFormat.self, forKey: .summaryMemoFormat) ?? .bulleted
        self.defaultSplitAccumulationMode = try container.decodeIfPresent(
            SplitAccumulationMode.self,
            forKey: .defaultSplitAccumulationMode
        ) ?? (try legacyContainer.decodeIfPresent(SplitAccumulationMode.self, forKey: .splitAccumulationMode) ?? .radio)
    }
}
