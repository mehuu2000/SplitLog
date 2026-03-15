//
//  MenuBarController.swift
//  SplitLog
//
//  Created by Codex on 2026/02/17.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private enum ShortcutAction {
        case split
        case stop
        case resume
        case togglePopover
        case openCurrentLapMemo
        case targetLap(Int)
        case moveLap(Int)
    }

    private static let hotKeySignature: OSType = 0x53504C54
    private static let hotKeyEventHandler: EventHandlerUPP = { _, eventRef, userData in
        guard
            let eventRef,
            let userData
        else {
            return noErr
        }

        let controller = Unmanaged<MenuBarController>.fromOpaque(userData).takeUnretainedValue()
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }
        controller.handleHotKey(withID: hotKeyID.id)
        return noErr
    }

    private let popover = NSPopover()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let stopwatch: StopwatchService
    private let appSettingsStore: AppSettingsStore
    private let commandCenter: SessionPopoverCommandCenter
    private var hotKeyHandlerRef: EventHandlerRef?
    private var registeredHotKeys: [EventHotKeyRef] = []
    private var hotKeyActions: [UInt32: ShortcutAction] = [:]
    private var nextHotKeyID: UInt32 = 1
    private var outsideClickLocalMonitor: Any?
    private var outsideClickGlobalMonitor: Any?

    override init() {
        self.stopwatch = StopwatchService()
        self.appSettingsStore = AppSettingsStore()
        self.commandCenter = SessionPopoverCommandCenter()
        super.init()
        configurePopover()
        configureStatusItem()
        configureHotKeys()
    }

    func applicationWillTerminate() {
        unregisterHotKeys()
        stopwatch.prepareForTermination()
    }

    private func configurePopover() {
        popover.delegate = self
        popover.behavior = .applicationDefined
        let popoverSize = SessionPopoverView.popoverSize
        popover.contentSize = NSSize(width: popoverSize.width, height: popoverSize.height)
        popover.contentViewController = NSHostingController(
            rootView: SessionPopoverView(
                stopwatch: stopwatch,
                appSettingsStore: appSettingsStore,
                commandCenter: commandCenter
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
        togglePopoverVisibility(triggeredByShortcut: false)
    }

    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitors()
    }

    private func configureHotKeys() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            Self.hotKeyEventHandler,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandlerRef
        )

        let modifiers = UInt32(cmdKey | controlKey)
        registerHotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: modifiers, action: .split)
        registerHotKey(keyCode: UInt32(kVK_ANSI_X), modifiers: modifiers, action: .stop)
        registerHotKey(keyCode: UInt32(kVK_ANSI_R), modifiers: modifiers, action: .resume)
        registerHotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: modifiers, action: .togglePopover)
        registerHotKey(keyCode: UInt32(kVK_ANSI_M), modifiers: modifiers, action: .openCurrentLapMemo)
        registerHotKey(keyCode: UInt32(kVK_ANSI_1), modifiers: modifiers, action: .targetLap(1))
        registerHotKey(keyCode: UInt32(kVK_ANSI_2), modifiers: modifiers, action: .targetLap(2))
        registerHotKey(keyCode: UInt32(kVK_ANSI_3), modifiers: modifiers, action: .targetLap(3))
        registerHotKey(keyCode: UInt32(kVK_ANSI_4), modifiers: modifiers, action: .targetLap(4))
        registerHotKey(keyCode: UInt32(kVK_ANSI_5), modifiers: modifiers, action: .targetLap(5))
        registerHotKey(keyCode: UInt32(kVK_ANSI_6), modifiers: modifiers, action: .targetLap(6))
        registerHotKey(keyCode: UInt32(kVK_ANSI_7), modifiers: modifiers, action: .targetLap(7))
        registerHotKey(keyCode: UInt32(kVK_ANSI_8), modifiers: modifiers, action: .targetLap(8))
        registerHotKey(keyCode: UInt32(kVK_ANSI_9), modifiers: modifiers, action: .targetLap(9))
        registerHotKey(keyCode: UInt32(kVK_ANSI_0), modifiers: modifiers, action: .targetLap(0))
        registerHotKey(keyCode: UInt32(kVK_UpArrow), modifiers: modifiers, action: .moveLap(-1))
        registerHotKey(keyCode: UInt32(kVK_DownArrow), modifiers: modifiers, action: .moveLap(1))
    }

    private func unregisterHotKeys() {
        for hotKey in registeredHotKeys {
            UnregisterEventHotKey(hotKey)
        }
        registeredHotKeys.removeAll()
        hotKeyActions.removeAll()

        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
            self.hotKeyHandlerRef = nil
        }
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32, action: ShortcutAction) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: nextHotKeyID)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else { return }

        registeredHotKeys.append(hotKeyRef)
        hotKeyActions[nextHotKeyID] = action
        nextHotKeyID += 1
    }

    private func handleHotKey(withID id: UInt32) {
        guard let action = hotKeyActions[id] else { return }
        performShortcutAction(action)
    }

    private func performShortcutAction(_ action: ShortcutAction) {
        switch action {
        case .togglePopover:
            togglePopoverVisibility(triggeredByShortcut: true)
        case .openCurrentLapMemo:
            handleOpenCurrentLapMemoShortcut()
        case .split:
            handleStateShortcut {
                guard self.stopwatch.state == .running else { return false }
                self.stopwatch.finishLap()
                return true
            }
        case .stop:
            handleStateShortcut(showPopoverWhenNoAction: true) {
                guard self.stopwatch.state == .running || self.stopwatch.state == .paused else { return false }
                self.stopwatch.finishSession()
                return true
            }
        case .resume:
            handleStateShortcut(showPopoverWhenNoAction: true) {
                guard self.stopwatch.state == .stopped || self.stopwatch.state == .paused else { return false }
                self.stopwatch.resumeSession()
                return true
            }
        case let .targetLap(index):
            handleStateShortcut {
                self.stopwatch.selectOrToggleLapForShortcut(displayIndex: index)
            }
        case let .moveLap(offset):
            handleStateShortcut {
                self.stopwatch.moveSelectedLapForShortcut(by: offset)
            }
        }
    }

    private func handleStateShortcut(
        showPopoverWhenNoAction: Bool = false,
        _ action: () -> Bool
    ) {
        let wasShown = popover.isShown
        guard action() else {
            guard showPopoverWhenNoAction, !wasShown else { return }
            showPopover(deferUntilNextRunLoop: true)
            return
        }
        guard !wasShown else { return }
        showPopover(deferUntilNextRunLoop: true)
    }

    private func handleOpenCurrentLapMemoShortcut() {
        guard stopwatch.currentLap != nil else { return }

        if !popover.isShown {
            showPopover(deferUntilNextRunLoop: true)
        }

        DispatchQueue.main.async { [weak self] in
            self?.commandCenter.send(.openCurrentLapMemo)
        }
    }

    private func togglePopoverVisibility(triggeredByShortcut: Bool) {
        if popover.isShown {
            closePopover()
            return
        }

        showPopover(activateApp: triggeredByShortcut, deferUntilNextRunLoop: triggeredByShortcut)
    }

    private func showPopover(
        activateApp: Bool = true,
        deferUntilNextRunLoop: Bool = false
    ) {
        if deferUntilNextRunLoop {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.popover.isShown else { return }
                self.showPopoverNow(activateApp: activateApp)
            }
            return
        }

        showPopoverNow(activateApp: activateApp)
    }

    private func showPopoverNow(activateApp: Bool) {
        guard let button = statusItem.button else { return }

        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
        }

        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            installOutsideClickMonitors()
        }
    }

    private func closePopover() {
        removeOutsideClickMonitors()
        popover.performClose(statusItem.button)
    }

    private func installOutsideClickMonitors() {
        guard outsideClickLocalMonitor == nil, outsideClickGlobalMonitor == nil else { return }

        outsideClickLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            guard self.popover.isShown else { return event }
            guard !self.isEventInsidePopover(event), !self.isEventOnStatusItemButton(event) else {
                return event
            }

            self.closePopover()
            return event
        }

        outsideClickGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.popover.isShown else { return }
                self.closePopover()
            }
        }
    }

    private func removeOutsideClickMonitors() {
        if let outsideClickLocalMonitor {
            NSEvent.removeMonitor(outsideClickLocalMonitor)
            self.outsideClickLocalMonitor = nil
        }

        if let outsideClickGlobalMonitor {
            NSEvent.removeMonitor(outsideClickGlobalMonitor)
            self.outsideClickGlobalMonitor = nil
        }
    }

    private func isEventInsidePopover(_ event: NSEvent) -> Bool {
        guard let popoverWindow = popover.contentViewController?.view.window else { return false }
        return event.window === popoverWindow
    }

    private func isEventOnStatusItemButton(_ event: NSEvent) -> Bool {
        guard
            let button = statusItem.button,
            let buttonWindow = button.window,
            event.window === buttonWindow
        else {
            return false
        }

        let location = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(location)
    }
}
