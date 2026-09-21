///|
/// Parse `args`, failing the test if they are rejected.
fn cli_ok(args : Array[String]) -> CliOptions {
  match CliOptions::parse(args) {
    Ok(options) => options
    Err(message) => abort("expected these arguments to parse, got: " + message)
  }
}

///|
/// Parse `args`, failing the test if they are accepted, and return the message.
fn cli_err(args : Array[String]) -> String {
  match CliOptions::parse(args) {
    Ok(_) => abort("expected these arguments to be rejected")
    Err(message) => message
  }
}

///|
test "no arguments yields the documented defaults" {
  let options = cli_ok([])
  assert_eq(options.files, [])
  assert_eq(options.indent, 2)
  assert_eq(options.max_depth, None)
  assert_eq(options.compact, false)
  assert_eq(options.sort_keys, false)
  assert_eq(options.trim_strings, false)
  assert_eq(options.flatten, false)
  assert_eq(options.unflatten, false)
  assert_eq(options.prune_null, false)
  assert_eq(options.prune_empty, false)
  assert_eq(options.jsonl, false)
  assert_eq(options.paths, false)
  assert_eq(options.keys_only, false)
  assert_eq(options.stats, false)
  assert_eq(options.validate, false)
  assert_eq(options.help, false)
  assert_eq(options.version, false)
  assert_eq(options.ai, false)
  assert_eq(options.json_out, None)
  assert_eq(options.no_color, false)
}

///|
test "--version asks for the version" {
  assert_eq(cli_ok(["--version"]).version, true)
}

///|
test "-V asks for the version" {
  assert_eq(cli_ok(["-V"]).version, true)
}

///|
test "-v is still validate and -V is still version" {
  // The two are one shifted key apart and mean unrelated things, so the parser
  // must not treat them as the same flag.
  let lower = cli_ok(["-v"])
  assert_eq(lower.validate, true)
  assert_eq(lower.version, false)
  let upper = cli_ok(["-V"])
  assert_eq(upper.version, true)
  assert_eq(upper.validate, false)
}

///|
test "-V combines with other short flags" {
  let options = cli_ok(["-Vv"])
  assert_eq(options.version, true)
  assert_eq(options.validate, true)
}

///|
/// Pull the value out of the `version = "..."` line of a `moon.mod` file.
///
/// Written to fail loudly rather than quietly: a `moon.mod` this cannot read is
/// a broken test, not a passing one, so every unexpected shape aborts.
fn moon_mod_version(text : String) -> String {
  for line in text.split("\n") {
    if line.trim().has_prefix("version") {
      match line.split_once("\"") {
        Some((_, rest)) =>
          match rest.split_once("\"") {
            Some((value, _)) => return value.to_owned()
            None =>
              abort("the version line has no closing quote: " + line.to_owned())
          }
        None =>
          abort("the version line has no quoted value: " + line.to_owned())
      }
    }
  }
  abort("moon.mod has no version line")
}

///|
test "the version line reads as documented" {
  assert_eq(version_line(), "moonjson-toolkit 0.1.0")
}

///|
test "the version parser reads a moon.mod" {
  let sample = "# a comment\n\nname = \"someone/pkg\"\n\nversion = \"9.8.7\"\n"
  assert_eq(moon_mod_version(sample), "9.8.7")
}

///|
/// The point of this test: `moon.mod` is the one place the version is meant to
/// be edited, and the constant in `cli.mbt` is a second copy that MoonBit has
/// no way to derive from it. This fails the moment the two disagree, so the
/// copy cannot go stale without the suite saying so.
async test "the version constant matches moon.mod" {
  let text = try @fs.read_file("moon.mod").text() catch {
    error =>
      abort(
        "cannot read moon.mod from the test directory: " + error.to_string(),
      )
  } noraise {
    text => text
  }
  assert_eq(version, moon_mod_version(text))
}

///|
test "--file takes a separate argument" {
  assert_eq(cli_ok(["--file", "a.json"]).files, ["a.json"])
}

///|
test "-f takes a separate argument" {
  assert_eq(cli_ok(["-f", "a.json"]).files, ["a.json"])
}

///|
test "a long option may carry its value after an equals sign" {
  assert_eq(cli_ok(["--file=a.json"]).files, ["a.json"])
}

///|
test "a short option may carry its value with no separator" {
  assert_eq(cli_ok(["-fa.json"]).files, ["a.json"])
}

///|
test "-f may be repeated to name several files" {
  // The one value option that accumulates: a second `-f` adds an input rather
  // than replacing the first, and the order given is the order kept.
  assert_eq(cli_ok(["-f", "a.json", "-f", "b.json"]).files, ["a.json", "b.json"])
  // Every spelling adds to the same list, mixed freely.
  assert_eq(cli_ok(["--file=a.json", "-fb.json", "--file", "c.json"]).files, [
    "a.json", "b.json", "c.json",
  ])
  // The same file twice is two documents, not one: the list is not a set.
  assert_eq(cli_ok(["-f", "a.json", "-f", "a.json"]).files, ["a.json", "a.json"])
}

///|
test "--indent accepts every documented spelling" {
  assert_eq(cli_ok(["--indent", "4"]).indent, 4)
  assert_eq(cli_ok(["--indent=4"]).indent, 4)
  assert_eq(cli_ok(["-i", "4"]).indent, 4)
  assert_eq(cli_ok(["-i4"]).indent, 4)
  assert_eq(cli_ok(["-i=4"]).indent, 4)
}

///|
test "--indent accepts the range endpoints" {
  assert_eq(cli_ok(["-i0"]).indent, 0)
  assert_eq(cli_ok(["-i16"]).indent, 16)
}

///|
test "boolean flags are recognised in both spellings" {
  assert_true(cli_ok(["-v"]).validate)
  assert_true(cli_ok(["--validate"]).validate)
  assert_true(cli_ok(["-h"]).help)
  assert_true(cli_ok(["--help"]).help)
  assert_true(cli_ok(["--ai"]).ai)
}

///|
test "--compact asks for a single line" {
  assert_true(cli_ok(["-c"]).compact)
  assert_true(cli_ok(["--compact"]).compact)
  // It changes the layout only, so the indent keeps its default rather than
  // being zeroed here.
  assert_eq(cli_ok(["-c"]).indent, default_indent)
}

///|
test "--sort-keys asks for ordered keys" {
  assert_true(cli_ok(["-S"]).sort_keys)
  assert_true(cli_ok(["--sort-keys"]).sort_keys)
  // `-s` is not the same flag, and neither is it an alias for anything.
  assert_eq(cli_err(["-s"]), "unknown option: -s")
}

///|
test "--trim-strings asks for the strings to be trimmed" {
  assert_true(cli_ok(["--trim-strings"]).trim_strings)
  // It stands on its own: trimming is not something another flag implies.
  assert_false(cli_ok(["--trim-strings"]).sort_keys)
  assert_eq(cli_err(["--trim"]), "unknown option: --trim")
}

///|
test "--flatten and --unflatten are read, each on its own" {
  assert_true(cli_ok(["--flatten"]).flatten)
  assert_true(cli_ok(["--unflatten"]).unflatten)
  // Parsing does not decide anything about the pair: the two are read as the
  // flags they are, and whether the pair makes a run is settled later, where
  // every other question about the command line as a whole is settled.
  assert_false(cli_ok(["--flatten"]).unflatten)
  assert_false(cli_ok(["--unflatten"]).flatten)
  assert_eq(cli_err(["--flat"]), "unknown option: --flat")
  assert_eq(cli_err(["--flatten-keys"]), "unknown option: --flatten-keys")
}

///|
test "--prune-null and --prune-empty are read, together or apart" {
  assert_true(cli_ok(["--prune-null"]).prune_null)
  assert_true(cli_ok(["--prune-empty"]).prune_empty)
  // Unlike --flatten and --unflatten these do different things and compose, so
  // there is nothing to refuse about asking for both.
  let both = cli_ok(["--prune-null", "--prune-empty"])
  assert_true(both.prune_null)
  assert_true(both.prune_empty)
  // Neither is a shortening of the other, and the prefix alone is not a flag.
  assert_eq(cli_err(["--prune"]), "unknown option: --prune")
  assert_eq(cli_err(["--prune-nulls"]), "unknown option: --prune-nulls")
}

///|
test "--jsonl asks for the input to be read as JSON Lines" {
  assert_true(cli_ok(["--jsonl"]).jsonl)
  // It says how the input is written, not what to do with the document, so it
  // turns nothing else on with it.
  assert_false(cli_ok(["--jsonl"]).compact)
  assert_eq(cli_err(["--json-lines"]), "unknown option: --json-lines")
}

///|
test "--paths asks for the path list" {
  assert_true(cli_ok(["--paths"]).paths)
  // It stands on its own: nothing else is turned on with it.
  assert_false(cli_ok(["--paths"]).keys_only)
}

///|
test "--keys-only asks for the member list" {
  assert_true(cli_ok(["--keys-only"]).keys_only)
  assert_false(cli_ok(["--keys-only"]).paths)
  // `--keys` and `-k` are not abbreviations of it.
  assert_eq(cli_err(["--keys"]), "unknown option: --keys")
  assert_eq(cli_err(["-k"]), "unknown option: -k")
}

///|
test "--max-depth takes a nesting limit" {
  assert_eq(cli_ok(["--max-depth", "3"]).max_depth, Some(3))
  assert_eq(cli_ok(["--max-depth=3"]).max_depth, Some(3))
  // Zero is a limit like any other: nothing may nest.
  assert_eq(cli_ok(["--max-depth", "0"]).max_depth, Some(0))
}

///|
test "a max-depth that is not a natural number is rejected" {
  assert_eq(
    cli_err(["--max-depth", "abc"]),
    "invalid max-depth value: abc (expected an integer)",
  )
  assert_eq(
    cli_err(["--max-depth", "-1"]),
    "max-depth out of range: -1 (expected 0 or more)",
  )
}

///|
test "--stats asks for the summary" {
  assert_true(cli_ok(["--stats"]).stats)
  // It is not the same request as `--json-out`: one prints, the other writes.
  assert_eq(cli_ok(["--stats"]).json_out, None)
  assert_eq(cli_err(["--stat"]), "unknown option: --stat")
}

///|
test "--no-color switches colour off" {
  assert_true(cli_ok(["--no-color"]).no_color)
  // The default is the only other state there is: the terminal decides.
  assert_false(cli_ok([]).no_color)
  assert_eq(cli_err(["--no-colour"]), "unknown option: --no-colour")
}

///|
test "--json-out takes a path" {
  assert_eq(cli_ok(["--json-out", "s.json"]).json_out, Some("s.json"))
  assert_eq(cli_ok(["--json-out=s.json"]).json_out, Some("s.json"))
}

///|
test "short flags may be combined" {
  let options = cli_ok(["-vh"])
  assert_true(options.validate)
  assert_true(options.help)
}

///|
test "a value-taking flag may end a combined group" {
  let options = cli_ok(["-vi4"])
  assert_true(options.validate)
  assert_eq(options.indent, 4)
}

///|
test "options may appear in any order" {
  let options = cli_ok(["-i", "4", "-f", "a.json", "--ai"])
  assert_eq(options.indent, 4)
  assert_eq(options.files, ["a.json"])
  assert_true(options.ai)
}

///|
test "an unknown long option is rejected" {
  assert_eq(cli_err(["--nope"]), "unknown option: --nope")
}

///|
test "an unknown short option is rejected" {
  assert_eq(cli_err(["-x"]), "unknown option: -x")
}

///|
test "a missing option value is reported" {
  assert_eq(cli_err(["--file"]), "option --file requires a value")
  assert_eq(cli_err(["-i"]), "option -i requires a value")
}

///|
test "an empty option value is reported" {
  assert_eq(cli_err(["--file="]), "option --file requires a non-empty value")
}

///|
test "a non-numeric indent is rejected" {
  assert_eq(
    cli_err(["-i", "abc"]),
    "invalid indent value: abc (expected an integer)",
  )
}

///|
test "an out-of-range indent is rejected" {
  assert_eq(cli_err(["-i99"]), "indent out of range: 99 (expected 0 to 16)")
  assert_eq(cli_err(["-i-1"]), "indent out of range: -1 (expected 0 to 16)")
}

///|
test "a bare file name is not accepted as an option" {
  assert_eq(
    cli_err(["a.json"]),
    "unexpected argument: a.json (use --file <path> to name an input file)",
  )
}

///|
test "a lone dash is not an option" {
  assert_true(cli_err(["-"]).has_prefix("unexpected argument: -"))
}

///|
test "-- ends option parsing" {
  assert_true(cli_ok(["-v", "--"]).validate)
  assert_eq(
    cli_err(["--", "-f"]),
    "unexpected argument: -f (use --file <path> to name an input file)",
  )
}

///|
test "--model names the model to ask for" {
  assert_eq(
    cli_ok(["--ai", "--model", "gpt-4o-mini"]).model,
    Some("gpt-4o-mini"),
  )
  // The attached spelling goes through the same path as every other value
  // option, and the default leaves the choice to the environment.
  assert_eq(cli_ok(["--ai", "--model=qwen2.5"]).model, Some("qwen2.5"))
  assert_eq(cli_ok(["--ai"]).model, None)
  assert_eq(cli_err(["--ai", "--model"]), "option --model requires a value")
}

///|
test "--ai-base-url names the endpoint to post to" {
  let url = "http://localhost:11434/v1/chat/completions"
  assert_eq(cli_ok(["--ai", "--ai-base-url", url]).ai_base_url, Some(url))
  assert_eq(
    cli_err(["--ai", "--ai-base-url"]),
    "option --ai-base-url requires a value",
  )
}

///|
/// The two describe the one request `--ai` makes and nothing else, so a run
/// that never asks for a review neither reads them nor refuses them.
test "the AI options are accepted but ignored without --ai" {
  let options = cli_ok(["--model", "gpt-4o-mini", "-c"])
  assert_eq(options.ai, false)
  assert_eq(options.compact, true)
  assert_eq(options.model, Some("gpt-4o-mini"))
}

///|
test "the usage text documents every option" {
  let text = usage()
  for
    option in [
      "-f", "--file", "-i", "--indent", "-c", "--compact", "-S", "--sort-keys", "--trim-strings",
      "--flatten", "--unflatten", "--prune-null", "--prune-empty", "--jsonl", "--max-depth",
      "--paths", "--keys-only", "-v", "--validate", "-h", "--help", "-V", "--version",
      "--ai", "--model", "--ai-base-url", "--json-out", "--stats", "--no-color",
    ] {
    assert_true(text.contains(option))
  }
}
