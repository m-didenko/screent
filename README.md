# Screent

Live on-screen translation for macOS. Pick a region of your screen with English text, such as meeting captions, a video or a chat. Screent reads it and shows a running Ukrainian translation in a small floating panel.

```
region of the screen → ScreenCaptureKit → Apple Vision OCR (local) → only the new text
        → Claude Code (one long session) → floating panel
```

- **Two modes:**
  - **Button:** press ⌥Space to translate what's in the region.
  - **Auto:** translates whenever the text changes.
- **Context-aware.** The whole session is a single Claude Code conversation, so names, terminology and style stay consistent, and translation quality improves as the meeting goes on.
- **Handles bad speech-to-text.** Claude reconstructs what the speaker most likely meant instead of translating misheard words literally.
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
2. **Pick a mode** with the toggle in the panel header:
   - **Button:** press **⌥Space**, or the *Translate* button.
   - **Auto:** the region is checked every 0.8 s. Text is sent once it has stopped changing, or after about 24 new words.
3. **Read the translation** in the panel. The latest line is bright and older ones fade. Speaker names are highlighted, and notes on terms appear underneath.

| Shortcut | Action |
|---|---|
| ⌥Space | Translate now |
| ⌥⇧Space | Switch mode: button ↔ auto |
| ⌥⇧P | Pause / resume |
| ⌥⇧R | Select region |
| ⌥⇧H | Show / hide panel |

**Status indicator** in the panel header:

| Color | Meaning |
|---|---|
| 🟢 green | Running and ready (pulses in auto mode) |
| 🟠 amber | Waiting for Claude |
| ⚪ grey | Paused |
| 🔴 red | Error. The message is shown at the bottom of the panel. |

**Panel buttons:** pause, show/hide the original English, select region, and ↺ start a new session.

**Menu bar menu:**

| Item | What it does |
|---|---|
| Model | Sonnet (balanced), Haiku (fastest) or Opus (most accurate). Takes effect in a new session. |
| New session | Clears the feed and Claude's context |
| Export transcript… | Saves a Markdown file with the original, the translation and the notes |
| Show region frame | Shows or hides the highlight around the captured region |
| Show original | Shows or hides the English text above each translation |

> The interface is currently in Ukrainian. The translation target language is set in the system prompt in `Sources/Screent/ClaudeBridge.swift`.

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
