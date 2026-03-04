import AVFoundation

class PronunciationManager: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = PronunciationManager()

    private let synthesizer = AVSpeechSynthesizer()
    private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]
    private var speakCompletion: (() -> Void)?

    private override init() {
        super.init()
        synthesizer.delegate = self
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: .duckOthers)
        #endif
    }

    /// Find the best available voice for a language, preferring premium > enhanced > default.
    private func bestVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        if let cached = voiceCache[languageCode] {
            return cached
        }

        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let matching = allVoices.filter { $0.language.hasPrefix(languageCode) }

        // Sort by quality: premium first, then enhanced, then default
        let sorted = matching.sorted { a, b in
            a.quality.rawValue > b.quality.rawValue
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

    func stop() {
        speakCompletion = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let cb = speakCompletion
        speakCompletion = nil
        DispatchQueue.main.async { cb?() }
    }
}
