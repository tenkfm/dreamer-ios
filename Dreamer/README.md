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
