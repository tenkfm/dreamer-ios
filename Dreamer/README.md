# Dreamer (iOS, SwiftUI)

Dreamer, the AI dream journal for iPhone: tell a dream, read what it may mean through three lenses,
keep the journal. The app talks to the Dreamer backend (`../dreamerweb`, NestJS) through a
generated OpenAPI client; RevenueCat, PostHog, Sentry and GoogleSignIn are its SDKs. Every service also has a
local mock, so the whole app runs without the network. Design handoff: `../Dreamer-iOS-Handoff`;
tasks and progress: `../../Dreamer-iOS-Tasks`.

- Xcode 26.2+, iOS 17.0+, iPhone only, portrait; day and night appearance
- Swift 6 language mode (strict concurrency), SwiftUI, `@Observable` MVVM
- Packages: swift-openapi-generator/runtime/urlsession, RevenueCat, PostHog, Sentry-Dynamic

## Quick start

1. Install Xcode 26.2 and Ruby 3.3.5 (`.tool-versions`), then `gem install bundler`.
2. Optional: `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig` and fill in the SDK keys
   you have. Without keys each SDK stays off and the app uses its local fallback.
3. `./run.sh` builds, boots the iPhone 17 simulator and launches the app. The first run resolves the
   Swift packages, which takes a few minutes. In Xcode, open `Dreamer.xcodeproj` and run the
   `Dreamer` scheme; Xcode asks once to trust the OpenAPI generator plugin.
4. `./run.sh test` runs the unit tests, and `bundle exec fastlane ui_test` the UI tests.
5. `./run.sh screen:interpretation` opens any screen directly on mock data (see "Debug" below).

Debug and Staging builds talk to the staging backend. Without an account there, use
`-mockServices` (the default for `-debugScreen`) for a fully local app.

## Guides

- `docs/release.md`: signing with match, internal TestFlight (`fastlane beta`), App Store release,
  hotfix
- `docs/analytics.md`: events, flags, and how to see PostHog, Sentry and RevenueCat while
  debugging
- `docs/app-store-connect.md`: everything the App Store Connect record needs
- `docs/qa-checklist.md`: the manual pass before App Review
- `docs/performance.md`: measurements and the Instruments checks on devices

## Environments

Three configurations, each driven by an xcconfig in `Config/` and read at runtime by `AppConfig`:

| Configuration | Scheme | Bundle id | API | Icon |
|---|---|---|---|---|
| Debug | Dreamer (Run) | `com.braincode.dreamer.io` | staging | STAGING band |
| Staging | Dreamer Staging | `com.braincode.dreamer.io` | staging | STAGING band |
| Release | Dreamer (Archive) | `com.braincode.dreamer.io` | production (domain pending) | App Store |

All three share one bundle id (one App ID, one Google client, one AASA entry), so a Staging and a
Release build replace each other on a device; the STAGING band on the icon tells them apart. SDK keys (RevenueCat, PostHog, Sentry) never live in the
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

Sharing (IOS-05.6, `Services/ShareCard.swift`): Share (in the header and "Share my dream image")
fetches the backend's 9:16 card with `GET /v1/dreams/{id}/share-card`. While the backend renders
it (202), the app asks again after `Retry-After`, for up to 15 s, and then downloads the card from
its signed link. The card opens in the system share sheet, which includes Save Image. Offline or in
mock mode the dream image is shared instead. `dream_shared {target}` is sent only when a share
finishes: `photos` for Save Image and the download button, `share_sheet` otherwise. "Share to
Instagram Stories" puts the card on the pasteboard for 5 minutes and opens
`instagram-stories://share?source_application=<Meta app id>`. The button shows only when Instagram
is installed and `FACEBOOK_APP_ID` is set in the xcconfig (empty for now, see Blockers).

Read aloud (IOS-05.5, `Services/BackendReadAloudService.swift`): Listen plays the backend's
ElevenLabs voice with AVPlayer, using the `playback` / `spokenAudio` session. The main lens comes
with the dream (`DreamDetail.audio[lens]`) and is buffered as soon as Interpretation opens, so it
starts at once. For another lens the app calls `POST /v1/dreams/{id}/audio?lens=`; on 202 it polls
`GET` of the same path every second for up to 30 s, and the button shows a spinner meanwhile.
Progress follows the word timings. An expired link is fetched again once. The on-device voice
(`SpeechSynthesizerReadAloudService`) reads instead when `ttsEnabled` is off, on `TTS_UNAVAILABLE`,
a failed job, a timeout, no connection, or a link that fails twice. Events: `read_aloud_played`
and `read_aloud_completed` (`fallback` true/false), and `read_aloud_fallback {reason}`.

Dream image (IOS-05.4, `Services/DreamImageLoader.swift`): while `image.status` is `pending`, the
hero shows the sky with "Painting your dream…" and Interpretation polls `GET /v1/dreams/{id}` every
3 s for up to 2 minutes. The ready image replaces the sky with the same reveal from blur. Images are
cached in Caches/DreamImages with complete protection, keyed by dream, `version` and size, so
expiring presigned links do not matter. A 403 on a link gets the dream again for fresh links, once,
and a new version replaces the old files. A failed image gets "Try a new image", and a long press
on the hero gives "Create a new image": both call `POST /v1/dreams/{id}/image/regenerate`, with the
daily 429 explained. Both are hidden by the `imageGenerationEnabled` kill switch and for crisis
dreams. Save to Photos writes the downloaded file. The cache is emptied at sign-out and account
deletion. Journal thumbnails (`.thumbnail`) arrive with IOS-06. Debug: `-debugScreen interpretation
-imagePending`.

Lenses and notes (IOS-05.3): the main lens of every interpretation is the account's preferred lens
(the backend reads it from the profile for each dream), so changing it in Settings updates dreams that
are already open. "Make this my main lens" sets it for the whole account and tracks
`lens_promoted {from, to}`. Setting changes are queued in `AppState.unsyncedProfile`, which persists,
and sent with `PATCH /v1/me`. At launch the queue goes up before the profile pull, so an offline
change is not overwritten. Notes are saved on the device as the user types, and sent with
`PATCH /v1/dreams/{id}` 1 s after typing stops, or at once when the screen closes. The limit is 4000
characters.

Crisis-flagged dreams (IOS-05.2): when `interpretation.safetyFlag` is true, Interpretation shows
`SupportCard` instead of the reading. There are no lenses, voice, image badge, sharing or saving;
the notes and the disclaimer stay. Analysis also drops the text it streamed. The copy and the
per-country help services come from `SupportContentProvider`. Until Tony approves them,
`PendingSupportContent` shows a neutral draft with only "call your local emergency number" and no
phone numbers. Debug: `-debugScreen support`.

Journal (IOS-06.1, `Services/CachedDreamStore.swift`): `DreamStore` gives the screens synchronous
reads from the device cache and async calls for the server. The live `CachedDreamStore` keeps the
list entries and the dreams opened in full in SwiftData, in the same protected LocalStore as the
drafts. So Journal opens at once, offline too. Opening Journal and pull-to-refresh load the first
page of `GET /v1/dreams`, which replaces the cached list; dreams deleted on another device disappear
along with their cached text. Older pages load when the last row appears (`nextCursor`). Rows are
grouped by the backend's `weekOf` ("This week", "Last week", "Sep 7 - 13"; the design's month
grouping gave way to the task's weekly one), with thumbnails from `thumbnailUrl` through the image
cache. A long press offers "Delete dream", confirmed first, which calls `DELETE /v1/dreams/{id}`
and then forgets the dream on the device. Interpretation shows the cached dream and fetches the
fresh one; when the dream is not cached yet, it shows a spinner.

Library (IOS-06.4, `Services/APISymbolCatalog.swift`): each category loads from
`GET /v1/library/symbols?category=`, following `nextCursor`, when it is selected; Home's thumbs use
`popular`. Search waits 300 ms after the last change and then calls `?q=`; offline it searches the
symbols on the device. A symbol's detail shows its cached entry at once and then loads
`GET /v1/library/symbols/{slug}`: the full meaning, every lens, the reflection question and
related symbols as chips that open them. Opening a detail tracks `library_symbol_opened {slug}`.
Symbols are kept in `Caches/library.json`, and a symbol opened in full keeps its lenses when list
refreshes come in. Pictures are cached in `Caches/SymbolImages`, keyed by symbol and link path. So
the library works offline once it has been opened.

Insights (IOS-06.3, `Services/InsightStore.swift`): Home's week strip and caption come from
`GET /v1/insights/week`, and its insight card from `GET /v1/insights/morning`. When that answer is
`null` the card is hidden, except for a new user with no dreams, who sees the invitation. The
Journal summary comes from `GET /v1/insights/month`: count, ring (dreams / nights so far), top
symbol and emotion shares; an empty month says "Tell a dream and your month will take shape here".
The three are fetched together when Home opens, after every new or deleted dream, and on Journal
refresh. The last answers are kept in `Application Support/Dreamer/insights.json` (complete
protection), so the numbers show offline and at launch, and the file is removed at sign-out.
Mock mode computes the same numbers from the stored dreams.

Search (IOS-06.2): the search field and the emotion chips under it wait 350 ms after the last change,
then call `GET /v1/dreams?q=&emotion=`. The backend matches titles, symbols, the text and the
interpretation, and every word works as a prefix. Rows then show the `snippet` with the matched
words in bold (the backend marks them with `**`). Until the answer comes, and offline, the
journal filters titles and symbols of the dreams on the device. Closing search brings back the
whole journal.

Analysis (IOS-05.1): the checklist follows the `step` events. The main lens appears under the card
as it is written (`text` deltas; `reset: true` drops what was shown because the backend restarted
with its fallback provider). `ready` enables "See my interpretation". A failed dream (`status: failed`
or an `error` event) shows "Try again": the same `clientId` returns the failed dream, and the service
then calls `POST /v1/dreams/{id}/retry` before following it again. Closing the screen only stops
listening; the backend finishes the dream anyway.

Mock or live: `AppDependencies.live()` talks to the build's backend (`APIClient` + `TokenManager`
with the Keychain) when the configuration has an API host. `-mockServices` (Debug and Staging
builds) keeps every service local, as do previews, unit tests and Release until the production
domain exists. Live today: the dream analysis (`APIDreamAnalysisService`); speech, journal,
library, purchases and voice switch as their stories land. Without a session the live analysis
answers "sign in again" - sign-in arrives with IOS-02.

Tests use `DreamerTests/Support/StubURLProtocol.swift`; `LiveAPITests` hit staging when run with
`TEST_RUNNER_DREAMER_LIVE_TESTS=1`.

UI tests (IOS-11.2, `DreamerUITests`, scheme "Dreamer UITests", `bundle exec fastlane ui_test`,
also a step in CI) cover the critical scenarios on mock services:
- a fresh install through onboarding, email sign-in, the paywall and a purchase, to Home;
- Home -> Record -> Details -> Analysis -> Interpretation -> Journal;
- deleting the account, which ends back on Welcome.
Each screen on the way runs `performAccessibilityAudit` for element descriptions, hit regions and
traits. Debug-only launch arguments keep the runs deterministic: `-uiTesting` starts with fresh
preferences, and `-uiTestOpenEmailLink` "taps" the sign-in link a moment after the mock sends it.
The purchase goes through the mock store, not StoreKit, because mock mode never calls StoreKit.
`fastlane ui_test iterations:10` repeats the suite until the first failure; the last run passed
10 times in a row (30 of 30).

Manual QA for internal TestFlight (IOS-11.3): `docs/qa-checklist.md` lists every screen and state
on 3-4 devices under real conditions (dim light, bad network, interruptions, sandbox purchases,
large text, VoiceOver), with severities for the ClickUp triage.

Contract tests (IOS-11.1): `scripts/extract_openapi_examples.py` turns every response example of
`Dreamer/API/openapi.yaml` into `DreamerTests/Fixtures/openapi-examples.json` (dates back to ISO
8601, as the API sends them). `ContractTests` stubs the network with each success example and
runs the client's mapping. They also check that every documented error code is known to the app
and that the paywall and rate-limit answers become the right screens. Rerun the script after
`scripts/sync-openapi.sh`. `scripts/coverage.sh` prints the line coverage of Services and API:
73 % now, against the target of at least 70 %. What remains uncovered wraps the system and SDKs
(RevenueCat, StoreKit, the speech synthesizer, the microphone) and is checked on devices.

## Account

Onboarding: Welcome -> Record intro -> Understand -> quiz -> **account** -> paywall -> Main. The
account step (`Features/Auth`) has Sign in with Apple and an email link ("Check your inbox", resend
with a 30 s cooldown; the backend allows 5 emails an hour). The design has no account screen: it is
built from the design system after the web handoff's spec. "I already have an account" opens the
same step as "Welcome back"; a returning account skips the rest of onboarding. Nothing after the
account step can be reached until the user is signed in.

The intro pages and the quiz are one screen (`OnboardingPagesView`): the top bar, the page dots and
"Continue" stay while only the content between them changes (a short slide and fade in the
direction of the move), the panoramic sky pans with the steps, and the top bar morphs from the logo
and "Skip" to Back and the quiz progress, which fills from 1 of 2 to 2 of 2. Swipes left and right
page as the buttons do. The account step and the paywall are separate screens that come in like a
navigation push (`Animation.push`). The staggered entrance plays only when the flow first appears;
after that the transitions carry every change. `-debugAdvance` walks the flow by itself, for
watching or recording the changes.
`AuthService` (`APIAuthService` / `MockAuthService`) stores tokens through `TokenManager`; at
launch the Keychain decides whether the user is still signed in.

Email links are universal links, `https://<api host>/auth/verify?token=...`: Associated Domains
lists `applinks:$(API_HOST)` and the backend serves the AASA file from that host. `DeepLink`
(App/AppLinks.swift) only trusts this build's API host; `.onOpenURL` in RootView hands the link to
AppState, which keeps it until the account step verifies it (so a cold start works too). An
expired link offers "Send a new link" to the address requested on this device.

Sign in with Google sits under the Apple button (`Services/GoogleSignIn.swift`,
`Features/Auth/GoogleSignInButton.swift`), through Google's SDK (GoogleSignIn-iOS). The SDK reads
`GIDClientID` from Info.plist and comes back through the `REVERSED_CLIENT_ID` URL scheme, which
`RootView.onOpenURL` hands to it; both come from `GOOGLE_IOS_CLIENT_ID` and
`GOOGLE_REVERSED_CLIENT_ID` in Shared.xcconfig (the client of com.braincode.dreamer.io, taken from
Google's client plist). The app sends a random nonce with the request, and the id token and the
nonce go to `POST /v1/auth/google`, which answers like the Apple and email sign-ins. The SDK is
signed out right after, so no Google tokens stay on the device. The button follows Google's
branding (the four-color "G", white by day, near-black at night, "Sign up/in with Google"); its
colors are `DS.Brand`. Without a valid client id the button is hidden (the SDK would crash); mock
mode always shows it and signs in without Google.

Settings has "Sign out" and "Delete account and all dreams" (`AccountController`). Sign-out calls
`POST /v1/auth/logout` (best effort, works offline), forgets the tokens, clears the dreams cached
for the account and unlinks the SDKs; the next sign-in is "Welcome back". Deletion shows a sheet
that warns the App Store subscription is separate (with Manage subscription), calls
`DELETE /v1/me`, and only then resets the device to a fresh install; a failure leaves everything
in place and explains why. Debug: `-debugScreen deleteAccount`.

Profile sync (`Services/ProfileSync.swift`): after a first sign-in the quiz answers and settings
made on this device go to `PATCH /v1/me` (goal, lens, reminder, IANA time zone, night mode);
after signing in to an existing account, and at every launch with a session, `GET /v1/me` wins
over the local copy (another device may have changed it) and a changed time zone is sent back.
Failed syncs stay pending and retry at the next launch. The paywall close button that skips to
Main exists in Debug builds only.

## Purchases

`PurchaseService` has three implementations: `RevenueCatPurchaseService` (RevenueCat SDK over
StoreKit 2, entitlement `premium`, app user id = backend user id) when `REVENUECAT_API_KEY` is
set; `StoreKitPurchaseService` (StoreKit 2 directly) otherwise, so purchases can be tried before
the RevenueCat project exists; `MockPurchaseService` in mock mode. `StoreKit/Dreamer.storekit`
holds `dreamer.yearly` ($39.99, 7-day free trial) and `dreamer.weekly` ($6.99) and is the Run
action's StoreKit configuration of the Dreamer scheme: running from Xcode buys locally, with no
sandbox account. `StoreKitPurchaseTests` use it through SKTestSession and are opt-in
(`TEST_RUNNER_DREAMER_STOREKIT_TESTS=1` or from Xcode): the command-line simulator of Xcode 26.2
serves no products to test sessions.

Access (`Services/SubscriptionSync.swift`): for the whole signed-in session the store's
entitlement stream drives `AppState.subscription`, so a renewal, an expiry or a refund applies at
once (an expired user lands on the paywall without a relaunch). `GET /v1/subscription` is read at
launch and, after a purchase, polled for a few seconds until the backend agrees (its webhook can
lag); it also brings the paywall variant and the free interpretations left. `PREMIUM_REQUIRED`
during analysis shows "See plans"; buying reads the same dream at once.

Paywall variant: the backend assigns it at sign-up (`paywallVariant`, kept on the device between
launches). `hard` shows the paywall right after sign-up; `oneFree` sends the new account to Main
with one free interpretation, and the paywall appears once it is used (the mic opens the paywall
instead of recording, so a told dream is never stuck behind a 402). Restore explains when there is
nothing to restore; subscribers open the App Store's own management from Settings -> Subscription.
Events: `paywall_viewed {placement, variant}`, `plan_selected`, `purchase_started`; trial and
purchase events come from the RevenueCat integration.

## Recording

`OnDeviceSpeechService` (live mode) streams the microphone through AVAudioEngine into
SFSpeechRecognizer with `requiresOnDeviceRecognition` where the model exists, so a dream is written
down in airplane mode. The user's language is used when the device can recognize it, US English
otherwise. One recognition request stops after about a minute; the service starts the next one and
`TranscriptStitcher` continues the text after the finished segments. `AudioLevelMeter` turns each
buffer into a 0...1 level about 20 times a second; the Record waveform mirrors the last 24 levels
around its centre. Mock mode types the sample dream with a talking-like level.

Permissions: the first time, Record shows its own card ("Tell your dream out loud", Allow microphone
/ Type it instead) before the system asks for the microphone and speech recognition. A refusal
shows "The microphone is off" with Type it instead and Open Settings, so a dream can always be
written. Debug: `-micPermission notDetermined|denied|restricted` with `-debugScreen record`.

Interruptions never lose words: a call, Siri or an alarm (audio session interruption), the app going
to the background or the lock screen pause the recording with the text so far, explain why, and
"Continue recording" (or a tap on the orb) adds to it. A dream is capped at 5 minutes: the pill
counts down the last 30 seconds, then the recording stops and the text is kept. Start and stop
have haptics.

Manual interruption checklist (device): incoming call mid-sentence; Siri; alarm; Home button /
swipe up; lock button; Control Center (keeps recording); airplane mode on the Record screen
(keeps recognizing on devices with the on-device model); 5-minute limit.

Drafts (`Services/DraftQueue.swift`, SwiftData in Application Support/Dreamer with complete file
protection): every told dream is saved as a draft before it is sent, with the `clientId` the record
flow generated for it, and removed once the backend has it. Offline, Analysis says "Saved on your
iPhone" and Home shows how many dreams wait; `flush` sends them when the connection comes back,
at launch and after sign-in. Resending the same `clientId` returns the same dream, so nothing is
duplicated. Rate limits wait until `resetAt`, other failures back off per draft; the paywall and
offline stop the flush. Sign-out and account deletion clear the drafts. File protection shows only
on a device (the simulator has no Data Protection): check it in the device QA.

Server transcription fallback (`Services/ServerTranscription.swift`, flag `serverSttFallback`, on by
default): while the flag is on, the recording is also written to an m4a (AAC, 16 kHz mono, about
2 MB for five minutes) in a protected temporary folder. If the iPhone cannot recognize the language,
the Record screen says "your words will appear when you're done" and records audio only. A
recognizer that fails mid-dream switches to audio only too. At "I'm done" with no text, the audio
goes through `POST /v1/recordings/upload-url` and a presigned PUT, and the file is deleted as soon
as the upload succeeds. Then `POST /v1/recordings/{id}/transcribe` returns the text, and the dream
is sent with that `recordingId`. The backend deletes the audio after the first transcribe call
whatever the result, so only the upload can be retried. A failed transcription (provider
unavailable, the 20-a-day limit) asks the user to type. When there is live text, the audio is
deleted and never sent. Recordings are also deleted when the flow is closed, and at launch in case
the app crashed mid-flow. Debug: `-noLiveText` with `-debugScreen record` shows the fallback with a
mock server.

## Reminders and notifications

`Services/Reminders.swift`: the first Home after onboarding offers the morning reminder once,
with `ReminderPrePrompt` ("Remind me" or "Not now"), a translucent modal over Home, before the
system alert. Pushes need that permission too: once it is given and the user is signed in, the app
registers with APNs and sends the token to `POST /v1/devices` at every launch. Settings turns it on
or off and asks for the permission when it was never asked. `ReminderPlanner` works out the next 7
mornings at the chosen local time. Each has its own words from a gentle rotation, the first one
mentions a streak of 2 or more mornings, and today is skipped once a dream is told. It also
schedules the reminder the paywall promises: 2 days before a renewing trial turns paid
(`EntitlementState.isTrial`). `ReminderController` plans them again whenever the app becomes
active, the settings, the journal, the account or the trial change, and when the time zone
changes, so 7:30 stays local after travel. Tapping a notification goes through `AppDelegate`
(`UNUserNotificationCenterDelegate`) and `NotificationRouter`, which also works on cold start, to
`AppState.handle(_:)`: the reminder opens Record, a push about a dream opens it, and the trial
reminder opens Settings. Debug: `-askReminder` with `-debugScreen home`.

Pushes (IOS-07.2, `Services/PushDevices.swift`): once the user allows notifications and has an
account, the app asks APNs for a token. `PushDevices` registers it with
`POST /v1/devices {token (hex), environment}`, once per account and token; `environment` follows
the build's `aps-environment`, which is sandbox in Debug and production in Staging/TestFlight and
Release. Sign-out removes the token with `DELETE /v1/devices` before the logout, while the session
still works; account deletion removes it on the server. The backend's pushes (`interpretation_ready`,
`image_ready` with `dreamId`) open that dream from a warm or cold start and send
`push_opened {type}`. The open app does not show them, because the screen already shows the
dream. Real pushes need the APNs key on the backend and a device (see Blockers).

## Settings sync and journal lock

The morning reminder, its time and night mode are part of the account (IOS-07.3). A change in
Settings is queued in `AppState.unsyncedProfile` and sent with `PATCH /v1/me` (see Lenses and
notes), and so is the time zone after travel. A profile applied from the server is never sent
back. The Face ID lock is this device's choice only.

"Lock journal with Face ID" (`Services/AppLock.swift`): turning it on asks for Face ID, Touch ID
or the passcode first, so nobody locks themselves out, and an iPhone without either is told how
to set one up. While it is on, the app opens covered by `LockScreen` and asks at once, locks
again whenever it goes to the background, and hides its content in the app switcher. The
passcode is the fallback (`deviceOwnerAuthentication`). `NSFaceIDUsageDescription` is in
Info.plist. Debug: `-lockJournal`.

## Feature flags

`Services/FeatureFlags.swift` lists the remote switches with their code defaults, chosen so the
app works fully offline: `ttsEnabled` (on), `attestationEnforced` (off), `serverSttFallback` (on),
`imageGenerationEnabled` (on, image kill switch). With a PostHog key the values come from PostHog
feature flags with the same keys. A session always uses the flags cached on the previous launch
and refreshes the cache in the background, so a change applies on the next launch and never flips
a feature mid-use. Debug builds accept overrides: `-featureFlag ttsEnabled=false`.
The paywall variant is not a flag: the backend assigns it (`GET /v1/subscription.paywallVariant`).

## Analytics

`Services/Analytics.swift` is the only place with event names, properties and their allowed values.
All of them are the client-owned events of `../dreamerweb/docs/tracking-plan.md`, with numbers and
booleans kept typed. With `POSTHOG_API_KEY` set, `PostHogAnalytics` sends them to PostHog;
otherwise, and in mock mode, they only go to the debug log. After sign-in the user is identified by
the backend user id, the same distinct id the server uses, and at sign-out the identity is reset.
Every event carries `preferred_lens` and `paywall_variant` as super properties. Screens report
screen views with `.trackScreen(...)`. Automatic lifecycle and screen capture stay off. Dream text,
titles, notes, emails and names are never properties (`AnalyticsTests` checks the keys against the
backend's forbidden list). Mappings to the plan's values: the paywall's gate and onboarding
placements count as `onboarding`, Record and Analysis as `limit`; the voice switched off by the
flag counts as `tts_unavailable`. The account step of onboarding is not in the plan yet and is not
sent (see Blockers).

## Attribution

`Services/Attribution.swift`: `AttributionService` starts install attribution once per launch,
gets the backend user id at sign-in (`nil` at sign-out), and hands the MMP's install id to
RevenueCat (`$appsflyerId` / `$adjustId`, plus `collectDeviceIdentifiers()`). This lets
RevenueCat's server-side integration send trial_start and purchase to the MMP, so the app never
sends revenue events itself. Until the MMP (AppsFlyer or Adjust) and its dev key are chosen,
`NoopAttribution` is used and nothing is attributed (see Blockers). The chosen SDK plugs in behind
the protocol, and its key goes into `Secrets.xcconfig`.

Ad networks (IOS-08.3): the Meta SDK (with Aggregated Event Measurement) and the TikTok Events SDK
plug in as `AdNetworkSDK`s. `MeasurementStack` starts them with the attribution once per launch
and passes on the user's tracking answer. Trials and purchases reach Meta and TikTok through the
MMP, and SKAN conversion values follow the MMP's schema. None of them is registered until the
Meta App ID and client token, the TikTok App ID and the SKAN schema exist (see Blockers). Their
SKAdNetwork ids go into Info.plist together with the SDKs.

## Tracking consent (ATT)

`Services/TrackingConsent.swift`: the App Tracking Transparency question is asked once, at a moment
set by the `attAfterFirstDream` flag. With the flag off (the default) it comes on the first Home
after onboarding, before the reminder offer; with it on, after the first interpretation. Our
explanation comes first (`TrackingPrePrompt`, a card in a translucent modal over Home with a
single "Continue"), then the system alert. The answer is sent as `att_response {status}` and passed to every measurement SDK through
`MeasurementStack`. With an earlier answer, or on a restricted device, measurement starts at
launch. Otherwise nothing starts until the user has answered, so no SDK can use the IDFA before
the user could refuse. A refusal changes nothing else in the app. `NSUserTrackingUsageDescription`
is in Info.plist. Debug: `-askTracking` with `-debugScreen home` (mock mode otherwise counts as
answered "no").

## App Attest

`Services/AppAttest.swift` proves to the backend that requests which cost money come from the real
app. These are the protected operations: `createDream`, `retryDream`, `regenerateImage`,
`requestDreamAudio`, `recordingUploadUrl` and `transcribeRecording`. Each account has one key.
`AppAttestor` generates it, gets `POST /v1/attest/challenge`, attests it with
`clientDataHash = SHA256(challenge)`, and registers it with `POST /v1/attest/keys`, only once even
when requests race; the key ids are kept in the Keychain. `AttestationMiddleware` sits inside the
retry, so each attempt gets a fresh assertion because the counter only goes up. It adds
`X-App-Attest-Key-Id` and `X-App-Attest-Assertion` = base64 of
`generateAssertion(SHA256("<METHOD> <path?query>\n" + body))` over the exact bytes it sends. A lost
key is replaced. In soft mode (the `attestationEnforced` flag off, as the backend is now) a device
that cannot attest, like the simulator, sends without the headers. With the flag on it stops
before sending. Registration uses a separate client, so the attested client never waits on
itself. The check against staging with enforcement on needs a TestFlight build and the App
Attest capability (see Blockers).

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

Release health (IOS-08.5): session tracking is on, so Sentry shows crash-free sessions and users
per release (`bundle id@version+build`) and per environment. API failures that point to a bug or
an outage are sent as non-fatal issues grouped by endpoint and code (`ErrorReportingMiddleware`,
after retries): 5xx, `VALIDATION_FAILED`, `ATTESTATION_REQUIRED`, `CONFLICT`, and answers the app
cannot read (reported by `APIClient`, meaning the contract drifted). Offline, sign-in, paywall,
limit and not-found answers are normal and are not reported. A report carries the operation id
and the code only, never the URL, the body or a header.

Alerts are configured in Sentry (project settings, not app code). Set them up once the project
and its DSN exist (see Blockers):
1. Alerts -> Create alert -> Issues: "A new issue is created" and "The issue changes state from
   resolved to unresolved", filtered to `level:fatal` and to `environment:production`
   (a second rule for `staging`). Action: send a notification to the Telegram integration (or to
   the team's email), with the action interval at 5 minutes so a test crash alerts within 15.
2. Alerts -> Create alert -> Sessions: "Crash free session rate" below 99.5% over 1 hour for
   `environment:production`, warning at 99.8%, with the same action.
3. Alerts -> Create alert -> Issues: "Number of events in an issue is more than 50 in 1 hour" with
   the filter `error_code` present, to catch an API endpoint failing for many users.
4. Dashboards -> Release health: the widgets "Crash free sessions by release" and "Top non-fatal
   issues by error_code" make the stability dashboard per version.
Check the setup with a TestFlight build: launch it with `-crashTestCrash` (Staging), relaunch, and
the alert should arrive within 15 minutes.

## App Store screenshots

`bundle exec fastlane screenshots` builds Debug, installs it clean on the iPhone 17 Pro Max
simulator, sets the status bar to 9:41 with full battery, and opens each screen of
`fastlane/screenshots.json` with `-debugScreen` on mock data (`-day -debugTime 07:30`). It then
takes the screenshots and captions them with `scripts/frame_screenshots.py` (the design's sky, the
Cormorant Garamond, the app's font, and the text colour). The result is 6.9" (1320 x 2868) and 6.5" (1284 x 2778)
images in `fastlane/screenshots/en-US`, which is git-ignored and regenerated at every design
change. `bundle exec fastlane upload_store` sends the metadata and the screenshots to App Store
Connect with `deliver`, without a binary. It needs the App Store Connect API key (see Blockers).
To change the story, edit the screens, waits and captions in `screenshots.json`.

## App Review

`fastlane/metadata/review_information/notes.txt` holds the notes for App Review, which deliver
uploads. They cover:
- sign-in with Sign in with Apple: the reviewer's own Apple ID works, so no demo account is
  needed;
- the subscription group, with sandbox purchases and Restore;
- a sample dream to paste through the keyboard, to reach an interpretation without speaking;
- how AI content is framed, including the crisis support screen;
- every permission, and account deletion.
`bundle exec fastlane review_video` records the scenario on mock data (Home -> Record -> Details
-> Analysis -> Interpretation, about 30 s) into `fastlane/review/demo.mp4` (git-ignored), to attach
in App Store Connect. The contact details of the review and whether a demo account is wanted
anyway are Tony's to fill in (see Blockers).

## Data on the device

Everything with dream content has complete file protection (unreadable while the phone is
locked):
- the SwiftData store (drafts, journal, dreams in full) in Application Support/Dreamer;
- `insights.json`;
- the dream image cache;
- recordings waiting for upload.
Tokens and App Attest key ids live in the Keychain
(`AfterFirstUnlockThisDeviceOnly`). API answers are never written to the shared URL cache
(`urlCache = nil`, no cookies). Media behind presigned links download through an ephemeral
session, and the app keeps its own protected caches. Sign-out and account deletion empty all of
them: journal, drafts, image cache, insights, recordings, URL cache, SDK identities. Nothing is
printed. The only `os.Logger` lines are an analytics debug line in Debug builds (event names and
enum values) and a write failure without details. There are no ATS exceptions and no plain
`http://`. `PrivacyGuardTests` fails the build when any of this regresses. To check a device:
`log stream --device --predicate 'process == "Dreamer"'` while telling a dream and signing in by
email; neither the dream text nor the email may appear.

## Privacy manifest

`Dreamer/Resources/PrivacyInfo.xcprivacy` declares:
- no tracking (it becomes true with the MMP and ad SDKs, which bring their tracking domains);
- the data the app collects, which matches docs/app-store-connect.md;
- the required-reason APIs: UserDefaults for its own preferences (CA92.1), and system uptime to
  pace the recording waveform (35F9.1).
RevenueCat, PostHog and Sentry include their own manifests. Organizer's Privacy Report of an
archive combines them and must match the App Privacy answers.

## App Store Connect

`docs/app-store-connect.md` lists everything the App Store Connect record needs: the app record,
the subscription group with localized names and the review screenshot (`fastlane/review/paywall.png`
from `fastlane screenshots`), the age-rating answers, export compliance
(`ITSAppUsesNonExemptEncryption` = NO) and App Privacy, all taken from what the code does. Entering
them in App Store Connect waits for Tony's "yes"; the open values are in the Blockers.

## App icon

`AppIcon` is a single 1024 image with the iOS 18 appearances: the light artwork, a dark variant
(the same rings, orb, crescent and star on the night palette) and a tinted variant (light glyphs on
transparency, which iOS tints). `scripts/make_icon_variants.py` draws the dark and tinted variants,
so rerun it when the final icon changes. Debug and Staging use `AppIcon-Staging`. To check them,
long-press the Home Screen on a device, choose Edit -> Customize, and switch Light, Dark and
Tinted; also look at Spotlight and Settings.

## App Store metadata (ASO)

`fastlane/metadata/en-US` holds the listing: name `Dreamer: AI Dream Journal`, subtitle
`Dream meaning & psychology`, keywords, promotional text, description and release notes.
`upload_store` sends them. The positioning is a dream journal with psychology, not fortune
telling (App Review 4.3): the words "fortune", "horoscope", "predict" and "psychic" are
deliberately absent. The keywords (up to 100 characters, commas, no spaces, none repeating a
word of the name or subtitle, which Apple already indexes) cover the searches around the core
terms "dream journal", "dream interpretation" and "dream meaning": interpreter, analysis,
dictionary, symbols, diary, sleep, lucid, tracker, recall, nightmare, jung, reflection. The
description repeats the auto-renewal terms App Review asks for. Still open (see Blockers): the
primary and secondary category, the support, marketing and privacy URLs, the copyright holder,
and Tony's approval of the texts and keywords.

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
  App/            DreamerApp, AppDependencies (composition root), AppState, RootView, AppConfig,
                  links and notifications routing, debug launch
  API/            openapi.yaml (normalized copy of the contract), generated client config, APIClient
                  + endpoints and mapping to domain models, middlewares (retry, auth, errors,
                  reporting), SSE
  DesignSystem/   Tokens (Theme), motion, glass material, sky, reusable components
  Models/         Sendable value types (Dream, Lens, Emotion, Plan, Route, remote models, ...)
  Services/       Protocols + live implementations (API, SDKs, system frameworks) and Mocks/
  Features/       One folder per screen: <Screen>View + <Screen>ViewModel; Shared/ for common UI
  Resources/      Asset catalog, fonts, Localizable.xcstrings, PrivacyInfo.xcprivacy
DreamerTests/     Swift Testing: view models, services on stubbed network, contract examples
DreamerUITests/   XCUITest: critical scenarios and accessibility audits
```

- **Views** only render and forward user intents, with design-system tokens only (no ad-hoc hex
  values or font sizes).
- **View models** are `@MainActor @Observable` classes that own screen state and talk to services
  through protocols. They take their dependencies explicitly, so tests need no UI.
- **AppState** holds session state (account, onboarding, lens, subscription, reminders, tab and
  navigation paths, queued profile changes) and persists preferences through `PreferencesStore`.
- **AppDependencies** is the composition root, injected with `.environment(_:)`. `live()` picks
  live or mock services once per launch (see below).
- **Navigation**: `OnboardingFlowView` (one screen for the intro and quiz, pushes to the account
  and the paywall); `MainTabView` keeps one `NavigationStack` per tab
  with typed `Route` paths in `AppState`; Record -> Details -> Analysis is a `fullScreenCover`, and
  on finish the Interpretation is pushed on the Today stack. Notification taps go through
  `NotificationRouter` to `AppState.handle(_:)`.

## Live vs mock services

`AppDependencies.live()` uses the live services when the build has an API host, which Debug and
Staging do. It uses the mocks with `-mockServices`, with `-debugScreen` (unless `-liveServices`),
and in builds without a host (Release until the production domain exists). Previews and unit
tests always use mocks.

| Service | Live | Mock |
|---|---|---|
| Auth, profile, subscription status | Backend (`APIAuthService`, `APIProfileService`, ...) | Always signs in, fixed profile |
| Dream analysis | `POST /v1/dreams` + SSE, polling fallback | 4 steps, sample interpretation streamed |
| Journal, insights, library | `CachedDreamStore` (SwiftData), `InsightStore`, `APISymbolCatalog` | Seeded dreams and symbols, computed insights |
| Speech-to-text | On-device `SFSpeechRecognizer`, server fallback | Types the sample transcript |
| Read aloud | Backend ElevenLabs voice, system voice fallback | System voice |
| Images, share card | Backend presigned links, protected cache | Asset catalog |
| Purchases | RevenueCat (with a key), else StoreKit 2 on the local `.storekit` | Succeeds after 0.8 s |
| Analytics, flags, crashes | PostHog, Sentry (with keys) | Debug log, code defaults |
| Attribution, ad SDKs | Protocols ready, none registered yet (blockers) | - |
| Reminders, Face ID, App Attest, push | System frameworks | Same (App Attest skipped on the simulator) |

## Debug: open any screen directly

Debug builds accept launch arguments (in `DebugLaunch.swift` and next to the services they
change); none of them is compiled into App Store builds.

```
./run.sh screen:interpretation
xcrun simctl launch booted com.braincode.dreamer.io -debugScreen journal -night
```

| Argument | Effect |
|---|---|
| `-debugScreen <name>` | Opens `welcome recordIntro understand quizGoal quizLens account paywall home journal library settings deleteAccount interpretation support symbol record details analysis paywallSheet` on mock data |
| `-mockServices` / `-liveServices` | All mocks for a normal launch / the backend for a debug screen |
| `-night`, `-day` | Force the appearance |
| `-debugTime HH:mm` | Today at that time for the Home greeting |
| `-offline` | Shows the offline banner |
| `-noLiveText` | Recording without live text, written down by a mock server |
| `-imagePending` | The dream image is painted during the first seconds |
| `-askTracking`, `-askReminder` | Show the tracking question / the reminder offer |
| `-lockJournal` | The Face ID lock is on |
| `-micPermission notDetermined\|denied\|restricted` | Microphone permission states |
| `-featureFlag name=true\|false` | Overrides a remote flag |
| `-debugAdvance` | The onboarding taps "Continue" by itself every 2.5 s, up to the account step |
| `-premiumRequired` | The mock backend refuses a dream with PREMIUM_REQUIRED (the analysis screen's paywall state) |
| `-openLink <url>` | Opens a link at launch as if the system had routed it (`./run.sh link:"<url>"`), for sign-in links Safari keeps |
| `-uiTesting`, `-uiTestOpenEmailLink` | UI tests: fresh preferences; the mock "opens" the sign-in link |
| `-crashTestNonFatal`, `-crashTestCrash` | Sentry checks (Debug and Staging) |

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

## Screen sizes and localization

All screens were checked on an iPhone SE (3rd generation, 375 x 667 pt; a simulator named
"Dreamer SE") and on the 6.9" Pro Max (App Store screenshots). On the SE, the Details sheet now
lets the transcript's top space give way first and scrolls when it still does not fit, so "Skip"
is never cut off. The onboarding pages, paywall and settings were already scroll views.

Strings are ready for translation in `Dreamer/Resources/Localizable.xcstrings` (source language
English, about 190 strings). SwiftUI `Text` literals are extracted by the compiler, and the copy
built in view models and models is `String(localized:)`: errors, captions, reminders, lens and
emotion names, paywall terms. After changing copy, build Debug for a simulator and run
`scripts/sync_strings.sh`, which updates the catalog and marks number-only keys as not to
translate. Xcode does the same when the catalog is open. To add a language, add it in the
catalog; the build then ships its `.lproj`.

## Performance

`docs/performance.md` covers IOS-10.1: what changed, with before and after numbers.
- Looping animations pause off screen and in the background.
- Long lists use `lightweightGlass`, with no live blur per card.
- Images decode at their display size (`ImageDownsampler`).
- `LaunchMetrics` logs the time to the first frame in Debug and Staging builds.
It also describes the Instruments checks that need an iPhone 12.

## Accessibility and motion

All loops (orb breathing, sky drift, waveforms, sparkles, thumbs) run on `TimelineView` and freeze
with Reduce Motion; entrance animations are skipped too. Icon-only buttons have labels, Dynamic Type
is capped at `.xxLarge`, and screens scroll on small devices (iPhone SE).

Accessibility check (IOS-10.2):
- Screenshots of every main screen at the largest supported size
  (`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryXXL`) show no clipped text. Key
  symbol cards widen with the text (`@ScaledMetric`), so no word breaks in the middle.
- The custom switch reads as a switch (`.isToggle`), the selected tab is marked selected, and the
  sign-in error card offers a "Dismiss" action.
- With Increase Contrast, white titles on the sky get a denser shadow.
- Reduce Motion stops every looping animation and entrance (`LoopingView`, `EnterUp`, the image
  reveal).
- Manual VoiceOver run of onboarding -> Record (keyboard) -> Interpretation: every icon button
  has a label and the steps of Analysis are read with their state. UI tests (IOS-11.2) add
  `performAccessibilityAudit()` on the same screens.

## Before release

See `docs/release.md` for the release itself. What is still open is listed as blockers in
`../../Dreamer-iOS-Tasks/PROGRESS.md`: the production domain, keys, accounts, legal URLs in
`AppLinks`, the final icon and approvals.
