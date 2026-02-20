//
//  SessionThemeColorResolver.swift
//  SplitLog
//
//  Created by Codex on 2026/02/20.
//

import SwiftUI

struct SessionThemeColorResolver {
    let mode: ThemeMode

    private static let monochromeWheel: [Double] = [
        0.18, 0.27, 0.36, 0.45, 0.54, 0.63, 0.72, 0.81,
        0.22, 0.31, 0.40, 0.49, 0.58, 0.67, 0.76, 0.85,
        0.25, 0.34, 0.43, 0.52, 0.61, 0.70, 0.79, 0.88,
    ]

    var isMonochrome: Bool {
        mode == .monochrome
    }

    var controlTint: Color {
        isMonochrome ? Color(white: 0.25) : .accentColor
    }

    var utilityButtonTint: Color {
        Color(white: 0.25)
    }

    var headerControlBackground: Color {
        isMonochrome ? Color.primary.opacity(0.14) : Color.primary.opacity(0.08)
    }

    var capsuleBorderColor: Color {
        isMonochrome ? Color.primary.opacity(0.38) : Color.primary.opacity(0.28)
    }

    var sessionChipSelectedColor: Color {
        isMonochrome ? Color.primary.opacity(0.2) : Color.primary.opacity(0.14)
    }

    var overflowButtonBackgroundColor: Color {
        isMonochrome ? Color.primary.opacity(0.16) : Color.primary.opacity(0.10)
    }

    var overflowButtonIconColor: Color {
        isMonochrome ? Color.primary.opacity(0.88) : Color.primary
    }

    var overflowPanelBorderColor: Color {
        isMonochrome ? Color.primary.opacity(0.2) : Color.primary.opacity(0.12)
    }

    var overflowPanelSelectedRowColor: Color {
        isMonochrome ? Color.primary.opacity(0.2) : Color.primary.opacity(0.14)
    }

    var overflowPanelDefaultRowColor: Color {
        isMonochrome ? Color.primary.opacity(0.12) : Color.primary.opacity(0.07)
    }

    var sessionTitleUnderlineColor: Color {
        isMonochrome ? Color.primary.opacity(0.36) : Color.primary.opacity(0.22)
    }

    var subtitleTextColor: Color {
        isMonochrome ? Color.primary.opacity(0.62) : .secondary
    }

    var inlineEditorBackgroundColor: Color {
        isMonochrome ? Color.primary.opacity(0.14) : Color.white.opacity(0.9)
    }

    var lapPrimaryTextColor: Color {
        isMonochrome ? Color.primary : Color.black
    }

    var lapSecondaryIconColor: Color {
        isMonochrome ? Color.primary.opacity(0.72) : Color.black.opacity(0.8)
    }

    var timelineTrackColor: Color {
        isMonochrome ? Color(white: 0.94) : Color.primary.opacity(0.1)
    }

    var timelineBorderColor: Color {
        isMonochrome ? Color.primary.opacity(0.92) : Color.white
    }

    func lapColor(for index: Int, rgbWheel: [(Double, Double, Double)]) -> Color {
        let zeroBasedIndex = max(0, index - 1)
        let cycle = zeroBasedIndex / rgbWheel.count
        let paletteIndex = (zeroBasedIndex + cycle) % rgbWheel.count

        if isMonochrome {
            let monochromeIndex = (zeroBasedIndex + cycle) % Self.monochromeWheel.count
            let white = Self.monochromeWheel[monochromeIndex]
            return Color(white: white)
        }

        let rgb = rgbWheel[paletteIndex]
        return Color(
            red: rgb.0 / 255.0,
            green: rgb.1 / 255.0,
            blue: rgb.2 / 255.0
        )
    }
}
