//
//  InlineLapLabelEditor.swift
//  SplitLog
//
//  Created by Codex on 2026/02/19.
//

import AppKit
import SwiftUI

struct InlineLapLabelEditor: NSViewRepresentable {
    @Binding var text: String
    let focusToken: Int
    let onCommit: () -> Void

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineLapLabelEditor
        weak var textField: NSTextField?
        private var outsideClickMonitor: Any?
        private var activeFocusRequestToken: Int = -1
        private var isOutsideCommitEnabled = false

        init(parent: InlineLapLabelEditor) {
            self.parent = parent
        }

        deinit {
            removeOutsideClickMonitor()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isOutsideCommitEnabled = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            removeOutsideClickMonitor()
            parent.onCommit()
        }

        func installOutsideClickMonitor() {
            guard outsideClickMonitor == nil else { return }

            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self else { return event }
                guard
                    let field = self.textField,
                    let window = field.window
                else {
                    // Ignore clicks while the editor is not attached yet.
                    return event
                }

                // Ignore clicks until initial focus is actually established.
                guard self.isOutsideCommitEnabled else {
                    return event
                }

                guard event.window === window else { return event }

                let pointInField = field.convert(event.locationInWindow, from: nil)
                if field.bounds.contains(pointInField) {
                    return event
                }

                if let editor = field.currentEditor() {
                    let pointInEditor = editor.convert(event.locationInWindow, from: nil)
                    if editor.bounds.contains(pointInEditor) {
                        return event
                    }
                    window.makeFirstResponder(nil)
                    return event
                }

                self.parent.onCommit()
                return event
            }
        }

        func requestInitialFocusIfNeeded(on field: NSTextField, token: Int) {
            guard activeFocusRequestToken != token else { return }
            activeFocusRequestToken = token
            isOutsideCommitEnabled = false
            requestFocus(on: field, token: token, remainingRetries: 8)
        }

        private func requestFocus(on field: NSTextField, token: Int, remainingRetries: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self, weak field] in
                guard let self, let field else { return }
                guard self.parent.focusToken == token else { return }

                if let window = field.window, window.makeFirstResponder(field) {
                    self.isOutsideCommitEnabled = true
                    return
                }

                guard remainingRetries > 0 else { return }
                self.requestFocus(on: field, token: token, remainingRetries: remainingRetries - 1)
            }
        }

        func removeOutsideClickMonitor() {
            guard let outsideClickMonitor else { return }
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.maximumNumberOfLines = 1
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        field.textColor = .black
        context.coordinator.textField = field
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.installOutsideClickMonitor()

        if nsView.currentEditor() == nil, nsView.stringValue != text {
            nsView.stringValue = text
        }

        context.coordinator.requestInitialFocusIfNeeded(on: nsView, token: focusToken)
    }
}
