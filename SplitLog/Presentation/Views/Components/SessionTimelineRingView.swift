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
                        RingArcShape(startRatio: slice.startRatio, endRatio: slice.endRatio)
                            .stroke(slice.color, style: StrokeStyle(lineWidth: outerLineWidth, lineCap: .butt))
                            .frame(width: side, height: side)
                    }
                }

                Circle()
                    .stroke(trackColor, lineWidth: innerLineWidth)
                    .frame(width: innerSide, height: innerSide)

                ForEach(innerSlices) { slice in
                    RingArcShape(startRatio: slice.startRatio, endRatio: slice.endRatio)
                        .stroke(slice.color, style: StrokeStyle(lineWidth: innerLineWidth, lineCap: .butt))
                        .frame(width: innerSide, height: innerSide)
                }
            }
            .frame(width: side, height: side)
        }
    }
}

private struct RingArcShape: Shape {
    let startRatio: Double
    let endRatio: Double

    func path(in rect: CGRect) -> Path {
        guard endRatio > startRatio else { return Path() }

        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let startAngle = Angle(degrees: -90 + 360 * startRatio)
        let endAngle = Angle(degrees: -90 + 360 * endRatio)

        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
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
