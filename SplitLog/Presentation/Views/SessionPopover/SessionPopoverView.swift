//
//  SessionPopoverView.swift
//  SplitLog
//
//  Created by 濱田真仁 on 2026/02/17.
//

import SwiftUI

@MainActor
struct SessionPopoverView: View {
    private static let rgbWheel: [(Double, Double, Double)] = [
        (255, 0, 0),
        (255, 64, 0),
        (255, 128, 0),
        (255, 192, 0),
        (255, 255, 0),
        (192, 255, 0),
        (128, 255, 0),
        (64, 255, 0),
        (0, 255, 0),
        (0, 255, 64),
        (0, 255, 128),
        (0, 255, 192),
        (0, 255, 255),
        (0, 192, 255),
        (0, 128, 255),
        (0, 64, 255),
        (0, 0, 255),
        (64, 0, 255),
        (128, 0, 255),
        (192, 0, 255),
        (255, 0, 255),
        (255, 0, 192),
        (255, 0, 128),
        (255, 0, 64),
    ]

    @StateObject private var stopwatch = StopwatchService()
    @State private var editingLapID: UUID?
    @State private var editingLapLabelDraft = ""
    @State private var editingFocusToken: Int = 0
    @State private var isShowingResetConfirmation = false
    @State private var isShowingDeleteSessionConfirmation = false
    @State private var isShowingSessionOverflowList = false
    // Temporary for UI verification: 1 ring = 30 seconds (instead of 12 hours)
    private let ringBlockDuration: TimeInterval = 30

    var body: some View {
        let referenceDate = stopwatch.clock
        let timeline = timelineSlices(referenceDate: referenceDate)
        let totalElapsedSeconds = durationSeconds(stopwatch.elapsedSession(at: referenceDate))
        let lapDisplayedSeconds = displayedLapSeconds(referenceDate: referenceDate)

        ZStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("SplitLog", systemImage: "timer")
                        .font(.headline)
                    Spacer()

                    HStack(spacing: 8) {
                        SessionSelectorCapsuleView(
                            sessions: stopwatch.sessions,
                            selectedSessionID: stopwatch.selectedSessionID,
                            isShowingOverflowList: $isShowingSessionOverflowList,
                            onSelectSession: { sessionID in
                                handleSelectSession(sessionID: sessionID)
                            }
                        )

                        Button(action: handleAddSession) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 24, height: 24)
                                .background(
                                    Circle()
                                        .fill(Color.primary.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("セッション追加")
                        .accessibilityLabel("セッション追加")
                    }
                }

                Divider()

                StatusRowView(
                    title: "全体経過",
                    value: formatDuration(seconds: totalElapsedSeconds)
                )

                HStack(alignment: .top, spacing: 16) {
                    SessionTimelineRingView(
                        innerSlices: timeline.inner,
                        outerSlices: timeline.outer,
                        showOuterTrack: timeline.showOuterTrack
                    )
                    .frame(width: 210, height: 210)

                    SessionLapListView(
                        laps: stopwatch.laps,
                        selectedLapID: stopwatch.selectedLapID,
                        lapDisplayedSeconds: lapDisplayedSeconds,
                        subtitleText: subtitleText,
                        editingLapID: $editingLapID,
                        editingLapLabelDraft: $editingLapLabelDraft,
                        editingFocusToken: editingFocusToken,
                        formatDuration: { formatDuration(seconds: $0) },
                        colorForLap: { lapColor(for: $0) },
                        onSelectLap: { lapID in
                            handleSelectLap(lapID: lapID)
                        },
                        onBeginLapLabelEdit: { lap in
                            beginLapLabelEdit(for: lap)
                        },
                        onCommitLapLabelEdit: { lapID in
                            commitLapLabelEdit(lapID: lapID)
                        }
                    )
                }

                Spacer(minLength: 8)

                HStack {
                    HStack(spacing: 10) {
                        Button(primaryActionButtonTitle, action: handlePrimaryAction)
                            .buttonStyle(.borderedProminent)

                        Button("ラップ終了", action: handleFinishLap)
                            .buttonStyle(.bordered)
                            .disabled(stopwatch.state != .running)
                    }

                    Spacer()

                    Button(action: requestReset) {
                        Image(systemName: "arrow.counterclockwise")
                            .frame(width: 14, height: 14)
                    }
                    .frame(width: 32, height: 32)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 8))
                    .help("リセット")
                    .accessibilityLabel("リセット")
                    .disabled(stopwatch.session == nil)

                    Button(action: requestDeleteSession) {
                        Image(systemName: "trash")
                            .frame(width: 14, height: 14)
                    }
                    .frame(width: 32, height: 32)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 8))
                    .help("現在セッションを削除")
                    .accessibilityLabel("現在セッションを削除")
                    .disabled(stopwatch.session == nil)
                }
            }

            if isShowingSessionOverflowList {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        isShowingSessionOverflowList = false
                    }

                VStack {
                    HStack {
                        Spacer()
                        SessionOverflowPanelView(
                            sessions: stopwatch.sessions,
                            selectedSessionID: stopwatch.selectedSessionID,
                            onSelectSession: { sessionID in
                                isShowingSessionOverflowList = false
                                handleSelectSession(sessionID: sessionID)
                            }
                        )
                    }
                    Spacer()
                }
                .padding(.top, 46)
                .padding(.trailing, 26)
            }

            if isShowingResetConfirmation || isShowingDeleteSessionConfirmation {
                SessionConfirmationOverlayView(
                    title: isShowingDeleteSessionConfirmation ? "セッションを削除しますか？" : "リセットしますか？",
                    message: isShowingDeleteSessionConfirmation
                        ? "現在表示中のセッションを削除します。"
                        : "現在表示中のセッションとラップを初期状態に戻します。",
                    confirmButtonTitle: isShowingDeleteSessionConfirmation ? "削除" : "リセット",
                    onCancel: {
                        isShowingResetConfirmation = false
                        isShowingDeleteSessionConfirmation = false
                    },
                    onConfirm: {
                        let isDeleteAction = isShowingDeleteSessionConfirmation
                        isShowingResetConfirmation = false
                        isShowingDeleteSessionConfirmation = false
                        if isDeleteAction {
                            handleDeleteSession()
                        } else {
                            handleReset()
                        }
                    }
                )
            }
        }
        .padding(14)
        .frame(width: 540, height: 380)
        .background(.regularMaterial)
        .onAppear {
            stopwatch.setDisplayActive(true)
        }
        .onDisappear {
            commitActiveLapLabelEditIfNeeded()
            stopwatch.setDisplayActive(false)
        }
    }

    private var subtitleText: String {
        guard !stopwatch.laps.isEmpty else { return "" }
        return stopwatchStateText
    }

    private var stopwatchStateText: String {
        switch stopwatch.state {
        case .idle:
            "Idle"
        case .running:
            "Running"
        case .paused:
            "Paused"
        case .stopped:
            "Stopped"
        case .finished:
            "Finished"
        }
    }

    private var primaryActionButtonTitle: String {
        switch stopwatch.state {
        case .idle, .finished:
            "作業開始"
        case .running, .paused:
            "作業終了"
        case .stopped:
            "作業再開"
        }
    }

    private func handlePrimaryAction() {
        commitActiveLapLabelEditIfNeeded()

        if stopwatch.state == .stopped {
            stopwatch.resumeSession()
            return
        }

        if stopwatch.state == .running || stopwatch.state == .paused {
            stopwatch.finishSession()
            return
        }

        stopwatch.startSession()
    }

    private func handleFinishLap() {
        commitActiveLapLabelEditIfNeeded()
        stopwatch.finishLap()
    }

    private func handleAddSession() {
        commitActiveLapLabelEditIfNeeded()
        stopwatch.addSession()
    }

    private func handleSelectSession(sessionID: UUID) {
        commitActiveLapLabelEditIfNeeded()
        stopwatch.selectSession(sessionID: sessionID)
    }

    private func handleSelectLap(lapID: UUID) {
        commitActiveLapLabelEditIfNeeded()
        stopwatch.selectLap(lapID: lapID)
    }

    private func requestReset() {
        isShowingDeleteSessionConfirmation = false
        isShowingResetConfirmation = true
    }

    private func requestDeleteSession() {
        isShowingResetConfirmation = false
        isShowingDeleteSessionConfirmation = true
    }

    private func handleReset() {
        commitActiveLapLabelEditIfNeeded()
        stopwatch.resetSelectedSession()
    }

    private func handleDeleteSession() {
        commitActiveLapLabelEditIfNeeded()
        stopwatch.deleteSelectedSession()
    }

    private func beginLapLabelEdit(for lap: WorkLap) {
        if let activeLapID = editingLapID, activeLapID != lap.id {
            commitLapLabelEdit(lapID: activeLapID)
        }

        editingLapID = lap.id
        editingLapLabelDraft = lap.label
        editingFocusToken += 1
    }

    private func commitLapLabelEdit(lapID: UUID) {
        guard editingLapID == lapID else { return }
        stopwatch.updateLapLabel(lapID: lapID, label: editingLapLabelDraft)

        editingLapID = nil
        editingLapLabelDraft = ""
    }

    private func commitActiveLapLabelEditIfNeeded() {
        guard let lapID = editingLapID else { return }
        commitLapLabelEdit(lapID: lapID)
    }

    private func timelineSlices(referenceDate: Date) -> (inner: [TimelineRingSlice], outer: [TimelineRingSlice], showOuterTrack: Bool) {
        guard stopwatch.session != nil else {
            return ([], [], false)
        }

        let elapsed = stopwatch.elapsedSession(at: referenceDate)
        guard elapsed > 0 else {
            return ([], [], false)
        }

        let lapRanges = lapCumulativeRanges(referenceDate: referenceDate)

        if elapsed < ringBlockDuration {
            let innerWindow = 0..<ringBlockDuration
            return (
                buildSlices(in: innerWindow, lapRanges: lapRanges, windowID: "inner"),
                [],
                false
            )
        }

        let currentBlockStart = floor(elapsed / ringBlockDuration) * ringBlockDuration
        let innerWindow = (currentBlockStart - ringBlockDuration)..<currentBlockStart
        let outerWindow = currentBlockStart..<(currentBlockStart + ringBlockDuration)

        return (
            buildSlices(in: innerWindow, lapRanges: lapRanges, windowID: "inner"),
            buildSlices(in: outerWindow, lapRanges: lapRanges, windowID: "outer"),
            true
        )
    }

    private func lapCumulativeRanges(referenceDate: Date) -> [(lap: WorkLap, start: TimeInterval, end: TimeInterval)] {
        var ranges: [(lap: WorkLap, start: TimeInterval, end: TimeInterval)] = []
        var cursor: TimeInterval = 0

        for lap in stopwatch.laps {
            let duration = max(0, stopwatch.elapsedLap(lap, at: referenceDate))
            let start = cursor
            let end = start + duration
            ranges.append((lap: lap, start: start, end: end))
            cursor = end
        }

        return ranges
    }

    private func buildSlices(
        in window: Range<TimeInterval>,
        lapRanges: [(lap: WorkLap, start: TimeInterval, end: TimeInterval)],
        windowID: String
    ) -> [TimelineRingSlice] {
        lapRanges.compactMap { range in
            let start = max(range.start, window.lowerBound)
            let end = min(range.end, window.upperBound)

            guard end > start else { return nil }

            let startRatio = (start - window.lowerBound) / ringBlockDuration
            let endRatio = (end - window.lowerBound) / ringBlockDuration

            return TimelineRingSlice(
                id: "\(windowID)-\(range.lap.id)-\(startRatio)-\(endRatio)",
                startRatio: startRatio,
                endRatio: endRatio,
                color: lapColor(for: range.lap.index)
            )
        }
    }

    private func lapColor(for index: Int) -> Color {
        let zeroBasedIndex = max(0, index - 1)
        let cycle = zeroBasedIndex / Self.rgbWheel.count
        let paletteIndex = (zeroBasedIndex + cycle) % Self.rgbWheel.count
        let rgb = Self.rgbWheel[paletteIndex]

        return Color(
            red: rgb.0 / 255.0,
            green: rgb.1 / 255.0,
            blue: rgb.2 / 255.0
        )
    }

    private func displayedLapSeconds(referenceDate: Date) -> [UUID: Int] {
        Dictionary(
            uniqueKeysWithValues: stopwatch.laps.map { lap in
                (lap.id, durationSeconds(stopwatch.elapsedLap(lap, at: referenceDate)))
            }
        )
    }

    private func formatDuration(seconds totalSeconds: Int) -> String {
        let totalSeconds = max(0, totalSeconds)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func durationSeconds(_ duration: TimeInterval) -> Int {
        max(0, Int(duration.rounded(.down)))
    }
}

struct SessionPopoverView_Previews: PreviewProvider {
    static var previews: some View {
        SessionPopoverView()
    }
}
