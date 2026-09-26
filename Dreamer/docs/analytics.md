# Analytics, flags and SDK debugging

What the app reports, which remote switches it reads, and how to see each SDK at work while
debugging. The tracking plan is shared with the backend: `../dreamerweb/docs/tracking-plan.md`,
generated from `packages/shared/src/api/tracking.ts`. When they disagree, the plan wins, and a
change to it goes through the backend (a blocker, never an edit from this repo).

## Rules

- Event names, properties and their allowed values live in `Services/Analytics.swift` and nowhere
  else. Call sites pass typed values (`.paywallViewed(placement: .limit, variant: ...)`), never
  strings.
- No dream text, title, note, email, name or token is ever a property. `AnalyticsTests` checks the
  keys against the backend's forbidden list.
- The distinct id is the backend user id (`identify` after sign-in, `reset` at sign-out), which is
  also the id the server sends its own events under. So one person is one PostHog person.
- Every event carries two super properties: `preferred_lens` and `paywall_variant`.

## Client events

| Event | Properties | Sent from |
| --- | --- | --- |
| `onboarding_step_viewed` | `step` (welcome, record, understand, quizGoal, quizLens, paywall; the account step is not in the plan yet) | `OnboardingViewModel` |
| `quiz_answered` | `question` (goal, lens), `answer` | `OnboardingViewModel` |
| `sign_in_started` | `method` (apple, email; Google is not in the plan yet, so it sends nothing) | `SignInViewModel` |
| `paywall_viewed` | `placement` (onboarding, settings, limit), `variant` | `PaywallViewModel` (once per screen) |
| `plan_selected`, `purchase_started` | `plan` (yearly, weekly) | `PaywallViewModel` |
| `record_started` | - | `RecordViewModel` (once per recording) |
| `record_finished` | `seconds`, `input` (voice, text) | `RecordViewModel` |
| `details_submitted` | `skipped`, `emotionsCount` | `RecordFlowViewModel` |
| `interpretation_viewed` | `lens` | `InterpretationViewModel` (not for crisis dreams) |
| `lens_promoted` | `from`, `to` | `InterpretationViewModel` |
| `read_aloud_played` | `lens`, `fallback` | `BackendReadAloudService` |
| `read_aloud_completed` | `lens`, `fallback`, `listenedPct` (at the end, or when stopped) | `BackendReadAloudService` |
| `read_aloud_fallback` | `lens`, `reason` (tts_unavailable, audio_failed, timeout, network) | `BackendReadAloudService` |
| `dream_shared` | `target` (share_sheet, photos), only when the share finished | `InterpretationViewModel` |
| `journal_opened` | - | `JournalViewModel` |
| `library_symbol_opened` | `slug` | `SymbolDetailViewModel` |
| `push_opened` | `type` (interpretation_ready, image_ready) | `RootView` |
| `att_response` | `status` (not in the plan yet: blocker) | `TrackingConsent` |

Screen views (`Home`, `Journal`, `Library`, `Settings`, `Interpretation`, `Symbol`, `Record`,
`Paywall`, `Onboarding`) come from `.trackScreen(_:)` on each screen.

Server events (sign-up, dream created, interpretation ready, subscription changes, ...) and the
revenue events (trial started, purchased; through RevenueCat's integrations) are not sent by the
app. Do not duplicate them.

**Adding an event:**
1. Add it to the backend's `tracking.ts` first (a backend task).
2. Add a case in `AnalyticsEvent` with typed values, and its name and properties.
3. Track it at the moment it means.
4. Add a line to `TrackingPlanTests.allEvents`.

## Feature flags

Remote booleans from PostHog (`Services/FeatureFlags.swift`). The key is the case name. A flag
flipped in PostHog applies from the next launch: the SDK keeps the last values on disk, so
features never switch mid-session. Without a key, or before the first fetch, every flag keeps its
default.

| Flag | Default | Effect |
| --- | --- | --- |
| `ttsEnabled` | on | The backend voice; off = the system voice only |
| `attestationEnforced` | off | App Attest fails closed (the backend is in soft mode now) |
| `serverSttFallback` | on | The audio is kept and written down on the server when the device gives no text |
| `imageGenerationEnabled` | on | Kill switch for new dream images (regeneration) |
| `attAfterFirstDream` | off | A/B of the tracking question: after the first interpretation, not before the paywall |

In Debug builds, override any flag at launch: `-featureFlag ttsEnabled=false`.

## Seeing the SDKs at work

**PostHog.** Put `POSTHOG_API_KEY` and `POSTHOG_HOST` in `Config/Secrets.xcconfig`, run a Debug
build with `-liveServices` (or no debug screen), and watch PostHog -> Activity -> Live events.
Without a key, every event goes to the unified log instead:

```
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.braincode.dreamer" AND category == "analytics"'
```

It prints each event with its properties.

**Sentry.** With `SENTRY_DSN` set, launch a Debug or Staging build with `-crashTestNonFatal`, which
sends a handled error with the code `CRASH_TEST`, or with `-crashTestCrash`, which crashes on
purpose; relaunch to send the report. Check the event in Sentry -> Issues, with the release and
environment tags. API failures appear as issues grouped by `operation` and `error_code`.

**RevenueCat.** With `REVENUECAT_API_KEY` set, Debug and Staging log at debug level (`[Purchases]`
in the Xcode console). Use a sandbox Apple ID on a device. Without a key, the app uses StoreKit 2 on
`StoreKit/Dreamer.storekit` in the simulator; Xcode -> Debug -> StoreKit -> Manage Transactions
expires or refunds a purchase to test the paywall's return.

**Tracking question and attribution.** `-askTracking` shows the tracking question in Debug.
Attribution and the ad SDKs are protocols without an implementation until the MMP and the ad
networks' ids exist (blockers). `MeasurementStack` is where they start with the user's answer.

**Launch time.** Debug and Staging log the time to the first frame:

```
xcrun simctl spawn booted log show --last 5m --predicate 'category == "launch"'
```
