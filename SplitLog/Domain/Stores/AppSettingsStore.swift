//
//  AppSettingsStore.swift
//  SplitLog
//
//  Created by Codex on 2026/02/20.
//

import Combine
import Foundation

@MainActor
final class AppSettingsStore: ObservableObject {
    struct PersistenceErrorEvent: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    @Published private(set) var settings: AppSettings {
        didSet {
            persistIfNeeded()
        }
    }
    @Published private(set) var persistenceErrorEvent: PersistenceErrorEvent?

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private var canPersist = false
    private(set) var lastPersistenceSucceeded: Bool = true

    init(userDefaults: UserDefaults = .standard, storageKey: String = "app_settings") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.settings = Self.loadSettings(from: userDefaults, using: storageKey)
        self.canPersist = true
    }

    var themeMode: ThemeMode {
        settings.themeMode
    }

    var showTimelineRing: Bool {
        settings.showTimelineRing
    }

    var summaryTimeFormat: SummaryTimeFormat {
        settings.summaryTimeFormat
    }

    var summaryMemoFormat: SummaryMemoFormat {
        settings.summaryMemoFormat
    }

    func setThemeMode(_ themeMode: ThemeMode) {
        guard settings.themeMode != themeMode else { return }
        settings.themeMode = themeMode
    }

    func setShowTimelineRing(_ isVisible: Bool) {
        guard settings.showTimelineRing != isVisible else { return }
        settings.showTimelineRing = isVisible
    }

    func setSummaryTimeFormat(_ format: SummaryTimeFormat) {
        guard settings.summaryTimeFormat != format else { return }
        settings.summaryTimeFormat = format
    }

    func setSummaryMemoFormat(_ format: SummaryMemoFormat) {
        guard settings.summaryMemoFormat != format else { return }
        settings.summaryMemoFormat = format
    }

    func update(_ settings: AppSettings) {
        guard self.settings != settings else { return }
        self.settings = settings
    }

    func resetToDefaults() {
        update(.default)
    }

    func consumePersistenceErrorEvent(id: UUID) {
        guard persistenceErrorEvent?.id == id else { return }
        persistenceErrorEvent = nil
    }

    private func persistIfNeeded() {
        guard canPersist else { return }
        do {
            try persist(settings, to: userDefaults, using: storageKey, encoder: encoder)
            lastPersistenceSucceeded = true
        } catch {
            lastPersistenceSucceeded = false
            persistenceErrorEvent = PersistenceErrorEvent(message: "設定の保存に失敗しました。")
        }
    }

    private static func loadSettings(from userDefaults: UserDefaults, using storageKey: String) -> AppSettings {
        guard
            let data = userDefaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    private func persist(
        _ settings: AppSettings,
        to userDefaults: UserDefaults,
        using storageKey: String,
        encoder: JSONEncoder
    ) throws {
        let data = try encoder.encode(settings)
        userDefaults.set(data, forKey: storageKey)
    }
}
