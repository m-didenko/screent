import SwiftUI

struct Entry: Identifiable, Equatable {
    let id = UUID()
    var original: String
    var translation: String
    var isStreaming: Bool
    /// Пояснення абревіатур і здогадки щодо помилок розпізнавання.
    var notes: [String] = []
    let date = Date()
}

enum Status: Equatable {
    case idle
    case listening
    case working
    case paused
    case error(String)
}

/// Стан, який показує панель перекладу.
@MainActor
final class AppModel: ObservableObject {
    @Published var entries: [Entry] = []
    @Published var status: Status = .idle
    @Published var mode: CaptureMode = AppSettings.shared.mode
    @Published var showOriginal = AppSettings.shared.showOriginal
    @Published var hasRegion = AppSettings.shared.region != nil
    @Published var notice: String?
    @Published var paused = false
    @Published var showSettings = false
    @Published var panelOpacity = AppSettings.shared.panelOpacity {
        didSet { AppSettings.shared.panelOpacity = panelOpacity }
    }
    @Published var regionHighlight = AppSettings.shared.regionHighlight {
        didSet { AppSettings.shared.regionHighlight = regionHighlight; onRegionHighlight(regionHighlight) }
    }

    var onTranslate: () -> Void = {}
    var onSelectRegion: () -> Void = {}
    var onSetMode: (CaptureMode) -> Void = { _ in }
    var onToggleOriginal: () -> Void = {}
    var onNewSession: () -> Void = {}
    var onTogglePause: () -> Void = {}
    var onRegionHighlight: (Double) -> Void = { _ in }
    var onQuit: () -> Void = {}

    private var noticeTask: Task<Void, Never>?

    func flash(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { notice = nil }
        }
    }
}

enum Theme {
    static let accent = Color(red: 1.0, green: 0.74, blue: 0.33)
    static let accentNS = NSColor(red: 1.0, green: 0.74, blue: 0.33, alpha: 1)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.40)
    static let ok = Color(red: 0.30, green: 0.85, blue: 0.48)
}
