# langx

`langx` is a SwiftUI macOS translation app that uses `codex`, `gemini`, or `claude` CLI tools as the translation engine.

## Features

- Auto-detects the current source language
- Supports English and Simplified Chinese as target languages
- Persists translation history locally
- Browses history as a list with full detail view
- Supports English and Simplified Chinese UI, defaulting to English
- Streams output when the selected CLI supports streaming

## Run

```bash
swift run
```

## Test

```bash
swift test
```

## Package DMG

```bash
./scripts/package-dmg.sh
```

The script builds a release binary, assembles `dist/langx.app`, and writes the installer image to `dist/langx-0.1.0.dmg`.

To keep Accessibility permission stable across installs, sign the app bundle with the same identity each time:

```bash
security find-identity -v -p codesigning
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package-dmg.sh
```

Optional distribution steps:

```bash
# Sign the app and DMG, then notarize and staple the DMG.
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARIZE=1 \
NOTARY_PROFILE="langx-notary" \
./scripts/package-dmg.sh
```

Notes:

- `CODESIGN_DMG_IDENTITY` lets you override the identity used for the `.dmg`. It defaults to `CODESIGN_IDENTITY`.
- `CODESIGN_TIMESTAMP=1` enables Apple timestamping during signing.
- `ENABLE_HARDENED_RUNTIME=1` is enabled by default and is required for notarization.
- `NOTARY_PROFILE` should match a keychain profile created with `xcrun notarytool store-credentials`.

## Notes

- The app resolves `codex`, `gemini`, and `claude` from the current `PATH` and several common install paths.
- `codex` is integrated through a persistent `codex app-server` stdio session and pins translation requests to `gpt-5.4-mini`; `gemini` and `claude` still run per-request CLI invocations.
- You can override executable paths in the Settings screen.
- Product, design, and engineering notes live in [Docs/LANGX_PLAN.md](Docs/LANGX_PLAN.md).
