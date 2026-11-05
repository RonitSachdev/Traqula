import AppKit
import SwiftUI
import MeetingRecords

/// Every caption line of the session, pinned to the newest line, with scrolling back allowed.
struct CaptionView: View {
    let session: CaptionSession

    var body: some View {
        CaptionCard(lines: session.timeline.lines)
    }
}

/// The soft rounded glass card that shows caption lines. Used by the floating window and by the preview in Settings.
struct CaptionCard: View {
    let lines: [CaptionLine]

    // Appearance is read live so changes in Settings show on the card immediately.
    @AppStorage(CaptionSettings.Key.captionFontSize) private var fontSize = CaptionSettings.default.captionFontSize
    @AppStorage(CaptionSettings.Key.showOriginalText) private var showOriginalText = CaptionSettings.default.showOriginalText
    @AppStorage(CaptionSettings.Key.captionBackgroundColor) private var backgroundHex = CaptionSettings.default.captionBackgroundColor
    @AppStorage(CaptionSettings.Key.captionBackgroundOpacity) private var backgroundOpacity = CaptionSettings.default.captionBackgroundOpacity

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(lines) { line in
                    CaptionLineView(line: line, fontSize: fontSize, showOriginalText: showOriginalText)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
        .scrollIndicators(.hidden)
        .glassEffect(.regular.tint(Color(hex: backgroundHex).opacity(backgroundOpacity)), in: .rect(cornerRadius: 24, style: .continuous))
        .padding(1)
    }
}

private struct CaptionLineView: View {
    let line: CaptionLine
    let fontSize: Double
    let showOriginalText: Bool
    @AppStorage(CaptionSettings.Key.captionBackgroundColor) private var backgroundHex = CaptionSettings.default.captionBackgroundColor
    @AppStorage(CaptionSettings.Key.captionBackgroundOpacity) private var backgroundOpacity = CaptionSettings.default.captionBackgroundOpacity

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(line.speaker ?? line.channel.displayName)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(badgeColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(line.translatedText ?? line.sourceText)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                if showOriginalText, line.translatedText != nil {
                    Text(line.sourceText)
                        .font(.system(size: fontSize * 0.68, weight: .regular, design: .rounded))
                        .foregroundStyle(textColor.opacity(0.6))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(textColor)
        .opacity(line.isFinal ? 1 : 0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// White text on dark tints, near-black on light ones.
    private var textColor: Color {
        let color = NSColor(Color(hex: backgroundHex)).usingColorSpace(.sRGB) ?? .black
        let luminance = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        return luminance > 0.6 && backgroundOpacity > 0.5 ? Color(white: 0.1) : .white
    }

    private var badgeColor: Color {
        switch line.channel {
        case .system: Color(red: 0.36, green: 0.55, blue: 1.0).opacity(0.85)
        case .microphone: Color(red: 0.98, green: 0.55, blue: 0.68).opacity(0.85)
        }
    }
}
