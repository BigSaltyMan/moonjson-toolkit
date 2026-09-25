///|
/// The regular expressions a JSON Schema `pattern` is matched with.
///
/// A schema is a document someone else wrote, and `pattern` has to mean what it
/// means everywhere else: an expression looked for anywhere in the string,
/// anchored only where it anchors itself. Full ECMA-262 expressions are a
/// language of their own and this is not one of them. What is here is the part
/// schemas are written with — literals, `.`, character classes, `^` and `$`,
/// alternation, grouping and the repetitions — and a pattern reaching for
/// anything else is reported as a schema this tool cannot read rather than
/// matched as something it is not.
///
/// The matcher keeps the set of positions a subpattern can end at rather than
/// backtracking into one guess at a time. That costs a list per position and a
/// worst case that grows with the product of the text and the pattern; what it
/// buys is that the worst case stays there — no pattern can ask for exponential
/// time, so a schema can be slow but it cannot hang, and `(a*)*b` costs what
/// `a*b` does instead of becoming the stack-eating backtrack it is in an engine
/// that guesses.
///
/// Positions are counted in characters rather than in bytes, so a repetition,
/// an offset and the `^` anchor are counted in the units the rest of the tool
/// counts them in.

///|
/// A pattern that has been read: the branches of its top-level alternation, each
/// one a sequence of pieces to be matched one after the other.
priv struct Pattern {
  branches : Array[Array[Piece]]
}

///|
/// One element of a sequence.
priv enum Piece {
  Literal(Char) // one character, written as itself or escaped
  AnyChar // `.`: any character but a line feed
  CharSet(Bool, Array[ClassItem]) // `[...]`: the flag says the set is negated
  AnchorStart // `^`
  AnchorEnd // `$`
  Group(Pattern) // `(...)`
  Repeat(Piece, Int, Int) // the piece, the least and the most times, -1 if endless
}

///|
/// One member of a character class: a character, a range of them, or one of the
/// sets `\d`, `\w` and `\s` spell — whose upper case forms are sets of their own
/// rather than a negation of these, so that a class negated around one of them
/// means what it says.
priv enum ClassItem {
  One(Char)
  Range(Char, Char)
  Named(Char)
}

///|
/// Where a pattern is being read from: its characters, and how far along.
///
/// The reading is one pass from left to right, so the position is the whole of
/// the state, and a mistake leaves it wherever it was found: the characters
/// before it are the ones that were read, and the ones after it are what a
/// report would point at.
priv struct Cursor {
  text : Array[Char]
  mut pos : Int
}

///|
fn Cursor::done(self : Cursor) -> Bool {
  self.pos >= self.text.length()
}

///|
/// The character the cursor is on.
///
/// Asking when there is none is a mistake this file never makes: every caller
/// asks `done` first, and every reader stops where the pattern stops.
fn Cursor::peek(self : Cursor) -> Char {
  self.text[self.pos]
}

///|
fn Cursor::advance(self : Cursor) -> Unit {
  self.pos = self.pos + 1
}

///|
/// Match `pattern` against `text`, answering whether it matches anywhere in it.
///
/// The pattern is not anchored: `^` and `$` say where a match may start and end,
/// and without them a match at any position counts, which is what a schema asks
/// for and what a regular expression means everywhere else.
///
/// The `Err` is a pattern this tool cannot read, with a sentence saying what it
/// reached for. That is a fact about the pattern rather than about the text,
/// which is why it is answered even when there was never a match to find.
pub fn pattern_matches(pattern : String, text : String) -> Result[Bool, String] {
  let parsed = match read_pattern(pattern) {
    Ok(parsed) => parsed
    Err(message) => return Err(message)
  }
  let chars = text.to_array()
  let mut start = 0
  while start <= chars.length() {
    if end_positions(parsed, chars, start).length() > 0 {
      return Ok(true)
    }
    start = start + 1
  }
  Ok(false)
}

///|
/// Read a pattern from its text, from the beginning to the end of it.
fn read_pattern(text : String) -> Result[Pattern, String] {
  let cursor : Cursor = { text: text.to_array(), pos: 0, }
  let pattern = match read_alternation(cursor) {
    Ok(pattern) => pattern
    Err(message) => return Err(message)
  }
  if !cursor.done() {
    // The one character that stops a sequence without ending the pattern is
    // `)`, and it only ends one where a `(` opened it.
    return Err("\")\" has no matching \"(\"")
  }
  Ok(pattern)
}

///|
/// Read the branches of an alternation, up to the end of the pattern or to the
/// `)` that closes it.
///
/// A branch with nothing in it matches the empty string, which is what `a|` and
/// `(|a)` say, so there is nothing to refuse here.
fn read_alternation(cursor : Cursor) -> Result[Pattern, String] {
  let branches = []
  while true {
    match read_sequence(cursor) {
      Ok(branch) => branches.push(branch)
      Err(message) => return Err(message)
    }
    if !cursor.done() && cursor.peek() == '|' {
      cursor.advance()
    } else {
      break
    }
  }
  Ok({ branches, })
}

///|
/// Read the pieces up to the end of a branch: the end of the pattern, a `)`, or
/// the `|` that starts the next branch.
fn read_sequence(cursor : Cursor) -> Result[Array[Piece], String] {
  let pieces = []
  while !cursor.done() {
    let ch = cursor.peek()
    if ch == '|' || ch == ')' {
      break
    }
    match read_piece(cursor) {
      Ok(piece) => pieces.push(piece)
      Err(message) => return Err(message)
    }
  }
  Ok(pieces)
}

///|
/// Read one piece: an atom, and the repetition that follows it if there is one.
///
/// A `?` after a repetition asks for the shortest match rather than the longest.
/// Nothing here cares which of the two is found — the question asked is whether
/// a match is there at all, and greediness is about which of several matches is
/// reported — so it is read and then dropped.
fn read_piece(cursor : Cursor) -> Result[Piece, String] {
  let atom = match read_atom(cursor) {
    Ok(atom) => atom
    Err(message) => return Err(message)
  }
  if cursor.done() {
    return Ok(atom)
  }
  let piece = match cursor.peek() {
    '*' => {
      cursor.advance()
      Repeat(atom, 0, -1)
    }
    '+' => {
      cursor.advance()
      Repeat(atom, 1, -1)
    }
    '?' => {
      cursor.advance()
      Repeat(atom, 0, 1)
    }
    '{' =>
      match read_braces(cursor, atom) {
        Ok(piece) => piece
        Err(message) => return Err(message)
      }
    _ => atom
  }
  if !cursor.done() && cursor.peek() == '?' {
    cursor.advance()
  }
  Ok(piece)
}

///|
/// Read the braced form of a repetition: `{n}`, `{n,}` or `{n,m}`.
///
/// A `{` that opens none of those is refused rather than read as the character
/// it is. Annex B of the JavaScript standard reads `a{` as those two characters,
/// and a schema writer who meant a literal brace can write `\{`: the other
/// reading would mean a pattern that looks like a repetition and quietly is not
/// one.
fn read_braces(cursor : Cursor, atom : Piece) -> Result[Piece, String] {
  cursor.advance()
  let least = match read_number(cursor) {
    Some(number) => number
    // Written out rather than read as `0`: a `{` with no count in it is not a
    // repetition of nothing, and the pattern under it is not matched as one.
    None => return Err("\"{\" must open a repetition like {2}, {2,} or {2,5}")
  }
  if cursor.done() {
    return Err("\"{\" is never closed")
  }
  match cursor.peek() {
    '}' => {
      cursor.advance()
      Ok(Repeat(atom, least, least))
    }
    ',' => {
      cursor.advance()
      let most = read_number(cursor) // none at all means no end
      if cursor.done() || cursor.peek() != '}' {
        return Err("\"{\" is never closed")
      }
      cursor.advance()
      match most {
        Some(most) =>
          if most < least {
            return Err(
              "a repetition cannot start at " +
              least.to_string() +
              " and end at " +
              most.to_string(),
            )
          } else {
            Ok(Repeat(atom, least, most))
          }
        None => Ok(Repeat(atom, least, -1))
      }
    }
    _ => Err("\"{\" must open a repetition like {2}, {2,} or {2,5}")
  }
}

///|
/// Read the digits of a repetition count, if there are any.
fn read_number(cursor : Cursor) -> Int? {
  let digits = StringBuilder()
  while !cursor.done() && cursor.peek().is_ascii_digit() {
    digits.write_char(cursor.peek())
    cursor.advance()
  }
  let text = digits.to_string()
  if text == "" {
    return None
  }
  // A count of more digits than an Int holds is read as a count no text can
  // satisfy, which is what it is: `{99999999999}` asks for more repetitions
  // than there are characters in any document this tool reads.
  if text.length() > 9 {
    return Some(1_000_000_000)
  }
  Some(
    try @string.parse_int(text) catch {
      _ => 1_000_000_000
    } noraise {
      number => number
    },
  )
}

///|
/// Read one atom: the smallest thing a repetition can be put after.
fn read_atom(cursor : Cursor) -> Result[Piece, String] {
  let ch = cursor.peek()
  match ch {
    '(' => {
      cursor.advance()
      let inner = match read_alternation(cursor) {
        Ok(inner) => inner
        Err(message) => return Err(message)
      }
      if cursor.done() || cursor.peek() != ')' {
        return Err("\"(\" is never closed")
      }
      cursor.advance()
      Ok(Group(inner))
    }
    '[' => read_class(cursor)
    '.' => {
      cursor.advance()
      Ok(AnyChar)
    }
    '^' => {
      cursor.advance()
      Ok(AnchorStart)
    }
    '$' => {
      cursor.advance()
      Ok(AnchorEnd)
    }
    '\\' =>
      // Qualified because the package holds two constructors called `Named`:
      // this is the one for a member of a class, not the one for a shape.
      match read_escape(cursor) {
        Ok(ClassItem::Named(letter)) =>
          Ok(CharSet(false, [ClassItem::Named(letter)]))
        Ok(ClassItem::One(escaped)) => Ok(Literal(escaped))
        // Unreachable: `read_escape` answers a range for no escape.
        Ok(ClassItem::Range(_, _)) => Ok(Literal(ch))
        Err(message) => Err(message)
      }
    '*' | '+' | '?' => Err("\"" + ch.to_string() + "\" has nothing to repeat")
    _ => {
      cursor.advance()
      Ok(Literal(ch))
    }
  }
}

///|
/// Read a character class, from its `[` to the `]` that closes it.
///
/// A class with nothing in it matches nothing at all, which is what `[]` says
/// and is not a mistake: `a[]b` is a pattern nothing satisfies, and refusing it
/// as an unterminated class would be reading it as something else. A `-` is a
/// range only between two characters, so the one in `[a-]` is the character it
/// looks like.
fn read_class(cursor : Cursor) -> Result[Piece, String] {
  cursor.advance()
  let negated = if !cursor.done() && cursor.peek() == '^' {
    cursor.advance()
    true
  } else {
    false
  }
  let items = []
  while !cursor.done() && cursor.peek() != ']' {
    let first = match read_class_item(cursor) {
      Ok(item) => item
      Err(message) => return Err(message)
    }
    match first {
      ClassItem::Named(letter) => items.push(ClassItem::Named(letter))
      // Unreachable: `read_class_item` answers a range for no item.
      Range(_, _) => ()
      One(from) =>
        if !cursor.done() &&
          cursor.peek() == '-' &&
          cursor.pos + 1 < cursor.text.length() &&
          cursor.text[cursor.pos + 1] != ']' {
          cursor.advance()
          let second = match read_class_item(cursor) {
            Ok(item) => item
            Err(message) => return Err(message)
          }
          match second {
            One(to) => items.push(Range(from, to))
            Named(letter) =>
              return Err(
                "\"-\" is a range between two characters, and \"" +
                letter.to_string() +
                "\" is a set of them",
              )
            // Unreachable: `read_class_item` answers a range for no item.
            Range(_, _) => items.push(One(from))
          }
        } else {
          items.push(One(from))
        }
    }
  }
  if cursor.done() {
    return Err("\"[\" is never closed")
  }
  cursor.advance()
  Ok(CharSet(negated, items))
}

///|
/// Read one member of a character class.
fn read_class_item(cursor : Cursor) -> Result[ClassItem, String] {
  if cursor.peek() == '\\' {
    read_escape(cursor)
  } else {
    let ch = cursor.peek()
    cursor.advance()
    Ok(One(ch))
  }
}

///|
/// Read an escape: one of the sets the schema dialect knows, a character it
/// writes with a letter, a character code, or any other character taken as
/// itself.
///
/// A backslash before a letter is always meant as something — `\d` is the digits
/// and `\n` is a line feed — so `\q`, which is neither a set nor a character
/// this tool writes with a letter, is refused rather than read as `q`. Before
/// anything else it is that character, which is how `.`, `[` and `\` are written
/// as themselves.
fn read_escape(cursor : Cursor) -> Result[ClassItem, String] {
  cursor.advance()
  if cursor.done() {
    return Err("\"\\\" is the last character of the pattern")
  }
  let ch = cursor.peek()
  cursor.advance()
  match ch {
    'd' | 'D' | 'w' | 'W' | 's' | 'S' => Ok(ClassItem::Named(ch))
    'n' => Ok(One('\n'))
    'r' => Ok(One('\r'))
    't' => Ok(One('\t'))
    'f' => Ok(One('\u{0C}'))
    'v' => Ok(One('\u{0B}'))
    '0' => Ok(One('\u{0}'))
    'u' => read_code_point(cursor)
    _ =>
      if ch.is_ascii_alphabetic() || ch.is_ascii_digit() {
        Err("\"\\" + ch.to_string() + "\" is not an escape this tool reads")
      } else {
        Ok(One(ch))
      }
  }
}

///|
/// Read the four hexadecimal digits of a `\uXXXX` escape.
///
/// One escape is one character, so an escape pair standing for a character
/// outside the basic plane — `\uD83D\uDE00` for an emoji — is two characters
/// here, and a pattern written that way will not match the character it names.
fn read_code_point(cursor : Cursor) -> Result[ClassItem, String] {
  let digits = StringBuilder()
  let mut read = 0
  while read < 4 {
    if cursor.done() || !cursor.peek().is_ascii_hexdigit() {
      return Err("\"\\u\" must be followed by four hexadecimal digits")
    }
    digits.write_char(cursor.peek())
    cursor.advance()
    read = read + 1
  }
  let value = try @string.parse_int(digits.to_string(), base=16) catch {
    _ => 0
  } noraise {
    number => number
  }
  match value.to_char() {
    Some(ch) => Ok(One(ch))
    // A value in the surrogate range is half of a character rather than one:
    // `\uD83D` is the first half of an emoji and means nothing on its own.
    None => Err("\"\\u" + digits.to_string() + "\" does not name a character")
  }
}

///|
/// Every position a match of `pattern` starting at `from` can end at.
///
/// All of them rather than the one a backtracking engine would settle on: an
/// alternation puts the caller in two places at once and a repetition puts it in
/// as many as it can reach, and the caller is what decides which of them is a
/// match. The positions are kept apart rather than in a multiset, so a pattern
/// that can reach one place several ways costs no more than one that reaches it
/// once.
fn end_positions(
  pattern : Pattern,
  text : Array[Char],
  from : Int,
) -> Array[Int] {
  let ends = []
  for branch in pattern.branches {
    for end in sequence_ends(branch, text, from) {
      add_position(ends, end)
    }
  }
  ends
}

///|
/// Every position the pieces can end at, read one after the other, each starting
/// where the one before it stopped.
fn sequence_ends(
  pieces : Array[Piece],
  text : Array[Char],
  from : Int,
) -> Array[Int] {
  let mut current = [from]
  for piece in pieces {
    let next = []
    for position in current {
      for end in piece_ends(piece, text, position) {
        add_position(next, end)
      }
    }
    current = next
    if current.length() == 0 {
      break
    }
  }
  current
}

///|
/// Every position one piece can end at, starting at `position`.
fn piece_ends(piece : Piece, text : Array[Char], position : Int) -> Array[Int] {
  let length = text.length()
  match piece {
    Literal(ch) =>
      if position < length && text[position] == ch {
        [position + 1]
      } else {
        []
      }
    AnyChar =>
      if position < length && text[position] != '\n' {
        [position + 1]
      } else {
        []
      }
    CharSet(negated, items) =>
      if position < length && class_matches(items, negated, text[position]) {
        [position + 1]
      } else {
        []
      }
    AnchorStart => if position == 0 { [position] } else { [] }
    AnchorEnd => if position == length { [position] } else { [] }
    Group(inner) => end_positions(inner, text, position)
    Repeat(inner, least, most) =>
      repeat_ends(inner, text, position, least, most)
  }
}

///|
/// Every position a repetition of `piece` can end at: the places reached by
/// repeating it between `least` and `most` times, `most` being -1 for a
/// repetition with no end.
///
/// The walk stops when the piece has nowhere left to go, which is what keeps a
/// repetition of something that consumes nothing — `(a?)*` — from going round
/// for ever: the positions it reaches only repeat the ones it has already been
/// at, and the number of steps is capped by what the pattern asked for plus what
/// the text can hold.
fn repeat_ends(
  piece : Piece,
  text : Array[Char],
  position : Int,
  least : Int,
  most : Int,
) -> Array[Int] {
  let ends = []
  // No repetition at all is one of the ways of repeating something between
  // `least` and `most` times whenever `least` is zero, and it is the one way of
  // doing it that reaches no `next` below: the loop only ever looks at what a
  // repetition reaches, and `a*` matching the empty string is not reached by
  // repeating anything.
  if least == 0 {
    add_position(ends, position)
  }
  let steps_limit = if most < 0 { least + text.length() + 1 } else { most }
  let mut frontier = [position]
  let mut steps = 0
  while frontier.length() > 0 && steps < steps_limit {
    let next = []
    for from in frontier {
      for end in piece_ends(piece, text, from) {
        add_position(next, end)
      }
    }
    steps = steps + 1
    if steps >= least {
      for end in next {
        add_position(ends, end)
      }
    }
    frontier = next
  }
  ends
}

///|
/// Whether one member of a class is a character.
fn class_item_matches(item : ClassItem, ch : Char) -> Bool {
  match item {
    One(wanted) => ch == wanted
    // An inverted range — `[z-a]` — holds nothing rather than everything: it is
    // a mistake in the pattern, and the reading that says so is the one that
    // never matches.
    Range(from, to) => from <= ch && ch <= to
    Named('d') => ch.is_ascii_digit()
    Named('D') => !ch.is_ascii_digit()
    Named('w') => ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '_'
    Named('W') =>
      !(ch.is_ascii_alphabetic() || ch.is_ascii_digit() || ch == '_')
    Named('s') => is_space(ch)
    Named('S') => !is_space(ch)
    // Unreachable: `read_escape` answers `Named` for the six sets alone.
    Named(_) => false
  }
}

///|
/// Whether a character is one of the six the schema dialect calls whitespace.
///
/// The six are the ones a JavaScript engine matches: the space, the tab, the
/// line feed, the carriage return and the two that only exist as escapes.
fn is_space(ch : Char) -> Bool {
  ch == ' ' ||
  ch == '\t' ||
  ch == '\n' ||
  ch == '\r' ||
  ch == '\u{0B}' ||
  ch == '\u{0C}'
}

///|
/// Whether a character is in a class, negated or not.
fn class_matches(items : Array[ClassItem], negated : Bool, ch : Char) -> Bool {
  let mut found = false
  for item in items {
    if class_item_matches(item, ch) {
      found = true
    }
  }
  if negated {
    !found
  } else {
    found
  }
}

///|
/// Add a position to a list of them, unless it is already there.
///
/// The positions are what the matcher carries from one piece to the next, so
/// their number is what the rest of the matching costs: two ways of reaching one
/// place leave one place to go on from, and a repetition of something that
/// consumes nothing would otherwise fill the list with copies of itself.
fn add_position(positions : Array[Int], position : Int) -> Unit {
  if !positions.contains(position) {
    positions.push(position)
  }
}
