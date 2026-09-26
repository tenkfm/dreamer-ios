fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios sim

```sh
[bundle exec] fastlane ios sim
```

Build the app and run it in the simulator

Options: device (simulator name), screen (debug start screen, e.g. journal), reset (true = clean install),

configuration (Debug, Staging or Release)

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

App Store screenshots: each screen of fastlane/screenshots.json opened with -debugScreen on

mock data, with a clean status bar, then captioned by scripts/frame_screenshots.py

### ios review_video

```sh
[bundle exec] fastlane ios review_video
```

A short screen recording of the review scenario (Home -> Record -> Details -> Analysis ->

Interpretation) on mock data, for the App Review notes: fastlane/review/demo.mp4

### ios upload_store

```sh
[bundle exec] fastlane ios upload_store
```

Upload the metadata (fastlane/metadata) and screenshots to App Store Connect, no binary

Needs the App Store Connect API key (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_CONTENT)

### ios ui_test

```sh
[bundle exec] fastlane ios ui_test
```

UI tests of the critical scenarios (mock services), 'Dreamer UITests' scheme

Options: device (simulator name), iterations (repeat until the first failure, e.g. 10)

### ios test

```sh
[bundle exec] fastlane ios test
```

Run the unit tests in the simulator

Options: device (simulator name)

### ios build_release

```sh
[bundle exec] fastlane ios build_release
```

Compile the Release configuration for devices without signing (CI check that the App Store build builds)

### ios certificates

```sh
[bundle exec] fastlane ios certificates
```

Download (or, with readonly:false, create) certificates and profiles with match

Needs MATCH_GIT_URL, MATCH_PASSWORD, APPLE_TEAM_ID and the App Store Connect API key variables

### ios signed_build

```sh
[bundle exec] fastlane ios signed_build
```

Archive a signed build with match profiles: configuration Staging (default) or Release

### ios beta

```sh
[bundle exec] fastlane ios beta
```

A signed build to TestFlight. The build number is TestFlight's latest + 1

Options: configuration (Staging, default, or Release); external:true also sends it to the external

group 'Beta' for Apple's beta review - only after Tony's explicit yes

### ios release

```sh
[bundle exec] fastlane ios release
```

The App Store version: a signed Release build (build number = TestFlight's latest + 1), uploaded

with the metadata and screenshots of fastlane/. Never submits unless submit:true - Tony's yes first

### ios upload_dsyms

```sh
[bundle exec] fastlane ios upload_dsyms
```

Upload the dSYMs of the last build to Sentry (SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_PROJECT; needs sentry-cli)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
