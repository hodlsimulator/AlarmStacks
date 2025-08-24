# Agents Playbook — AlarmStacks (iOS 26-only) — Full Privileges

**Agent:** Codex (software engineering agent).  
**Authority:** Full write access. You may modify any files, project settings, entitlements, Info.plists, CI, and scripts.  
**Branching policy:** Work on **`main`** after creating/pushing a full snapshot backup branch.

---

## Objectives

1) **Live Activities reliability**: Make Live Activities start and update **reliably** on real devices.  
   - Avoid `ActivityAuthorizationError.visibility` by only requesting when the app is **foreground + device unlocked**.  
   - Avoid thrashing on `targetMaximumExceeded`; back off and retry on a sane cadence.

2) **“Liquid Glass” styling**: Lock-screen Live Activity should **let the system render the translucent background** (no opaque cards).  
   - Use `.activityBackgroundTint(.clear)`.  
   - Do **not** add a SwiftUI `.containerBackground` for the Live Activity lock-screen root.

**Constraints**

- iOS **26** only; no legacy paths.  
- **No notifications permission prompt**. We are **not** using ActivityKit push updates.  
- Keep content compact and legible (monospaced digits, `.primary`/`.secondary` colours).  
- Respect OS guardrails: hard minimum lead ≈ **48s** before fire to avoid “late start” rejections.

---

## Current State (must keep)

- `AlarmStacksWidget/AlarmStacksWidget.swift`  
  - Lock-screen view uses `.activityBackgroundTint(.clear)` (Liquid Glass).  
  - No `.containerBackground` on the Live Activity lock view.  
  - Dynamic Island is compact; uses `.keylineTint(accent)`.

- `AlarmStacks/LiveActivityManager.swift`  
  - Defers `Activity.request` when the app is not active; schedules retries up to **+180s** after target (`RETRY_AFTER_TARGET`).  
  - Foreground cadence tick ~30s; bridge pre-arm in last **90s** via `NextAlarmBridge`.  
  - Hard minimum lead **48s** (`HARD_MIN_LEAD_SECONDS`).  
  - Protected-data unlock observer uses `UIApplication.protectedDataDidBecomeAvailableNotification`.  
  - `cleanupOverflow` ends extras to prevent cap errors.  
  - No push update types; purely in-app `Activity.request/update/end`.

**Do not remove these behaviours.** You may refactor but must preserve semantics.

---

## What to change or verify

1) **Entitlements & Info.plists**
   - App target **and** widget target have **Live Activities capability** enabled.
   - `Info.plist` (app and widget):  
     ```xml
     <key>NSSupportsLiveActivities</key>
     <true/>
     ```
   - No remote push update entitlements are required.

2) **Live Activity start policy**
   - Start only when:
     - `UIApplication.shared.applicationState == .active`
     - `UIApplication.shared.isProtectedDataAvailable == true`
     - Global toggle: `ActivityAuthorizationInfo().areActivitiesEnabled == true`
   - If not eligible:
     - **Defer** and schedule a retry every **5s** until `target + 180s`.  
     - On `.targetMaximumExceeded`: apply a **cooldown** (≥ 90s) before next attempt.  
     - On `.visibility`: do a tight quick retry once the app becomes active/unlocked.

3) **Styling**
   - Keep `.activityBackgroundTint(.clear)` on the **lock-screen Live Activity root**.  
   - Do **not** set a custom `.containerBackground` for the lock-screen Live Activity.  
   - Keep typography minimal and legible; monospaced digits for timers.  
   - Dynamic Island remains minimal; `.keylineTint(accent)` optional.

4) **Guardrails**
   - Do not start new activities inside the late window (`lead < 48s`) unless via the bridge pre-arm path.  
   - Keep the “far-future” guard (avoid “in 23h” flashes).  
   - Maintain `cleanupOverflow(keeping:)` calls to avoid cap errors.

5) **Logging (retain)**
   - Keep MiniDiag/LADiag logging for `start/refresh/update/fail` and timer state.  
   - Log retry schedules and cooldowns.

---

## Deterministic test plan (real device)

1) **Foreground success test**
   - Ensure a step ~2 minutes out. With app **open**, call the manager’s start/sync path.  
   - Expect logs like:  
     `"[ACT] start stack=… step=… ends=… id=…"`,  
     and `active.count=1 … seen=y`.  
   - Live Activity appears on Lock Screen / Dynamic Island within seconds.

2) **Background/locked deferral**
   - Lock the device while inside the pre-arm window.  
   - Expect **no** `Activity.request` until device unlock; retries logged with 5s cadence.  
   - Upon unlock, a start should succeed quickly (no repeated `visibility`).

3) **Bridge fallback (≤90s)**
   - With no stack IDs discoverable, ensure `NextAlarmBridge` snapshot triggers a Live Activity in the last **90s** before fire.

4) **TargetMaximumExceeded handling**
   - Force multiple parallel attempts (dev only) and verify a **cooldown** log then a later successful start after overflow cleanup.

All tests should keep the lock-screen background translucent (“Liquid Glass”).

---

## Git workflow for Codex

**You must do this before any edits:**

```bash
git fetch origin
git checkout -B main origin/main || git checkout main
git pull --ff-only
STAMP=$(date +"%Y-%m-%d-%H%M")
git switch -c "backup/pre-codex-$STAMP"
git add -A
git commit -m "Backup: full project snapshot before Codex changes ($STAMP)"
git push -u origin HEAD
git switch main
git pull --ff-only
git merge --no-ff "backup/pre-codex-$STAMP" -m "Merge backup snapshot before Codex changes ($STAMP)"
git push origin main
