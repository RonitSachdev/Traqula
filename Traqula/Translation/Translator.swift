/// Translates text from one language to another. Implementations decide where the work happens.
protocol Translator: Sendable {
    func translate(_ text: String) async throws -> String
}
