# Working in this repo

The Dreamer iPhone app: SwiftUI, Swift 6 strict concurrency, iOS 17+. The Xcode project is in
`Dreamer/`; the design handoff in `Dreamer-iOS-Handoff/`. The backend is a separate repo
(`../dreamerweb`) and is never edited from here: contract mismatches go to the blockers. Tasks and
progress live in `../Dreamer-iOS-Tasks` (`PROGRESS.md`, one story file per epic).

Start with `Dreamer/README.md`; it has a section per feature, and the detailed guides are in
`Dreamer/docs/`.

## Commands and what they cost

Run from `Dreamer/`. Everything goes through fastlane (Ruby 3.3.5, `bundle install` once).

| Command | Cost |
| --- | --- |
| `./run.sh test` (unit tests, 315) | about 70 s with the build; the tests themselves take 4 s |
| `./run.sh screen:<name>` (build, install, open a screen) | 30-60 s |
| `xcodebuild -project Dreamer.xcodeproj -scheme "Dreamer Staging" -configuration Staging -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation build` | about 25 s incremental; check it has no Swift warnings |
| `bundle exec fastlane ui_test` (4 scenarios) | about 2 min; `iterations:10` about 10 min, so only before a release or for a flaky test |
| `bundle exec fastlane screenshots` | about 3 min |
| `scripts/coverage.sh` | about 2 min |

`-skipPackagePluginValidation` is needed on every command-line build: the OpenAPI generator is a
build plugin, and the command line cannot answer Xcode's trust prompt. The lanes add it.

The simulator sometimes shuts down after a test run. `xcrun simctl boot <udid>` plus
`xcrun simctl bootstatus <udid>` brings it back before taking screenshots.

## Where things are

| Thing | Path |
| --- | --- |
| Composition root, live vs mock switch | `Dreamer/Dreamer/App/AppDependencies.swift` (`live()`, `mode(config:arguments:)`) |
| Session state, navigation, deep links | `Dreamer/Dreamer/App/AppState.swift` |
| Debug launch arguments | `Dreamer/Dreamer/App/DebugLaunch.swift` (table in the README) |
| Build settings per environment | `Dreamer/Config/*.xcconfig`; secrets in the git-ignored `Secrets.xcconfig` |
| The contract | `Dreamer/Dreamer/API/openapi.yaml`, a normalized copy: `scripts/sync-openapi.sh` from the backend, never by hand |
| Endpoint wrappers and mapping | `API/APIClient+Endpoints.swift`, `API/APIMapping.swift`; generated types never leave `API/` |
| Middlewares (order matters) | `API/APIClient.swift`: reporting -> retry -> attestation -> auth -> errors |
| Design tokens | `Dreamer/Dreamer/DesignSystem/Theme.swift`; views use nothing else |
| Analytics events and their allowed values | `Services/Analytics.swift` only, after `../dreamerweb/docs/tracking-plan.md` |
| Feature flags | `Services/FeatureFlags.swift` (PostHog keys, defaults) |
| Mocks | `Services/Mocks/`; a new protocol method needs its mock too, or the build fails |
| Contract examples for tests | `DreamerTests/Fixtures/openapi-examples.json` from `scripts/extract_openapi_examples.py` |
| String Catalog | `Dreamer/Resources/Localizable.xcstrings`, refreshed by `scripts/sync_strings.sh` |
| Project file | `Dreamer.xcodeproj` uses synchronized folders: a new file in a feature folder is picked up without editing the project |

## Standing instructions

These come from `../Dreamer-iOS-Tasks/CLAUDE.md` and Tony; they hold unless he says otherwise:

- **Never push.** Commit with a meaningful message; Tony pushes.
- **Secrets: names only.** Keys live in `Secrets.xcconfig` or CI secrets, never in code, commits or
  messages. Print variable names, never values.
- **No personal data leaves the device by the side door.** Dream texts, notes, emails and tokens
  are never logged, sent to analytics or put in crash reports. `PrivacyGuardTests` fails the build
  on `print`, `NSLog` or an unmarked Logger interpolation. Tokens live only in the Keychain.
- **Never invent a value** Tony has to give (keys, URLs, prices, copy that needs approval). Build it
  behind a protocol with a mock and write a blocker in `PROGRESS.md`.
- **App Store Connect, external TestFlight, App Review and RevenueCat dashboard actions only after
  an explicit "yes" from Tony.**
- **Only the SDKs named in the tasks.**
- Plain hyphen "-" in copy and docs, never an em dash.

## Working a task

Stories go in the order of `../Dreamer-iOS-Tasks/CLAUDE.md`. For each subtask:
1. Write the code, its tests, and the README or docs section.
2. Run `./run.sh test` and the Staging build, and check it has no Swift 6 warnings.
3. Where the UI changed, compare it on the simulator with `-debugScreen` against the handoff
   screenshots.
4. Commit, then mark `[x]` in `PROGRESS.md` with a one-line note.

## House style

Code comments explain *why*, not *what*: the reasoning the next person would otherwise rediscover,
including the defect a line exists to prevent. Match the comment density of the file you edit.
Commit messages do the same at a larger scale: what changed and why, in plain sentences.
