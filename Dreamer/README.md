# Dreamer (iOS, SwiftUI)

Phase 1 of the Dreamer app: all 14 designed screens, the full navigation flow and motion, running on
mock data behind service protocols. Design handoff: `../Dreamer-iOS-Handoff`.

- Xcode 26+, iOS 17.0+, iPhone only, portrait, light appearance
- Swift 6 language mode (strict concurrency), no third-party dependencies
- Open `Dreamer.xcodeproj` and run the `Dreamer` scheme; `Cmd+U` runs the unit tests

## Run from the terminal (fastlane)

Ruby 3.3.5 (`.tool-versions`) and Bundler; the first run installs the gems.

```
./run.sh                                     # build, boot iPhone 17, install and launch
./run.sh screen:journal                      # open a screen directly (see "Debug" below)
./run.sh device:"iPhone 17 Pro" reset:true   # another simulator, clean install
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
interpretation symbol record details analysis`. You can also add it to the scheme's launch arguments.

## Accessibility and motion

All loops (orb breathing, sky drift, waveforms, sparkles, thumbs) run on `TimelineView` and freeze
with Reduce Motion; entrance animations are skipped too. Icon-only buttons have labels, Dynamic Type
is capped at `.xxLarge`, and screens scroll on small devices (iPhone SE).

## Before release

- Re-export sky and thumbnail images at @3x (the handoff ships @2x only).
- Add the app icon to `AppIcon`.
- Replace the placeholder URLs in `AppLinks`.
