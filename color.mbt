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
/// Whether standard output is a terminal, as far as the kernel will say.
///
/// `kind` is what the file at `/proc/self/fd/1` is, and `target` is where that
/// link points, or `None` when there was no way to read it.
///
/// The kind is most of the answer. A terminal is a character device, so
/// everything else — a pipe, a regular file, a socket — is not one and cannot
/// become one, and that is the half `moonjson-toolkit -f a.json > b.json` is
/// asked about.
///
/// What the kind cannot say is *which* character device, and the ones output is
/// sent to are not all terminals. `/dev/null` is the one worth naming: running
/// a program for its exit code alone means `tool -f a.json > /dev/null`, and
/// that is not a terminal, however much a character device resembles one. It
/// has to be excluded for consistency as much as for looks — the same command
/// redirected to a file is coloured nothing, and only the destination's name
/// differs.
///
/// The remaining character devices are taken at their word. `/dev/zero` and
/// `/dev/full` are read the same way a terminal is, and a run sent to one of
/// them would be coloured, which is wrong for the same reason `/dev/null` was.
/// They are not where output is normally sent, so they are left out rather than
/// listed; a list would be a device taxonomy this program has no business
/// keeping.
///
/// This is a function of its three arguments rather than of the process, so
/// every case can be stated — including the ones a test suite cannot otherwise
/// reach, since the standard output of the test process is not a terminal and
/// cannot be made into `/dev/null` for the duration of one test.
fn output_is_terminal(
  kind : @fs.FileKind,
  target : String?,
  null_device : String,
) -> Bool? {
  match kind {
    @fs.CharDevice =>
      match target {
        // The one character device that is definitely not a terminal.
        Some(path) => Some(path != null_device)
        // A character device whose link could not be followed: it is a
        // terminal as far as anything here can tell, which is what this
        // function answered before the link was read at all.
        None => Some(true)
      }
    // Either the probe failed or this platform does not describe its
    // descriptors this way; nothing is known, so nothing is claimed.
    @fs.Unknown => None
    _ => Some(false)
  }
}

///|
/// Where `/proc/self/fd/1` leads, spelled the way the kernel spells it.
///
/// The link reads back as a path for everything that has one: the terminal
/// device when output is a terminal, `/dev/null` when the run was sent there,
/// and the name of the file when it was redirected to one. A pipe is the case
/// that has no path — the link says `pipe:[12345]`, which names nothing on the
/// filesystem — and the null answer is what comes back for it. Nothing is lost:
/// a pipe is not a character device, so the kind has already answered for it,
/// and the path is only ever wanted for the character devices.
async fn output_target() -> String? {
  try @fs.realpath("/proc/self/fd/1") catch {
    _ => None
  } noraise {
    path => Some(path)
  }
}

///|
/// Whether colour may be used on standard output in this run.
///
/// On Linux the fact is available rather than guessed at: `/proc/self/fd/1` is
/// a link to whatever standard output is connected to, and its kind and its
/// target between them say which. That half matters because a formatter is
/// usually run as `moonjson-toolkit -f a.json > b.json`, and colouring that
/// output would put escape sequences inside the file it was asked to produce.
/// `TERM` is no help there, since it stays set when output is redirected — and
/// it stays set when output goes to `/dev/null`, which is the other destination
/// that must not be coloured.
///
/// `color_allowed` holds the rule and `output_is_terminal` holds the reading of
/// the two facts; this function is what finds the facts out and hands them over.
pub async fn is_tty() -> Bool {
  let kind = @fs.kind("/proc/self/fd/1", follow_symlink=true) catch {
    _ => @fs.Unknown
  }
  color_allowed(
    @env.get_env_var("NO_COLOR"),
    @env.get_env_var("TERM"),
    output_is_terminal(kind, output_target(), "/dev/null"),
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
