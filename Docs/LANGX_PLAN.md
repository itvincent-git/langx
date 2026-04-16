# langx Product, Design, and Engineering Plan

## Product

- Product name: `langx`
- Platform: macOS SwiftUI desktop app
- Core use case: quick translation for multilingual work using local CLI-based LLM agents instead of embedded SDKs
- Primary users: developers, PMs, designers, operators, and bilingual knowledge workers
- Core requirements covered:
  - Use `codex`, `gemini`, and `claude` CLIs as translation engines
  - Auto-detect source language
  - Support English and Simplified Chinese as target languages
  - Persist translation history locally and support list/detail browsing
  - Support English and Simplified Chinese UI, defaulting to English
  - Stream results progressively when the selected CLI exposes streaming output

## Design

- Source of truth: Stitch project `6255785941976326484`
- Implemented screens:
  - Main translator
  - Translation history
  - History detail
  - Settings
- Design translation into SwiftUI:
  - Editorial desktop layout with wide spacing and layered surfaces
  - Left navigation rail + large content canvas
  - No hard divider-heavy layout; hierarchy is created through tonal surfaces
  - Gradient primary CTA for the main translation action
  - Card-based history list and detail panels
  - Light mode default, following the Stitch color tokens

## Engineering

### Architecture

- UI: SwiftUI
- State: `ObservableObject` + `@Published`
- Local persistence: JSON files under `Application Support/langx`
- Language detection: `NaturalLanguage.NLLanguageRecognizer`
- Engine integration: `Foundation.Process`

### CLI strategy

- `codex`
  - Launches one long-lived `codex app-server` subprocess over stdio
  - Uses JSONL / JSON-RPC to `initialize`, `thread/start`, and `turn/start`
  - Pins translation threads to `gpt-5.4-mini` to keep cost aligned with the translation use case
  - Reuses the same subprocess across translations while keeping each translation on a fresh ephemeral thread
- `gemini`
  - Uses `--prompt`
  - Uses `--output-format stream-json` when streaming is enabled
- `claude`
  - Uses `--print`
  - Uses `--output-format stream-json` when streaming is enabled

### Streaming

- Streaming is not assumed universally.
- The app attempts streaming only when:
  - the user has streaming enabled in settings
  - the selected CLI exposes a streaming output mode
- A tolerant JSON-line parser is used because each CLI emits a slightly different event schema.

### Persistence

- `preferences.json`
  - selected engine
  - default target language
  - interface language
  - streaming preference
  - optional custom executable paths
- `history.json`
  - source text
  - translated text
  - source language code
  - target language code
  - engine
  - timestamp
  - streamed flag

### Tradeoffs

- JSON persistence is simpler than SwiftData for this version and keeps the app easy to inspect and migrate.
- CLI invocation is intentionally isolated behind one translation service so the app can later swap to SDK or MCP-based engines without rewriting the UI.
- The streaming parser is heuristic, because the three CLIs do not share a stable event schema.
