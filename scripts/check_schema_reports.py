"""Offline acceptance of report v1 through real native CLI processes."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "_build/schema-report-acceptance"
FIXTURES = "examples/schema-acceptance/"
GENERATED = "_build/schema-report-acceptance/"
CLI_ARTIFACT = ROOT / "_build/native/debug/build/cmd/main/main.exe"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def write_json(name, value):
    (OUTPUT / name).write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def cases():
    """Inputs and expected results are explicit, never learned from CLI output."""
    write_json("true.schema.json", True)
    write_json("false.schema.json", False)
    special = '中文"\\\n字段'
    write_json("special.schema.json", {
        "properties": {special: {"type": "integer"}}
    })
    first = json.dumps({special: 1}, ensure_ascii=False)
    invalid = json.dumps({special: "bad"}, ensure_ascii=False)
    last = json.dumps({special: 2}, ensure_ascii=False)
    jsonl = f"{first}\n\n{invalid}\n{{\n \t\n{last}\n"
    missing = GENERATED + "absent-input.json"
    require(not (ROOT / missing).exists(), "reserved missing-input path exists")
    result = []

    def add(name, group, args, code, status, report_type, stdin=b""):
        result.append(dict(name=name, group=group, args=args, code=code,
                           status=status, report_type=report_type, stdin=stdin))

    for value in ("true", "false"):
        add("check-" + value, "independent-check",
            ["--check-schema", GENERATED + value + ".schema.json"],
            0, "supported", None)
    person = ["-v", "--schema", FIXTURES + "person.schema.json"]
    add("single-invalid", "single-file", person + [
        "-f", FIXTURES + "extra-property.json"], 1, "invalid", "validation")
    add("stdin-valid", "stdin-success", person, 0, "valid", "validation",
        (ROOT / FIXTURES / "valid.json").read_bytes())
    add("stdin-parse", "stdin-parse-error", person, 1, "error", "validation",
        '{"name":"中文",'.encode("utf-8"))
    add("schema-first", "schema-priority", [
        "-v", "--schema", FIXTURES + "unsupported.schema.json", "-f", missing,
    ], 2, "error", "validation")
    add("cycle", "evaluation-cycle", [
        "-v", "--schema", FIXTURES + "cycle.schema.json",
        "-f", FIXTURES + "valid.json",
    ], 2, "error", "validation")
    add("batch-mixed", "batch", [
        "-v", "--schema", FIXTURES + "batch.schema.json",
        "-f", FIXTURES + "batch-invalid.json",
        "-f", FIXTURES + "batch-cycle.json",
        "-f", FIXTURES + "valid.json",
    ], 2, "error", "batchValidation")
    add("jsonl-stdin", "jsonl-stdin", [
        "-v", "--schema", GENERATED + "special.schema.json", "--jsonl",
    ], 1, "error", "jsonlValidation", jsonl.encode("utf-8"))
    return result, special


def check_issue(issue, stage, kind, location):
    require(issue["stage"] == stage, "wrong issue stage")
    require(issue["kind"] == kind, "wrong issue kind")
    require(issue["location"] == location, "wrong issue location")
    require(isinstance(issue["message"], str) and bool(issue["message"]),
            "missing human-readable diagnostic")


def check_fields(case, report, special):
    require(isinstance(report, dict), "report must be an object")
    require(type(report["reportVersion"]) is int and report["reportVersion"] == 1,
            "wrong report version")
    require(report["status"] == case["status"], "wrong status")
    args = case["args"]
    schema_option = "--check-schema" if case["report_type"] is None else "--schema"
    require(report["schemaFile"] == args[args.index(schema_option) + 1],
            "wrong schemaFile")
    require(isinstance(report["issues"], list), "issues must be an array")
    name = case["name"]
    if case["report_type"] is None:
        require(not any(key in report for key in
                        ("reportType", "inputFile", "results", "summary")),
                "independent check acquired another mode's fields")
        require(report["issues"] == [], "successful check has issues")
        return
    require(report["reportType"] == case["report_type"], "wrong reportType")
    if case["report_type"] != "batchValidation":
        source = args[args.index("-f") + 1] if "-f" in args else "<stdin>"
        require(report["inputFile"] == source, "wrong inputFile")
    if name == "stdin-valid":
        require(report["issues"] == [], "valid stdin has issues")
    elif name in ("single-invalid", "stdin-parse", "schema-first", "cycle"):
        require(len(report["issues"]) == 1, "expected one issue")
        issue = report["issues"][0]
        if name == "single-invalid":
            check_issue(issue, "input", "ValidationError", "extra")
        elif name == "stdin-parse":
            check_issue(issue, "input", "ParseError", None)
        elif name == "schema-first":
            check_issue(issue, "schema", "UnsupportedFeature", "unevaluatedProperties")
        else:
            check_issue(issue, "evaluation", "ReferenceCycle", None)
            require(issue["instancePointer"] == "", "root instance pointer changed")
            require(issue["schemaPointer"] == "/$ref", "wrong schema pointer")
    elif name == "batch-mixed":
        require(report["issues"] == [], "file issues leaked into batch issues")
        summary = report["summary"]
        for key, value in dict(requested=3, processed=3, valid=1, invalid=1, errors=1).items():
            require(type(summary[key]) is int and summary[key] == value,
                    "wrong batch count: " + key)
        rows = report["results"]
        require(len(rows) == 3, "wrong result count")
        require(all(type(row["exitCode"]) is int for row in rows), "file exitCode must be integer")
        paths = [args[i + 1] for i, value in enumerate(args) if value == "-f"]
        require([row["inputFile"] for row in rows] == paths, "batch order changed")
        require([row["status"] for row in rows] == ["invalid", "error", "valid"],
                "wrong file statuses")
        require([row["exitCode"] for row in rows] == [1, 2, 0], "wrong file exits")
        check_issue(rows[0]["issues"][0], "input", "ValidationError", "n")
        cycle = rows[1]["issues"][0]
        check_issue(cycle, "evaluation", "ReferenceCycle", None)
        require(cycle["instancePointer"] == "/loop", "wrong batch instance pointer")
        require(cycle["schemaPointer"] == "/properties/loop/$ref", "wrong batch schema pointer")
        require(rows[2]["issues"] == [], "later valid file has issues")
    elif name == "jsonl-stdin":
        require(report["issues"] == [], "record issues leaked into top-level issues")
        for key, value in dict(records=4, valid=2, invalid=1, errors=1).items():
            require(type(report["summary"][key]) is int and report["summary"][key] == value,
                    "wrong JSONL count: " + key)
        rows = report["results"]
        require(all(type(row["line"]) is int and type(row["exitCode"]) is int for row in rows),
                "record line and exitCode must be integers")
        require([row["line"] for row in rows] == [1, 3, 4, 6], "wrong actual line numbers")
        require([row["status"] for row in rows] == ["valid", "invalid", "error", "valid"],
                "wrong record statuses")
        require([row["exitCode"] for row in rows] == [0, 1, 1, 0], "wrong record exits")
        check_issue(rows[1]["issues"][0], "input", "ValidationError", special)
        check_issue(rows[2]["issues"][0], "input", "ParseError", None)
        require(rows[0]["issues"] == [] and rows[3]["issues"] == [],
                "valid records have issues")


def reject_constant(value):
    raise ValueError("non-JSON numeric constant: " + value)


def run_case(cli, case, special):
    stdout, stderr, actual = b"", b"", None
    reasons = []
    command = [str(cli), "--no-color", "--schema-output=json"] + case["args"]
    (OUTPUT / (case["name"] + ".stdin")).write_bytes(case["stdin"])
    try:
        process = subprocess.run(command, cwd=ROOT, input=case["stdin"],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 timeout=20, check=False)
        stdout, stderr, actual = process.stdout, process.stderr, process.returncode
    except subprocess.TimeoutExpired as error:
        stdout, stderr = error.stdout or b"", error.stderr or b""
        reasons.append("CLI timed out after 20 seconds")
    except OSError as error:
        reasons.append("cannot start native CLI: " + str(error))
    name = case["name"]
    (OUTPUT / (name + ".stdout")).write_bytes(stdout)
    (OUTPUT / (name + ".stderr")).write_bytes(stderr)
    if actual != case["code"]:
        reasons.append(f"expected exit {case['code']}, got {actual}")
    if b"\x1b" in stdout or b"\x1b" in stderr:
        reasons.append("raw output contains an ANSI escape")
    selected, other = (stdout, stderr) if case["code"] == 0 else (stderr, stdout)
    if other:
        reasons.append("unselected stream is not empty")
    try:
        # Decode and parse the entire stream, never locate/extract a JSON fragment.
        report = json.loads(selected.decode("utf-8"), parse_constant=reject_constant)
        check_fields(case, report, special)
    except (ValueError, AssertionError, KeyError, TypeError, IndexError) as error:
        reasons.append(f"report check failed: {type(error).__name__}: {error}")
    print(("FAIL " if reasons else "PASS ") + name)
    for reason in reasons:
        print("  " + reason)
    return dict(name=name, group=case["group"], command=command,
                expected_exit=case["code"], actual_exit=actual,
                passed=not reasons, failures=reasons,
                stdin=name + ".stdin", stdout=name + ".stdout", stderr=name + ".stderr")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path,
                        help="Use an already-built native CLI; relative paths resolve from repository root")
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    summary = dict(cli=None, cli_sha256=None, build=None, results=[], fatal_errors=[])
    # Invalidate an earlier successful run before starting any build/process.
    write_json("summary.json", {**summary, "status": "running"})
    try:
        if args.cli is None:
            command = ["moon", "build", "--target", "native", "--debug", "--frozen", "cmd/main"]
            try:
                build = subprocess.run(command, cwd=ROOT, stdin=subprocess.DEVNULL,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       timeout=300, check=False)
                build_out, build_err, build_code = build.stdout, build.stderr, build.returncode
            except subprocess.TimeoutExpired as error:
                (OUTPUT / "build.stdout").write_bytes(error.stdout or b"")
                (OUTPUT / "build.stderr").write_bytes(error.stderr or b"")
                raise RuntimeError("native build timed out after 300 seconds") from error
            (OUTPUT / "build.stdout").write_bytes(build_out)
            (OUTPUT / "build.stderr").write_bytes(build_err)
            summary["build"] = dict(command=command, exit_code=build_code)
            require(build_code == 0, "native build failed; see build.stdout/build.stderr")
            cli = CLI_ARTIFACT
        else:
            cli = (ROOT / args.cli).resolve()
        summary["cli"] = str(cli)
        require(cli.is_file(), "native CLI artifact not found: " + str(cli))
        summary["cli_sha256"] = hashlib.sha256(cli.read_bytes()).hexdigest()
        scenario_cases, special = cases()
        for case in scenario_cases:
            summary["results"].append(run_case(cli, case, special))
    except (OSError, ValueError, AssertionError, RuntimeError) as error:
        summary["fatal_errors"].append(str(error))
        print("FAIL setup: " + str(error))
    rows = summary["results"]
    passed = sum(row["passed"] for row in rows)
    groups = len({row["group"] for row in rows})
    success = bool(rows) and passed == len(rows) and not summary["fatal_errors"]
    summary.update(status="passed" if success else "failed", groups=groups,
                   executed=len(rows), passed=passed, failed=len(rows) - passed)
    write_json("summary.json", summary)
    text = f"Schema report acceptance: {passed}/{len(rows)} passed, {groups} groups; {summary['status']}."
    (OUTPUT / "summary.txt").write_text(text + "\n", encoding="utf-8")
    print(text)
    print("Evidence: " + str(OUTPUT))
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
