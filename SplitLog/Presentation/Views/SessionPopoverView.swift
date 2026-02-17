//
//  SessionPopoverView.swift
//  SplitLog
//
//  Created by 濱田真仁 on 2026/02/17.
//

import SwiftUI

@MainActor
struct SessionPopoverView: View {
    @StateObject private var stopwatch = StopwatchService()
    // Temporary for UI verification: 1 ring = 30 seconds (instead of 12 hours)
    private let ringBlockDuration: TimeInterval = 30

    var body: some View {
        let referenceDate = stopwatch.clock
        let timeline = timelineSlices(referenceDate: referenceDate)
        let totalElapsedSeconds = durationSeconds(stopwatch.elapsedSession(at: referenceDate))
        let lapDisplayedSeconds = displayedLapSeconds(referenceDate: referenceDate, totalElapsedSeconds: totalElapsedSeconds)

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
                                                Text("\(lap.label)：")
                                                    .fontWeight(.medium)
                                                    .foregroundStyle(Color.black)
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

            HStack(spacing: 10) {
                Button("作業開始", action: handleStart)
                    .buttonStyle(.borderedProminent)
                    .disabled(stopwatch.state == .running || stopwatch.state == .paused)

                Button(pauseButtonTitle, action: handlePauseResume)
                    .buttonStyle(.bordered)
                    .disabled(stopwatch.state != .running && stopwatch.state != .paused)

                Button("ラップ終了", action: handleFinishLap)
                    .buttonStyle(.bordered)
                    .disabled(stopwatch.state != .running)

                Button("作業終了", action: handleFinishSession)
                    .buttonStyle(.bordered)
                    .disabled(stopwatch.state == .idle || stopwatch.state == .finished)
            }
        }
        .padding(14)
        .frame(width: 540, height: 380)
        .background(.regularMaterial)
        .onAppear {
            stopwatch.setDisplayActive(true)
        }
        .onDisappear {
            stopwatch.setDisplayActive(false)
        }
    }

    private var stateText: String {
        switch stopwatch.state {
        case .idle:
            "Idle"
        case .running:
            "Running"
        case .paused:
            "Paused"
        case .finished:
            "Finished"
        }
    }

    private var subtitleText: String {
        switch stopwatch.state {
        case .idle:
            "Idle"
        case .running:
            "Running"
        case .paused:
            "Paused"
        case .finished:
            "Finished"
        }
    }

    private var pauseButtonTitle: String {
        stopwatch.state == .paused ? "再開" : "一時停止"
    }

    private func handleStart() {
        stopwatch.startSession()
    }

    private func handleFinishLap() {
        stopwatch.finishLap()
    }

    private func handlePauseResume() {
        if stopwatch.state == .running {
            stopwatch.pauseSession()
            return
        }

        if stopwatch.state == .paused {
            stopwatch.resumeSession()
        }
    }

    private func handleFinishSession() {
        stopwatch.finishSession()
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
