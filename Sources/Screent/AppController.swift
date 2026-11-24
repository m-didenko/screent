import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

/// Склеює все разом: захоплення → OCR → дифф → Claude → панель.
@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings.shared
    private let model = AppModel()
    private let bridge = ClaudeBridge()
    private let capturer = ScreenCapturer()
    private let selector = RegionSelector()
    private let frameWindow = RegionFrameWindow()
    private var panel: TranslationPanel!
    private var statusItem: NSStatusItem!

    /// Куди дописується поточна відповідь Claude.
    private struct Target {
        let index: Int
        let appended: Bool
        /// Стан запису до надсилання — для відкату, якщо Claude відповів «…».
        let baseTranslation: String
        let baseOriginal: String
        let baseNotes: [String]
        /// Частина перекладу, що лишається незмінною (решту Claude перепише).
        let keptPrefix: String
        /// Сирий вивід Claude за цей хід.
        var raw = ""
        /// Текст, надісланий на переклад (для картки згадки).
        var source = ""
        /// Claude у цьому ході позначив звернення до користувача рядком «🔔».
        var bellShown = false
    }

    private var lastSentText = ""
    private var target: Target?
    private var busy = false
    private var capturing = false
    private var pending = false
    private var autoTimer: Timer?
    private var lastPolled = ""
    private var stableTicks = 0
    private var permissionBlockedAt: Date?
    private var paused = false

    // Згадки імені (лише авто-режим)
    private enum TurnKind { case translation, mention, hint }
    private var turnKind = TurnKind.translation
    private var lastScanned = ""
    private var recentCaptions = ""
    private var lastMentionAt: Date?
    private var mentionPending = false
    private var modelSwitchPending = false

    // AI-підказки
    private var captionsSinceHint = ""
    private var wordsSinceHint = 0
    private var lastHintAt: Date?
    private var hintPending = false
    private var hintIndex: Int?
    private static let autoHintWords = 60
    private static let autoHintInterval: TimeInterval = 45

    /// Англійський режим: без перекладу, підказки й контекст — англійською.
    private var english: Bool { !settings.translateEnabled }

    // MARK: - Запуск

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onTranslate = { [weak self] in self?.translateNow() }
        model.onSelectRegion = { [weak self] in self?.selectRegion() }
        model.onSetMode = { [weak self] in self?.applyMode($0) }
        model.onToggleOriginal = { [weak self] in self?.toggleOriginal() }
        model.onNewSession = { [weak self] in self?.menuNewSession() }
        model.onTogglePause = { [weak self] in self?.togglePause() }
        model.onRegionHighlight = { [weak self] in self?.frameWindow.setHighlight($0) }
        model.onQuit = { NSApp.terminate(nil) }
        model.onMinimize = { [weak self] in self?.minimizePanel() }
        model.onDismissMention = { [weak self] in self?.model.mention = nil }
        model.onHint = { [weak self] in self?.hintNow() }
        model.onSelectModel = { [weak self] in self?.switchModel($0) }
        frameWindow.setHighlight(settings.regionHighlight)

        panel = TranslationPanel(model: model)
        panel.orderFrontRegardless()
        setupStatusItem()
        setupHotKeys()

        bridge.onDelta = { [weak self] in self?.appendDelta($0) }
        bridge.onTurnEnd = { [weak self] in self?.turnEnded(isError: $0, message: $1) }
        bridge.onExit = { [weak self] in self?.bridgeExited($0) }

        if let r = settings.region { showFrame(r) }
        Log.write("launch \(Bundle.main.bundlePath) preflight=\(CGPreflightScreenCaptureAccess())")
        ScreenCapturer.requestPermission()

        startSession()
        applyMode(settings.mode)
        setPaused(true) // після запуску завжди на паузі — переклад починається лише за бажанням користувача
        Task.detached(priority: .utility) { await OCR.warmUp() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridge.stop()
    }

    private func setupHotKeys() {
        let hk = HotKeyCenter.shared
        hk.register(id: 1, keyCode: kVK_Space, modifiers: optionKey) { [weak self] in
            MainActor.assumeIsolated { self?.translateNow() }
        }
        hk.register(id: 2, keyCode: kVK_Space, modifiers: optionKey | shiftKey) { [weak self] in
            MainActor.assumeIsolated { self?.toggleMode() }
        }
        hk.register(id: 3, keyCode: kVK_ANSI_R, modifiers: optionKey | shiftKey) { [weak self] in
            MainActor.assumeIsolated { self?.selectRegion() }
        }
        hk.register(id: 5, keyCode: kVK_ANSI_P, modifiers: optionKey | shiftKey) { [weak self] in
            MainActor.assumeIsolated { self?.togglePause() }
        }
        hk.register(id: 6, keyCode: kVK_ANSI_I, modifiers: optionKey | shiftKey) { [weak self] in
            MainActor.assumeIsolated { self?.hintNow() }
        }
        hk.register(id: 4, keyCode: kVK_ANSI_H, modifiers: optionKey | shiftKey) { [weak self] in
            MainActor.assumeIsolated { self?.togglePanel() }
        }
    }

    // MARK: - Сесія

    private func startSession() {
        bridge.stop()
        model.entries.removeAll()
        lastSentText = ""
        lastPolled = ""
        target = nil
        busy = false
        pending = false
        turnKind = .translation
        mentionPending = false
        lastScanned = ""
        recentCaptions = ""
        model.mention = nil
        captionsSinceHint = ""
        wordsSinceHint = 0
        lastHintAt = nil
        hintPending = false
        hintIndex = nil
        do {
            try bridge.start(model: settings.model)
            restoreStatus()
        } catch {
            model.status = .error(error.localizedDescription)
        }
    }

    private func bridgeExited(_ reason: String) {
        if let t = target, model.entries.indices.contains(t.index) {
            model.entries[t.index].isStreaming = false
        }
        target = nil
        busy = false
        turnKind = .translation
        mentionPending = false
        hintPending = false
        model.mention?.isStreaming = false
        if let i = hintIndex, model.entries.indices.contains(i) { model.entries[i].isStreaming = false }
        hintIndex = nil
        model.status = .error("Claude Code stopped: \(reason)")
    }

    // MARK: - Режими

    private func applyMode(_ mode: CaptureMode) {
        settings.mode = mode
        model.mode = mode
        autoTimer?.invalidate()
        autoTimer = nil
        stableTicks = 0
        if mode == .auto {
            autoTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.autoPoll() }
            }
        }
        frameWindow.setActive(mode == .auto && !paused)
        if case .error = model.status {} else { restoreStatus() }
    }

    private func toggleMode() {
        applyMode(settings.mode == .auto ? .manual : .auto)
        model.flash(settings.mode == .auto ? "Auto mode" : "Button mode")
    }

    private func restoreStatus() {
        if busy { model.status = .working }
        else if paused { model.status = .paused }
        else { model.status = settings.mode == .auto ? .listening : .idle }
    }

    private func togglePause() {
        setPaused(!paused)
        model.flash(paused ? "Paused" : "Resumed")
    }

    private func setPaused(_ value: Bool) {
        if !value && !panel.isVisible { showPanel() } // відновлення перекладу завжди повертає панель
        paused = value
        model.paused = value
        if value { pending = false; hintPending = false }
        frameWindow.setActive(settings.mode == .auto && !value)
        frameWindow.setPaused(value)
        restoreStatus()
    }

    // MARK: - Захоплення

    private func translateNow() {
        if paused { model.flash("Paused — press ▶︎ or ⌥⇧P"); return }
        guard let region = settings.region else { selectRegion(); return }
        if busy || capturing {
            pending = true
            model.flash("Queued — will run right after the current one")
            return
        }
        Task { await runCapture(region: region, manual: true) }
    }

    /// Підказка просто зараз: свіжий знімок → підказка.
    private func hintNow() {
        guard settings.hintsEnabled else { model.flash("Turn on Hints in settings"); return }
        if paused { model.flash("Paused — press ▶︎ or ⌥⇧P"); return }
        guard let region = settings.region else { selectRegion(); return }
        if busy || capturing {
            hintPending = true
            model.flash("Hint queued — right after the current reply")
            return
        }
        Task { await runCapture(region: region, manual: true, forHint: true) }
    }

    private func autoPoll() {
        guard !paused, !capturing, !selector.isActive, let region = settings.region else { return }
        // Без дозволу не смикаємо систему щотакту — повторюємо раз на 5 с.
        if let t = permissionBlockedAt, Date().timeIntervalSince(t) < 5 { return }
        Task { await runCapture(region: region, manual: false) }
    }

    private func runCapture(region: CGRect, manual: Bool, forHint: Bool = false) async {
        capturing = true
        defer { capturing = false }
        if manual {
            frameWindow.flash()
            model.status = .working
        }
        do {
            let image = try await capturer.captureLogged(region: region)
            let text = try await OCR.recognize(image).joined(separator: "\n")
            permissionBlockedAt = nil
            if case .error = model.status { restoreStatus() }
            if forHint {
                ingest(text)
                requestHint(auto: false)
                if !busy { restoreStatus() }
            } else if manual { handleManual(text) } else { handleAuto(text) }
        } catch {
            if case CaptureError.permission = error { permissionBlockedAt = Date() }
            model.status = .error(error.localizedDescription)
        }
    }

    private func handleManual(_ text: String) {
        ingest(text)
        let diff = TextDiffer.diff(previous: lastSentText, current: text)
        guard !diff.isEmpty else {
            restoreStatus()
            model.flash(text.isEmpty ? "No text found in the region" : "No new text")
            return
        }
        send(diff, fullText: text)
    }

    /// Авто: надсилаємо, коли текст «устоявся» (не змінювався один такт) або накопичилося багато нових слів.
    private func handleAuto(_ text: String) {
        ingest(text)
        let norm = TextDiffer.normalized(text)
        if norm == lastPolled { stableTicks += 1 } else { stableTicks = 0; lastPolled = norm }
        guard !busy, !paused, settings.mode == .auto else { return }

        // Авто-підказка: назбиралося достатньо нового тексту, розмова «видихнула» і минуло досить часу.
        if settings.hintsEnabled, stableTicks >= 1, wordsSinceHint >= Self.autoHintWords,
           lastHintAt.map({ Date().timeIntervalSince($0) >= Self.autoHintInterval }) ?? true {
            requestHint(auto: true)
            return
        }

        let diff = TextDiffer.diff(previous: lastSentText, current: text)
        guard !diff.isEmpty, stableTicks >= 1 || diff.wordCount >= 24 else { return }
        frameWindow.flash()
        send(diff, fullText: text)
    }

    // MARK: - Згадка імені

    /// Кожен знімок: накопичуємо нові рядки субтитрів (для згадок і підказок) і шукаємо ім'я.
    private func ingest(_ text: String) {
        let diff = TextDiffer.diff(previous: lastScanned, current: text)
        lastScanned = text
        guard !diff.isEmpty else { return }
        recentCaptions = String((recentCaptions + "\n" + diff.text).suffix(1500))
        captionsSinceHint = String((captionsSinceHint + "\n" + diff.text).suffix(3000))
        wordsSinceHint += diff.wordCount
        checkMention(diff.text)
    }

    /// Лише авто-режим: шукаємо ім'я користувача в нових рядках.
    private func checkMention(_ newText: String) {
        let names = MentionDetector.parse(settings.myNames)
        guard settings.mode == .auto, !paused,
              let line = MentionDetector.findMention(in: newText, names: names) else { return }
        guard canAlert() else { return }
        showMentionAlert(snippet: line, context: "", source: "local")
        if busy { mentionPending = true } else { sendMention() }
    }

    private func canAlert() -> Bool {
        if settings.alertsMuted { return false }
        if let last = lastMentionAt, Date().timeIntervalSince(last) < 20 { return false }
        return true
    }

    private func showMentionAlert(snippet: String, context: String, source: String) {
        lastMentionAt = Date()
        NSSound(named: "Glass")?.play()
        frameWindow.flash()
        showPanel()
        model.mention = MentionAlert(snippet: snippet, context: context, isStreaming: true)
        Log.write("mention detected (\(source))")
    }

    private func sendMention() {
        mentionPending = false
        if !bridge.isRunning {
            do { try bridge.start(model: settings.model) } catch {
                model.mention?.isStreaming = false
                return
            }
        }
        let message = """
        MENTION:\(english ? " (LANGUAGE: English)" : "")
        The user's name (\(settings.myNames)) was just said in the meeting, in this line:
        «\(model.mention?.snippet ?? "")»

        Recent captions, oldest first:
        \(recentCaptions.trimmingCharacters(in: .whitespacesAndNewlines))
        """
        do {
            try bridge.send(envelope(message))
            turnKind = .mention
            busy = true
            model.status = .working
        } catch {
            model.mention?.isStreaming = false
        }
    }

    // MARK: - Переклад

    private func send(_ diff: TextDiff, fullText: String) {
        if !bridge.isRunning {
            do { try bridge.start(model: settings.model) } catch {
                model.status = .error(error.localizedDescription)
                return
            }
        }

        if english {
            addCaption(diff)
            lastSentText = fullText
            restoreStatus()
            return
        }

        let message: String
        if diff.continues, let i = model.entries.indices.last, model.entries[i].kind == .translation,
           !model.entries[i].isStreaming {
            // Незавершене речення наприкінці перекладу Claude перекладе заново цілком.
            let old = model.entries[i].translation
            let kept = Self.unfinishedSentenceStart(in: old)
            let tail = String(old.dropFirst(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = String(old.prefix(kept)) + (kept > 0 ? " " : "")
            target = Target(index: i, appended: true, baseTranslation: old,
                            baseOriginal: model.entries[i].original,
                            baseNotes: model.entries[i].notes, keptPrefix: prefix)
            model.entries[i].original += " " + diff.text
            model.entries[i].translation = prefix
            model.entries[i].isStreaming = true
            message = userHeader() + "NEW (continues previous):\n" + diff.text
                + (tail.isEmpty ? "" : "\n\nUnfinished end of your previous translation (will be replaced):\n«\(tail)»")
        } else {
            model.entries.append(Entry(original: diff.text, translation: "", isStreaming: true))
            target = Target(index: model.entries.count - 1, appended: false,
                            baseTranslation: "", baseOriginal: "", baseNotes: [], keptPrefix: "")
            message = userHeader() + "NEW:\n" + diff.text
        }
        target?.source = diff.text

        do {
            try bridge.send(envelope(message))
            lastSentText = fullText
            busy = true
            model.status = .working
        } catch {
            turnEnded(isError: true, message: error.localizedDescription)
        }
    }

    /// Англійський режим: розпізнаний текст іде в стрічку як є, без Claude.
    private func addCaption(_ diff: TextDiff) {
        if diff.continues, let i = model.entries.indices.last, model.entries[i].kind == .caption {
            model.entries[i].original += " " + diff.text
        } else {
            model.entries.append(Entry(original: diff.text, translation: "", isStreaming: false, kind: .caption))
        }
    }

    // MARK: - Підказки

    private func requestHint(auto: Bool) {
        guard settings.hintsEnabled else { return }
        if busy { hintPending = true; return }
        hintPending = false
        let captions = captionsSinceHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if auto && captions.isEmpty { return }
        if !bridge.isRunning {
            do { try bridge.start(model: settings.model) } catch {
                model.status = .error(error.localizedDescription)
                return
            }
        }
        let message = """
        HINT (\(auto ? "automatic" : "requested by the user")\(english ? ", LANGUAGE: English" : "")):
        New captions since the last hint:
        \(captions.isEmpty ? "(none — use the conversation so far)" : captions)
        """
        model.entries.append(Entry(original: "", translation: "", isStreaming: true, kind: .hint))
        hintIndex = model.entries.count - 1
        captionsSinceHint = ""
        wordsSinceHint = 0
        lastHintAt = Date()
        do {
            try bridge.send(envelope(message))
            turnKind = .hint
            busy = true
            model.status = .working
        } catch {
            model.entries.removeLast()
            hintIndex = nil
            model.status = .error(error.localizedDescription)
        }
    }

    /// Після кожної відповіді: спершу згадка, потім підказка, потім відкладений переклад.
    private func drainQueue() {
        if modelSwitchPending { applyModelSwitch() }
        if mentionPending { sendMention() }
        else if hintPending { requestHint(auto: false) }
        else if pending { pending = false; translateNow() }
    }

    /// Кожне повідомлення несе мову перекладу: її можна змінити посеред сесії без втрати контексту.
    private func envelope(_ body: String) -> String {
        "TARGET: \(settings.targetLanguage.promptName)\n" + body
    }

    /// В авто-режимі повідомляємо Claude ім'я користувача, щоб він теж помічав звернення.
    private func userHeader() -> String {
        let names = settings.myNames.trimmingCharacters(in: .whitespaces)
        guard settings.mode == .auto, !settings.alertsMuted, !names.isEmpty else { return "" }
        return "USER NAME: \(names)\n"
    }

    /// Позиція, з якої починається останнє незавершене речення (після останнього . ! ? або переносу рядка).
    static func unfinishedSentenceStart(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let last = trimmed.last, ".!?".contains(last) { return text.count }
        var cut = 0
        for (i, ch) in text.enumerated() where ".!?\n".contains(ch) { cut = i + 1 }
        return cut
    }

    private func appendDelta(_ text: String) {
        if turnKind == .mention {
            model.mention?.context += text
            return
        }
        if turnKind == .hint {
            if let i = hintIndex, model.entries.indices.contains(i) { model.entries[i].translation += text }
            return
        }
        guard var t = target, model.entries.indices.contains(t.index) else { return }
        t.raw += text
        target = t
        let (body, notes, bell) = Self.split(t.raw)
        model.entries[t.index].translation = t.keptPrefix + body
        model.entries[t.index].notes = t.baseNotes + notes.filter { !t.baseNotes.contains($0) }

        // Резерв: Claude розпізнав звернення, яке пропустив локальний пошук імені.
        if let bell, !bell.isEmpty {
            if t.bellShown {
                model.mention?.context = bell
            } else if canAlert() {
                t.bellShown = true
                target = t
                let snippet = t.source.split(whereSeparator: \.isNewline).last.map(String.init) ?? t.source
                showMentionAlert(snippet: String(snippet.suffix(160)), context: bell, source: "claude")
            }
        }
    }

    /// Розділяє вивід Claude на переклад, рядки-пояснення «ⓘ» і рядок звернення «🔔».
    static func split(_ raw: String) -> (body: String, notes: [String], bell: String?) {
        var body: [String] = []
        var notes: [String] = []
        var bell: String?
        for line in raw.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("🔔") {
                bell = t.dropFirst().trimmingCharacters(in: .whitespaces)
            } else if t.hasPrefix("ⓘ") {
                let note = t.dropFirst().trimmingCharacters(in: .whitespaces)
                if !note.isEmpty { notes.append(note) }
            } else {
                body.append(line)
            }
        }
        var text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "…" || text == "..." { text = "" }
        return (text, notes, bell)
    }

    private func turnEnded(isError: Bool, message: String?) {
        busy = false
        if turnKind == .mention {
            turnKind = .translation
            model.mention?.isStreaming = false
            if isError { model.mention?.context = message ?? "Claude Code error" }
            restoreStatus()
            drainQueue()
            return
        }
        if turnKind == .hint {
            turnKind = .translation
            if let i = hintIndex, model.entries.indices.contains(i) {
                model.entries[i].isStreaming = false
                let hint = Hint.parse(model.entries[i].translation)
                if isError {
                    model.entries[i].translation = "TIP: " + (message ?? "Claude Code error")
                } else if hint.isEmpty {
                    model.entries.remove(at: i) // Claude вирішив, що додати нічого
                }
            }
            hintIndex = nil
            restoreStatus()
            drainQueue()
            return
        }
        if let t = target, model.entries.indices.contains(t.index) {
            model.entries[t.index].isStreaming = false
            if t.bellShown { model.mention?.isStreaming = false }
            let (body, notes, _) = Self.split(t.raw)
            if body.isEmpty && notes.isEmpty {
                if t.appended {
                    model.entries[t.index].translation = t.baseTranslation
                    model.entries[t.index].original = t.baseOriginal
                    model.entries[t.index].notes = t.baseNotes
                } else {
                    model.entries.remove(at: t.index)
                }
            }
        }
        target = nil

        if isError {
            model.status = .error(message ?? "Claude Code error")
        } else {
            restoreStatus()
        }

        drainQueue()
    }

    // MARK: - Область і панель

    private func selectRegion() {
        guard !selector.isActive else { return }
        frameWindow.orderOut(nil)
        selector.begin { [weak self] rect in
            guard let self else { return }
            if let rect {
                self.settings.region = rect
                self.model.hasRegion = true
                self.lastSentText = ""
                self.lastPolled = ""
                self.model.flash("Region saved")
            }
            if let r = self.settings.region { self.showFrame(r) }
            if !self.panel.isVisible { self.showPanel() }
        }
    }

    private func showFrame(_ region: CGRect) {
        if settings.showFrame { frameWindow.show(region: region) } else { frameWindow.orderOut(nil) }
    }

    private func toggleOriginal() {
        settings.showOriginal.toggle()
        model.showOriginal = settings.showOriginal
    }

    private func togglePanel() {
        if panel.isVisible { minimizePanel() } else { showPanel() }
    }

    /// Згорнути в рядок меню — лише на паузі: під час живого перекладу панель має бути на екрані.
    private func minimizePanel() {
        guard paused else {
            model.flash("Pause first (⌥⇧P), then minimize")
            NSSound.beep()
            return
        }
        panel.orderOut(nil)
        frameWindow.orderOut(nil)
        updateStatusIcon()
        Log.write("panel minimized")
    }

    private func showPanel() {
        panel.orderFrontRegardless()
        if let r = settings.region { showFrame(r) }
        updateStatusIcon()
    }

    // MARK: - Меню в рядку меню

    private var statusMenu: NSMenu!

    /// Значок у рядку меню (біля годинника). Клік, коли панель згорнута, — розгорнути її;
    /// інакше (або правий клік / ⌥-клік) — меню.
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "ScreentStatusItem"
        statusMenu = NSMenu()
        statusMenu.autoenablesItems = false
        statusMenu.delegate = self
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusIcon()
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true
        if !panel.isVisible && !wantsMenu {
            showPanel()
            return
        }
        // Показати меню під значком.
        statusItem.menu = statusMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// Згорнута панель — заповнений значок: видно, що Screent працює у фоні.
    private func updateStatusIcon() {
        let minimized = panel.map { !$0.isVisible } ?? false
        let name = minimized ? "character.bubble.fill" : "character.bubble"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Screent")
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = minimized ? "Screent is minimized — click to show the panel"
                                                : "Screent — click for the menu"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(item("Translate Now", #selector(menuTranslate), key: " ", mods: [.option]))
        menu.addItem(item(paused ? "Resume" : "Pause", #selector(menuTogglePause), key: "p", mods: [.option, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Mode: Button", #selector(menuManual), checked: settings.mode == .manual))
        menu.addItem(item("Mode: Auto", #selector(menuAuto), key: " ", mods: [.option, .shift],
                          checked: settings.mode == .auto))
        menu.addItem(.separator())
        menu.addItem(item("Select Region…", #selector(menuSelectRegion), key: "r", mods: [.option, .shift]))
        menu.addItem(item("Show Region Frame", #selector(menuToggleFrame), checked: settings.showFrame))
        menu.addItem(item("Show Original", #selector(menuToggleOriginal), checked: settings.showOriginal))
        let panelItem = item(panel.isVisible ? (paused ? "Minimize to Menu Bar" : "Minimize (pause first)") : "Show Panel",
                             #selector(menuTogglePanel), key: "h", mods: [.option, .shift])
        panelItem.isEnabled = !(panel.isVisible && !paused)
        menu.addItem(panelItem)
        menu.addItem(.separator())

        let modelMenu = NSMenu()
        for (alias, title) in [("sonnet", "Sonnet — balanced"), ("haiku", "Haiku — fastest"), ("opus", "Opus — most accurate")] {
            let mi = item(title, #selector(menuModel(_:)), checked: settings.model == alias)
            mi.representedObject = alias
            modelMenu.addItem(mi)
        }
        let modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)
        menu.addItem(item("New Session", #selector(menuNewSession)))
        menu.addItem(item("Export Transcript…", #selector(menuExport)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Screent", #selector(menuQuit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "",
                      mods: NSEvent.ModifierFlags = [.command], checked: Bool = false) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.keyEquivalentModifierMask = mods
        mi.target = self
        mi.state = checked ? .on : .off
        return mi
    }

    @objc private func menuTranslate() { translateNow() }
    @objc private func menuTogglePause() { togglePause() }
    @objc private func menuManual() { applyMode(.manual) }
    @objc private func menuAuto() { applyMode(.auto) }
    @objc private func menuSelectRegion() { selectRegion() }
    @objc private func menuToggleOriginal() { toggleOriginal() }
    @objc private func menuTogglePanel() { togglePanel() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    @objc private func menuToggleFrame() {
        settings.showFrame.toggle()
        if let r = settings.region { showFrame(r) }
    }

    @objc private func menuModel(_ sender: NSMenuItem) {
        guard let alias = sender.representedObject as? String else { return }
        switchModel(alias)
    }

    /// Змінює модель одразу, продовжуючи ту саму сесію Claude Code (--resume): контекст мітингу зберігається.
    private func switchModel(_ alias: String) {
        guard alias != settings.model else { return }
        settings.model = alias
        model.selectedModel = alias
        if busy { modelSwitchPending = true; return }
        applyModelSwitch()
    }

    private func applyModelSwitch() {
        modelSwitchPending = false
        let name = settings.model.prefix(1).uppercased() + settings.model.dropFirst()
        do {
            try bridge.start(model: settings.model, resume: model.entries.isEmpty ? nil : bridge.sessionID)
            restoreStatus()
            model.flash("Model: \(name) — context kept")
        } catch {
            model.status = .error(error.localizedDescription)
        }
    }

    @objc private func menuNewSession() {
        startSession()
        model.flash("New session — context cleared")
    }

    @objc private func menuExport() {
        guard !model.entries.isEmpty else { model.flash("The transcript is empty"); return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        let save = NSSavePanel()
        save.nameFieldStringValue = "Screent \(formatter.string(from: Date())).md"
        save.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        NSApp.activate(ignoringOtherApps: true)
        guard save.runModal() == .OK, let url = save.url else { return }

        let time = DateFormatter()
        time.dateFormat = "HH:mm:ss"
        var md = "# Screent — transcript\n\n"
        for e in model.entries {
            md += "**\(time.string(from: e.date))**\n\n"
            if e.kind == .hint {
                let h = Hint.parse(e.translation)
                md += "💡 \(h.tip)\n\n"
                if !h.en.isEmpty { md += "> **EN:** \(h.en)\n" }
                if !h.ua.isEmpty { md += "> **\(settings.targetLanguage.code):** \(h.ua)\n" }
                md += "\n---\n\n"
                continue
            }
            md += e.original.split(separator: "\n").map { "> \($0)" }.joined(separator: "\n") + "\n\n"
            md += e.translation.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
            for n in e.notes { md += "- ⓘ \(n)\n" }
            md += (e.notes.isEmpty ? "" : "\n") + "---\n\n"
        }
        do {
            try md.write(to: url, atomically: true, encoding: .utf8)
            model.flash("Saved: \(url.lastPathComponent)")
        } catch {
            model.status = .error(error.localizedDescription)
        }
    }
}
