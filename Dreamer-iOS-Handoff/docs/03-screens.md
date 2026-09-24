# 03 - Screens

For every screen: reference image `screens/NN-Name.png`, exact source `reference-html/NN-Name.html`.
Positions are given top to bottom on the 390 x 844 canvas; convert fixed y offsets into
stacks + spacers relative to the safe area. All elements enter with the staggered
"enter up" animation unless said otherwise (delays listed in doc 05).

---

## 01 Welcome (first launch)

Background: full sky. Content, centered:
- Logo large "Dreamer" (44) at y 112; tagline "YOUR DREAM JOURNAL" 12 pt, tracking 2.4, white, y 168.
- Orb 170 (moon glyph, not tappable) centered at y 262-432.
- Title `display` "Your dreams are / talking to you" (line break after "are"), y 540.
- Body `body` #3A4666, centered, 32 side margin: "Tell a dream in 10 seconds after you wake up. Get a personal interpretation every morning."
- Page dots (1 of 3) y 684.
- PrimaryButton "Get started" -> 02. TextLinkButton "I already have an account" -> Home (phase 1: skip onboarding, mark done).

## 02 Onboarding - Record

Full sky. Logo 28 at top (y 70); "Skip" 13 pt white top right -> 04 Quiz.
- Orb 170 with mic glyph at y 230.
- Glass bubble (radius 22, padding 14 x 16, 36 side margin) at y 440 with a typing quote:
  "“I was back in my grandmother’s house, and the hallway kept getting longer…”" + blinking caret.
  Phase 1: type the text in character by character on appear (≈ 40 ms/char).
- Title "Catch it before it fades"; body "Say your dream out loud in 10 seconds. We write it down while you are still half asleep."
- Dots (2 of 3). "Continue" -> 03. "I already have an account".

## 03 Onboarding - Understand

Full sky. Logo + Skip as 02.
- A fanned stack of 3 dream images (center 140 x 180 radius 24; sides 130 x 160 radius 22 rotated -8 / +8 deg), each floating at a different rhythm. Under them a small glass pill with sparkle: "Stairs · Roots · A voice".
- Title "Understand it. Then see it."; body "A personal interpretation, the symbols behind it and an image of your dream."
- Dots (3 of 3). "Get started" -> 04. "I already have an account".

## 04 Quiz - Goal

Top sky. GlassIconButton back (-> 03). ProgressCapsule 50% + "1 of 2" centered between buttons at y 84.
- Title (display, centered) "What brings you to Dreamer?" at y 210.
- 4 RadioOptionCards with 38 icon circles, gap 10, from y 300: "Understand my dreams" (sparkle), "A dream keeps coming back" (stairs), "Someone keeps appearing" (heart), "Remember my dreams better" (moon). Single select, first selected by default.
- PrimaryButton "Continue" pinned to the bottom (y 760) -> 05. Store the answer in `AppState.goal`.

## 05 Quiz - Lens

Same frame as 04; progress 100%, "2 of 2".
- Title "Which lens feels closer to you?"
- 3 RadioOptionCards (title + description, no icon): Psychology / "What your mind is working through"; Spiritual / "Signs, symbols and inner guidance"; Dream book / "Classic meanings of dream symbols".
- "Continue" -> 06. Store in `AppState.preferredLens` - this drives the main interpretation.

## 06 Paywall

Full sky. GlassIconButton close (top right) -> Home without subscription only if you decide on a soft paywall; default (hard paywall): close is present but leads to Home in phase 1 for testing.
- Logo 44-ish and title "Wake up to meaning" (white over sky).
- Glass perks card with 4 rows (white check circle + 13-14 pt text): "Personal interpretation in 3 lenses", "An image of every dream", "Private journal and recurring symbols", "Gentle morning reminders".
- 2 PlanCards: **Yearly** + peach badge "7 days free", sub "$3.33 a month, billed yearly", price "$39.99" (selected by default); **Weekly**, sub "Billed every week", "$6.99".
- PrimaryButton label depends on plan: Yearly "Try 7 days free", Weekly "Subscribe for $6.99 a week".
- Terms line 11-12 pt centered, depends on plan: Yearly "Free for 7 days, then $39.99 a year. We remind you 2 days before it ends. Cancel anytime."; Weekly "Renews every week until you cancel. Cancel anytime."
- Links row: Restore / Terms / Privacy (underlined, 11-12 pt).
- CTA -> `PurchaseService.purchase(plan)` (mock: succeed after 0.8 s with a loading state in the button) -> Home, onboarding complete.

## 07 Home (Today tab)

Top sky. Header row at y 64: GlassIconButton settings (-> 14 Settings), Logo 28 centered, GlassIconButton moon (night mode - phase 1: no-op with a light haptic).
- OrbButton (150 frame, 92 orb, mic) centered at y 116 -> opens 08 Record (fullScreenCover).
- Greeting `title` "Good morning, Anna" (time-based: morning 4-12, afternoon 12-18, evening otherwise; name from AppState), sub "Tap to tell last night’s dream" 15 pt #3A4666.
- Week card (glass, height 96, radius 26): WeekStrip M..S with done days popping in one after another, caption "3 dreams caught this week".
- Insight card (glass, radius 26, height 96): sparkle, overline "YOUR MORNING INSIGHT", text "Stairs appeared in 3 of your dreams this week.", PillButton "See the pattern" -> Journal tab.
  **Fix vs design:** in the render the text runs under the pill. Limit the text width so it ends before the pill (max ~200 pt) or place the pill on its own line; the card may grow to ~110.
- Section header `heading` "Dreamed about today" + "See all" 13 pt -> Library tab.
- Horizontal scroll of DreamThumbs (84 x 94, gap 8, leading 22): "Teeth falling out", "Falling", "Your ex", "Being chased" (+ more). Tap -> Library symbol (phase 1: Interpretation mock).
- TabBar (Today active).

## 08 Record (fullScreenCover)

Full sky, no tab bar.
- GlassIconButton close (top left) -> dismiss to Home.
- Glass pill at top center: pulsing `recordDot` + "Recording 0:14" (live timer, 12 pt).
- Big orb with mic, stronger breathing while recording; under it a row of ~24 waveform bars animating (driven by audio level later; phase 1 random/looping).
- Live transcript, centered, `body` 16-17 pt #1E2A4A, grows as speech is recognized with a blinking caret. Mock text types at ~2 chars / 80 ms:
  "I was back in my grandmother’s house, but the hallway kept getting longer. Every door opened onto another staircase going down, and someone was calling my name from below."
- Bottom bar: GlassIconButton keyboard (switch to typing - phase 1: shows a TextEditor sheet) + PrimaryButton "I’m done" with check icon -> 09 Details (push inside the cover's own NavigationStack, or replace content).

## 09 Details

Background: full sky, dimmed/blurred, the transcript visible at the top (15 pt, white @ ~85%, 2 lines, ellipsis).
Bottom sheet (see BottomSheet) with grabber, gap 18, content:
- `display`-ish title "A few details" (22-24), sub "They make your interpretation more personal." 13 pt.
- "How did it feel?" 15 Medium; wrap layout of emotion Chips: Fear, Joy, Anxiety, Calm, Confusion (multi-select, default Anxiety + Confusion selected). Selected chip = emotion color.
- "Have you had this dream before?"; SegmentedControl Never / Sometimes / Often (default Sometimes).
- Row in a glass card: person icon + "Someone specific was in it" + DreamerToggle (default on).
- PrimaryButton with sparkle "Interpret my dream" -> 10 Analysis. TextLinkButton "Skip" -> 10 with no details.

## 10 Analysis

Top sky.
- Orb (sparkle glyph) with breathing rings; title `display` "Reading your dream".
- Glass card with 4 steps, each: status circle + 15 pt label. States: done = white circle with check (pops), active = spinning ring, pending = dashed ring + label at 50% opacity.
  Steps: "Reading your dream", "Finding the key symbols", "Connecting with how you felt", "Writing your interpretation".
- Phase 1 timing: advance one step every 1.3 s. When all done, PrimaryButton "See my interpretation" fades/slides in -> 11. (Real: steps map to backend progress; auto-navigate when finished is acceptable too.)

## 11 Interpretation (scrolling)

Everything scrolls in one ScrollView; the three header buttons stay fixed.
- Hero 380 high: dream image (placeholder `SkyTall`, object-position ~30% from top) revealed from blur 14 + scale 1.05 to sharp over 1.6 s; 200 pt fade at the bottom into `background`.
  Glass pill "AI dream image" 11 pt at top right (y 124).
- Fixed header: back (left, -> previous), download (right - 56) "Save image", share (right).
- At the bottom of the hero: "Yesterday · 7:12 AM" 13 pt #4B587A, title `display` "The house with endless stairs", emotion chips (small): Anxiety, Confusion.
- Content column, padding 22, gap 22:
  1. `heading` "Key symbols" + horizontal scroll of SymbolCards: Staircase down / "Progress you can’t see yet" (stairs icon); Grandmother’s house / "Roots and safety" (house); A voice calling / "A part of you asking for attention" (person).
  2. **Main interpretation card** (glass, radius 26, padding 18, gap 14):
     - Row: overline "YOUR INTERPRETATION" + white pill with a peach dot and the lens name (e.g. "Psychology").
     - **VoicePlayer** (white @60% capsule, padding 8/12): 44 `cta` circle with play / pause (pulsing ring while playing) · waveform (24 bars, animate only while playing, 55% opacity when paused) above a 3 pt progress bar that fills over the read-out duration · trailing "headphones + 1:12" (shows "Playing" / "Paused"). Durations for mock: Psychology 1:12, Spiritual 1:04, Dream book 0:48.
       Implementation: `AVSpeechSynthesizer` reading the main text (en-US, rate ~0.47), progress from `willSpeakRangeOfSpeechString`. Stop when leaving the screen or switching lens.
     - Interpretation text `body` 15/23 of the main lens.
  3. **Other perspectives**: header `heading` "Other perspectives" + "2 more lenses" 12 pt. Two glass cards (the two lenses not chosen), each:
     collapsed = title `bodyStrong` + chevron, 2-line preview 14/21 #3A4666; tap toggles expand (chevron rotates 180, full text, smooth height animation);
     expanded shows PillButton "Make this my main lens" -> swaps it into the main card (animated), resets the player, collapses both. Optionally persist as new default (ask via a small toast "Set Spiritual as default?" - phase 2).
  4. "For you, right now" card: sparkle + overline "FOR YOU, RIGHT NOW" + "You mentioned stress at work. Dreams like this often come when a decision feels unfinished. What is the one step you keep putting off?"
  5. "Your thoughts" label + glass TextEditor (3 lines, placeholder "Only you can see this"), saved to the dream.
  6. PrimaryButton with share icon "Share my dream image" -> ShareLink with the image.
  7. Disclaimer 12 pt centered: "Dreamer offers reflection, not medical advice."

Lens texts (mock, keep verbatim):
- Psychology: "Endless stairs in a familiar house often appear when you are working through something slowly, one step at a time, without seeing where it ends. Your grandmother’s house points to roots and safety. The voice calling from below is a part of you asking for attention - a feeling or a decision you keep postponing."
- Spiritual: "Going down stairs is a classic image of a journey inward, toward memory and intuition. A house that keeps growing suggests your inner world is larger than you let yourself explore. The calling voice is often read as guidance: something from your past holds wisdom for your present."
- Dream book: "Stairs going down: a time of reflection before a change. An old family house: news from family, or a return to an old question. Hearing your name called: an important message is near, so listen to the people close to you this week."

## 12 Journal (tab)

Top sky. Header: `title` "Journal" (white over sky, centered) + GlassIconButton search (right).
- Summary glass card: "Your September" `bodyStrong`, "Most frequent symbol: stairs" 12 pt; ring on the right (progress ring animating from 0, center "12" + "dreams"); emotion distribution bar (rounded segments in emotion colors) + legend dots: Anxiety, Calm, Joy, Confusion, Fear.
- `heading` "This month" + list of DreamRows (glass, gap 10): 
  "The house with endless stairs" · Yesterday · Anxiety;
  "Flying over a frozen lake" · Tuesday · Joy;
  "Late for an exam I never took" · Monday · Anxiety;
  "My old dog came back" · Sep 17 · Calm;
  "Chased through a night market" · Sep 15 · Fear.
  Tap -> 11 with that dream.
- TabBar (Journal active). List scrolls under the tab bar (add bottom inset).

## 13 Library (tab)

Top sky. `title` "Library".
- Glass search field (magnifier, placeholder "Search a symbol, e.g. teeth").
- Horizontal chips (small): Popular (selected), Love, Fear, Animals, Places, People.
- `heading` "Most searched dreams" + 2-column grid (gap 10) of image tiles (radius 22, image top, glass bottom with title `bodyStrong` + meaning 12 pt):
  Teeth falling out / Control and self-image; Falling / Losing your footing; Your ex / Unfinished feelings; Being chased / Avoiding something; Water / Emotions rising; Flying / Freedom and perspective; Snakes / Hidden fear or healing; Pregnancy / Something new growing.
  Tap -> symbol detail (phase 1: reuse Interpretation layout with symbol content, or a simple detail).
- TabBar (Library active). See `13-Library-scrolled.png`.

## 14 Settings (pushed from Home)

Top sky. Back button + `title` "Settings".
- Glass group 1: Morning reminder (bell, toggle on) · Reminder time (clock, "7:30 AM", chevron -> time picker sheet) · Default lens (sparkle, "Psychology", chevron -> picker with the 3 lenses, bound to `AppState.preferredLens`) · Night mode after 9 PM (moon, toggle on) · Lock journal with Face ID (lock, toggle off).
- Glass group 2: Subscription ("Yearly", chevron) · Restore purchases · Privacy policy · Terms of use · Contact support (each chevron).
- Destructive text button centered: "Delete account and all dreams" (#B4453C) -> confirmation dialog.
