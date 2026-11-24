import AppKit

/// Ледь помітні кутові дужки навколо вибраної області. Не перехоплює мишку
/// і не потрапляє в знімок (вікна застосунку виключені із захоплення).
@MainActor
final class RegionFrameWindow: NSWindow {
    private let frameView = FrameView()
    private static let outset: CGFloat = 8

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = frameView
    }

    func show(region: CGRect) {
        setFrame(region.insetBy(dx: -Self.outset, dy: -Self.outset), display: true)
        orderFrontRegardless()
    }

    func setActive(_ active: Bool) { frameView.active = active }
    func setPaused(_ paused: Bool) { frameView.paused = paused }
    func setHighlight(_ level: Double) { frameView.level = CGFloat(level) }
    func flash() { frameView.flash() }
}

private final class FrameView: NSView {
    var active = false { didSet { needsDisplay = true } }
    var paused = false { didSet { needsDisplay = true } }
    /// Яскравість підсвітки з налаштувань: 0…1.
    var level: CGFloat = 0.5 { didSet { needsDisplay = true } }
    /// Відступ рамки від області (див. RegionFrameWindow.outset).
    private let inset: CGFloat = 8
    private var highlight: CGFloat = 0 { didSet { needsDisplay = true } }
    private var timer: Timer?

    override func draw(_ dirtyRect: NSRect) {
        // Ледь помітна сіра підсвітка самої області (вікно не потрапляє в знімок, OCR не заважає).
        let area = bounds.insetBy(dx: inset, dy: inset)
        let fill = NSBezierPath(roundedRect: area, xRadius: 3, yRadius: 3)
        let fillAlpha = 0.14 * level * (paused ? 0.5 : 1) + 0.05 * highlight
        NSColor(white: 0.55, alpha: fillAlpha).setFill()
        fill.fill()

        let base = NSColor.white.withAlphaComponent(active ? 0.55 : 0.4)
        let color = base.blended(withFraction: max(highlight, active ? 0.55 : 0), of: Theme.accentNS) ?? base
        drawCornerBrackets(in: bounds.insetBy(dx: 3, dy: 3), length: 12,
                           width: 2 + highlight, color: color.withAlphaComponent((0.45 + 0.55 * max(highlight, active ? 0.4 : 0))
                                                                 * min(1, 0.25 + level * 1.5)))
    }

    func flash() {
        timer?.invalidate()
        highlight = 1
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                self.highlight = max(0, self.highlight - 0.04)
                if self.highlight == 0 { t.invalidate() }
            }
        }
    }
}
