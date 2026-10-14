"""Build an explicit, reviewable policy from capabilities, never from results.

This script is an update aid, not part of CI or the runtime runner. Policies are
committed and descriptions/indexes are independently checked by the runner.
"""
import collections
import decimal
import json
import pathlib
import re
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[1]
DATA = ROOT / "testdata/json-schema-suite"
SUPPORTED = set("type required properties patternProperties minProperties maxProperties prefixItems items minItems maxItems uniqueItems contains minContains maxContains enum const minimum maximum exclusiveMinimum exclusiveMaximum multipleOf minLength maxLength pattern allOf anyOf oneOf not additionalProperties $defs $ref $schema title description $comment format default examples".split())
COUNTS = {"minLength", "maxLength", "minItems", "maxItems", "minProperties", "maxProperties", "minContains", "maxContains"}


def child(path, key):
    return path + "." + key if path else key


def regex_limit(pattern):
    if "(?" in pattern or re.search(r"\\(?:[1-9bBpP]|u\{|u[dD][89a-fA-F])", pattern):
        return True
    return bool(re.search(r"\\[A-Za-z]", re.sub(r"\\[dDsSwWnrtfu]", "", pattern)))


def limitation(root):
    queue = [(root, "")]
    seen = set()
    found = []
    for schema, path in queue:
        if not isinstance(schema, dict):
            continue
        identity = id(schema)
        if identity in seen:
            continue
        seen.add(identity)
        for keyword, value in schema.items():
            here = child(path, keyword)
            if keyword not in SUPPORTED:
                found.append((here, "UnsupportedFeature", "keyword is not supported", f"Keyword/mechanism {keyword} is not implemented"))
                continue
            if keyword == "$schema" and value != "https://json-schema.org/draft/2020-12/schema":
                found.append((here, "UnsupportedVersion", "unsupported schema version", "Only the declared Draft 2020-12 URI is supported"))
            if keyword == "$ref":
                if not value.startswith("#"):
                    found.append((here, "UnsupportedFeature", "external references are not supported", "External/meta-schema references are not implemented"))
                    continue
                fragment = urllib.parse.unquote(value[1:])
                if fragment and not fragment.startswith("/"):
                    found.append((here, "UnsupportedFeature", "named anchors are not supported", "Named anchor references are not implemented"))
                    continue
                target = root
                missing = False
                for token in fragment[1:].split("/") if fragment else []:
                    token = token.replace("~1", "/").replace("~0", "~")
                    try:
                        target = target[int(token)] if isinstance(target, list) else target[token]
                    except (KeyError, IndexError):
                        missing = True
                        break
                if missing:
                    found.append((here, "InvalidSchema", "reference target does not exist", "Local pointer requires an unsupported $id resource scope"))
                else:
                    queue.append((target, fragment))
            if keyword in COUNTS and value > 1_000_000_000:
                found.append((here, "UnsupportedFeature", "exceeds the supported", "Count parameters exceed the implementation limit of 1000000000"))
            if keyword == "pattern" and regex_limit(value):
                found.append((here, "UnsupportedFeature", "not a pattern this tool reads", "Regex uses a mechanism outside the declared subset"))
            if keyword in {"properties", "$defs", "patternProperties"}:
                for name, sub in value.items():
                    location = here + "[" + json.dumps(name, ensure_ascii=False) + "]" if keyword == "patternProperties" else child(here, name)
                    if keyword == "patternProperties" and regex_limit(name):
                        found.append((location, "UnsupportedFeature", "not a pattern this tool reads", "Regex uses a mechanism outside the declared subset"))
                    queue.append((sub, location))
            elif keyword in {"allOf", "anyOf", "oneOf", "prefixItems"}:
                queue.extend((sub, here + f"[{i}]") for i, sub in enumerate(value))
            elif keyword in {"not", "items", "additionalProperties", "contains"}:
                queue.append((value, here))
    return found


def main():
    entries = []
    for path in sorted((DATA / "tests/draft2020-12").rglob("*.json")):
        file = path.relative_to(DATA).as_posix()
        groups = json.loads(path.read_text(encoding="utf-8"), parse_float=decimal.Decimal, parse_int=decimal.Decimal)
        for index, group in enumerate(groups):
            entry = {"file": file, "group": index, "description": group["description"],
                     "capability": path.stem, "action": "validate"}
            if "/optional/format/" in file:
                entry.update(action="skip", reason="Optional format assertions are not implemented; format is annotation only")
            else:
                limit = limitation(group["schema"])
                if limit:
                    if not any(kind.startswith("Unsupported") for _, kind, _, _ in limit):
                        raise ValueError("Cannot exclude a case solely because it fails compilation")
                    entry.update(action="reject", reason="; ".join(dict.fromkeys(row[3] for row in limit)),
                                 expected_problems=[{"path": location, "kind": kind, "message_contains": message}
                                                    for location, kind, message, _ in limit])
            entries.append(entry)
    manifest = {"version": 1, "upstream_commit": "55719286c33ae0d1823bfb65fea10338a19bc37c",
                "policy": "Policies derive from declared capabilities, not observed outcomes. Every upstream group has exactly one entry; review updates manually.",
                "groups": entries}
    path = ROOT / "testdata/schema-suite-manifest.json"
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(collections.Counter(e["action"] for e in entries), "groups", len(entries))


if __name__ == "__main__":
    main()
