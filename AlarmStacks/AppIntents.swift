//
//  AppIntents.swift
//  AlarmStacks
//
//  Created by . . on 8/16/25.
//

import AppIntents
import SwiftData
import Foundation

struct AlarmStackEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayName: LocalizedStringResource = "Alarm Stack"
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Alarm Stack")
    }
    static var defaultQuery = AlarmStackQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(stack: Stack) {
        self.id = stack.id
        self.name = stack.name
    }
}

struct AlarmStackQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [AlarmStackEntity] {
        let container = try ModelContainer(for: Stack.self, Step.self)
        let ctx = ModelContext(container)
        let all = try ctx.fetch(FetchDescriptor<Stack>())
        return all.filter { identifiers.contains($0.id) }.map(AlarmStackEntity.init)
    }

    func suggestedEntities() async throws -> [AlarmStackEntity] {
        let container = try ModelContainer(for: Stack.self, Step.self)
        let ctx = ModelContext(container)
        let desc = FetchDescriptor<Stack>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let stacks = try ctx.fetch(desc)
        return stacks.prefix(6).map(AlarmStackEntity.init)
    }
}

struct StartStackIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Alarm Stack"
    static var description = IntentDescription("Schedule all steps in the selected stack.")

    @Parameter(title: "Stack")
    var stack: AlarmStackEntity

    init() { }
    init(stack: AlarmStackEntity) { self.stack = stack }

    func perform() async throws -> some IntentResult {
        let container = try ModelContainer(for: Stack.self, Step.self)
        let ctx = ModelContext(container)
        let all = try ctx.fetch(FetchDescriptor<Stack>())
        guard let target = all.first(where: { $0.id == stack.id }) else { return .result() }
        _ = try? await AlarmScheduler.shared.schedule(stack: target, calendar: .current)
        await LiveActivityManager.start(for: target, calendar: .current)
        return .result()
    }
}
