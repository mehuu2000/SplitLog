//
//  SessionLapMemoOverlayView.swift
//  SplitLog
//
//  Created by Codex on 2026/02/20.
//

import SwiftUI

struct SessionLapMemoOverlayView: View {
    @Binding var lapLabel: String
    let elapsedText: String
    @Binding var memoText: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Text("Splitメモ")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Split名")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Split名", text: $lapLabel)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 10) {
                    Text("経過時間")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(elapsedText)
                        .monospacedDigit()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("メモ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $memoText)
                        .font(.body)
                        .frame(minHeight: 120)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.7))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
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
