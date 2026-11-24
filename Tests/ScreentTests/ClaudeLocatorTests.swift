import Foundation
import Testing
@testable import Screent

@Suite struct ClaudeLocatorTests {
    /// Builds a fake ~/.nvm with the given versions (each with bin/claude) and alias files.
    private func makeNVM(versions: [String], aliases: [String: String]) throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nvm-\(UUID().uuidString)").path
        for v in versions {
            let bin = "\(root)/versions/node/\(v)/bin"
            try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: "\(bin)/claude", contents: Data("#!/bin/sh\n".utf8),
                                           attributes: [.posixPermissions: 0o755])
        }
        for (name, value) in aliases {
            let file = "\(root)/alias/\(name)"
            try FileManager.default.createDirectory(atPath: (file as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
            try value.write(toFile: file, atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test func defaultAliasMajorVersion() throws {
        let nvm = try makeNVM(versions: ["v18.20.4", "v22.3.0", "v22.11.0", "v23.1.0"], aliases: ["default": "22\n"])
        let c = ClaudeLocator.nvmCandidates(nvmDir: nvm)
        #expect(c.first == "\(nvm)/versions/node/v22.11.0/bin/claude")
        #expect(c.count == 4)
        #expect(c[1].contains("v23.1.0")) // then the rest, newest first
    }

    @Test func aliasChainAndExactVersion() throws {
        let nvm = try makeNVM(versions: ["v20.11.0", "v22.11.0"], aliases: ["default": "lts/iron", "lts/iron": "v20.11.0"])
        #expect(ClaudeLocator.nvmCandidates(nvmDir: nvm).first?.contains("v20.11.0") == true)
    }

    @Test func noAliasUsesNewest() throws {
        let nvm = try makeNVM(versions: ["v9.0.0", "v10.1.0", "v8.17.0"], aliases: [:])
        #expect(ClaudeLocator.nvmCandidates(nvmDir: nvm).first?.contains("v10.1.0") == true)
    }

    @Test func noNVM() {
        #expect(ClaudeLocator.nvmCandidates(nvmDir: "/nonexistent/.nvm").isEmpty)
    }

    @Test func parsesBannerOutput() {
        let out = "hi\nWelcome back 👋\nalias claude='claude --foo'\n/Users/x/.nvm/versions/node/v22.11.0/bin/claude\n\n"
        let path = ClaudeLocator.lastExecutablePath(in: out) { $0.hasSuffix("/claude") }
        #expect(path == "/Users/x/.nvm/versions/node/v22.11.0/bin/claude")
        #expect(ClaudeLocator.lastExecutablePath(in: "hi\nnothing here") { _ in true } == nil)
    }

    /// The real shell fallback finds claude even with a bare PATH (as when launched from Finder),
    /// as long as it is reachable from the user's shell config.
    @Test func interactiveShellFindsClaude() throws {
        guard FileManager.default.isExecutableFile(atPath: "/bin/zsh") else { return }
        let path = ClaudeLocator.fromLoginShell(timeout: 8)
        #expect(path == nil || path!.hasSuffix("claude"))
    }
}
