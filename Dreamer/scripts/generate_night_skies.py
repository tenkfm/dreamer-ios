#!/usr/bin/env python3
"""Generates the night-mode sky images with Seedream 5.0 Pro on kie.ai.

Usage (from the Dreamer/ folder):
    KIE_API_KEY=... python3 scripts/generate_night_skies.py [name ...]

Images land in build/night_skies/<name>.jpeg. Review them, then add them to the asset
catalog as the dark-appearance variant of the matching image set.
"""

import json
import os
import sys
import time
import urllib.request
from pathlib import Path

API = "https://api.kie.ai/api/v1/jobs"
MODEL = "seedream/5-pro-text-to-image"
OUTPUT = Path(__file__).resolve().parent.parent / "build" / "night_skies"

STYLE = (
    "Photographic, soft focus, fine grain, gentle volumetric moonlight, calm and dreamy, "
    "Calm-app aesthetic, premium meditation app background. "
    "No ground, no horizon line, no mountains, no trees, no buildings, no people, no birds, "
    "no text, no logos, no watermark, no vignette, no lens flare, no harsh contrast, "
    "no bright moon disk."
)

# Night versions of the day skies. The app fades every sky into the night background #0F1833.
IMAGES = {
    "SkyTopNight": {
        "aspect_ratio": "4:3",
        "prompt": (
            "Night sky seen upward, calm deep indigo and midnight blue (#1B2A5C to #2E3F7A), "
            "a scattering of soft small stars, rows of soft moonlit cumulus clouds with silver-lavender "
            "edges across the middle of the frame, faint warm peach glow (#F2A488) hidden behind the "
            "clouds in the center. The lower third dissolves into a smooth dark navy haze (#0F1833). "
            "Same composition as a gentle daytime cloud strip, but at night. " + STYLE
        ),
    },
    "SkyTallNight": {
        "aspect_ratio": "9:16",
        "prompt": (
            "Vertical night sky, deep indigo to midnight blue gradient (#1B2A5C at top to #2E3F7A), "
            "delicate starfield with a few brighter twinkling stars in the upper half, soft moonlit "
            "cumulus clouds with silver and pale lavender rims drifting across the middle, subtle warm "
            "peach glow (#F2A488) behind a cloud. The bottom 40 percent fades smoothly into a clean, "
            "flat dark navy (#0F1833) with no detail at the bottom edge. Calm empty area in the "
            "vertical center for interface elements. " + STYLE
        ),
    },
    "OnboardingSkyNight": {
        "aspect_ratio": "16:9",
        "prompt": (
            "Ultra-wide seamless panoramic night sky, continuous cloudscape flowing left to right with no "
            "repeating elements. Left third: late dusk, last violet and muted peach afterglow (#F2A488) "
            "on soft clouds under a deepening indigo sky. Middle third: clear deep midnight blue sky "
            "(#1B2A5C) with a delicate starfield and a faint milky way haze, a few thin silver clouds. "
            "Right third: soft moonlight from the upper right lighting silver-lavender clouds, calm and "
            "luminous. Consistent cloud altitude and light across the whole image, no seams. Upper half "
            "holds the stars and clouds; the lower half dissolves into a smooth dark navy haze that "
            "becomes flat #0F1833 at the bottom edge. " + STYLE
        ),
    },
}


def request(url, key, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method="POST" if data else "GET")
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=60) as response:
        payload = json.load(response)
    if payload.get("code") != 200:
        raise RuntimeError(f"{url}: {payload.get('code')} {payload.get('msg')}")
    return payload["data"]


def generate(name, spec, key):
    task = request(f"{API}/createTask", key, {
        "model": MODEL,
        "input": {
            "prompt": spec["prompt"],
            "aspect_ratio": spec["aspect_ratio"],
            "quality": "high",
            "output_format": "jpeg",
        },
    })
    task_id = task["taskId"]
    print(f"{name}: task {task_id}", flush=True)

    deadline = time.time() + 600
    while time.time() < deadline:
        time.sleep(5)
        info = request(f"{API}/recordInfo?taskId={task_id}", key)
        state = info.get("state")
        if state == "success":
            url = json.loads(info["resultJson"])["resultUrls"][0]
            target = OUTPUT / f"{name}.jpeg"
            urllib.request.urlretrieve(url, target)
            print(f"{name}: saved {target} ({info.get('creditsConsumed')} credits)", flush=True)
            return target
        if state == "fail":
            raise RuntimeError(f"{name}: {info.get('failCode')} {info.get('failMsg')}")
    raise TimeoutError(f"{name}: no result after 10 minutes")


def main():
    key = os.environ.get("KIE_API_KEY")
    if not key:
        sys.exit("Set KIE_API_KEY.")
    names = sys.argv[1:] or list(IMAGES)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    failed = []
    for name in names:
        try:
            generate(name, IMAGES[name], key)
        except Exception as error:  # keep going with the other images
            print(f"{name}: FAILED {error}", flush=True)
            failed.append(name)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
