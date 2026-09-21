#!/usr/bin/env bash
#
# Time the tool on the documents bench/generate.sh writes.
#
#   bench/run.sh [--runs N]
#
# Each document is formatted and then validated, and the shell's own `time` does
# the measuring, so every number in the table can be reproduced by hand. Each one
# is the best of three runs: the first run of a file pays for reading it off the
# disk, and the smallest of these numbers is close enough to the noise floor that
# a single unlucky run would say more about the machine than about the tool.
#
# The binary is the release build. A debug build is several times slower and
# would be measuring the wrong thing, so run.sh builds the release one if it is
# not there. The documents are generated on demand for the same reason: they are
# in .gitignore, being output rather than source.
#
# The sizes in the table are what generate.sh wrote, which is close to but not
# exactly the 1 KB, 1 MB and 10 MB those files are named for.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$here")"
binary="$root/_build/native/release/build/cmd/main/main.exe"
runs=3

usage() {
  printf 'usage: bench/run.sh [--runs N]\n'
  printf '\n'
  printf 'Times the release build on bench/small.json, bench/medium.json and\n'
  printf 'bench/large.json, formatting and validating each, best of N runs.\n'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --runs)
      runs="${2:-}"
      case "$runs" in
        ''|*[!0-9]*) printf 'bench: --runs wants a number\n' >&2; exit 2 ;;
      esac
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

errors="$(mktemp)"
trap 'rm -f "$errors"' EXIT

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

# A byte count, written the way a person would.
size_of() {
  awk -v bytes="$(wc -c <"$1")" 'BEGIN {
    if (bytes < 1024) {
      printf "%d B", bytes
    } else if (bytes < 1048576) {
      printf "%.1f KB", bytes / 1024
    } else {
      printf "%.1f MB", bytes / 1048576
    }
  }'
}

if [ ! -x "$binary" ]; then
  printf 'building the release binary\n'
  (cd "$root" && moon build --target native --release)
fi

generated=true
for name in small medium large; do
  if [ ! -f "$here/$name.json" ]; then
    generated=false
  fi
done
if [ "$generated" = false ]; then
  printf 'generating the documents\n'
  "$here/generate.sh" >/dev/null
fi

"$binary" --version
printf 'best of %s runs, times in seconds\n\n' "$runs"

printf '%-14s %-10s %-10s %-10s\n' file size format validate
for name in small medium large; do
  file="$here/$name.json"
  format="$(best_of "$runs" "$binary" --file "$file")"
  validate="$(best_of "$runs" "$binary" --validate --file "$file")"
  printf '%-14s %-10s %-10s %-10s\n' \
    "$name.json" "$(size_of "$file")" "$format s" "$validate s"
done
