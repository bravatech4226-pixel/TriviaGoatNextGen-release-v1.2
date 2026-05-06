//
//  TriviaFallbackQuestions.swift
//  TriviaGoatNextGen
//
//  Created by Michael Houlder on 2026-03-04.
//


import Foundation

enum TriviaFallbackQuestions {
    static func bank() -> [TriviaQuestion] {
        [
            TriviaQuestion(prompt: "In computing, what does 'CPU' stand for?",
                          choices: ["Central Processing Unit", "Computer Personal Unit", "Core Process Utility", "Central Program Upload"],
                          correctIndex: 0),
            TriviaQuestion(prompt: "Which planet is known as the Red Planet?",
                          choices: ["Venus", "Mars", "Jupiter", "Mercury"],
                          correctIndex: 1),
            TriviaQuestion(prompt: "What is the largest ocean on Earth?",
                          choices: ["Atlantic", "Indian", "Pacific", "Arctic"],
                          correctIndex: 2),
            TriviaQuestion(prompt: "Which language is primarily used for iOS development?",
                          choices: ["Swift", "Kotlin", "Ruby", "Go"],
                          correctIndex: 0),
            TriviaQuestion(prompt: "How many continents are there?",
                          choices: ["5", "6", "7", "8"],
                          correctIndex: 2),
            TriviaQuestion(prompt: "What does 'HTTP' stand for?",
                          choices: ["HyperText Transfer Protocol", "High Transfer Text Process", "Host Transport Transfer Package", "Hyperlink Trace Transfer Program"],
                          correctIndex: 0),
            TriviaQuestion(prompt: "Which gas do plants absorb from the atmosphere?",
                          choices: ["Oxygen", "Nitrogen", "Carbon Dioxide", "Hydrogen"],
                          correctIndex: 2),
            TriviaQuestion(prompt: "What is the capital of Japan?",
                          choices: ["Seoul", "Tokyo", "Kyoto", "Osaka"],
                          correctIndex: 1),
            TriviaQuestion(prompt: "Which element has the symbol 'O'?",
                          choices: ["Gold", "Oxygen", "Osmium", "Silver"],
                          correctIndex: 1),
            TriviaQuestion(prompt: "How many sides does a hexagon have?",
                          choices: ["5", "6", "7", "8"],
                          correctIndex: 1),
        ]
    }
}