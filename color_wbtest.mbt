///|
/// The colour decision is tested through `env_allows_color` and
/// `output_is_terminal` rather than through `is_tty`, because the answer
/// `is_tty` gives depends on where standard output of the test process happens
/// to point, and a test that asserted one of the two answers would be asserting
/// something about the machine it ran on. `moon test` can be run with a
/// terminal on standard output or with a pipe, and the process it starts cannot
/// be either of those and `/dev/null` within one run.
///
/// Between them the two functions are the whole of the decision, and both take
/// the facts they read as arguments, so every case can be stated exactly — the
/// one a terminal cannot reach included.

///|
test "NO_COLOR switches colour off" {
  // Any non-empty value does it, and the value is never read: the convention
  // exists so that a setting in a shell profile is obeyed by every tool that
  // reads it, and `NO_COLOR=0` means the same as `NO_COLOR=1`.
  assert_false(env_allows_color(Some("1"), Some("xterm-256color")))
  assert_false(env_allows_color(Some("0"), Some("xterm-256color")))
  assert_false(env_allows_color(Some("true"), Some("xterm-256color")))
  // It outranks TERM, including a TERM that would otherwise have allowed colour.
  assert_false(env_allows_color(Some("1"), Some("dumb")))
  // An empty value is not a setting, so it switches nothing off.
  assert_true(env_allows_color(Some(""), Some("xterm-256color")))
}

///|
test "an absent or empty TERM does not allow colour" {
  assert_false(env_allows_color(None, None))
  assert_false(env_allows_color(None, Some("")))
  // `dumb` is the value that has always meant "no escape sequences here".
  assert_false(env_allows_color(None, Some("dumb")))
}

///|
test "a normal TERM allows colour" {
  assert_true(env_allows_color(None, Some("xterm-256color")))
  assert_true(env_allows_color(None, Some("screen")))
}

///|
test "NO_COLOR is obeyed on a terminal as well as off one" {
  // The case this test exists for is the first line: a terminal with NO_COLOR
  // set. A rule that let the terminal decide on its own would colour that run
  // happily, and it would be wrong — a terminal is the only place `NO_COLOR`
  // ever matters, so it is the one place the variable must not be skipped.
  assert_false(color_allowed(Some("1"), Some("xterm-256color"), Some(true)))
  assert_false(color_allowed(Some("1"), Some("xterm-256color"), Some(false)))
  assert_true(color_allowed(None, Some("xterm-256color"), Some(true)))
  // TERM cannot rescue output that is not a terminal: it stays set when a
  // document is redirected to a file, which is exactly when colour would end up
  // inside the file.
  assert_false(color_allowed(None, Some("xterm-256color"), Some(false)))
  // Nothing known about the output leaves the environment's answer standing.
  assert_true(color_allowed(None, Some("xterm-256color"), None))
  assert_false(color_allowed(Some("1"), Some("xterm-256color"), None))
  assert_false(color_allowed(None, None, None))
}

///|
test "a character device is a terminal unless it is the null device" {
  // The ordinary case: a shell running the tool with nothing redirected, where
  // `/proc/self/fd/1` is a link to the pty the shell is on.
  assert_eq(
    output_is_terminal(@fs.CharDevice, Some("/dev/pts/0"), "/dev/null"),
    Some(true),
  )
  // The case this pair exists for. `/dev/null` is a character device, so the
  // kind says "terminal" and only the target says otherwise.
  assert_eq(
    output_is_terminal(@fs.CharDevice, Some("/dev/null"), "/dev/null"),
    Some(false),
  )
  // A character device whose link could not be read is still a character
  // device, and that is the more useful half of what is known about it.
  assert_eq(output_is_terminal(@fs.CharDevice, None, "/dev/null"), Some(true))
}

///|
test "output that is not a character device is not a terminal" {
  // A pipe, a file and a socket are the cases the redirect in the README
  // produces, and none of them can be a terminal whatever it resolves to.
  assert_eq(output_is_terminal(@fs.Pipe, None, "/dev/null"), Some(false))
  assert_eq(
    output_is_terminal(@fs.Regular, Some("/tmp/out.json"), "/dev/null"),
    Some(false),
  )
  assert_eq(output_is_terminal(@fs.Socket, None, "/dev/null"), Some(false))
  assert_eq(
    output_is_terminal(@fs.Directory, Some("/dev"), "/dev/null"),
    Some(false),
  )
  // Nothing is claimed when the probe itself did not answer.
  assert_eq(output_is_terminal(@fs.Unknown, None, "/dev/null"), None)
}

///|
test "the null device is compared as a path, not assumed to be one" {
  // The path is an argument for the same reason the two variables are: it is a
  // fact about the platform, and a test that wants to state the rule should not
  // have to be on a machine where the null device is spelled the usual way.
  assert_eq(
    output_is_terminal(@fs.CharDevice, Some("/dev/null"), "/devices/null"),
    Some(true),
  )
  assert_eq(
    output_is_terminal(@fs.CharDevice, Some("/devices/null"), "/devices/null"),
    Some(false),
  )
}

///|
test "colour is refused for the null device and allowed for a terminal" {
  // The end of the chain, with both halves of the decision present: the same
  // environment, two destinations, two answers. These are the two runs the bug
  // this rule fixes got wrong, since `tool > /dev/null` was coloured and
  // `tool > out.json` was not.
  let terminal = color_allowed(
    None,
    Some("xterm-256color"),
    output_is_terminal(@fs.CharDevice, Some("/dev/pts/0"), "/dev/null"),
  )
  let null_device = color_allowed(
    None,
    Some("xterm-256color"),
    output_is_terminal(@fs.CharDevice, Some("/dev/null"), "/dev/null"),
  )
  assert_true(terminal)
  assert_false(null_device)
}

///|
test "colour wraps the text and passes it through untouched" {
  // The wrapping is the same code either way, so both directions are checked
  // here: escape sequences when colour is on, and the very same string back
  // when it is not. The second is the one the rest of the suite leans on —
  // `moon test` compares plain messages against coloured ones, and every one of
  // those comparisons would fail if the pass-through were wrong.
  assert_eq(paint("error:", "31", true), "\u{1b}[31merror:\u{1b}[0m")
  assert_eq(
    paint("line 1, column 2", "33", true),
    "\u{1b}[33mline 1, column 2\u{1b}[0m",
  )
  assert_eq(paint("error:", "31", false), "error:")
  assert_eq(paint("line 1, column 2", "33", false), "line 1, column 2")
  // Colour is off unless the runner turns it on, which is the state every other
  // test in this package runs in.
  assert_eq(red("error:"), "error:")
  assert_eq(yellow("line 1, column 2"), "line 1, column 2")
}
