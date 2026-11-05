import Foundation
import Translation

/// On-device translation through Apple's Translation framework.
///
/// Language models are downloaded once per language pair and shared system-wide; `prepare()` triggers
/// that download (with the system's own prompt) so the first caption does not fail with "not installed".
actor AppleTranslator: Translator {
    private let session: TranslationSession

    init(from source: Locale.Language, to target: Locale.Language) {
        session = TranslationSession(installedSource: source, target: target)
    }

    func prepare() async throws {
        try await session.prepareTranslation()
    }

    func translate(_ text: String) async throws -> String {
        try await session.translate(text).targetText
    }
}

/// `TranslationSession` carries no concurrency annotations. Traqula only reaches a session through the
/// `AppleTranslator` actor that owns it, and the framework itself hands sessions to concurrent SwiftUI
/// tasks, so treating it as Sendable here is safe.
extension TranslationSession: @unchecked @retroactive Sendable {}
