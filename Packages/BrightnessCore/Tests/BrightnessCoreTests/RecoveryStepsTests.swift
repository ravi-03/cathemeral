import BrightnessCore
import Foundation
import Testing

@Suite struct RecoveryStepsTests {
    /// The README's "If your screen is stuck dim" section, with Markdown emphasis taken out.
    func readmeSection() throws -> [String] {
        let readme = URL(filePath: #filePath)
            .deletingLastPathComponent()  // BrightnessCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // BrightnessCore
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()
            .appending(path: "README.md")
        let lines = try String(contentsOf: readme, encoding: .utf8).components(separatedBy: "\n")
        let start = try #require(lines.firstIndex(of: "## \(RecoverySteps.title)"))
        return lines[(start + 1)...]
            .prefix { !$0.hasPrefix("## ") }
            .map { $0.replacingOccurrences(of: "**", with: "") }
            .filter { !$0.isEmpty }
    }

    @Test func settingsShowsTheSameRecoveryStepsAsTheReadme() throws {
        let numbered = RecoverySteps.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
        #expect(try readmeSection() == [RecoverySteps.intro] + numbered + [RecoverySteps.footer])
    }
}
