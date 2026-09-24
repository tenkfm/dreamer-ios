# 06 - Build plan

Work milestone by milestone. At the end of each milestone: build with zero warnings, run on the
iPhone 16 simulator, compare against the PNGs in `screens/`, then continue.

## M0 - Project setup
- Xcode project `Dreamer`, iOS 17, SwiftUI lifecycle, bundle id placeholder `com.braincode.dreamer`.
- Asset catalog, fonts (+ `UIAppFonts`), `swift/DesignSystem` compiled.
- A `DesignSystemPreview` screen (debug only) showing colors, type scale and every component.
**Done when:** the preview matches doc 02; fonts render as Quicksand / Cormorant (check with `UIFont.familyNames`).

## M1 - Design system components
Implement every component from doc 02 section 7 with SwiftUI previews, including glass
variants, SkyBackground (top/full), OrbButton, TabBar with sliding pill, SegmentedControl,
DreamerToggle, Chips (wrap layout via `Layout`), VoicePlayer (UI only), EnterUp modifier.
**Done when:** each component has a preview and matches the screenshots where it appears.

## M2 - Onboarding flow (screens 01-06)
Welcome -> Onboarding 2 -> 3 -> Quiz 1 -> Quiz 2 -> Paywall with mock purchase, persisted completion,
"I already have an account" and Skip paths.
**Done when:** fresh install shows Welcome; after purchase the app opens Main on relaunch.

## M3 - Main shell + Home (07) + Settings (14)
Custom tab container, per-tab NavigationStack, floating TabBar hidden on pushed screens,
Home with all cards and animations, Settings with working toggles/pickers bound to AppState
(Default lens changes the main lens on Interpretation).

## M4 - Record flow (08-10) + Interpretation (11)
fullScreenCover flow with mock speech typing, Details sheet, Analysis progression, then
Interpretation with: main lens = preferred lens, alternatives expandable and promotable,
VoicePlayer reading the main text with AVSpeechSynthesizer (play/pause/progress, stops on disappear
and on lens swap), notes saved, ShareLink.
**Done when:** a new dream recorded from Home appears at the top of Journal.

## M5 - Journal (12) + Library (13)
Journal summary (ring, distribution bar computed from stored dreams), list -> Interpretation.
Library search filters tiles by title, category chips filter, grid -> symbol detail.

## M6 - Polish
Reduce Motion, Dynamic Type check (body up to xxLarge), VoiceOver labels, haptics,
small-screen check (iPhone SE 375 x 667: onboarding content must not clip - allow scrolling),
large-screen check (Pro Max 440 pt).

## Acceptance checklist (whole app)
- [ ] Every screen visually matches its PNG at iPhone 16 size (spacing within ~2 pt, same weights and colors).
- [ ] Only design-system tokens are used in feature code.
- [ ] Titles Medium, never Bold; logo Cormorant SemiBold Italic.
- [ ] Glass cards are translucent (sky visible through them), not grey.
- [ ] All animations from doc 05 are present and disabled with Reduce Motion.
- [ ] Chosen lens always shows as the main interpretation; two others as alternatives; promotion works.
- [ ] Listen button reads the main interpretation aloud with working pause/resume and progress.
- [ ] All services are protocols with mocks; no network calls in phase 1.
