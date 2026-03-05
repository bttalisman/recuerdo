import AVFoundation
import Speech
import MicrosoftCognitiveServicesSpeech

// MARK: - Data Types

enum PronunciationScore: Int, Comparable {
    case noMatch = 0
    case poor = 1
    case partial = 2
    case good = 3
    case excellent = 4

    static func < (lhs: PronunciationScore, rhs: PronunciationScore) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "mint"
        case .partial: return "yellow"
        case .poor: return "orange"
        case .noMatch: return "red"
        }
    }

    var icon: String {
        switch self {
        case .excellent: return "checkmark.circle.fill"
        case .good: return "checkmark.circle"
        case .partial: return "minus.circle.fill"
        case .poor: return "xmark.circle.fill"
        case .noMatch: return "xmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .excellent: return "Excellent!"
        case .good: return "Good"
        case .partial: return "Partial"
        case .poor: return "Try again"
        case .noMatch: return "Not recognized"
        }
    }
}

struct HandsFreeResult {
    let recognizedText: String
    let isMatch: Bool
}

struct PronunciationResult {
    let recognizedText: String
    let expectedText: String
    let score: PronunciationScore
    let normalizedScore: Double
    let accuracyScore: Double      // 0-100 from Azure, or mapped from SFSpeech confidence
    let pronunciationScore: Double // 0-100 from Azure overall, or same as accuracy for SFSpeech
    let isAzure: Bool
}

// MARK: - SpeechRecognitionManager

class SpeechRecognitionManager {
    static let shared = SpeechRecognitionManager()

    // SFSpeech recognizers
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    private let englishRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var stopTimer: Timer?

    private(set) var isRecording = false
    private(set) var isProcessing = false
    private(set) var audioLevel: Float = 0  // 0...1 normalized
    private var levelTimer: Timer?

    private init() {}

    var useAzure: Bool { AzureSpeechConfig.shared != nil }

    // MARK: - Permissions

    func requestPermissions(completion: @escaping (Bool) -> Void) {
        // Microphone permission is needed for both Azure and SFSpeech paths
        AVAudioApplication.requestRecordPermission { micGranted in
            guard micGranted else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            if AzureSpeechConfig.shared != nil {
                // Azure doesn't need SFSpeech authorization
                DispatchQueue.main.async { completion(true) }
            } else {
                // SFSpeech fallback needs speech recognition authorization
                SFSpeechRecognizer.requestAuthorization { status in
                    DispatchQueue.main.async { completion(status == .authorized) }
                }
            }
        }
    }

    var hasPermissions: Bool {
        let micGranted = AVAudioApplication.shared.recordPermission == .granted
        if AzureSpeechConfig.shared != nil {
            return micGranted
        }
        return micGranted && SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    // MARK: - Recording

    func startRecording(
        expectedText: String,
        article: String?,
        completion: @escaping (PronunciationResult) -> Void
    ) {
        if isRecording { stopRecording() }

        if PronunciationManager.shared.isSpeaking {
            PronunciationManager.shared.stop()
        }

        if let azureConfig = AzureSpeechConfig.shared {
            startAzureRecording(config: azureConfig, expectedText: expectedText, article: article, completion: completion)
        } else {
            startSFSpeechRecording(expectedText: expectedText, article: article, completion: completion)
        }
    }

    func stopRecording() {
        stopTimer?.invalidate()
        stopTimer = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        isRecording = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.recognitionTask = nil
            let duckOption: AVAudioSession.CategoryOptions = PronunciationManager.shared.keepSessionActive ? [] : .duckOthers
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: duckOption)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }

    // MARK: - Hands-Free Recording (SFSpeech only)

    func startHandsFreeRecording(
        expectedAnswer: String,
        languageCode: String,
        timeout: TimeInterval = 5.0,
        completion: @escaping (HandsFreeResult) -> Void
    ) {
        if isRecording { stopRecording() }

        if PronunciationManager.shared.isSpeaking {
            PronunciationManager.shared.stop()
        }

        let recognizer = languageCode.hasPrefix("en")
            ? englishRecognizer
            : speechRecognizer

        guard let recognizer, recognizer.isAvailable else {
            completion(HandsFreeResult(recognizedText: "", isMatch: false))
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .defaultToSpeaker)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            completion(HandsFreeResult(recognizedText: "", isMatch: false))
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        var hasCompleted = false
        var latestTranscription = ""

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result {
                latestTranscription = result.bestTranscription.formattedString

                if result.isFinal {
                    guard !hasCompleted else { return }
                    hasCompleted = true
                    self?.stopRecording()
                    let match = Self.isHandsFreeMatch(recognized: latestTranscription, expected: expectedAnswer)
                    DispatchQueue.main.async {
                        completion(HandsFreeResult(recognizedText: latestTranscription, isMatch: match))
                    }
                }
            }

            if let error, !hasCompleted {
                hasCompleted = true
                self?.stopRecording()
                let match = !latestTranscription.isEmpty && Self.isHandsFreeMatch(recognized: latestTranscription, expected: expectedAnswer)
                DispatchQueue.main.async {
                    completion(HandsFreeResult(recognizedText: latestTranscription.isEmpty ? "(error)" : latestTranscription, isMatch: match))
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            startAudioLevelMonitoring()
        } catch {
            stopRecording()
            completion(HandsFreeResult(recognizedText: "", isMatch: false))
            return
        }

        stopTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.recognitionRequest?.endAudio()
            if self.audioEngine.isRunning {
                self.audioEngine.stop()
                self.audioEngine.inputNode.removeTap(onBus: 0)
            }
            self.isRecording = false
            self.stopAudioLevelMonitoring()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard !hasCompleted else { return }
                hasCompleted = true
                self.recognitionTask?.cancel()
                self.recognitionTask = nil
                self.recognitionRequest = nil

                let match = !latestTranscription.isEmpty && Self.isHandsFreeMatch(recognized: latestTranscription, expected: expectedAnswer)
                completion(HandsFreeResult(recognizedText: latestTranscription.isEmpty ? "" : latestTranscription, isMatch: match))

                let duckOption: AVAudioSession.CategoryOptions = PronunciationManager.shared.keepSessionActive ? [] : .duckOthers
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: duckOption)
                try? AVAudioSession.sharedInstance().setActive(true)
            }
        }
    }

    private static let spanishArticles: Set<String> = ["el", "la", "los", "las", "un", "una", "unos", "unas"]

    private static func isHandsFreeMatch(recognized: String, expected: String) -> Bool {
        let normRecognized = normalize(recognized)
        // Strip leading "to " for English verb hints
        let strippedExpected = expected.hasPrefix("to ") ? String(expected.dropFirst(3)) : expected
        let normExpected = normalize(strippedExpected)

        guard !normRecognized.isEmpty, !normExpected.isEmpty else { return false }

        // Exact match
        if normRecognized == normExpected { return true }

        // Recognized contains expected (SFSpeech sometimes adds extra words)
        if normRecognized.contains(normExpected) { return true }

        // Parse out article if expected has one — require exact article match
        let expectedParts = normExpected.split(separator: " ", maxSplits: 1)
        if expectedParts.count == 2, spanishArticles.contains(String(expectedParts[0])) {
            let expectedArticle = String(expectedParts[0])
            let expectedWord = String(expectedParts[1])

            let recognizedParts = normRecognized.split(separator: " ", maxSplits: 1)
            guard recognizedParts.count == 2 else { return false }

            let recognizedArticle = String(recognizedParts[0])
            let recognizedWord = String(recognizedParts[1])

            // Article must match exactly
            guard recognizedArticle == expectedArticle else { return false }

            // Word gets fuzzy matching for recognition errors
            if recognizedWord == expectedWord { return true }
            let distance = levenshteinDistance(recognizedWord, expectedWord)
            let maxLen = max(recognizedWord.count, expectedWord.count)
            let ratio = maxLen > 0 ? Double(distance) / Double(maxLen) : 1.0
            return ratio <= 0.25
        }

        // No article — fuzzy match on the whole string
        let distance = levenshteinDistance(normRecognized, normExpected)
        let maxLen = max(normRecognized.count, normExpected.count)
        let ratio = maxLen > 0 ? Double(distance) / Double(maxLen) : 1.0
        return ratio <= 0.25
    }

    // MARK: - Azure Path

    private func startAzureRecording(
        config: AzureSpeechConfig,
        expectedText: String,
        article: String?,
        completion: @escaping (PronunciationResult) -> Void
    ) {
        isRecording = true

        // Set up audio session for recording BEFORE Azure tries to access the mic
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .defaultToSpeaker)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            isRecording = false
            completion(Self.makeErrorResult(expectedText: expectedText, message: "(audio session error)"))
            return
        }

        // Start audio level metering
        startAudioLevelMonitoring()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let speechConfig = try SPXSpeechConfiguration(subscription: config.subscriptionKey, region: config.region)
                // Short timeouts for snappy single-word pronunciation assessment
                speechConfig.setPropertyTo("1000", by: SPXPropertyId.speechServiceConnectionEndSilenceTimeoutMs)
                speechConfig.setPropertyTo("2000", by: SPXPropertyId.speechServiceConnectionInitialSilenceTimeoutMs)
                speechConfig.setPropertyTo("1000", by: SPXPropertyId.speechSegmentationSilenceTimeoutMs)

                // Reference text: just the word (without article for better single-word scoring)
                let referenceText = expectedText

                let pronConfig = try SPXPronunciationAssessmentConfiguration(
                    referenceText,
                    gradingSystem: SPXPronunciationAssessmentGradingSystem.hundredMark,
                    granularity: SPXPronunciationAssessmentGranularity.phoneme,
                    enableMiscue: false
                )

                let recognizer = try SPXSpeechRecognizer(speechConfiguration: speechConfig, language: "es-ES")
                try pronConfig.apply(to: recognizer)

                try recognizer.recognizeOnceAsync { [weak self] result in
                    defer {
                        DispatchQueue.main.async {
                            self?.isRecording = false
                            self?.isProcessing = false
                            self?.stopAudioLevelMonitoring()
                            // Restore audio session to playback so TTS plays at full volume
                            let duckOption: AVAudioSession.CategoryOptions = PronunciationManager.shared.keepSessionActive ? [] : .duckOthers
                            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: duckOption)
                            try? AVAudioSession.sharedInstance().setActive(true)
                        }
                    }
                    // Transition from recording to processing
                    DispatchQueue.main.async {
                        self?.isRecording = false
                        self?.isProcessing = true
                        self?.stopAudioLevelMonitoring()
                    }

                    // Check cancellation details
                    if result.reason == SPXResultReason.canceled {
                        _ = try! SPXCancellationDetails(fromCanceledRecognitionResult: result)
                    }

                    // Check if recognition succeeded
                    guard result.reason == SPXResultReason.recognizedSpeech else {
                        let reason: String
                        if result.reason == SPXResultReason.noMatch {
                            reason = "(no match)"
                        } else if result.reason == SPXResultReason.canceled {
                            let cancellation = try! SPXCancellationDetails(fromCanceledRecognitionResult: result)
                            reason = "(canceled: \(cancellation.errorDetails ?? "unknown"))"
                        } else {
                            reason = "(reason: \(result.reason.rawValue))"
                        }
                        let fallback = Self.makeErrorResult(expectedText: expectedText, message: reason)
                        DispatchQueue.main.async { completion(fallback) }
                        return
                    }

                    let pronResult = SPXPronunciationAssessmentResult(result)
                    let accuracy = pronResult?.accuracyScore ?? 0
                    let pronScore = pronResult?.pronunciationScore ?? 0
                    let completeness = pronResult?.completenessScore ?? 0
                    let fluency = pronResult?.fluencyScore ?? 0
                    let recognized = result.text ?? ""

                    print("[AZURE] Pronunciation scores:")
                    print("[AZURE]   Accuracy:      \(accuracy)")
                    print("[AZURE]   Pronunciation: \(pronScore)")
                    print("[AZURE]   Completeness:  \(completeness)")
                    print("[AZURE]   Fluency:       \(fluency)")
                    print("[AZURE]   Recognized:    '\(recognized)'")


                    let tier = Self.tierFromAzureAccuracy(accuracy)

                    let scored = PronunciationResult(
                        recognizedText: recognized,
                        expectedText: expectedText,
                        score: tier,
                        normalizedScore: accuracy / 100.0,
                        accuracyScore: accuracy,
                        pronunciationScore: pronScore,
                        isAzure: true
                    )
                    DispatchQueue.main.async { completion(scored) }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isRecording = false
                    self?.isProcessing = false
                    self?.stopAudioLevelMonitoring()
                    let duckOption: AVAudioSession.CategoryOptions = PronunciationManager.shared.keepSessionActive ? [] : .duckOthers
                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: duckOption)
                    try? AVAudioSession.sharedInstance().setActive(true)
                    let fallback = Self.makeErrorResult(expectedText: expectedText, message: "(Azure error: \(error.localizedDescription))")
                    completion(fallback)
                }
            }
        }
    }

    private static func reasonName(_ reason: SPXResultReason) -> String {
        switch reason {
        case .noMatch: return "NoMatch"
        case .canceled: return "Canceled"
        case .recognizingSpeech: return "RecognizingSpeech"
        case .recognizedSpeech: return "RecognizedSpeech"
        case .recognizingIntent: return "RecognizingIntent"
        case .recognizedIntent: return "RecognizedIntent"
        case .translatingSpeech: return "TranslatingSpeech"
        case .translatedSpeech: return "TranslatedSpeech"
        case .synthesizingAudio: return "SynthesizingAudio"
        case .synthesizingAudioCompleted: return "SynthesizingAudioCompleted"
        case .synthesizingAudioStarted: return "SynthesizingAudioStarted"
        default: return "Unknown(\(reason.rawValue))"
        }
    }

    static func tierFromAzureAccuracy(_ accuracy: Double) -> PronunciationScore {
        switch accuracy {
        case 93...: return .excellent
        case 80..<93: return .good
        case 50..<80: return .partial
        case 30..<50: return .poor
        default: return .noMatch
        }
    }

    private static func makeErrorResult(expectedText: String, message: String) -> PronunciationResult {
        PronunciationResult(
            recognizedText: message,
            expectedText: expectedText,
            score: .noMatch,
            normalizedScore: 0,
            accuracyScore: 0,
            pronunciationScore: 0,
            isAzure: true
        )
    }

    // MARK: - SFSpeech Fallback Path

    private func startSFSpeechRecording(
        expectedText: String,
        article: String?,
        completion: @escaping (PronunciationResult) -> Void
    ) {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            completion(Self.makeFallbackResult(recognized: "(recognizer unavailable)", expected: expectedText, confidence: 0))
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .defaultToSpeaker)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            completion(Self.makeFallbackResult(recognized: "(audio error)", expected: expectedText, confidence: 0))
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        var hasCompleted = false
        var latestTranscription = ""
        var latestConfidence: Float = 0

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result {
                latestTranscription = result.bestTranscription.formattedString
                let segments = result.bestTranscription.segments
                if !segments.isEmpty {
                    latestConfidence = segments.reduce(Float(0)) { $0 + $1.confidence } / Float(segments.count)
                }

                if result.isFinal {
                    guard !hasCompleted else { return }
                    hasCompleted = true
                    self?.stopRecording()
                    let scored = Self.scoreSFSpeech(recognized: latestTranscription, expected: expectedText, article: article, confidence: latestConfidence)
                    DispatchQueue.main.async { completion(scored) }
                }
            }

            if let error, !hasCompleted {
                hasCompleted = true
                self?.stopRecording()
                let scored = latestTranscription.isEmpty
                    ? Self.makeFallbackResult(recognized: "(error: \((error as NSError).localizedDescription))", expected: expectedText, confidence: 0)
                    : Self.scoreSFSpeech(recognized: latestTranscription, expected: expectedText, article: article, confidence: latestConfidence)
                DispatchQueue.main.async { completion(scored) }
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            stopRecording()
            completion(Self.makeFallbackResult(recognized: "(engine error)", expected: expectedText, confidence: 0))
            return
        }

        stopTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.recognitionRequest?.endAudio()
            if self.audioEngine.isRunning {
                self.audioEngine.stop()
                self.audioEngine.inputNode.removeTap(onBus: 0)
            }
            self.isRecording = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                guard !hasCompleted else { return }
                hasCompleted = true
                self.recognitionTask?.cancel()
                self.recognitionTask = nil
                self.recognitionRequest = nil

                let scored = latestTranscription.isEmpty
                    ? Self.makeFallbackResult(recognized: "(no speech detected)", expected: expectedText, confidence: 0)
                    : Self.scoreSFSpeech(recognized: latestTranscription, expected: expectedText, article: article, confidence: latestConfidence)
                completion(scored)

                let duckOption: AVAudioSession.CategoryOptions = PronunciationManager.shared.keepSessionActive ? [] : .duckOthers
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: duckOption)
                try? AVAudioSession.sharedInstance().setActive(true)
            }
        }
    }

    // MARK: - SFSpeech Scoring (fallback)

    private static func scoreSFSpeech(recognized: String, expected: String, article: String?, confidence: Float) -> PronunciationResult {
        let normalizedRecognized = normalize(recognized)
        let normalizedExpected = normalize(expected)

        let expectedWithArticle: String? = {
            guard let article, !article.isEmpty else { return nil }
            return normalize("\(article) \(expected)")
        }()

        let isExactMatch = normalizedRecognized == normalizedExpected
            || (expectedWithArticle != nil && normalizedRecognized == expectedWithArticle)
        let containsExpected = !isExactMatch && normalizedRecognized.contains(normalizedExpected)

        let distance = levenshteinDistance(normalizedRecognized, normalizedExpected)
        let maxLen = max(normalizedRecognized.count, normalizedExpected.count)
        let ratio = maxLen > 0 ? Double(distance) / Double(maxLen) : 1.0

        let tier: PronunciationScore
        if isExactMatch {
            tier = confidence >= 0.8 ? .excellent : confidence >= 0.5 ? .good : .partial
        } else if containsExpected {
            tier = confidence >= 0.5 ? .good : .partial
        } else if ratio <= 0.3 {
            tier = .partial
        } else if ratio <= 0.6 {
            tier = .poor
        } else {
            tier = .noMatch
        }

        // Map SFSpeech confidence to 0-100 scale for consistent display
        let mappedAccuracy = Double(confidence) * 100.0

        return PronunciationResult(
            recognizedText: recognized,
            expectedText: expected,
            score: tier,
            normalizedScore: Double(confidence),
            accuracyScore: mappedAccuracy,
            pronunciationScore: mappedAccuracy,
            isAzure: false
        )
    }

    private static func makeFallbackResult(recognized: String, expected: String, confidence: Float) -> PronunciationResult {
        PronunciationResult(
            recognizedText: recognized,
            expectedText: expected,
            score: .noMatch,
            normalizedScore: 0,
            accuracyScore: Double(confidence) * 100,
            pronunciationScore: 0,
            isAzure: false
        )
    }

    // MARK: - Audio Level Monitoring

    private func startAudioLevelMonitoring() {
        // Enable metering on the audio session's input
        _ = AVAudioSession.sharedInstance()
        // Use AVAudioEngine's input node to read power levels
        // We'll use a simple AVAudioRecorder for metering since Azure manages the actual mic
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, self.isRecording else { return }
            // Read input node power level via audio engine tap
            let inputNode = self.audioEngine.inputNode
            // If the engine isn't running (Azure path), estimate from audio session
            if !self.audioEngine.isRunning {
                // Simple pulse simulation based on recording state
                // Azure manages its own audio; we animate based on time
                let t = Date().timeIntervalSince1970
                let simulated = Float(0.3 + 0.4 * abs(sin(t * 4)))
                DispatchQueue.main.async { self.audioLevel = simulated }
            } else {
                // SFSpeech path — read from input node
                let level = inputNode.outputFormat(forBus: 0).channelCount > 0 ? Float(0.5) : Float(0.1)
                DispatchQueue.main.async { self.audioLevel = level }
            }
        }
    }

    private func stopAudioLevelMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioLevel = 0
    }

    // MARK: - Helpers

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func levenshteinDistance(_ s: String, _ t: String) -> Int {
        let sArray = Array(s)
        let tArray = Array(t)
        let m = sArray.count
        let n = tArray.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = sArray[i - 1] == tArray[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            prev = curr
        }

        return prev[n]
    }
}
