import SwiftUI
import SwiftData
import UIKit

/// Shared review/learn session view used by StudySessionView, WordListView, and DebugView.
struct ReviewSessionView: View {
    var viewModel: StudySessionViewModel
    let title: String
    let backLabel: String
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var decks: [DeckMetadata]
    @State private var ratingFlash: RatingFlash?
    @State private var hasRevealedCard = false
    @State private var completedFirstLap = false
    @State private var cardsSeenInLap = 0
    private let hapticGenerator = UINotificationFeedbackGenerator()

    var body: some View {
        Group {
            if viewModel.isSessionComplete {
                sessionCompleteView
            } else if let card = viewModel.currentCard {
                cardView(card: card)
            } else {
                emptyStateView
            }
        }
        .onAppear { hapticGenerator.prepare() }
        .navigationTitle(title)
        .toolbar {
            if !viewModel.sessionCards.isEmpty && !viewModel.isSessionComplete {
                ToolbarItem(placement: .principal) {
                    Text(viewModel.sessionProgress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Card View

    @ViewBuilder
    private func cardView(card: FlashCard) -> some View {
        let deckMeta = decks.first
        VStack(spacing: 0) {
            FlashCardView(
                sourceText: card.displaySourceText,
                targetText: card.targetText,
                sourceLanguage: deckMeta?.sourceLanguage ?? "English",
                targetLanguage: deckMeta?.targetLanguage ?? "Spanish",
                status: card.status,
                article: card.article,
                partOfSpeech: card.partOfSpeech,
                showTargetFirst: viewModel.effectiveShowTargetFirst,
                sourceLanguageCode: deckMeta?.sourceLanguageCode ?? "en",
                targetLanguageCode: deckMeta?.targetLanguageCode ?? "es",
                examples: card.examples,
                isFlipped: Binding(
                    get: { viewModel.isFlipped },
                    set: {
                        viewModel.isFlipped = $0
                        if $0 { hasRevealedCard = true }
                    }
                )
            )
            .id(card.wordId)
            .transition(.identity)
            .frame(height: 300)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .fill(ratingFlash == .correct ? Color.green.opacity(0.25) : ratingFlash == .incorrect ? Color.red.opacity(0.25) : Color.clear)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            )
            .padding(.horizontal)
            .padding(.top, 16)

            Spacer()

            if viewModel.mode == .learn {
                learnButtons
            } else {
                VStack(spacing: 12) {
                    reviewButtons
                        .opacity(hasRevealedCard ? 1 : 0)
                        .allowsHitTesting(hasRevealedCard)

                    Button {
                        viewModel.isSessionComplete = true
                    } label: {
                        Label("Done", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .padding(.horizontal)
                }
            }
        }
        .padding()
    }

    // MARK: - Learn Mode Buttons

    private var learnButtons: some View {
        VStack(spacing: 12) {
            if completedFirstLap || hasRevealedCard {
                Button {
                    cardsSeenInLap += 1
                    if cardsSeenInLap >= viewModel.totalSessionCards {
                        completedFirstLap = true
                    }
                    if !completedFirstLap {
                        hasRevealedCard = false
                    }
                    viewModel.advanceToNextCard(context: modelContext)
                } label: {
                    Label("Next", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .padding(.horizontal)
            }

            Button {
                viewModel.endLearnSession(context: modelContext)
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .padding(.horizontal)
        }
    }

    // MARK: - Review Mode Buttons

    private var reviewButtons: some View {
        HStack(spacing: 16) {
            Button {
                submitWithFeedback(quality: 1)
            } label: {
                Label("Nope", systemImage: "xmark.circle.fill")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(GlowButtonStyle(baseColor: .red))
            .accessibilityLabel("Incorrect, I didn't know this word")

            Button {
                submitWithFeedback(quality: 4)
            } label: {
                Label("Got it", systemImage: "checkmark.circle.fill")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(GlowButtonStyle(baseColor: .green))
            .accessibilityLabel("Correct, I knew this word")
        }
        .padding(.horizontal)
    }

    private func submitWithFeedback(quality: Int) {
        let correct = quality >= 3
        hapticGenerator.notificationOccurred(correct ? .success : .error)
        hapticGenerator.prepare()
        ratingFlash = correct ? .correct : .incorrect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                ratingFlash = nil
                hasRevealedCard = false
                viewModel.submitRating(quality, context: modelContext)
            }
        }
    }

    // MARK: - Session Complete

    private var sessionCompleteView: some View {
        SessionCompleteContent(
            mode: viewModel.mode,
            wordsLearned: viewModel.wordsLearned,
            totalReviewed: viewModel.totalReviewed,
            correctCount: viewModel.correctCount,
            accuracy: viewModel.accuracy,
            backLabel: backLabel,
            onDismiss: onDismiss
        )
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No cards available")
                .font(.title2)
            Text("Check back later.")
                .foregroundStyle(.secondary)

            Button("Back") { onDismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top)
        }
        .padding()
    }
}

// MARK: - Rating Flash

enum RatingFlash {
    case correct, incorrect
}

// MARK: - Session Complete (animated)

private struct SessionCompleteContent: View {
    let mode: StudyMode
    let wordsLearned: Int
    let totalReviewed: Int
    let correctCount: Int
    let accuracy: Double
    let backLabel: String
    let onDismiss: () -> Void

    @State private var boltScale: CGFloat = 0.3
    @State private var boltOpacity: Double = 0
    @State private var boltRotation: Double = -20
    @State private var glowOpacity: Double = 0
    @State private var glowScale: CGFloat = 0.5
    @State private var sparkles: [(offset: CGSize, opacity: Double)] = Array(
        repeating: (.zero, 0), count: 6
    )
    @State private var textOpacity: Double = 0
    @State private var statsOpacity: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // Radial glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.yellow.opacity(0.3),
                                Color.orange.opacity(0.1),
                                .clear
                            ],
                            center: .center,
                            startRadius: 5,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                    .scaleEffect(glowScale)
                    .opacity(glowOpacity)

                // Sparkles
                ForEach(0..<6, id: \.self) { i in
                    Circle()
                        .fill(i % 2 == 0 ? Color.yellow : Color.orange)
                        .frame(width: i % 3 == 0 ? 6 : 4, height: i % 3 == 0 ? 6 : 4)
                        .offset(sparkles[i].offset)
                        .opacity(sparkles[i].opacity)
                }

                // Bolt
                BoltShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.95, blue: 0.7),
                                Color(red: 1.0, green: 0.8, blue: 0.2),
                                Color(red: 0.95, green: 0.65, blue: 0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 50, height: 70)
                    .shadow(color: .yellow.opacity(0.4), radius: 8, y: 2)
                    .scaleEffect(boltScale)
                    .rotationEffect(.degrees(boltRotation))
                    .opacity(boltOpacity)
            }
            .frame(height: 140)
            .accessibilityHidden(true)

            Text(mode == .learn ? "Words Learned!" : "Review Complete!")
                .font(.title.bold())
                .opacity(textOpacity)

            VStack(spacing: 8) {
                if mode == .learn {
                    completionStatRow(label: "New words seen", value: "\(wordsLearned)")
                } else {
                    completionStatRow(label: "Cards reviewed", value: "\(totalReviewed)")
                    completionStatRow(label: "Correct", value: "\(correctCount)")
                    completionStatRow(label: "Accuracy", value: "\(Int(accuracy * 100))%")
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
            .opacity(statsOpacity)
            .accessibilityElement(children: .combine)

            Button(backLabel) { onDismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top)
                .opacity(statsOpacity)
        }
        .padding()
        .onAppear { animate() }
    }

    private func completionStatRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }

    private func animate() {
        // Bolt pops in with a bounce
        withAnimation(.spring(response: 0.5, dampingFraction: 0.5).delay(0.1)) {
            boltScale = 1.0
            boltOpacity = 1
            boltRotation = 0
        }

        // Glow expands
        withAnimation(.easeOut(duration: 0.6).delay(0.2)) {
            glowScale = 1.2
            glowOpacity = 1
        }
        withAnimation(.easeInOut(duration: 1.0).delay(0.8)) {
            glowScale = 1.0
            glowOpacity = 0.5
        }

        // Sparkles burst outward
        let angles: [Double] = [0, 60, 120, 180, 240, 300]
        for i in 0..<6 {
            let rad = angles[i] * .pi / 180
            let dist: CGFloat = CGFloat.random(in: 35...55)
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                sparkles[i] = (
                    offset: CGSize(width: cos(rad) * dist, height: sin(rad) * dist),
                    opacity: 1.0
                )
            }
            withAnimation(.easeIn(duration: 0.4).delay(0.7)) {
                sparkles[i].opacity = 0
            }
        }

        // Text fades in
        withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
            textOpacity = 1
        }

        // Stats slide in
        withAnimation(.easeOut(duration: 0.4).delay(0.6)) {
            statsOpacity = 1
        }
    }
}

// MARK: - Bolt Shape (shared with StartupView)

struct BoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()

        path.move(to: CGPoint(x: w * 0.55, y: 0))
        path.addLine(to: CGPoint(x: w * 0.05, y: h * 0.50))
        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.50))
        path.addLine(to: CGPoint(x: w * 0.25, y: h))
        path.addLine(to: CGPoint(x: w * 0.95, y: h * 0.42))
        path.addLine(to: CGPoint(x: w * 0.58, y: h * 0.42))
        path.closeSubpath()

        return path
    }
}
