#!/usr/bin/env bash
# Small, offline CLI demonstrations, not a second Schema test runner.
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
fixtures=examples/schema-acceptance
output=_build/schema-acceptance
mkdir -p "$output"
printf 'Schema acceptance did not complete.\n' > "$output/summary.txt"
: > "$output/results.tsv"
moon version --all > "$output/toolchain.txt"
git rev-parse HEAD > "$output/checkout.txt"
moon build --target native cmd/main > "$output/build.stdout" 2> "$output/build.stderr"
failures=0

run_case() {
  local name=$1 expected=$2 actual
  shift 2
  # Expected nonzero statuses must not escape set -e.
  if moon run --quiet --target native cmd/main -- --no-color -v "$@" \
      > "$output/$name.stdout" 2> "$output/$name.stderr"; then
    actual=0
  else
    actual=$?
  fi
  printf '%s\tactual=%s\texpected=%s\n' "$name" "$actual" "$expected" | tee -a "$output/results.tsv"
  if [[ $actual -ne $expected ]]; then
    failures=$((failures + 1))
    printf 'FAIL: %s exit status differs\n' "$name" >&2
  fi
  if [[ $expected -ne 0 ]]; then
    if [[ $name != mixed-* && $name != reversed-batch && -s "$output/$name.stdout" ]]; then
      failures=$((failures + 1))
      printf 'FAIL: %s printed a success/output verdict\n' "$name" >&2
    fi
    if grep -Fq 'matches the schema' "$output/$name.stderr" "$output/$name.stdout"; then
      failures=$((failures + 1))
      printf 'FAIL: %s printed a success verdict\n' "$name" >&2
    fi
  fi
}

contains() {
  if ! grep -Fq -- "$2" "$output/$1.stderr"; then
    failures=$((failures + 1))
    printf 'FAIL: %s missing diagnostic: %s\n' "$1" "$2" >&2
  fi
}

run_case valid 0 --schema "$fixtures/person.schema.json" -f "$fixtures/valid.json"
if [[ -s "$output/valid.stderr" ]] || ! grep -Fq 'matches the schema' "$output/valid.stdout"; then
  failures=$((failures + 1))
  printf 'FAIL: valid case lacks a clean success verdict\n' >&2
fi

run_case extra-property 1 --schema "$fixtures/person.schema.json" -f "$fixtures/extra-property.json"
contains extra-property 'extra: additional property is not allowed'

run_case one-of-overlap 1 --schema "$fixtures/one-of.schema.json" -f "$fixtures/one-of-overlap.json"
contains one-of-overlap 'it matches 2 oneOf branches; exactly one is required'

run_case unsupported 2 --schema "$fixtures/unsupported.schema.json" -f "$fixtures/valid.json"
contains unsupported 'unevaluatedProperties: keyword is not supported'

run_case invalid-parameter 2 --schema "$fixtures/invalid-parameter.schema.json" -f "$fixtures/valid.json"
contains invalid-parameter 'minLength:'
contains invalid-parameter 'nonnegative integer'

run_case reference-cycle 2 --schema "$fixtures/cycle.schema.json" -f "$fixtures/valid.json"
contains reference-cycle 'schema validation could not complete'
contains reference-cycle 'reference cycle at instance (root), schema /$ref'

run_case mixed-jsonl 1 --schema "$fixtures/person.schema.json" --jsonl --continue-on-error -f "$fixtures/mixed.jsonl"
contains mixed-jsonl 'line 2 does not match the schema'
contains mixed-jsonl 'extra: additional property is not allowed'
if grep -Eq 'line (1|3) ' "$output/mixed-jsonl.stderr"; then
  failures=$((failures + 1))
  printf 'FAIL: mixed-jsonl reported a valid record as a failure\n' >&2
fi
if ! grep -Fq 'Summary: 0 passed, 1 failed' "$output/mixed-jsonl.stdout"; then
  failures=$((failures + 1))
  printf 'FAIL: mixed-jsonl did not report its file-level failure summary\n' >&2
fi

run_case mixed-batch 2 --schema "$fixtures/batch.schema.json" --continue-on-error -f "$fixtures/batch-invalid.json" -f "$fixtures/batch-cycle.json"
run_case reversed-batch 2 --schema "$fixtures/batch.schema.json" --continue-on-error -f "$fixtures/batch-cycle.json" -f "$fixtures/batch-invalid.json"
for name in mixed-batch reversed-batch; do
  contains "$name" 'batch-invalid.json does not match the schema'
  contains "$name" 'n: it is a string where the schema expects an integer'
  contains "$name" 'batch-cycle.json schema validation could not complete'
  contains "$name" 'reference cycle at instance /loop, schema /properties/loop/$ref'
  if ! grep -Fq 'Summary: 0 passed, 2 failed' "$output/$name.stdout"; then
    failures=$((failures + 1))
    printf 'FAIL: %s did not report both failed files\n' "$name" >&2
  fi
done

if [[ $failures -ne 0 ]]; then
  printf 'Schema acceptance FAILED: %s checks differ; see %s\n' "$failures" "$output" | tee "$output/summary.txt" >&2
  exit 1
fi
printf 'Schema acceptance passed: 9 cases; exit codes and diagnostics match.\n' | tee "$output/summary.txt"
