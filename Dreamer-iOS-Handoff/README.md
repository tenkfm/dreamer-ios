# Dreamer - SwiftUI handoff

Design export of the Dreamer iOS app (14 screens, v4 light design) prepared for building with Claude Code.

## How to use

1. Unzip anywhere, e.g. `~/development/Dreamer-iOS-Handoff`.
2. Open a terminal in that folder and run `claude`.
3. Prompt: `Read CLAUDE.md and build the app following docs/06-build-plan.md, starting with M0.`
   Claude Code creates the Xcode project next to this folder (or inside `app/`), then goes milestone by milestone.

## Contents

- `CLAUDE.md` - instructions Claude Code reads automatically
- `docs/` - product, design system, screens, navigation/state, motion, build plan
- `screens/` - PNG renders of every screen (@2x)
- `reference-html/` - original design source per screen (exact values)
- `assets/Assets.xcassets` - sky images, dream thumbnails, named colors
- `fonts/` - Quicksand + Cormorant Garamond (SIL OFL)
- `swift/DesignSystem/` - starter tokens and components
- `design-tokens.json` - tokens in JSON

Note: sky and thumbnail images are @2x only (780 px wide). For release, re-export them at @3x.
