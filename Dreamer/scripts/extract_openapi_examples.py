#!/usr/bin/env python3
"""Response examples of Dreamer/API/openapi.yaml as a test fixture.

Writes DreamerTests/Fixtures/openapi-examples.json: {operationId: {status: example}} for every
response that has an application/json example. The contract tests stub the network with these
bodies, so a contract change that breaks the app's mapping fails a test. Rerun after
scripts/sync-openapi.sh.
"""
import json
import pathlib
import re

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
class ContractLoader(yaml.SafeLoader):
    """Keeps dates as the strings the API sends (YAML would turn them into datetimes)."""


ContractLoader.yaml_implicit_resolvers = {
    key: [(tag, regexp) for tag, regexp in resolvers if tag != "tag:yaml.org,2002:timestamp"]
    for key, resolvers in yaml.SafeLoader.yaml_implicit_resolvers.items()
}
spec = yaml.load((ROOT / "Dreamer/API/openapi.yaml").read_text(), Loader=ContractLoader)
examples = {}
for path, methods in spec.get("paths", {}).items():
    for method, operation in methods.items():
        if not isinstance(operation, dict) or "operationId" not in operation:
            continue
        for status, response in (operation.get("responses") or {}).items():
            content = (response or {}).get("content", {}).get("application/json", {})
            if "example" in content:
                examples.setdefault(operation["operationId"], {})[str(status)] = content["example"]
STAMP = re.compile(r"^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})(\.\d+)?(\+00:00|Z)$")


def iso(value):
    """The normalized copy of the contract writes example dates as "2026-09-20 07:00:00+00:00";
    the API sends ISO 8601 with milliseconds and Z, which is what the app must parse."""
    if isinstance(value, dict):
        return {key: iso(item) for key, item in value.items()}
    if isinstance(value, list):
        return [iso(item) for item in value]
    if isinstance(value, str) and (match := STAMP.match(value)):
        fraction = (match.group(3) or ".000")[:4].ljust(4, "0")
        return f"{match.group(1)}T{match.group(2)}{fraction}Z"
    return value


examples = iso(examples)
out = ROOT / "DreamerTests/Fixtures/openapi-examples.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(examples, indent=2, sort_keys=True) + "\n")
print(f"{sum(len(v) for v in examples.values())} examples of {len(examples)} operations -> {out.relative_to(ROOT)}")
