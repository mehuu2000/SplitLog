//
//  MenuBarController.swift
//  SplitLog
//
//  Created by Codex on 2026/02/17.
//

import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let popover = NSPopover()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let stopwatch: StopwatchService
    private let appSettingsStore: AppSettingsStore

    override init() {
        self.stopwatch = StopwatchService()
        self.appSettingsStore = AppSettingsStore()
        super.init()
        configurePopover()
        configureStatusItem()
    }

    func applicationWillTerminate() {
        stopwatch.prepareForTermination()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 540, height: 380)
        popover.contentViewController = NSHostingController(
            rootView: SessionPopoverView(
                stopwatch: stopwatch,
                appSettingsStore: appSettingsStore
            )
        )
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
