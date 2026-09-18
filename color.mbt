///|
/// The environment half of the colour decision.
///
/// This is the whole of the convention the environment encodes, and it is pure
/// so that every case can be stated without touching the environment of the
/// process running the tests. `color_allowed` is where it is combined with what
/// is known about standard output.
///
/// `NO_COLOR` is honoured exactly the way the convention at no-color.org
/// describes it: the variable switches colour off when it is present and not
/// empty, and its *value* is never read — `NO_COLOR=0` means no colour just as
/// `NO_COLOR=1` does, because the point is that a user who sets it once, in
/// their shell profile, is obeyed by every tool that reads it.
///
/// `TERM` is the older convention and a weaker one. A terminal sets it to
/// something; `dumb` is the value that has always meant "no escape sequences
/// here", and an absent or empty `TERM` is treated the same way.
pub fn env_allows_color(no_color_var : String?, term : String?) -> Bool {
  let refused = match no_color_var {
    Some(value) => value != ""
    None => false
  }
  if refused {
    false
  } else {
    match term {
      Some(value) => value != "" && value != "dumb"
      None => false
    }
  }
}

///|
/// Whether colour may be used, given what the environment says and what is
/// known about where standard output is going.
///
/// Two questions have to agree, and the environment is asked first and asked
/// always — including when output is a terminal, which is the only place
/// `NO_COLOR` matters. A terminal is where colour appears, so a rule that let
/// the terminal answer first, or answer alone, would ignore `NO_COLOR` in
/// exactly the runs it exists for.
///
/// `output_is_terminal` is what the kernel says: `Some(true)` for a terminal,
/// `Some(false)` for a pipe or a file, and `None` when there was no way to find
/// out. `None` leaves the environment's answer standing, which is the best a
/// platform with nothing to ask can do.
///
/// This is a function of its three arguments rather than of the process, so
/// every combination can be tested — including the one a test suite cannot
/// otherwise reach, a terminal that has `NO_COLOR` set.
pub fn color_allowed(
  no_color_var : String?,
  term : String?,
  output_is_terminal : Bool?,
) -> Bool {
  if !env_allows_color(no_color_var, term) {
    false
  } else {
    match output_is_terminal {
      Some(is_terminal) => is_terminal
      None => true
    }
  }
}

///|
/// Whether colour may be used on standard output in this run.
///
/// On Linux the fact is available rather than guessed at: `/proc/self/fd/1`
/// resolves to the terminal device when output is a terminal and to a pipe or a
/// regular file when it has been redirected. That half matters because a
/// formatter is usually run as `moonjson-toolkit -f a.json > b.json`, and
/// colouring that output would put escape sequences inside the file it was
/// asked to produce. `TERM` is no help there, since it stays set when output is
/// redirected.
///
/// `color_allowed` holds the rule; this function only finds out the one fact
/// the rule needs and then applies it.
pub async fn is_tty() -> Bool {
  let kind = @fs.kind("/proc/self/fd/1", follow_symlink=true) catch {
    _ => @fs.Unknown
  }
  let output_is_terminal = match kind {
    @fs.CharDevice => Some(true)
    // Either the probe failed or this platform does not describe its
    // descriptors this way; nothing is known, so nothing is claimed.
    @fs.Unknown => None
    _ => Some(false)
  }
  color_allowed(
    @env.get_env_var("NO_COLOR"),
    @env.get_env_var("TERM"),
    output_is_terminal,
  )
}

///|
/// Whether colour is on for this run.
///
/// The runner settles this once, before the first byte is printed, from
/// `--no-color` and `is_tty()`. It is a cell rather than a parameter because
/// the text that needs colouring is built in several places, and the answer is
/// the same everywhere in a given run.
///
/// The default is off, which is what keeps `moon test` — whose standard output
/// is not a terminal — from seeing escape sequences in the messages it compares
/// against.
let color_on : @ref.Ref[Bool] = @ref.new(false)

///|
/// Turn colour on or off for the rest of the run.
pub fn set_color_enabled(enabled : Bool) -> Unit {
  color_on.val = enabled
}

///|
/// Wrap `text` in an ANSI escape when colour is on, and return it unchanged
/// when it is not.
///
/// Both halves are the same function with a different code, so the pass-through
/// rule has one home rather than two.
fn paint(text : String, code : String, enabled : Bool) -> String {
  if enabled {
    "\u{1b}[" + code + "m" + text + "\u{1b}[0m"
  } else {
    text
  }
}

///|
/// `text` in red, for the part of a message that says something went wrong.
pub fn red(text : String) -> String {
  paint(text, "31", color_on.val)
}

///|
/// `text` in yellow, for a position that is worth looking at rather than an
/// error in itself.
pub fn yellow(text : String) -> String {
  paint(text, "33", color_on.val)
}
