import AppKit
import SwiftUI

// MARK: - Вікно

/// Плаваюче скляне вікно перекладу: завжди зверху, не забирає фокус в інших застосунків.
final class TranslationPanel: NSPanel {
    init(model: AppModel) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
                   styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        minSize = NSSize(width: 360, height: 180)
        appearance = NSAppearance(named: .darkAqua)

        contentView = FirstMouseHostingView(rootView: PanelView().environmentObject(model))

        if !setFrameUsingName("ScreentPanel"), let screen = NSScreen.main {
            let v = screen.visibleFrame
            setFrameOrigin(NSPoint(x: v.maxX - frame.width - 24, y: v.minY + 24))
        }
        setFrameAutosaveName("ScreentPanel")
    }

    override var canBecomeKey: Bool { true }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Корінь

struct PanelView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Header()
            if model.showSettings {
                SettingsStrip()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
            if model.entries.isEmpty { EmptyState() } else { Feed() }
            Footer()
        }
        .background(
            VisualEffect()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .opacity(model.panelOpacity)
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(.white.opacity(0.04 + 0.06 * model.panelOpacity), lineWidth: 1))
        // На прозорому фоні тексту потрібна тінь, щоб читатися поверх будь-чого.
        .shadow(color: .black.opacity(0.6 * (1 - model.panelOpacity)), radius: 2)
        .animation(.easeOut(duration: 0.2), value: model.showSettings)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Шапка

private struct Header: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(status: model.status)
            Text(statusLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .fixedSize()
                .animation(.easeOut(duration: 0.2), value: statusLabel)
            Spacer(minLength: 8)
            IconButton(symbol: model.paused ? "play.fill" : "pause.fill",
                       help: model.paused ? "Відновити переклад (⌥⇧P)" : "Пауза (⌥⇧P)",
                       tint: model.paused ? Theme.ok : nil,
                       action: model.onTogglePause)
            ModeToggle(mode: model.mode, onChange: model.onSetMode)
            IconButton(symbol: "viewfinder", help: "Виділити область (⌥⇧R)", action: model.onSelectRegion)
            IconButton(symbol: "slider.horizontal.3", help: "Налаштування",
                       tint: model.showSettings ? Theme.accent : nil,
                       action: { model.showSettings.toggle() })
            IconButton(symbol: "power", help: "Вийти з Screent", action: model.onQuit)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 44)
        .background(WindowDragArea())
    }

    private var statusLabel: String {
        switch model.status {
        case .idle: return "ПРАЦЮЄ"
        case .listening: return "ПРАЦЮЄ · АВТО"
        case .working: return "ПЕРЕКЛАДАЮ"
        case .paused: return "ПАУЗА"
        case .error: return "ПОМИЛКА"
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .idle, .listening: return Theme.ok.opacity(0.85)
        case .working: return Theme.accent.opacity(0.9)
        case .paused: return .white.opacity(0.4)
        case .error: return Theme.danger
        }
    }
}

private struct StatusDot: View {
    let status: Status

    private var color: Color {
        switch status {
        case .idle, .listening: return Theme.ok
        case .working: return Theme.accent
        case .paused: return .white.opacity(0.35)
        case .error: return Theme.danger
        }
    }

    private var speed: Double? {
        switch status {
        case .working: return 7
        case .listening: return 2.2
        default: return nil
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: speed == nil)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let s = speed.map { (sin(t * $0) + 1) / 2 } ?? 0
            ZStack {
                Circle().fill(color.opacity(0.35 * s)).frame(width: 7 + 8 * s, height: 7 + 8 * s)
                Circle().fill(color).frame(width: 7, height: 7)
            }
            .frame(width: 16, height: 16)
        }
    }
}

private struct ModeToggle: View {
    let mode: CaptureMode
    let onChange: (CaptureMode) -> Void
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            segment(.manual, "Кнопка")
            segment(.auto, "Авто")
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }

    private func segment(_ m: CaptureMode, _ title: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { onChange(m) }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .foregroundStyle(mode == m ? Color.black.opacity(0.85) : .white.opacity(0.55))
                .background {
                    if mode == m {
                        Capsule().fill(Theme.accent).matchedGeometryEffect(id: "segment", in: ns)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint ?? .white.opacity(hover ? 0.9 : 0.55))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(hover ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

// MARK: - Налаштування

private struct SettingsStrip: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SliderRow(title: "Фон панелі", value: $model.panelOpacity, range: 0.1...1)
            SliderRow(title: "Підсвітка зони", value: $model.regionHighlight, range: 0...1)
            HStack(spacing: 8) {
                PillButton(title: "Оригінал", symbol: model.showOriginal ? "eye" : "eye.slash",
                           active: model.showOriginal, action: model.onToggleOriginal)
                PillButton(title: "Нова сесія", symbol: "arrow.counterclockwise", action: model.onNewSession)
                Spacer()
                PillButton(title: "Вийти", symbol: "power", tint: Theme.danger, action: model.onQuit)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 92, alignment: .leading)
            Slider(value: $value, in: range)
                .controlSize(.mini)
                .tint(Theme.accent)
            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 34, alignment: .trailing)
        }
    }
}

private struct PillButton: View {
    let title: String
    let symbol: String
    var active = false
    var tint: Color? = nil
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint ?? .white.opacity(active || hover ? 0.85 : 0.6))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill((tint ?? .white).opacity(hover ? 0.14 : 0.07)))
                .overlay(Capsule().strokeBorder((tint ?? .white).opacity(0.12), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

// MARK: - Стрічка

private struct Feed: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(model.entries) { entry in
                        EntryView(entry: entry,
                                  isLatest: entry.id == model.entries.last?.id,
                                  showOriginal: model.showOriginal)
                            .id(entry.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.never)
            .onChange(of: model.entries) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}

private struct EntryView: View {
    let entry: Entry
    let isLatest: Bool
    let showOriginal: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showOriginal {
                Text(entry.original)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.32))
                    .lineSpacing(1.5)
                    .lineLimit(5)
            }
            translation
                .font(.system(size: 15))
                .lineSpacing(3.5)
                .foregroundStyle(.white.opacity(0.94))
            if !entry.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(entry.notes.enumerated()), id: \.offset) { _, note in
                        NoteRow(note: note)
                    }
                }
                .padding(.top, 2)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Theme.accent.opacity(0.35)).frame(width: 1.5)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isLatest ? 1 : 0.55)
        .animation(.easeOut(duration: 0.25), value: isLatest)
    }

    private var translation: Text {
        if entry.translation.trimmingCharacters(in: .whitespaces).isEmpty && entry.isStreaming {
            return Text("···").foregroundColor(Theme.accent)
        }
        var text = styled(entry.translation)
        if entry.isStreaming { text = text + Text(" ▍").foregroundColor(Theme.accent) }
        return text
    }

    /// Підсвічує мітку мовця «Ім'я: » на початку рядка.
    private func styled(_ s: String) -> Text {
        let lines = s.components(separatedBy: "\n")
        var result = Text("")
        for (i, line) in lines.enumerated() {
            if i > 0 { result = result + Text("\n") }
            if let r = line.range(of: #"^[A-Z][\p{L}.'’-]+(?: [A-Z][\p{L}.'’-]+){0,3}: "#, options: .regularExpression) {
                result = result
                    + Text(line[r]).fontWeight(.semibold).foregroundColor(Theme.accent)
                    + Text(line[r.upperBound...])
            } else {
                result = result + Text(line)
            }
        }
        return result
    }
}

/// Пояснення: «SRS — Software Requirements Specification, …». Термін до « — » виділяємо.
private struct NoteRow: View {
    let note: String

    var body: some View {
        let parts = note.components(separatedBy: " — ")
        Group {
            if parts.count > 1 {
                Text(parts[0]).fontWeight(.semibold).foregroundColor(.white.opacity(0.78))
                    + Text(" — " + parts.dropFirst().joined(separator: " — "))
            } else {
                Text(note)
            }
        }
        .font(.system(size: 11.5))
        .lineSpacing(2)
        .foregroundStyle(.white.opacity(0.5))
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct EmptyState: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text(model.hasRegion
                 ? (model.mode == .auto ? "Стежу за областю — переклад з'явиться тут"
                                        : "Натисніть ⌥Space, щоб перекласти")
                 : "Спочатку виділіть область із текстом")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
            if !model.hasRegion {
                Button(action: model.onSelectRegion) {
                    Label("Виділити область", systemImage: "viewfinder")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(.white.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Нижня панель

private struct Footer: View {
    @EnvironmentObject var model: AppModel

    private var hint: (String, Color) {
        if case .error(let message) = model.status { return (message, Theme.danger) }
        if let notice = model.notice { return (notice, .white.opacity(0.7)) }
        return model.mode == .auto
            ? ("Переклад з'являється, щойно текст зміниться", .white.opacity(0.38))
            : ("⌥Space — перекласти  ·  ⌥⇧P — пауза", .white.opacity(0.38))
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(hint.0)
                .font(.system(size: 11))
                .foregroundStyle(hint.1)
                .lineLimit(2)
                .help(hint.0)
            Spacer(minLength: 8)
            if model.mode == .manual {
                Button(action: model.onTranslate) {
                    HStack(spacing: 8) {
                        Text(model.status == .working ? "Перекладаю" : "Перекласти")
                            .font(.system(size: 12, weight: .semibold))
                        Text("⌥␣")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .opacity(0.55)
                    }
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Capsule().fill(Theme.accent))
                    .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 2)
                }
                .buttonStyle(PressStyle())
                .disabled(!model.hasRegion || model.paused)
                .opacity(model.hasRegion && !model.paused ? 1 : 0.4)
            } else {
                let tone = model.paused ? Color.white.opacity(0.45) : Theme.ok
                Button(action: model.onTogglePause) {
                    HStack(spacing: 6) {
                        Image(systemName: model.paused ? "play.fill" : "pause.fill").font(.system(size: 9))
                        Text(model.paused ? "ПАУЗА" : "АВТО")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.6)
                    }
                    .foregroundStyle(tone)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(tone.opacity(0.1)))
                    .overlay(Capsule().strokeBorder(tone.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(PressStyle())
                .help(model.paused ? "Відновити (⌥⇧P)" : "Пауза (⌥⇧P)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(WindowDragArea())
    }
}

// MARK: - Допоміжне

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Дозволяє перетягувати вікно за шапку/низ.
private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
