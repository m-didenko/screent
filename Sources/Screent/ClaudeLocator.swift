import Foundation

/// Finds the `claude` CLI. Apps started from Finder or the Dock get a bare PATH, so we check
/// the usual install locations directly (native installer, Homebrew, nvm, volta, fnm, bun) and
/// only then ask the user's interactive login shell, where nvm is usually loaded from ~/.zshrc.
enum ClaudeLocator {
    static let notFoundMessage = "claude CLI not found. Install Claude Code, or link it into ~/.local/bin."

    private static var cached: URL?

    static func find() throws -> URL {
        if let cached, FileManager.default.isExecutableFile(atPath: cached.path) { return cached }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default

        var candidates = fixedCandidates(home: home)
        candidates += nvmCandidates(nvmDir: ProcessInfo.processInfo.environment["NVM_DIR"] ?? "\(home)/.nvm")
        if let path = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return remember(path)
        }
        if let path = fromLoginShell() {
            return remember(path)
        }
        Log.write("claude lookup failed; checked: \(candidates.joined(separator: ", ")) and the login shell")
        throw NSError(domain: "Screent", code: 1, userInfo: [NSLocalizedDescriptionKey: notFoundMessage])
    }

    private static func remember(_ path: String) -> URL {
        let url = URL(fileURLWithPath: path)
        cached = url
        Log.write("claude found: \(path)")
        return url
    }

    // MARK: - Known locations

    static func fixedCandidates(home: String) -> [String] {
        [
            "\(home)/.local/bin/claude",                                    // native installer
            "\(home)/.claude/local/claude",                                 // legacy local install
            "/opt/homebrew/bin/claude",                                     // Homebrew (Apple Silicon)
            "/usr/local/bin/claude",                                        // Homebrew (Intel), npm -g
            "\(home)/.volta/bin/claude",                                    // volta
            "\(home)/.local/share/fnm/aliases/default/bin/claude",          // fnm (XDG)
            "\(home)/Library/Application Support/fnm/aliases/default/bin/claude", // fnm (macOS default)
            "\(home)/.bun/bin/claude",                                      // bun
        ]
    }

    /// nvm: the default alias's version first, then every installed version, newest first.
    static func nvmCandidates(nvmDir: String) -> [String] {
        let versionsDir = "\(nvmDir)/versions/node"
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: versionsDir)) ?? [])
            .filter { $0.hasPrefix("v") }
            .sorted { versionKey($1).lexicographicallyPrecedes(versionKey($0)) } // newest first
        guard !versions.isEmpty else { return [] }

        var ordered: [String] = []
        if let alias = resolveAlias("default", nvmDir: nvmDir),
           let match = matchVersion(alias, in: versions) {
            ordered.append(match)
        }
        ordered += versions.filter { !ordered.contains($0) }
        return ordered.map { "\(versionsDir)/\($0)/bin/claude" }
    }

    /// Follows nvm alias files (default → lts/iron → v20.11.0), at most a few hops.
    static func resolveAlias(_ name: String, nvmDir: String) -> String? {
        var current = name
        for _ in 0..<4 {
            let file = "\(nvmDir)/alias/\(current)"
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else {
                return current == name ? nil : current
            }
            let next = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if next.isEmpty { return nil }
            current = next
        }
        return current
    }

    /// "22" → newest v22.x.x, "v20.11.0" → exact, "node"/"stable"/"lts/*" → newest overall.
    /// `versions` must be sorted newest first.
    static func matchVersion(_ alias: String, in versions: [String]) -> String? {
        let a = alias.hasPrefix("v") ? String(alias.dropFirst()) : alias
        if ["node", "stable", "lts/*"].contains(alias) || alias.hasPrefix("lts/") { return versions.first }
        if versions.contains("v" + a) { return "v" + a }
        return versions.first { String($0.dropFirst()).hasPrefix(a + ".") }
    }

    static func versionKey(_ dir: String) -> [Int] {
        dir.dropFirst().split(separator: ".").map { Int($0) ?? 0 }
    }

    // MARK: - Interactive login shell

    /// `$SHELL -ilc 'command -v claude'`: interactive, so ~/.zshrc / ~/.bashrc (and nvm) are loaded.
    /// Times out so a slow or prompting shell config can't hang the app.
    static func fromLoginShell(timeout: TimeInterval = 5) -> String? {
        let envShell = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        let shell = envShell.isEmpty ? "/bin/zsh" : envShell

        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-ilc", "command -v claude"]
        p.standardInput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let out = Pipe()
        p.standardOutput = out

        let buffer = OutputBuffer()
        out.fileHandleForReading.readabilityHandler = { h in buffer.append(h.availableData) }
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }

        do { try p.run() } catch { return nil }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            // Interactive zsh ignores SIGTERM.
            kill(p.processIdentifier, SIGKILL)
            Log.write("login shell lookup timed out after \(Int(timeout)) s")
        }
        // Let the handler deliver the last chunk. Don't block on readToEnd: something started
        // from the shell config may keep the pipe open.
        Thread.sleep(forTimeInterval: 0.2)
        out.fileHandleForReading.readabilityHandler = nil
        return lastExecutablePath(in: buffer.text)
    }

    /// Interactive configs may print banners; take the last line that is an executable path.
    static func lastExecutablePath(in output: String,
                                   isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        for line in output.split(whereSeparator: \.isNewline).reversed() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("/"), isExecutable(t) { return t }
        }
        return nil
    }
}

/// Thread-safe accumulator for the shell's stdout.
private final class OutputBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func append(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(data: data, encoding: .utf8) ?? "" }
}
