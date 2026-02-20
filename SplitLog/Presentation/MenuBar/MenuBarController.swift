//
//  MenuBarController.swift
//  SplitLog
//
//  Created by Codex on 2026/02/17.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let popover = NSPopover()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let stopwatch: StopwatchService
    private let appSettingsStore: AppSettingsStore
    private var cancellables = Set<AnyCancellable>()

    override init() {
        self.stopwatch = StopwatchService()
        self.appSettingsStore = AppSettingsStore()
        super.init()
        configurePopover()
        bindSettings()
        configureStatusItem()
    }

    func applicationWillTerminate() {
        stopwatch.prepareForTermination()
    }

    private func configurePopover() {
        popover.behavior = .transient
        let popoverSize = SessionPopoverView.popoverSize(showTimelineRing: appSettingsStore.showTimelineRing)
        popover.contentSize = NSSize(width: popoverSize.width, height: popoverSize.height)
        popover.contentViewController = NSHostingController(
            rootView: SessionPopoverView(
                stopwatch: stopwatch,
                appSettingsStore: appSettingsStore
            )
        )
    }

    private func bindSettings() {
        appSettingsStore.$settings
            .map(\.showTimelineRing)
            .removeDuplicates()
            .sink { [weak self] showTimelineRing in
                guard let self else { return }
                let size = SessionPopoverView.popoverSize(showTimelineRing: showTimelineRing)
                popover.contentSize = NSSize(width: size.width, height: size.height)
            }
            .store(in: &cancellables)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "SplitLog")
        button.image?.isTemplate = true
        button.toolTip = "SplitLog"
        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    @objc
    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }

        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
