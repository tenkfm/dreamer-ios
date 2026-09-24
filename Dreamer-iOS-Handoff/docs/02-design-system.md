# 02 - Design system

All values are in points (the designs are 390 x 844 CSS px = pt 1:1).
Swift implementations of the tokens and core components are in `swift/DesignSystem/`.

## 1. Look in one paragraph

A photographic pastel morning sky sits at the top of the screen and fades into a pale blue
background (#EEF4FB). Everything interactive floats on it as frosted glass: translucent white
cards with blur, a thin white border and a soft blue shadow. Type is a rounded, light sans
(Quicksand) with medium-weight titles; the logo is an elegant serif italic. Accents are navy
(CTA) and a warm peach sparkle. Lots of gentle, slow motion.

## 2. Colors

| Token | Hex | Use |
|---|---|---|
| `background` | #EEF4FB | Screen background, bottom of every sky fade |
| `textPrimary` | #1E2A4A | Titles, body, card text |
| `textSecondary` | #3A4666 | Subtitles under titles, secondary paragraphs |
| `textTertiary` | #4B587A | Captions, dates, "See all", small descriptions |
| `overline` | #3D4A6B | Uppercase overlines (e.g. YOUR MORNING INSIGHT) |
| `icon` | #5670A3 | Icons in glass buttons and rows |
| `iconSoft` | #7FA2DC | Mic / moon glyph inside white orbs, waveform bars |
| `accent` | #3F5E9C | Active page dot, active tab icon |
| `cta` | #2E4677 | Primary buttons, radio fill, switch on, player button |
| `peach` | #F2A488 | Sparkle glyph, small accent dots |
| `tabInactive` | #8392B4 | Inactive tab label/icon |
| `segmentInactive` | #5B6785 | Inactive segment label |
| `destructive` | #B4453C | "Delete account and all dreams" |
| `recordDot` | #E9826A | Pulsing dot in the "Recording" pill |
| `white` | #FFFFFF | Logo, selected segment/tab pill, orb, secondary pill buttons |

Emotion colors (chips, legend, distribution bar), text on them is `textPrimary`:

| Emotion | Hex |
|---|---|
| Anxiety | #F8CFB2 |
| Confusion | #DCD3F8 |
| Calm | #C4E2F4 |
| Joy | #F9DF98 |
| Fear | #F6C1C1 |

Shadow color everywhere: rgb(80, 110, 170) at the given opacity (a soft blue, never black).
CTA shadow: rgb(46, 70, 119).

## 3. Typography

Fonts: **Quicksand** (UI, all text) and **Cormorant Garamond Italic** (logo only).
PostScript names: `Quicksand-Light`, `Quicksand-Regular`, `Quicksand-Medium`, `Quicksand-SemiBold`,
`Quicksand-Bold`, `CormorantGaramond-MediumItalic`, `CormorantGaramond-SemiBoldItalic`.

Type scale (size / line height / weight / tracking):

| Style | Size | Line | Weight | Tracking | Use |
|---|---|---|---|---|---|
| `logoLarge` | 44 | 52 | Cormorant SemiBold Italic | 0 | Welcome logo |
| `logo` | 28 | 36 | Cormorant SemiBold Italic | 0 | Logo in headers |
| `display` | 26 | 32 | Medium 500 | -0.3 | Screen titles (onboarding, quiz, interpretation) |
| `title` | 24 | 30 | Medium 500 | -0.2 | Home greeting, Journal/Library/Settings headers |
| `heading` | 18 | 24 | Medium 500 | 0 | Section titles ("Dreamed about today", "Other perspectives") |
| `bodyStrong` | 15 | 21 | Medium 500 | 0 | Card titles, list row titles, option titles |
| `body` | 15 | 21-23 | Regular 400 | 0 | Paragraphs (interpretation text uses 23 line height) |
| `button` | 16 | - | Medium 500 | 0 | Primary CTA |
| `link` | 14 | - | Regular 400 | 0 | Secondary text buttons, segments, chips |
| `secondary` | 13 | 18 | Regular 400 | 0 | Subtitles, captions, option descriptions |
| `label` | 12 | 16 | Regular 400 | 0 | Pills, small buttons, thumb captions |
| `small` | 11 | 14 | Regular 400 | 0 | Tab labels, week day letters, tiny chips |
| `overline` | 11 | 14 | Medium 500 | 1.4 | Uppercase overlines |

Rules: titles are Medium, never Bold/SemiBold. White text over the sky (logo, "Skip", quiz
counter, onboarding tagline) gets a soft shadow: rgb(70,110,180) 35-40% opacity, radius 8-14, y 1-2.

The designs had a runtime font tweak (Nunito / M PLUS Rounded / Comfortaa / Outfit / Urbanist and
Thin/Light/Regular weights). The chosen default is **Quicksand + "Light" set** (the table above).
Implement fonts through one `DreamerFont` enum so the family can be swapped in one place.

## 4. Spacing, radii, sizes

- Screen side margin: **22** (cards, headers); CTA block and onboarding text: **24**; long text blocks on onboarding: **32**.
- Vertical gap between stacked cards: 10-14; between sections: 22.
- Glass card padding: 16-18; list rows: 14 x 16.
- Radii: card 22-26 (default 24), small tile 16, thumbnails 16, chips/pills/buttons fully rounded (capsule), sheet top 32.
- Primary button: height 56, capsule. Secondary text button: height 40.
- Round glass icon button: 46 x 46, icon 20-22, placed 22 from the side, top at safe area + ~10 (64 pt from screen top in the design).
- Tab bar: floating capsule, height 62, inset 26 left/right, 24 above the bottom edge (top at 758 on 844).
- Touch targets never below 44 x 44.

## 5. Glass material (the core look)

```
fill:    white @ 36% opacity
blur:    background blur ~14 (SwiftUI: .ultraThinMaterial under the white fill, or a custom blur)
border:  1 pt white @ 70% (inside stroke)
shadow:  rgb(80,110,170) @ 12%, radius 28, y 10   (CSS 0 10px 28px)
```

Variants:
- **Tab bar glass**: white @ 42%, blur 16, border white @ 75%, shadow @ 16%, radius 30, y 12.
- **Selected card** (radio cards, plans): white @ 82%, border 1.5 pt pure white, shadow @ 18% radius 28 y 12.
- **Unselected option card**: white @ 36%, border white @ 70%, shadow @ 8% radius 22 y 8.
- **Inner soft fill** (icon circles inside cards, player bar): white @ 60-70%, no border.

SwiftUI approach: `RoundedRectangle.fill(.ultraThinMaterial)` often looks too grey on this
palette. Preferred: `.background { shape.fill(Color.white.opacity(0.36)).background(.ultraThinMaterial.opacity(0.6), in: shape) }`
then `.overlay(shape.strokeBorder(.white.opacity(0.7), lineWidth: 1))` and `.shadow(...)`.
Tune against the screenshots: the card must read as light, airy and slightly see-through, not grey.

## 6. Sky backgrounds

Two variants, both `SkyBackground` in the starter code:

- **Top sky** (`SkyTop`, 390 x 300): image pinned to the top, scaled to fill, with a slow drift
  (see motion). A fade from y 150 to y 380: clear -> white-blue @ 60% (at 45%) -> `background`.
  Used by Home, Quiz 1-2, Journal, Library, Settings, Analysis.
- **Full sky** (`SkyTall`, full screen): image fills the whole screen; fade from y 470 to bottom:
  clear -> @75% (at 35%) -> `background` (at 70%). Used by Welcome, Onboarding 2-3, Paywall, Record.
- Interpretation: hero image 380 high (the dream image, placeholder `SkyTall`) with a 200 pt fade at its bottom.

## 7. Components

Each exists in `swift/DesignSystem/Components.swift` (starter) unless marked "build".

| Component | Spec |
|---|---|
| `GlassCard` | Container modifier `.glassCard(radius:)` with the glass material above |
| `GlassIconButton` | 46 circle, glass, icon `icon` color 20-22 pt stroke 1.7. Back, Close, Settings, Moon, Share, Download, Search |
| `PrimaryButton` | Capsule 56 high, `cta` fill, white `button` text, optional leading icon, shadow rgb(46,70,119) @30% radius 30 y 14, press scale 0.95 |
| `TextLinkButton` | 40 high, `link` style, `textPrimary` |
| `PillButton` | White capsule 30-32 high, 12 pt label, shadow @15% r12 y4 ("See the pattern", "Make this my main lens") |
| `OrbButton` | White radial-gradient circle (#FFFFFF -> #F6F9FE 70% -> #E9F0FA) with 2 breathing concentric glass rings. Sizes: Home 150 frame / 92 orb, Welcome/Onboarding 170 frame / 98 orb (inset 36). Glyph `iconSoft` |
| `Logo` | "Dreamer" in logo style, white, blue shadow |
| `PageDots` | 3 dots: active 26 x 8 capsule `accent`, inactive 8 x 8 `accent` @25%, gap 8 |
| `ProgressCapsule` | 6 high, track white @55%, fill `cta`, grows on appear; label "1 of 2" white 12 |
| `RadioOptionCard` | Option card (see glass variants) with optional 38 icon circle, title `bodyStrong`, optional description `secondary`, radio 22: off = 1.5 pt ring rgb(90,110,150)@45%, on = 7 pt `cta` ring |
| `PlanCard` | RadioOptionCard with price on the right (`bodyStrong`) and optional peach badge ("7 days free") |
| `Chip` | Capsule 38 high, padding 16, `link` text. Off: white @60% + 1 pt border rgb(90,110,150)@25%. On: emotion color fill + same-color border. Small variant 24-26 high, 11-12 pt text (emotion tags) |
| `SegmentedControl` | Glass capsule track with a white sliding pill (spring), segments 36-38 high, `link` text, inactive `segmentInactive` |
| `DreamerToggle` | 50 x 30 capsule, on `cta`, off rgb(90,110,150)@30%, 24 white knob with shadow, bouncy spring |
| `SettingsRow` | min 54 high row inside a glass group: 20 icon `icon`, title `body`, trailing value `secondary` + chevron, or toggle |
| `WeekStrip` | 7 circles 38: empty = 1.5 pt ring rgb(130,150,190)@45%; done = white fill + check `icon` + shadow; day letter 11 below |
| `InsightCard` | Glass card: peach 4-point sparkle (twinkling), overline, body text, PillButton at bottom right |
| `DreamThumb` | 84 x 94 image radius 16 + 12 pt caption; floats slowly |
| `SymbolCard` | 150 wide glass tile: 34 icon circle, `bodyStrong` title, 12 pt meaning |
| `VoicePlayer` | See Interpretation in doc 03: 44 play/pause circle `cta`, 24 waveform bars 3 x 26 `iconSoft`, 3 pt progress bar, duration label with headphones icon |
| `DreamRow` | Journal row: 56 thumb radius 16, title `bodyStrong`, date `secondary` + small emotion chip, chevron |
| `TabBar` | Floating glass capsule with 3 tabs (Today / Journal / Library). Active tab: white @95% pill with shadow, icon `accent`, label `textPrimary`; inactive: `tabInactive`. Tab = icon 24 over label 11, pill 50 high radius 26. Sliding pill uses matchedGeometryEffect |
| `BottomSheet` | Details: fill rgb(247,250,254) @ 92%, blur 20, top radius 32, shadow rgb(60,90,150)@20% radius 40 y -12, grabber, slides up 0.7 s ease-out |

Icons: the designs use simple 24-grid stroke icons (stroke 1.7-2, round caps/joins).
Use SF Symbols equivalents: gearshape, moon, mic, chevron.left, xmark, square.and.arrow.up,
arrow.down.to.line, magnifyingglass, house, book.closed, square.grid.2x2, checkmark, sparkle,
keyboard, headphones, play.fill, pause.fill, bell, clock, lock, crown, arrow.clockwise,
hand.raised, doc.text, envelope, trash. Use weight `.light`/`.regular` so they match the thin look.
The peach sparkle is a custom 4-point star shape (path in `Components.swift`).
