#!/usr/bin/env bash
# Fixed official archives, verified before extraction; no latest installer.
set -euo pipefail
version='0.10.13%2Bcbb11c36f'
if [[ "$(uname -ms)" != 'Linux x86_64' ]]; then
  echo 'This CI installer supports Linux x86_64 only.' >&2
  exit 2
fi
archive_dir=$(mktemp -d)
trap 'rm -rf "$archive_dir"' EXIT
moon_home=${MOON_HOME:-"$HOME/.moon"}
curl -fsSL --retry 3 "https://cli.moonbitlang.com/binaries/$version/moonbit-linux-x86_64.tar.gz" -o "$archive_dir/moon.tar.gz"
curl -fsSL --retry 3 "https://cli.moonbitlang.com/cores/core-$version.tar.gz" -o "$archive_dir/core.tar.gz"
(
  cd "$archive_dir"
  printf '%s\n' \
    'ef643f267d5ee075dbafd54b44b0a26c55116340515dca07294c2a0b83479a8b  moon.tar.gz' \
    'd36b64c42df3019d9da87291e40738e90623c0380d0e200a62156091fb00c176  core.tar.gz' \
    | sha256sum --check --strict
)
mkdir -p "$moon_home/lib"
tar -xzf "$archive_dir/moon.tar.gz" -C "$moon_home"
tar -xzf "$archive_dir/core.tar.gz" -C "$moon_home/lib"
export PATH="$moon_home/bin:$PATH"
moon -C "$moon_home/lib/core" bundle --warn-list -a --all
versions=$(moon version --all)
grep -F 'moon 0.1.20260915 (2e1a46d 2026-09-15)' <<< "$versions"
grep -F 'moonc v0.10.13+cbb11c36f (2026-09-15)' <<< "$versions"
if [[ -n ${GITHUB_PATH:-} ]]; then printf '%s\n' "$moon_home/bin" >> "$GITHUB_PATH"; fi
