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
        minSize = NSSize(width: 440, height: 180)
        appearance = NSAppearance(named: .darkAqua)

        self.model = model
        let host = FirstMouseHostingView(rootView: PanelView().environmentObject(model))
        // Розмір вікна задає користувач, а не вміст: інакше довга стрічка розтягує вікно за межі екрана.
        host.sizingOptions = []
        contentView = host

        if !setFrameUsingName("ScreentPanel"), let screen = NSScreen.main {
            let v = screen.visibleFrame
            setFrameOrigin(NSPoint(x: v.maxX - frame.width - 24, y: v.minY + 24))
        }
        setFrameAutosaveName("ScreentPanel")
        setFrame(frame, display: false) // застосувати обмеження до збереженого розміру
    }

    override var canBecomeKey: Bool { true }

    private weak var model: AppModel?

    /// Прокрутка коліщатком/трекпадом — ознака, що користувач гортає сам (а не автопрокрутка).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel { model?.lastUserScroll = Date() }
        super.sendEvent(event)
    }

    /// Вікно ніколи не більше за видиму частину екрана і не виходить за її межі.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(clamped(frameRect), display: flag)
    }

    private func clamped(_ rect: NSRect) -> NSRect {
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? screen ?? NSScreen.main
        guard let v = screen?.visibleFrame else { return rect }
        var r = rect
        r.size.width = min(max(r.width, minSize.width), v.width)
        r.size.height = min(max(r.height, minSize.height), v.height)
        if r.maxY > v.maxY { r.origin.y = v.maxY - r.height }
        if r.minY < v.minY { r.origin.y = v.minY }
        if r.maxX > v.maxX { r.origin.x = v.maxX - r.width }
        if r.minX < v.minX { r.origin.x = v.minX }
        return r
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Корінь

struct PanelView: View {
    @EnvironmentObject var model: AppModel

    /// 0 при ≤30%, до 0.9 при 100%.
    private var darkTint: Double { max(0, (model.panelOpacity - 0.3) / 0.7) * 0.9 }

    var body: some View {
        VStack(spacing: 0) {
            Header()
            if model.showSettings {
                SettingsStrip()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let mention = model.mention {
                MentionBanner(mention: mention, onDismiss: model.onDismissMention)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
            Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
            if model.entries.isEmpty { EmptyState() } else { Feed() }
            Footer()
        }
        .background(
            ZStack {
                VisualEffect()
                // Сам матеріал напівпрозорий навіть на 100%, тож поверх нього — темний шар:
                // на 100% фон майже суцільний, і текст читається поверх будь-чого.
                Color(white: 0.07).opacity(darkTint)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(min(1, model.panelOpacity * 1.6))
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(.white.opacity(0.04 + 0.06 * model.panelOpacity), lineWidth: 1))
        // На прозорому фоні тексту потрібна тінь, щоб читатися поверх будь-чого.
        .shadow(color: .black.opacity(0.6 * (1 - model.panelOpacity)), radius: 2)
        .animation(.easeOut(duration: 0.2), value: model.showSettings)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.mention?.id)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Шапка

private struct Header: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
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
            IconButton(symbol: bellSymbol, help: bellHelp, tint: bellTint,
                       action: { model.alertsMuted.toggle(); model.flash(model.alertsMuted ? "Сповіщення вимкнено" : "Сповіщення увімкнено") })
            IconButton(symbol: "viewfinder", help: "Виділити область (⌥⇧R)", action: model.onSelectRegion)
            IconButton(symbol: "arrow.counterclockwise", help: "Нова сесія — очистити стрічку й контекст Claude",
                       action: model.onNewSession)
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

    private var hasName: Bool { !model.myNames.trimmingCharacters(in: .whitespaces).isEmpty }
    private var bellSymbol: String { model.alertsMuted ? "bell.slash" : "bell.fill" }
    private var bellTint: Color? {
        if model.alertsMuted { return .white.opacity(0.35) }
        return hasName ? Theme.accent : nil
    }
    private var bellHelp: String {
        if model.alertsMuted { return "Сповіщення про згадку імені вимкнено — увімкнути" }
        return hasName ? "Вимкнути сповіщення про згадку імені"
                       : "Сповіщення: вкажіть своє ім'я в налаштуваннях (працює в авто-режимі)"
    }

    private var statusLabel: String {
        switch model.status {
        case .idle: return "ПРАЦЮЄ"
        case .listening: return "ПРАЦЮЄ"
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
                .lineLimit(1)
                .fixedSize()
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
            HStack(spacing: 10) {
                Text("Функції")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 92, alignment: .leading)
                FeatureChip(title: "Переклад", symbol: "character.bubble", color: Theme.accent,
                            isOn: $model.translateEnabled)
                    .help("Вимкнено — англійський режим: текст і підказки англійською")
                FeatureChip(title: "Підказки", symbol: "lightbulb", color: Theme.hint,
                            isOn: $model.hintsEnabled)
                    .help("AI радить, що сказати на мітингу (англійською + переклад)")
                Spacer()
            }
            SliderRow(title: "Фон панелі", value: $model.panelOpacity, range: 0.1...1)
            SliderRow(title: "Підсвітка зони", value: $model.regionHighlight, range: 0...1)
            HStack(spacing: 10) {
                Text("Моє ім'я")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 92, alignment: .leading)
                TextField("", text: $model.myNames, prompt: Text("Nick, Nik, Нік").foregroundColor(.white.opacity(0.25)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.1), lineWidth: 1))
                    .help("Варіанти імені через кому. В авто-режимі, коли вас згадають, пролунає звук і з'явиться контекст.")
                Image(systemName: "bell.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(model.myNames.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? .white.opacity(0.25) : Theme.accent)
                    .frame(width: 34)
                    .help("Сповіщення працюють лише в авто-режимі")
            }
            HStack(spacing: 8) {
                PillButton(title: "Оригінал", symbol: model.showOriginal ? "eye" : "eye.slash",
                           active: model.showOriginal, action: model.onToggleOriginal)
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

private struct FeatureChip: View {
    let title: String
    let symbol: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } } label: {
            Label(title, systemImage: isOn ? symbol + ".fill" : symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? color : .white.opacity(0.5))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(isOn ? color.opacity(0.15) : .white.opacity(0.05)))
                .overlay(Capsule().strokeBorder(isOn ? color.opacity(0.4) : .white.opacity(0.1), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
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

// MARK: - Підказка

private struct HintCard: View {
    let entry: Entry
    let isLatest: Bool
    @State private var copied = false

    var body: some View {
        let hint = Hint.parse(entry.translation)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill").font(.system(size: 10))
                Text(entry.isStreaming && entry.translation.isEmpty ? "ДУМАЮ…" : "ПІДКАЗКА")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                Spacer()
                if !hint.en.isEmpty && !entry.isStreaming {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(hint.en, forType: .string)
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help("Скопіювати англійську фразу")
                }
            }
            .foregroundStyle(Theme.hint)

            if !hint.tip.isEmpty {
                Text(hint.tip)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !hint.en.isEmpty {
                (Text(hint.en) + (entry.isStreaming && hint.ua.isEmpty ? Text(" ▍").foregroundColor(Theme.hint) : Text("")))
                    .font(.system(size: 15, weight: .medium))
                    .lineSpacing(3)
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !hint.ua.isEmpty {
                Text(hint.ua)
                    .font(.system(size: 12.5))
                    .lineSpacing(2)
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.hint.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hint.opacity(0.28), lineWidth: 1))
        .opacity(isLatest ? 1 : 0.7)
        .animation(.easeOut(duration: 0.25), value: isLatest)
    }
}

// MARK: - Згадка імені

private struct MentionBanner: View {
    let mention: MentionAlert
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.bounce, value: mention.id)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("ВАС ЗГАДАЛИ")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(Theme.accent)
                    Text(mention.date, style: .time)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Text("«\(mention.snippet)»")
                    .font(.system(size: 11).italic())
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(2)
                Group {
                    if mention.context.isEmpty && mention.isStreaming {
                        Text("Збираю контекст…").foregroundColor(.white.opacity(0.45))
                    } else {
                        Text(mention.context.trimmingCharacters(in: .whitespacesAndNewlines))
                            + (mention.isStreaming ? Text(" ▍").foregroundColor(Theme.accent) : Text(""))
                    }
                }
                .font(.system(size: 13))
                .lineSpacing(2.5)
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(.white.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .help("Закрити")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Стрічка

private struct Feed: View {
    @EnvironmentObject var model: AppModel
    /// Стрічка «приклеєна» до низу. Знімається, коли користувач сам прокрутив угору.
    @State private var follow = true
    /// Поки користувач читає історію, з'явився новий текст.
    @State private var hasNew = false
    @State private var viewport: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Звичайний VStack: висоти відомі точно, тож прокрутка до низу не «недолітає».
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(model.entries) { entry in
                        EntryView(entry: entry,
                                  isLatest: entry.id == model.entries.last?.id,
                                  showOriginal: model.showOriginal)
                            .id(entry.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                        .background(GeometryReader { g in
                            Color.clear.preference(key: BottomOffsetKey.self,
                                                   value: g.frame(in: .named("feed")).maxY)
                        })
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .coordinateSpace(name: "feed")
            .scrollIndicators(.automatic)
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { viewport = geo.size.height }
                    .onChange(of: geo.size) { _, size in
                        viewport = size.height
                        if follow { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
            })
            .onPreferenceChange(BottomOffsetKey.self) { bottomY in
                let atBottom = bottomY <= viewport + 40
                if atBottom {
                    // Користувач сам докрутив до кінця — знову стежимо за новим текстом.
                    if !follow { follow = true; hasNew = false }
                } else if follow, model.userScrolledRecently {
                    follow = false
                }
            }
            // Новий запис — плавно вниз; потік тексту в останньому записі — миттєво, без смикання.
            .onChange(of: model.entries.count) { _, _ in
                if follow {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                } else {
                    hasNew = true
                }
            }
            .onChange(of: model.entries.last) { _, _ in
                if follow { proxy.scrollTo("bottom", anchor: .bottom) } else { hasNew = true }
            }
            .onChange(of: model.showOriginal) { _, _ in if follow { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: model.entries.isEmpty) { _, empty in if empty { follow = true; hasNew = false } }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .overlay(alignment: .bottomTrailing) {
                if !follow {
                    Button {
                        follow = true
                        hasNew = false
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down").font(.system(size: 11, weight: .semibold))
                            if hasNew {
                                Text("Нове").font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.black.opacity(0.85))
                        .padding(.horizontal, hasNew ? 12 : 0)
                        .frame(minWidth: 30, minHeight: 30)
                        .background(Capsule().fill(Theme.accent))
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                    }
                    .buttonStyle(PressStyle())
                    .help("До останнього повідомлення — знову автопрокрутка")
                    .padding(14)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: follow)
            .animation(.easeOut(duration: 0.2), value: hasNew)
        }
    }
}

private struct BottomOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct EntryView: View {
    let entry: Entry
    let isLatest: Bool
    let showOriginal: Bool

    var body: some View {
        switch entry.kind {
        case .hint:
            HintCard(entry: entry, isLatest: isLatest)
        case .caption:
            Text(entry.original)
                .font(.system(size: 15))
                .lineSpacing(3.5)
                .foregroundStyle(.white.opacity(0.94))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(isLatest ? 1 : 0.55)
        case .translation:
            translationBody
        }
    }

    private var translationBody: some View {
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
        let what = model.translateEnabled ? "Переклад" : "Текст"
        if model.mode == .auto {
            return (model.hintsEnabled ? "\(what) і підказки з'являються під час розмови"
                                       : "\(what) з'являється, щойно текст зміниться", .white.opacity(0.38))
        }
        return (model.hintsEnabled ? "⌥Space — \(model.translateEnabled ? "переклад" : "текст")  ·  ⌥⇧I — підказка"
                                   : "⌥Space — \(model.translateEnabled ? "перекласти" : "захопити")  ·  ⌥⇧P — пауза",
                .white.opacity(0.38))
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(hint.0)
                .font(.system(size: 11))
                .foregroundStyle(hint.1)
                .lineLimit(2)
                .help(hint.0)
            Spacer(minLength: 8)
            if model.hintsEnabled {
                Button(action: model.onHint) {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill").font(.system(size: 10))
                        Text("Підказка").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.hint)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(Theme.hint.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(Theme.hint.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(PressStyle())
                .help("Підказка: що сказати зараз (⌥⇧I)")
                .disabled(!model.hasRegion || model.paused)
                .opacity(model.hasRegion && !model.paused ? 1 : 0.4)
            }
            if model.mode == .manual {
                Button(action: model.onTranslate) {
                    HStack(spacing: 8) {
                        Text(model.translateEnabled
                             ? (model.status == .working ? "Перекладаю" : "Перекласти")
                             : "Захопити")
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
