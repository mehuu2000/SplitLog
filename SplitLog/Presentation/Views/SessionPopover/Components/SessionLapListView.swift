//
//  SessionLapListView.swift
//  SplitLog
//
//  Created by Codex on 2026/02/19.
//

import SwiftUI

struct SessionLapListView: View {
    let laps: [WorkLap]
    let selectedLapID: UUID?
    let lapDisplayedSeconds: [UUID: Int]
    let subtitleText: String
    let subtitleColor: Color
    let rowPrimaryTextColor: Color
    let rowSecondaryIconColor: Color
    let inlineEditorBackgroundColor: Color
    @Binding var editingLapID: UUID?
    @Binding var editingLapLabelDraft: String
    let editingFocusToken: Int
    let formatDuration: (Int) -> String
    let colorForLap: (Int) -> Color
    let onSelectLap: (UUID) -> Void
    let onOpenMemo: (WorkLap) -> Void
    let onBeginLapLabelEdit: (WorkLap) -> Void
    let onCommitLapLabelEdit: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if laps.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ラップはまだありません")
                        .foregroundStyle(subtitleColor)
                        .font(.subheadline)
                    Text("作業を開始して下さい")
                        .foregroundStyle(subtitleColor)
                        .font(.caption)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(laps) { lap in
                                SessionLapRowView(
                                    lap: lap,
                                    selectedLapID: selectedLapID,
                                    displayedSeconds: lapDisplayedSeconds[lap.id] ?? 0,
                                    isEditing: editingLapID == lap.id,
                                    editingText: $editingLapLabelDraft,
                                    editingFocusToken: editingFocusToken,
                                    formatDuration: formatDuration,
                                    color: colorForLap(lap.index),
                                    primaryTextColor: rowPrimaryTextColor,
                                    secondaryIconColor: rowSecondaryIconColor,
                                    inlineEditorBackgroundColor: inlineEditorBackgroundColor,
                                    onSelectLap: {
                                        onSelectLap(lap.id)
                                    },
                                    onOpenMemo: {
                                        onOpenMemo(lap)
                                    },
                                    onBeginEdit: {
                                        onBeginLapLabelEdit(lap)
                                    },
                                    onCommitEdit: {
                                        onCommitLapLabelEdit(lap.id)
                                    }
                                )
                                .id(lap.id)
                            }
                        }
                    }
                    .onChange(of: laps.count) { _, _ in
                        guard let lastID = laps.last?.id else { return }
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            if !subtitleText.isEmpty {
                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(subtitleColor)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct SessionLapRowView: View {
    let lap: WorkLap
    let selectedLapID: UUID?
    let displayedSeconds: Int
    let isEditing: Bool
    @Binding var editingText: String
    let editingFocusToken: Int
    let formatDuration: (Int) -> String
    let color: Color
    let primaryTextColor: Color
    let secondaryIconColor: Color
    let inlineEditorBackgroundColor: Color
    let onSelectLap: () -> Void
    let onOpenMemo: () -> Void
    let onBeginEdit: () -> Void
    let onCommitEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Button(action: onSelectLap) {
                    Image(systemName: selectedLapID == lap.id ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(primaryTextColor)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())

                if isEditing {
                    InlineLapLabelEditor(
                        text: $editingText,
                        focusToken: editingFocusToken,
                        onCommit: onCommitEdit
                    )
                    .frame(minWidth: 96, maxWidth: 220, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(inlineEditorBackgroundColor)
                    )
                } else {
                    Text("\(lap.label)：")
                        .fontWeight(.medium)
                        .foregroundStyle(primaryTextColor)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onBeginEdit)
                }

                Spacer()

                Button(action: onOpenMemo) {
                    Image(systemName: "note.text")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(secondaryIconColor)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())

                Text(formatDuration(displayedSeconds))
                    .monospacedDigit()
                    .foregroundStyle(primaryTextColor)
            }

            Rectangle()
                .fill(color)
                .frame(height: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1))
        }
    }
}
