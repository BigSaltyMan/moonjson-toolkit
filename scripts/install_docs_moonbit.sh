#!/usr/bin/env bash
# Isolated, fixed toolchain for registry documentation compatibility only.
set -euo pipefail
version='0.10.16%2Bb1a0e846e'
if [[ "$(uname -ms)" != 'Linux x86_64' ]]; then
  echo 'This CI installer supports Linux x86_64 only.' >&2
  exit 2
fi
docs_moon_home=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/moonjson-docs-toolchain-XXXXXX")
archive_dir=$(mktemp -d)
trap 'rm -rf "$archive_dir"' EXIT
curl -fsSL --retry 3 "https://cli.moonbitlang.com/binaries/$version/moonbit-linux-x86_64.tar.gz" -o "$archive_dir/moon.tar.gz"
curl -fsSL --retry 3 "https://cli.moonbitlang.com/cores/core-$version.tar.gz" -o "$archive_dir/core.tar.gz"
(
  cd "$archive_dir"
  printf '%s\n' \
    '84ae424cd31bc485d2cf4d3736534e52f2f265ceafb562a187b9ab26d9566212  moon.tar.gz' \
    'e7db6e3c80a97af953598b374cf14f3e330918b1ca4659b141b9f550c9c0adb0  core.tar.gz' \
    | sha256sum --check --strict
)
mkdir -p "$docs_moon_home/lib"
tar -xzf "$archive_dir/moon.tar.gz" -C "$docs_moon_home"
tar -xzf "$archive_dir/core.tar.gz" -C "$docs_moon_home/lib"
chmod +x "$docs_moon_home/bin/"* "$docs_moon_home/bin/internal/tcc"
export MOON_HOME="$docs_moon_home"
export PATH="$docs_moon_home/bin:$PATH"
moon -C "$docs_moon_home/lib/core" bundle --warn-list -a --all
versions=$(moon version --all)
grep -F 'moon 0.1.20261020 (2284bd2 2026-10-20)' <<< "$versions"
grep -F 'moonc v0.10.16+b1a0e846e' <<< "$versions"
if [[ -n ${GITHUB_PATH:-} ]]; then printf '%s\n' "$docs_moon_home/bin" >> "$GITHUB_PATH"; fi
if [[ -n ${GITHUB_ENV:-} ]]; then printf 'MOON_HOME=%s\n' "$docs_moon_home" >> "$GITHUB_ENV"; fi
