import Foundation

struct TriviaQuestion: Identifiable, Codable {
    var id: UUID = UUID()
    let prompt: String
    let choices: [String]
    let correctIndex: Int

    // ✅ IMPORTANT:
    // Exclude `id` from Codable so decoding works even if the JSON does not provide an "id" field.
    // (Synthesized Decodable would otherwise expect "id" to be present and fail.)
    private enum CodingKeys: String, CodingKey {
        case prompt, choices, correctIndex
    }

    // SOLDER POINT: Standard init for hardcoded fallback questions
    init(prompt: String, choices: [String], correctIndex: Int) {
        self.prompt = prompt
        self.choices = choices
        self.correctIndex = correctIndex
    }

    // Bridge for raw dictionary parsing from API
    init?(from dict: [String: Any]) {
        guard let prompt = dict["prompt"] as? String,
              let choices = dict["choices"] as? [String],
              let correctIndex = dict["correctIndex"] as? Int else {
            return nil
        }
        self.prompt = prompt
        self.choices = choices
        self.correctIndex = correctIndex
    }

    // SOLDER POINT: Returns a version of the question with choices randomized
    func randomized() -> TriviaQuestion {
        let indexedChoices = choices.enumerated().map { $0 }
        let shuffledChoices = indexedChoices.shuffled()

        // Find where the original correct answer ended up
        let newCorrectIndex = shuffledChoices.firstIndex(where: { $0.offset == correctIndex }) ?? 0
        let newChoices = shuffledChoices.map { $0.element }

        return TriviaQuestion(prompt: prompt, choices: newChoices, correctIndex: newCorrectIndex)
    }
}

struct TriviaSession: Codable {
    var pack: [TriviaQuestion]
    var currentIndex: Int
    var score: Int
    var topic: String?

    static var idle: TriviaSession {
        TriviaSession(pack: [], currentIndex: 0, score: 0, topic: nil)
    }

    static func makeNew(from questions: [TriviaQuestion], topic: String) -> TriviaSession {
        // SOLDER POINT: Shuffle the questions AND their internal choices for maximum variety
        let randomizedPack = questions.shuffled().map { $0.randomized() }
        return TriviaSession(pack: randomizedPack, currentIndex: 0, score: 0, topic: topic)
    }

    mutating func next() {
        if currentIndex < pack.count { currentIndex += 1 }
    }
}

// MARK: - THE VAULT (Single Source of Truth)
let localFallbackVault: [TriviaQuestion] = [
    TriviaQuestion(prompt: "Which particle is considered the 'force carrier' of the electromagnetic field?", choices: ["Gluon", "Photon", "W Boson", "Graviton"], correctIndex: 1),
    TriviaQuestion(prompt: "In which year did the 'Great Fire of London' occur?", choices: ["1666", "1702", "1588", "1642"], correctIndex: 0),
    TriviaQuestion(prompt: "Which work begins with: 'Man is born free, and everywhere he is in chains'?", choices: ["The Republic", "The Social Contract", "Beyond Good and Evil", "Leviathan"], correctIndex: 1),
    TriviaQuestion(prompt: "What is the only metal that is liquid at standard temperature and pressure?", choices: ["Gallium", "Bromine", "Mercury", "Cesium"], correctIndex: 2),
    TriviaQuestion(prompt: "Which composer's 9th Symphony is known as 'From the New World'?", choices: ["Gustav Mahler", "Antonín Dvořák", "Jean Sibelius", "Pyotr Tchaikovsky"], correctIndex: 1),
    TriviaQuestion(prompt: "What is the chemical symbol for the element Tungsten?", choices: ["T", "Tu", "W", "Tg"], correctIndex: 2),
    TriviaQuestion(prompt: "Which country was the first to grant women the right to vote in 1893?", choices: ["Finland", "Norway", "New Zealand", "Australia"], correctIndex: 2),
    TriviaQuestion(prompt: "The movement of water across a semi-permeable membrane is called:", choices: ["Diffusion", "Osmosis", "Mitosis", "Active Transport"], correctIndex: 1),
    TriviaQuestion(prompt: "Who was the primary architect behind the design of St. Peter's Basilica's dome?", choices: ["Donato Bramante", "Michelangelo", "Bernini", "Raphael"], correctIndex: 1),
    TriviaQuestion(prompt: "The 'Event Horizon' is a boundary associated with which phenomenon?", choices: ["Supernova", "Quasar", "Black Hole", "Nebula"], correctIndex: 2)
]
