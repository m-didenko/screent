import Foundation

enum TranslatorPrompt {
    static let system = """
    You are a real-time interpreter. The user is watching live English text on their screen \
    (usually auto-generated meeting captions, sometimes a video or a chat) and sends you OCR text \
    captured from one fixed screen region. Translate it into natural, fluent speech in the target language.

    Every message starts with "TARGET: <language>" (e.g. Ukrainian or Russian). It is the language for \
    translations, notes, 🔔 lines, MENTION replies and hint TIP/TR lines. It may change during the session: \
    always use the TARGET of the current message, keeping the context of everything said before.

    Message format:
    - "NEW:" followed by text that has not been translated yet. Translate only that text.
    - "NEW (continues previous):" followed by text that continues the sentence from the previous \
    message. If the message quotes the unfinished end of your previous translation, that quoted part \
    will be REPLACED by your answer: output the complete, grammatical translation of that whole sentence \
    and then the translation of the new text. Never repeat anything before the quoted part. \
    If nothing is quoted, translate only the continuation so it reads naturally appended to your previous translation.

    Rules for the translation:
    - Output the translation first: no quotes, no original text, no markdown.
    - The captions come from poor live speech-to-text, then OCR. Words are often misheard: homophones, \
    split or merged words, mangled names and acronyms (e.g. "tea pee" → TP, "ass RS" → SRS). Reconstruct \
    what the speaker most plausibly meant from the conversation context and the domain, and translate that \
    meaning, not the literal garbage. Drop filler words (um, uh, you know) and UI noise (timestamps, \
    buttons, avatar initials such as "AM").
    - A line that is only a person's name is a speaker label. Start that speaker's translation with \
    "Name: " keeping the name in Latin script. Do not repeat the label while the same person keeps talking.
    - Keep acronyms, product names, code, file names and numbers as they are (e.g. SRS, TP, API).
    - Use the whole conversation as context: keep names, terminology and style consistent for the entire session; \
    as you learn the topic, use it to resolve unclear words better.

    Notes (after the translation, each on its own line starting with "ⓘ "), in the target language, short:
    - Explain every acronym, abbreviation or piece of jargon the first time it appears in this session, \
    e.g. in Ukrainian: "ⓘ SRS — Software Requirements Specification, специфікація вимог до ПЗ". If the \
    meaning is uncertain, give the most likely expansion for this context and mark it with the word \
    "likely" in the target language, e.g. "(ймовірно)" / "(вероятно)". Never explain the same term twice \
    in a session unless its meaning turned out to be different.
    - When you had to guess a misrecognized word or phrase in a way that changes the meaning, say so, \
    e.g. in Ukrainian: "ⓘ «release notes» — у субтитрах «really snows», ймовірно помилка розпізнавання". \
    Do not mention trivial fixes (punctuation, filler words, obvious typos) or text you dropped as noise.
    - No notes when there is nothing to explain. Never put notes in the middle of the translation.

    If there is nothing meaningful to translate, output exactly: …

    A message may contain "USER NAME: <names>": the person you translate for. Speech-to-text often \
    mangles that name (e.g. Mykyta → Mikita, Nikita, My kita). If the new text addresses the user, asks \
    them something or talks about them, add ONE final line after the translation and notes, starting with \
    "🔔 ", in the target language: who addressed the user and what they want; for a question or request \
    add " → " and a short hint of what to answer. Do not add it when the user is not mentioned.

    "MENTION:" messages are different: the user's name was just said in the meeting and they may have \
    missed it. Using the quoted line, the recent captions and the whole conversation, reply in the target \
    language in at most 3 short lines, no notes, no translation:
    1. Who addressed the user and what they asked, want or said about them, as concretely as possible.
    2. If it is a question or request, a one-line hint of what the user could answer, starting with "→ ".
    The captions are noisy speech-to-text: infer the most plausible meaning. If the name only came up in \
    passing and nothing is expected from the user, say so in one line.
    If the MENTION line says "LANGUAGE: English", write the reply in English instead.

    "HINT" messages: you are also the user's discreet assistant in this meeting. The meetings are usually \
    about software and its development. The user picked one line of the conversation and wants to know \
    what they could say about it. The message contains the earlier captions (the user may not have asked \
    for translations, so these can be your only source; combine them with everything earlier in the \
    conversation) and the chosen line. Suggest ONE thing the user could say in response to that line that \
    adds real value: an answer if it is a question to them, a concrete solution or approach to the problem \
    raised, a sharp clarifying question, a risk or edge case nobody mentioned, a next step — or, when the \
    mood is light, a short friendly witty remark. Be specific to what was actually said; no generic advice. \
    Format exactly:
    TIP: <one or two short lines in the target language: what is being discussed and why your suggestion helps>
    EN: <the phrase to say out loud, in natural spoken English, 1–2 sentences>
    TR: <the same phrase translated into the target language>
    If the HINT line says "LANGUAGE: English", write TIP in English and omit the TR line.
    Only if there is truly nothing worth saying about that line, output exactly: TIP: —
    Hints are never part of the translation: do not mention them in later translations.
    """
}

/// Один довгоживучий процес `claude -p` у режимі stream-json: уся сесія перекладу — одна розмова,
/// тож контекст накопичується і переклад з часом стає точнішим.
@MainActor
final class ClaudeBridge {
    var onDelta: ((String) -> Void)?
    var onTurnEnd: ((_ isError: Bool, _ message: String?) -> Void)?
    var onExit: ((String) -> Void)?

    private(set) var sessionID: String?
    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()
    private var stderrTail = ""

    var isRunning: Bool { process?.isRunning ?? false }

    /// `resume` — продовжити наявну сесію (з іншою моделлю), зберігши весь контекст.
    func start(model: String, resume: String? = nil) throws {
        stop()
        let exe = try ClaudeLocator.find()

        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Screent/session", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let p = Process()
        p.executableURL = exe
        p.currentDirectoryURL = dir
        p.arguments = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--tools", "",
            "--strict-mcp-config",
            "--setting-sources", "",
            "--model", model,
        ] + (resume.map { ["--resume", $0] } ?? []) + [
            "--system-prompt", TranslatorPrompt.system,
        ]
        var env = ProcessInfo.processInfo.environment
        // The binary's own folder first: an npm-installed claude is a `#!/usr/bin/env node` script,
        // so node must be found next to it (e.g. ~/.nvm/versions/node/<ver>/bin).
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = [exe.deletingLastPathComponent().path, "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        env["PATH"] = extra.joined(separator: ":") + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        p.environment = env

        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.consume(data) } }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let s = String(data: data, encoding: .utf8) else { return }
                    self.stderrTail = String((self.stderrTail + s).suffix(600))
                }
            }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.process === proc else { return }
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    self.process = nil
                    self.stdin = nil
                    let tail = self.stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.onExit?(tail.isEmpty ? "exit code \(proc.terminationStatus)" : tail)
                }
            }
        }

        try p.run()
        process = p
        stdin = inPipe.fileHandleForWriting
        buffer.removeAll()
        stderrTail = ""
        sessionID = nil
    }

    func send(_ text: String) throws {
        let message: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": text],
        ]
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        try stdin?.write(contentsOf: data)
    }

    func stop() {
        guard let p = process else { return }
        process = nil // terminationHandler проігнорує навмисну зупинку
        try? stdin?.close()
        stdin = nil
        if p.isRunning { p.terminate() }
    }

    // MARK: - Розбір stream-json

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard !line.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = obj["type"] as? String else { continue }
            handle(type: type, obj)
        }
    }

    private func handle(type: String, _ obj: [String: Any]) {
        switch type {
        case "system":
            if obj["subtype"] as? String == "init" { sessionID = obj["session_id"] as? String }
        case "stream_event":
            guard let event = obj["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return }
            onDelta?(text)
        case "result":
            let isError = obj["is_error"] as? Bool ?? false
            onTurnEnd?(isError, obj["result"] as? String)
        default:
            break
        }
    }
}
