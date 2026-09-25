# Dreamer (iOS, SwiftUI)

Phase 1 of the Dreamer app: all 14 designed screens, the full navigation flow and motion, running on
mock data behind service protocols. Design handoff: `../Dreamer-iOS-Handoff`.

- Xcode 26+, iOS 17.0+, iPhone only, portrait, light appearance
- Swift 6 language mode (strict concurrency), no third-party dependencies
- Open `Dreamer.xcodeproj` and run the `Dreamer` scheme; `Cmd+U` runs the unit tests

## Environments

Three configurations, each driven by an xcconfig in `Config/` and read at runtime by `AppConfig`:

| Configuration | Scheme | Bundle id | API | Icon |
|---|---|---|---|---|
| Debug | Dreamer (Run) | `com.braincode.dreamer.staging` | staging | STAGING band |
| Staging | Dreamer Staging | `com.braincode.dreamer.staging` | staging | STAGING band |
| Release | Dreamer (Archive) | `com.braincode.dreamer` | production (domain pending) | App Store |

Staging and Release install side by side. SDK keys (RevenueCat, PostHog, Sentry) never live in the
repository: copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` (git-ignored) or let
CI write it from its secrets. An empty key keeps that SDK off.

## Run from the terminal (fastlane)

Ruby 3.3.5 (`.tool-versions`) and Bundler; the first run installs the gems.

```
./run.sh                                     # build, boot iPhone 17, install and launch
./run.sh screen:journal                      # open a screen directly (see "Debug" below)
./run.sh device:"iPhone 17 Pro" reset:true   # another simulator, clean install
./run.sh configuration:Staging              # optimized build against staging
./run.sh test                                # unit tests (results in build/test_output)
```

`run.sh` wraps `bundle exec fastlane sim` / `bundle exec fastlane test` (see `fastlane/Fastfile`).
Build products go to `build/DerivedData` (git-ignored).

## API layer

`Dreamer/API/` holds everything that knows the backend contract:

- `openapi.yaml` - copy of the contract, written by `scripts/sync-openapi.sh` from
  `../dreamerweb/openapi.yaml` (never edited by hand). The script normalizes nullable
  `anyOf [X, null]` values to optional `X`, which swift-openapi-generator 1.x would otherwise drop.
- `openapi-generator-config.yaml` - swift-openapi-generator runs at build time (Xcode asks once to
  trust the plugin; command-line builds pass `-skipPackagePluginValidation`). The operation
  allowlist leaves out the server webhooks and `morningInsight` (nullable body, called by hand).
- `APIClient` + `APIClient+Endpoints` - every phase 1 endpoint returning models from `Models/`;
  generated types never leave `API/`. `APIClient+Raw` covers the calls outside the generator.
- `APIError` - one error type: backend codes (`PREMIUM_REQUIRED`, `RATE_LIMITED` with
  `Retry-After` / `resetAt`, ...), plus offline, timeout and signed-out states.

Failures: `RetryMiddleware` retries GETs and the idempotent `POST /v1/dreams` on 5xx and dropped
connections (backoff 0.5 s, 1 s), never on 4xx. `ErrorState` (Features/Shared) turns every
`APIError` into a screen state with copy and an action (retry, paywall, sign in, new link, wait
until `resetAt`), shown with `ErrorStateCard`. `NetworkMonitor` drives a glass offline banner
(`offlineBannerInset()`, applied inside each navigation container; debug: `-offline`).

Live analysis: `APIClient.dreamEventStream` reads `GET /v1/dreams/{id}/events` (Server-Sent Events,
parsed byte by byte because `AsyncBytes.lines` drops the blank lines that end an event) into
`DreamEvent` (step, text delta with reset, ready with the whole dream, failed).
`DreamProgressTracker` falls back to polling `/status` every 2 s when the stream ends (after 120 s)
or the connection drops, and keeps polling through network gaps, so the result is never lost.

Tests use `DreamerTests/Support/StubURLProtocol.swift`; `LiveAPITests` hit staging when run with
`TEST_RUNNER_DREAMER_LIVE_TESTS=1`.

## Feature flags

`Services/FeatureFlags.swift` lists the remote switches with their code defaults, chosen so the
app works fully offline: `ttsEnabled` (on), `attestationEnforced` (off), `serverSttFallback` (on),
`imageGenerationEnabled` (on, image kill switch). With a PostHog key the values come from PostHog
feature flags with the same keys. A session always uses the flags cached on the previous launch
and refreshes the cache in the background, so a change applies on the next launch and never flips
a feature mid-use. Debug builds accept overrides: `-featureFlag ttsEnabled=false`.
The paywall variant is not a flag: the backend assigns it (`GET /v1/subscription.paywallVariant`).

## Crash reporting

Sentry (`Services/CrashReporter.swift`, SPM product `Sentry-Dynamic`: the static product drops
the Objective-C categories Sentry relies on and crashes on the first event). It starts first in
`AppDependencies.live()` when `SENTRY_DSN` is set; without it a no-op reporter is used. Reports
carry error codes, tags and the anonymous user id only: screenshots, view hierarchies, network
breadcrumbs, failed-request capture and default PII are off, so no dream text, note or email
leaves the device. Debug and Staging builds accept `-crashTestNonFatal` and `-crashTestCrash` to
check the console. `bundle exec fastlane upload_dsyms` (also run by `signed_build` when
`SENTRY_AUTH_TOKEN` is set) uploads the archive's dSYMs; it needs `sentry-cli`, `SENTRY_ORG` and
`SENTRY_PROJECT`.

## Signing

Certificates and profiles are shared through fastlane match (`fastlane/Matchfile`), App Store
Connect access through an API key, all from the environment: `APPLE_TEAM_ID`, `MATCH_GIT_URL`,
`MATCH_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT` (base64 of the .p8).

```
bundle exec fastlane certificates                        # fetch signing assets (readonly)
bundle exec fastlane certificates readonly:false         # create / renew them (admin only)
bundle exec fastlane signed_build configuration:Staging  # signed App Store build into build/archive
```

Capabilities live in `Dreamer/Dreamer.entitlements` and follow the configuration: Sign in with
Apple, Push (`aps-environment`), Associated Domains (`applinks:` + the API host) and App Attest.
Debug uses the development APNs / App Attest environments, Staging and Release production.
In-App Purchase needs no entitlement, only the capability on the App ID.

## CI

`.github/workflows/ci.yml` runs on every pull request and on `main` (macOS 26 runner, Xcode 26):
unit tests (`fastlane test`, JUnit and HTML report as the `test-report` artifact) and an unsigned
Release build for devices (`fastlane build_release`). Swift packages and DerivedData are cached.
SDK keys come from repository secrets through `scripts/write-secrets-xcconfig.sh`, which logs only
the names it set. To block merging on a red CI, mark `CI / test-and-build` as a required status
check in the branch protection of `main`.

## Architecture (MVVM)

```
Dreamer/
  App/            DreamerApp (composition root), AppState, AppDependencies, RootView, links, debug launch
  DesignSystem/   Tokens (Theme), motion, glass material, sky, reusable components
  Models/         Plain Sendable value types (Dream, Lens, Emotion, Plan, Route, ...)
  Services/       Protocols + implementations (real read-out and photo saving, mocks for the rest)
  Features/       One folder per screen: <Screen>View + <Screen>ViewModel
  Resources/      Asset catalog, fonts (listed under UIAppFonts in Info.plist)
DreamerTests/     Swift Testing suites for the view models
```

- **Views** only render and forward user intents. They use design-system tokens only (no ad-hoc
  hex values or font sizes).
- **View models** are `@MainActor @Observable` classes that own screen state and talk to services
  through protocols. They are created with explicit dependencies, so they can be tested without UI.
- **AppState** holds session state (onboarding, lens, subscription, reminders, tab and navigation
  paths) and persists preferences through `PreferencesStore`.
- **AppDependencies** is the composition root, injected with `.environment(_:)`. To go live, swap
  the mocks in `AppDependencies.live()`: `SpeechService` (SFSpeechRecognizer), `DreamAnalysisService`
  (backend LLM), `PurchaseService` (StoreKit 2, ids `dreamer.yearly` / `dreamer.weekly`), `DreamStore`
  (persistence).
- **Navigation**: linear `OnboardingFlowView`; `MainTabView` keeps one `NavigationStack` per tab
  with typed `Route` paths in `AppState`; Record -> Details -> Analysis is a `fullScreenCover`, and on
  finish the Interpretation is pushed on the Today stack.

## What is real vs mocked

| Real | Mocked |
|---|---|
| Voice read-out (`AVSpeechSynthesizer`, progress from spoken range) | Speech-to-text (types the sample transcript) |
| Save image to Photos (add-only permission) | Analysis (4 steps x 1.3 s, sample interpretation) |
| Preferences persisted in `UserDefaults` | Purchases (succeed after 0.8 s) |
| Share sheet (`ShareLink`) | Dreams (in memory, seeded with the Journal entries) |

## Debug: open any screen directly

Debug builds accept `-debugScreen <name>` (in-memory preferences, nothing persisted):

```
xcrun simctl launch booted com.braincode.dreamer -debugScreen interpretation
```

Names: `welcome recordIntro understand quizGoal quizLens paywall home journal library settings
interpretation symbol record details analysis`. Add `-night` or `-day` to force the appearance,
`-debugAdvance` to let an onboarding page tap "Continue" by itself after 2 s (checks the slide).
You can also add these to the scheme's launch arguments.

## Night mode

Every color token is adaptive (`Color(day:night:)` in `DesignSystem/Theme.swift`) and the sky images
have a dark-appearance variant in the asset catalog, so screens need no night-specific code. The app
always sets its own appearance through `preferredColorScheme` and never follows the system setting:

- by schedule from 9 PM to 5 AM, when Settings -> "Night mode after 9 PM" is on;
- by the moon / sun button on Home, which holds until the schedule flips at 9 PM or 5 AM.

Night skies are generated with Seedream 5.0 Pro on kie.ai; prompts live in the script:

```
KIE_API_KEY=... python3 scripts/generate_night_skies.py            # all images
KIE_API_KEY=... python3 scripts/generate_night_skies.py SkyTopNight
```

Results land in `build/night_skies/`; copy the ones you like into the matching image set.

## Accessibility and motion

All loops (orb breathing, sky drift, waveforms, sparkles, thumbs) run on `TimelineView` and freeze
with Reduce Motion; entrance animations are skipped too. Icon-only buttons have labels, Dynamic Type
is capped at `.xxLarge`, and screens scroll on small devices (iPhone SE).

## Before release

- Re-export sky and thumbnail images at @3x (the handoff ships @2x only).
- Add the app icon to `AppIcon`.
- Replace the placeholder URLs in `AppLinks`.
