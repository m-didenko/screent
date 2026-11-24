import Foundation
import CoreGraphics

enum CaptureMode: String {
    case manual, auto
}

/// Налаштування, що зберігаються між запусками.
final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    var mode: CaptureMode {
        get { CaptureMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .manual }
        set { defaults.set(newValue.rawValue, forKey: "mode") }
    }

    /// Аліас моделі для Claude Code: sonnet / haiku / opus.
    var model: String {
        get { defaults.string(forKey: "model") ?? "sonnet" }
        set { defaults.set(newValue, forKey: "model") }
    }

    var showOriginal: Bool {
        get { defaults.object(forKey: "showOriginal") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showOriginal") }
    }

    var showFrame: Bool {
        get { defaults.object(forKey: "showFrame") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showFrame") }
    }

    /// Непрозорість фону панелі: 0.1…1.
    var panelOpacity: Double {
        get { defaults.object(forKey: "panelOpacity") as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: "panelOpacity") }
    }

    /// Яскравість підсвітки зони захоплення: 0…1.
    var regionHighlight: Double {
        get { defaults.object(forKey: "regionHighlight") as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: "regionHighlight") }
    }

    /// Ім'я користувача та його варіанти через кому — для сповіщень у авто-режимі.
    var myNames: String {
        get { defaults.string(forKey: "myNames") ?? "" }
        set { defaults.set(newValue, forKey: "myNames") }
    }

    /// Перекладати українською. Вимкнено — англійський режим: стрічка й підказки англійською.
    var translateEnabled: Bool {
        get { defaults.object(forKey: "translateEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "translateEnabled") }
    }

    /// AI-підказки: що сказати на мітингу.
    var hintsEnabled: Bool {
        get { defaults.object(forKey: "hintsEnabled") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "hintsEnabled") }
    }

    /// Сповіщення про згадку імені вимкнено.
    var alertsMuted: Bool {
        get { defaults.bool(forKey: "alertsMuted") }
        set { defaults.set(newValue, forKey: "alertsMuted") }
    }

    /// Область захоплення в глобальних координатах AppKit (початок — лівий нижній кут).
    var region: CGRect? {
        get {
            guard let a = defaults.array(forKey: "region") as? [Double], a.count == 4 else { return nil }
            return CGRect(x: a[0], y: a[1], width: a[2], height: a[3])
        }
        set {
            if let r = newValue {
                defaults.set([r.origin.x, r.origin.y, r.width, r.height].map(Double.init), forKey: "region")
            } else {
                defaults.removeObject(forKey: "region")
            }
        }
    }
}
