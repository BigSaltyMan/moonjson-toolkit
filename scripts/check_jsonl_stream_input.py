"""Check JSONL text validation exits while its real stdin pipe stays open.

Build first with: moon build --target native
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
CLI_ARTIFACT = ROOT / "_build/native/debug/build/cmd/main/main.exe"
OUTPUT = ROOT / "_build/jsonl-stream-input-acceptance"


def run_case(cli, name, args, payload, code, expected, forbidden):
    command = [str(cli), *args, "--no-color"]
    process = None
    stdout = stderr = b""
    actual = None
    exited_with_stdin_open = False
    failures = []
    try:
        process = subprocess.Popen(
            command, cwd=ROOT, stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        if payload:
            process.stdin.write(payload)
            process.stdin.flush()
        # Do not use communicate(input=...), a context manager or close stdin
        # before this wait: those could turn the test into an ordinary EOF test.
        try:
            actual = process.wait(timeout=10)
            exited_with_stdin_open = not process.stdin.closed
        except subprocess.TimeoutExpired:
            failures.append("CLI did not exit within 10 seconds with stdin open")
            process.kill()
            actual = process.wait(timeout=5)
        process.stdin.close()
        process.stdin = None
        stdout, stderr = process.communicate(timeout=5)
        if actual != code:
            failures.append(f"expected exit {code}, got {actual}")
        if not exited_with_stdin_open:
            failures.append("exit while stdin remained open was not observed")
        if stdout:
            failures.append("stdout must be empty")
        if not stderr:
            failures.append("stderr must contain the text diagnostic")
        text = stderr.decode("utf-8")
        for fragment in expected:
            if fragment not in text:
                failures.append("missing diagnostic: " + fragment)
        for fragment in forbidden:
            if fragment in text:
                failures.append("unexpected diagnostic: " + fragment)
        if b"\x1b" in stdout or b"\x1b" in stderr:
            failures.append("output contains an ANSI escape")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        failures.append(str(error))
    finally:
        if process is not None:
            if process.poll() is None:
                process.kill()
            # On failures too, reap the child and release all three pipe handles.
            process.wait(timeout=5)
            for stream in (process.stdin, process.stdout, process.stderr):
                if stream is not None:
                    stream.close()
    (OUTPUT / (name + ".stdout")).write_bytes(stdout)
    (OUTPUT / (name + ".stderr")).write_bytes(stderr)
    print(("FAIL " if failures else "PASS ") + name)
    for failure in failures:
        print("  " + failure)
    return dict(name=name, command=command, expected_exit=code,
                actual_exit=actual, exited_with_stdin_open=exited_with_stdin_open,
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
        if not cli.is_file():
            raise FileNotFoundError("native CLI not found; run moon build --target native: " + str(cli))
        schema = OUTPUT / "unsupported.schema.json"
        schema.write_text('{"unevaluatedProperties":false}\n', encoding="utf-8")
        summary["results"].append(run_case(
            cli, "fail-fast-before-eof", ["-v", "--jsonl", "--fail-fast"],
            b"{\n", 1, ["<stdin> is not valid JSON", "line 1, column"],
            ["valid JSON, and every record", "cannot read standard input"],
        ))
        summary["results"].append(run_case(
            cli, "schema-check-before-input", ["-v", "--jsonl", "--schema", str(schema)],
            b"", 2, ["unevaluatedProperties"],
            ["<stdin> is not valid JSON", "cannot read standard input", "every record matches"],
        ))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        summary["fatal_errors"].append(str(error))
        print("FAIL setup: " + str(error))
    rows = summary["results"]
    passed = sum(row["passed"] for row in rows)
    success = len(rows) == 2 and passed == 2 and not summary["fatal_errors"]
    summary.update(status="passed" if success else "failed", executed=len(rows), passed=passed)
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"JSONL stream input CLI: {passed}/{len(rows)} passed; {summary['status']}.")
    print("Evidence: " + str(OUTPUT))
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
