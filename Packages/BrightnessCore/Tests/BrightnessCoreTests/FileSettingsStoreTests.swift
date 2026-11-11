import BrightnessCore
import Foundation
import Testing

@MainActor @Suite struct FileSettingsStoreTests {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("FileSettingsStoreTests-\(UUID().uuidString)", isDirectory: true)
    var fileURL: URL { folder.appendingPathComponent("settings.json") }

    func makeStore() -> FileSettingsStore {
        FileSettingsStore(fileURL: fileURL)
    }

    @Test func savedSettingsLoadBackUnchanged() {
        var settings = Settings()
        settings.defaultLevel = Level(0.8)
        settings.appSettings[notion.id] = Level(0.4)
        settings.appSettings[unbundled] = Level(0.25)
        settings.isEnabled = false

        makeStore().save(settings)

        #expect(makeStore().load() == settings)
    }

    @Test func aMissingFileLoadsTheDefaults() {
        #expect(makeStore().load() == Settings())
    }

    @Test func aFileFromSchemaVersion1LoadsWithDimmingOn() throws {
        try write(
            """
            {"schemaVersion": 1, "defaultLevel": 0.8,
             "appSettings": [{"bundleID": "notion.id", "level": 0.4}]}
            """)

        let settings = makeStore().load()

        #expect(settings == Settings(appSettings: [notion.id: Level(0.4)], defaultLevel: Level(0.8), isEnabled: true))
        #expect(try setAsideFiles().isEmpty)
    }

    @Test func levelsBelowTheFloorInTheFileLoadAsTenPercent() throws {
        try write(
            """
            {"schemaVersion": 1, "defaultLevel": 0.05,
             "appSettings": [{"bundleID": "notion.id", "level": 0}]}
            """)

        let settings = makeStore().load()

        #expect(settings.defaultLevel.fraction == 0.1)
        #expect(settings.appSettings[notion.id]?.fraction == 0.1)
    }

    @Test func theFileRecordsItsSchemaVersion() throws {
        makeStore().save(Settings())

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        #expect(json?["schemaVersion"] as? Int == FileSettingsStore.schemaVersion)
    }

    @Test(arguments: [
        "{ not json",
        #"{"schemaVersion": 1, "defaultLevel": "dim", "appSettings": []}"#,
        #"{"defaultLevel": 0.5, "appSettings": []}"#,
    ])
    func aCorruptFileIsSetAsideAndTheDefaultsLoad(contents: String) throws {
        try write(contents)

        #expect(makeStore().load() == Settings())

        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        let setAside = try setAsideFiles()
        #expect(setAside.count == 1)
        let first = try #require(setAside.first)
        #expect(try String(contentsOf: first, encoding: .utf8) == contents)
    }

    @Test func aFileFromANewerSchemaVersionIsSetAside() throws {
        try write(#"{"schemaVersion": 99, "defaultLevel": 0.5, "appSettings": []}"#)

        #expect(makeStore().load() == Settings())

        #expect(try setAsideFiles().count == 1)
    }

    @Test func aSecondCorruptFileDoesNotReplaceTheFirst() throws {
        try write("{ first")
        _ = makeStore().load()
        try write("{ second")
        _ = makeStore().load()

        #expect(try setAsideFiles().count == 2)
    }

    @Test func savingAfterRecoveryWritesAFreshFile() throws {
        try write("{ not json")
        let store = makeStore()
        _ = store.load()

        store.save(Settings(defaultLevel: Level(0.6)))

        #expect(makeStore().load().defaultLevel == Level(0.6))
        #expect(try setAsideFiles().count == 1)
    }

    /// Files set aside next to the settings file, named with a date suffix.
    func setAsideFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("settings-corrupt-") }
    }

    func write(_ contents: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: fileURL)
    }
}

let unbundled = AppID(bundleID: nil, executablePath: "/usr/local/bin/tool")!
