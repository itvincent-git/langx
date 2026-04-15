# Repository Guidelines

## Project Structure & Module Organization
`langx` is a Swift Package Manager macOS app. Application code lives in `Sources/langx`, with UI entry points in files such as `LangXApp.swift`, state and business logic in `AppModel.swift`, and integration helpers like `CLITranslationService.swift`. Localized resources are under `Sources/langx/Resources/<locale>.lproj/`. Tests live in `Tests/langxTests`. Product and architecture notes are kept in `Docs/LANGX_PLAN.md`.

## Build, Test, and Development Commands
- `swift run`: builds and launches the macOS app locally.
- `swift build`: checks that the package compiles without starting the UI.
- `swift test`: runs the `Testing`-based test suite in `Tests/langxTests`.

Run commands from the repository root. Use `swift test` before opening a PR, even for UI-focused changes.

## Coding Style & Naming Conventions
Follow existing Swift conventions:
- Use 4-space indentation and keep imports minimal.
- Use `UpperCamelCase` for types (`AppModel`) and `lowerCamelCase` for properties and functions (`runTranslation()`).
- Keep one primary type per file when practical, and name files after the main type or feature.
- Prefer small SwiftUI views and isolate platform or process logic in support/service files.

There is no formatter config checked in yet, so match the surrounding style closely and keep diffs tight.

## Testing Guidelines
Tests use Swift's `Testing` framework with `@Test` and `#expect(...)`. Add tests in `Tests/langxTests/langxTests.swift` or split into new `*Tests.swift` files as coverage grows. Name tests after the behavior they verify, for example `csvExportEscapesQuotes`. Cover translation logic, persistence formatting, and language constraints when changing those areas.

## Commit & Pull Request Guidelines
Current history uses a Conventional Commit-style subject, for example `feat(): init project`. Keep commit messages short, imperative, and scoped when useful, such as `fix(history): preserve selection after reload`.

PRs should include:
- a brief summary of user-visible or architectural changes
- linked issues or task references when available
- screenshots for SwiftUI layout or localization changes
- confirmation that `swift test` passed

## Configuration & Safety Notes
The app resolves `codex`, `gemini`, and `claude` from `PATH` or user-specified settings. Do not hardcode machine-specific executable paths or commit local application data.
