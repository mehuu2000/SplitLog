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
    let onSelectSession: (UUID) -> Void

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
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
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
                        .fill(isSelected ? Color.primary.opacity(0.14) : Color.primary.opacity(0.07))
                )
        }
        .buttonStyle(.plain)
    }
}
