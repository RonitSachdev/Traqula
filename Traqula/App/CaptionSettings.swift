import Foundation

/// User preferences. Stored in `UserDefaults` so the Settings window's `@AppStorage` fields and the
/// session share one source of truth; the session reads a snapshot when captions start.
struct CaptionSettings: Sendable, Equatable {
    enum Key {
        static let theirLanguage = "theirLanguage"
        static let myLanguage = "myLanguage"
        static let targetLanguage = "targetLanguage"
        static let captureMicrophone = "captureMicrophone"
        static let showOriginalText = "showOriginalText"
        static let captionFontSize = "captionFontSize"
        static let hideFromScreenSharing = "hideFromScreenSharing"
    }

    /// BCP 47 code of the language remote participants speak (system audio).
    var theirLanguage: String
    /// BCP 47 code of the language the user speaks (microphone).
    var myLanguage: String
    /// BCP 47 code of the language captions are shown in.
    var targetLanguage: String
    var captureMicrophone: Bool
    var showOriginalText: Bool
    var captionFontSize: Double
    /// Keeps the caption window out of screenshots and shared screens.
    var hideFromScreenSharing: Bool

    static let `default` = CaptionSettings(
        theirLanguage: "ja",
        myLanguage: "ja",
        targetLanguage: "en",
        captureMicrophone: true,
        showOriginalText: true,
        captionFontSize: 22,
        hideFromScreenSharing: true
    )

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Key.theirLanguage: `default`.theirLanguage,
            Key.myLanguage: `default`.myLanguage,
            Key.targetLanguage: `default`.targetLanguage,
            Key.captureMicrophone: `default`.captureMicrophone,
            Key.showOriginalText: `default`.showOriginalText,
            Key.captionFontSize: `default`.captionFontSize,
            Key.hideFromScreenSharing: `default`.hideFromScreenSharing,
        ])
    }

    static func load(from defaults: UserDefaults = .standard) -> CaptionSettings {
        CaptionSettings(
            theirLanguage: defaults.string(forKey: Key.theirLanguage) ?? `default`.theirLanguage,
            myLanguage: defaults.string(forKey: Key.myLanguage) ?? `default`.myLanguage,
            targetLanguage: defaults.string(forKey: Key.targetLanguage) ?? `default`.targetLanguage,
            captureMicrophone: defaults.bool(forKey: Key.captureMicrophone),
            showOriginalText: defaults.bool(forKey: Key.showOriginalText),
            captionFontSize: defaults.double(forKey: Key.captionFontSize),
            hideFromScreenSharing: defaults.bool(forKey: Key.hideFromScreenSharing)
        )
    }
}
