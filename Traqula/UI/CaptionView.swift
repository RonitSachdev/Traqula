import SwiftUI
import MeetingRecords

/// Every caption line of the session on a soft rounded glass card. The list stays pinned to the newest
/// line, and scrolling up to re-read earlier lines is allowed.
struct CaptionView: View {
    let session: CaptionSession
    let settings: CaptionSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(session.timeline.lines) { line in
                    CaptionLineView(line: line, settings: settings)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
        .scrollIndicators(.hidden)
        .glassEffect(.regular.tint(.black.opacity(0.55)), in: .rect(cornerRadius: 24, style: .continuous))
        .padding(1)
    }
}

private struct CaptionLineView: View {
    let line: CaptionLine
    let settings: CaptionSettings

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(line.channel.displayName)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(badgeColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(line.translatedText ?? line.sourceText)
                    .font(.system(size: settings.captionFontSize, weight: .semibold, design: .rounded))
                if settings.showOriginalText, line.translatedText != nil {
                    Text(line.sourceText)
                        .font(.system(size: settings.captionFontSize * 0.68, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .opacity(line.isFinal ? 1 : 0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var badgeColor: Color {
        switch line.channel {
        case .system: Color(red: 0.36, green: 0.55, blue: 1.0).opacity(0.85)
        case .microphone: Color(red: 0.98, green: 0.55, blue: 0.68).opacity(0.85)
        }
    }
}
