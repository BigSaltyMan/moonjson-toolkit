///|
/// The name the tool answers to in its usage text and its version line.
pub let program_name : String = "moonjson-toolkit"

///|
/// The version reported by `-V` / `--version`.
///
/// MoonBit cannot read `moon.mod` while building — `moon.mod` is strictly
/// parsed, has no build hooks, and the language has no way to include a file at
/// compile time — so the number has to exist here as well as there. What keeps
/// the two from drifting is `cli_wbtest.mbt`, which reads `moon.mod` on every
/// test run and fails when this constant disagrees with it. Bump `moon.mod` and
/// the suite will tell you to bump this too.
pub let version : String = "0.1.0"

///|
/// The line printed by `-V` / `--version`.
pub fn version_line() -> String {
  program_name + " " + version
}

///|
/// Options accepted by the command-line interface.
pub(all) struct CliOptions {
  mut file : String?
  mut indent : Int
  mut compact : Bool
  mut sort_keys : Bool
  mut validate : Bool
  mut help : Bool
  mut version : Bool
  mut ai : Bool
  mut json_out : String?
}

///|
/// The options used when no argument changes them.
pub fn CliOptions::default() -> CliOptions {
  {
    file: None,
    indent: default_indent,
    compact: false,
    sort_keys: false,
    validate: false,
    help: false,
    version: false,
    ai: false,
    json_out: None,
  }
}

///|
/// The text shown for `-h` / `--help`.
pub fn usage() -> String {
  [
    program_name + " - format, validate and analyse JSON documents",
    "",
    "Usage:",
    "  moonjson-toolkit [options]",
    "",
    "Input is read from standard input unless --file is given.",
    "",
    "Options:",
    "  -f, --file <path>      Read JSON from <path> instead of standard input",
    "  -i, --indent <n>       Spaces per nesting level, 0 to 16 (default: 2)",
    "  -c, --compact          Print the document on one line, ignoring --indent",
    "  -S, --sort-keys        Order the keys of every object before printing",
    "  -v, --validate         Only check the input and report the first error",
    "  -h, --help             Show this message and exit",
    "  -V, --version          Show the version and exit",
    "      --ai               Ask DeepSeek for a quality report and suggestions",
    "      --json-out <path>  Write a statistics report as JSON to <path>",
    "",
    "Short options may be combined, so -vh means -v -h. The value of --indent",
    "may be attached, as in -i4, -i=4, --indent=4 or --indent 4.",
    "",
    "Exit codes:",
    "  0  success",
    "  1  the input could not be read, or is not valid JSON",
    "  2  the command line was invalid",
    "  3  the input was valid but the AI review failed",
  ].join("\n")
}

///|
/// Parse a signed decimal integer, rejecting empty strings, stray characters
/// and a lone sign.
fn parse_decimal(value : String) -> Int? {
  let chars = value.to_array()
  if chars.length() == 0 {
    return None
  }
  let mut index = 0
  let mut negative = false
  if chars[0] == '-' {
    negative = true
    index = 1
  } else if chars[0] == '+' {
    index = 1
  }
  if index >= chars.length() {
    return None
  }
  let mut result = 0
  while index < chars.length() {
    let ch = chars[index]
    if ch < '0' || ch > '9' {
      return None
    }
    result = result * 10 + (ch.to_int() - 48)
    index = index + 1
  }
  Some(if negative { -result } else { result })
}

///|
/// Interpret the text given to `-i` / `--indent` as a width in `0..=16`.
fn parse_indent(value : String) -> Result[Int, String] {
  match parse_decimal(value) {
    None => Err("invalid indent value: " + value + " (expected an integer)")
    Some(width) =>
      if width < 0 || width > max_indent {
        Err(
          "indent out of range: " +
          value +
          " (expected 0 to " +
          max_indent.to_string() +
          ")",
        )
      } else {
        Ok(width)
      }
  }
}

///|
/// Resolve the value of an option, taking it from `inline` (the text after
/// `=`) or, failing that, from the next argument.
///
/// Returns the value together with the index of the next unread argument.
fn option_value(
  option : String,
  inline : String?,
  args : Array[String],
  index : Int,
) -> Result[(String, Int), String] {
  match inline {
    Some(value) =>
      if value == "" {
        Err("option " + option + " requires a non-empty value")
      } else {
        Ok((value, index))
      }
    None =>
      if index < args.length() {
        Ok((args[index], index + 1))
      } else {
        Err("option " + option + " requires a value")
      }
  }
}

///|
/// Split the body of a long option into its name and the text after `=`.
fn split_long_option(body : String) -> (String, String?) {
  match body.find("=") {
    Some(position) =>
      (
        body.exact_view(start=0, end=position).to_owned(),
        Some(body.exact_view(start=position + 1).to_owned()),
      )
    None => (body, None)
  }
}

///|
/// The error reported for an argument that is neither an option nor a value.
fn unexpected_argument(arg : String) -> String {
  "unexpected argument: " + arg + " (use --file <path> to name an input file)"
}

///|
/// Apply a value-taking option, reporting the first error it hits.
fn apply_value_option(
  options : CliOptions,
  name : String,
  value : String,
) -> Result[Unit, String] {
  match name {
    "file" => {
      options.file = Some(value)
      Ok(())
    }
    "json-out" => {
      options.json_out = Some(value)
      Ok(())
    }
    _ =>
      match parse_indent(value) {
        Ok(width) => {
          options.indent = width
          Ok(())
        }
        Err(message) => Err(message)
      }
  }
}

///|
/// Parse command-line arguments into `CliOptions`.
///
/// This is a pure function: it touches no file, environment or console state,
/// so every branch is cheap to unit test. The message in `Err` is written for
/// the user and is meant to be printed verbatim before exiting with code 2.
pub fn CliOptions::parse(args : Array[String]) -> Result[CliOptions, String] {
  let options = CliOptions::default()
  let mut index = 0
  let total = args.length()
  while index < total {
    let arg = args[index]
    index = index + 1
    if arg == "--" {
      // `--` ends option parsing; anything left would be a positional
      // argument, which this CLI does not accept.
      if index < total {
        return Err(unexpected_argument(args[index]))
      }
    } else if arg.has_prefix("--") {
      let (name, inline) = split_long_option(arg.exact_view(start=2).to_owned())
      match name {
        "help" => options.help = true
        "version" => options.version = true
        "validate" => options.validate = true
        "compact" => options.compact = true
        "sort-keys" => options.sort_keys = true
        "ai" => options.ai = true
        "file" | "json-out" | "indent" =>
          match option_value("--" + name, inline, args, index) {
            Err(message) => return Err(message)
            Ok((value, next)) =>
              match apply_value_option(options, name, value) {
                Err(message) => return Err(message)
                Ok(_) => index = next
              }
          }
        _ => return Err("unknown option: --" + name)
      }
    } else if arg.has_prefix("-") && arg.length() > 1 {
      let cluster = arg.exact_view(start=1).to_owned()
      let flags = cluster.to_array()
      let mut position = 0
      while position < flags.length() {
        let flag = flags[position]
        position = position + 1
        match flag {
          'h' => options.help = true
          // Lower case is `--validate`, upper case is `--version`; they are
          // one keystroke apart and mean quite different things, so both
          // spellings are worth having a test for.
          'V' => options.version = true
          'v' => options.validate = true
          'c' => options.compact = true
          // Capitalised on purpose: `jq` gives `-S` to its own `--sort-keys`,
          // so the letter a reader is likely to reach for is already the one
          // that does this.
          'S' => options.sort_keys = true
          'f' | 'i' => {
            let option = if flag == 'f' { "-f" } else { "-i" }
            let rest = String::from_array(flags[position:])
            // `-i4` and `-i=4` both attach the value to the flag, and an
            // empty `rest` means the value is the next argument.
            let attached = if rest.has_prefix("=") {
              Some(rest.exact_view(start=1).to_owned())
            } else if rest == "" {
              None
            } else {
              Some(rest)
            }
            match option_value(option, attached, args, index) {
              Err(message) => return Err(message)
              Ok((value, next)) =>
                match
                  apply_value_option(
                    options,
                    if flag == 'f' {
                      "file"
                    } else {
                      "indent"
                    },
                    value,
                  ) {
                  Err(message) => return Err(message)
                  Ok(_) => {
                    index = next
                    // The rest of the cluster was the value, so stop here.
                    position = flags.length()
                  }
                }
            }
          }
          _ => return Err("unknown option: -" + flag.to_string())
        }
      }
    } else {
      return Err(unexpected_argument(arg))
    }
  }
  Ok(options)
}
