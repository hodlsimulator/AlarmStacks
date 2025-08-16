# Alarm Stacks — Routine Alarm Clock

A beautiful, system-level alarm & routine builder for iOS 26. Compose “stacks” like **Wake → Hydrate → Stretch → Shower → Leave**, where each step is a real **AlarmKit** alarm or timer with system alerts that cut through Silent/Focus, Live Activity countdowns, and Lock Screen/Dynamic Island controls. Optional on-device “generate my routine” uses Apple’s **Foundation Models** — no servers, no user data leaving the device. **App Intents** + **Visual Intelligence** make your stacks discoverable from visual search and “what’s on my screen”. The entire UI embraces **Liquid Glass**.

---

## Why this wins now

- **AlarmKit is new in iOS 26** — schedule one-shot or repeating alarms and countdown timers with system-level alerts, Live Activities, and Dynamic Island. Previously this wasn’t possible without special entitlements.  
- **Liquid Glass is the headline design** for this cycle; apps that ship day-one with it are strong candidates for editorial featuring.  
- **On-device Foundation Models** expose guided generation and tool calling — perfect for “turn this text into a stepwise routine” with no server and no privacy trade-offs.  
- **App Intents power Visual Intelligence** so system visual search can deep-link straight into stacks and steps, aiding organic discovery without an ad budget.

---

## Key features

- **Stacks of Alarms & Timers** — chain fixed-time alarms and relative timers into stepwise routines.
- **System-grade Alerts** — AlarmKit alerts cut through Silent/Focus with familiar system UI.
- **Live Activities & Dynamic Island** — see countdowns, skip/complete steps, and snooze from anywhere.
- **Liquid Glass UI** — modern, depth-rich visuals with materials and refined controls.
- **On-device Routine Generation (optional)** — type “6:30 gym then shower and coffee” → get a proposed stack. Runs entirely on device with Foundation Models; graceful fallback if a model isn’t available.
- **Visual Intelligence & App Intents** — surface stacks from screenshots or real-world text (“6:30 Gym”) and create/start stacks via Shortcuts.
- **No servers** — pure client-side app; optional CloudKit for iCloud sync.

---

## Monetisation

**Freemium + subscription (StoreKit 2, client-side only):**

- **Free:** 2 stacks, 8 steps per stack, basic sounds/themes.
- **Alarm Stacks Plus:** Unlimited stacks, advanced step types (smart snooze windows, auto-repeat blocks), batch templates, pro Liquid-Glass themes, Focus-based auto-arming, on-device “Generate my routine”, alternate icons.
- **Pricing:** £3.99/month or £24.99/year. Launch promo: 1-week free trial.
- **Optional:** iCloud sync via CloudKit (Apple-hosted; no infra to run).

---

## App Store optimisation & virality

- **Name:** *Alarm Stacks — Routine Alarm Clock* (retains “alarm clock”, “routine”, “timer”).
- **Subtitle:** “Build step-by-step alarms for mornings, workouts & focus.”
- **Keywords:** alarm, alarm clock, timer, routine, pomodoro, wake up, habit, focus, hydration, workout, study, productivity.
- **Self-marketing loops:**
  - Shareable **Stack Cards** (image export) with your Liquid-Glass theme.
  - **Shortcuts/App Intents** gallery links (“Start 25-minute Pomodoro”, “Hydrate every 2h”).
  - **Visual Intelligence** surfacing from screenshots/real-world text.

---

## MVP scope (2–3 weeks, single dev)

### Must-have (week 1–2)
- Create/edit **Stacks & Steps** (SwiftData).
- **AlarmKit** scheduling for timers and fixed/relative alarms; Live Activity countdown; Dynamic Island UI.
- **Liquid Glass** adoption on custom SwiftUI views.
- **StoreKit 2** subscription (free tier + Plus).

### Nice-to-have (week 3)
- On-device “Generate routine from text” via **Foundation Models** with graceful fallback.
- **App Intents** for creating/starting stacks (ready for Spotlight/Shortcuts/Visual Intelligence).

---

## Requirements

- **iOS:** 26.0 or later.
- **Devices:** iPhone (day-one release target).
- **Xcode:** Latest version with the iOS 26 SDK.
- **Languages & Frameworks:** Swift, SwiftUI, SwiftData, AlarmKit, WidgetKit (for Live Activities), App Intents, StoreKit 2, CloudKit (optional).

---

## Build & run

1. Open the project in Xcode (latest iOS 26 SDK).
2. Select the **AlarmStacks** scheme and an **iOS 26** simulator or device.
3. **First launch prompts:**
   - Allow **Notifications** so AlarmKit alerts can break through Silent/Focus when appropriate.
   - (Optional) Enable **iCloud** if you want CloudKit sync.

> Tip: For reliable testing, try a real device to verify Live Activities, Dynamic Island, Focus interactions, and alert presentation.

---

## Permissions & privacy

- **Notifications:** Required for alarms/timers to alert reliably.
- **Focus/Silent behaviour:** AlarmKit integrates with system policies to present time-critical alerts.
- **Privacy:** No third-party analytics. No external servers. Optional iCloud sync via CloudKit. On-device routine generation only.

---

## Roadmap (post-launch)

- **Templates gallery:** Morning, Gym, Study, Pomodoro, Wind-down.
- **Advanced step types:** Conditional branches, location-aware “Leave now”, health-aware recovery windows.
- **Rich theming:** Additional Liquid-Glass themes and icon packs.
- **Localization:** Major languages prioritised by App Store regions.

---

## ASO copy blocks (for reference)

- **Long description (excerpt):**  
  Alarm Stacks turns your mornings and workflows into step-by-step routines made of real system alarms and timers. Build stacks like “Wake → Hydrate → Stretch → Shower → Leave”, run them from the Lock Screen and Dynamic Island, and (optionally) generate them from plain English — all on device.

- **Promo phrases:**  
  “Build step-by-step alarms.” · “Real alarms that cut through Silent.” · “Live countdowns on your Lock Screen.” · “Generate routines on device.”

---

## Tech summary

- **Architecture:** SwiftUI + SwiftData models; AlarmKit scheduling; Live Activity management; App Intents surfaces for creation/start; optional Foundation-Models-powered parser; StoreKit 2 for subscriptions; CloudKit for sync.
- **No servers:** All core features function offline; sync is Apple-hosted if enabled.

---

## Licence

Copyright © 2025. All rights reserved.

---

## Contact

Issues and feature requests welcome via GitHub Issues.
