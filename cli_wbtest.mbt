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
  assert_eq(options.file, None)
  assert_eq(options.indent, 2)
  assert_eq(options.validate, false)
  assert_eq(options.help, false)
  assert_eq(options.ai, false)
  assert_eq(options.json_out, None)
}

///|
test "--file takes a separate argument" {
  assert_eq(cli_ok(["--file", "a.json"]).file, Some("a.json"))
}

///|
test "-f takes a separate argument" {
  assert_eq(cli_ok(["-f", "a.json"]).file, Some("a.json"))
}

///|
test "a long option may carry its value after an equals sign" {
  assert_eq(cli_ok(["--file=a.json"]).file, Some("a.json"))
}

///|
test "a short option may carry its value with no separator" {
  assert_eq(cli_ok(["-fa.json"]).file, Some("a.json"))
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
  assert_eq(options.file, Some("a.json"))
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
test "the usage text documents every option" {
  let text = usage()
  for
    option in [
      "-f", "--file", "-i", "--indent", "-v", "--validate", "-h", "--help", "--ai",
      "--json-out",
    ] {
    assert_true(text.contains(option))
  }
}
