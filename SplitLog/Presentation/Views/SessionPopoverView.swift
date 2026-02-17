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
    private let ringBlockDuration: TimeInterval = 12 * 60 * 60

    var body: some View {
        let timeline = timelineSlices(referenceDate: stopwatch.clock)

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

            statusRow(title: "全体経過", value: formatDuration(stopwatch.elapsedSession()))

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
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(stopwatch.laps) { lap in
                                    let color = lapColor(for: lap.index)
                                    HStack {
                                        Text("\(lap.label)：")
                                            .foregroundStyle(color)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Text(formatDuration(stopwatch.elapsedLap(lap)))
                                            .monospacedDigit()
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
                    .disabled(stopwatch.state == .running)

                Button("ラップ終了", action: handleFinishLap)
                    .buttonStyle(.bordered)
                    .disabled(stopwatch.state != .running)

                Button("作業終了", action: handleFinishSession)
                    .buttonStyle(.bordered)
                    .disabled(stopwatch.state != .running)
            }
        }
        .padding(14)
        .frame(width: 540, height: 380)
        .background(.regularMaterial)
    }

    private var stateText: String {
        switch stopwatch.state {
        case .idle:
            "Idle"
        case .running:
            "Running"
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
        case .finished:
            "Finished"
        }
    }

    private func handleStart() {
        stopwatch.startSession()
    }

    private func handleFinishLap() {
        stopwatch.finishLap()
    }

    private func handleFinishSession() {
        stopwatch.finishSession()
    }

    private func timelineSlices(referenceDate: Date) -> (inner: [TimelineRingSlice], outer: [TimelineRingSlice], showOuterTrack: Bool) {
        guard let session = stopwatch.session else {
            return ([], [], false)
        }

        let elapsed = stopwatch.elapsedSession(at: referenceDate)
        guard elapsed > 0 else {
            return ([], [], false)
        }

        if elapsed < ringBlockDuration {
            let innerWindow = 0..<ringBlockDuration
            return (
                buildSlices(in: innerWindow, sessionStart: session.startedAt, referenceDate: referenceDate, windowID: "inner"),
                [],
                false
            )
        }

        let currentBlockStart = floor(elapsed / ringBlockDuration) * ringBlockDuration
        let innerWindow = (currentBlockStart - ringBlockDuration)..<currentBlockStart
        let outerWindow = currentBlockStart..<(currentBlockStart + ringBlockDuration)

        return (
            buildSlices(in: innerWindow, sessionStart: session.startedAt, referenceDate: referenceDate, windowID: "inner"),
            buildSlices(in: outerWindow, sessionStart: session.startedAt, referenceDate: referenceDate, windowID: "outer"),
            true
        )
    }

    private func buildSlices(
        in window: Range<TimeInterval>,
        sessionStart: Date,
        referenceDate: Date,
        windowID: String
    ) -> [TimelineRingSlice] {
        stopwatch.laps.compactMap { lap in
            let lapStart = max(0, lap.startedAt.timeIntervalSince(sessionStart))
            let rawLapEnd = (lap.endedAt ?? referenceDate).timeIntervalSince(sessionStart)
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
        let palette: [Color] = [
            .red,
            .green,
            .orange,
            .blue,
            .purple,
            .pink,
            .teal,
            .indigo,
            .mint,
            .brown,
        ]

        let paletteIndex = max(0, (index - 1) % palette.count)
        return palette[paletteIndex]
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
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
