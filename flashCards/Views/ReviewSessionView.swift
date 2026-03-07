import SwiftUI
import SwiftData
import Speech
import UIKit
import AudioToolbox
import AVFoundation

/// Shared review/learn session view used by StudySessionView, WordListView, and DebugView.
struct ReviewSessionView: View {
    var viewModel: StudySessionViewModel
    let title: String
    let backLabel: String
    let onDismiss: () -> Void
    var deckMeta: DeckMetadata?
    var autoStartHandsFree: Bool = false

    @Environment(\.modelContext) private var modelContext
    @State private var ratingFlash: RatingFlash?
    @State private var hasRevealedCard = false
    @State private var completedFirstLap = false
    @State private var cardsSeenInLap = 0
    @State private var dragOffset: CGFloat = 0
    @State private var sessionStartTime: Date = Date()
    @State private var preSessionVerge: [String: VergeCategory] = [:]
    @State private var newAlmostMastered: Int = 0
    @State private var newTipOfTongue: Int = 0
    @State private var newStillBuilding: Int = 0
    @State private var vergeSlideOffset: CGFloat = 300
    @State private var vergeSlideOpacity: Double = 0
    @State private var showMasteredCelebration = false
    @State private var isRecording = false
    @State private var isProcessing = false
    @State private var audioLevel: Float = 0
    @State private var pronunciationResult: PronunciationResult? = nil
    @State private var levelPollTimer: Timer? = nil
    @State private var pronunciationStartTime: Date? = nil
    @State private var pronunciationTimeAccumulator: Double = 0
    @State private var handsFree = HandsFreeController()
    @State private var handsFreeTimer: Timer? = nil
    @State private var showVoiceAlert = false
    @State private var voiceAlertLanguages = ""
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
        .alert("Improve Voice Quality", isPresented: $showVoiceAlert) {
            voiceAlertButtons
        } message: {
            Text(voiceAlertMessage)
        }
        .onAppear {
            hapticGenerator.prepare()
            modelContext.autosaveEnabled = false
            snapshotVergeState()
            checkVoiceQuality()
            if autoStartHandsFree {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    PronunciationManager.shared.keepSessionActive = true
                    startHandsFreeWithPermissions()
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            }
        }
        .onDisappear {
            if handsFree.isActive { handsFree.stop() }
            UIApplication.shared.isIdleTimerDisabled = false
            PronunciationManager.shared.keepSessionActive = false
            handsFreeTimer?.invalidate()
            viewModel.flushPendingRecords(context: modelContext)
            try? modelContext.save()
            modelContext.autosaveEnabled = true
        }
        .onChange(of: viewModel.isSessionComplete) { _, complete in
            guard complete, viewModel.mode == .review else { return }
            // When session ends via "Done" button (not last card answered),
            // Phase 2 won't run, so we flush here and trigger verge computation.
            // We use asyncAfter to yield to Phase 2 first if it was enqueued.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if !viewModel.sessionRecordsFlushed {
                    viewModel.flushPendingRecords(context: modelContext)
                    try? modelContext.save()
                    viewModel.sessionRecordsFlushed = true
                }
            }
        }
        .onChange(of: viewModel.sessionRecordsFlushed) { _, flushed in
            guard flushed, viewModel.mode == .review else { return }
            Task { await computeVergeSummary() }
        }
        .onChange(of: newAlmostMastered + newTipOfTongue + newStillBuilding + viewModel.masteredCount) { _, total in
            guard total > 0 else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                vergeSlideOffset = 0
                vergeSlideOpacity = 1
            }
        }
        .onChange(of: viewModel.masteredCount) { old, new in
            guard new > old else { return }
            showMasteredCelebration = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showMasteredCelebration = false
            }
        }
        .onChange(of: viewModel.isFlipped) { _, _ in
            guard !handsFree.isActive else { return }
            if SpeechRecognitionManager.shared.isRecording {
                SpeechRecognitionManager.shared.stopRecording()
                isRecording = false
                isProcessing = false
                stopLevelPolling()
            }
        }
        .overlay {
            if showMasteredCelebration {
                MasteredCelebrationView()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .navigationTitle(title)
        .toolbar {
            if !viewModel.sessionCards.isEmpty && !viewModel.isSessionComplete {
                ToolbarItem(placement: .principal) {
                    Text(viewModel.sessionProgress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if viewModel.mode == .review {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if handsFree.isActive {
                                handsFree.stop()
                                handsFreeTimer?.invalidate()
                                handsFreeTimer = nil
                                UIApplication.shared.isIdleTimerDisabled = false
                                PronunciationManager.shared.keepSessionActive = false
                            } else {
                                PronunciationManager.shared.keepSessionActive = true
                                startHandsFreeWithPermissions()
                                UIApplication.shared.isIdleTimerDisabled = true
                            }
                        } label: {
                            Label("Audio Review", systemImage: handsFree.isActive ? "waveform.circle.fill" : "waveform.circle")
                                .font(.subheadline.bold())
                                .foregroundStyle(handsFree.isActive ? .green : .blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(handsFree.isActive ? Color.green.opacity(0.15) : Color.blue.opacity(0.1))
                                )
                        }
                    }
                }
            }
        }
        .onChange(of: handsFree.state) { _, newState in
            guard handsFree.isActive, let card = viewModel.currentCard else { return }
            handleHandsFreeState(newState, card: card)
        }
        .onChange(of: viewModel.isSessionComplete) { _, complete in
            if complete && handsFree.isActive {
                handsFree.stop()
                handsFreeTimer?.invalidate()
                handsFreeTimer = nil
                UIApplication.shared.isIdleTimerDisabled = false
                PronunciationManager.shared.keepSessionActive = false
            }
        }
    }

    @ViewBuilder
    private var voiceAlertButtons: some View {
        Button("Open Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        Button("Not Now", role: .cancel) {}
    }

    private var voiceAlertMessage: String {
        "You can download enhanced \(voiceAlertLanguages) voices for much more natural pronunciation.\n\nSettings > Accessibility > Spoken Content > Voices"
    }

    // MARK: - Card View

    @ViewBuilder
    private func cardView(card: FlashCard) -> some View {
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
                onMicTap: handsFree.isActive ? nil : { handleMicTap(card: card) },
                isRecording: isRecording,
                isProcessing: isProcessing,
                audioLevel: audioLevel,
                pronunciationResult: pronunciationResult,
                disableFlip: handsFree.isActive,
                isFlipped: Binding(
                    get: { viewModel.isFlipped },
                    set: {
                        viewModel.isFlipped = $0
                        if $0 {
                            hasRevealedCard = true
                            if viewModel.flipResponseTime == nil {
                                let rawTime = Date().timeIntervalSince(viewModel.cardShownAt)
                                viewModel.flipResponseTime = max(0, rawTime - pronunciationTimeAccumulator)
                            }
                            viewModel.introduceOnFlipIfNeeded(context: modelContext)
                        }
                    }
                )
            )
            .id(card.wordId)
            .frame(height: 300)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .fill(swipeOverlayColor)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            )
            .overlay {
                if handsFree.isActive {
                    handsFreeOverlay
                        .allowsHitTesting(false)
                }
            }
            .offset(x: dragOffset)
            .rotationEffect(.degrees(Double(dragOffset) / 20), anchor: .bottom)
            .gesture(reviewDragGesture)
            .padding(.horizontal)
            .padding(.top, 16)

            Spacer()

            if viewModel.mode == .learn {
                learnButtons
            } else if handsFree.isActive {
                handsFreeBottomBar
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                ratingFlash = nil
                hasRevealedCard = false
                dragOffset = 0
                isRecording = false
                isProcessing = false
                self.stopLevelPolling()
                pronunciationResult = nil
                pronunciationStartTime = nil
                pronunciationTimeAccumulator = 0
                viewModel.submitRating(quality, recallModality: "visual", context: modelContext)
            }
        }
    }

    // MARK: - Pronunciation

    private func handleMicTap(card: FlashCard) {
        let manager = SpeechRecognitionManager.shared

        if manager.isRecording {
            manager.stopRecording()
            isRecording = false
            return
        }

        guard manager.hasPermissions else {
            manager.requestPermissions { granted in
                if granted {
                    beginRecording(card: card)
                }
            }
            return
        }

        beginRecording(card: card)
    }

    private func beginRecording(card: FlashCard) {
        AudioServicesPlayAlertSound(1113)
        withAnimation { pronunciationResult = nil }
        isRecording = true
        isProcessing = false
        pronunciationStartTime = Date()

        // Delay recording start so beep plays at full volume before audio session switches
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.startLevelPolling()

            SpeechRecognitionManager.shared.startRecording(
                expectedText: card.targetText,
                article: card.article
            ) { result in
                self.stopLevelPolling()
                self.isRecording = false
                self.isProcessing = false
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    self.pronunciationResult = result
                }

                // Auto-play correct pronunciation if not excellent
                if result.score < .excellent {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let speechText: String
                        if let article = card.article, !article.isEmpty {
                            speechText = "\(article) \(card.targetText)"
                        } else {
                            speechText = card.targetText
                        }
                        PronunciationManager.shared.speak(speechText, languageCode: "es")
                    }
                } else {
                    // Excellent — no TTS will follow, so deactivate the ducking session
                    // to prevent it from ducking subsequent TTS playback
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    }
                }

                // Clear result after 4 seconds, accumulate pronunciation time
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    withAnimation { self.pronunciationResult = nil }
                    if let start = self.pronunciationStartTime {
                        self.pronunciationTimeAccumulator += Date().timeIntervalSince(start)
                        self.pronunciationStartTime = nil
                    }
                }
            }
        }
    }

    private func startLevelPolling() {
        levelPollTimer?.invalidate()
        levelPollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            let manager = SpeechRecognitionManager.shared
            audioLevel = manager.audioLevel
            if manager.isProcessing && !isProcessing {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isRecording = false
                    isProcessing = true
                }
            }
        }
    }

    private func stopLevelPolling() {
        levelPollTimer?.invalidate()
        levelPollTimer = nil
        audioLevel = 0
    }

    // MARK: - Voice Quality Check

    private static let voiceAlertDismissedKey = "voiceQualityAlertDismissed"

    private func checkVoiceQuality() {
        guard !UserDefaults.standard.bool(forKey: Self.voiceAlertDismissedKey) else { return }
        let langs = PronunciationManager.shared.languagesWithDefaultOnlyVoices(["en", "es"])
        guard !langs.isEmpty else { return }
        let names = langs.map { $0 == "en" ? "English" : "Spanish" }
        voiceAlertLanguages = names.joined(separator: " and ")
        UserDefaults.standard.set(true, forKey: Self.voiceAlertDismissedKey)
        // Slight delay so it doesn't compete with the session appearing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showVoiceAlert = true
        }
    }

    // MARK: - Audio Review Mode

    private func startHandsFreeWithPermissions() {
        let manager = SpeechRecognitionManager.shared
        guard manager.hasPermissions else {
            manager.requestPermissions { granted in
                if granted {
                    // Also need SFSpeech authorization for hands-free
                    if SFSpeechRecognizer.authorizationStatus() == .authorized {
                        handsFree.start()
                    } else {
                        SFSpeechRecognizer.requestAuthorization { status in
                            DispatchQueue.main.async {
                                if status == .authorized { handsFree.start() }
                            }
                        }
                    }
                }
            }
            return
        }
        // Also check SFSpeech auth since hands-free always uses SFSpeech
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    if status == .authorized { handsFree.start() }
                }
            }
            return
        }
        handsFree.start()
    }

    private func handleHandsFreeState(_ state: HandsFreeState, card: FlashCard) {
        handsFreeTimer?.invalidate()
        handsFreeTimer = nil

        switch state {
        case .idle:
            break

        case .speakingPrompt:
            // Determine prompt text and language based on card direction
            let showTargetFirst = viewModel.effectiveShowTargetFirst
            let promptText: String
            let promptLang: String

            if showTargetFirst {
                // Spanish shown first — speak the Spanish word
                if let article = card.article, !article.isEmpty {
                    promptText = "\(article) \(card.targetText)"
                } else {
                    promptText = card.targetText
                }
                promptLang = deckMeta?.targetLanguageCode ?? "es"
            } else {
                // English shown first — speak the English word
                promptText = card.displaySourceText
                promptLang = deckMeta?.sourceLanguageCode ?? "en"
            }

            PronunciationManager.shared.speak(promptText, languageCode: promptLang) {
                guard self.handsFree.isActive else { return }
                self.handsFree.state = .thinkPause
            }

        case .thinkPause:
            handsFreeTimer = Timer.scheduledTimer(withTimeInterval: handsFree.thinkPauseDuration, repeats: false) { _ in
                guard self.handsFree.isActive else { return }
                // Play beep while still in .playback mode, then delay before recording starts
                AudioServicesPlayAlertSound(1113)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    guard self.handsFree.isActive else { return }
                    self.handsFree.state = .listening
                }
            }

        case .listening:
            // Determine expected answer and locale
            let showTargetFirst = viewModel.effectiveShowTargetFirst
            let expectedAnswer: String
            let listenLang: String

            if showTargetFirst {
                // Spanish shown, user says English
                expectedAnswer = card.displaySourceText
                listenLang = "en-US"
            } else {
                // English shown, user says Spanish — require article if present
                if let article = card.article, !article.isEmpty {
                    expectedAnswer = "\(article) \(card.targetText)"
                } else {
                    expectedAnswer = card.targetText
                }
                listenLang = "es-ES"
            }

            startLevelPolling()
            SpeechRecognitionManager.shared.startHandsFreeRecording(
                expectedAnswer: expectedAnswer,
                languageCode: listenLang
            ) { result in
                self.stopLevelPolling()
                guard self.handsFree.isActive else { return }
                self.handsFree.recognizedText = result.recognizedText
                self.handsFree.state = .showingResult(correct: result.isMatch)
            }

        case .showingResult(let correct):
            // Flip to reveal answer
            if !viewModel.isFlipped {
                withAnimation(.easeInOut(duration: 0.4)) {
                    viewModel.isFlipped = true
                    hasRevealedCard = true
                }
                viewModel.flipResponseTime = handsFree.thinkPauseDuration
            }

            if correct {
                // Delay so audio session has switched back from recording mode
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    AudioServicesPlaySystemSound(1407)
                }
            }

            // If wrong, speak the correct answer
            if !correct {
                let showTargetFirst = viewModel.effectiveShowTargetFirst
                let correctText: String
                let correctLang: String

                if showTargetFirst {
                    correctText = card.displaySourceText
                    correctLang = deckMeta?.sourceLanguageCode ?? "en"
                } else {
                    if let article = card.article, !article.isEmpty {
                        correctText = "\(article) \(card.targetText)"
                    } else {
                        correctText = card.targetText
                    }
                    correctLang = deckMeta?.targetLanguageCode ?? "es"
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    PronunciationManager.shared.speak(correctText, languageCode: correctLang)
                }
            }

            // Auto-advance after result display
            let isLastCard = correct && viewModel.sessionCards.count == 1
            let lastCardDelay: TimeInterval = isLastCard ? 1.5 : handsFree.resultDisplayDuration

            handsFreeTimer = Timer.scheduledTimer(withTimeInterval: lastCardDelay, repeats: false) { _ in
                guard self.handsFree.isActive else { return }

                // Stop any TTS still playing without deactivating the audio session
                PronunciationManager.shared.cancelSpeaking()

                if isLastCard {
                    // Last card — skip flip-back/settle animations, go straight to completion
                    self.viewModel.submitRating(correct ? 4 : 1, recallModality: "spoken", context: self.modelContext)
                    self.hasRevealedCard = false
                    self.dragOffset = 0
                    self.handsFree.stop()
                    return
                }

                // Step 1: Animate the flip back
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.viewModel.isFlipped = false
                }
                // Step 2: After flip-back, submit rating (swaps card) with a crossfade
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard self.handsFree.isActive else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.viewModel.submitRating(correct ? 4 : 1, recallModality: "spoken", context: self.modelContext)
                        self.hasRevealedCard = false
                        self.dragOffset = 0
                    }
                    // Step 3: Let the new card settle before advancing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        guard self.handsFree.isActive else { return }
                        self.handsFree.state = .advancing
                    }
                }
            }

        case .advancing:
            if viewModel.isSessionComplete {
                handsFree.stop()
            } else {
                handsFree.beginNextCard()
            }
        }
    }

    @ViewBuilder
    private var handsFreeOverlay: some View {
        VStack {
            Spacer()
            switch handsFree.state {
            case .speakingPrompt:
                Label("Listen...", systemImage: "speaker.wave.2.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)
                    .transition(.opacity)

            case .thinkPause:
                Text("Think...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse)
                    .transition(.opacity)

            case .listening:
                VStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse)
                    AudioLevelBars(level: audioLevel)
                        .frame(height: 24)
                    Text("Say the answer...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)

            case .showingResult(let correct):
                VStack(spacing: 6) {
                    Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(correct ? .green : .red)
                    if !handsFree.recognizedText.isEmpty {
                        Text("Heard: \"\(handsFree.recognizedText)\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.scale.combined(with: .opacity))

            default:
                EmptyView()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial.opacity(handsFree.state == .idle || handsFree.state == .advancing ? 0 : 0.8))
        )
        .animation(.easeInOut(duration: 0.3), value: handsFree.state)
    }

    private var handsFreeBottomBar: some View {
        VStack(spacing: 12) {
            Text("Audio Review")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                handsFree.stop()
                handsFreeTimer?.invalidate()
                handsFreeTimer = nil
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .padding(.horizontal)
        }
    }

    // MARK: - Swipe Gesture

    private var swipeOverlayColor: Color {
        if dragOffset > 0 {
            return Color.green.opacity(Double(min(abs(dragOffset), 100)) / 400)
        } else if dragOffset < 0 {
            return Color.red.opacity(Double(min(abs(dragOffset), 100)) / 400)
        }
        if ratingFlash == .correct { return Color.green.opacity(0.25) }
        if ratingFlash == .incorrect { return Color.red.opacity(0.25) }
        return .clear
    }

    private var reviewDragGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                guard viewModel.mode == .review && hasRevealedCard && !handsFree.isActive else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard viewModel.mode == .review && hasRevealedCard && !handsFree.isActive else {
                    withAnimation(.spring(response: 0.3)) { dragOffset = 0 }
                    return
                }
                let threshold: CGFloat = 100
                if value.translation.width > threshold {
                    // Swipe right → correct
                    withAnimation(.easeOut(duration: 0.15)) { dragOffset = 400 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        submitWithFeedback(quality: 4)
                    }
                } else if value.translation.width < -threshold {
                    // Swipe left → incorrect
                    withAnimation(.easeOut(duration: 0.15)) { dragOffset = -400 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        submitWithFeedback(quality: 1)
                    }
                } else {
                    // Snap back
                    withAnimation(.spring(response: 0.3)) { dragOffset = 0 }
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
            onDismiss: onDismiss,
            masteredCount: viewModel.masteredCount,
            almostMasteredCount: newAlmostMastered,
            tipOfTongueCount: newTipOfTongue,
            stillBuildingCount: newStillBuilding,
            vergeOffset: vergeSlideOffset,
            vergeOpacity: vergeSlideOpacity
        )
    }

    private func snapshotVergeState() {
        guard viewModel.mode == .review else { return }
        sessionStartTime = Date()
        let container = modelContext.container
        Task {
            let results = await VergeAnalyzer.analyzeInBackground(container: container)
            preSessionVerge = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0.category) })
            print("[VERGE] PRE-snapshot: \(results.count) verge words")
        }
    }

    private func computeVergeSummary() async {
        guard viewModel.mode == .review else { return }

        let container = modelContext.container
        let boundary = sessionStartTime
        let preSnapshot = preSessionVerge

        let results = await VergeAnalyzer.analyzeInBackground(
            container: container,
            forcedSessionBoundary: boundary
        )
        print("[VERGE] Post-analysis: \(results.count) verge words (pre had \(preSnapshot.count))")

        var newAlmost = 0, newTip = 0, newBuilding = 0
        let postIds = Set(results.map(\.id))

        for word in results {
            let previous = preSnapshot[word.id]
            let changed = previous == nil || previous != word.category
            if changed {
                print("[VERGE]   CHANGED \(word.id): \(previous.map { "\($0)" } ?? "new") → \(word.category)")
                switch word.category {
                case .almostMastered: newAlmost += 1
                case .tipOfTongue: newTip += 1
                case .stillBuilding: newBuilding += 1
                }
            }
        }

        for (id, previous) in preSnapshot where !postIds.contains(id) {
            print("[VERGE]   GRADUATED \(id): was \(previous), no longer on verge")
            newAlmost += 1
        }

        print("[VERGE] Result: \(newAlmost) new almostMastered, \(newTip) new tipOfTongue, \(newBuilding) new stillBuilding")
        newAlmostMastered = newAlmost
        newTipOfTongue = newTip
        newStillBuilding = newBuilding
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

// MARK: - Mastered Celebration

private struct MasteredCelebrationView: View {
    @State private var particles: [CelebrationParticle] = []
    @State private var bannerScale: CGFloat = 0.3
    @State private var bannerOpacity: Double = 0

    var body: some View {
        ZStack {
            // Particles
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .position(particle.position)
                    .opacity(particle.opacity)
            }

            // Banner
            VStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.title)
                    .foregroundStyle(.yellow)
                Text("Mastered!")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            .background(Color.yellow.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .yellow.opacity(0.4), radius: 12)
            .scaleEffect(bannerScale)
            .opacity(bannerOpacity)
        }
        .onAppear {
            spawnParticles()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                bannerScale = 1.0
                bannerOpacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: 2.0)) {
                    bannerOpacity = 0
                }
            }
        }
    }

    private func spawnParticles() {
        let colors: [Color] = [.yellow, .orange, .green, .blue, .purple, .red]
        let center = CGPoint(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY)

        // Create all particles at center with zero opacity (invisible)
        var initial: [CelebrationParticle] = []
        for i in 0..<30 {
            initial.append(CelebrationParticle(
                id: i,
                color: colors.randomElement()!,
                size: CGFloat.random(in: 4...10),
                position: center,
                opacity: 0
            ))
        }
        particles = initial

        // Animate them outward on the next frame
        DispatchQueue.main.async {
            for i in 0..<particles.count {
                let angle = Double.random(in: 0...(2 * .pi))
                let speed = Double.random(in: 80...200)
                let dx = CGFloat(cos(angle) * speed)
                let dy = CGFloat(sin(angle) * speed)
                let duration = Double.random(in: 0.8...1.5)

                withAnimation(.easeOut(duration: duration)) {
                    particles[i].position = CGPoint(x: center.x + dx, y: center.y + dy)
                    particles[i].opacity = 1.0
                }
                // Fade out after burst
                withAnimation(.easeOut(duration: duration).delay(duration * 0.5)) {
                    particles[i].opacity = 0
                }
            }
        }
    }
}

private struct CelebrationParticle: Identifiable {
    let id: Int
    let color: Color
    let size: CGFloat
    var position: CGPoint
    var opacity: Double
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
    var masteredCount: Int = 0
    var almostMasteredCount: Int = 0
    var tipOfTongueCount: Int = 0
    var stillBuildingCount: Int = 0
    var vergeOffset: CGFloat = 300
    var vergeOpacity: Double = 0

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
            .frame(maxWidth: 320)
            .background(RoundedRectangle(cornerRadius: 12).fill(.background).shadow(radius: 2))
            .opacity(statsOpacity)
            .accessibilityElement(children: .combine)

            vergeSummary
                .offset(x: vergeOffset)
                .opacity(vergeOpacity)

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

    private var hasVergeWords: Bool {
        masteredCount + almostMasteredCount + tipOfTongueCount + stillBuildingCount > 0
    }

    private var vergeSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame")
                .foregroundStyle(.orange)
                .font(.caption)

            VStack(alignment: .leading, spacing: 3) {
                if masteredCount > 0 {
                    vergeRow(color: .yellow, label: "Mastered", count: masteredCount)
                }
                if almostMasteredCount > 0 {
                    vergeRow(color: .green, label: "Almost mastered", count: almostMasteredCount)
                }
                if tipOfTongueCount > 0 {
                    vergeRow(color: .orange, label: "Tip of tongue", count: tipOfTongueCount)
                }
                if stillBuildingCount > 0 {
                    vergeRow(color: .blue, label: "Still building", count: stillBuildingCount)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 320, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background).shadow(radius: 1))
    }

    private func vergeRow(color: Color, label: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count) new \(label.lowercased())")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            let dist: CGFloat = CGFloat.random(in: 35...75)
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
