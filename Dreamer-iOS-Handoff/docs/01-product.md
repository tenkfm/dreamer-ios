# 01 - Product context

## What Dreamer is

An iPhone app that turns a dream told by voice right after waking up into a personal
interpretation, the key symbols behind it and an AI-generated image of the dream.
Positioning: a calm, airy "morning" app (reference feel: Calm), not a dark mystical one.

The full PRD, roadmap and PM board live in ClickUp (Search Partners Group -> Dream).
This doc is the minimum context needed to build the UI correctly.

## Core loop

1. Wake up -> open app -> tap the mic orb on Home.
2. Tell the dream by voice; live transcript appears (Record).
3. Add a few details: emotions, how often it repeats, whether someone specific was in it (Details).
4. Short "reading your dream" analysis state (Analysis).
5. Interpretation: dream image, key symbols, the interpretation in the user's chosen lens
   (with voice read-out), two alternative lenses, a personal "For you" note, private notes, share.
6. Dream is saved to the Journal; patterns (recurring symbols, emotions) surface on Home and Journal.

## Lenses (interpretation styles)

Three lenses, chosen in onboarding (Quiz 2) and changeable in Settings -> Default lens:

- **Psychology** - what your mind is working through
- **Spiritual** - signs, symbols and inner guidance
- **Dream book** - classic meanings of dream symbols

The chosen lens is always shown as the main interpretation; the other two are shown as
collapsible "Other perspectives". The user can promote an alternative to main on the spot.

## Monetization

Hard paywall after onboarding (paid-traffic funnel):

- **Yearly** - $39.99/year, 7-day free trial, shown as "$3.33 a month, billed yearly". Default selected.
- **Weekly** - $6.99/week, no trial.

Phase 1: StoreKit is mocked (`PurchaseService` protocol with a mock that always succeeds).
Phase 2: StoreKit 2 with product ids `dreamer.yearly` and `dreamer.weekly` (placeholders).

## MVP screens (14)

Onboarding: Welcome, Onboarding-Record, Onboarding-Understand, Quiz-Goal, Quiz-Lens, Paywall.
App: Home, Record, Details, Analysis, Interpretation, Journal, Library, Settings.

## Out of scope for phase 1

Real speech-to-text, LLM interpretation, image generation, StoreKit, notifications, Face ID lock,
night mode, accounts/sync. Build the UI and the service protocols; mocks return the sample
content found in the designs.

## Planned later (keep the architecture ready)

- Speech: `SFSpeechRecognizer` on-device transcription.
- Interpretation + symbols: backend LLM call returning the three lenses at once.
- Image: backend image generation; placeholder = `SkyTall` / `DreamThumbN` assets.
- Voice read-out: `AVSpeechSynthesizer` in phase 1 is acceptable (the Listen button works for real
  with on-device TTS), later a neural TTS voice from the backend.
- Night mode: starry sky asset fading into a deep navy background, same components.
