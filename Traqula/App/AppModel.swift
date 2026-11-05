import AVFoundation
import Foundation
import Observation
import Speech
import Translation
import MeetingRecords

enum AppError: LocalizedError {
    case microphoneAccessDenied
    case unsupportedSpeechLanguage(String)
    case translationModelMissing(source: String, target: String)

    var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied:
            "Microphone access was denied. Allow it in System Settings > Privacy & Security > Microphone, or turn off microphone captions."
        case let .unsupportedSpeechLanguage(code):
            "On-device speech recognition does not support \"\(code)\"."
        case let .translationModelMissing(source, target):
            "The \(source) → \(target) translation model is not installed. Download it in Settings."
        }
    }
}

/// App-wide state: whether captions are running, the current session, and the caption window.
@MainActor
@Observable
final class AppModel {
    enum State: Equatable {
        case idle, starting, running, stopping
    }

    private(set) var state = State.idle
    private(set) var session: CaptionSession?
    /// The most recent problem worth showing in the menu, cleared when captions start.
    private(set) var statusMessage: String?
    /// True while the microphone channel is feeding silence, e.g. because the user is muted in the meeting.
    private(set) var isMicrophonePaused = false
    /// What the browser extension reports about the current meeting page.
    let bridge = MeetingBridge()

    private var panel: CaptionPanelController?
    private var microphone: MicrophoneSource?
    private var bridgeServer: MeetingBridgeServer?

    init() {
        CaptionSettings.registerDefaults()
        do {
            try BrowserExtension.install()
        } catch {
            statusMessage = "Could not install the Chrome extension folder: \(error.localizedDescription)"
        }
        do {
            bridgeServer = try MeetingBridgeServer(
                onSnapshot: { [weak self] snapshot in self?.bridgeDidReport(snapshot) },
                onConnectionCountChange: { [weak self] count in self?.bridge.isExtensionConnected = count > 0 }
            )
        } catch {
            statusMessage = "Browser meeting bridge unavailable: \(error.localizedDescription)"
        }
    }

    // MARK: Browser meetings

    private func bridgeDidReport(_ snapshot: BridgeSnapshot) {
        let wasInCall = bridge.inCall
        bridge.apply(snapshot)
        let settings = CaptionSettings.load()

        if settings.followBrowserMute, let microphone, let muted = snapshot.muted {
            microphone.isPaused = muted
            isMicrophonePaused = muted
        }
        if let session {
            Task { try? await session.record.update(title: snapshot.title, participants: snapshot.participants) }
        }
        guard settings.autoStartBrowserMeetings else { return }
        if snapshot.inCall, !wasInCall, state == .idle {
            Task { await start() }
        } else if !snapshot.inCall, wasInCall, state == .running {
            Task { await stop() }
        }
    }

    var isRunning: Bool { state == .running }
    var isCapturingMicrophone: Bool { isRunning && microphone != nil }

    func toggleMicrophonePause() {
        guard let microphone else { return }
        microphone.isPaused.toggle()
        isMicrophonePaused = microphone.isPaused
    }

    func toggleCaptions() {
        Task {
            switch state {
            case .idle: await start()
            case .running: await stop()
            case .starting, .stopping: break
            }
        }
    }

    func start() async {
        guard state == .idle else { return }
        state = .starting
        statusMessage = nil
        do {
            let settings = CaptionSettings.load()
            let session = try await makeSession(settings)
            let panel = CaptionPanelController(session: session, settings: settings)
            panel.show()
            session.start()
            self.session = session
            self.panel = panel
            state = .running
        } catch {
            statusMessage = error.localizedDescription
            state = .idle
        }
    }

    func stop() async {
        guard state == .running, let session else { return }
        state = .stopping
        await session.stop()
        panel?.close()
        panel = nil
        self.session = nil
        microphone = nil
        isMicrophonePaused = false
        state = .idle
    }

    // MARK: Session assembly

    private func makeSession(_ settings: CaptionSettings) async throws -> CaptionSession {
        let target = Locale.Language(identifier: settings.targetLanguage)
        var translators: [Locale.Language: AppleTranslator] = [:]

        func makeChannel(_ source: any AudioSource, languageCode: String) async throws -> CaptionSession.Channel {
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: languageCode)) else {
                throw AppError.unsupportedSpeechLanguage(languageCode)
            }
            try await LiveTranscriber.installAssets(for: locale)

            let language = Locale.Language(identifier: languageCode)
            var translator: AppleTranslator?
            if language != target {
                if let existing = translators[language] {
                    translator = existing
                } else {
                    let fresh = AppleTranslator(from: language, to: target)
                    do {
                        try await fresh.prepare()
                    } catch TranslationError.notInstalled {
                        throw AppError.translationModelMissing(source: languageCode, target: settings.targetLanguage)
                    }
                    translators[language] = fresh
                    translator = fresh
                }
            }
            return CaptionSession.Channel(source: source, transcriber: LiveTranscriber(locale: locale), translator: translator)
        }

        var channels = [try await makeChannel(SystemAudioTap(), languageCode: settings.theirLanguage)]
        if settings.captureMicrophone {
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw AppError.microphoneAccessDenied }
            let microphone = MicrophoneSource()
            channels.append(try await makeChannel(microphone, languageCode: settings.myLanguage))
            if settings.followBrowserMute, let muted = bridge.isMuted {
                microphone.isPaused = muted
                isMicrophonePaused = muted
            }
            self.microphone = microphone
        }
        let record = try MeetingRecord()
        try await record.update(title: bridge.title, participants: bridge.participants)
        let bridge = self.bridge
        return CaptionSession(channels: channels, targetLanguage: target, record: record) { channel, date in
            bridge.speakerName(for: channel, at: date)
        }
    }
}
