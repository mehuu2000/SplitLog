//
//  SessionConfirmationOverlayView.swift
//  SplitLog
//
//  Created by Codex on 2026/02/19.
//

import SwiftUI

struct SessionConfirmationOverlayView: View {
    let title: String
    let message: String
    let confirmButtonTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()

                    Button("キャンセル", action: onCancel)
                        .buttonStyle(.bordered)

                    Button(confirmButtonTitle, role: .destructive, action: onConfirm)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .frame(width: 320)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
    }
}
