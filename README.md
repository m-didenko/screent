# Screent

Live on-screen translation for macOS. Pick a region of your screen with English text, such as meeting captions, a video or a chat. Screent reads it and shows a running Ukrainian or Russian translation in a small floating panel.

```
region of the screen → ScreenCaptureKit → Apple Vision OCR (local) → only the new text
        → Claude Code (one long session) → floating panel
```

- **Two modes:**
  - **Button:** press ⌥Space to translate what's in the region.
  - **Auto:** translates whenever the text changes.
- **Context-aware.** The whole session is a single Claude Code conversation, so names, terminology and style stay consistent, and translation quality improves as the meeting goes on.
- **Handles bad speech-to-text.** Claude reconstructs what the speaker most likely meant instead of translating misheard words literally.
- **AI hints.** In meetings about software, Claude suggests one thing you could say right now: a concrete solution, a sharp question, a risk nobody mentioned, or a light witty remark. You get the phrase in English plus its Ukrainian translation.
- **English mode.** Turn translation off to see the recognized English text as is, with hints in English only.
- **Name alerts (auto mode).** When someone says your name in the meeting, Screent plays a sound. It also shows a short summary: who addressed you, what they asked, and a hint on what to answer.
- **Explains jargon.** Acronyms and terms get a short note (ⓘ) the first time they appear. So do guesses about misrecognized words.
- **Sends only new text.** Captions scroll, so each new frame mostly repeats the previous one. Screent diffs frames and sends only the new words. A sentence that was cut off is re-translated as a whole.
- **Minimal UI.** It lives in the menu bar and shows a translucent panel that stays on top. A faint highlight marks the captured region. Screent's own windows are never captured, so the panel can even sit on top of the region.

## Requirements

- macOS 14 or later, Apple Silicon or Intel
- Xcode 16+ or the Swift 6 command line tools (`xcode-select --install`)
- [Claude Code](https://docs.claude.com/en/docs/claude-code) installed and logged in. The `claude` command must work in your terminal.

Translation runs through your own Claude Code login. Each translation is a normal Claude Code request.

## Install

```bash
git clone git@github.com:m-didenko/screent.git
cd screent
```

1. **Create a local signing certificate (once).** macOS remembers the Screen Recording permission per code signature. Without a stable signature you'd have to grant it again after every rebuild. The script creates a self-signed certificate named "Screent Local Signing" in your login keychain:

   ```bash
   ./scripts/setup-signing.sh
   ```

   The first time you build, macOS may ask whether `codesign` can use the key. Choose **Always Allow**.

2. **Build, install to `/Applications` and launch:**

   ```bash
   ./scripts/build-app.sh --install --run
   ```

   A speech-bubble icon appears in the menu bar, and the translation panel opens in the bottom-right corner.

## Grant Screen Recording access

Screent needs the **Screen Recording** permission to read the region.

1. On first launch macOS shows a prompt. Click **Open System Settings**, not *Deny*.
2. In **System Settings → Privacy & Security → Screen & System Audio Recording**, turn on **Screent**. If it isn't in the list, click **+** and choose `/Applications/Screent.app`.
3. Allow macOS to **Quit & Reopen** Screent, or restart it yourself:

   ```bash
   pkill -x Screent; open /Applications/Screent.app
   ```

### Troubleshooting

The app writes a diagnostic log to `~/Library/Logs/Screent.log`.

```bash
tail -f ~/Library/Logs/Screent.log
```

- **`capture ok`:** access works.
- **`The user declined TCCs…`:** macOS has a stored *deny* record. This happens if you pressed *Deny* once, and the toggle in Settings won't override it. Reset the record, relaunch and grant access again:

  ```bash
  tccutil reset ScreenCapture com.screent.app
  pkill -x Screent; open /Applications/Screent.app
  ```

- **The permission resets after every rebuild:** you're building with an ad-hoc signature. Run `./scripts/setup-signing.sh`, rebuild, and grant access one more time.
- **`claude CLI not found`:** Screent looks for `claude` in `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin`, `/usr/local/bin`, then falls back to your login shell's `PATH`.

## Usage

1. **Select a region.** Use the ⌖ button in the panel or **⌥⇧R**, then drag over the text, e.g. the captions area of your meeting app. Press Esc to cancel.
2. **Resume.** Screent always starts paused: press ▶︎ in the header or **⌥⇧P** when you're ready.
3. **Pick a mode** with the toggle in the panel header:
   - **Button:** press **⌥Space**, or the *Translate* button.
   - **Auto:** the region is checked every 0.8 s. Text is sent once it has stopped changing, or after about 24 new words.
4. **Read the translation** in the panel. The latest line is bright and older ones fade. Speaker names are highlighted, and notes on terms appear underneath. The feed follows the newest text. Scroll up to read history and autoscroll pauses. A ↓ button appears, marked **New** when something new arrives. Click it, or scroll back to the bottom, to follow again.

| Shortcut | Action |
|---|---|
| ⌥Space | Translate now |
| ⌥⇧Space | Switch mode: button ↔ auto |
| ⌥⇧P | Pause / resume |
| ⌥⇧I | AI hint now |
| ⌥⇧R | Select region |
| ⌥⇧H | Show / hide panel |

**Status indicator** in the panel header:

| Color | Meaning |
|---|---|
| 🟢 green | Running and ready (pulses in auto mode) |
| 🟠 amber | Waiting for Claude |
| ⚪ grey | Paused |
| 🔴 red | Error. The message is shown at the bottom of the panel. |

**Panel header:** status (LIVE / THINKING / PAUSED / ERROR), pause, Button/Auto toggle, 🔔 mute/unmute name alerts, select region, ↺ new session, settings (sliders icon) and quit (power icon).

**Settings section** (opens under the header):
- **Text size:** size of the feed, hint and mention text, 0–100%. The default is 50%, which is the base size; 0% is 0.7× and 100% is 1.6×.
- **Panel background:** opacity of the background, 10–100%, default 100%. At 100% the background is almost solid dark, so text is readable over anything. Lower values reveal more of the glass behind it, and the text gets a soft shadow.
- **Region highlight:** brightness of the grey fill and corner marks over the captured region, 0–100%. The default is 50%; higher values make the highlight up to twice as strong. It never affects OCR.
- **Model:** Sonnet (default), Haiku or Opus. Switches immediately; the session is resumed with the new model, so context is kept.
- **Translate to:** Ukrainian or Russian. You can switch mid-session without losing context: each request to Claude carries the target language.
- **Features:** **Translation** and **Hints** toggle independently. See [Translation, English mode and AI hints](#translation-english-mode-and-ai-hints).
- **My name:** your name and its variants, comma-separated, e.g. `Nick, Nik, Нік`. It's used for name alerts.
- **Original**, **Quit**.

**Menu bar menu:**

| Item | What it does |
|---|---|
| Model | Sonnet (balanced, default), Haiku (fastest) or Opus (most accurate). Also in panel settings. Switches immediately and keeps the meeting context (the same Claude Code session is resumed). |
| New session | Clears the feed and Claude's context |
| Export transcript… | Saves a Markdown file with the original, the translation and the notes |
| Show region frame | Shows or hides the highlight around the captured region |
| Show original | Shows or hides the English text above each translation |

> The interface is in English, since you're in an English-speaking meeting anyway. Translation, notes, hints and mention cards use the language chosen under **Translate to** (Ukrainian or Russian).

## Translation, English mode and AI hints

Under **Features** in settings, switch **Translation** and **Hints** on or off in any combination:

| Translation | Hints | What you get |
|---|---|---|
| on | off | Ukrainian translation of the captions, with notes on jargon (default) |
| on | on | Translation, plus hint cards: the tip in Ukrainian, then the phrase in English **and** in Ukrainian |
| off | on | **English mode.** The recognized English text, plus hint cards fully in English. Mention cards are in English too. |
| off | off | English mode, captions only |

**Hints:**
- **Automatic (auto mode):** a hint is requested after roughly 60 new words of conversation, at most every 45 s, once the speaker pauses.
- **On demand:** the 💡 **Hint** button in the panel, or **⌥⇧I**.
- **Hint card:**
  - **TIP:** what is being discussed and why the suggestion helps;
  - **EN:** a ready-to-say phrase. Copy it with the copy button;
  - **UA:** its translation (translation on only).
- **Nothing to add:** if there is nothing worth saying (small talk, too little context), Claude skips the hint and no card appears.
- **Context:** hints use the same Claude session, so they know the whole meeting so far. In English mode no translation requests are made, and the hint request carries the captions since the previous hint.

## Name alerts

Name alerts work in **auto mode** only, because the region has to be watched continuously.

1. Open settings (sliders icon) and fill in **My name** with your name and the ways speech-to-text tends to spell it, e.g. `Nick, Nik, Нік`. Matching is phonetic: `Mykyta` also catches `Mikita`, `Mykita` and `Микита`, and `Nick` catches `Nic`, `Nik`, `Нік` and `Nick's`. As a backup, Claude knows your name in auto mode. If it sees you were addressed under a spelling the local matcher missed (e.g. `Nikita`), it raises the alert itself.
2. When your name appears in the captions, Screent:
   - plays a sound and flashes the region frame;
   - brings the panel to the front and shows a **"YOU WERE MENTIONED"** card with the line that mentioned you;
   - asks Claude, in the same session and so with the full meeting context, who addressed you, what they want, and what you could answer (`→ …`).
3. To silence alerts quickly, for example while you're presenting, click the 🔔 bell in the panel header. It turns into a crossed-out bell, and clicking it again turns alerts back on. The setting is remembered.
4. Close the card with ×. After an alert, Screent waits 20 s before alerting again, so it doesn't ring on every caption line.

## How it works

| File | Role |
|---|---|
| `ScreenCapturer.swift` | Captures the region with ScreenCaptureKit at 2× scale, excluding Screent's own windows |
| `OCR.swift` | Apple Vision text recognition, grouped into lines top to bottom |
| `TextDiffer.swift` | Finds where the previous frame's text overlaps the new one, tolerating OCR noise, and returns only the new words. It also tells whether they continue an unfinished sentence. |
| `ClaudeBridge.swift` | One long-running `claude -p --input-format stream-json --output-format stream-json` process with no tools, no MCP servers and no user settings. Responses stream into the panel token by token. |
| `AppController.swift` | Connects everything: modes, pause, queueing, sentence continuation, explanatory notes |
| `PanelView.swift` | The SwiftUI panel |

Claude Code runs in an empty working directory (`~/Library/Application Support/Screent/session`), so no project `CLAUDE.md` or tools leak into the translator.

## Development

```bash
swift build                    # debug build
swift test                     # TextDiffer unit tests
SCREENT_SAMPLE=/path/to/screenshot.png swift test   # also run OCR on an image
./scripts/build-app.sh --install --run              # rebuild the app
```
