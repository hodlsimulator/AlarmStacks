//
//  ImportExport.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import Foundation
import SwiftData

// Lightweight export format (stable, decoupled from SwiftData)
struct ExportStack: Codable {
    var id: UUID
    var name: String
    var createdAt: Date
    var themeName: String
    var steps: [ExportStep]
}

struct ExportStep: Codable {
    var id: UUID
    var title: String
    var kind: Int
    var order: Int
    var isEnabled: Bool
    var createdAt: Date
    var hour: Int?
    var minute: Int?
    var weekday: Int?
    var durationSeconds: Int?
    var offsetSeconds: Int?
    var soundName: String?
    var allowSnooze: Bool
    var snoozeMinutes: Int
}

// MARK: - Builders

func makeExport(from stack: Stack) -> ExportStack {
    ExportStack(
        id: stack.id,
        name: stack.name,
        createdAt: stack.createdAt,
        themeName: stack.themeName,
        steps: stack.sortedSteps.map { s in
            ExportStep(
                id: s.id,
                title: s.title,
                kind: s.kind.rawValue,
                order: s.order,
                isEnabled: s.isEnabled,
                createdAt: s.createdAt,
                hour: s.hour,
                minute: s.minute,
                weekday: s.weekday,
                durationSeconds: s.durationSeconds,
                offsetSeconds: s.offsetSeconds,
                soundName: s.soundName,
                allowSnooze: s.allowSnooze,
                snoozeMinutes: s.snoozeMinutes
            )
        }
    )
}

@MainActor
func importStacks(from data: Data, into context: ModelContext) throws -> [Stack] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    // Accept either a single stack or an array
    var exports: [ExportStack] = []
    if let one = try? decoder.decode(ExportStack.self, from: data) {
        exports = [one]
    } else {
        exports = try decoder.decode([ExportStack].self, from: data)
    }

    var created: [Stack] = []
    for ex in exports {
        let stack = Stack(id: UUID(), name: ex.name, createdAt: ex.createdAt, themeName: ex.themeName)
        stack.steps = ex.steps.sorted { $0.order < $1.order }.map { e in
            Step(
                id: UUID(),
                title: e.title,
                kind: StepKind(rawValue: e.kind) ?? .timer,
                order: e.order,
                isEnabled: e.isEnabled,
                createdAt: e.createdAt,
                hour: e.hour,
                minute: e.minute,
                weekday: e.weekday,
                durationSeconds: e.durationSeconds,
                offsetSeconds: e.offsetSeconds,
                soundName: e.soundName,
                allowSnooze: e.allowSnooze,
                snoozeMinutes: e.snoozeMinutes,
                stack: stack
            )
        }
        context.insert(stack)
        created.append(stack)
    }
    try context.save()
    return created
}

// File helper: writes JSON to a temp file for ShareLink
func writeExportFile(for stack: Stack) throws -> URL {
    let ex = makeExport(from: stack)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(ex)
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    let safeName = stack.name.replacingOccurrences(of: "/", with: "-")
    let url = tmp.appendingPathComponent("AlarmStack-\(safeName).json")
    try data.write(to: url, options: .atomic)
    return url
}
