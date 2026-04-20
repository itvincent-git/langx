import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 248, max: 280)
        } detail: {
            ZStack {
                Color.langxBackground
                    .ignoresSafeArea()

                switch model.activeSection {
                case .translate:
                    TranslateView()
                case .history:
                    HistoryView()
                case .logs:
                    LogsView()
                case .settings:
                    SettingsView()
                }
            }
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("langx")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.langxText)
                Text(model.t("app.subtitle"))
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(Color.langxSubtext.opacity(0.7))
            }
            .padding(.top, 12)
            .padding(.horizontal, 14)

            VStack(spacing: 8) {
                ForEach(AppSection.allCases) { section in
                    Button {
                        model.activeSection = section
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: section.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 20)
                            Text(model.sectionLabel(for: section))
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(model.activeSection == section ? Color.langxPrimary.opacity(0.12) : .clear)
                        )
                        .foregroundStyle(model.activeSection == section ? Color.langxPrimary : Color.langxSubtext)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(model.preferences.selectedEngine.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Text(model.t("sidebar.footer"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.langxSubtext)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.72))
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.langxSidebar)
    }
}

private struct TranslateView: View {
    @EnvironmentObject private var model: AppModel

    private let targetColumns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.t("translate.title"))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.langxText)
                        Text(model.t("translate.subtitle"))
                            .foregroundStyle(Color.langxSubtext)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        Pill(text: model.detectedSourceLanguage.localizedName(in: model.preferences.interfaceLanguage), tone: .neutral)
                        Pill(text: model.preferences.selectedEngine.displayName, tone: .primary)
                        Pill(text: model.preferences.preferStreaming ? model.t("translate.streaming_on") : model.t("translate.streaming_off"), tone: .warm)
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(model.t("translate.source"), systemImage: "waveform.and.magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.langxSubtext)
                        Spacer()
                        Button(model.t("translate.clear_source")) {
                            model.clearSourceText()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.langxSubtext)
                        .disabled(model.sourceText.isEmpty || model.isTranslating)
                        Text("\(model.sourceText.count) / 5000")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.langxSubtext.opacity(0.75))
                    }

                    TextEditor(
                        text: Binding(
                            get: { model.sourceText },
                            set: { model.updateSourceText($0) }
                        )
                    )
                    .font(.system(size: 18))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 220)
                    .padding(6)
                    .background(Color.clear)
                }
                .langxCardStyle()

                HStack {
                    Button {
                        model.translate()
                    } label: {
                        HStack(spacing: 10) {
                            if model.isTranslating {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Text(model.isTranslating ? model.t("translate.translating") : model.t("translate.cta"))
                                .font(.system(size: 15, weight: .bold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(LinearGradient.langxPrimary)
                        .clipShape(Capsule())
                        .shadow(color: Color.langxPrimary.opacity(0.22), radius: 18, x: 0, y: 8)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isTranslating)

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(model.t("translate.target"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.langxSubtext)
                        Spacer()
                        HStack(spacing: 10) {
                            ForEach(TranslationLanguage.supportedTargets) { language in
                                Button {
                                    model.selectTargetLanguage(language)
                                } label: {
                                    Text(language.localizedName(in: model.preferences.interfaceLanguage))
                                        .font(.system(size: 13, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(model.preferences.defaultTargetLanguage.code == language.code ? Color.langxPrimary.opacity(0.12) : Color.langxSurfaceHigh.opacity(0.6))
                                        )
                                        .foregroundStyle(model.preferences.defaultTargetLanguage.code == language.code ? Color.langxPrimary : Color.langxSubtext)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    ScrollView {
                        Text(model.translatedText.isEmpty ? model.t("translate.placeholder") : model.translatedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.system(size: 18))
                            .foregroundStyle(model.translatedText.isEmpty ? Color.langxSubtext.opacity(0.6) : Color.langxText)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 220)

                    HStack {
                        if let errorMessage = model.errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.red)
                        } else {
                            Text(model.t("translate.footer"))
                                .font(.system(size: 13))
                                .foregroundStyle(Color.langxSubtext)
                        }
                        Spacer()
                        Button(model.t("translate.copy")) {
                            model.copyTranslatedText()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.langxPrimary)
                    }
                }
                .langxCardStyle()

                LazyVGrid(columns: targetColumns, spacing: 16) {
                    MetricCard(
                        title: model.t("metric.detected_language"),
                        value: model.detectedSourceLanguage.localizedName(in: model.preferences.interfaceLanguage),
                        detail: model.t("metric.detected_language_detail"),
                        accent: .langxPrimary
                    )
                    MetricCard(
                        title: model.t("metric.engine"),
                        value: model.preferences.selectedEngine.displayName,
                        detail: model.preferences.preferStreaming ? model.t("metric.engine_streaming") : model.t("metric.engine_snapshot"),
                        accent: .langxTertiary
                    )
                    MetricCard(
                        title: model.t("metric.records"),
                        value: "\(model.history.count)",
                        detail: model.t("metric.records_detail"),
                        accent: .langxSubtext
                    )
                }
            }
            .padding(32)
        }
    }
}

private struct HistoryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.t("history.title"))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(model.t("history.subtitle"))
                            .foregroundStyle(Color.langxSubtext)
                    }
                    Spacer()
                }

                TextField(model.t("history.search"), text: $model.searchText)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(model.historySections) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(section.title)
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(1.4)
                                    .foregroundStyle(Color.langxSubtext.opacity(0.75))

                                ForEach(section.records) { record in
                                    Button {
                                        model.selectedHistoryID = record.id
                                    } label: {
                                        HStack(spacing: 14) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack(spacing: 8) {
                                                    Text(record.sourceLanguage.localizedName(in: model.preferences.interfaceLanguage))
                                                    Image(systemName: "arrow.right")
                                                    Text(record.targetLanguage.localizedName(in: model.preferences.interfaceLanguage))
                                                }
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(model.selectedHistoryID == record.id ? Color.langxPrimary : Color.langxSubtext)

                                                Text(record.sourceText)
                                                    .lineLimit(2)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundStyle(Color.langxText)
                                            }

                                            Spacer()

                                            Text(model.formattedDate(record.createdAt))
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(Color.langxSubtext)
                                        }
                                        .padding(16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .fill(model.selectedHistoryID == record.id ? Color.langxPrimary.opacity(0.12) : Color.white)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(6)
                }
            }
            .frame(width: 430)
            .langxCardStyle()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(model.t("history.detail"))
                        .font(.system(size: 22, weight: .bold))
                    Spacer()
                    Button(model.t("history.clear")) {
                        model.clearHistory()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.langxSubtext)
                    Button(model.t("history.export")) {
                        model.exportHistory()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(LinearGradient.langxPrimary)
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
                }

                if let record = model.selectedRecord {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(model.formattedDate(record.createdAt))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.langxSubtext)
                                Text(record.engine.displayName)
                                    .font(.system(size: 16, weight: .semibold))
                            }

                            DetailCard(
                                title: model.t("history.source_text"),
                                language: record.sourceLanguage.localizedName(in: model.preferences.interfaceLanguage),
                                text: record.sourceText
                            )

                            DetailCard(
                                title: model.t("history.translated_text"),
                                language: record.targetLanguage.localizedName(in: model.preferences.interfaceLanguage),
                                text: record.translatedText
                            )

                            HStack(spacing: 12) {
                                Button(model.t("history.use_source")) {
                                    model.useRecord(record)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.langxSurface)
                                .clipShape(Capsule())

                                Button(model.t("history.copy")) {
                                    model.copyRecord(record)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(LinearGradient.langxPrimary)
                                .clipShape(Capsule())
                                .foregroundStyle(.white)
                            }
                        }
                    }
                } else {
                    Spacer()
                    Text(model.t("history.empty"))
                        .foregroundStyle(Color.langxSubtext)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .langxCardStyle()
        }
        .padding(32)
    }
}

private struct LogsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.t("logs.title"))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(model.t("logs.subtitle"))
                            .foregroundStyle(Color.langxSubtext)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        Button(model.t("logs.clear")) {
                            model.clearLogs()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.langxSubtext)

                        Button(model.t("logs.copy")) {
                            model.copyLogs()
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(LinearGradient.langxPrimary)
                        .clipShape(Capsule())
                        .foregroundStyle(.white)
                    }
                }

                if model.logs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.t("logs.empty"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.langxSubtext)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
                    .langxCardStyle()
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(model.logs.reversed())) { entry in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    Text(model.formattedLogTimestamp(entry.timestamp))
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.langxSubtext)

                                    Text(entry.level.rawValue)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(logLevelBackground(for: entry.level))
                                        .clipShape(Capsule())
                                        .foregroundStyle(logLevelColor(for: entry.level))

                                    Text(entry.category)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.langxPrimary)

                                    Spacer()
                                }

                                Text(entry.message)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(Color.langxText)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(16)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                    .langxCardStyle()
                }
            }
            .padding(32)
        }
    }

    private func logLevelColor(for level: AppLogLevel) -> Color {
        switch level {
        case .debug:
            .langxSubtext
        case .info:
            .langxPrimary
        case .error:
            .red
        }
    }

    private func logLevelBackground(for level: AppLogLevel) -> Color {
        switch level {
        case .debug:
            Color.langxSurface
        case .info:
            Color.langxPrimary.opacity(0.12)
        case .error:
            Color.red.opacity(0.12)
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.t("settings.title"))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(model.t("settings.subtitle"))
                        .foregroundStyle(Color.langxSubtext)
                }

                VStack(alignment: .leading, spacing: 18) {
                    SettingsSectionTitle(icon: "globe", title: model.t("settings.general"))

                    VStack(alignment: .leading, spacing: 14) {
                        Text(model.t("settings.default_target"))
                            .font(.system(size: 14, weight: .semibold))

                        HStack(spacing: 12) {
                            ForEach(TranslationLanguage.supportedTargets) { language in
                                SelectionChip(
                                    title: language.localizedName(in: model.preferences.interfaceLanguage),
                                    isSelected: model.preferences.defaultTargetLanguage.code == language.code
                                ) {
                                    model.selectTargetLanguage(language)
                                }
                            }
                        }
                    }
                    .langxCardStyle()
                }

                VStack(alignment: .leading, spacing: 18) {
                    SettingsSectionTitle(icon: "keyboard", title: model.t("settings.quick_access"))

                    VStack(alignment: .leading, spacing: 14) {
                        Text(model.t("settings.open_panel_shortcut"))
                            .font(.system(size: 14, weight: .semibold))

                        Text(model.t("settings.open_panel_shortcut_hint"))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.langxSubtext)

                        HStack(spacing: 12) {
                            ForEach(GlobalShortcutPreset.allCases) { preset in
                                SelectionChip(
                                    title: model.shortcutPresetTitle(preset),
                                    isSelected: model.preferences.globalShortcutPreset == preset
                                ) {
                                    model.selectGlobalShortcutPreset(preset)
                                }
                            }
                        }
                    }
                    .langxCardStyle()

                    VStack(alignment: .leading, spacing: 14) {
                        Text(model.t("settings.selection_shortcut"))
                            .font(.system(size: 14, weight: .semibold))

                        Text(model.t("settings.selection_shortcut_hint"))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.langxSubtext)

                        HStack(spacing: 12) {
                            ForEach(GlobalShortcutPreset.allCases) { preset in
                                SelectionChip(
                                    title: model.shortcutPresetTitle(preset),
                                    isSelected: model.preferences.selectionTranslationShortcutPreset == preset
                                ) {
                                    model.selectSelectionTranslationShortcutPreset(preset)
                                }
                            }
                        }
                    }
                    .langxCardStyle()
                }

                VStack(alignment: .leading, spacing: 18) {
                    SettingsSectionTitle(icon: "terminal", title: model.t("settings.engine"))

                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            ForEach(TranslationEngine.allCases) { engine in
                                SelectionChip(
                                    title: engine.displayName,
                                    isSelected: model.preferences.selectedEngine == engine
                                ) {
                                    model.selectEngine(engine)
                                }
                            }
                        }

                        Toggle(isOn: Binding(
                            get: { model.preferences.preferStreaming },
                            set: { model.setStreamingEnabled($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.t("settings.streaming"))
                                    .font(.system(size: 14, weight: .semibold))
                                Text(model.t("settings.streaming_hint"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.langxSubtext)
                            }
                        }
                        .toggleStyle(.switch)

                        ForEach(TranslationEngine.allCases) { engine in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(engine.displayName)
                                    .font(.system(size: 13, weight: .semibold))

                                HStack {
                                    TextField(
                                        engine.displayName,
                                        text: Binding(
                                            get: { model.preferences.executablePath(for: engine).isEmpty ? model.resolvedExecutablePath(for: engine) : model.preferences.executablePath(for: engine) },
                                            set: { model.setExecutablePath($0, for: engine) }
                                        )
                                    )
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(Color.langxSurfaceHigh.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                    Button(model.t("settings.browse")) {
                                        model.browseExecutable(for: engine)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color.langxSurface)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .langxCardStyle()
                }

                VStack(alignment: .leading, spacing: 18) {
                    SettingsSectionTitle(icon: "character.bubble", title: model.t("settings.appearance"))

                    VStack(alignment: .leading, spacing: 14) {
                        Text(model.t("settings.interface_language"))
                            .font(.system(size: 14, weight: .semibold))

                        HStack(spacing: 12) {
                            ForEach(InterfaceLanguage.allCases) { language in
                                SelectionChip(
                                    title: language.displayName,
                                    isSelected: model.preferences.interfaceLanguage == language
                                ) {
                                    model.selectInterfaceLanguage(language)
                                }
                            }
                        }
                    }
                    .langxCardStyle()
                }

                HStack {
                    Spacer()
                    Button(model.t("settings.reset")) {
                        model.resetPreferences()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.langxSubtext)
                }
            }
            .padding(32)
        }
    }
}

private struct Pill: View {
    enum Tone {
        case neutral
        case primary
        case warm
    }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch tone {
        case .neutral: Color.white.opacity(0.8)
        case .primary: Color.langxPrimary.opacity(0.12)
        case .warm: Color.langxTertiary.opacity(0.12)
        }
    }

    private var foreground: Color {
        switch tone {
        case .neutral: .langxSubtext
        case .primary: .langxPrimary
        case .warm: .langxTertiary
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.langxSubtext.opacity(0.7))
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Color.langxSubtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .langxCardStyle()
    }
}

private struct DetailCard: View {
    let title: String
    let language: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text(language)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.langxSurface)
                    .clipShape(Capsule())
            }
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .foregroundStyle(Color.langxText)
        }
        .langxCardStyle()
    }
}

private struct SettingsSectionTitle: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.langxPrimary)
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.langxSubtext)
        }
    }
}

private struct SelectionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? Color.langxPrimary.opacity(0.12) : Color.langxSurfaceHigh.opacity(0.6))
                )
                .foregroundStyle(isSelected ? Color.langxPrimary : Color.langxSubtext)
        }
        .buttonStyle(.plain)
    }
}
