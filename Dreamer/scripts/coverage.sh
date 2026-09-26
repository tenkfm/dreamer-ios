#!/bin/zsh
# Runs the unit tests with code coverage and prints the line coverage of the live services and
# the API layer (Services/ and API/, mocks excluded) - the IOS-11.1 target is at least 70 %.
#   scripts/coverage.sh ["iPhone 17"]
set -e
cd "${0:A:h}/.."
device=${1:-"iPhone 17"}
result=build/coverage.xcresult
rm -rf $result
xcodebuild test -project Dreamer.xcodeproj -scheme Dreamer -destination "platform=iOS Simulator,name=$device" \
  -skipPackagePluginValidation -enableCodeCoverage YES -resultBundlePath $result -quiet
xcrun xccov view --report --json $result | python3 -c '
import json, sys
report = json.load(sys.stdin)
app = next(t for t in report["targets"] if t["name"].startswith("Dreamer.app"))
rows = [f for f in app["files"] if ("/Dreamer/Services/" in f["path"] or "/Dreamer/API/" in f["path"]) and "Mocks" not in f["path"]]
covered = sum(f["coveredLines"] for f in rows)
lines = sum(f["executableLines"] for f in rows)
for f in sorted(rows, key=lambda f: f["lineCoverage"]):
    print(f"{f[\"lineCoverage\"]:6.0%}  {f[\"path\"].split(\"/Dreamer/Dreamer/\")[-1]}")
print(f"\nServices + API: {covered}/{lines} lines = {covered / lines:.1%} (app: {app[\"lineCoverage\"]:.1%})")
'
