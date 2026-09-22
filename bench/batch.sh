#!/usr/bin/env bash
#
# Time the tool on a batch of many small documents: once as one process per
# file, once as one process for all of them.
#
#   bench/batch.sh [--runs N] [--files N]
#
# The documents are copies of bench/small.json, made in a scratch directory that
# is removed on the way out. A directory of small files is the shape a batch is
# worth having for: what is being measured is the cost of opening and reading
# each file, which is what a run over a long list of them is mostly made of.
#
# Each number is the best of N runs, for the reason bench/run.sh gives: the
# fastest run is the one least interfered with. The batch reads four files at a
# time, and its time is not the sum of the per-file ones — each read waits on
# the disk, and a wait is what another file's work fills. The third row of the
# table in the README is the same batch with that window set to one file, which
# is not a flag: it is a rebuild of runner.mbt with `max_parallel_inputs` set
# to 1, and it is what the difference in that table is measured against.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"
binary="$root/_build/native/release/build/cmd/main/main.exe"
runs=7
files=200

usage() {
  printf 'usage: bench/batch.sh [--runs N] [--files N]\n'
  printf '\n'
  printf 'Times the release build over N copies of bench/small.json, once with a\n'
  printf 'process per file and once as a single batch, best of N runs.\n'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --runs|--files)
      value="${2:-}"
      case "$value" in
        ''|*[!0-9]*)
          printf 'bench: %s wants a number\n' "$1" >&2
          exit 2
          ;;
      esac
      if [ "$1" = "--runs" ]; then runs="$value"; else files="$value"; fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'bench: unknown argument %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$files" -lt 1 ]; then
  printf 'bench: --files wants at least one file\n' >&2
  exit 2
fi

errors="$(mktemp)"
scratch="$(mktemp -d)"
trap 'rm -rf "$errors" "$scratch"' EXIT

# Time one run of the command, printing the seconds it took with no decoration.
# A run that fails stops the benchmark: a number for a command that did not work
# is worse than no number, and it is the tool's own error output that says why.
timed() {
  local seconds
  TIMEFORMAT='%R'
  seconds=$({ time "$@" >/dev/null 2>"$errors"; } 2>&1) || {
    printf 'bench: %s failed\n' "$*" >&2
    cat "$errors" >&2
    exit 1
  }
  printf '%s' "$seconds"
}

# The best of `count` runs of the command, which is the number to quote: the
# fastest run is the one least interfered with.
best_of() {
  local count="$1"
  shift
  local best=""
  local seconds
  for _ in $(seq "$count"); do
    seconds="$(timed "$@")"
    if [ -z "$best" ] ||
      awk -v new="$seconds" -v old="$best" 'BEGIN { exit !(new < old) }'; then
      best="$seconds"
    fi
  done
  printf '%s' "$best"
}

# One file per process, which is how the same documents were handled before the
# batch flags existed: the shell does the looping.
loop_over_files() {
  local file
  for file in "$scratch"/*.json; do
    "$binary" --file "$file" >/dev/null
  done
}

if [ ! -x "$binary" ]; then
  printf 'building the release binary\n'
  (cd "$root" && moon build --target native --release)
fi

if [ ! -f "$here/small.json" ]; then
  printf 'generating the documents\n'
  "$here/generate.sh" >/dev/null
fi

printf 'copying %s documents into %s\n' "$files" "$scratch"
index=0
while [ "$index" -lt "$files" ]; do
  index=$((index + 1))
  cp "$here/small.json" "$scratch/$(printf 'doc-%05d.json' "$index")"
done

# The whole batch as one command line, which is what the two are compared on.
arguments=()
for file in "$scratch"/*.json; do
  arguments+=(--file "$file")
done

"$binary" --version
printf 'best of %s runs, times in seconds\n\n' "$runs"

printf '%-14s %-10s %-10s %-10s\n' input files separate batch
printf '%-14s %-10s %-10s %-10s\n' small.json "$files" \
  "$(best_of "$runs" loop_over_files) s" \
  "$(best_of "$runs" "$binary" "${arguments[@]}") s"
