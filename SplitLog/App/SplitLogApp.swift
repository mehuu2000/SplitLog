//
//  SplitLogApp.swift
//  SplitLog
//
//  Created by 濱田真仁 on 2026/02/17.
//

import SwiftUI

@main
struct SplitLogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
