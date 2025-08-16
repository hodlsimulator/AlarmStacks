//
//  AlarmStacksWidget.swift
//  AlarmStacksWidget
//
//  Created by . . on 8/16/25.
//

import WidgetKit
import SwiftUI

struct SimpleEntry: TimelineEntry { let date: Date }

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let now = Date()
        let entries = (0..<6).map { i in SimpleEntry(date: now.addingTimeInterval(Double(i) * 600)) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct AlarmStacksWidgetEntryView: View {
    var entry: Provider.Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Alarm Stacks").font(.headline)
            Text("Open to start a routine").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
        .widgetURL(URL(string: "alarmstacks://open"))
    }
}

@main
struct AlarmStacksWidget: Widget {
    let kind = "AlarmStacksWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AlarmStacksWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Alarm Stacks")
        .description("Quick access to your routines.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
