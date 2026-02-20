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
    let fontSize: CGFloat
    let fontWeight: NSFont.Weight
    let onCommit: () -> Void

    init(
        text: Binding<String>,
        focusToken: Int,
        fontSize: CGFloat = NSFont.systemFontSize,
        fontWeight: NSFont.Weight = .medium,
        onCommit: @escaping () -> Void
    ) {
        _text = text
        self.focusToken = focusToken
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.onCommit = onCommit
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineLapLabelEditor
        weak var textField: NSTextField?
        private var activeFocusRequestToken: Int = -1

        init(parent: InlineLapLabelEditor) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.onCommit()
        }

        func requestInitialFocusIfNeeded(on field: NSTextField, token: Int) {
            guard activeFocusRequestToken != token else { return }
            activeFocusRequestToken = token
            requestFocus(on: field, token: token, remainingRetries: 8)
        }

        private func requestFocus(on field: NSTextField, token: Int, remainingRetries: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self, weak field] in
                guard let self, let field else { return }
                guard self.parent.focusToken == token else { return }

                if let window = field.window, window.makeFirstResponder(field) {
                    return
                }

                guard remainingRetries > 0 else { return }
                self.requestFocus(on: field, token: token, remainingRetries: remainingRetries - 1)
            }
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
        field.font = NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
        field.textColor = .black
        context.coordinator.textField = field
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self

        if nsView.currentEditor() == nil, nsView.stringValue != text {
            nsView.stringValue = text
        }

        let targetFont = NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
        if nsView.font != targetFont {
            nsView.font = targetFont
        }

        context.coordinator.requestInitialFocusIfNeeded(on: nsView, token: focusToken)
    }
}
