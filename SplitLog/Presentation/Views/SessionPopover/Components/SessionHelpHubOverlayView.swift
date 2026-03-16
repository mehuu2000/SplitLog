//
//  SessionHelpHubOverlayView.swift
//  SplitLog
//
//  Created by Codex on 2026/03/16.
//

import SwiftUI

struct SessionHelpHubOverlayView: View {
    let onOpenOperationGuide: () -> Void
    let onOpenContact: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("案内")
                        .font(.headline)

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("閉じる")
                }

                VStack(alignment: .leading, spacing: 10) {
                    helpCard(
                        title: "操作説明",
                        subtitle: "このアプリでできることと使い方を確認",
                        systemImage: "questionmark",
                        accentColor: Color.accentColor,
                        action: onOpenOperationGuide
                    )

                    helpCard(
                        title: "お問い合わせ",
                        subtitle: "不具合報告や相談用の導線",
                        systemImage: "envelope",
                        accentColor: Color.accentColor,
                        action: onOpenContact
                    )
                }
            }
            .padding(16)
            .frame(width: 300)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
        }
    }

    private func helpCard(
        title: String,
        subtitle: String,
        systemImage: String,
        accentColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accentColor.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accentColor.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

}
