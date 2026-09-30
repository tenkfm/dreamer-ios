#!/bin/bash
# Copies the API contract from the backend repository (dreamer-platform) into the app.
# The file is generated there from the zod schemas - never edit the copy by hand; run this
# script after a contract release and let the build (swift-openapi-generator) catch changes.
# Needs python3 with PyYAML.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${1:-$ROOT/../dreamerweb/openapi.yaml}"
TARGET="$ROOT/Dreamer/Dreamer/API/openapi.yaml"

if [[ ! -f "$SOURCE" ]]; then
  echo "No contract at $SOURCE. Pass the path, or download it:" >&2
  echo "  curl -o openapi.yaml https://staging-api.dreamerapp.io/docs/openapi.yaml" >&2
  exit 1
fi

# Nullable `anyOf [X, null]` values become optional `X`: swift-openapi-generator 1.x drops the
# whole property otherwise (see normalize_openapi.py).
VERSION=$(python3 "$ROOT/scripts/normalize_openapi.py" "$SOURCE" "$TARGET")
echo "Synced openapi.yaml ($VERSION) into Dreamer/API/"

# Operations in the contract that the generator config does not list (new endpoints to review).
python3 - "$TARGET" "$(dirname "$TARGET")/openapi-generator-config.yaml" <<'PY'
import sys, re
contract, config = open(sys.argv[1]).read(), open(sys.argv[2]).read()
ops = set(re.findall(r"^\s+operationId: (\w+)", contract, re.M))
listed = set(re.findall(r"^\s+- (\w+)$", config, re.M)) | set(re.findall(r"^#\s+(\w+):", config, re.M))
missing = sorted(ops - listed)
if missing:
    print("Not in openapi-generator-config.yaml (add to the filter or to the left-out list):", ", ".join(missing))
PY
