import Foundation
import Security

/// A release on GitHub that is newer than the running app.
struct ReleaseInfo: Equatable {
    let version: String
    let zipURL: URL
    let pageURL: URL
}

/// Checks the GitHub "latest release" of this repo. No personal data is sent: just an anonymous
/// request with a generic User-Agent.
enum UpdateChecker {
    static let api = URL(string: "https://api.github.com/repos/m-didenko/screent/releases/latest")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func latest() async throws -> ReleaseInfo? {
        var req = URLRequest(url: api, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Screent/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> ReleaseInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              obj["draft"] as? Bool != true, obj["prerelease"] as? Bool != true,
              let page = (obj["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = obj["assets"] as? [[String: Any]],
              let zip = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true })?["browser_download_url"] as? String,
              let zipURL = URL(string: zip) else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return ReleaseInfo(version: version, zipURL: zipURL, pageURL: page)
    }

    /// "1.0.0.10" > "1.0.0.9"; missing parts count as 0.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    private static func parts(_ v: String) -> [Int] {
        (v.hasPrefix("v") ? String(v.dropFirst()) : v).split(separator: ".").map { Int($0) ?? 0 }
    }
}

enum UpdateError: LocalizedError {
    case download, badArchive, signature, version
    var errorDescription: String? {
        switch self {
        case .download: return "Couldn't download the update"
        case .badArchive: return "The update archive has no Screent.app"
        case .signature: return "The update isn't signed like this copy"
        case .version: return "The downloaded app isn't newer"
        }
    }
}

/// Downloads the release zip, checks that the new app is signed with the same certificate as
/// the running one (so Screen Recording access is kept and nobody else's build gets installed),
/// swaps it in place of the running bundle and relaunches.
enum UpdateInstaller {
    static func install(_ release: ReleaseInfo) async throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("ScreentUpdate-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let (tmp, resp) = try await URLSession.shared.download(from: release.zipURL)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.download }
        let zip = work.appendingPathComponent("update.zip")
        try fm.moveItem(at: tmp, to: zip)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, work.path]
        try unzip.run()
        unzip.waitUntilExit()
        let newApp = work.appendingPathComponent("Screent.app")
        guard unzip.terminationStatus == 0, fm.fileExists(atPath: newApp.path) else { throw UpdateError.badArchive }

        guard hasSameSigner(newApp) else { throw UpdateError.signature }
        let newVersion = Bundle(url: newApp)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard UpdateChecker.isNewer(newVersion, than: UpdateChecker.currentVersion) else { throw UpdateError.version }

        _ = try fm.replaceItemAt(Bundle.main.bundleURL, withItemAt: newApp)
        Log.write("updated to \(newVersion)")
    }

    /// The new bundle must satisfy the running app's designated requirement
    /// (same bundle ID and the same signing certificate).
    static func hasSameSigner(_ app: URL) -> Bool {
        var me: SecCode?
        var meStatic: SecStaticCode?
        var requirement: SecRequirement?
        var other: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &meStatic) == errSecSuccess, let meStatic,
              SecCodeCopyDesignatedRequirement(meStatic, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &other) == errSecSuccess, let other else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(other, flags, requirement)
        if status != errSecSuccess { Log.write("update signature check failed: \(status)") }
        return status == errSecSuccess
    }

    /// Opens the (already replaced) bundle again once this process has quit.
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
    }
}
