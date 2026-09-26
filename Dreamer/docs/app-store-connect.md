# App Store Connect: what to fill in

Everything the Dreamer record in App Store Connect needs for version 1.0, prepared from the code.
Nothing here has been entered in App Store Connect: that happens after Tony's "yes"
(Dreamer-iOS-Tasks/CLAUDE.md). Values marked **Tony** are decisions or data that only Tony can
give; they are also listed under Blockers in PROGRESS.md.

## App record

| Field | Value |
| --- | --- |
| Name, subtitle, keywords, description | `fastlane/metadata/en-US` (IOS-12.2), uploaded by `fastlane upload_store` |
| Bundle ID | `com.braincode.dreamer` (Release) |
| SKU | **Tony** |
| Primary language | English (U.S.) |
| Category | **Tony**: Health & Fitness or Lifestyle |
| Privacy Policy URL | **Tony** (`AppLinks.privacy` is a placeholder) |
| Support URL | **Tony** (`AppLinks.support` is a placeholder) |
| Marketing URL | optional, **Tony** |
| Copyright | **Tony** (the legal holder) |
| Screenshots | `fastlane screenshots` (IOS-12.1) |
| App Review notes | `fastlane/metadata/review_information/notes.txt` (IOS-12.4) |

## Subscriptions

One subscription group, both products submitted with version 1.0. The product ids match
`Plan.productID` and `StoreKit/Dreamer.storekit`.

| | Group | Yearly | Weekly |
| --- | --- | --- | --- |
| Reference name | Dreamer Premium | Yearly | Weekly |
| Product ID | - | `dreamer.yearly` | `dreamer.weekly` |
| Duration | - | 1 year | 1 week |
| Introductory offer | - | Free trial, 1 week, new subscribers | none |
| Price | - | **Tony** ($39.99 in the StoreKit file) | **Tony** ($6.99 in the StoreKit file) |
| Level (upgrade order) | - | 1 | 2 |
| Display name (en-US) | Dreamer Premium | Yearly | Weekly |
| Description (en-US, max 45) | - | Every reading, image and voice, yearly | Every reading, image and voice, weekly |
| Review screenshot | - | `fastlane/review/paywall.png` | `fastlane/review/paywall.png` |

The review screenshot comes from `fastlane screenshots`, which also writes `fastlane/review/paywall.png`.

## Age rating

The suggested answers, based on the app's content. **Tony** confirms them.

| Question | Answer | Why |
| --- | --- | --- |
| Violence (cartoon, realistic, graphic) | None | The app writes no violent content itself. A dream the user tells may describe violence, but it stays in their own journal. |
| Sexual content or nudity | None | |
| Profanity or crude humor | None | |
| Horror or fear themes | Infrequent / mild | Interpretations of nightmares talk about fear. |
| Mature or suggestive themes | Infrequent / mild | Dreams about relationships and loss. |
| Medical or treatment information | None | The app gives reflection, not medical advice; see the disclaimer and the support screen. |
| Alcohol, tobacco, drugs | None | |
| Gambling, contests | None | |
| Unrestricted web access | No | |
| User-generated content shared with others | No | The journal is private. Sharing a card goes through the system share sheet. |
| Messaging or chat | No | |
| Advertising in the app | No | |

## Export compliance

`ITSAppUsesNonExemptEncryption` is `NO` in Info.plist. The app uses only exempt encryption:
HTTPS through URLSession, the Keychain, and SHA-256 hashing of the Sign in with Apple nonce and of
cache keys. It has no encryption of its own. No export documents are needed.

## App Privacy

This is what the app collects, taken from the code. The product board owns the final answers
(**Tony**).

| Data type | Collected by | Purpose | Linked to the user | Tracking |
| --- | --- | --- | --- | --- |
| Email address | Email sign-in (backend) | App functionality | Yes | No |
| Name | Sign in with Apple, first name only (backend) | App functionality | Yes | No |
| User content: dream texts, notes | Backend | App functionality | Yes | No |
| Audio data | Server transcription fallback only; deleted after transcription (IOS-04.5) | App functionality | Yes | No |
| User ID | Backend id; PostHog, Sentry and RevenueCat get the same id | App functionality, analytics | Yes | No |
| Purchase history | RevenueCat | App functionality | Yes | No |
| Product interaction | PostHog: tracking-plan events, no dream content | Analytics | Yes | No |
| Crash data, performance data, other diagnostic data | Sentry: codes and the user id only | App functionality | Yes | No |
| Other usage data | PostHog SDK (declared in its manifest) | Analytics | Yes | No |
| Device ID (IDFA) | MMP and ad networks, only after the user allows tracking (IOS-08.2 to 08.4) | Third-party advertising, attribution | No | Yes |
| Advertising data | MMP, Meta and TikTok (once integrated) | Third-party advertising | No | Yes |

The app's `Dreamer/Resources/PrivacyInfo.xcprivacy` declares its own part; RevenueCat, PostHog and
Sentry ship their manifests in their packages. Before submitting, archive in Xcode and use
Organizer -> the archive -> Generate Privacy Report: the report must match this table.

Not collected: location, contacts, photos (the app only adds images to Photos), health data,
browsing history, search history outside the app. Search queries are sent to our backend only to
search the user's own journal.
