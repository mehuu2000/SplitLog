//
//  SessionOverflowPanelView.swift
//  SplitLog
//
//  Created by Codex on 2026/02/19.
//

import SwiftUI

struct SessionOverflowPanelView: View {
    let sessions: [WorkSession]
    let selectedSessionID: UUID?
    let borderColor: Color
    let selectedRowColor: Color
    let defaultRowColor: Color
    let onSelectSession: (UUID) -> Void

    init(
        sessions: [WorkSession],
        selectedSessionID: UUID?,
        borderColor: Color = Color.primary.opacity(0.12),
        selectedRowColor: Color = Color.primary.opacity(0.14),
        defaultRowColor: Color = Color.primary.opacity(0.07),
        onSelectSession: @escaping (UUID) -> Void
    ) {
        self.sessions = sessions
        self.selectedSessionID = selectedSessionID
        self.borderColor = borderColor
        self.selectedRowColor = selectedRowColor
        self.defaultRowColor = defaultRowColor
        self.onSelectSession = onSelectSession
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(sessions) { listedSession in
                    sessionRow(listedSession)
                }
            }
        }
        .padding(10)
        .frame(width: 180, height: 260, alignment: .top)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private func sessionRow(_ session: WorkSession) -> some View {
        let isSelected = selectedSessionID == session.id
        return Button {
            onSelectSession(session.id)
        } label: {
            Text(session.title)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected ? selectedRowColor : defaultRowColor)
                )
        }
        .buttonStyle(.plain)
    }
}
