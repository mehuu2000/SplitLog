//
//  SessionSettingsOverlayView.swift
//  SplitLog
//
//  Created by Codex on 2026/02/20.
//

import SwiftUI

struct SessionSettingsOverlayView: View {
    private enum StorageAction {
        case deleteSessionData
        case deleteLapData
        case resetSettings
        case initializeAllData

        var title: String {
            switch self {
            case .deleteSessionData:
                "セッション情報を削除しますか？"
            case .deleteLapData:
                "ラップ情報を削除しますか？"
            case .resetSettings:
                "設定を初期化しますか？"
            case .initializeAllData:
                "すべて初期化しますか？"
            }
        }

        var message: String {
            switch self {
            case .deleteSessionData:
                "全セッション・ラップ・メモを削除します。"
            case .deleteLapData:
                "全セッションのラップ・メモを削除します（セッション名は保持）。"
            case .resetSettings:
                "アプリ設定をすべてデフォルトに戻します。"
            case .initializeAllData:
                "全データと設定を削除して初期状態に戻します。"
            }
        }

        var confirmTitle: String {
            switch self {
            case .deleteSessionData:
                "削除"
            case .deleteLapData:
                "削除"
            case .resetSettings:
                "リセット"
            case .initializeAllData:
                "初期化"
            }
        }
    }

    @ObservedObject var settingsStore: AppSettingsStore
    let onDeleteSessionData: () -> Void
    let onDeleteLapData: () -> Void
    let onResetSettings: () -> Void
    let onInitializeAllData: () -> Void
    let onClose: () -> Void
    @State private var pendingStorageAction: StorageAction?

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 14) {
                Text("設定")
                    .font(.headline)

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("テーマカラー")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker(
                                "テーマカラー",
                                selection: Binding(
                                    get: { settingsStore.themeMode },
                                    set: { newValue in
                                        Task { @MainActor in
                                            settingsStore.setThemeMode(newValue)
                                        }
                                    }
                                )
                            ) {
                                Text("カラー")
                                    .tag(ThemeMode.color)
                                Text("モノクロ")
                                    .tag(ThemeMode.monochrome)
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("表示")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Toggle(
                                "経過時間の円を表示",
                                isOn: Binding(
                                    get: { settingsStore.showTimelineRing },
                                    set: { isVisible in
                                        Task { @MainActor in
                                            settingsStore.setShowTimelineRing(isVisible)
                                        }
                                    }
                                )
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("サマリー表示")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                Text("メモ表示形式")
                                Spacer()
                                Picker(
                                    "メモ表示形式",
                                    selection: Binding(
                                        get: { settingsStore.summaryMemoFormat },
                                        set: { newValue in
                                            Task { @MainActor in
                                                settingsStore.setSummaryMemoFormat(newValue)
                                            }
                                        }
                                    )
                                ) {
                                    Text("- メモ")
                                        .tag(SummaryMemoFormat.bulleted)
                                    Text("メモ")
                                        .tag(SummaryMemoFormat.plain)
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }

                            HStack {
                                Text("時間表示形式")
                                Spacer()
                                Picker(
                                    "時間表示形式",
                                    selection: Binding(
                                        get: { settingsStore.summaryTimeFormat },
                                        set: { newValue in
                                            Task { @MainActor in
                                                settingsStore.setSummaryTimeFormat(newValue)
                                            }
                                        }
                                    )
                                ) {
                                    Text("N.Mh")
                                        .tag(SummaryTimeFormat.decimalHours)
                                    Text("N時間M分")
                                        .tag(SummaryTimeFormat.hourMinute)
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("ストレージ管理")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            storageActionRow(
                                title: "セッション情報",
                                systemImage: "trash",
                                destructive: true
                            ) {
                                pendingStorageAction = .deleteSessionData
                            }

                            storageActionRow(
                                title: "ラップ情報",
                                systemImage: "trash",
                                destructive: true
                            ) {
                                pendingStorageAction = .deleteLapData
                            }

                            storageActionRow(
                                title: "設定の初期化",
                                systemImage: "arrow.counterclockwise",
                                destructive: false
                            ) {
                                pendingStorageAction = .resetSettings
                            }

                            storageActionRow(
                                title: "初期化",
                                systemImage: "exclamationmark.triangle",
                                destructive: true
                            ) {
                                pendingStorageAction = .initializeAllData
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 260)

                HStack {
                    Spacer()
                    Button("閉じる", action: onClose)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .frame(width: 360, height: 360)
            .tint(settingsStore.themeMode == .monochrome ? Color(white: 0.25) : .accentColor)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )

            if let action = pendingStorageAction {
                SessionConfirmationOverlayView(
                    title: action.title,
                    message: action.message,
                    confirmButtonTitle: action.confirmTitle,
                    isMonochrome: settingsStore.themeMode == .monochrome,
                    onCancel: {
                        pendingStorageAction = nil
                    },
                    onConfirm: {
                        performStorageAction(action)
                        pendingStorageAction = nil
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func storageActionRow(
        title: String,
        systemImage: String,
        destructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
            Spacer()

            if destructive {
                Button(role: .destructive, action: action) {
                    Image(systemName: systemImage)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 8))
            } else {
                Button(action: action) {
                    Image(systemName: systemImage)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 8))
            }
        }
    }

    private func performStorageAction(_ action: StorageAction) {
        switch action {
        case .deleteSessionData:
            onDeleteSessionData()
        case .deleteLapData:
            onDeleteLapData()
        case .resetSettings:
            onResetSettings()
        case .initializeAllData:
            onInitializeAllData()
        }
    }
}
