# Releasing Dreamer

How a build gets from `main` to TestFlight and the App Store, and how a hotfix goes out. Every
step is a command; nothing here needs the author.

Two rules come first:
- **App Store Connect, external TestFlight, App Review and RevenueCat actions happen only after
  an explicit "yes" from Tony.**
- **Only Tony pushes.** A release starts from a `main` that he pushed and that CI passed.

## Once per machine: access

Everything comes from the environment; keep the values in your shell profile or a password
manager, never in the repo.

| Variable | What |
| --- | --- |
| `APPLE_TEAM_ID` | The Apple Developer team |
| `MATCH_GIT_URL`, `MATCH_PASSWORD` | Private repo with the encrypted certificates and profiles, and its passphrase |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT` | App Store Connect API key (`ASC_KEY_CONTENT` = base64 of the .p8) |
| `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` | dSYM upload (optional, needs `sentry-cli`) |

The SDK keys go in `Config/Secrets.xcconfig`, copied from `Secrets.example.xcconfig`. CI writes
this file from its secrets. The Release build also needs `API_HOST_RELEASE`, the production
domain.

## Signing with match

```
bundle exec fastlane certificates                  # fetch the certificates and profiles (read only)
bundle exec fastlane certificates readonly:false   # create or renew them (admin, once a year or after revoking)
```

match keeps one Apple Distribution certificate and the App Store profile of the bundle id
(`com.braincode.dreamer.io`, shared by every configuration) in the match repo. Everyone uses the
same ones, so nobody creates certificates in the Developer portal by hand.

- **After adding a capability** (for example App Attest or Push): enable it on the App ID in the
  Developer portal, then run `certificates readonly:false` so the profiles include it.
- **When a certificate expires**: `fastlane match nuke distribution` (admin), then
  `certificates readonly:false`. Builds already on the App Store keep working.

## Versions

- `MARKETING_VERSION` in `Config/Shared.xcconfig` is the version users see (`1.0.0`). Raise it
  in a commit before each App Store release: the patch number for a hotfix, the minor number for
  features.
- The build number is set at build time: `beta` takes TestFlight's latest number plus one, so it
  never collides.

## 1. Before the build

On an up-to-date `main`, run each command from `Dreamer/`:

```
./run.sh test                                   # unit tests
bundle exec fastlane ui_test iterations:10      # UI scenarios, 10 times in a row
xcodebuild -project Dreamer.xcodeproj -scheme "Dreamer Staging" -configuration Staging \
  -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation build   # no Swift warnings
bundle exec fastlane screenshots                # only if the UI changed; compare with the last set
```

Check that `PROGRESS.md` has no open blocker that stops this release. For the first release that
means the production domain, the legal URLs, the keys, and the App Store Connect record
(docs/app-store-connect.md).

## 2. Internal TestFlight

```
bundle exec fastlane beta                          # Staging build: the "Dreamer β" app, staging backend
bundle exec fastlane beta configuration:Release    # the App Store app against production
```

`beta` does the whole chain:
1. Takes TestFlight's latest build number plus one.
2. Fetches the signing assets with match.
3. Archives, and uploads the dSYMs to Sentry when `SENTRY_AUTH_TOKEN` is set.
4. Uploads the build for the internal testers only (`distribute_external: false`).

Apple processes the build in 10-30 minutes; after that it appears in TestFlight for the internal
group. Then run `docs/qa-checklist.md` on 3-4 devices and triage the results in ClickUp. A Blocker
or a Critical means fixing it, running `beta` again, and rerunning the checklist for the affected
area.

External testers (beta review by Apple), only after Tony's yes:
`bundle exec fastlane beta configuration:Release external:true` sends the build to the "Beta"
group and waits for processing. The "What to test" notes come from `release_notes.txt` plus the
commits since the last tag.

From CI: Actions -> Release -> Run workflow, lane `beta`. The workflow needs the secrets named in
`.github/workflows/release.yml`.

## 3. App Store

After Tony's yes:

1. `bundle exec fastlane release` builds and signs the Release version (TestFlight's latest build
   number plus one) and uploads it with the metadata of `fastlane/metadata`. It also uploads
   `fastlane/screenshots` when a local set exists, so run `fastlane screenshots` first; without
   one, the screenshots already in App Store Connect stay. It sets manual release and phased
   release, and never submits. `release submit:true` submits as well, only after Tony's yes. From
   CI: Actions -> Release, lane `release`. `upload_store` sends the metadata and screenshots alone,
   without a build.
2. In App Store Connect, open the version and:
   - choose the Release build;
   - check the review notes (`fastlane/metadata/review_information/notes.txt`) and attach
     `fastlane/review/demo.mp4` (`bundle exec fastlane review_video`);
   - for the first version, add both subscriptions to the submission (docs/app-store-connect.md);
   - choose **manual release** and **phased release over 7 days**.
3. Submit for review.
4. When approved, release. Watch Sentry release health (crash-free sessions per version, see the
   README) and PostHog for the first day. Pause the phased release in App Store Connect if the
   crash-free rate drops below 99.5 %.
5. Tag the release commit: `git tag v1.0.0-<build>`. Tony pushes the tag.

## Hotfix

A problem in the live version:

1. **Stop the damage without a release where possible.** Remote flags switch features off for the
   next launch: `imageGenerationEnabled`, `ttsEnabled` and `serverSttFallback` in PostHog. Pausing
   the phased release stops new updates.
2. Branch from the release tag: `git switch -c hotfix/1.0.1 v1.0.0-<build>`.
3. Fix it, with a test that fails before the fix. Raise `MARKETING_VERSION` to the next patch.
4. Run the checks from step 1 (the UI tests with at least `iterations:3`), then `beta
   configuration:Release`, and a short QA pass of the affected area.
5. Submit as in step 3. For a severe problem, ask for an expedited review (App Store Connect ->
   Contact Us -> Request Expedited Review), after Tony's yes.
6. Merge the hotfix branch back into `main`.

## The first days after a release

Every morning until traffic is steady (for 1.0, until 20.11), post a short summary in the release
task:
- **Crashes**: Sentry -> Releases -> the version: crash-free sessions and users, new issues, and
  API error codes that grew (`error_code` tag).
- **Reviews and ratings**: App Store Connect -> Ratings and Reviews; answer the helpful ones.
- **Funnel**: PostHog, from install to `onboarding_step_viewed` (paywall), `paywall_viewed`,
  `purchase_started`, trial started and paid. Compare conversion by `paywall_variant` and by the
  tracking A/B (`attAfterFirstDream`).
- **Server side**: interpretation failures and latency (`interpretation_failed`,
  `interpretation_ready.latencyMs`) with the backend on call.
- **Decision**: fine, a flag to switch off, or a hotfix (below).

An App Store release cannot be rolled back. The fix is always a new version, and the flags and
the phased-release pause are what buy the time.

## dSYMs and crash symbols

`signed_build`, and therefore `beta`, uploads the dSYMs when `SENTRY_AUTH_TOKEN` is set. To upload
them later: `bundle exec fastlane upload_dsyms`, which reads the last archive in `build/archive`.
A crash without symbols in Sentry means that archive's dSYMs never went up.

## Checklist

- [ ] CI green on `main`, unit and UI tests, Staging build without warnings
- [ ] `MARKETING_VERSION` raised
- [ ] `beta` uploaded, QA checklist done, no Blocker or Critical open
- [ ] Tony's yes for App Store Connect
- [ ] Metadata and screenshots uploaded, review notes and video in place
- [ ] Submitted with manual, phased release
- [ ] Released, Sentry and PostHog watched for a day, tag created
