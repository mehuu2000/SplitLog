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
    let trackColor: Color
    let boundaryColor: Color
    let perimeterBorderColor: Color

    private let innerLineWidth: CGFloat = 30
    private let outerLineWidth: CGFloat = 30
    private let segmentBoundaryLineWidth: CGFloat = 1
    private let perimeterBorderLineWidth: CGFloat = 2
    private let contactBorderOutwardOffset: CGFloat = 3
    private let ringDiameterInset: CGFloat = 16

    init(
        innerSlices: [TimelineRingSlice],
        outerSlices: [TimelineRingSlice],
        showOuterTrack: Bool,
        trackColor: Color = Color.primary.opacity(0.1),
        boundaryColor: Color = .white,
        perimeterBorderColor: Color = .white
    ) {
        self.innerSlices = innerSlices
        self.outerSlices = outerSlices
        self.showOuterTrack = showOuterTrack
        self.trackColor = trackColor
        self.boundaryColor = boundaryColor
        self.perimeterBorderColor = perimeterBorderColor
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let ringSide = max(0, side - ringDiameterInset)
            let innerSide = max(0, ringSide - 56)

            ZStack {
                if showOuterTrack {
                    Circle()
                        .stroke(trackColor, lineWidth: outerLineWidth)
                        .frame(width: ringSide, height: ringSide)

                    ForEach(outerSlices) { slice in
                        ringSlice(
                            slice: slice,
                            lineWidth: outerLineWidth,
                            frameSide: ringSide
                        )
                    }

                    segmentBoundaries(
                        ratios: boundaryRatios(for: outerSlices),
                        lineWidth: outerLineWidth,
                        frameSide: ringSide
                    )
                }

                Circle()
                    .stroke(trackColor, lineWidth: innerLineWidth)
                    .frame(width: innerSide, height: innerSide)

                ForEach(innerSlices) { slice in
                    ringSlice(
                        slice: slice,
                        lineWidth: innerLineWidth,
                        frameSide: innerSide
                    )
                }

                segmentBoundaries(
                    ratios: boundaryRatios(for: innerSlices),
                    lineWidth: innerLineWidth,
                    frameSide: innerSide
                )

                outerPerimeterBorder(
                    frameSide: showOuterTrack ? ringSide : innerSide,
                    ringLineWidth: showOuterTrack ? outerLineWidth : innerLineWidth
                )

                innerPerimeterBorder(
                    frameSide: showOuterTrack ? ringSide : innerSide,
                    ringLineWidth: showOuterTrack ? outerLineWidth : innerLineWidth,
                    outwardOffset: showOuterTrack ? contactBorderOutwardOffset : 0,
                    lineWidth: showOuterTrack ? segmentBoundaryLineWidth : perimeterBorderLineWidth
                )

                if showOuterTrack {
                    innerPerimeterBorder(
                        frameSide: innerSide,
                        ringLineWidth: innerLineWidth,
                        outwardOffset: 0,
                        lineWidth: perimeterBorderLineWidth
                    )
                }
            }
            .frame(width: side, height: side)
        }
    }

    private func ringSlice(slice: TimelineRingSlice, lineWidth: CGFloat, frameSide: CGFloat) -> some View {
        Circle()
            .trim(from: clampedRatio(slice.startRatio), to: clampedRatio(slice.endRatio))
            .stroke(slice.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            .rotationEffect(.degrees(-90))
            .frame(width: frameSide, height: frameSide)
    }

    private func segmentBoundaries(ratios: [Double], lineWidth: CGFloat, frameSide: CGFloat) -> some View {
        ZStack {
            ForEach(Array(ratios.enumerated()), id: \.offset) { _, ratio in
                Path { path in
                    let center = CGPoint(x: frameSide / 2, y: frameSide / 2)
                    let angle = angleRadians(for: ratio)
                    let innerRadius = max(0, (frameSide / 2) - (lineWidth / 2))
                    let outerRadius = (frameSide / 2) + (lineWidth / 2)
                    let start = point(center: center, radius: innerRadius, angle: angle)
                    let end = point(center: center, radius: outerRadius, angle: angle)
                    path.move(to: start)
                    path.addLine(to: end)
                }
                .stroke(boundaryColor, style: StrokeStyle(lineWidth: segmentBoundaryLineWidth, lineCap: .round))
            }
        }
        .frame(width: frameSide, height: frameSide)
    }

    private func outerPerimeterBorder(frameSide: CGFloat, ringLineWidth: CGFloat) -> some View {
        Circle()
            .stroke(
                perimeterBorderColor,
                style: StrokeStyle(lineWidth: perimeterBorderLineWidth, lineCap: .round)
            )
            .frame(
                width: frameSide + ringLineWidth + perimeterBorderLineWidth,
                height: frameSide + ringLineWidth + perimeterBorderLineWidth
            )
    }

    private func innerPerimeterBorder(
        frameSide: CGFloat,
        ringLineWidth: CGFloat,
        outwardOffset: CGFloat,
        lineWidth: CGFloat
    ) -> some View {
        Circle()
            .stroke(
                perimeterBorderColor,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(
                width: max(0, frameSide - ringLineWidth - lineWidth + (outwardOffset * 2)),
                height: max(0, frameSide - ringLineWidth - lineWidth + (outwardOffset * 2))
            )
    }

    private func boundaryRatios(for slices: [TimelineRingSlice]) -> [Double] {
        guard slices.count > 1 else { return [] }
        let sorted = slices.sorted { lhs, rhs in
            if lhs.startRatio == rhs.startRatio {
                return lhs.endRatio < rhs.endRatio
            }
            return lhs.startRatio < rhs.startRatio
        }

        var boundaries: [Double] = []
        let epsilon = 0.0005
        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            let current = sorted[index]
            if abs(previous.endRatio - current.startRatio) <= epsilon {
                boundaries.append(current.startRatio)
            }
        }
        return boundaries
    }

    private func angleRadians(for ratio: Double) -> Double {
        (2 * .pi * ratio) - (.pi / 2)
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        CGPoint(
            x: center.x + (radius * CGFloat(Darwin.cos(angle))),
            y: center.y + (radius * CGFloat(Darwin.sin(angle)))
        )
    }

    private func clampedRatio(_ ratio: Double) -> CGFloat {
        CGFloat(min(1, max(0, ratio)))
    }
}

struct SessionTimelineRingView_Previews: PreviewProvider {
    static var previews: some View {
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
}
