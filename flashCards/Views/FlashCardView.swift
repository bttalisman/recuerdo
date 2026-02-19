import SwiftUI

struct FlashCardView: View {
    let sourceText: String
    let targetText: String
    let sourceLanguage: String
    let targetLanguage: String
    let status: String
    var article: String? = nil
    var partOfSpeech: String? = nil
    var showTargetFirst: Bool = false
    var sourceLanguageCode: String = "en"
    var targetLanguageCode: String = "es"
    var examples: [ExampleSentence] = []
    @Binding var isFlipped: Bool
    @State private var showAllExamples = false

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
            cardFace(text: frontText, article: frontArticle, language: frontLanguage, languageCode: frontLanguageCode, isFront: true, isTargetLanguage: showTargetFirst)
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))

            // Back
            cardFace(text: backText, article: backArticle, language: backLanguage, languageCode: backLanguageCode, isFront: false, isTargetLanguage: !showTargetFirst)
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cardAccessibilityLabel)
        .accessibilityHint("Double tap to flip card")
        .accessibilityValue(isFlipped ? "showing answer" : "showing prompt")
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.4)) {
                isFlipped.toggle()
            }
        }
        .sheet(isPresented: $showAllExamples) {
            ExamplesSheet(word: showTargetFirst ? frontText : backText, examples: examples)
                .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private func cardFace(text: String, article: String?, language: String, languageCode: String, isFront: Bool, isTargetLanguage: Bool) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 2) {
                Text(language.uppercased())
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                if let partOfSpeech, !partOfSpeech.isEmpty {
                    Text(partOfSpeech)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

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

            VStack(spacing: 8) {
                if isTargetLanguage {
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
                    .accessibilityLabel("Pronounce word")

                    if let example = examples.first {
                        VStack(spacing: 2) {
                            Text(example.es)
                                .font(.subheadline)
                                .italic()
                                .minimumScaleFactor(0.7)
                            if !isFront {
                                Text(example.en)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        .multilineTextAlignment(.center)
                        .lineLimit(3)

                        if !isFront && examples.count > 1 {
                            Button {
                                showAllExamples = true
                            } label: {
                                Text("more examples")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows all example sentences")
                        }
                    }
                } else if isFront {
                    Text("Tap to reveal")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 70, alignment: .top)
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

    private var cardAccessibilityLabel: String {
        let currentText = isFlipped ? backText : frontText
        let currentLang = isFlipped ? backLanguage : frontLanguage
        let currentArticle = isFlipped ? backArticle : frontArticle
        var label = "\(currentLang). "
        if let currentArticle, !currentArticle.isEmpty {
            label += "\(currentArticle) "
        }
        label += currentText
        if let partOfSpeech, !partOfSpeech.isEmpty {
            label += ", \(partOfSpeech)"
        }
        return label
    }

    private func buildSpeechText(_ text: String, article: String?) -> String {
        if let article, !article.isEmpty {
            return "\(article) \(text)"
        }
        return text
    }
}

private struct ExamplesSheet: View {
    let word: String
    let examples: [ExampleSentence]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(examples.enumerated()), id: \.offset) { index, example in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(example.es)
                            .font(.body)
                            .italic()
                        Text(example.en)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Examples: \(word)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
