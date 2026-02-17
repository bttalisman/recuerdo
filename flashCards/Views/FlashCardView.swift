import SwiftUI

struct FlashCardView: View {
    let sourceText: String
    let targetText: String
    let sourceLanguage: String
    let targetLanguage: String
    let status: String
    var article: String? = nil
    var showTargetFirst: Bool = false
    var sourceLanguageCode: String = "en"
    var targetLanguageCode: String = "es"
    var examples: [ExampleSentence] = []
    @Binding var isFlipped: Bool

    // Article is displayed on whichever side shows the target language
    private var frontText: String { showTargetFirst ? targetText : sourceText }
    private var frontLanguage: String { showTargetFirst ? targetLanguage : sourceLanguage }
    private var frontArticle: String? { showTargetFirst ? article : nil }
    private var frontLanguageCode: String { showTargetFirst ? targetLanguageCode : sourceLanguageCode }
    private var backText: String { showTargetFirst ? sourceText : targetText }
    private var backLanguage: String { showTargetFirst ? sourceLanguage : targetLanguage }
    private var backArticle: String? { showTargetFirst ? nil : article }
    private var backLanguageCode: String { showTargetFirst ? sourceLanguageCode : targetLanguageCode }

    var statusColor: Color {
        switch status {
        case "new": return .blue
        case "learning": return .orange
        case "mastered": return .green
        default: return .gray
        }
    }

    var body: some View {
        ZStack {
            // Front
            cardFace(text: frontText, article: frontArticle, language: frontLanguage, languageCode: frontLanguageCode, isFront: true)
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))

            // Back
            cardFace(text: backText, article: backArticle, language: backLanguage, languageCode: backLanguageCode, isFront: false)
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.4)) {
                isFlipped.toggle()
            }
        }
    }

    @ViewBuilder
    private func cardFace(text: String, article: String?, language: String, languageCode: String, isFront: Bool) -> some View {
        VStack(spacing: 16) {
            Text(language.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                if let article, !article.isEmpty {
                    Text(article)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(text)
                    .font(.system(size: 36, weight: .bold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
            }

            if isFront {
                Text("Tap to reveal")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Button {
                    PronunciationManager.shared.speak(
                        buildSpeechText(text, article: article),
                        languageCode: languageCode
                    )
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                if let example = examples.first {
                    VStack(spacing: 2) {
                        Text(example.es)
                            .font(.subheadline)
                            .italic()
                        Text(example.en)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.background)
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(statusColor.opacity(0.4), lineWidth: 3)
        )
    }

    private func buildSpeechText(_ text: String, article: String?) -> String {
        if let article, !article.isEmpty {
            return "\(article) \(text)"
        }
        return text
    }
}
