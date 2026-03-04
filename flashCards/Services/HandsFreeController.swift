import Foundation
import Observation

enum HandsFreeState: Equatable {
    case idle
    case speakingPrompt
    case thinkPause
    case listening
    case showingResult(correct: Bool)
    case advancing
}

@Observable
class HandsFreeController {
    var state: HandsFreeState = .idle
    var isActive: Bool = false
    var recognizedText: String = ""

    let thinkPauseDuration: TimeInterval = 1.5
    let resultDisplayDuration: TimeInterval = 2.5

    func start() {
        guard !isActive else { return }
        isActive = true
        state = .speakingPrompt
    }

    func stop() {
        isActive = false
        state = .idle
        recognizedText = ""
        PronunciationManager.shared.stop()
        if SpeechRecognitionManager.shared.isRecording {
            SpeechRecognitionManager.shared.stopRecording()
        }
    }

    func beginNextCard() {
        guard isActive else { return }
        recognizedText = ""
        state = .speakingPrompt
    }
}
