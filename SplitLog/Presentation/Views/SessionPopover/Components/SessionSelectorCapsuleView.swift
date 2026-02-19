//
//  SessionSelectorCapsuleView.swift
//  SplitLog
//
//  Created by Codex on 2026/02/19.
//

import SwiftUI

struct SessionSelectorCapsuleView: View {
    let sessions: [WorkSession]
    let selectedSessionID: UUID?
    @Binding var isShowingOverflowList: Bool
    let onSelectSession: (UUID) -> Void

    var body: some View {
        HStack(spacing: 4) {
            inlineArea
            overflowButton
        }
        .background(
            Capsule()
                .stroke(Color.primary.opacity(0.28), lineWidth: 1)
        )
        .onChange(of: sessions.count) { _, count in
            if count == 0 {
                isShowingOverflowList = false
            }
        }
    }

    @ViewBuilder
    private var inlineArea: some View {
        if sessions.isEmpty {
            Text("セッションなし")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(sessions) { session in
                        sessionChip(session)
                    }
                }
            }
            .frame(width: 220)
            .clipped()
        }
    }

    private func sessionChip(_ session: WorkSession) -> some View {
        let isSelected = selectedSessionID == session.id
        return Button {
            onSelectSession(session.id)
        } label: {
            Text(session.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 64, height: 22)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.primary.opacity(0.14) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .frame(width: 64)
    }

    private var overflowButton: some View {
        Button {
            isShowingOverflowList.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.10))
                VStack(spacing: 2) {
                    Circle().frame(width: 3, height: 3)
                    Circle().frame(width: 3, height: 3)
                    Circle().frame(width: 3, height: 3)
                }
                .foregroundStyle(Color.primary)
            }
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
        .zIndex(1)
        .disabled(sessions.isEmpty)
        .opacity(sessions.isEmpty ? 0.6 : 1)
        .help("セッション一覧")
    }
}
