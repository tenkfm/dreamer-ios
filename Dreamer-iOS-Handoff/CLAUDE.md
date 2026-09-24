# Dreamer - iOS app (SwiftUI) - instructions for Claude Code

You are building **Dreamer**, an AI dream-interpretation app for iPhone, from a finished design.
This folder is the complete design handoff. Read this file first, then the docs in order.

## What to build (phase 1 = UI prototype on mock data)

A native SwiftUI app that reproduces the 14 designed screens pixel-close, with the full
navigation flow, all interactive states and the motion described in `docs/05-motion.md`.
All data is mocked locally (no backend, no AI calls, no StoreKit purchase yet) behind protocol
interfaces, so real services can be plugged in later without touching views.

## Stack and constraints

- Swift 5.10+/Swift 6, SwiftUI only (no UIKit views unless unavoidable), iOS 17.0+ deployment target.
- State: `@Observable` view models (Observation framework), one `AppState` for session-level state
  (onboarding done, chosen lens, subscription status, dreams store).
- Navigation: `NavigationStack` with a typed `Route` enum for the app, a separate linear flow for
  onboarding, `fullScreenCover` for Record, sheets/overlays as specified in `docs/04-navigation-and-state.md`.
- No third-party dependencies in phase 1.
- Portrait only, iPhone only. Light appearance only for now (night mode is a later phase).
- Design canvas = 390 x 844 pt (iPhone 14/15/16). Lay out with stacks, padding and safe areas,
  not absolute frames, so it adapts to 375-440 pt widths. Keep the designed spacing values.
- Accessibility: every icon-only button gets an `accessibilityLabel`; support Reduce Motion
  (disable looping and entrance animations when `accessibilityReduceMotion` is true);
  Dynamic Type may scale body text up to `.xxLarge` without breaking layout.

## Where things are

| Path | What |
|---|---|
| `docs/01-product.md` | Product context, users, monetization, MVP scope |
| `docs/02-design-system.md` | Colors, type scale, glass material, spacing, radii, every reusable component |
| `docs/03-screens.md` | All 14 screens: layout top to bottom, copy, states, interactions |
| `docs/04-navigation-and-state.md` | Flow graph, routes, app state, mock data models, service protocols |
| `docs/05-motion.md` | Every animation with timing and SwiftUI implementation |
| `docs/06-build-plan.md` | Milestones and acceptance criteria - work through them in order |
| `design-tokens.json` | Machine-readable tokens (same values as doc 02) |
| `screens/*.png` | Rendered screens at @2x (780 x 1688 px = 390 x 844 pt). The visual source of truth |
| `reference-html/*.html` | Original design source for each screen. Use it to read exact pt values (all CSS px = pt), paddings, shadows, copy. `asset:Name` = the asset catalog image of that name |
| `assets/Assets.xcassets` | Drop-in asset catalog: sky images, dream thumbnails, named colors |
| `fonts/` | Quicksand (Light..Bold) and Cormorant Garamond (Medium/SemiBold Italic) TTF + OFL licenses |
| `swift/DesignSystem/` | Starter Swift files for tokens and core components. Use them as the base of the design system module and extend them |

## How to work

1. Create the Xcode project `Dreamer` (SwiftUI App, iOS 17). Suggested structure:
   `App/`, `DesignSystem/`, `Features/<Screen>/`, `Models/`, `Services/`, `Resources/`.
2. Copy `assets/Assets.xcassets` into the project, add `fonts/*.ttf` to the target and list
   them under `UIAppFonts` in Info.plist.
3. Add `swift/DesignSystem/*.swift`, build, fix anything that does not compile.
4. Follow `docs/06-build-plan.md` milestone by milestone. After each screen, compare it with
   `screens/<NN>-<Name>.png` in the simulator (iPhone 16, light mode) and fix differences in
   spacing, size, weight and color before moving on.
5. When a value is not written in the docs, take it from the matching `reference-html` file.
   When the docs and the HTML disagree, the docs win (they contain deliberate fixes).

## Rules

- Use only the tokens from `DesignSystem` - no ad-hoc hex values or font sizes inside feature views.
- Titles use weight Medium (500), never Bold. Body text is Light/Regular per the type scale.
- The logo "Dreamer" is Cormorant Garamond SemiBold Italic, white, with a soft blue shadow.
- Glass cards are translucent white (36%) over the sky/background with blur, 1 pt white border
  at 70% and a soft blue shadow. Do not replace them with opaque cards.
- Copy is final English copy. Keep it verbatim, including curly apostrophes.
- Use a plain hyphen "-" in any copy or docs you write, never an em dash.
