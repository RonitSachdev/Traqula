import AppKit
import Foundation
import SwiftUI

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
        static let captionBackgroundColor = "captionBackgroundColor"
        static let captionBackgroundOpacity = "captionBackgroundOpacity"
        static let followBrowserMute = "followBrowserMute"
        static let autoStartBrowserMeetings = "autoStartBrowserMeetings"
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
    /// Tint of the caption card as a `#RRGGBB` hex string, and how strongly it is applied over the glass.
    var captionBackgroundColor: String
    var captionBackgroundOpacity: Double
    /// Browser meetings, reported by the Traqula Bridge extension.
    var followBrowserMute: Bool
    var autoStartBrowserMeetings: Bool

    static let `default` = CaptionSettings(
        theirLanguage: "ja",
        myLanguage: "ja",
        targetLanguage: "en",
        captureMicrophone: true,
        showOriginalText: true,
        captionFontSize: 22,
        hideFromScreenSharing: true,
        captionBackgroundColor: "#000000",
        captionBackgroundOpacity: 0.55,
        followBrowserMute: true,
        autoStartBrowserMeetings: true
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
            Key.captionBackgroundColor: `default`.captionBackgroundColor,
            Key.captionBackgroundOpacity: `default`.captionBackgroundOpacity,
            Key.followBrowserMute: `default`.followBrowserMute,
            Key.autoStartBrowserMeetings: `default`.autoStartBrowserMeetings,
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
            hideFromScreenSharing: defaults.bool(forKey: Key.hideFromScreenSharing),
            captionBackgroundColor: defaults.string(forKey: Key.captionBackgroundColor) ?? `default`.captionBackgroundColor,
            captionBackgroundOpacity: defaults.double(forKey: Key.captionBackgroundOpacity),
            followBrowserMute: defaults.bool(forKey: Key.followBrowserMute),
            autoStartBrowserMeetings: defaults.bool(forKey: Key.autoStartBrowserMeetings)
        )
    }
}

extension Color {
    /// Parses `#RRGGBB`; falls back to black for anything else.
    init(hex: String) {
        var value: UInt64 = 0
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, Scanner(string: digits).scanHexInt64(&value) else {
            self = .black
            return
        }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    /// `#RRGGBB` in sRGB, for storing in settings.
    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}
