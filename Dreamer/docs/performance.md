# Performance (IOS-10.1)

## What changed

| Area | Before | After |
| --- | --- | --- |
| Looping animations (orbs, sparkles, spinners: `LoopingView`) | Ran while the app was in the background and on screens not shown (other tabs, pushed screens) | Paused off screen and whenever the scene is not active |
| Glass in long lists (Journal rows, Library tiles) | A live blur layer per card | `lightweightGlass`: a flat 10 % white layer instead; the blur was at 30 %, so the cards look the same |
| Dream and symbol images | Decoded at full size (a 1024 x 1536 image in a 56 pt row is a 6 MB bitmap) | `ImageDownsampler` decodes at the size shown: 168 px for journal rows, 600 pt for the hero, 200 pt for tiles |

## Cold start

Measured with `LaunchMetrics` (Debug and Staging builds log "first frame after N ms" to the
unified log): 7 cold launches of the optimized Staging build on the iPhone 17 simulator (a Mac
M-series), from the process start to the first frame of the root view.

| | First launch after install | Following launches |
| --- | --- | --- |
| Before | 1331 ms | 793 - 804 ms |
| After | 906 ms | 765 - 797 ms |

The first frame is dominated by SwiftUI's first render (about 85 % of the main-thread samples in
Time Profiler), then the SwiftData container (`LocalStore.makeContainer`, about 7 %, 40 ms) and
the panorama sky image (about 4 %). None of the app's own work is a hotspot, so the changes
above do not target launch.

## To measure on a device (needs an iPhone 12)

- **Cold start**: Instruments -> App Launch on a Release build, 5 launches after a reboot; the
  target is at most 1.5 s to the first frame.
- **Hitches**: Instruments -> Animation Hitches. Scroll the Journal with 30+ dreams and
  Home for 30 s each; the target is under 5 ms/s.
- **Memory**: Allocations while scrolling the Journal and opening 10 dreams; with downsampling
  the image bytes should stay under about 40 MB.
- **Energy**: Energy Log for 5 minutes on Home with the screen on, then 5 minutes in the
  background; the looping animations should cost nothing in the background.

Simulator numbers run on a Mac and cannot stand in for these; record the device results here.
