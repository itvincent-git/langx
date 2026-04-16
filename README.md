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

## Notes

- The app resolves `codex`, `gemini`, and `claude` from the current `PATH` and several common install paths.
- `codex` is integrated through a persistent `codex app-server` stdio session and pins translation requests to `gpt-5.4-mini`; `gemini` and `claude` still run per-request CLI invocations.
- You can override executable paths in the Settings screen.
- Product, design, and engineering notes live in [Docs/LANGX_PLAN.md](Docs/LANGX_PLAN.md).
