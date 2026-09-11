# 60Minus

60Minus is a lightweight, native macOS writing assistant that converts English number words into digits wherever you type.

Type a completed number phrase, and a small suggestion menu appears beside the text. Accept the compact number with **Tab**, choose an alternative with the arrow keys, click an option, or simply keep typing to dismiss it.

## Support Miguel's work

<p align="center">
  If 60Minus makes typing a little easier, you can support Miguel's work across design, photography, AI, and vibe coding.<br><br>
  <a href="https://buymeacoffee.com/migw03">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Miguel a coffee" height="60">
  </a>
</p>

| What you type | Primary suggestion | Alternative |
| --- | --- | --- |
| `five five three ` | `553` | `5 5 3` |
| `one two ten ` | `1210` | `1 2 10` |
| `twenty one ` | `21` | — |
| `one hundred forty two ` | `142` | — |

60Minus runs as a menu-bar utility, stays out of the way, and keeps keyboard focus in the application where you are writing.

## Requirements

- macOS 13 Ventura or newer
- A Mac capable of running the Swift 5.10 toolchain
- Xcode Command Line Tools or Xcode
- Accessibility permission for 60Minus

The project has no third-party dependencies.

## Installation

There is not yet a downloadable, notarized release. For now, build 60Minus from source.

### 1. Install Apple's developer tools

Open Terminal and run:

```sh
xcode-select --install
```

If Xcode or the Command Line Tools are already installed, macOS will tell you.

### 2. Clone and build 60Minus

```sh
git clone https://github.com/MigW03/60minus.git
cd 60minus
./scripts/build-app.sh
```

The finished application is created at:

```text
build/60Minus.app
```

### 3. Launch the app

```sh
open build/60Minus.app
```

60Minus has no Dock icon or main window. Look for the number-circle icon in the macOS menu bar.

### 4. Grant Accessibility permission

60Minus needs Accessibility access to read the text immediately around the caret and replace a suggestion you explicitly accept.

1. Open **System Settings**.
2. Go to **Privacy & Security → Accessibility**.
3. Enable **60Minus**.
4. If 60Minus was already listed but is not responding, toggle it off and on.

The menu-bar app checks permission continuously and should begin working without another relaunch.

> Development builds are ad-hoc signed. Rebuilding changes the app's code identity, so macOS may ask you to toggle Accessibility permission off and on again.

## How to use 60Minus

1. Launch 60Minus and confirm its menu-bar status says **60Minus is running**.
2. Focus an editable text field in an application such as TextEdit, Notes, Safari, or a Chromium-based editor.
3. Type an English number phrase followed by a space, punctuation mark, or line break.
4. When the suggestion menu appears, choose what to do:

   - Press **Tab** to accept the highlighted suggestion.
   - Press **Up** or **Down** to select another interpretation, then press **Tab**.
   - Click any visible suggestion to accept that exact option.
   - Press **Escape** or click **×** to dismiss the menu.
   - Continue typing normally to dismiss the menu without changing your text.

For example, typing `five five three ` shows `553` and `5 5 3`. The first option is selected initially. Pressing Down selects the spaced version; pressing Tab then replaces only `five five three` with `5 5 3` and preserves the trailing space.

### Correcting an existing phrase

60Minus reads the current document instead of relying only on a record of keystrokes. If you type `five five tee`, move the caret back, and correct `tee` to `three`, it can recognize the resulting `five five three` phrase and suggest `553`.

### Pausing or quitting

Click the 60Minus menu-bar icon to:

- Pause or resume suggestions
- Open Accessibility settings
- Quit 60Minus

## Number interpretation

60Minus distinguishes between spoken sequences and conventional compound numbers:

- Digit-like sequences are concatenated: `five five three` → `553`.
- Mixed spoken chunks remain sequential: `one two ten` → `1210`, not `13`.
- Tens followed by a unit form a conventional number: `twenty one` → `21`.
- Scale words are evaluated arithmetically: `one hundred forty two` → `142`.
- Newlines and layout whitespace are hard phrase boundaries; numbers on separate lines are never joined.

## Privacy and security

60Minus works locally on your Mac.

- It makes no network requests.
- It has no analytics or telemetry.
- It does not save the text you type.
- It reads only a bounded section of text around the active caret when checking for a number phrase.
- It ignores secure and password fields.
- It changes text only after you accept a suggestion.

Accessibility permission is powerful. Review the source and build the app yourself if you want to verify its behavior.

## Troubleshooting

### No suggestion appears

- Open the menu-bar menu and confirm 60Minus is running rather than paused.
- Confirm 60Minus is enabled under **Privacy & Security → Accessibility**.
- If it is already enabled, toggle it off and on—especially after rebuilding.
- Make sure the number phrase is complete and followed by a boundary such as a space or punctuation.
- Try TextEdit to determine whether the current editor exposes compatible Accessibility text ranges.

### Tab inserts a tab instead of accepting

The keyboard monitor is not active. Re-enable 60Minus in Accessibility settings, then try again. A visible suggestion should intercept Tab; when no suggestion is visible, Tab continues to behave normally in the current application.

### Clicking works but Tab does not

Make sure you are running the latest app from `build/60Minus.app`, quit any older 60Minus process, relaunch the new build, and re-enable Accessibility permission if necessary.

### A particular app does not work

60Minus supports standard AppKit character ranges and document-scoped Accessibility text markers used by many Chromium, Electron, and WebKit editors. Some custom editors do not expose enough information through macOS Accessibility APIs; those controls are not currently supported.

### Accessibility permission keeps resetting

The development script uses ad-hoc code signing. A stable distribution build should be signed with a persistent Apple Developer ID certificate and notarized. Until then, rebuilding may require toggling the permission again.

## Development

Run the automated test suite:

```sh
./scripts/test.sh
```

Build the release application bundle:

```sh
./scripts/build-app.sh
```

Or build the Swift package directly:

```sh
swift build
```

### Project structure

- `Sources/SixtyMinusApp/AppDelegate.swift` — menu-bar lifecycle, permission polling, pause, settings, and quit actions
- `Sources/SixtyMinusApp/EventTap.swift` — observes keyboard and mouse input while leaving ordinary input untouched
- `Sources/SixtyMinusApp/AccessibilityClient.swift` — reads focused text, finds geometry, validates candidates, and performs accepted replacements
- `Sources/SixtyMinusApp/NumberParser.swift` — parses English number words and produces alternatives
- `Sources/SixtyMinusApp/ContextScanner.swift` — finds a completed number phrase around the current caret
- `Sources/SixtyMinusApp/CorrectionCoordinator.swift` — coordinates scanning, presentation, dismissal, selection, and acceptance
- `Sources/SixtyMinusApp/SuggestionPanel.swift` — renders the non-activating suggestion menu
- `Tests/SixtyMinusTests/NumberParserTests.swift` — parser and context-scanner regression tests

## Roadmap

- Spoken-symbol conversion, including asterisks, parentheses, brackets, plus and minus signs, percentages, slashes, and other common symbols
- Portuguese support for number words and spoken symbols

## Current limitations

- English number words only
- macOS 13 or newer
- The target control must expose editable text through macOS Accessibility APIs
- In some browser and web-based editors, including ChatGPT, the suggestion popup may appear outside the application's window because the editor reports inaccurate text coordinates through Accessibility
- No signed and notarized downloadable release yet
- No configurable shortcuts or launch-at-login setting yet

## Contributing

Bug reports and focused pull requests are welcome. When reporting editor-specific behavior, include:

- The macOS version
- The application and version where the issue occurred
- The number phrase you typed
- Whether the suggestion appeared
- Whether clicking, Tab, Escape, and ordinary typing behaved as expected

Please run `./scripts/test.sh` before submitting code changes.
