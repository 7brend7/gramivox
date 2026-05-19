# GramiVox

GramiVox is a macOS SwiftUI utility app that:

- listens for a global hotkey: `Control + Option + G`
- tries to read the currently selected text from any app
- opens a popup near the cursor
- loads ChatGPT in a private `WKWebView` session
- fills the prompt with `fix grammar or rephrase: [SELECTED TEXT]`

## Build

```bash
swift build
```

## Run As Binary

```bash
swift run GramiVox
```

This works for quick testing, but macOS may still attribute permissions to your terminal app.

## Build As Real App

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/GramiVox.app
```

Launching the bundled app gives GramiVox its own app name, icon, tray behavior, and cleaner macOS permission handling.

## First launch

1. Open the app.
2. Click `Request Access`.
3. Approve Accessibility access in `System Settings > Privacy & Security > Accessibility`.
4. Select text in any app and press the configured hotkey.

## Notes

- The app runs as a menu bar utility when launched from the bundled `.app`.
- The app first tries the Accessibility API for selected text.
- If that fails, it falls back to simulating `Command + C`, reads the copied text, and restores your clipboard contents.
- ChatGPT is loaded in a non-persistent web session, so it behaves like a private/incognito popup and does not keep website data between launches.
- The prompt template and hotkey can be changed in Settings.
