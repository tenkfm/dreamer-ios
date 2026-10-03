# App Store screenshots: image prompts

Seven images for the Mooncatch listing ("Mooncatch: Dream Meaning"), all in the app's own style.
Image 1 has no phone; images 2-7 show an iPhone mockup with a real screen from the app on a soft
gradient. The headlines are drafts: every one needs Tony's approval before upload (see
"Before upload" at the end).

## Format

- Size: **1290 x 2796** px (6.9" iPhone, the size App Store Connect requires; 6.5" at 1242 x 2688
  is scaled from it). Portrait, the same tall format as the app's sky backgrounds.
- Keep the top 30% for the headline and the bottom 8% clear (App Store rounds the corners and
  overlays nothing, but thumbnails crop tight).
- Text: image generators misspell words. Generate every image **without text** and set the
  headline in Figma (or with `scripts/frame_screenshots.py`, which already draws captions in the
  app's font). The prompts say where the text goes so the composition leaves room for it.
- Screens for the mockups come from the app on mock data in day mode (`./run.sh screen:<name>`
  plus `-day`, then `xcrun simctl io booted screenshot`), so no real dream or email appears.

## Shared style (append to every prompt)

> Soft dreamy pastel palette taken from the app: sky blue #8FA6DA fading to deep blue #4F68A0,
> pale morning white #EEF4FB, peach clouds #F2A488 and #F7CDBD, warm golden light #F8D25C, ink
> navy #1E2A4A for contrast. Calm, airy, premium, quiet. Gentle film grain, no hard shadows, no
> neon, no harsh saturation. Elegant editorial look, generous empty space. Photographic clouds,
> never cartoon. No text, no letters, no logos, no watermarks, no UI except the phone screen
> described. Vertical 1290x2796 composition.

Typography for the overlaid text (not for the generator): Cormorant Garamond SemiBold for
headlines, Cormorant Garamond Regular for the line under them, the app name in Cormorant
Garamond SemiBold Italic like the logo. White with a soft navy shadow on sky images, ink navy
#1E2A4A on the light gradients.

## Phone mockup (images 2-7)

> A modern iPhone 17 Pro in a thin natural titanium frame, front view, rotated about 8-10 degrees
> clockwise and very slightly tilted back, floating in the lower two thirds of the frame, with a
> soft diffuse blue-grey shadow beneath it. The screen shows exactly the attached screenshot,
> undistorted, edge to edge, with its rounded corners and the Dynamic Island. Nothing in front of
> the screen.

Attach the screenshot to the request; if the tool cannot place it, generate the phone with a flat
#EEF4FB screen and composite the screenshot in Figma.

---

## 1. Hero: the sky

No phone, no app UI. The first image people see, so it sells the feeling.

**Text on the image**
- Top: `Mooncatch` (the logo, large)
- Under it, one of:
  - `Your dreams, finally understood` (recommended)
  - `Understand what your dreams are telling you`
  - `The dream journal that understands you`

On "The #1 app for dream...": App Review (guideline 2.3.7 and the accuracy rules of 2.3) rejects
ranking claims it cannot verify. Use "#1" only with a source we can show (a chart position on a
given date); otherwise one of the lines above.

**Prompt**

> You are floating inside the clouds at sunrise, high above the earth. Soft layered cumulus clouds
> all around and below, their tops lit warm gold and peach by a low sun just below the horizon;
> the light glows through gaps between the clouds. Far away a thin calm horizon line where the
> golden light meets pale blue sky. The upper third of the frame is open, softly lit sky with a
> few wisps of cloud, quiet and empty, leaving room for a title. The lower part is a sea of
> clouds catching the light. Serene, weightless, the moment between sleep and waking.
> [shared style]

---

## 2. Know yourself through your dreams

**Text on the image**
- Headline: `Know yourself through your dreams`
- Line under it (10 words): `Read every dream through psychology, spirituality and the dream book`

**Screen to attach**: Home (`./run.sh screen:home`, `-day`).

**Prompt**

> A soft vertical gradient from pale morning white #EEF4FB at the top to light sky blue #C9D8F2
> at the bottom. The upper 30% is clean and empty for a headline. Behind the phone, a loose grid of
> rounded square tiles, each a small dreamlike painting: a staircase into clouds, a crescent moon
> over water, a bird in flight, an old house at dusk, a key, the sea at night. The tiles have
> 24 px rounded corners and even gaps between them; they are softly blurred and faded to about
> 40% so they read as a background pattern, fading out toward the edges. In front, the phone
> mockup with the attached Home screen. [phone mockup] [shared style]

---

## 3. See your dreams come alive

**Text on the image**
- Headline: `See your dreams come alive`
- Line under it: `Every dream becomes a short film with its own voice-over`
- Alternative headline: `Visualize your dreams`

**Screen to attach**: the dream video playing full screen. On a phone with a ready video, open a
dream, tap "Watch your dream" and take a screenshot at a vivid frame (no controls in the middle);
on the simulator, `-debugScreen interpretation -videoReady -videoURL <mp4>`.

**Prompt**

> A smooth gradient from light sky blue #8FA6DA at the top to deep twilight blue #4F68A0 at the
> bottom, with a faint glow of warm gold behind the phone, as if light comes from the screen.
> Very soft, almost transparent clouds drift across the lower edge. The upper 30% is calm and
> empty for a headline. In the center, the phone mockup showing the attached frame of the dream
> film; a subtle light bloom around the phone suggests it is playing. Cinematic, magical, still
> calm. [phone mockup] [shared style]

---

## 4. The psychology of your dream

**Text on the image**
- Headline: `What your mind is working through`
- Line under it: `Psychological readings inspired by Jung, Freud and modern sleep research`
- Small print at the bottom (optional, 2 lines, 40% opacity):
  - `Walker & van der Helm (2009), Psychological Bulletin 135(5)`
  - `Hall & Van de Castle (1966), The Content Analysis of Dreams`

Before using the names and sources: the line must say only what the readings really do. The
backend's psychology lens decides it (its prompt in `../dreamerweb`); "inspired by" is the most
we can claim without a study of our own. Both sources exist and are standard references (sleep
and emotional processing; the method of counting dream content), but the copy needs Tony's yes.

**Screen to attach**: Interpretation with the Psychology lens as the main one, scrolled so the
reading and "For you, right now" show (`./run.sh screen:interpretation`, `-day`).

**Prompt**

> A soft gradient from pale white #EEF4FB at the top to light periwinkle #C9D8F2 at the bottom.
> Behind the phone, very faint fine line art, almost invisible at 10% opacity: thin concentric
> circles and a few calm flowing lines, like ripples of thought. The upper 30% is clean for a
> headline; a narrow empty band at the very bottom for two lines of small print. In front, the
> phone mockup with the attached interpretation screen. Thoughtful, clear, trustworthy, like a
> page from a beautiful psychology book. [phone mockup] [shared style]

---

## 5. The spiritual meaning

**Text on the image**
- Headline: `Hear what your soul is saying`
- Line under it: `A spiritual reading of the symbols in every dream`
- Alternative headline: `Find the spiritual meaning`

**Screen to attach**: Interpretation with Spiritual as the main lens (Settings -> Default lens ->
Spiritual, then open a dream), or "Other perspectives" with Spiritual expanded.

**Prompt**

> A gradient from soft lavender-blue #DCD3F8 at the top to calm sky blue #8FA6DA at the bottom.
> High in the background a pale crescent moon and a scatter of tiny soft stars, very subtle;
> a thin veil of luminous mist around the phone. The upper 30% is open for a headline. In front,
> the phone mockup with the attached spiritual reading. Peaceful, sacred, gentle, never mystical
> kitsch: no crystals, no tarot, no zodiac signs. [phone mockup] [shared style]

---

## 6. The dream book

**Text on the image**
- Headline: `Every dream symbol, explained`
- Line under it: `From falling to flying - the classic dream book, in your pocket`

**Screen to attach**: Library (`./run.sh screen:library`, `-day`) or a symbol opened from it
(`./run.sh screen:symbol`).

**Prompt**

> A soft gradient from pale morning white #EEF4FB at the top to peach-tinted white #F7E3DA at the
> bottom. Around the phone, five or six small rounded tiles float at different depths, slightly
> out of focus, each a tiny dreamlike painting of a classic dream symbol: falling teeth rendered
> softly and tastefully, a feather in the air, a door ajar with light behind it, a snake as an
> elegant curve, a house with a lit window. The upper 30% is clean for a headline. In front, the
> phone mockup with the attached Library screen. Curious, inviting, like opening an old book of
> dreams. [phone mockup] [shared style]

---

## 7. Your dream journal

**Text on the image**
- Headline: `The more you dream, the better it knows you`
- Line under it: `30 nights of dreams reveal the patterns of your life`
- Alternatives: `Know yourself, night by night` / `Your month in dreams`

Wording on purpose: the listing is a dream journal with psychology, not fortune telling (App
Review 4.3; "predict", "forecast", "fortune" and "psychic" are kept out of the metadata, see the
README's ASO section). So the line promises patterns and insight about your life, not
predictions. "30 nights" matches what the Journal shows (the month summary and recurring
symbols); if the backend's insights change, change the number.

**Screen to attach**: Journal with the month summary on top (`./run.sh screen:journal`, `-day`).

**Prompt**

> A gradient from light sky blue #C9D8F2 at the top to soft blue #8FA6DA at the bottom. Behind the
> phone, a subtle trail of thirty small glowing dots arranged in a gentle arc across the frame,
> like nights on a calendar, a few of them brighter and warmer gold; very faint wisps of cloud
> along the bottom. The upper 30% is open for a headline. In front, the phone mockup with the
> attached Journal screen. Personal, reflective, a sense of progress over time. [phone mockup]
> [shared style]

---

## Before upload

- All headlines and lines are drafts: Tony approves the copy (a standing rule).
- No "#1" without a source; no predictions or forecasts; the psychology sources only if they match
  the backend's lens.
- Mock data only on the screens: no real dreams, names or emails.
- Upload to App Store Connect only after Tony's explicit yes.
- Order in the listing: 1 hero, 2 know yourself, 3 video, 4 psychology, 5 spiritual, 6 dream book,
  7 journal. The first three show in search results, so they carry the main promise.
