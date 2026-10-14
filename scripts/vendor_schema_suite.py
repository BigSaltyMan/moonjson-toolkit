"""Copy fixed upstream bytes and inventory them. Never reserialize test data."""
import argparse
import hashlib
import json
import pathlib
import tarfile

SHA = "55719286c33ae0d1823bfb65fea10338a19bc37c"
REPOSITORY = "https://github.com/json-schema-org/JSON-Schema-Test-Suite"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", help="tar.gz from codeload at the fixed SHA")
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[1]
    dest = root / "testdata/json-schema-suite"
    prefix = "JSON-Schema-Test-Suite-" + SHA + "/"
    entries = []
    with tarfile.open(args.archive, "r:gz") as archive:
        for member in sorted(archive.getmembers(), key=lambda m: m.name):
            if not member.isfile() or not member.name.startswith(prefix):
                continue
            name = member.name[len(prefix):]
            if name != "LICENSE" and not name.startswith("tests/draft2020-12/"):
                continue
            if ".." in pathlib.PurePosixPath(name).parts:
                raise ValueError("Unsafe archive path")
            data = archive.extractfile(member).read()
            path = dest / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            entries.append({"path": name, "sha256": hashlib.sha256(data).hexdigest()})
    if not entries or not any(e["path"] == "LICENSE" for e in entries):
        raise ValueError("Missing upstream data or license")
    metadata = {
        "repository": REPOSITORY,
        "commit": SHA,
        "scope": ["LICENSE", "tests/draft2020-12/**"],
        "files": entries,
        "update": "Download " + REPOSITORY.replace("https://github.com/", "https://codeload.github.com/")
        + "/tar.gz/" + SHA + "; run python scripts/vendor_schema_suite.py <archive>. "
        "Review all manifest policies before accepting a new version; never use results to infer policies.",
    }
    (dest / "UPSTREAM.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Copied {len(entries)} original files at {SHA}")


if __name__ == "__main__":
    main()
