///|
/// Parse `text` as JSON, reporting the raw library error.
///
/// This is `parse_with_diagnostic` with no diagnostic built around the failure,
/// reading documents the same way and to the same limits.
pub fn parse(text : String) -> Result[@pjson.Json, @pjson.JsonError] {
  parse_raw(text, None)
}

///|
/// The nesting depth the parser allows when the caller does not ask for a
/// different one.
///
/// This is the value `Nanaloveyuki/parsec/json` uses for `JsonLimits::standard()`,
/// restated because the struct keeps its fields private and exposes no
/// accessors. `parser_wbtest.mbt` measures the limit the library actually
/// applies and fails if the two ever disagree.
pub let standard_max_depth : Int = 128

///|
/// The largest document the parser accepts, in characters.
///
/// `Nanaloveyuki/parsec/json` caps input at 1 MiB, which is small enough that a
/// 10 MB export is refused outright rather than read. The scanner below is what
/// reads a document, so the cap is ours to set: 64 MiB leaves room for the file
/// sizes this tool is meant to handle while still bounding what one run will
/// hold in memory.
pub let standard_max_input_chars : Int = 67_108_864

///|
/// The string length `JsonLimits::standard()` allows, restated for the scanner.
let standard_max_string_chars : Int = 262_144

///|
/// The array length `JsonLimits::standard()` allows, restated for the scanner.
let standard_max_array_items : Int = 65_536

///|
/// The object member count `JsonLimits::standard()` allows, for the scanner.
let standard_max_object_members : Int = 65_536

///|
/// Parse `text`, turning any failure into a diagnostic that carries the line,
/// the column and a human-readable reason.
///
/// `max_depth` caps how many collections may nest, counting one for each array
/// or object entered. `Some(limit)` refuses anything deeper, reporting the
/// position where the limit was passed; `None` leaves the parser's own default
/// in place. Either way the other four size limits keep their standard values,
/// so this changes only how deep a document may go.
pub fn parse_with_diagnostic(
  text : String,
  max_depth : Int?,
) -> Result[@pjson.Json, JsonDiagnostic] {
  match parse_raw(text, max_depth) {
    Ok(json) => Ok(json)
    Err(error) => Err(JsonDiagnostic::from_error(text, error))
  }
}

// ---------------------------------------------------------------------------
// The fast path
//
// `Nanaloveyuki/parsec/json` is a backtracking combinator parser, and it reads a
// document at about a megabyte a second: a 10 MB file takes it ten seconds. The
// scanner below follows the same grammar directly, over the document's own code
// units, and reads the same file in a fraction of the time.
//
// It is not a second implementation of JSON in the sense that matters: it never
// says what is wrong with a document. Everything it will not accept is handed to
// the library parser, which has been describing bad documents all along, so the
// two cannot disagree about a diagnostic. What the scanner must therefore get
// exactly right is *which documents are good*: anything it accepts, the library
// parser would have accepted too. `parser_differential_wbtest.mbt` measures that
// over a corpus of documents and mutations of them.
// ---------------------------------------------------------------------------

///|
/// Structural characters as UTF-16 code units, which is what `code_units` hands
/// out. The scanner walks those units directly, so they are named by number,
/// with the character in a comment.
const CODE_TAB : UInt16 = 9

///|
const CODE_LF : UInt16 = 10

///|
const CODE_CR : UInt16 = 13

///|
const CODE_SPACE : UInt16 = 32

///|
const CODE_QUOTE : UInt16 = 34 // '"'

///|
const CODE_PLUS : UInt16 = 43 // '+'

///|
const CODE_COMMA : UInt16 = 44 // ','

///|
const CODE_MINUS : UInt16 = 45 // '-'

///|
const CODE_DOT : UInt16 = 46 // '.'

///|
const CODE_SLASH : UInt16 = 47 // '/'

///|
const CODE_ZERO : UInt16 = 48 // '0'

///|
const CODE_ONE : UInt16 = 49 // '1'

///|
const CODE_NINE : UInt16 = 57 // '9'

///|
const CODE_COLON : UInt16 = 58 // ':'

///|
const CODE_UPPER_E : UInt16 = 69 // 'E'

///|
const CODE_LBRACKET : UInt16 = 91 // '['

///|
const CODE_BACKSLASH : UInt16 = 92 // '\\'

///|
const CODE_RBRACKET : UInt16 = 93 // ']'

///|
const CODE_LOWER_B : UInt16 = 98 // 'b'

///|
const CODE_LOWER_E : UInt16 = 101 // 'e'

///|
const CODE_LOWER_F : UInt16 = 102 // 'f'

///|
const CODE_LOWER_N : UInt16 = 110 // 'n'

///|
const CODE_LOWER_R : UInt16 = 114 // 'r'

///|
const CODE_LOWER_T : UInt16 = 116 // 't'

///|
const CODE_LOWER_U : UInt16 = 117 // 'u'

///|
const CODE_LBRACE : UInt16 = 123 // '{'

///|
const CODE_RBRACE : UInt16 = 125 // '}'

///|
/// The size limits the scanner refuses a document for, which the library
/// restates in `JsonLimits`, privately. A refusal here only sends the document
/// to the library, which is where the limit is described, so these have to
/// agree with `ScanLimits::of` rather than with any message.
priv struct ScanLimits {
  depth : Int
  string_chars : Int
  array_items : Int
  object_members : Int
}

///|
fn ScanLimits::of(max_depth : Int) -> ScanLimits {
  {
    depth: max_depth,
    string_chars: standard_max_string_chars,
    array_items: standard_max_array_items,
    object_members: standard_max_object_members,
  }
}

///|
/// A scanner over one document's code units.
///
/// `pos` always points at the next unit to read. `view` is the document those
/// units came from, kept so that a stretch of text can be sliced back out of it
/// instead of being rebuilt a character at a time.
priv struct Scanner {
  view : StringView
  units : ArrayView[UInt16]
  limits : ScanLimits
  mut pos : Int
}

///|
fn Scanner::new(text : String, limits : ScanLimits) -> Scanner {
  { view: text, units: text.code_units(), limits, pos: 0, }
}

///|
fn Scanner::at_end(self : Scanner) -> Bool {
  self.pos >= self.units.length()
}

///|
fn Scanner::skip_whitespace(self : Scanner) -> Unit {
  while self.pos < self.units.length() {
    let code = self.units[self.pos]
    if code == CODE_SPACE ||
      code == CODE_LF ||
      code == CODE_TAB ||
      code == CODE_CR {
      self.pos = self.pos + 1
    } else {
      break
    }
  }
}

///|
/// Consume `code` if it is next, and say whether it was.
fn Scanner::take(self : Scanner, code : UInt16) -> Bool {
  if self.pos < self.units.length() && self.units[self.pos] == code {
    self.pos = self.pos + 1
    true
  } else {
    false
  }
}

///|
/// Consume `word` if it is next, letter by letter.
fn Scanner::take_word(self : Scanner, word : String) -> Bool {
  let letters = word.code_units()
  if self.pos + letters.length() > self.units.length() {
    return false
  }
  for index in 0..<letters.length() {
    if self.units[self.pos + index] != letters[index] {
      return false
    }
  }
  self.pos = self.pos + letters.length()
  true
}

///|
/// The text between two positions, as a string of its own.
fn Scanner::slice(self : Scanner, start : Int, stop : Int) -> String {
  self.view.exact_view(start~, end=stop).to_owned()
}

///|
/// Read one value, or answer `None` for anything the library should look at.
///
/// `depth` is the number of collections already entered, so a container is only
/// read when there is room for it: scalars are always allowed, which is what
/// makes a limit of zero still accept `5`.
fn Scanner::value(self : Scanner, depth : Int) -> @pjson.Json? {
  self.skip_whitespace()
  if self.at_end() {
    return None
  }
  let code = self.units[self.pos]
  if code == CODE_LBRACE {
    self.object_value(depth)
  } else if code == CODE_LBRACKET {
    self.array_value(depth)
  } else if code == CODE_QUOTE {
    match self.text_value() {
      Some(text) => Some(@pjson.Text(value=text))
      None => None
    }
  } else if code == CODE_LOWER_T {
    if self.take_word("true") {
      Some(@pjson.Bool(value=true))
    } else {
      None
    }
  } else if code == CODE_LOWER_F {
    if self.take_word("false") {
      Some(@pjson.Bool(value=false))
    } else {
      None
    }
  } else if code == CODE_LOWER_N {
    if self.take_word("null") {
      Some(@pjson.Null)
    } else {
      None
    }
  } else if code == CODE_MINUS || (code >= CODE_ZERO && code <= CODE_NINE) {
    self.number_value()
  } else {
    None
  }
}

///|
/// Read one or more digits, saying whether there were any.
fn Scanner::digits(self : Scanner) -> Bool {
  let start = self.pos
  while self.pos < self.units.length() {
    let code = self.units[self.pos]
    if code >= CODE_ZERO && code <= CODE_NINE {
      self.pos = self.pos + 1
    } else {
      break
    }
  }
  self.pos > start
}

///|
/// Read a number, keeping its text exactly as it was written.
///
/// The shape is JSON's own, not the widest thing that could be read as one: no
/// leading zeroes, something after a `.`, something after an `e`. A number that
/// is only nearly right is left to the library to complain about.
fn Scanner::number_value(self : Scanner) -> @pjson.Json? {
  let start = self.pos
  ignore(self.take(CODE_MINUS))
  if self.at_end() {
    return None
  }
  let first = self.units[self.pos]
  if first == CODE_ZERO {
    self.pos = self.pos + 1
  } else if first >= CODE_ONE && first <= CODE_NINE {
    self.pos = self.pos + 1
    ignore(self.digits())
  } else {
    return None
  }
  if self.take(CODE_DOT) && !self.digits() {
    return None
  }
  if !self.at_end() &&
    (
      self.units[self.pos] == CODE_LOWER_E ||
      self.units[self.pos] == CODE_UPPER_E
    ) {
    self.pos = self.pos + 1
    if !self.at_end() &&
      (self.units[self.pos] == CODE_PLUS || self.units[self.pos] == CODE_MINUS) {
      self.pos = self.pos + 1
    }
    if !self.digits() {
      return None
    }
  }
  Some(@pjson.Number(raw=self.slice(start, self.pos)))
}

///|
/// Read a string value, escapes and all.
///
/// A string with no escapes in it is sliced straight out of the document. One
/// with escapes is rebuilt, because the escapes are not what the value is.
fn Scanner::text_value(self : Scanner) -> String? {
  self.pos = self.pos + 1
  let start = self.pos
  let units = self.units
  let length = units.length()
  let mut characters = 0
  let mut escaped = false
  while self.pos < length {
    let code = units[self.pos]
    if code == CODE_QUOTE {
      let stop = self.pos
      self.pos = self.pos + 1
      if escaped {
        return self.unescaped(start, stop)
      }
      return Some(self.slice(start, stop))
    } else if code == CODE_BACKSLASH {
      escaped = true
      // The escape and its payload are two units, except for `\uXXXX`, which
      // is six. Validity is settled by `unescaped`, which reads the same text
      // again; here the only job is to find the closing quote.
      if self.pos + 1 >= length || units[self.pos + 1] == CODE_LOWER_U {
        self.pos = self.pos + 6
        characters = characters + 1
      } else {
        self.pos = self.pos + 2
        characters = characters + 1
      }
    } else {
      // A control character has to be written as an escape, and the library holds
      // documents to that.
      if code < 0x20 {
        return None
      }
      // A low surrogate is half of one character, not a character.
      if code < 0xDC00 || code > 0xDFFF {
        characters = characters + 1
      }
      self.pos = self.pos + 1
    }
    if characters > self.limits.string_chars {
      return None
    }
  }
  None
}

///|
/// Rebuild the string between `start` and `stop`, where the escapes are.
///
/// Answers `None` for an escape that is not one of JSON's, or for a `\u` escape
/// that is not a character on its own and not the first half of a pair, so that
/// the library gets to name the problem.
fn Scanner::unescaped(self : Scanner, start : Int, stop : Int) -> String? {
  let buf = StringBuilder()
  let units = self.units
  let mut index = start
  while index < stop {
    let code = units[index]
    if code != CODE_BACKSLASH {
      buf.write_char(Int::unsafe_to_char(code.to_int()))
      index = index + 1
      continue
    }
    if index + 1 >= stop {
      return None
    }
    let escaped = units[index + 1]
    if escaped == CODE_LOWER_U {
      let mut value = match self.hex4(index + 2, stop) {
        Some(value) => value
        None => return None
      }
      index = index + 6
      if value >= 0xD800 && value <= 0xDBFF {
        // A high surrogate is only a character with its low half behind it.
        if index + 5 >= stop ||
          units[index] != CODE_BACKSLASH ||
          units[index + 1] != CODE_LOWER_U {
          return None
        }
        let low = match self.hex4(index + 2, stop) {
          Some(low) => low
          None => return None
        }
        if low < 0xDC00 || low > 0xDFFF {
          return None
        }
        value = 0x10000 + (value - 0xD800) * 1024 + (low - 0xDC00)
        index = index + 6
      } else if value >= 0xDC00 && value <= 0xDFFF {
        // A low surrogate on its own is half of a character, which is not one.
        return None
      }
      buf.write_char(Int::unsafe_to_char(value))
      continue
    }
    let character = if escaped == CODE_QUOTE {
      '"'
    } else if escaped == CODE_BACKSLASH {
      '\\'
    } else if escaped == CODE_SLASH {
      '/'
    } else if escaped == CODE_LOWER_B {
      '\u{8}'
    } else if escaped == CODE_LOWER_F {
      '\u{c}'
    } else if escaped == CODE_LOWER_N {
      '\n'
    } else if escaped == CODE_LOWER_R {
      '\r'
    } else if escaped == CODE_LOWER_T {
      '\t'
    } else {
      return None
    }
    buf.write_char(character)
    index = index + 2
  }
  Some(buf.to_string())
}

///|
/// Four hex digits at `at`, or `None` if they are not four hex digits.
fn Scanner::hex4(self : Scanner, at : Int, stop : Int) -> Int? {
  if at + 4 > stop {
    return None
  }
  let mut value = 0
  for offset in 0..<4 {
    let digit = match hex_digit(self.units[at + offset]) {
      Some(digit) => digit
      None => return None
    }
    value = value * 16 + digit
  }
  Some(value)
}

///|
fn hex_digit(code : UInt16) -> Int? {
  if code >= CODE_ZERO && code <= CODE_NINE {
    Some(code.to_int() - 48)
  } else if code >= 97 && code <= 102 {
    Some(code.to_int() - 87)
  } else if code >= 65 && code <= 70 {
    Some(code.to_int() - 55)
  } else {
    None
  }
}

///|
/// Read an array, up to the item limit.
fn Scanner::array_value(self : Scanner, depth : Int) -> @pjson.Json? {
  if depth >= self.limits.depth {
    return None
  }
  self.pos = self.pos + 1
  let items : Array[@pjson.Json] = []
  self.skip_whitespace()
  if self.take(CODE_RBRACKET) {
    return Some(@pjson.Array(items~))
  }
  while true {
    let item = match self.value(depth + 1) {
      Some(item) => item
      None => return None
    }
    items.push(item)
    if items.length() > self.limits.array_items {
      return None
    }
    self.skip_whitespace()
    if self.take(CODE_COMMA) {
      continue
    }
    if self.take(CODE_RBRACKET) {
      return Some(@pjson.Array(items~))
    }
    return None
  } nobreak {
    abort("unreachable: the array loop leaves only by returning")
  }
}

///|
/// Read an object, up to the member limit.
///
/// A repeated key is refused here, not because the scanner has anything to say
/// about it but because the library refuses it: accepting one would be accepting
/// a document the tool has always turned down.
fn Scanner::object_value(self : Scanner, depth : Int) -> @pjson.Json? {
  if depth >= self.limits.depth {
    return None
  }
  self.pos = self.pos + 1
  let members : Array[(String, @pjson.Json)] = []
  // A hash map per object costs more than a walk down a handful of keys, so the
  // map is only built once an object is big enough to need it.
  let seen : Map[String, Unit] = Map([])
  let mut indexed = false
  self.skip_whitespace()
  if self.take(CODE_RBRACE) {
    return Some(@pjson.Object(members~))
  }
  while true {
    self.skip_whitespace()
    if self.at_end() || self.units[self.pos] != CODE_QUOTE {
      return None
    }
    let key = match self.text_value() {
      Some(key) => key
      None => return None
    }
    if indexed {
      if seen.contains(key) {
        return None
      }
      seen.set(key, ())
    } else {
      for entry in members {
        let (name, _) = entry
        if name == key {
          return None
        }
      }
      if members.length() >= 8 {
        for entry in members {
          let (name, _) = entry
          seen.set(name, ())
        }
        indexed = true
      }
    }
    self.skip_whitespace()
    if !self.take(CODE_COLON) {
      return None
    }
    let value = match self.value(depth + 1) {
      Some(value) => value
      None => return None
    }
    members.push((key, value))
    if members.length() > self.limits.object_members {
      return None
    }
    self.skip_whitespace()
    if self.take(CODE_COMMA) {
      continue
    }
    if self.take(CODE_RBRACE) {
      return Some(@pjson.Object(members~))
    }
    return None
  } nobreak {
    abort("unreachable: the object loop leaves only by returning")
  }
}

///|
/// Scan `text` as JSON within `max_depth`, or answer `None`.
///
/// `None` means "not the scanner's to read": either the document is bad, or it
/// is good but past a limit the scanner does not describe. Both go to the
/// library parser.
fn scan(text : String, max_depth : Int) -> @pjson.Json? {
  let scanner = Scanner::new(text, ScanLimits::of(max_depth))
  match scanner.value(0) {
    None => None
    Some(json) => {
      scanner.skip_whitespace()
      if scanner.at_end() {
        Some(json)
      } else {
        None
      }
    }
  }
}

///|
/// The parser call itself, with no diagnostic built around it.
///
/// Split out because JSON Lines parses a record at a time and needs the raw
/// error to place it in the file as a whole rather than in the record.
///
/// The scanner in `scan` reads what it can. Anything it will not accept — a
/// syntax error, a limit passed, a repeated key — goes to the library parser,
/// which is the authority on what a bad document means and where it went wrong.
/// So the fast path can only ever make a good document quicker; it cannot
/// change what is said about a bad one.
fn parse_raw(
  text : String,
  max_depth : Int?,
) -> Result[@pjson.Json, @pjson.JsonError] {
  let limit = match max_depth {
    None => standard_max_depth
    Some(limit) => limit
  }
  // A document over the cap is refused by the library, which is where the
  // message for it is written. Asking first saves scanning a document that is
  // only going to be turned away.
  if over_input_limit(text) {
    return @pjson.parse_with_limits(text, depth_limits(limit))
  }
  match scan(text, limit) {
    Some(json) => Ok(json)
    None => @pjson.parse_with_limits(text, depth_limits(limit))
  }
}

///|
/// Whether `text` is too long to parse, counted in characters as the library
/// counts them.
///
/// The quick test is in code units, which are never fewer than characters, so a
/// document that passes it is under the cap without counting anything; only a
/// document that might be over is counted properly.
fn over_input_limit(text : String) -> Bool {
  if text.length() <= standard_max_input_chars {
    false
  } else {
    text.char_length() > standard_max_input_chars
  }
}

///|
/// The standard limits, with `max_depth` replaced by `limit`.
///
/// Four of the five fields are the sizes `JsonLimits::standard()` picks, spelled
/// out again because only the depth is meant to change and the struct offers no
/// way to read the others back. The input cap is the one field that is not the
/// library's: see `standard_max_input_chars`.
fn depth_limits(limit : Int) -> @pjson.JsonLimits {
  @pjson.JsonLimits::new(
    max_input_chars=standard_max_input_chars,
    max_depth=limit,
    max_string_chars=standard_max_string_chars,
    max_array_items=standard_max_array_items,
    max_object_members=standard_max_object_members,
  )
}

///|
/// Render a caught error as a concise message fit for one line of output.
///
/// Operating-system failures are reduced to a plain-language reason. The debug
/// form of these errors carries internal call context that only clutters a CLI
/// message, so the errno is translated through the public predicates instead.
fn describe_io_error(error : Error) -> String {
  match error {
    @os_error.OSError(errno, ..) as failure =>
      if failure.is_ENOENT() {
        "no such file or directory"
      } else if failure.is_EACCES() {
        "permission denied"
      } else if failure.is_ENOTDIR() {
        "not a directory"
      } else {
        "operating system error " + errno.to_string()
      }
    _ => @debug.to_string(error)
  }
}

///|
/// Read `path` as UTF-8 text.
///
/// The failure is reported as a message rather than an error value so that the
/// caller can print it and exit with code 1 without unwrapping anything.
pub async fn read_file(path : String) -> Result[String, String] {
  Ok(@fs.read_file(path).text()) catch {
    error => Err(describe_io_error(error))
  }
}

///|
/// Read all of standard input as UTF-8 text.
pub async fn read_stdin() -> Result[String, String] {
  Ok(@stdio.stdin.read_all().text()) catch {
    error => Err(describe_io_error(error))
  }
}
