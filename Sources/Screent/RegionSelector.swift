import AppKit

/// Повноекранний оверлей для виділення області мишкою.
@MainActor
final class RegionSelector {
    private var windows: [NSWindow] = []
    private var completion: ((CGRect?) -> Void)?

    var isActive: Bool { !windows.isEmpty }

    func begin(_ completion: @escaping (CGRect?) -> Void) {
        guard windows.isEmpty else { return }
        self.completion = completion

        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless,
                                       backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { [weak self, weak window] rect in
                guard let self else { return }
                if let rect, let window {
                    self.finish(window.convertToScreen(rect))
                } else {
                    self.finish(nil)
                }
            }
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        let key = windows.first(where: { $0.frame.contains(mouse) }) ?? windows.first
        key?.makeKey()
        key?.makeFirstResponder(key?.contentView)
    }

    private func finish(_ rect: CGRect?) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let done = completion
        completion = nil
        done?(rect)
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var current: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private var selection: CGRect? {
        guard let s = start, let c = current else { return nil }
        return CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                      width: abs(s.x - c.x), height: abs(s.y - c.y)).integral
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        if let r = selection {
            dim.append(NSBezierPath(rect: r))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.45).setFill()
        dim.fill()

        guard let r = selection else {
            drawHint()
            return
        }

        NSColor.white.withAlphaComponent(0.85).setStroke()
        let border = NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()

        drawCornerBrackets(in: r.insetBy(dx: -4, dy: -4), length: 14, width: 2.5, color: Theme.accentNS)

        let label = "\(Int(r.width)) × \(Int(r.height))"
        let below = CGPoint(x: r.midX, y: r.minY - 22)
        let above = CGPoint(x: r.midX, y: r.maxY + 22)
        drawPill(label, center: below.y > 20 ? below : above, mono: true)
    }

    private func drawHint() {
        let center = CGPoint(x: bounds.midX, y: bounds.maxY * 0.72)
        drawPill("Виділіть область із текстом", center: center, mono: false, size: 13)
        drawPill("Esc — скасувати", center: CGPoint(x: center.x, y: center.y - 32),
                 mono: false, size: 11, alpha: 0.55)
    }

    private func drawPill(_ text: String, center: CGPoint, mono: Bool, size: CGFloat = 11, alpha: CGFloat = 1) {
        let font = mono
            ? NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
            : NSFont.systemFont(ofSize: size, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.92 * alpha),
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let pill = CGRect(x: center.x - size.width / 2 - 10, y: center.y - size.height / 2 - 4,
                          width: size.width + 20, height: size.height + 8)
        let path = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
        NSColor(white: 0.08, alpha: 0.82 * max(alpha, 0.7)).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 1
        path.stroke()
        str.draw(at: CGPoint(x: pill.minX + 10, y: pill.minY + 4))
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let r = selection, r.width >= 24, r.height >= 12 {
            onFinish?(r)
        } else {
            start = nil
            current = nil
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) } else { super.keyDown(with: event) }
    }
}

/// Тонкі кутові дужки навколо прямокутника — спільний елемент стилю.
func drawCornerBrackets(in r: CGRect, length: CGFloat, width: CGFloat, color: NSColor) {
    let l = min(length, r.width / 3, r.height / 3)
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    // лівий нижній
    path.move(to: CGPoint(x: r.minX, y: r.minY + l)); path.line(to: CGPoint(x: r.minX, y: r.minY)); path.line(to: CGPoint(x: r.minX + l, y: r.minY))
    // правий нижній
    path.move(to: CGPoint(x: r.maxX - l, y: r.minY)); path.line(to: CGPoint(x: r.maxX, y: r.minY)); path.line(to: CGPoint(x: r.maxX, y: r.minY + l))
    // правий верхній
    path.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); path.line(to: CGPoint(x: r.maxX, y: r.maxY)); path.line(to: CGPoint(x: r.maxX - l, y: r.maxY))
    // лівий верхній
    path.move(to: CGPoint(x: r.minX + l, y: r.maxY)); path.line(to: CGPoint(x: r.minX, y: r.maxY)); path.line(to: CGPoint(x: r.minX, y: r.maxY - l))
    color.setStroke()
    path.stroke()
}
