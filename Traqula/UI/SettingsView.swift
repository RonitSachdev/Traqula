import Speech
import SwiftUI
import Translation

struct SettingsView: View {
    @AppStorage(CaptionSettings.Key.theirLanguage) private var theirLanguage = CaptionSettings.default.theirLanguage
    @AppStorage(CaptionSettings.Key.myLanguage) private var myLanguage = CaptionSettings.default.myLanguage
    @AppStorage(CaptionSettings.Key.targetLanguage) private var targetLanguage = CaptionSettings.default.targetLanguage
    @AppStorage(CaptionSettings.Key.captureMicrophone) private var captureMicrophone = CaptionSettings.default.captureMicrophone
    @AppStorage(CaptionSettings.Key.showOriginalText) private var showOriginalText = CaptionSettings.default.showOriginalText
    @AppStorage(CaptionSettings.Key.captionFontSize) private var captionFontSize = CaptionSettings.default.captionFontSize
    @AppStorage(CaptionSettings.Key.hideFromScreenSharing) private var hideFromScreenSharing = CaptionSettings.default.hideFromScreenSharing

    /// Languages the on-device recognizer and translator support, loaded once the window opens.
    @State private var speechLanguages: [String] = []
    @State private var translationLanguages: [String] = []
    @State private var models = TranslationModels()
    @State private var assistants = AssistantConnections()

    var body: some View {
        Form {
            Section("Languages") {
                languagePicker("They speak", selection: $theirLanguage, options: speechLanguages)
                languagePicker("I speak", selection: $myLanguage, options: speechLanguages)
                languagePicker("Show captions in", selection: $targetLanguage, options: translationLanguages)
            }
            Section {
                ForEach(models.pairs) { pair in
                    LabeledContent(pair.title) {
                        switch pair.status.display {
                        case .installed:
                            Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .supported:
                            Button("Download") { models.download(pair) }
                                .disabled(models.downloading != nil)
                        case .unsupported:
                            Label("Not available", systemImage: "xmark.circle").foregroundStyle(.secondary)
                        case .unknown:
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                if let message = models.message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Translation models")
            } footer: {
                Text("Models are downloaded once and shared with every app on this Mac.")
            }
            Section("Audio") {
                Toggle("Also caption my microphone", isOn: $captureMicrophone)
            }
            Section {
                if let executable = assistants.executable {
                    ForEach(MCPClient.known) { client in
                        LabeledContent(client.name) {
                            switch assistants.statuses[client.id] ?? .notInstalled {
                            case .connected:
                                Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            case .available:
                                Button("Connect") { assistants.connect(client) }
                            case .notInstalled:
                                Text("Not installed").foregroundStyle(.secondary)
                            }
                        }
                    }
                    LabeledContent("Claude Code") {
                        Button("Copy command") { assistants.copy(MCPServer.claudeCodeCommand(for: executable), label: "Command") }
                    }
                    LabeledContent("Codex CLI") {
                        Button("Copy config") { assistants.copy(MCPServer.codexSnippet(for: executable), label: "Config") }
                    }
                    LabeledContent("Any other MCP client") {
                        Button("Copy JSON") { assistants.copy(MCPServer.jsonSnippet(for: executable), label: "JSON") }
                    }
                    if let message = assistants.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Text("This build is missing the MCP server.").foregroundStyle(.secondary)
                }
            } header: {
                Text("AI assistants")
            } footer: {
                Text("Lets an assistant list, read, and search your meeting transcripts over MCP. It only reads; nothing leaves the Mac unless the assistant you connect sends it. If you move Traqula.app, connect again.")
            }
            Section("Captions") {
                Toggle("Show the original text under the translation", isOn: $showOriginalText)
                Toggle("Hide captions from screen sharing and screenshots", isOn: $hideFromScreenSharing)
                LabeledContent("Text size") {
                    Slider(value: $captionFontSize, in: 16...40, step: 1) {
                        Text("Text size")
                    }
                    .frame(width: 180)
                }
            }
            Text("Changes apply the next time captions start.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear { assistants.refresh() }
        .task {
            let speechLocales = await DictationTranscriber.supportedLocales
            speechLanguages = Set(speechLocales.map { $0.language.minimalIdentifier }).sorted()
            translationLanguages = await Self.translationLanguageCodes()
        }
        .task(id: [theirLanguage, myLanguage, targetLanguage]) {
            await models.refresh(sources: [theirLanguage, myLanguage], target: targetLanguage)
        }
        // The system's download sheet is only offered through SwiftUI, so the download runs here.
        .translationTask(models.downloading) { session in
            await models.finishDownload { try await session.prepareTranslation() }
            await models.refresh(sources: [theirLanguage, myLanguage], target: targetLanguage)
        }
    }

    /// Runs off the main actor because `LanguageAvailability` is not Sendable.
    nonisolated private static func translationLanguageCodes() async -> [String] {
        let languages = await LanguageAvailability().supportedLanguages
        return Set(languages.map(\.minimalIdentifier)).sorted()
    }

    private func languagePicker(_ title: String, selection: Binding<String>, options: [String]) -> some View {
        // Keep the stored value selectable even before the list loads.
        let choices = options.contains(selection.wrappedValue) ? options : [selection.wrappedValue] + options
        return Picker(title, selection: selection) {
            ForEach(choices, id: \.self) { code in
                Text(languageName(code)).tag(code)
            }
        }
    }
}

/// Install state of the translation language pairs the current settings need.
@MainActor
@Observable
private final class TranslationModels {
    struct Pair: Identifiable {
        let source: String
        let target: String
        var status: LanguageAvailability.Status?

        var id: String { "\(source)->\(target)" }
        var title: String { "\(languageName(source)) → \(languageName(target))" }
    }

    private(set) var pairs: [Pair] = []
    private(set) var downloading: TranslationSession.Configuration?
    private(set) var message: String?

    func refresh(sources: [String], target: String) async {
        let needed = Array(NSOrderedSet(array: sources.filter { $0 != target })) as! [String]
        pairs = needed.map { Pair(source: $0, target: target, status: nil) }
        for index in pairs.indices {
            let pair = pairs[index]
            pairs[index].status = await Self.status(from: pair.source, to: pair.target)
        }
    }

    func download(_ pair: Pair) {
        message = nil
        downloading = TranslationSession.Configuration(
            source: Locale.Language(identifier: pair.source),
            target: Locale.Language(identifier: pair.target)
        )
    }

    func finishDownload(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            message = error.localizedDescription
        }
        downloading = nil
    }

    nonisolated private static func status(from source: String, to target: String) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(
            from: Locale.Language(identifier: source),
            to: Locale.Language(identifier: target)
        )
    }
}

extension LanguageAvailability.Status? {
    // Keeps the view's switch readable: nil means "still checking".
    fileprivate enum Display { case installed, supported, unsupported, unknown }

    fileprivate var display: Display {
        switch self {
        case .installed: .installed
        case .supported: .supported
        case .unsupported: .unsupported
        case .none: .unknown
        @unknown default: .unknown
        }
    }
}

private func languageName(_ code: String) -> String {
    Locale.current.localizedString(forIdentifier: code) ?? code
}
