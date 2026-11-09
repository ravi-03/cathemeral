import BrightnessCore
import Testing

@Suite struct AppIDTests {
    @Test func anAppIsIdentifiedByItsBundleID() {
        let id = AppID(bundleID: "notion.id", executablePath: "/Applications/Notion.app/Contents/MacOS/Notion")
        #expect(id == AppID(bundleID: "notion.id"))
    }

    @Test func anAppWithoutABundleIDIsIdentifiedByItsExecutablePath() {
        let id = AppID(bundleID: nil, executablePath: "/usr/local/bin/tool")
        #expect(id != nil)
        #expect(id == AppID(bundleID: nil, executablePath: "/usr/local/bin/tool"))
        #expect(id != AppID(bundleID: "/usr/local/bin/tool"))
    }

    @Test func anAppWithNeitherHasNoID() {
        #expect(AppID(bundleID: nil, executablePath: nil) == nil)
        #expect(AppID(bundleID: "", executablePath: "") == nil)
    }
}
