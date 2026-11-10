import Foundation
import os

/// App settings and preferences: everything Cathemeral remembers between launches.
public struct Settings: Equatable, Sendable {
    /// The level the user saved for each app. An app missing here uses the default level.
    public var appSettings: [AppID: Level]

    /// The level for any app without its own app setting.
    public var defaultLevel: Level

    public init(appSettings: [AppID: Level] = [:], defaultLevel: Level = .full) {
        self.appSettings = appSettings
        self.defaultLevel = defaultLevel
    }
}

/// Loads and saves settings.
@MainActor public protocol SettingsStore: AnyObject {
    /// The saved settings, or the defaults if there are none.
    func load() -> Settings

    func save(_ settings: Settings)
}

/// Keeps settings in memory only. They are lost on quit.
@MainActor public final class InMemorySettingsStore: SettingsStore {
    private var settings: Settings

    public init(_ settings: Settings = Settings()) {
        self.settings = settings
    }

    public func load() -> Settings { settings }

    public func save(_ settings: Settings) {
        self.settings = settings
    }
}

/// Keeps settings in one JSON file with a schema version.
@MainActor public final class FileSettingsStore: SettingsStore {
    /// The layout version written to the file. Bump it, and migrate older files on load, whenever
    /// the layout changes.
    public nonisolated static let schemaVersion = 1

    /// Where the app keeps its settings: `~/Library/Application Support/Cathemeral/settings.json`.
    public nonisolated static var standardFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "Cathemeral/settings.json")
    }

    private let fileURL: URL

    public init(fileURL: URL = standardFileURL) {
        self.fileURL = fileURL
    }

    /// The settings in the file. If there is no file, the defaults. If the file can't be read as
    /// this schema version, it is renamed with a date suffix so nothing is lost, and the defaults
    /// load.
    public func load() -> Settings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Settings() }
        do {
            let file = try JSONDecoder().decode(SettingsFile.self, from: Data(contentsOf: fileURL))
            guard file.schemaVersion == Self.schemaVersion else {
                throw UnknownSchemaVersion(version: file.schemaVersion)
            }
            return file.settings
        } catch {
            setAside(because: error)
            return Settings()
        }
    }

    /// Writes the whole file atomically, so a crash mid-write leaves the old file intact.
    public func save(_ settings: Settings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(SettingsFile(settings)).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Couldn't save settings to \(self.fileURL.path, privacy: .public): \(error)")
        }
    }

    /// Renames the unreadable file to `settings-corrupt-<date>.json` beside it, adding a counter
    /// if that name is taken.
    private func setAside(because error: any Error) {
        let folder = fileURL.deletingLastPathComponent()
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let date = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        var destination = folder.appendingPathComponent("\(stem)-corrupt-\(date).json")
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent("\(stem)-corrupt-\(date)-\(counter).json")
            counter += 1
        }
        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
            logger.error(
                "Settings file unreadable (\(error)); set aside as \(destination.lastPathComponent, privacy: .public)")
        } catch {
            logger.error("Couldn't set aside the unreadable settings file: \(error)")
        }
    }
}

private let logger = Logger(subsystem: "io.github.ravi-03.cathemeral", category: "settings")

private struct UnknownSchemaVersion: Error {
    let version: Int
}

/// The file's JSON layout. App settings are a list so each app reads clearly when hand-edited:
/// `{"bundleID": "notion.id", "level": 0.4}`.
private struct SettingsFile: Codable {
    struct Entry: Codable {
        var bundleID: String?
        var executablePath: String?
        var level: Double
    }

    var schemaVersion: Int
    var defaultLevel: Double
    var appSettings: [Entry]

    init(_ settings: Settings) {
        schemaVersion = FileSettingsStore.schemaVersion
        defaultLevel = settings.defaultLevel.fraction
        appSettings = settings.appSettings
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { app, level in
                Entry(bundleID: app.bundleID, executablePath: app.executablePath, level: level.fraction)
            }
    }

    var settings: Settings {
        var appSettings: [AppID: Level] = [:]
        for entry in self.appSettings {
            if let app = AppID(bundleID: entry.bundleID, executablePath: entry.executablePath) {
                appSettings[app] = Level(entry.level)
            }
        }
        return Settings(appSettings: appSettings, defaultLevel: Level(defaultLevel))
    }
}
