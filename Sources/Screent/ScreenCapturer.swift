import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case permission
    case noScreen
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .permission:
            return "No Screen Recording permission: System Settings → Privacy & Security → Screen & System Audio Recording"
        case .noScreen:
            return "The region is off-screen — select it again"
        case .noDisplay:
            return "Could not find the display to capture"
        }
    }
}

/// Робить знімок області екрана через ScreenCaptureKit, виключаючи власні вікна застосунку.
@MainActor
final class ScreenCapturer {
    private var cache: (content: SCShareableContent, time: Date)?
    private var lastCaptureOK: Bool?

    func capture(region: CGRect) async throws -> CGImage {

        let screen = NSScreen.screens.max { a, b in
            area(a.frame.intersection(region)) < area(b.frame.intersection(region))
        }
        guard let screen, area(screen.frame.intersection(region)) > 0 else { throw CaptureError.noScreen }
        let clipped = screen.frame.intersection(region)

        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let displayID = screen.deviceDescription[key] as? CGDirectDisplayID else { throw CaptureError.noDisplay }

        let content = try await shareableContent()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            cache = nil
            throw CaptureError.noDisplay
        }
        let ownApps = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        // Координати дисплея: початок — лівий верхній кут.
        let local = CGRect(x: clipped.minX - screen.frame.minX,
                           y: screen.frame.maxY - clipped.maxY,
                           width: clipped.width, height: clipped.height)
        let scale = max(screen.backingScaleFactor, 2) // дрібний текст краще розпізнається у 2×

        let config = SCStreamConfiguration()
        config.sourceRect = local
        config.width = Int(local.width * scale)
        config.height = Int(local.height * scale)
        config.showsCursor = false
        config.captureResolution = .best

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Обгортка, що перетворює відмову системи на зрозуміле повідомлення і пише діагностику.
    func captureLogged(region: CGRect) async throws -> CGImage {
        do {
            let img = try await capture(region: region)
            if lastCaptureOK != true {
                Log.write("capture ok \(img.width)x\(img.height) preflight=\(CGPreflightScreenCaptureAccess())")
            }
            lastCaptureOK = true
            return img
        } catch {
            let ns = error as NSError
            Log.write("capture FAILED preflight=\(CGPreflightScreenCaptureAccess()) domain=\(ns.domain) code=\(ns.code) \(ns.localizedDescription)")
            cache = nil
            lastCaptureOK = false
            if ns.domain == SCStreamErrorDomain || !CGPreflightScreenCaptureAccess() {
                throw CaptureError.permission
            }
            throw error
        }
    }

    /// Реальне звернення до ScreenCaptureKit — саме воно додає застосунок у список
    /// «Запис екрана» і показує системний запит.
    static func requestPermission() {
        Task {
            do {
                let c = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                Log.write("launch: SCShareableContent ok, displays=\(c.displays.count) preflight=\(CGPreflightScreenCaptureAccess())")
            } catch {
                let ns = error as NSError
                Log.write("launch: SCShareableContent FAILED domain=\(ns.domain) code=\(ns.code) preflight=\(CGPreflightScreenCaptureAccess())")
                CGRequestScreenCaptureAccess()
            }
        }
    }

    private func shareableContent() async throws -> SCShareableContent {
        if let cache, Date().timeIntervalSince(cache.time) < 20 { return cache.content }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        cache = (content, Date())
        return content
    }

    private func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
}
