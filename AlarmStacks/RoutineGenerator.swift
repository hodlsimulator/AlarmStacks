//
//  RoutineGenerator.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import Foundation

struct GeneratedStack: Codable {
    var name: String
    var steps: [GeneratedStep]
}

struct GeneratedStep: Codable {
    var title: String
    var minutes: Int
}

enum RoutineGenerator {
    /// Tiny rule-based generator so the app compiles without extra frameworks.
    static func make(from prompt: String) async throws -> GeneratedStack {
        let p = prompt.lowercased()

        if p.contains("pomodoro") {
            return GeneratedStack(name: "Pomodoro x2", steps: [
                GeneratedStep(title: "Focus 25", minutes: 25),
                GeneratedStep(title: "Break 5", minutes: 5),
                GeneratedStep(title: "Focus 25", minutes: 25),
                GeneratedStep(title: "Break 5", minutes: 5)
            ])
        } else if p.contains("morning") {
            return GeneratedStack(name: "Morning — 45m", steps: [
                GeneratedStep(title: "Hydrate", minutes: 5),
                GeneratedStep(title: "Stretch", minutes: 8),
                GeneratedStep(title: "Shower", minutes: 10)
            ])
        } else {
            return GeneratedStack(name: "Quick Routine", steps: [
                GeneratedStep(title: "Start", minutes: 0),
                GeneratedStep(title: "Focus 20", minutes: 20),
                GeneratedStep(title: "Break 5", minutes: 5)
            ])
        }
    }
}

