//
//  SessionTimelineRingView.swift
//  SplitLog
//
//  Created by Codex on 2026/02/17.
//

import SwiftUI

struct TimelineRingSlice: Identifiable {
    let id: String
    let startRatio: Double
    let endRatio: Double
    let color: Color
}

struct SessionTimelineRingView: View {
    let innerSlices: [TimelineRingSlice]
    let outerSlices: [TimelineRingSlice]
    let showOuterTrack: Bool

    private let innerLineWidth: CGFloat = 34
    private let outerLineWidth: CGFloat = 26

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let innerSide = max(0, side - 56)
            let trackColor = Color.primary.opacity(0.1)

            ZStack {
                if showOuterTrack {
                    Circle()
                        .stroke(trackColor, lineWidth: outerLineWidth)
                        .frame(width: side, height: side)

                    ForEach(outerSlices) { slice in
                        Circle()
                            .trim(from: clampedRatio(slice.startRatio), to: clampedRatio(slice.endRatio))
                            .stroke(slice.color, style: StrokeStyle(lineWidth: outerLineWidth, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                            .frame(width: side, height: side)
                    }
                }

                Circle()
                    .stroke(trackColor, lineWidth: innerLineWidth)
                    .frame(width: innerSide, height: innerSide)

                ForEach(innerSlices) { slice in
                    Circle()
                        .trim(from: clampedRatio(slice.startRatio), to: clampedRatio(slice.endRatio))
                        .stroke(slice.color, style: StrokeStyle(lineWidth: innerLineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .frame(width: innerSide, height: innerSide)
                }
            }
            .frame(width: side, height: side)
        }
    }

    private func clampedRatio(_ ratio: Double) -> CGFloat {
        CGFloat(min(1, max(0, ratio)))
    }
}

#Preview {
    SessionTimelineRingView(
        innerSlices: [
            TimelineRingSlice(id: "1", startRatio: 0.0, endRatio: 0.25, color: .red),
            TimelineRingSlice(id: "2", startRatio: 0.25, endRatio: 0.5, color: .green),
            TimelineRingSlice(id: "3", startRatio: 0.5, endRatio: 0.75, color: .orange),
            TimelineRingSlice(id: "4", startRatio: 0.75, endRatio: 1.0, color: .blue),
        ],
        outerSlices: [
            TimelineRingSlice(id: "5", startRatio: 0.0, endRatio: 0.45, color: .purple),
        ],
        showOuterTrack: true
    )
    .frame(width: 220, height: 220)
    .padding()
}
