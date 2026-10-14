"""Compare portable classifications, not executable paths or report locations."""
import argparse
import hashlib
import json
import pathlib


def projection(report):
    rows = json.dumps(report["records"], ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {"upstream_commit": report["upstream_commit"], "manifest_sha256": report["manifest_sha256"],
            "counts": report["counts"], "capabilities": report["capabilities"],
            "scope_errors": report["scope_errors"], "runner_errors": report["runner_errors"],
            "records_sha256": hashlib.sha256(rows).hexdigest()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", default="_build/schema-suite/report.json")
    parser.add_argument("--baseline", default="testdata/schema-suite-baseline.json")
    parser.add_argument("--write-baseline", action="store_true", help="Explicit maintainer update; never used in CI")
    args = parser.parse_args()
    report = json.loads(pathlib.Path(args.report).read_text(encoding="utf-8"))
    actual = projection(report)
    if actual["scope_errors"] or actual["runner_errors"] or not actual["counts"]["executed"]:
        raise SystemExit("Cannot accept a failed or empty suite report")
    for key in ["false_accept", "false_reject", "execution_error"]:
        if actual["counts"][key]:
            raise SystemExit("Cannot accept a suite discrepancy")
    baseline = pathlib.Path(args.baseline)
    if args.write_baseline:
        baseline.write_text(json.dumps(actual, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        print("Recorded reviewed portable baseline")
    elif actual != json.loads(baseline.read_text(encoding="utf-8")):
        raise SystemExit("Classification or diagnostic differs from the reviewed portable baseline")
    else:
        print("Portable classifications and every per-test diagnostic match the reviewed baseline")


if __name__ == "__main__":
    main()
