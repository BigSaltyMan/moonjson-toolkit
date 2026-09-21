#!/usr/bin/env bash
#
# Generate the documents the benchmark reads.
#
#   bench/generate.sh [output directory]
#
# Three sizes, because the tool is doing something different at each of them: on
# a small document almost all of the work is starting the process and reading the
# file, a megabyte is where the reading itself starts to show, and ten megabytes
# is the size the fast path in parser.mbt exists for.
#
# The sizes are targets rather than exact figures — the order of magnitude is the
# point — but all three documents are inside the parser's limits (nesting under
# 128, under 65536 items in any one array, under 262144 characters in any one
# string), so all three are read by the fast path rather than falling back to the
# library parser. A benchmark that quietly measured the fallback would measure
# the wrong thing.
#
# The output is generated with awk rather than a MoonBit program so that this
# script needs nothing but a shell, and so that the benchmark cannot fail to run
# because of the very toolchain it is measuring.

set -euo pipefail

out="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
mkdir -p "$out"

# ~1 KB. A few levels of nesting: an object holding a config object, an array of
# records, and inside each record another object and another array.
awk 'BEGIN {
  records = 6
  print "{\"name\": \"moonjson-toolkit\", \"version\": \"0.1.0\","
  print "  \"config\": {\"indent\": 2, \"sort_keys\": false,"
  print "    \"limits\": {\"depth\": 128, \"strings\": 262144, \"arrays\": 65536}},"
  print "  \"records\": ["
  for (i = 0; i < records; i++) {
    printf "    {\"id\": %d, \"title\": \"record %d\", \"tags\": [\"parser\", \"formatter\", \"benchmark\"], \"meta\": {\"ok\": %s, \"score\": %.2f, \"note\": null}}%s\n",
      i + 1, i + 1, (i % 2 ? "false" : "true"), (i + 1) / 4,
      (i + 1 < records ? "," : "")
  }
  print "  ]}"
}' >"$out/small.json"

# ~1 MB. Objects and arrays mixed, one array at the root so the whole document is
# read in one pass with nothing to skip over.
awk 'BEGIN {
  records = 5000
  printf "["
  for (i = 0; i < records; i++) {
    printf "%s\n  {\"id\": %d, \"name\": \"record-%05d\", \"active\": %s, \"score\": %.3f,",
      (i ? "," : ""), i, i, (i % 3 ? "false" : "true"), i * 1.5
    printf " \"tags\": [\"alpha\", \"beta\", \"gamma\"],"
    printf " \"meta\": {\"created\": \"2026-01-01T00:00:00Z\", \"visits\": %d, \"ratio\": %.4f},",
      i, (i % 1000) / 1000
    printf " \"values\": [%d, %d, %d, %d, %d]}", i, i + 1, i + 2, i + 3, i + 4
  }
  printf "\n]"
}' >"$out/medium.json"

# ~10 MB, and deliberately awkward: a chain of objects forty deep, arrays long
# enough to matter, and a string just under the length limit, so that the reading
# is doing something at every level rather than repeating one flat record.
awk 'BEGIN {
  depth = 40
  numbers = 60000
  rows = 200
  columns = 250
  records = 58000
  characters = 250000

  printf "{"
  # Forty levels of nesting, written in one line: what makes this file big is
  # the records below, but a deep document is the one shape a reader that keeps
  # a stack can get wrong.
  printf "\"deep\":"
  for (i = 1; i <= depth; i++) {
    printf "{\"level\":%d,\"child\":", i
  }
  printf "null"
  for (i = 1; i <= depth; i++) {
    printf "}"
  }
  printf ",\"numbers\":["
  for (i = 0; i < numbers; i++) {
    printf "%s%d", (i ? "," : ""), i
  }
  printf "]"
  printf ",\"matrix\":["
  for (r = 0; r < rows; r++) {
    printf "%s[", (r ? "," : "")
    for (c = 0; c < columns; c++) {
      printf "%s%d", (c ? "," : ""), r * c
    }
    printf "]"
  }
  printf "]"
  printf ",\"records\":["
  for (i = 0; i < records; i++) {
    printf "%s{\"id\":%d,\"label\":\"item-%06d\",\"value\":%.3f,\"flags\":[true,false],", (i ? "," : ""), i, i, i * 0.25
    printf "\"note\":\"a note long enough that a record looks like a record and not a row of digits\"}"
  }
  printf "]"
  # Just under the 262144 character limit, so this document is still read by the
  # fast path — a string over it would send the whole file to the library.
  printf ",\"text\":\""
  for (i = 0; i < characters; i++) {
    printf "a"
  }
  printf "\"}"
}' >"$out/large.json"

for name in small medium large; do
  printf '%-12s %s bytes\n' "$name.json" "$(wc -c <"$out/$name.json")"
done
