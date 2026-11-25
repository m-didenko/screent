import Foundation
import CoreGraphics

enum CaptureMode: String {
    case manual, auto
}

/// Мова перекладу.
enum TargetLanguage: String, CaseIterable {
    case uk, ru

    /// Як мову називаємо в повідомленнях для Claude.
    var promptName: String { self == .uk ? "Ukrainian" : "Russian" }
    var title: String { self == .uk ? "Ukrainian" : "Russian" }
    var code: String { self == .uk ? "UA" : "RU" }
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
    /// 50% (за замовчуванням) = колишні 100%; вище — яскравіше, до подвійної інтенсивності.
    var regionHighlight: Double {
        get {
            if let v = defaults.object(forKey: "regionHighlight2") as? Double { return v }
            // Перенесення зі старої шкали, де 100% було максимумом.
            if let old = defaults.object(forKey: "regionHighlight") as? Double { return old / 2 }
            return 0.5
        }
        set { defaults.set(newValue, forKey: "regionHighlight2") }
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

    /// Версія, оновлення до якої користувач сховав хрестиком (меню все одно його пропонує).
    var skippedUpdate: String? {
        get { defaults.string(forKey: "skippedUpdate") }
        set { defaults.set(newValue, forKey: "skippedUpdate") }
    }

    /// Сповіщення про згадку імені вимкнено.
    var alertsMuted: Bool {
        get { defaults.bool(forKey: "alertsMuted") }
        set { defaults.set(newValue, forKey: "alertsMuted") }
    }

    /// Розмір тексту стрічки: 0…1, 0.5 = базовий.
    var textSize: Double {
        get { defaults.object(forKey: "textSize") as? Double ?? 0.5 }
        set { defaults.set(newValue, forKey: "textSize") }
    }

    var targetLanguage: TargetLanguage {
        get { TargetLanguage(rawValue: defaults.string(forKey: "targetLanguage") ?? "") ?? .uk }
        set { defaults.set(newValue.rawValue, forKey: "targetLanguage") }
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
