# Alarm Stacks — Routine Alarm Clock

A beautiful, system-level alarm & routine builder for **iOS 26**. Compose “stacks” like **Wake → Hydrate → Stretch → Shower → Leave**, where each step is a real **AlarmKit** alarm or timer with system alerts that cut through Silent/Focus, Live Activity countdowns, and Lock Screen/Dynamic Island controls. Optional on-device “generate my routine” uses Apple’s Foundation Models — no servers, no user data leaving the device.

App Intents + Visual Intelligence make your stacks discoverable from visual search and “what’s on my screen”. The entire UI embraces **Liquid Glass**.

---

## Why this wins now
- **AlarmKit in iOS 26** — schedule one-shot or repeating alarms and countdown timers with system-level alerts, Live Activities, and Dynamic Island. Previously not possible without special entitlements.
- **Liquid Glass** is the headline design this cycle; day-one apps are strong editorial candidates.
- **On-device Foundation Models** enable guided generation and tool-calling — perfect for “turn this text into a stepwise routine” with no servers.
- **App Intents + Visual Intelligence** surface your content from screenshots and real-world text, driving organic discovery.

---

## Key features
- **Stacks of Alarms & Timers** — chain fixed-time alarms and relative timers into stepwise routines.
- **System-grade Alerts** — AlarmKit alerts cut through Silent/Focus with familiar full-screen UI.
- **Live Activities & Dynamic Island** — see countdowns, skip/complete steps, and snooze from anywhere.
- **Liquid Glass UI** — modern, depth-rich visuals with refined controls.
- **On-device Routine Generation (optional)** — type “6:30 gym then shower and coffee” → get a proposed stack; runs on-device with graceful fallback if a model isn’t available.
- **Visual Intelligence & App Intents** — surface stacks from screenshots or real-world text (“6:30 Gym”) and create/start stacks via Shortcuts.
- **No servers** — pure client-side app; optional CloudKit for iCloud sync.

---

## Status
Early WIP. Core targets and scaffolding exist; APIs and UI are evolving rapidly for iOS 26 betas.

---

## Requirements
- **iOS:** 26.0 or later
- **Devices:** iPhone (day-one target)
- **Xcode:** Latest with the **iOS 26 SDK**
- **Frameworks:** Swift, SwiftUI, SwiftData, **AlarmKit**, App Intents, WidgetKit (for Live Activities), StoreKit 2, CloudKit (optional)

---

## Setup (AlarmKit authorisation)
Add the usage description key and request authorisation before scheduling alarms/timers:

1) **Info.plist**
```xml
<key>NSAlarmKitUsageDescription</key>
<string>We schedule alarms and timers for your routines so they alert reliably.</string>
