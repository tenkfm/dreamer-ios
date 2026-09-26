# Internal TestFlight: manual QA checklist (IOS-11.3)

Run on 3-4 iPhones: an SE (small screen), a 12 or 13 (the oldest target), a Pro Max, and one with a
non-English iOS language. Use a Staging TestFlight build with sandbox Apple IDs. For each item,
note the device, the iOS version and the result. File every problem in ClickUp with a screen
recording and the steps: **Blocker** stops the release, **Critical** must be fixed before App
Review, **Minor** can wait.

## Conditions to combine with the scenarios

- [ ] Half-dark room, brightness low, night mode on (after 9 PM, or the moon button)
- [ ] Bad network: Settings -> Developer -> Network Link Conditioner "Very Bad Network", then Airplane mode
- [ ] Interruptions while recording: a call, Siri, an alarm, locking the phone, the home gesture
- [ ] Largest text size (Settings -> Accessibility -> Display & Text Size -> Larger Text, xxLarge)
- [ ] VoiceOver on for one full pass of the main scenario
- [ ] Reduce Motion and Increase Contrast on for one pass

## Onboarding and account

- [ ] Fresh install: Welcome -> Record intro -> Understand swipe and buttons slide the pages with the sky
- [ ] Quiz: goal and lens can be changed, Back works, progress label reads "1 of 2", "2 of 2"
- [ ] Sign up with Apple (new Apple ID): lands on the paywall; hide-my-email works
- [ ] Email sign-in: the link opens the app (cold and warm), "Signing you in…" moves on within seconds
- [ ] Expired link (older than 15 minutes): the right message, a new link can be requested
- [ ] "I already have an account" on a second device: Welcome back, the journal from the server
- [ ] Tracking question: our explanation, then the system alert; both answers keep the app working

## Paywall and subscription (sandbox)

- [ ] Prices and the trial in the local currency; "Try 7 days free" on Yearly, weekly without trial
- [ ] Purchase Yearly: the app opens Main; Settings shows the plan; a trial reminder 2 days before its end
- [ ] Cancel in the sandbox account, wait for expiry: back to the paywall without a relaunch
- [ ] Restore on a second device and after reinstall
- [ ] Ask to Buy / pending purchase message; cancelled purchase leaves the paywall as it was
- [ ] Terms and Privacy links open the right pages (after the real URLs exist)

## Record and interpretation

- [ ] Microphone and speech permissions: pre-prompt, allow, deny -> "Type it instead" and Settings link
- [ ] Recording shows live text, the waveform, the timer; the 30 s warning and the 5-minute stop
- [ ] Each interruption pauses with "Your words are saved" and Continue adds to the text
- [ ] A language the iPhone cannot recognise (or on-device recognition off): "your words will appear when you're done", then the server writes it down
- [ ] Airplane mode at "I'm done": "Saved on your iPhone", Home shows the waiting dream, it is read when back online
- [ ] Analysis: four steps, the first words appear before the end, "See my interpretation"
- [ ] Interpretation: image painting then revealing, Listen starts within 1 s (main lens), another lens voices after loading, the system voice when TTS is off
- [ ] Make another lens the main one; the change shows in Settings and on other dreams
- [ ] Notes are kept after leaving and on another device
- [ ] Share card opens in the share sheet, Save Image works, Stories when available
- [ ] A crisis dream (reference text from the backend team) shows the support screen, no image or voice
- [ ] Push "Your dream is ready" when the app is in the background opens that dream

## Journal, insights, library

- [ ] Journal opens instantly from the cache, pull-to-refresh, older weeks load while scrolling
- [ ] Search by a word from the interpretation; emotion chips; offline search
- [ ] Delete a dream (long press): confirmation, gone on the other device too
- [ ] Home week strip and caption match the journal; the morning insight card, or none
- [ ] Library categories, search, a symbol with lenses and related symbols; works in Airplane mode after one visit

## Settings and privacy

- [ ] Morning reminder at the chosen time opens Record; changing the time zone keeps it local
- [ ] Reminder, time and night mode follow to a second device
- [ ] Face ID lock: turning it on asks first; the app locks in the background and in the app switcher
- [ ] Sign out and sign back in; delete the account: Welcome, nothing left in the journal
- [ ] Device log (Console, process Dreamer) shows no dream text and no email

## Stability

- [ ] No crash in 30 minutes of mixed use per device; any crash appears in Sentry with its version
- [ ] Cold start feels instant on the oldest device; scrolling the journal with 30+ dreams is smooth
