#!/bin/zsh
# Refreshes Dreamer/Resources/Localizable.xcstrings from the strings the compiler found in the last
# Debug build (Text literals, String(localized:)), like Xcode does when the catalog is open.
# Keys without letters (numbers, "%lld") are marked not to be translated.
#   xcodebuild ... build && scripts/sync_strings.sh
set -e
cd "${0:A:h}/.."
# The newest Debug build: run.sh and the fastlane lanes build into build/DerivedData, Xcode into
# ~/Library/Developer/Xcode/DerivedData. Looking only at Xcode's left the lanes' strings out.
objects=$(find build/DerivedData ~/Library/Developer/Xcode/DerivedData \
    -path "*Dreamer.build/Debug-iphonesimulator/Dreamer.build/Objects-normal/*" -name "*.stringsdata" \
    -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1 | xargs dirname)
[[ -n "$objects" ]] || { echo "Build the Debug scheme for a simulator first." >&2; exit 1; }
args=()
for file in $objects/*.stringsdata; do args+=(--stringsdata "$file"); done
xcrun xcstringstool sync Dreamer/Resources/Localizable.xcstrings "${args[@]}"
python3 - <<'PY'
import json, pathlib, re
path = pathlib.Path("Dreamer/Resources/Localizable.xcstrings")
catalog = json.loads(path.read_text())
for key, entry in catalog["strings"].items():
    if not re.search(r"[A-Za-z]{2}", key.replace("%lld", "").replace("%@", "")):
        entry["shouldTranslate"] = False
path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
print(f"{len(catalog['strings'])} strings in the catalog")
PY
