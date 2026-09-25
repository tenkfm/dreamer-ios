import Foundation
import Observation

/// 09 Details: emotions, recurrence, someone specific.
@MainActor
@Observable
final class DetailsViewModel {
    let transcript: String
    let clientId: String
    private(set) var emotions: Set<Emotion> = [.anxiety, .confusion]
    var recurrence: Recurrence = .sometimes
    var someoneSpecific = true

    init(transcript: String, clientId: String = UUID().uuidString.lowercased()) {
        self.transcript = transcript
        self.clientId = clientId
    }

    func isSelected(_ emotion: Emotion) -> Bool { emotions.contains(emotion) }

    func toggle(_ emotion: Emotion) {
        if emotions.contains(emotion) {
            emotions.remove(emotion)
        } else {
            emotions.insert(emotion)
        }
    }

    var draft: DreamDraft {
        DreamDraft(clientId: clientId,
                   transcript: transcript,
                   emotions: Emotion.allCases.filter(emotions.contains),
                   recurrence: recurrence,
                   someoneSpecific: someoneSpecific)
    }
}
