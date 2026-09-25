#!/usr/bin/env python3
"""Normalizes the backend contract for swift-openapi-generator (called by sync-openapi.sh).

The contract marks nullable values the OpenAPI 3.1 way, `anyOf: [X, {type: "null"}]`.
swift-openapi-generator 1.x does not support the null branch and drops the whole property,
so `nextCursor`, `thumbnailUrl`, `DreamDetail.image` and others would disappear from the
generated types. The rewrite is purely mechanical:

- `anyOf/oneOf: [X, {type: null}]` becomes `X`;
- such a property is removed from its object's `required` list, so the generated Swift property
  is optional and decoded with `decodeIfPresent` - a JSON `null` decodes as `nil`.

Nothing else changes. Needs PyYAML (`pip3 install pyyaml`).
"""
import sys

import yaml


def is_null(schema):
    return isinstance(schema, dict) and schema.get("type") == "null" and len(schema) == 1


def strip_null(schema):
    """Returns (schema without a null branch, whether it was nullable)."""
    if not isinstance(schema, dict):
        return schema, False
    for key in ("anyOf", "oneOf"):
        branches = schema.get(key)
        if isinstance(branches, list) and any(is_null(b) for b in branches):
            rest = [b for b in branches if not is_null(b)]
            outer = {k: v for k, v in schema.items() if k != key}
            if len(rest) == 1:
                merged = dict(rest[0])
                if "$ref" in merged:
                    # Siblings of $ref are ignored by generators; keep the reference alone.
                    return merged, True
                for k, v in outer.items():
                    merged.setdefault(k, v)
                return merged, True
            outer[key] = rest
            return outer, True
    return schema, False


def walk(node):
    if isinstance(node, list):
        return [walk(item) for item in node]
    if not isinstance(node, dict):
        return node

    node, _ = strip_null(node)
    node = dict(node)

    # Properties first: their null branches decide the `required` list before recursion strips them.
    properties = node.get("properties")
    if isinstance(properties, dict):
        nullable = []
        properties = dict(properties)
        for name, prop in properties.items():
            stripped, was_nullable = strip_null(prop)
            if was_nullable:
                properties[name] = stripped
                nullable.append(name)
        node["properties"] = properties
        if nullable and isinstance(node.get("required"), list):
            node["required"] = [r for r in node["required"] if r not in nullable]
            if not node["required"]:
                del node["required"]

    return {k: walk(v) for k, v in node.items()}


def main(source, target):
    contract = yaml.safe_load(open(source))
    version = contract.get("info", {}).get("version", "?")
    normalized = walk(contract)
    header = (
        f"# Normalized copy of the Dreamer API contract {version} (dreamer-platform openapi.yaml).\n"
        "# Written by scripts/sync-openapi.sh - do not edit. Only change: nullable `anyOf [X, null]`\n"
        "# values became optional `X` (see scripts/normalize_openapi.py).\n"
    )
    with open(target, "w") as out:
        out.write(header)
        yaml.safe_dump(normalized, out, sort_keys=False, allow_unicode=True, width=120)
    print(f"contract {version}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
