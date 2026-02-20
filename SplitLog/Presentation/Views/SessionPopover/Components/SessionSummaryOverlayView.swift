//
//  SessionSummaryOverlayView.swift
//  SplitLog
//
//  Created by Codex on 2026/02/20.
//

import SwiftUI

struct SessionSummaryOverlayView: View {
    @Binding var summaryText: String
    let onCopy: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("セッションまとめ")
                        .font(.headline)

                    Spacer()

                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .help("コピー")
                    .accessibilityLabel("コピー")
                }

                TextEditor(text: $summaryText)
                    .font(.body)
                    .frame(minHeight: 220)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.7))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )

                HStack {
                    Spacer()
                    Button("閉じる", action: onClose)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .frame(width: 400)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
    }
}
