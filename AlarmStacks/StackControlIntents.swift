//
//  StackControlIntents.swift
//  AlarmStacks
//
//  Created by . . on 8/17/25.
//

import AppIntents
import SwiftData
import Foundation

struct ArmStackIntent: AppIntent {
    static var title: LocalizedStringResource = "Arm Stack"
    static var description = IntentDescription("Arm a stack and schedule all of its steps.")
    static var suggestedInvocationPhrase: String? { "Arm my morning stack" }

    @Parameter(title: "Stack")
    var stack: AlarmStackEntity

    init() { }
    init(stack: AlarmStackEntity) { self.stack = stack }

    static var parameterSummary: some ParameterSummary {
        Summary("Arm \(\.$stack)")
    }

    func perform() async throws -> some IntentResult {
        let container = try ModelContainer(for: Stack.self, Step.self)
        let ctx = ModelContext(container)
        let all = try ctx.fetch(FetchDescriptor<Stack>())
        guard let target = all.first(where: { $0.id == stack.id }) else { return .result() }
        target.isArmed = true
        try? ctx.save()
        _ = try? await AlarmScheduler.shared.schedule(stack: target, calendar: .current)
        await LiveActivityManager.start(for: target, calendar: .current)
        return .result()
    }
}

struct DisarmStackIntent: AppIntent {
    static var title: LocalizedStringResource = "Disarm Stack"
    static var description = IntentDescription("Disarm a stack and cancel its scheduled steps.")
    static var suggestedInvocationPhrase: String? { "Disarm evening stack" }

    @Parameter(title: "Stack")
    var stack: AlarmStackEntity

    init() { }
    init(stack: AlarmStackEntity) { self.stack = stack }

    static var parameterSummary: some ParameterSummary {
        Summary("Disarm \(\.$stack)")
    }

    func perform() async throws -> some IntentResult {
        let container = try ModelContainer(for: Stack.self, Step.self)
        let ctx = ModelContext(container)
        let all = try ctx.fetch(FetchDescriptor<Stack>())
        guard let target = all.first(where: { $0.id == stack.id }) else { return .result() }
        target.isArmed = false
        try? ctx.save()
        await AlarmScheduler.shared.cancelAll(for: target)
        await LiveActivityManager.end()
        return .result()
    }
}

struct CancelStackIntent: AppIntent {
    static var title: LocalizedStringResource = "Cancel Scheduled Alarms"
    static var description = IntentDescription("Cancel all scheduled notifications/alarms for a stack.")

    @Parameter(title: "Stack")
    var stack: AlarmStackEntity

    init() { }
    init(stack: AlarmStackEntity) { self.stack = stack }

    static var parameterSummary: some ParameterSummary {
        Summary("Cancel alarms for \(\.$stack)")
    }

    func perform() async throws -> some IntentResult {
        let container = try ModelContainer(for: Stack.self, Step.self)
        let ctx = ModelContext(container)
        let all = try ctx.fetch(FetchDescriptor<Stack>())
        guard let target = all.first(where: { $0.id == stack.id }) else { return .result() }
        await AlarmScheduler.shared.cancelAll(for: target)
        await LiveActivityManager.end()
        return .result()
    }
}
