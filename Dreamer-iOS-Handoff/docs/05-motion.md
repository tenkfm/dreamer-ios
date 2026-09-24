# 05 - Motion

Motion is a core part of the brand: slow, soft, "breathing". Everything respects Reduce Motion
(`@Environment(\.accessibilityReduceMotion)`): when on, show final states, no loops, no drift.

Standard curve: CSS `cubic-bezier(.22,.8,.26,1)` = a soft ease-out.
SwiftUI: `.timingCurve(0.22, 0.8, 0.26, 1, duration: d)` or `.spring(response: 0.6, dampingFraction: 0.85)`.

## Screen-level

| Name | Spec | SwiftUI |
|---|---|---|
| Enter up (stagger) | Each block: opacity 0 -> 1, y +18 -> 0, 0.9 s, soft ease-out. Delays per screen: header 0.1-0.15, hero/orb 0.25-0.5, title 0.3-0.4, cards +0.15 each, CTA ~0.9-1.0 | `EnterUp(delay:)` modifier in starter code (`.enterUp(0.4)`) |
| Tab bar slide up | opacity 0 + y +40 -> in, 0.9 s, delay 1.1 on Home | same modifier with offset 40 |
| Sky drift | Sky image scaled 1.12, x moves -10 -> +10 -> -10, 40 s (top) / 46 s (full), ease-in-out, infinite | `SkyBackground` uses `TimelineView(.animation)` or repeatForever offset |
| Screen transitions (onboarding) | Sky stays; content: outgoing fades + moves up 12, incoming enter-up | `.transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 18)), removal: .opacity))` |
| Push (app) | Standard NavigationStack push; content of the new screen uses enter-up | default |
| Sheet (Details) | Slides from bottom 0.7 s soft ease-out | offset-based custom sheet over the blurred sky |
| Hero reveal (Interpretation) | Image blur 14 -> 0 and scale 1.05 -> 1, 1.6 s | `.blur(radius:)` + `.scaleEffect` animated on appear |

## Components

| Name | Spec |
|---|---|
| Press | Buttons scale to 0.95 while pressed, 0.18 s | `PressableButtonStyle` in starter |
| Orb breathing | Outer ring: scale 1 -> 1.14, opacity .7 -> .2, 4.2-4.6 s loop. Inner ring: scale 1 -> 1.08, opacity .9 -> .45, same period, +0.5 s offset. Orb itself floats y 0 -> -5, 5 s |
| Recording orb | Same but faster (1.8-2 s) and rings stronger |
| Waveform bars | Each bar scaleY 0.25 <-> 1, 0.7-1.2 s, stagger 0.05 s per bar, loop. Voice player: paused = bars frozen at their current height, opacity .55 |
| Caret | Opacity 1/0 step every 0.5 s |
| Week check pop | Done circles: scale .4 -> 1.1 -> 1, opacity 0 -> 1, 0.55 s bouncy, stagger 0.12 s starting 1.14 s |
| Sparkle twinkle | Scale .85 -> 1.1, rotate 0 -> 20 deg, opacity .55 -> 1, 3 s loop |
| Thumb float | y 0 -> -5, 4.0 / 4.6 / 5.2 / 5.8 s with 0.4 s offsets so they never sync |
| Progress capsule | Width 0 -> value, 1 s soft ease-out, 0.3 s delay |
| Ring (Journal) | Stroke trim 0 -> value, ~1.4 s ease-out |
| Analysis steps | Spinner rotates 1 s linear; on done the check pops (see week check); pending labels at 50% opacity animate to 100% |
| Segmented / tab pill | Sliding white pill 0.45 s soft ease-out (matchedGeometryEffect) |
| Toggle knob | Spring with slight overshoot (cubic-bezier .3,.7,.4,1.3) |
| Expand card | Height + chevron rotation 0.35 s soft ease-out; "Make this my main lens" fades in 0.4 s |
| Lens swap | Main card text crossfades (0.5 s), alternatives reorder with `.animation(.spring, value: mainLens)` |
| Recording dot | Opacity/scale pulse 1.2 s |
| Card lift | (iPad/hover only) y -3 + stronger shadow. On iPhone skip |

Haptics: light impact on primary CTA, selection changed on radio/chips/segments/toggles,
success notification when the interpretation is ready.
