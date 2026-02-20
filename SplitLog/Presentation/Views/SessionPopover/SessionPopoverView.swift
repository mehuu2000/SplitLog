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
    private static let expandedPopoverSize = CGSize(width: 540, height: 380)
    private static let compactPopoverSize = CGSize(width: 360, height: 330)

    @StateObject private var stopwatch: StopwatchService
    @StateObject private var appSettingsStore: AppSettingsStore
    @State private var editingLapID: UUID?
    @State private var editingLapLabelDraft = ""
    @State private var editingFocusToken: Int = 0
    @State private var editingSessionID: UUID?
    @State private var editingSessionTitleDraft = ""
    @State private var editingSessionTitleFocusToken: Int = 0
    @State private var isShowingResetConfirmation = false
    @State private var isShowingDeleteSessionConfirmation = false
    @State private var isShowingSessionOverflowList = false
    @State private var isShowingSettingsModal = false
    @State private var isShowingSessionSummaryModal = false
    @State private var memoEditingLapID: UUID?
    @State private var memoLapLabelDraft = ""
    @State private var memoLapTextDraft = ""
    @State private var sessionSummaryDraft = ""
    // Temporary for UI verification: 1 ring = 30 seconds (instead of 12 hours)
    private let ringBlockDuration: TimeInterval = 30
    private let sessionTitleAreaWidth: CGFloat = 250
    private let compactSessionTitleAreaWidth: CGFloat = 140
    private let compactSessionTitleEditingAreaWidth: CGFloat = 140
    private let sessionTitleAreaHeight: CGFloat = 28

    init(stopwatch: StopwatchService, appSettingsStore: AppSettingsStore) {
        _stopwatch = StateObject(wrappedValue: stopwatch)
        _appSettingsStore = StateObject(wrappedValue: appSettingsStore)
    }

    init(stopwatch: StopwatchService) {
        _stopwatch = StateObject(wrappedValue: stopwatch)
        _appSettingsStore = StateObject(wrappedValue: AppSettingsStore())
    }

    init() {
        _stopwatch = StateObject(wrappedValue: StopwatchService())
        _appSettingsStore = StateObject(wrappedValue: AppSettingsStore())
    }

    static func popoverSize(showTimelineRing: Bool) -> CGSize {
        showTimelineRing ? expandedPopoverSize : compactPopoverSize
    }

    var body: some View {
        let colorResolver = self.colorResolver
        let showTimelineRing = appSettingsStore.showTimelineRing
        let popoverSize = Self.popoverSize(showTimelineRing: showTimelineRing)
        let referenceDate = stopwatch.clock
        let timeline = timelineSlices(referenceDate: referenceDate)
        let totalElapsedSeconds = durationSeconds(stopwatch.elapsedSession(at: referenceDate))
        let lapDisplayedSeconds = displayedLapSeconds(
            referenceDate: referenceDate,
            totalElapsedSeconds: totalElapsedSeconds
        )
        let lapListView = SessionLapListView(
            laps: stopwatch.laps,
            selectedLapID: stopwatch.selectedLapID,
            lapDisplayedSeconds: lapDisplayedSeconds,
            subtitleText: subtitleText,
            subtitleColor: colorResolver.subtitleTextColor,
            rowPrimaryTextColor: colorResolver.lapPrimaryTextColor,
            rowSecondaryIconColor: colorResolver.lapSecondaryIconColor,
            inlineEditorBackgroundColor: colorResolver.inlineEditorBackgroundColor,
            editingLapID: $editingLapID,
            editingLapLabelDraft: $editingLapLabelDraft,
            editingFocusToken: editingFocusToken,
            formatDuration: { formatDuration(seconds: $0) },
            colorForLap: { lapColor(for: $0) },
            onSelectLap: { lapID in
                handleSelectLap(lapID: lapID)
            },
            onOpenMemo: { lap in
                beginLapMemoEdit(for: lap)
            },
            onBeginLapLabelEdit: { lap in
                beginLapLabelEdit(for: lap)
            },
            onCommitLapLabelEdit: { lapID in
                commitLapLabelEdit(lapID: lapID)
            }
        )

        ZStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    if showTimelineRing {
                        Label("SplitLog", systemImage: "timer")
                            .font(.headline)
                        Spacer()
                    } else {
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        SessionSelectorCapsuleView(
                            sessions: stopwatch.sessions,
                            selectedSessionID: stopwatch.selectedSessionID,
                            capsuleBorderColor: colorResolver.capsuleBorderColor,
                            selectedChipColor: colorResolver.sessionChipSelectedColor,
                            overflowButtonBackgroundColor: colorResolver.overflowButtonBackgroundColor,
                            overflowButtonIconColor: colorResolver.overflowButtonIconColor,
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
                                        .fill(colorResolver.headerControlBackground)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("セッション追加")
                        .accessibilityLabel("セッション追加")

                        Button {
                            isShowingSessionOverflowList = false
                            isShowingSettingsModal = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 24, height: 24)
                                .background(
                                    Circle()
                                        .fill(colorResolver.headerControlBackground)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("設定")
                        .accessibilityLabel("設定")
                    }

                    if !showTimelineRing {
                        Spacer(minLength: 0)
                    }
                }

                Divider()
                    .padding(.top, -10)

                HStack(spacing: 10) {
                    if showTimelineRing {
                        sessionTitleSection

                        Spacer()
                        sessionSummaryButton(
                            lapDisplayedSeconds: lapDisplayedSeconds,
                            totalElapsedSeconds: totalElapsedSeconds
                        )
                        Text("全体経過")
                            .foregroundStyle(colorResolver.subtitleTextColor)
                        Text(formatDuration(seconds: totalElapsedSeconds))
                            .monospacedDigit()
                    } else {
                        sessionTitleSection

                        Spacer(minLength: 8)

                        HStack(spacing: 6) {
                            sessionSummaryButton(
                                lapDisplayedSeconds: lapDisplayedSeconds,
                                totalElapsedSeconds: totalElapsedSeconds
                            )
                            Text("全体経過")
                                .foregroundStyle(colorResolver.subtitleTextColor)
                            Text(formatDuration(seconds: totalElapsedSeconds))
                                .monospacedDigit()
                        }
                    }
                }
                .font(.body)
                .padding(.horizontal, showTimelineRing ? 0 : 24)

                if showTimelineRing {
                    HStack(alignment: .top, spacing: 16) {
                        SessionTimelineRingView(
                            innerSlices: timeline.inner,
                            outerSlices: timeline.outer,
                            showOuterTrack: timeline.showOuterTrack,
                            trackColor: colorResolver.timelineTrackColor,
                            boundaryColor: colorResolver.timelineBorderColor,
                            perimeterBorderColor: colorResolver.timelineBorderColor
                        )
                        .frame(width: 210, height: 210)

                        lapListView
                    }
                } else {
                    HStack {
                        lapListView
                            .frame(width: 290, alignment: .center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }

                Spacer(minLength: 8)

                if showTimelineRing {
                    HStack {
                        HStack(spacing: 10) {
                            Button(primaryActionButtonTitle, action: handlePrimaryAction)
                                .buttonStyle(.borderedProminent)

                            Button("ラップ終了", action: handleFinishLap)
                                .buttonStyle(.bordered)
                                .disabled(stopwatch.state != .running)
                        }
                        .tint(colorResolver.controlTint)

                        Spacer()

                        Button(action: requestReset) {
                            Image(systemName: "arrow.counterclockwise")
                                .frame(width: 14, height: 14)
                        }
                        .frame(width: 32, height: 32)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: 8))
                        .tint(colorResolver.utilityButtonTint)
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
                        .tint(colorResolver.utilityButtonTint)
                        .help("現在セッションを削除")
                        .accessibilityLabel("現在セッションを削除")
                        .disabled(stopwatch.session == nil)
                    }
                } else {
                    HStack(spacing: 10) {
                        Button(primaryActionButtonTitle, action: handlePrimaryAction)
                            .buttonStyle(.borderedProminent)
                            .tint(colorResolver.controlTint)

                        Button("ラップ終了", action: handleFinishLap)
                            .buttonStyle(.bordered)
                            .tint(colorResolver.controlTint)
                            .disabled(stopwatch.state != .running)

                        Button(action: requestReset) {
                            Image(systemName: "arrow.counterclockwise")
                                .frame(width: 14, height: 14)
                        }
                        .frame(width: 32, height: 32)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: 8))
                        .tint(colorResolver.utilityButtonTint)
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
                        .tint(colorResolver.utilityButtonTint)
                        .help("現在セッションを削除")
                        .accessibilityLabel("現在セッションを削除")
                        .disabled(stopwatch.session == nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
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
                            borderColor: colorResolver.overflowPanelBorderColor,
                            selectedRowColor: colorResolver.overflowPanelSelectedRowColor,
                            defaultRowColor: colorResolver.overflowPanelDefaultRowColor,
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
                    isMonochrome: colorResolver.isMonochrome,
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

            if let memoLap = memoEditingLap {
                SessionLapMemoOverlayView(
                    lapLabel: $memoLapLabelDraft,
                    elapsedText: formatDuration(seconds: lapDisplayedSeconds[memoLap.id] ?? 0),
                    memoText: $memoLapTextDraft,
                    onClose: commitLapMemoEdit
                )
            }

            if isShowingSessionSummaryModal {
                SessionSummaryOverlayView(
                    summaryText: $sessionSummaryDraft,
                    memoFormatLabel: sessionSummaryMemoFormatLabel,
                    onToggleMemoFormat: {
                        toggleSessionSummaryMemoFormat(
                            lapDisplayedSeconds: lapDisplayedSeconds,
                            totalElapsedSeconds: totalElapsedSeconds
                        )
                    },
                    timeFormatLabel: sessionSummaryTimeFormatButtonText(referenceDate: referenceDate),
                    onToggleTimeFormat: {
                        toggleSessionSummaryTimeFormat(
                            lapDisplayedSeconds: lapDisplayedSeconds,
                            totalElapsedSeconds: totalElapsedSeconds
                        )
                    },
                    onCopy: copySessionSummaryToPasteboard,
                    onClose: {
                        isShowingSessionSummaryModal = false
                    }
                )
            }

            if isShowingSettingsModal {
                SessionSettingsOverlayView(
                    settingsStore: appSettingsStore,
                    onClose: {
                        isShowingSettingsModal = false
                    }
                )
            }
        }
        .padding(14)
        .frame(width: popoverSize.width, height: popoverSize.height)
        .tint(colorResolver.controlTint)
        .background(.regularMaterial)
        .onAppear {
            stopwatch.setDisplayActive(true)
        }
        .onDisappear {
            commitPendingInlineEdits()
            commitActiveLapMemoEditIfNeeded()
            stopwatch.setDisplayActive(false)
        }
    }

    private var memoEditingLap: WorkLap? {
        guard let memoEditingLapID else { return nil }
        return stopwatch.laps.first(where: { $0.id == memoEditingLapID })
    }

    private var selectedSessionTitleText: String {
        stopwatch.session?.title ?? "セッション未選択"
    }

    private var sessionTitleUnderlineWidth: CGFloat {
        let baseText = isEditingSelectedSessionTitle ? editingSessionTitleDraft : selectedSessionTitleText
        let text = baseText.isEmpty ? " " : baseText
        let fontSize: CGFloat = isEditingSelectedSessionTitle ? 14 : 16
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let measuredWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return max(32, ceil(measuredWidth) + 4)
    }

    private var isEditingSelectedSessionTitle: Bool {
        guard let editingSessionID, let selectedSessionID = stopwatch.selectedSessionID else { return false }
        return editingSessionID == selectedSessionID
    }

    @ViewBuilder
    private var sessionTitleDisplayView: some View {
        let width = appSettingsStore.showTimelineRing ? sessionTitleAreaWidth : compactSessionTitleAreaWidth

        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedSessionTitleText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(stopwatch.session == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Rectangle()
                    .fill(colorResolver.sessionTitleUnderlineColor)
                    .frame(width: sessionTitleUnderlineWidth)
                    .frame(height: 1)
            }
        }
        .frame(width: width, height: sessionTitleAreaHeight, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(perform: beginSessionTitleEdit)
    }

    @ViewBuilder
    private var sessionTitleSection: some View {
        Group {
            if isEditingSelectedSessionTitle {
                sessionTitleEditingView
            } else {
                sessionTitleDisplayView
            }
        }
    }

    @ViewBuilder
    private func sessionSummaryButton(
        lapDisplayedSeconds: [UUID: Int],
        totalElapsedSeconds: Int
    ) -> some View {
        Button {
            openSessionSummary(
                lapDisplayedSeconds: lapDisplayedSeconds,
                totalElapsedSeconds: totalElapsedSeconds
            )
        } label: {
            Image(systemName: "doc.text")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(colorResolver.headerControlBackground)
                )
        }
        .buttonStyle(.plain)
        .help("セッションまとめ")
        .accessibilityLabel("セッションまとめ")
        .disabled(stopwatch.session == nil)
    }

    @ViewBuilder
    private var sessionTitleEditingView: some View {
        let width = appSettingsStore.showTimelineRing ? sessionTitleAreaWidth : compactSessionTitleEditingAreaWidth

        VStack(alignment: .leading, spacing: 2) {
            InlineLapLabelEditor(
                text: $editingSessionTitleDraft,
                focusToken: editingSessionTitleFocusToken,
                fontSize: 14,
                fontWeight: .semibold,
                onCommit: commitSessionTitleEdit
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(colorResolver.inlineEditorBackgroundColor)
            )

            Rectangle()
                .fill(colorResolver.sessionTitleUnderlineColor)
                .frame(width: sessionTitleUnderlineWidth)
                .frame(height: 1)
        }
        .frame(width: width, height: sessionTitleAreaHeight, alignment: .leading)
        .clipped()
    }

    private var subtitleText: String {
        guard !stopwatch.laps.isEmpty else { return "" }
        return stopwatchStateText
    }

    private func sessionSummaryTimeFormatButtonText(referenceDate: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: referenceDate)
        let hour = max(0, components.hour ?? 0)
        let minute = max(0, components.minute ?? 0)

        switch appSettingsStore.summaryTimeFormat {
        case .decimalHours:
            let decimalHours = Double(hour) + (Double(minute) / 60.0)
            return String(format: "%.1fh", decimalHours)
        case .hourMinute:
            return "\(hour)時間\(minute)分"
        }
    }

    private var sessionSummaryMemoFormatLabel: String {
        switch appSettingsStore.summaryMemoFormat {
        case .bulleted:
            "- メモ"
        case .plain:
            "メモ"
        }
    }

    private var colorResolver: SessionThemeColorResolver {
        SessionThemeColorResolver(mode: appSettingsStore.themeMode)
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
        commitPendingInlineEdits()

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
        commitPendingInlineEdits()
        stopwatch.finishLap()
    }

    private func handleAddSession() {
        commitPendingInlineEdits()
        stopwatch.addSession()
    }

    private func handleSelectSession(sessionID: UUID) {
        commitPendingInlineEdits()
        stopwatch.selectSession(sessionID: sessionID)
    }

    private func handleSelectLap(lapID: UUID) {
        commitPendingInlineEdits()
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
        commitPendingInlineEdits()
        stopwatch.resetSelectedSession()
    }

    private func handleDeleteSession() {
        commitPendingInlineEdits()
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

    private func beginSessionTitleEdit() {
        guard let session = stopwatch.session else { return }
        commitActiveLapLabelEditIfNeeded()
        editingSessionID = session.id
        editingSessionTitleDraft = session.title
        editingSessionTitleFocusToken += 1
    }

    private func commitSessionTitleEdit() {
        guard let sessionID = editingSessionID else { return }
        stopwatch.updateSessionTitle(sessionID: sessionID, title: editingSessionTitleDraft)
        editingSessionID = nil
        editingSessionTitleDraft = ""
    }

    private func commitActiveSessionTitleEditIfNeeded() {
        guard editingSessionID != nil else { return }
        commitSessionTitleEdit()
    }

    private func commitPendingInlineEdits() {
        commitActiveLapLabelEditIfNeeded()
        commitActiveSessionTitleEditIfNeeded()
    }

    private func beginLapMemoEdit(for lap: WorkLap) {
        commitPendingInlineEdits()
        memoEditingLapID = lap.id
        memoLapLabelDraft = lap.label
        memoLapTextDraft = lap.memo
    }

    private func openSessionSummary(
        lapDisplayedSeconds: [UUID: Int],
        totalElapsedSeconds: Int
    ) {
        commitPendingInlineEdits()
        commitActiveLapMemoEditIfNeeded()
        sessionSummaryDraft = buildSessionSummaryText(
            lapDisplayedSeconds: lapDisplayedSeconds,
            totalElapsedSeconds: totalElapsedSeconds,
            timeFormat: appSettingsStore.summaryTimeFormat,
            memoFormat: appSettingsStore.summaryMemoFormat
        )
        isShowingSessionSummaryModal = true
    }

    private func toggleSessionSummaryTimeFormat(
        lapDisplayedSeconds: [UUID: Int],
        totalElapsedSeconds: Int
    ) {
        let nextFormat: SummaryTimeFormat = appSettingsStore.summaryTimeFormat == .decimalHours ? .hourMinute : .decimalHours
        appSettingsStore.setSummaryTimeFormat(nextFormat)
        sessionSummaryDraft = buildSessionSummaryText(
            lapDisplayedSeconds: lapDisplayedSeconds,
            totalElapsedSeconds: totalElapsedSeconds,
            timeFormat: nextFormat,
            memoFormat: appSettingsStore.summaryMemoFormat
        )
    }

    private func toggleSessionSummaryMemoFormat(
        lapDisplayedSeconds: [UUID: Int],
        totalElapsedSeconds: Int
    ) {
        let nextFormat: SummaryMemoFormat = appSettingsStore.summaryMemoFormat == .bulleted ? .plain : .bulleted
        appSettingsStore.setSummaryMemoFormat(nextFormat)
        sessionSummaryDraft = buildSessionSummaryText(
            lapDisplayedSeconds: lapDisplayedSeconds,
            totalElapsedSeconds: totalElapsedSeconds,
            timeFormat: appSettingsStore.summaryTimeFormat,
            memoFormat: nextFormat
        )
    }

    private func copySessionSummaryToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sessionSummaryDraft, forType: .string)
    }

    private func buildSessionSummaryText(
        lapDisplayedSeconds: [UUID: Int],
        totalElapsedSeconds: Int,
        timeFormat: SummaryTimeFormat,
        memoFormat: SummaryMemoFormat
    ) -> String {
        guard let session = stopwatch.session else { return "" }

        var lines: [String] = []
        lines.append("【\(session.title) (\(summaryDurationText(seconds: totalElapsedSeconds, format: timeFormat)))】")

        if stopwatch.laps.isEmpty {
            lines.append("・ラップはまだありません")
            return lines.joined(separator: "\n")
        }

        for lap in stopwatch.laps {
            let elapsedSeconds = lapDisplayedSeconds[lap.id] ?? durationSeconds(stopwatch.elapsedLap(lap))
            lines.append("・\(lap.label)　(\(summaryDurationText(seconds: elapsedSeconds, format: timeFormat)))")
            let trimmedMemo = lap.memo.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedMemo.isEmpty {
                switch memoFormat {
                case .plain:
                    lines.append(lap.memo)
                case .bulleted:
                    let paragraphs = lap.memo
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    for paragraph in paragraphs {
                        lines.append("- \(paragraph)")
                    }
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private func summaryDurationText(seconds: Int, format: SummaryTimeFormat) -> String {
        switch format {
        case .decimalHours:
            let roundedHours = max(0, Double(seconds) / 3600)
            return String(format: "%.1fh", roundedHours)
        case .hourMinute:
            let roundedTotalMinutes = max(0, (seconds + 30) / 60)
            let hours = roundedTotalMinutes / 60
            let minutes = roundedTotalMinutes % 60
            return "\(hours)時間\(minutes)分"
        }
    }

    private func commitLapMemoEdit() {
        guard let lapID = memoEditingLapID else { return }
        stopwatch.updateLapLabel(lapID: lapID, label: memoLapLabelDraft)
        stopwatch.updateLapMemo(lapID: lapID, memo: memoLapTextDraft)

        memoEditingLapID = nil
        memoLapLabelDraft = ""
        memoLapTextDraft = ""
    }

    private func commitActiveLapMemoEditIfNeeded() {
        guard memoEditingLapID != nil else { return }
        commitLapMemoEdit()
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
        colorResolver.lapColor(for: index, rgbWheel: Self.rgbWheel)
    }

    private func displayedLapSeconds(referenceDate: Date, totalElapsedSeconds: Int) -> [UUID: Int] {
        struct Entry {
            let lap: WorkLap
            let baseSeconds: Int
            let fraction: TimeInterval
            let isSelected: Bool
        }

        let entries: [Entry] = stopwatch.laps.map { lap in
            let raw = max(0, stopwatch.elapsedLap(lap, at: referenceDate))
            let base = durationSeconds(raw)
            let fraction = raw - TimeInterval(base)
            return Entry(
                lap: lap,
                baseSeconds: base,
                fraction: fraction,
                isSelected: lap.id == stopwatch.selectedLapID
            )
        }

        var result = Dictionary(uniqueKeysWithValues: entries.map { ($0.lap.id, $0.baseSeconds) })
        let baseTotal = entries.reduce(0) { $0 + $1.baseSeconds }
        var remaining = max(0, totalElapsedSeconds - baseTotal)
        guard remaining > 0 else { return result }

        let sortedByFraction = entries
            .filter { $0.fraction > 0 }
            .sorted { lhs, rhs in
                if lhs.fraction == rhs.fraction {
                    return lhs.lap.index > rhs.lap.index
                }
                return lhs.fraction > rhs.fraction
            }

        func applyCarry(to candidates: [Entry], maxCount: Int) -> Int {
            guard maxCount > 0, !candidates.isEmpty else { return 0 }
            let granted = min(maxCount, candidates.count)
            for entry in candidates.prefix(granted) {
                result[entry.lap.id, default: entry.baseSeconds] += 1
            }
            return granted
        }

        if stopwatch.state == .running,
           let selectedLapID = stopwatch.selectedLapID,
           let selectedEntry = entries.first(where: { $0.lap.id == selectedLapID }) {
            let nonSelectedEntries = entries.filter { $0.lap.id != selectedLapID && $0.fraction > 0 }
            let fixedCarry = Int(floor(nonSelectedEntries.reduce(0) { $0 + $1.fraction }))
            let fixedGranted = applyCarry(
                to: nonSelectedEntries.sorted { lhs, rhs in
                    if lhs.fraction == rhs.fraction {
                        return lhs.lap.index > rhs.lap.index
                    }
                    return lhs.fraction > rhs.fraction
                },
                maxCount: min(remaining, fixedCarry)
            )
            remaining -= fixedGranted

            if remaining > 0, selectedEntry.fraction > 0 {
                result[selectedLapID, default: selectedEntry.baseSeconds] += 1
                remaining -= 1
            }
        }

        if remaining > 0 {
            remaining -= applyCarry(to: sortedByFraction, maxCount: remaining)
        }

        if remaining > 0, let first = sortedByFraction.first {
            result[first.lap.id, default: first.baseSeconds] += remaining
        }

        return result
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
