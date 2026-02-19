//
//  SessionPopoverView.swift
//  SplitLog
//
//  Created by 濱田真仁 on 2026/02/17.
//

import AppKit
import SwiftUI

@MainActor
struct SessionPopoverView: View {
    @StateObject private var stopwatch = StopwatchService()
    @State private var editingLapID: UUID?
    @State private var editingLapLabelDraft = ""
    @State private var editingFocusToken: Int = 0
    @State private var isShowingResetConfirmation = false
    // Temporary for UI verification: 1 ring = 30 seconds (instead of 12 hours)
    private let ringBlockDuration: TimeInterval = 30

    var body: some View {
        let referenceDate = stopwatch.clock
        let timeline = timelineSlices(referenceDate: referenceDate)
        let totalElapsedSeconds = durationSeconds(stopwatch.elapsedSession(at: referenceDate))
        let lapDisplayedSeconds = displayedLapSeconds(referenceDate: referenceDate, totalElapsedSeconds: totalElapsedSeconds)

        ZStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("SplitLog", systemImage: "timer")
                        .font(.headline)
                    Spacer()
                    Text(stateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                statusRow(title: "全体経過", value: formatDuration(seconds: totalElapsedSeconds))

                HStack(alignment: .top, spacing: 16) {
                    SessionTimelineRingView(
                        innerSlices: timeline.inner,
                        outerSlices: timeline.outer,
                        showOuterTrack: timeline.showOuterTrack
                    )
                    .frame(width: 210, height: 210)

                    VStack(alignment: .leading, spacing: 8) {
                        if stopwatch.laps.isEmpty {
                            Text("ラップはまだありません")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        } else {
                            ScrollViewReader { proxy in
                                ScrollView(showsIndicators: false) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(stopwatch.laps) { lap in
                                            let color = lapColor(for: lap.index)
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack {
                                                    if editingLapID == lap.id {
                                                        InlineLapLabelEditor(
                                                            text: $editingLapLabelDraft,
                                                            focusToken: editingFocusToken,
                                                            onCommit: {
                                                                commitLapLabelEdit(lapID: lap.id)
                                                            }
                                                        )
                                                        .frame(minWidth: 96, maxWidth: 220, alignment: .leading)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(
                                                            RoundedRectangle(cornerRadius: 4)
                                                                .fill(Color.white.opacity(0.9))
                                                        )
                                                    } else {
                                                        Text("\(lap.label)：")
                                                            .fontWeight(.medium)
                                                            .foregroundStyle(Color.black)
                                                            .contentShape(Rectangle())
                                                            .onTapGesture {
                                                                beginLapLabelEdit(for: lap)
                                                            }
                                                    }

                                                    Spacer()
                                                    Text(formatDuration(seconds: lapDisplayedSeconds[lap.id] ?? 0))
                                                        .monospacedDigit()
                                                        .foregroundStyle(Color.black)
                                                }

                                                Rectangle()
                                                    .fill(color)
                                                    .frame(height: 2)
                                                    .clipShape(RoundedRectangle(cornerRadius: 1))
                                            }
                                            .id(lap.id)
                                        }
                                    }
                                }
                                .onChange(of: stopwatch.laps.count) { _, _ in
                                    guard let lastID = stopwatch.laps.last?.id else { return }
                                    DispatchQueue.main.async {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            proxy.scrollTo(lastID, anchor: .bottom)
                                        }
                                    }
                                }
                            }
                        }

                        Text(subtitleText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
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
                    .disabled(stopwatch.state == .idle)
                }
            }

            if isShowingResetConfirmation {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        isShowingResetConfirmation = false
                    }

                VStack(alignment: .leading, spacing: 12) {
                    Text("リセットしますか？")
                        .font(.headline)
                    Text("現在のセッションとラップを初期状態に戻します。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Spacer()
                        Button("キャンセル") {
                            isShowingResetConfirmation = false
                        }
                        .buttonStyle(.bordered)

                        Button("リセット", role: .destructive) {
                            isShowingResetConfirmation = false
                            handleReset()
                        }
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

    private var stateText: String {
        stopwatchStateText
    }

    private var subtitleText: String {
        stopwatchStateText
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

    private func requestReset() {
        isShowingResetConfirmation = true
    }

    private func handleReset() {
        commitActiveLapLabelEditIfNeeded()
        stopwatch.resetToIdle()
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

        if elapsed < ringBlockDuration {
            let innerWindow = 0..<ringBlockDuration
            return (
                buildSlices(in: innerWindow, referenceDate: referenceDate, windowID: "inner"),
                [],
                false
            )
        }

        let currentBlockStart = floor(elapsed / ringBlockDuration) * ringBlockDuration
        let innerWindow = (currentBlockStart - ringBlockDuration)..<currentBlockStart
        let outerWindow = currentBlockStart..<(currentBlockStart + ringBlockDuration)

        return (
            buildSlices(in: innerWindow, referenceDate: referenceDate, windowID: "inner"),
            buildSlices(in: outerWindow, referenceDate: referenceDate, windowID: "outer"),
            true
        )
    }

    private func buildSlices(
        in window: Range<TimeInterval>,
        referenceDate: Date,
        windowID: String
    ) -> [TimelineRingSlice] {
        stopwatch.laps.compactMap { lap in
            let lapStart = max(0, stopwatch.activeTimelineOffset(at: lap.startedAt))
            let rawLapEnd = stopwatch.activeTimelineOffset(at: lap.endedAt ?? referenceDate)
            let lapEnd = max(lapStart, rawLapEnd)

            let start = max(lapStart, window.lowerBound)
            let end = min(lapEnd, window.upperBound)

            guard end > start else { return nil }

            let startRatio = (start - window.lowerBound) / ringBlockDuration
            let endRatio = (end - window.lowerBound) / ringBlockDuration

            return TimelineRingSlice(
                id: "\(windowID)-\(lap.id)-\(startRatio)-\(endRatio)",
                startRatio: startRatio,
                endRatio: endRatio,
                color: lapColor(for: lap.index)
            )
        }
    }

    private func lapColor(for index: Int) -> Color {
        let rgbWheel: [(Double, Double, Double)] = [
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

        let zeroBasedIndex = max(0, index - 1)
        let cycle = zeroBasedIndex / rgbWheel.count
        let paletteIndex = (zeroBasedIndex + cycle) % rgbWheel.count
        let rgb = rgbWheel[paletteIndex]

        return Color(
            red: rgb.0 / 255.0,
            green: rgb.1 / 255.0,
            blue: rgb.2 / 255.0
        )
    }

    private func displayedLapSeconds(referenceDate: Date, totalElapsedSeconds: Int) -> [UUID: Int] {
        var secondsByLapID: [UUID: Int] = [:]
        var completedTotalSeconds = 0

        for lap in stopwatch.laps {
            if lap.endedAt != nil {
                let lapSeconds = durationSeconds(stopwatch.elapsedLap(lap, at: referenceDate))
                secondsByLapID[lap.id] = lapSeconds
                completedTotalSeconds += lapSeconds
                continue
            }

            secondsByLapID[lap.id] = max(0, totalElapsedSeconds - completedTotalSeconds)
        }

        return secondsByLapID
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

    @ViewBuilder
    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.body)
    }
}

struct SessionPopoverView_Previews: PreviewProvider {
    static var previews: some View {
        SessionPopoverView()
    }
}

private struct InlineLapLabelEditor: NSViewRepresentable {
    @Binding var text: String
    let focusToken: Int
    let onCommit: () -> Void

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineLapLabelEditor
        weak var textField: NSTextField?
        private var outsideClickMonitor: Any?
        private var activeFocusRequestToken: Int = -1
        private var isOutsideCommitEnabled = false

        init(parent: InlineLapLabelEditor) {
            self.parent = parent
        }

        deinit {
            removeOutsideClickMonitor()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isOutsideCommitEnabled = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            removeOutsideClickMonitor()
            parent.onCommit()
        }

        func installOutsideClickMonitor() {
            guard outsideClickMonitor == nil else { return }

            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self else { return event }
                guard
                    let field = self.textField,
                    let window = field.window
                else {
                    // Ignore clicks while the editor is not attached yet.
                    return event
                }

                // Ignore clicks until initial focus is actually established.
                guard self.isOutsideCommitEnabled else {
                    return event
                }

                guard event.window === window else { return event }

                let pointInField = field.convert(event.locationInWindow, from: nil)
                if field.bounds.contains(pointInField) {
                    return event
                }

                if let editor = field.currentEditor() {
                    let pointInEditor = editor.convert(event.locationInWindow, from: nil)
                    if editor.bounds.contains(pointInEditor) {
                        return event
                    }
                    window.makeFirstResponder(nil)
                    return event
                }

                self.parent.onCommit()
                return event
            }
        }

        func requestInitialFocusIfNeeded(on field: NSTextField, token: Int) {
            guard activeFocusRequestToken != token else { return }
            activeFocusRequestToken = token
            isOutsideCommitEnabled = false
            requestFocus(on: field, token: token, remainingRetries: 8)
        }

        private func requestFocus(on field: NSTextField, token: Int, remainingRetries: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self, weak field] in
                guard let self, let field else { return }
                guard self.parent.focusToken == token else { return }

                if let window = field.window, window.makeFirstResponder(field) {
                    self.isOutsideCommitEnabled = true
                    return
                }

                guard remainingRetries > 0 else { return }
                self.requestFocus(on: field, token: token, remainingRetries: remainingRetries - 1)
            }
        }

        func removeOutsideClickMonitor() {
            guard let outsideClickMonitor else { return }
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.maximumNumberOfLines = 1
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        field.textColor = .black
        context.coordinator.textField = field
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.installOutsideClickMonitor()

        if nsView.currentEditor() == nil, nsView.stringValue != text {
            nsView.stringValue = text
        }

        context.coordinator.requestInitialFocusIfNeeded(on: nsView, token: focusToken)
    }
}
