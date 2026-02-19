//
//  FileSessionStore.swift
//  SplitLog
//
//  Created by Codex on 2026/02/20.
//

import Foundation

struct FileSessionStore: SessionStore {
    private let fileURL: URL?

    init(fileURL: URL? = FileSessionStore.makeDefaultURL()) {
        self.fileURL = fileURL
    }

    func saveSnapshot(_ snapshot: StopwatchStorageSnapshot?) throws {
        guard let fileURL else { return }

        guard let snapshot else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    func loadSnapshot() throws -> StopwatchStorageSnapshot? {
        guard let fileURL else { return nil }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(StopwatchStorageSnapshot.self, from: data)
    }

    private static func makeDefaultURL() -> URL? {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let directory = appSupportURL.appendingPathComponent("SplitLog", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        return directory.appendingPathComponent("sessions.json")
    }
}
