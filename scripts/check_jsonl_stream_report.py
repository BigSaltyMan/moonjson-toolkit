"""Check native JSONL JSON reports with a real, incrementally written stdin.

Build first with: moon build --target native
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parent.parent
CLI_ARTIFACT = ROOT / "_build/native/debug/build/cmd/main/main.exe"
OUTPUT = ROOT / "_build/jsonl-stream-report-acceptance"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def reject_constant(value):
    raise ValueError("non-JSON constant: " + value)


def run_case(cli, name, schema, parts, needs_eof):
    command = [str(cli), "-v", "--jsonl", "--schema", str(schema),
               "--schema-output", "json", "--no-color"]
    process = None
    actual = None
    waited_for_eof = False
    exited_with_stdin_open = False
    failures = []
    # Files let us check for premature output portably, without pipe deadlocks
    # or reader threads. Popen itself is deliberately not a context manager.
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        try:
            process = subprocess.Popen(command, cwd=ROOT, stdin=subprocess.PIPE,
                                       stdout=out, stderr=err)
            if needs_eof:
                for part in parts:
                    process.stdin.write(part)
                    process.stdin.flush()
                    try:
                        process.wait(timeout=0.25)
                    except subprocess.TimeoutExpired:
                        pass
                    else:
                        raise AssertionError("CLI exited before stdin EOF")
                    require(not process.stdin.closed, "stdin was closed during waiting check")
                    require(out.seek(0, 2) == 0 and err.seek(0, 2) == 0,
                            "CLI emitted output before stdin EOF")
                waited_for_eof = True
                process.stdin.close()
                process.stdin = None
                actual = process.wait(timeout=10)
            else:
                # No data is sent and stdin stays open until after process exit.
                actual = process.wait(timeout=10)
                exited_with_stdin_open = not process.stdin.closed
        except (OSError, ValueError, AssertionError, subprocess.SubprocessError) as error:
            failures.append(str(error))
        finally:
            if process is not None:
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=5)
                actual = process.returncode
                if process.stdin is not None:
                    try:
                        process.stdin.close()
                    except OSError as error:
                        failures.append("stdin cleanup: " + str(error))
            out.seek(0)
            err.seek(0)
            stdout, stderr = out.read(), err.read()
    expected_code = 1 if needs_eof else 2
    try:
        require(actual == expected_code, f"expected exit {expected_code}, got {actual}")
        require(waited_for_eof if needs_eof else exited_with_stdin_open,
                "stdin lifecycle assertion was not completed")
        require(stdout == b"", "stdout must be empty on failure")
        require(b"\x1b" not in stdout + stderr, "output contains an ANSI escape")
        # Parse the entire selected stream; extra text or a second JSON fails.
        report = json.loads(stderr.decode("utf-8"), parse_constant=reject_constant)
        require(type(report["reportVersion"]) is int and report["reportVersion"] == 1,
                "wrong report version")
        require(report["reportType"] == "jsonlValidation", "wrong report type")
        require(report["schemaFile"] == str(schema), "wrong schemaFile")
        require(report["inputFile"] == "<stdin>", "wrong inputFile")
        if needs_eof:
            require(report["status"] == "invalid", "wrong overall status")
            require(report["summary"] == dict(records=3, valid=2, invalid=1, errors=0),
                    "wrong record counts")
            require(report["issues"] == [], "unexpected top-level issue")
            rows = report["results"]
            require([row["line"] for row in rows] == [1, 3, 4], "wrong actual line numbers")
            require([row["status"] for row in rows] == ["valid", "invalid", "valid"],
                    "lost or misclassified record")
            require([row["exitCode"] for row in rows] == [0, 1, 0], "wrong record exits")
            require(rows[0]["issues"] == [] and rows[2]["issues"] == [], "unexpected valid-record issue")
            issue = rows[1]["issues"][0]
            require(len(rows[1]["issues"]) == 1 and issue["stage"] == "input"
                    and issue["kind"] == "ValidationError" and issue["location"] == "n",
                    "wrong validation issue")
        else:
            require(report["status"] == "error", "wrong schema failure status")
            require(report["summary"] == dict(records=0, valid=0, invalid=0, errors=0),
                    "schema failure must not fabricate records")
            require(report["results"] == [], "schema failure has input results")
            require(len(report["issues"]) == 1, "expected one schema issue")
            issue = report["issues"][0]
            require(issue["stage"] == "schema" and issue["kind"] == "UnsupportedFeature"
                    and issue["location"] == "unevaluatedProperties", "wrong schema issue")
        require(isinstance(issue["message"], str) and bool(issue["message"]), "empty issue message")
    except (ValueError, AssertionError, KeyError, TypeError, IndexError) as error:
        failures.append(str(error))
    (OUTPUT / (name + ".stdout")).write_bytes(stdout)
    (OUTPUT / (name + ".stderr")).write_bytes(stderr)
    print(("FAIL " if failures else "PASS ") + name)
    for failure in failures:
        print("  " + failure)
    return dict(name=name, command=command, expected_exit=expected_code, actual_exit=actual,
                waited_for_eof=waited_for_eof, exited_with_stdin_open=exited_with_stdin_open,
                passed=not failures, failures=failures)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path,
                        help="Already-built native CLI; relative paths resolve from repository root")
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    summary = dict(status="running", results=[], fatal_errors=[])
    summary_path = OUTPUT / "summary.json"
    summary_path.write_text(json.dumps(summary) + "\n", encoding="utf-8")
    try:
        cli = (ROOT / args.cli).resolve() if args.cli else CLI_ARTIFACT
        require(cli.is_file(), "native CLI not found; run moon build --target native: " + str(cli))
        supported = OUTPUT / "supported.schema.json"
        unsupported = OUTPUT / "unsupported.schema.json"
        supported.write_text('{"properties":{"n":{"type":"integer"}}}\n', encoding="utf-8")
        unsupported.write_text('{"unevaluatedProperties":false}\n', encoding="utf-8")
        parts = [b'{"n":1,"text":"\xf0\x9f', b'\x98\x80"}\r\n\r\n{"n":"bad"}\n', b'{"n":2}']
        summary["results"].append(run_case(cli, "stdin-segments-then-eof", supported, parts, True))
        summary["results"].append(run_case(cli, "schema-error-before-input", unsupported, [], False))
    except (OSError, ValueError, AssertionError, subprocess.SubprocessError) as error:
        summary["fatal_errors"].append(str(error))
        print("FAIL setup: " + str(error))
    rows = summary["results"]
    passed = sum(row["passed"] for row in rows)
    success = len(rows) == 2 and passed == 2 and not summary["fatal_errors"]
    summary.update(status="passed" if success else "failed", executed=len(rows), passed=passed)
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"JSONL stream report CLI: {passed}/{len(rows)} passed; {summary['status']}.")
    print("Evidence: " + str(OUTPUT))
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
