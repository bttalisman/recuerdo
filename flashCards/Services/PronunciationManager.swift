import AVFoundation

class PronunciationManager: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = PronunciationManager()

    private let synthesizer = AVSpeechSynthesizer()
    private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]
    private var speakCompletion: (() -> Void)?

    /// When true, the audio session stays active between utterances (for audio review mode).
    var keepSessionActive = false

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // Novelty/joke voices to exclude from auto-selection
    private static let excludedVoices: Set<String> = [
        "Bahh", "Albert", "Jester", "Organ", "Cellos", "Zarvox", "Bells",
        "Trinoids", "Boing", "Whisper", "Good News", "Bad News", "Wobble",
        "Bubbles", "Superstar", "Grandma", "Grandpa", "Fred", "Kathy",
        "Junior", "Ralph"
    ]

    // Preferred locales when the language code is just "en" or "es"
    private static let preferredLocales: [String: [String]] = [
        "en": ["en-US", "en-GB"],
        "es": ["es-MX", "es-ES"]
    ]

    /// Find the best available voice for a language, preferring premium > enhanced > default.
    private func bestVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        if let cached = voiceCache[languageCode] {
            return cached
        }

        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let matching = allVoices.filter {
            $0.language.hasPrefix(languageCode) && !Self.excludedVoices.contains($0.name)
        }

        let preferred = Self.preferredLocales[languageCode] ?? []

        // Sort by: quality (premium > enhanced > default), then preferred locale, then name
        let sorted = matching.sorted { a, b in
            if a.quality.rawValue != b.quality.rawValue {
                return a.quality.rawValue > b.quality.rawValue
            }
            let aLocaleRank = preferred.firstIndex(of: a.language) ?? preferred.count
            let bLocaleRank = preferred.firstIndex(of: b.language) ?? preferred.count
            if aLocaleRank != bLocaleRank {
                return aLocaleRank < bLocaleRank
            }
            return a.name < b.name
        }

        let voice = sorted.first ?? AVSpeechSynthesisVoice(language: languageCode)
        if let voice {
            voiceCache[languageCode] = voice
        }
        return voice
    }

    func speak(_ text: String, languageCode: String, completion: (() -> Void)? = nil) {
        synthesizer.stopSpeaking(at: .immediate)
        speakCompletion = completion

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if keepSessionActive {
            // Audio review: no ducking, just ensure playback is active
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)
        } else {
            // Standalone tap: duck other apps, will deactivate in didFinish
            try? session.setCategory(.playback, mode: .default, options: .duckOthers)
            try? session.setActive(true)
        }
        #endif

        // Strip parenthetical hints like "to be (permanent)" → "to be"
        let cleaned = text.replacingOccurrences(
            of: "\\s*\\(.*?\\)",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = bestVoice(for: languageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1

        synthesizer.speak(utterance)
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    /// Returns language codes (e.g. "en", "es") that only have default-quality voices.
    func languagesWithDefaultOnlyVoices(_ languageCodes: [String]) -> [String] {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        return languageCodes.filter { code in
            let matching = allVoices.filter {
                $0.language.hasPrefix(code) && !Self.excludedVoices.contains($0.name)
            }
            return !matching.contains { $0.quality != .default }
        }
    }

    func stop() {
        speakCompletion = nil
        keepSessionActive = false
        synthesizer.stopSpeaking(at: .immediate)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Stop current speech without deactivating the audio session.
    /// Use during hands-free mode to cancel TTS mid-utterance while keeping audio alive.
    func cancelSpeaking() {
        speakCompletion = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let cb = speakCompletion
        speakCompletion = nil
        #if os(iOS)
        if !keepSessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
        DispatchQueue.main.async { cb?() }
    }
}
