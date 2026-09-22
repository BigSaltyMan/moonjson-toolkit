**English** | [简体中文](README.zh-CN.md)

# MoonJSON Toolkit

A JSON toolkit for MoonBit: format, validate, diagnose, analyse and visualise
JSON documents. It ships as a command line tool plus a small web dashboard that
charts the statistics the tool writes.

![The statistics dashboard](./frontend/screenshot.png)

## Features

- **Formatting** — pretty-prints any JSON document with 0 to 16 spaces per
  nesting level. Empty containers stay inline, strings are escaped correctly,
  and numbers keep the exact literal they had in the input. `--compact` puts
  the whole document on one line instead, `--sort-keys` orders the keys of
  every object before printing, and `--trim-strings` removes the whitespace
  around every string value while leaving the spaces inside one alone.
- **Several documents at once** — `--file` may be repeated. A few files are
  read at a time and answered in the order they were named, each under a
  `==> path <==` heading once there is more than one of them, and a file that
  fails does not stop the ones after it. `--fail-fast` asks for the run to end
  at that file instead, and `--continue-on-error` adds a summary of which inputs
  passed and which failed.
- **JSON Lines** — `--jsonl` reads an input whose lines are documents, one per
  line, and formats each of them onto a line of its own. A line that is not
  valid JSON is reported by its line number while the others are still printed.
- **Reshaping** — `--flatten` collapses every nested object into dotted keys,
  turning `{"a":{"b":1}}` into `{"a.b":1}`, and `--unflatten` expands them
  again. Both reach objects inside arrays, and both refuse a document that
  names one path two ways, naming the two keys that disagree.
- **Pruning** — `--prune-null` removes every object member whose value is
  `null`, and `--prune-empty` removes every empty object and every empty array,
  then the containers left empty by that. The two may be given together, nulls
  first, so `{"a":{"b":null}}` becomes `{}` in one pass.
- **Validation with diagnostics** — a malformed document reports the line, the
  column and the reason, and points at the offending character:

  ```
  error: <stdin> is not valid JSON
  line 1, column 8: expected opening quote
    {"a":1,}
           ^
  ```

  A line too long to print is elided around the column, the two ends it cut
  replaced by `...`, so a document written on one line is not reported at its
  full length — the line and column in the summary are always the ones in the
  document, and the caret is the recomputed one.

  A repeated key inside one object is an error for the same reason, reported at
  the second spelling of the key and naming the line and column of the first —
  silently keeping one of the two would mean the value you get back depends on
  the parser rather than on the document. `--max-depth <n>` puts the same kind of
  bound on nesting: any document deeper than `n` is refused, with the position
  where it went too far.
- **Paths and keys** — `--paths` lists the route to every value in the document,
  one per line, and `--keys-only` lists just the object members. Between them
  they answer "what is in here" without printing the document.

- **Statistics** — key counts, node counts, maximum nesting depth, the
  distribution of JSON types and a per-depth breakdown, written as JSON by
  `--json-out` or printed as a two-line summary by `--stats`.
- **Colour** — errors are coloured on a terminal and plain everywhere else, so
  a redirected run never has escape sequences in it. `--no-color` turns them
  off, as does the `NO_COLOR` and `TERM=dumb` conventions.
- **Charts** — a [Rabbita](https://github.com/moonbit-community/rabbita) web app
  renders the statistics file as a key-count bar chart, a nesting-depth pie
  chart and a type table.
- **AI review** — `--ai` sends the formatted document to an OpenAI-compatible
  API (DeepSeek by default) and prints a quality report with refactoring
  suggestions. The endpoint, the model and the key are all configurable.
- **MoonBit dependency analysis** — `--moon-deps` reads a module manifest and
  prints the tree of modules it depends on, drawn from the manifests in
  `.mooncakes`, and reports a module required at more than one version or a
  circular dependency beneath the tree. See
  [analyzing MoonBit dependencies](#analyzing-moonbit-dependencies).

## Requirements

- The [MoonBit toolchain](https://www.moonbitlang.com/download/) (developed
  against `moon 0.1.20260915`).
- A native target. The HTTP client and the async runtime are native only, so the
  command line tool builds for `native` rather than `wasm`.

## Installation

```sh
git clone https://github.com/BigSaltyMan/moonjson-toolkit.git
cd moonjson-toolkit
moon build --target native
```

Dependencies are declared in `moon.mod` and fetched by `moon build`:

```sh
moon add Nanaloveyuki/parsec   # parser combinators, with a JSON grammar
moon add oboard/mio            # HTTP client used by --ai
```

## Usage

```
moonjson-toolkit - format, validate and analyse JSON documents

Usage:
  moonjson-toolkit [options]

Input is read from standard input unless --file is given.

Options:
  -f, --file <path>      Read one or more input files instead of standard input
  -i, --indent <n>       Spaces per nesting level, 0 to 16 (default: 2)
  -c, --compact          Print the document on one line, ignoring --indent
  -S, --sort-keys        Order the keys of every object before printing
      --trim-strings     Trim the whitespace around every string in the document
      --flatten          Collapse every nested object into dotted keys
      --unflatten        Expand every dotted key back into nested objects
      --prune-null       Remove every object member whose value is null
      --prune-empty      Remove every empty object and every empty array
      --jsonl            Read the input as JSON Lines, one document per line
      --max-depth <n>    Refuse documents nested deeper than <n> (default: 128)
      --paths            Print the path of every value instead of the document
      --keys-only        Print only the paths that name an object member
  -v, --validate         Only check the input and report the first error
  -h, --help             Show this message and exit
  -V, --version          Show the version and exit
      --ai               Ask the AI for a quality report and suggestions
      --model <name>     Model to ask for instead of the default
      --ai-base-url <url>
                         Endpoint to post to instead of the default
      --moon-deps        Print the dependency tree of a MoonBit module
                         manifest
      --fail-fast        Stop at the first input that fails
      --continue-on-error
                         Process every input, then summarise the failures
      --json-out <path>  Write a statistics report as JSON to <path>
      --stats            Print a statistics summary instead of the document
      --no-color         Never colour the output, even on a terminal

Short options may be combined, so -vh means -v -h. The value of --indent
may be attached, as in -i4, -i=4, --indent=4 or --indent 4.

--file may be repeated. Each file is handled in turn, each under a
'==> path <==' heading once more than one is given, and the run exits with
the first non-zero code among them.

--fail-fast stops the run at the first input that fails, so a batch of
files ends at the one that went wrong rather than at the end of the list.
Without it every input named is read and every failure is reported as it
happens, which is the default; --continue-on-error asks for that same
reading and adds a summary of it at the end, naming each input that failed
and the message it failed with. The two describe one run in opposite
directions, so asking for both is refused. Under --jsonl the input is one
file however many records it holds, so --fail-fast stops at the first
record that fails, and --continue-on-error summarises the file.

--paths and --keys-only each replace the printed document with a list of
names, one per line. Asking for both prints the longer list, and -v wins
over either of them, since it asks for no document output at all.

--stats replaces the document with a two-line summary of it. It joins the
same family: -v wins over it as it wins over the name lists, and --json-out
takes precedence over it, so asking for both writes the file and prints the
document as usual. --json-out describes one document, so it is refused when
several files are named.

--flatten collapses every nested object into dotted keys, and --unflatten
expands them again. The two are inverses of each other, so only one of them
may be given. A document that names one path two ways, with a key "a.b"
beside a key "a", has no flattened or unflattened form and is refused with
both keys named.

--prune-null drops every object member whose value is null, and --prune-empty
drops every empty object and every empty array, then the containers left empty
by that in turn. The two are independent and may be given together, in which
case the nulls go first, so a member left holding {} is dropped as well.
--prune-null keeps every item of an array: a null in an object is a member with
no value, while a null in an array is a value in a place, and dropping it would
renumber the items after it.

--jsonl reads the input as JSON Lines: one document per line, with blank
lines skipped. Each record is handled on its own, so the other options apply
to every one of them in turn. A record that is not valid JSON is reported
with its line in the file and the rest are still printed; the run exits 1 if
any record failed. It describes many documents at once, so it is refused
with --json-out and with --ai.

--ai asks an OpenAI-compatible chat-completions API for a review of the
formatted document. The endpoint, the model and the key are taken from
--ai-base-url, --model and MOONJSON_AI_API_KEY, each falling back in turn
to MOONJSON_AI_BASE_URL, MOONJSON_AI_MODEL and DEEPSEEK_API_KEY, and then
to DeepSeek's own. There is no --api-key: a key on a command line is a key
in the shell history and in the process list.

--model and --ai-base-url describe that one request, so without --ai they
are read, accepted and ignored.

--moon-deps reads the input as a MoonBit module manifest and prints the
tree of modules it depends on, each dependency read in turn from the
.mooncakes directory beside the manifest. Both manifest forms are read:
moon.mod.json, and the moon.mod whose dependencies sit in an import block.
A dependency that has not been downloaded is shown with nothing under it,
and a module required at more than one version, or a circular dependency,
is reported beneath the tree. The tree is the whole of the output, so no
other option is consulted; --ai reviews the document instead, so under it
--moon-deps does nothing.

Exit codes:
  0  success
  1  the input could not be read, or is not valid JSON
  2  the command line was invalid
  3  the input was valid but the AI review failed
```

Short options may be combined, so `-vh` means `-v -h`. The value of `--indent`
may be attached, as in `-i4`, `-i=4`, `--indent=4` or `--indent 4`.

Note that `-v` and `-V` are different flags: the lower case one validates, the
upper case one prints the version.

`-v` replaces the formatted document with a one-line verdict. It is the only
thing it changes: `--json-out` and `--ai` still run. `--help` and `--version`
both answer without reading any input at all.

`--paths` and `--keys-only` also replace the document, with a list of names
rather than a verdict. Asking for both prints the longer list, and `-v` wins
over either of them, since it asks for no document output at all. Like `-v`,
neither of them stops the rest of the work: `--json-out` and `--ai` still run.

`--stats` replaces the document with a two-line summary of it. It joins the same
family: `-v` wins over it as it wins over the name lists, and `--json-out` takes
precedence over it, so asking for both writes the file and prints the document
as usual.

`--file` may be repeated, and each document is handled on its own. `--json-out`
describes a single document, so it is refused when several files are named
rather than written for whichever one came first.

A run over several files does not stop at one that fails: the failure is
reported as it happens, the files after it are still read, and the run ends with
the first non-zero code among them. A batch is read a few files at a time and
answered in the order they were named, so the documents keep the order of the
command line whatever order they were ready in. `--fail-fast` asks for the
opposite reading and ends the run at the first input that fails: what is already
in hand is printed, and the inputs after it are given up rather than waited for.
`--continue-on-error` keeps the default reading and adds a roll-call at the end,
naming every input that failed and what it said:

```sh
moonjson-toolkit -f a.json -f broken.json -f c.json --continue-on-error
# ==> a.json <==
# {
#   "a": 1
# }
# ==> c.json <==
# {
#   "c": 3
# }
#
# Summary: 2 passed, 1 failed
#   failed: broken.json
#     error: broken.json is not valid JSON
#     line 1, column 8: expected opening quote
#       {"a":1,}
#              ^
```

The failure was reported on standard error as it happened, where a run of many
files says what went wrong while it is still going; the summary repeats it on
standard output, so the place a run ends also says what it found. The count is
of inputs rather than of documents: `--jsonl` reads one file however many
records it holds, so a JSON Lines file counts once, and `--fail-fast` stops such
a file at the first record that fails rather than at the next one.

`--jsonl` declares what the input is, not what to do with it: each line is read
as a document of its own and the other options apply to every one of them in
turn, so `--compact`, `--sort-keys` or `--trim-strings` reach every record the
same way they reach a single document. Blank lines are skipped. `--json-out`,
`--ai`, `--stats`, `--paths` and `--keys-only` each answer a question about one
document, and a JSON Lines input is many, so they are refused rather than
repeated once per record with nothing to say which record an answer belongs to.
`-v` is not among them: it asks whether the input is valid, which is as good a
question about a file of many documents as about a file of one.

`--flatten` and `--unflatten` are inverses of each other, so asking for both is
not a pair of changes but a question about which one was meant, and the command
line is refused. A document that can be read either way is answered either way:
`{"a":{"b":1}}` and `{"a.b":1}` are the same document written two ways, and each
flag rewrites one into the other. Neither of them invents or drops anything —
flattening joins keys that were already written and unflattening splits them at
their dots — so the values, their order and even the empty containers survive
the trip.

A document that spells one path two ways has no flattened form to be had. If a
member is named `a.b` while a sibling named `a` holds an object, lifting `a`
produces a second `a.b`, and one of the two would have to be dropped; the run
exits `1` rather than settling it by a rule about which of them matters less.
Both keys are named, so the message says which pair to reconcile:

```
error: <stdin> cannot be flattened
conflicting keys: "a" and "a.b"
```

`--unflatten` refuses those shapes too, and is stricter: it decides by the keys
alone, so a key that is the dotted start of another key means one place is named
twice, whatever the value at the shorter key holds. A literal dotted key beside a
key holding anything but an object is no trouble at all, since nothing is lifted
and nothing collides: `{"a.b":1,"a":2}` flattens to itself.

`--prune-null` and `--prune-empty` remove what a document does not need, and are
independent of each other and of everything else, so they may be given together
or one at a time. The first drops every object member whose value is `null`: a
member holding `null` says no more than the member being absent. The second drops
every empty object and every empty array, and the containers that removal leaves
empty go as well, however far up that reaches. The document itself is not a
member of anything, so a run that prunes everything away still prints `{}` rather
than nothing at all.

`--prune-null` leaves arrays alone. An array is a sequence and its positions are
part of what it says, so a `null` in the middle of one is a value in a place, and
removing it would renumber the items after it — which is why `--prune-empty`,
whose whole business is removing things, does reach into arrays to drop the
empty containers in them. The two are applied nulls first when both are given:
`{"a":{"b":null}}` is `{}` once the member holding the null is left empty and
`--prune-empty` takes it, where the other order would stop at `{"a":{}}`.

`--flatten`, `--unflatten`, `--prune-null`, `--prune-empty`, `--sort-keys` and
`--trim-strings` change the document rather than its layout, so everything else
in the run sees the result: the printed document, the path list, the AI review,
and the counts behind `--stats` and `--json-out`, which describe what the run
produced rather than what came in. Sorting and trimming cannot tell the
difference — neither moves a value or changes its type — but pruning and
reshaping can, and a summary still counting members the document no longer has
would be describing something the reader cannot see.

### Exit codes

| Code | Meaning |
| ---- | ------- |
| `0`  | the input was formatted, or validated successfully |
| `1`  | the input could not be read, or is not valid JSON |
| `2`  | the command line itself was invalid |
| `3`  | the input was valid, but the AI review could not be produced |

A run that fails writes nothing to standard output for the document that failed.
All the work that can fail for one document happens before the first byte of it
is printed, so a failure never leaves a partly written document for whatever is
reading the output. With several files this holds per file: the ones that worked
are printed, the ones that did not are on standard error, and the exit code is
the first one that was not `0`. Under `--jsonl` it holds per record, since a
record is the unit that either parses or does not; a run that had any bad record
at all exits `1`, however many good ones followed it.

### Examples

Format a file with the default two-space indent:

```sh
moon run cmd/main -- -f test.json
```

```json
{
  "name": "moonjson-toolkit",
  "version": 2,
  "stable": true,
  "tags": [
    "json",
    "cli",
    "formatter"
  ],
  "owner": {
    "name": "MoonBit",
    "contact": {
      "email": "dev@moonbitlang.com",
      "active": true
    }
  },
  "dependencies": [
    {
      "name": "parsec",
      "version": "0.1.3"
    },
    {
      "name": "async",
      "version": "0.22.1"
    },
    {
      "name": "x",
      "version": "0.5.5"
    }
  ],
  "settings": {
    "indent": 2,
    "theme": null
  }
}
```

Handle several documents in one run. Each is formatted on its own, under a
heading that names the file it came from, and the headings appear only when
there is more than one document to tell apart:

```sh
moon run cmd/main -- -f a.json -f b.json
# ==> a.json <==
# {
#   "a": 1
# }
# ==> b.json <==
# {
#   "b": 2
# }
```

A file that cannot be read or parsed does not end the run. Its error goes to
standard error and the next file is still processed, so one bad input does not
hide the state of the rest; the run then exits with the first code that was not
`0`, which is `1` here:

```sh
moon run cmd/main -- -f a.json -f c.json -f b.json
# ==> a.json <==
# {
#   "a": 1
# }
# ==> b.json <==
# {
#   "b": 2
# }
# error: c.json is not valid JSON
# line 1, column 8: expected opening quote
#   {"c":3,}
#          ^
```

Format a file whose lines are documents, which is the shape a log or an export
usually arrives in. Each record is printed on a line of its own, and the blank
line is not a record:

```sh
printf '{"a":1}\n\n{"b":[2]}\n' | moon run cmd/main -- --jsonl
# {
#   "a": 1
# }
# {
#   "b": [
#     2
#   ]
# }
```

One bad line does not cost the reader the others. It is reported on standard
error, with its line number in the file, while every record that could be read
is still printed; the run then exits `1`:

```sh
printf '{"a":1}\n{"b":1,}\n{"c":3}\n' | moon run cmd/main -- --jsonl -c
# {"a":1}
# {"c":3}
# error: <stdin> is not valid JSON
# line 2, column 8: expected opening quote
#   {"b":1,}
#          ^
```

Trim the whitespace that crept into a document's strings. Only the ends of a
string are touched, so the spaces inside one are part of it and stay:

```sh
printf '{"name":"  moon  ","note":"  a  b  "}' | moon run cmd/main -- --trim-strings -c
# {"name":"moon","note":"a  b"}
```

Keys are names rather than values and are left exactly as they were written.
Trimming them would rename them, and two keys differing only in their surrounding
spaces would collapse into the repeated key the parser refuses — a document that
parsed would become one that would not.

Collapse the nesting of a document into dotted keys, which is the shape to hand
to anything that reads a flat table of names:

```sh
printf '{"a":{"b":{"c":1}},"d":[{"e":{"f":2}}]}' | moon run cmd/main -- --flatten -c
# {"a.b.c":1,"d":[{"e.f":2}]}
```

Expand them again, merging the keys that share a prefix as it goes:

```sh
printf '{"a.b":1,"a.c":{"d":2}}' | moon run cmd/main -- --unflatten -c
# {"a":{"b":1,"c":{"d":2}}}
```

A document that names one path two ways has no form to be had in either
direction, and is refused with both keys named:

```sh
printf '{"a":{"b":1},"a.b":2}' | moon run cmd/main -- --flatten -c
# error: <stdin> cannot be flattened
# conflicting keys: "a" and "a.b"
```

A literal dotted key beside a key holding something else is not that case:
nothing is lifted out of `a`, so nothing collides, and the document is already
flat.

Drop what a document does not say: the members that hold `null`, and the
containers that hold nothing. The two compose, and the nulls go first, so a
member left empty by a removal goes too:

```sh
printf '{"a":null,"b":{},"c":[1,null],"d":{"e":null}}' | moon run cmd/main -- --prune-null --prune-empty -c
# {"c":[1,null]}
```

The `null` inside the array is still there: an array is a sequence, and dropping
an item out of the middle would renumber the ones after it. An empty container is
a different matter, and `--prune-empty` does reach into arrays to remove one.

Read from a pipe and indent with four spaces:

```sh
echo '{"a":[1,2]}' | moon run cmd/main -- -i4
```

Collapse a document onto one line and order its keys, which is the pair to
reach for when the output is going to be compared or diffed rather than read:

```sh
echo '{"b":{"z":1,"a":2},"a":[{"y":3,"x":4}]}' | moon run cmd/main -- -cS
# {"a":[{"x":4,"y":3}],"b":{"a":2,"z":1}}
```

`--sort-keys` reaches every object in the document, including the ones nested
inside arrays, and compares keys by code point, so an upper case letter sorts
before a lower case one. It changes what is printed, not what `--json-out`
records: the statistics file keeps the order the document was written in.

Check a document without printing it:

```sh
moon run cmd/main -- -v -f test.json
# test.json: valid JSON
```

`-v` suppresses the formatted document and nothing else: `--json-out` still
writes its file and `--ai` still produces its report. The combinations compose,
so `-v --json-out stats.json` checks a document and collects its statistics
without printing the document itself:

```sh
moon run cmd/main -- -v --json-out stats.json -f test.json
# test.json: valid JSON
# statistics written to stats.json
```

Reject a malformed document (exit code `1`):

```sh
printf '{"a":1,}' | moon run cmd/main --
# error: <stdin> is not valid JSON
# line 1, column 8: expected opening quote
#   {"a":1,}
#          ^
```

Refuse a document that nests too deeply. The default limit is 128 levels; lower
it when the documents you expect are shallow and anything deeper is a mistake:

```sh
printf '[[[[]]]]' | moon run cmd/main -- --max-depth 3
# error: <stdin> is not valid JSON
# line 1, column 4: nesting depth exceeds limit 3
#   [[[[]]]]
#      ^
```

List what is in a document instead of printing it:

```sh
echo '{"name":"x","tags":["a","b"],"owner":{"email":"e"}}' | moon run cmd/main -- --paths
# name
# tags
# tags[0]
# tags[1]
# owner
# owner.email
```

`--keys-only` on the same input drops the array indices and stops at `tags`,
because a value inside an array is not reached:

```sh
echo '{"name":"x","tags":["a","b"],"owner":{"email":"e"}}' | moon run cmd/main -- --keys-only
# name
# tags
# owner
# owner.email
```

A repeated key is reported at the second spelling and names the first:

```sh
printf '{"a":1,"a":2}' | moon run cmd/main --
# error: <stdin> is not valid JSON
# line 1, column 8: duplicate object key "a" (first defined at line 1, column 2)
#   {"a":1,"a":2}
#          ^
```

Write a statistics report while formatting:

```sh
moon run cmd/main -- -f test.json --json-out stats.json
```

```json
{
  "total_keys": 19,
  "total_nodes": 26,
  "max_depth": 4,
  "type_counts": [
    { "kind": "null", "count": 1 },
    { "kind": "boolean", "count": 2 },
    { "kind": "number", "count": 2 },
    { "kind": "string", "count": 12 },
    { "kind": "array", "count": 2 },
    { "kind": "object", "count": 7 }
  ],
  "key_counts": [
    { "name": "name", "count": 0 },
    { "name": "version", "count": 0 },
    { "name": "stable", "count": 0 },
    { "name": "tags", "count": 0 },
    { "name": "owner", "count": 4 },
    { "name": "dependencies", "count": 6 },
    { "name": "settings", "count": 2 }
  ],
  "depth_counts": [
    { "depth": 1, "count": 1 },
    { "depth": 2, "count": 7 },
    { "depth": 3, "count": 10 },
    { "depth": 4, "count": 8 }
  ]
}
```

`key_counts` counts the keys nested inside each top-level field, so a field
holding a scalar or an array of scalars reports `0` — `name`, `version`,
`stable` and `tags` all do — while `owner` reports the four keys it holds
across its two levels, and `dependencies` reports six across its three entries.
`depth_counts` is 1-based and covers every level up to `max_depth`.

Ask for the same numbers on standard output instead of in a file:

```sh
moon run cmd/main -- --stats -f test.json
# keys: 19  nodes: 26  depth: 4
# type counts: null=1 boolean=2 number=2 string=12 array=2 object=7
```

The two lines say what the report above says, in the order it says it, with the
types the document does not contain left out rather than shown as `=0`.

## The statistics dashboard

The dashboard reads the file written by `--json-out`. It is a separate MoonBit
module under `frontend/`, built with Rabbita and compiled to JavaScript.

```sh
cd frontend

# 1. Produce the data the page reads.
moon run ../cmd/main -- -f ../test.json --json-out public/stats.json

# 2. Build the browser bundle.
warren build --browser-entry main

# 3. Serve dist/ over HTTP and open it.
python3 -m http.server 8000 --directory dist
```

Open <http://localhost:8000/> to see the bar chart of top-level key counts, the
pie chart of the nesting-depth distribution and the type table.

During development, `warren dev --browser-entry main` serves the app with live
reload instead.

[Apache ECharts](https://echarts.apache.org/) is vendored at
`frontend/public/echarts.min.js`, so the page needs no network access and no
CDN. If the file is missing, `charts.js` falls back to loading ECharts from a
CDN.

## AI review

`--ai` asks an OpenAI-compatible API for a review of the formatted document.
Left alone it asks DeepSeek, which is what this does:

```sh
export DEEPSEEK_API_KEY=sk-...
moon run cmd/main -- --ai -f test.json
```

The key is read from the environment and is never hardcoded, and there is no
`--api-key`: a key on a command line is a key in the shell history and in the
process list. A review that cannot be produced exits with code `3` and prints
the reason on standard error, leaving standard output empty. Documents longer
than 20 000 characters are truncated before they are sent, and the request times
out after 60 seconds.

## Using other LLM providers

The request is the chat-completions shape every provider now speaks, so pointing
it somewhere else is a matter of naming the endpoint and the model. Both come
from a flag or an environment variable, and a flag wins over the variable, which
wins over the default:

| Setting | Flag | Environment variable | Default |
| ------- | ---- | -------------------- | ------- |
| Endpoint | `--ai-base-url <url>` | `MOONJSON_AI_BASE_URL` | DeepSeek's |
| Model | `--model <name>` | `MOONJSON_AI_MODEL` | `deepseek-flash` |
| API key | — | `MOONJSON_AI_API_KEY`, else `DEEPSEEK_API_KEY` | — |

The endpoint is the whole URL rather than a base for the tool to append a path
to, because that is the spelling every provider documents and the one that
leaves nothing to guess. The two flags describe the one request `--ai` makes, so
without `--ai` they are read, accepted and ignored.

| Provider | `--ai-base-url` | `--model` |
| -------- | --------------- | --------- |
| DeepSeek (the default) | `https://api.deepseek.com/chat/completions` | `deepseek-flash` |
| Kimi (Moonshot) | `https://api.moonshot.cn/v1/chat/completions` | `kimi-k3` |
| 智谱 GLM | `https://open.bigmodel.cn/api/paas/v4/chat/completions` | `glm-4-flash` |
| OpenAI | `https://api.openai.com/v1/chat/completions` | `gpt-4o-mini` |
| Ollama (local) | `http://localhost:11434/v1/chat/completions` | `llama3.1` |

One command each, the key passed for that one run rather than exported:

```sh
# DeepSeek, which needs neither flag: this is the default
MOONJSON_AI_API_KEY=sk-... moon run cmd/main -- --ai -f test.json

# Kimi
MOONJSON_AI_API_KEY=sk-... moon run cmd/main -- --ai \
  --ai-base-url https://api.moonshot.cn/v1/chat/completions --model kimi-k3 -f test.json

# 智谱 GLM
MOONJSON_AI_API_KEY=... moon run cmd/main -- --ai \
  --ai-base-url https://open.bigmodel.cn/api/paas/v4/chat/completions --model glm-4-flash -f test.json

# OpenAI
MOONJSON_AI_API_KEY=sk-... moon run cmd/main -- --ai \
  --ai-base-url https://api.openai.com/v1/chat/completions --model gpt-4o-mini -f test.json

# Ollama, which asks for no key of its own: the tool still wants one to start
# a review, so any placeholder will do
MOONJSON_AI_API_KEY=ollama moon run cmd/main -- --ai \
  --ai-base-url http://localhost:11434/v1/chat/completions --model llama3.1 -f test.json
```

A shell that already exports `DEEPSEEK_API_KEY` keeps working untouched: that
name is still read, second only to `MOONJSON_AI_API_KEY`. Nothing else about the
exchange changes — the report is read from `choices[0].message.content`, and a
provider that reports a failure in the usual `error.message` envelope has its
message shown rather than swallowed.

## Analyzing MoonBit dependencies

`--moon-deps` reads its input as a MoonBit module manifest rather than as a
document, and prints the tree of modules it depends on. Run it in this
repository:

```sh
moon run cmd/main -- --moon-deps -f moon.mod
# BigSaltyMan/moonjson-toolkit@0.1.0
# ├── Nanaloveyuki/parsec@0.1.3
# ├── oboard/mio@0.5.4
# │   ├── moonbitlang/x@0.5.5
# │   ├── moonbitlang/async@0.22.1
# │   └── bikallem/compress@0.3.4
# │       ├── moonbitlang/async@0.22.1
# │       └── bikallem/blit@0.2.2
# ├── moonbitlang/x@0.5.5
# └── moonbitlang/async@0.22.1
#
# warning: 2 versions of moonbitlang/x are required
#   0.5.5 by BigSaltyMan/moonjson-toolkit@0.1.0
#   0.4.50 by oboard/mio@0.5.4
#
# warning: 3 versions of moonbitlang/async are required
#   0.22.1 by BigSaltyMan/moonjson-toolkit@0.1.0
#   0.20.6 by oboard/mio@0.5.4
#   0.16.7 by bikallem/compress@0.3.4
```

Each dependency's own manifest is read from the `.mooncakes` directory beside
the manifest, which is where `moon` downloads them for a run made from that
directory. A dependency that was not downloaded is shown by name with nothing
beneath it, so the tree reaches exactly as far as the fetch that preceded it.

A module is printed with the version of the manifest that was read from it. For
a module that was downloaded that is the version the toolchain resolved — the
copy sitting in `.mooncakes` — so `moonbitlang/x` above is shown under
`oboard/mio` as `0.5.5` even though `mio` asks for `0.4.50`: that is the copy
that is there. The warnings underneath are where the asking is written down
instead, and the same module reached from two places is drawn twice rather than
recognised, which is what `moon tree` does and what makes each warning readable
on its own.

Both manifest forms are read. `moon.mod.json` is JSON:

```sh
echo '{"name":"myproject","version":"0.1.0","deps":{"moonbitlang/x":"0.5.5"}}' \
  | moon run cmd/main -- --moon-deps
# myproject@0.1.0
# └── moonbitlang/x@0.5.5
```

`moon.mod` is a list of `key = value` lines whose dependencies sit in an
`import { "name@version", ... }` block, which is what the manifest of this
repository ends with:

```sh
tail -6 moon.mod
# import {
#   "Nanaloveyuki/parsec@0.1.3",
#   "oboard/mio@0.5.4",
#   "moonbitlang/x@0.5.5",
#   "moonbitlang/async@0.22.1",
# }
```

Which form a manifest is in is decided by the first character that is not white
space, not by the file name, so a manifest is read as what it is rather than as
what it is called. An entry that pins no version — `"moonbitlang/x"` on its own
— is a dependency that may be any version, and is printed by name.

A circular dependency is reported in the same place as the version warnings,
with the path that closes it:

```sh
# Two manifests in a scratch directory, each asking for the other.
mkdir -p /tmp/cycle/.mooncakes/b
printf 'name = "b"\n\nversion = "1.0.0"\n\nimport {\n  "a@1.0.0",\n}\n' > /tmp/cycle/.mooncakes/b/moon.mod
printf 'name = "a"\n\nversion = "1.0.0"\n\nimport {\n  "b@1.0.0",\n}\n' > /tmp/cycle/moon.mod

moon run cmd/main -- --moon-deps -f /tmp/cycle/moon.mod
# a@1.0.0
# └── b@1.0.0
#     └── a@1.0.0
#
# warning: circular dependency detected
#   a → b → a
```

Nothing that was published can have one — no build order exists for a module
that depends on itself — so this is a reading of a manifest rather than of a
working project. The walk stops at the module it would have entered a second
time rather than going round forever, which is why the name that closes the
circle is left in the tree as well as named underneath it.

The tree is the whole of the output: `--moon-deps` replaces the document rather
than adding to it, so no other option is consulted. `--jsonl` and `--json-out`
are refused beside it, since each would be answering about a different kind of
input than the one the tree describes, and `--ai` wins over it, since a review
describes the document.

## Project layout

```
moonjson-toolkit/
├── moon.mod              module metadata and dependencies
├── moon.pkg              the library package and its imports
├── formatter.mbt         pretty-printing
├── flatten.mbt           dotted keys out of nesting, and back again
├── prune.mbt             dropping null members and empty containers
├── jsonl.mbt             splitting a JSON Lines input into records
├── diagnostics.mbt       offsets to line/column, rendered error snippets
├── color.mbt             the colour decision and the escape wrapping
├── cli.mbt               argument parsing and usage text
├── parser.mbt            parsing and file/standard-input reading
├── paths.mbt             the path of every value, and of every object member
├── ai.mbt                the AI request, its settings and its response handling
├── moondeps.mbt          module manifests, read into a dependency tree
├── stats.mbt             the statistics model and its JSON form
├── runner.mbt            one run of the tool, and the exit codes
├── cmd/main/             the process entry point
└── frontend/             the Rabbita dashboard
    ├── main/main.mbt     the app: model, update and view
    └── public/           index.html, styles.css, charts.js, echarts.min.js
```

Every module is covered by whitebox tests in the matching `_wbtest.mbt` file.
The formatter, the diagnostics, the argument parser, the statistics, the
dependency analysis and the AI response handling all run without network access,
so `moon test` is the same command on every machine.

## Development

```sh
moon check --target native   # type-check
moon test  --target native   # 221 tests
moon fmt                     # format

cd frontend
moon test --target js        # 4 tests
```

## Test coverage

`moon test` can be run with instrumentation, which reports how much of every
module the suite reaches:

```sh
moon coverage analyze -- -f summary
```

```
ai.mbt: 80/90
cli.mbt: 143/147
cmd/main/main.mbt: 0/14
color.mbt: 41/43
diagnostics.mbt: 81/98
flatten.mbt: 100/102
formatter.mbt: 151/152
parser.mbt: 261/276
runner.mbt: 213/239
Total: 1485/1576
```

That is 1485 of the 1576 points the instrumentation watches, or 94.2%. The count
is of positions in the source rather than lines — a line carrying two expressions
is two points, and one of them can go unexecuted while the line itself is read as
covered — so a module is listed whenever any of its points went unexecuted, and
the five this block leaves out, `jsonl.mbt`, `moondeps.mbt`, `paths.mbt`,
`prune.mbt` and `stats.mbt`, are covered point for point. The same numbers,
ordered by how much of each module is reached:

| Module | Coverage |
| ------ | -------- |
| `jsonl.mbt`, `moondeps.mbt`, `paths.mbt`, `prune.mbt`, `stats.mbt` | 100% |
| `formatter.mbt` | 99.3% |
| `flatten.mbt` | 98.0% |
| `cli.mbt` | 97.3% |
| `color.mbt` | 95.3% |
| `parser.mbt` | 94.6% |
| `runner.mbt` | 89.1% |
| `ai.mbt` | 88.9% |
| `diagnostics.mbt` | 82.7% |
| `cmd/main/main.mbt` | 0% |

`cmd/main/main.mbt` is the one deliberate zero: it is the process entry point,
and `moon test` never runs `main`. What it does is hand the real command line and
the two real streams to `run`, which the suite covers directly instead.

The rest of what is missed is what needs something from outside the process.
`analyze` in `ai.mbt` — the only function that talks to a provider — is never
called, because no test may reach a real API. The standard-input paths in
`parser.mbt` and `runner.mbt` stay untouched, because every test names a file.
The two points left in `color.mbt` are both answers the kernel gives about a
standard output the suite cannot choose: a pipe resolves to no path, so the
branch that reads one back is never taken, and a pipe is a kind the kernel
describes plainly, so the branch for a probe that fails is never taken either.
`diagnostics.mbt` keeps the parse-error variants and limit kinds no input in the
suite manages to provoke.

Most of what is left in `parser.mbt` is the fast path, and the points there that
go unexecuted go unexecuted because reaching them would mean a bug: the two
`abort` lines after loops that leave only by returning, and the guards against an
escape cut short by the end of a string. The rest of them can only be
reached by a document the suite does not carry — one over the 64 MiB input cap,
which is the subject of the next section.

## Performance

`bench/run.sh` generates three documents and times the release build on each of
them, formatting and then validating:

```sh
bench/run.sh
```

```
moonjson-toolkit 0.1.0
best of 3 runs, times in seconds

file           size       format     validate
small.json     982 B      0.002 s    0.002 s
medium.json    1.1 MB     0.042 s    0.035 s
large.json     9.6 MB     0.304 s    0.248 s
```

Those numbers are from a Ryzen 9 8940HX under WSL2, and move by about a tenth
from run to run. `bench/generate.sh` writes the documents, and it is the only
part of the benchmark in the repository: the documents are output rather than
source, and are in `.gitignore`. The three are shaped differently on purpose —
1 KB of nested objects, 1 MB of objects and arrays mixed, and 10 MB of a
forty-deep chain beside a 60,000-item array, a 200×250 matrix and a
250,000-character string.

A list of files is read four at a time, and what that overlaps is the reading.
`bench/batch.sh` copies `bench/small.json` two hundred times and times one
process per file against one process for all of them:

```sh
bench/batch.sh
```

```
moonjson-toolkit 0.1.0
best of 7 runs, times in seconds

input          files      separate   batch
small.json     200        0.735 s    0.039 s
```

The same batch takes 0.117 s with the window set to one file. That row is not in
the script's table because the window is not a flag: it is `max_parallel_inputs`
in `runner.mbt`, so measuring it means rebuilding with that constant set to 1.
With two hundred documents of a kilobyte each, the window is worth three times
the speed — 0.039 s against 0.117 s — and eight files at a time measures no
better than four. A small file is mostly the wait for it to arrive, and four of
those waits are enough to cover each other.

The window is worth nothing measurable on sixteen documents of a megabyte each:
0.68 s against 0.71 s, which is inside the run-to-run spread. What a megabyte
costs is formatting it, and two files are never formatted at the same time —
`moonbitlang/async` runs its tasks on one thread and switches between them only
where one of them waits, so a batch overlaps its reading and nothing else. Over a
handful of large documents a batch is worth having for the one process and the
one command line, not for the window.

Ten megabytes is a size this tool could not read at all until recently. The
library parser refuses any document over 1 MiB, a cap it keeps to itself and
reports only when a document is already too long, so `parser.mbt` reads documents
itself now, up to 64 MiB. Reading was also where the time went: `parsec/json`
takes about a megabyte a second, which would have made ten megabytes ten seconds.
`parser.mbt` follows the same grammar with a scanner over the document's own code
units. On `medium.json` the library takes 1.21 s and the scanner takes 48 ms,
measured in the same build, which is the ratio behind the third of a second in
the large row.

The scanner is not a second opinion on what is wrong with a document. Everything
it will not accept is handed to the library parser, which is what names the
problem and says where it is, so every diagnostic is exactly the one the tool
gave before. What it does have to get right is which documents are good, and
`parser_differential_wbtest.mbt` measures that: over a corpus of documents and of
every single-character edit of them, the two readers accept the same documents
and read the same values out of them.

## Tech stack

| Piece | Used for |
| ----- | -------- |
| [MoonBit](https://www.moonbitlang.com/) | the whole project |
| [`Nanaloveyuki/parsec`](https://mooncakes.io/docs/Nanaloveyuki/parsec) | parser combinators, with the JSON grammar in `parsec/json` |
| [`oboard/mio`](https://mooncakes.io/docs/oboard/mio) | the HTTP request behind `--ai` |
| [`moonbitlang/async`](https://mooncakes.io/docs/moonbitlang/async) | async runtime, timeouts, file and standard-stream IO |
| [`moonbitlang/x`](https://mooncakes.io/docs/moonbitlang/x) | system helpers |
| [Rabbita](https://github.com/moonbit-community/rabbita) | the web dashboard, compiled to JavaScript |
| [Apache ECharts](https://echarts.apache.org/) | the bar and pie charts |

## Known limitations

- **`--ai` ignores proxy settings.** The request is written with a direct socket
  through `mio`, which does not read `http_proxy` or `https_proxy`. On a network
  that reaches the internet only through a proxy, `--ai` will fail to connect;
  run it somewhere the API is directly reachable, or route the traffic yourself.
  Everything else in the tool works offline.

- **Colour detection outside Linux falls back to the environment.** On Linux the
  tool asks the kernel whether standard output is a terminal, so a document
  redirected to a file is never coloured. Platforms without `/proc` have no such
  answer to hand without platform-specific calls this project does not make, so
  `TERM` is taken as the answer there instead. `TERM` stays set when output is
  redirected, so a redirected run on those platforms may be coloured after all;
  `--no-color` or `NO_COLOR=1` is the answer there, and both work everywhere.

- **A redirected run is recognised as not a terminal by its destination, and
  `/dev/null` is the only character device named.** `> /dev/null` is coloured
  nothing, because a character device output was sent to on purpose is otherwise
  what a terminal looks like, and the null device is the one such destination
  worth listing. `> /dev/zero` and `> /dev/full` are consequently treated as
  terminals, which costs nothing visible — the output is thrown away either
  way — and the alternative, listing which character devices *are* terminals,
  would risk the opposite mistake on a terminal this project has not seen.

- **A path is ambiguous when a key contains `.`, `[` or `]`.** Paths are written
  the way they are read rather than escaped, so `{"a.b": 1}` and
  `{"a": {"b": 1}}` both produce `a.b`, and `{"a[0]": 1}` is indistinguishable
  from the first element of an array named `a`. Keys that use those characters
  are rare enough to be worth the readable form; quote them, or read the path
  list alongside the document, when they turn up.

## Dependencies and Licenses

Every dependency is Apache-2.0, which is permissive and compatible with this
project's own license: it is not copyleft, it does not require this project to be
released under the same terms, and it asks only that the copyright and license
notices be kept. Nothing in the tree is GPL or AGPL.

| Dependency | Version | License |
| ---------- | ------- | ------- |
| [`Nanaloveyuki/parsec`](https://mooncakes.io/docs/Nanaloveyuki/parsec) | 0.1.3 | Apache-2.0 |
| [`oboard/mio`](https://mooncakes.io/docs/oboard/mio) | 0.5.4 | Apache-2.0 |
| [`moonbitlang/async`](https://mooncakes.io/docs/moonbitlang/async) | 0.22.1 | Apache-2.0 |
| [`moonbitlang/x`](https://mooncakes.io/docs/moonbitlang/x) | 0.5.5 | Apache-2.0 |
| [`moonbit-community/rabbita`](https://mooncakes.io/docs/moonbit-community/rabbita) | 0.15.2 | Apache-2.0 |

The first four are the command line tool's dependencies and are declared in
`moon.mod`; Rabbita is the dashboard's and is declared in `frontend/moon.mod`.
The license of each is the one declared in that package's own `moon.mod` on
Mooncakes, which is also what the copy under `.mooncakes/` carries.

The dependencies those pull in are Apache-2.0 as well: `bikallem/compress@0.3.4`
and `bikallem/blit@0.2.2`, which `oboard/mio` needs, and
`moonbitlang/async@0.20.5`, which Rabbita pins. `moon tree` prints the whole
closure from either module. The dashboard build also uses
[`moonbit-community/warren`](https://mooncakes.io/docs/moonbit-community/warren)
(Apache-2.0) from the command line, and the chart library is vendored: see the
license section below.

## License

Apache-2.0. ECharts is licensed under Apache-2.0 as well; its license text ships
with the vendored bundle at `frontend/public/echarts.LICENSE.txt`.
