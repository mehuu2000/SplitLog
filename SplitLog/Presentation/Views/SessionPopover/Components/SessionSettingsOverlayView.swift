//
//  SessionSettingsOverlayView.swift
//  SplitLog
//
//  Created by Codex on 2026/02/20.
//

import SwiftUI

struct SessionSettingsOverlayView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 14) {
                Text("設定")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("テーマカラー")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker(
                        "テーマカラー",
                        selection: Binding(
                            get: { settingsStore.themeMode },
                            set: { settingsStore.setThemeMode($0) }
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
                            set: { settingsStore.setShowTimelineRing($0) }
                        )
                    )
                }

                HStack {
                    Spacer()
                    Button("閉じる", action: onClose)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .frame(width: 360)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
    }
}
