"""Check JSONL formatting through real native CLI stdin processes.

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
OUTPUT = ROOT / "_build/jsonl-stream-format-acceptance"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def run_case(cli, name, parts, fast, expected_stdout):
    command = [str(cli), "--jsonl", "--compact", "--no-color"]
    if fast:
        command.append("--fail-fast")
    process = None
    actual = None
    exited_with_stdin_open = False
    waited_for_eof = False
    failures = []
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        try:
            process = subprocess.Popen(command, cwd=ROOT, stdin=subprocess.PIPE,
                                       stdout=out, stderr=err)
            for part in parts:
                process.stdin.write(part)
                process.stdin.flush()
                if not fast:
                    try:
                        process.wait(timeout=0.25)
                    except subprocess.TimeoutExpired:
                        pass
                    else:
                        raise AssertionError("CLI exited before the final record and stdin EOF")
                    require(not process.stdin.closed, "stdin was closed during waiting check")
                    require(out.seek(0, 2) == 0 and err.seek(0, 2) == 0,
                            "CLI emitted output before completing this buffered run")
            if fast:
                # Keep stdin open: closing it here would hide an EOF dependency.
                actual = process.wait(timeout=10)
                exited_with_stdin_open = not process.stdin.closed
            else:
                waited_for_eof = True
                process.stdin.close()
                process.stdin = None
                actual = process.wait(timeout=10)
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
    expected_code = 1 if fast else 0
    try:
        require(actual == expected_code, f"expected exit {expected_code}, got {actual}")
        require(exited_with_stdin_open if fast else waited_for_eof,
                "stdin lifecycle assertion was not completed")
        require(stdout == expected_stdout, "formatted stdout content or record order differs")
        require(b"\x1b" not in stdout + stderr, "output contains an ANSI escape")
        if fast:
            diagnostic = stderr.decode("utf-8")
            require(diagnostic.startswith("error: <stdin> is not valid JSON\n"),
                    "missing stdin parse diagnostic")
            require("line 2, column 2:" in diagnostic, "wrong actual error position")
            require("cannot read standard input" not in diagnostic, "unexpected input read error")
        else:
            require(stderr == b"", "successful formatting must leave stderr empty")
    except (ValueError, AssertionError) as error:
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
        summary["results"].append(run_case(
            cli, "format-fail-fast-before-eof", [b'{"ok":1}\n{\n'], True, b'{"ok":1}\n',
        ))
        parts = ['{"text":"中文'.encode("utf-8") + b'\xf0\x9f',
                 b'\x98\x80"}\r\n \t\r\n', b'{"n":1e500,"exact":9007199254740993}']
        expected = '{"text":"中文😀"}\n{"n":1e500,"exact":9007199254740993}\n'.encode("utf-8")
        summary["results"].append(run_case(cli, "format-segments-then-eof", parts, False, expected))
    except (OSError, ValueError, AssertionError, subprocess.SubprocessError) as error:
        summary["fatal_errors"].append(str(error))
        print("FAIL setup: " + str(error))
    rows = summary["results"]
    passed = sum(row["passed"] for row in rows)
    success = len(rows) == 2 and passed == 2 and not summary["fatal_errors"]
    summary.update(status="passed" if success else "failed", executed=len(rows), passed=passed)
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"JSONL stream format CLI: {passed}/{len(rows)} passed; {summary['status']}.")
    print("Evidence: " + str(OUTPUT))
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
