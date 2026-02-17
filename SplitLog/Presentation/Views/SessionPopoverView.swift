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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("SplitLog", systemImage: "timer")
                    .font(.headline)
                Spacer()
                Text("Step 4")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Group {
                statusRow(title: "状態", value: stateText)
                statusRow(title: "全体経過", value: formatDuration(stopwatch.elapsedSession()))
                statusRow(title: "現在ラップ", value: formatDuration(stopwatch.elapsedCurrentLap()))
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
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

            Text(subtitleText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 340, height: 320)
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
            "開始するとラップ1から計測を開始します"
        case .running:
            "ラップ終了で次ラップへ。作業終了で確定します"
        case .finished:
            "計測完了。再度「作業開始」で新規セッションを開始できます"
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
