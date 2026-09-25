///|
/// Whether a pattern matches, with a pattern that cannot be read counted as a
/// failure: no test here is about a pattern the engine refuses unless it says so
/// by name.
fn matches(pattern : String, text : String) -> Bool {
  match pattern_matches(pattern, text) {
    Ok(answer) => answer
    Err(message) => abort("the pattern was not read: " + message)
  }
}

///|
/// Whether a string is a match of an anchored pattern, also asked of the same
/// text with a line feed after it: a pattern that matches everything matches the
/// wrong test as well, and the pair of answers is what says it does not.
///
/// The line feed is the character no anchored pattern of these tests can take
/// for one of its own — it is not a digit, a letter or anything else in a class
/// — so a pattern that says it ends at the end still finds itself past it.
fn matches_only(pattern : String, text : String) -> Bool {
  matches(pattern, text) && !matches(pattern, text + "\n")
}

///|
/// The reason a pattern is not read.
fn refusal(pattern : String) -> String {
  match pattern_matches(pattern, "anything") {
    Ok(_) => abort("the pattern was read: " + pattern)
    Err(message) => message
  }
}

///|
test "a literal is looked for anywhere in the text" {
  assert_true(matches("b", "abc"))
  assert_false(matches("d", "abc"))
  // Nothing is anchored unless it anchors itself, and a pattern with nothing in
  // it is found at every position, which is what a regular expression with no
  // pieces means.
  assert_true(matches("", "abc"))
  assert_true(matches("abc", "abc"))
  assert_true(matches("abc", "xxabcxx"))
  assert_false(matches("abcd", "abc"))
}

///|
test "^ and $ are the two ends of the text" {
  assert_true(matches("^a", "abc"))
  assert_false(matches("^b", "abc"))
  assert_true(matches("c$", "abc"))
  assert_false(matches("b$", "abc"))
  assert_true(matches("^abc$", "abc"))
  assert_false(matches("^abc$", "abcd"))
  // The empty text is both ends at once, and a text of one line has no other
  // end for `$` to mean.
  assert_true(matches("^$", ""))
  assert_false(matches("^$", "\n"))
  // Without `^` a pattern is found past the beginning, which is the whole
  // difference between the two: `^` is the only thing that says where a match
  // has to start.
  assert_true(matches("b$", "ab"))
  assert_false(matches("^b", "ab"))
}

///|
test "a dot is any character but a line feed" {
  assert_true(matches("a.c", "abc"))
  assert_true(matches("a.c", "a c"))
  assert_false(matches("a.c", "ac"))
  assert_false(matches("a.c", "a\nc"))
  // A character outside the basic plane is one character, so one dot is the
  // whole of it: counting in code units would have made it two.
  assert_true(matches("^.$", "😀"))
  assert_false(matches("^..$", "😀"))
}

///|
test "a class holds the characters it lists" {
  assert_true(matches("^[abc]+$", "cab"))
  assert_false(matches("^[abc]+$", "cad"))
  assert_true(matches("^[a-c]+$", "abc"))
  assert_false(matches("^[a-c]+$", "abd"))
  // A negated class holds everything else, the line feed included: only `.`
  // leaves one out.
  assert_true(matches("^[^a-c]+$", "xyz"))
  assert_false(matches("^[^a-c]+$", "xay"))
  assert_true(matches("^[^a]+$", "\n"))
  // A `-` is a range between two characters and the character itself at either
  // end, and a class with nothing in it holds nothing.
  assert_true(matches("^[a-]+$", "a-a"))
  assert_false(matches("^[]$", ""))
  assert_false(matches("a[]b", "ab"))
}

///|
test "the sets \\d, \\w and \\s are classes of their own" {
  assert_true(matches("^\\d{3}-\\d{4}$", "555-1234"))
  assert_false(matches("^\\d{3}-\\d{4}$", "55-1234"))
  assert_true(matches("^\\w+$", "a_1"))
  assert_false(matches("^\\w+$", "a-1"))
  assert_true(matches("^\\s$", "\t"))
  assert_true(matches("^\\D$", "a"))
  assert_false(matches("^\\D$", "1"))
  assert_true(matches("^\\W$", "-"))
  assert_true(matches("^[\\d]+$", "12"))
  assert_true(matches("^[^\\d]+$", "ab"))
  // A set inside a class is a member like any other, so a class can hold one
  // set and hold out another.
  assert_true(matches("^[\\w-]+$", "a-1"))
  assert_false(matches("^[\\d-]+$", "a-1"))
}

///|
test "a repetition says how many times, and a ? after it changes nothing here" {
  assert_true(matches("^a*$", ""))
  assert_true(matches("^a*$", "aaa"))
  assert_false(matches("^a+$", ""))
  assert_true(matches("^a+$", "aaa"))
  assert_true(matches("^a?$", ""))
  assert_true(matches("^a?$", "a"))
  assert_false(matches("^a?$", "aa"))
  assert_true(matches("^a{2}$", "aa"))
  assert_false(matches("^a{2}$", "aaa"))
  assert_true(matches("^a{2,}$", "aaaa"))
  assert_false(matches("^a{2,}$", "a"))
  assert_true(matches("^a{2,3}$", "aa"))
  assert_true(matches("^a{2,3}$", "aaa"))
  assert_false(matches("^a{2,3}$", "aaaa"))
  // The `?` asks for the shortest match rather than the longest, and the
  // question here is whether a match is there at all, so it answers the same
  // either way.
  assert_true(matches("^a*?$", "aa"))
  assert_true(matches("^a{2,3}?$", "aa"))
  assert_false(matches("^a{2,3}?$", "aab"))
  assert_true(matches("a{2}b", "aab"))
}

///|
test "a group holds a pattern, and a bar is the choice between them" {
  assert_true(matches("^(a|b)c$", "ac"))
  assert_true(matches("^(a|b)c$", "bc"))
  assert_false(matches("^(a|b)c$", "cc"))
  assert_true(matches("^ab|cd$", "cd"))
  // A group repeats as one piece, which is what makes it a group rather than a
  // bracket: `(ab)+` is `ab` any number of times and `ab+` is `a` and a run of
  // `b`.
  assert_true(matches("^(ab)+$", "abab"))
  assert_false(matches("^(ab)+$", "aba"))
  assert_true(matches("^ab+$", "abbb"))
  assert_false(matches("^ab+$", "abab"))
  assert_true(matches("^(a|b)*c$", "abbac"))
  // A branch with nothing in it matches nothing, and a branch is chosen by
  // where it leads rather than by its order.
  assert_true(matches("^(a|)b$", "b"))
  assert_true(matches("^(a|)b$", "ab"))
}

///|
test "an escape is the character it names, however it is written" {
  assert_true(matches("^a\\.c$", "a.c"))
  assert_false(matches("^a\\.c$", "abc"))
  assert_true(matches("^\\*$", "*"))
  assert_true(matches("^\\\\$", "\\"))
  assert_true(matches("^\\t$", "\t"))
  assert_true(matches("^a\\nb$", "a\nb"))
  assert_true(matches("^\\f$", "\u{0C}"))
  assert_true(matches("^\\r$", "\r"))
  assert_true(matches("^\\v$", "\u{0B}"))
  assert_true(matches("^\\0$", "\u{0}"))
  assert_true(matches("^\\u0041$", "A"))
  assert_true(matches("^\\u0041+$", "AAA"))
  assert_false(matches("^\\u0041$", "a"))
}

///|
test "a pattern this tool cannot read says what it reached for" {
  // Each of these is a mistake rather than a pattern of its own: the reader
  // stops at the first one and says where, so a schema holding one is reported
  // rather than matched as something else.
  assert_true(refusal("(").contains("never closed"))
  assert_true(refusal("[a").contains("never closed"))
  assert_true(refusal("a{").contains("repetition"))
  assert_true(refusal("a{}").contains("repetition"))
  assert_true(refusal("a{2").contains("never closed"))
  // A repetition that stops in the middle — before its closing brace, or at
  // something that is neither a digit nor a brace nor a comma — is refused where
  // it stops rather than read as the characters it is made of.
  assert_true(refusal("a{2,").contains("never closed"))
  assert_true(refusal("a{2x}").contains("must open a repetition"))
  assert_true(refusal("*a").contains("nothing to repeat"))
  assert_true(refusal("a)b").contains("\")\" has no matching"))
  assert_true(refusal("\\q").contains("not an escape"))
  // A mistake inside a group or a class is reached through what holds it, and
  // the reason is the one the escape gave rather than the bracket's.
  assert_true(refusal("(\\q)").contains("not an escape"))
  assert_true(refusal("[\\q]").contains("not an escape"))
  assert_true(refusal("[a-\\q]").contains("not an escape"))
  assert_true(refusal("\\u12").contains("four hexadecimal digits"))
  assert_true(refusal("\\uD83D").contains("does not name a character"))
  assert_true(refusal("\\").contains("last character"))
  assert_true(refusal("[a-\\d]").contains("set of them"))
  assert_true(refusal("a{3,2}").contains("cannot start at 3"))
  // A backspace is written `\b` in some dialects and is a word boundary in
  // others; neither is read here, and a schema that means the character can
  // write it as `\u0008`.
  assert_true(refusal("\\b").contains("not an escape"))
  assert_true(matches("^\\u0008$", "\u{8}"))
}

///|
/// `count` copies of `text`, for the test that needs a long run of one
/// character: a pattern that goes round for ever is one that goes round for ever
/// on a short text too, but a long one is where it would be noticed.
fn repeated(text : String, count : Int) -> String {
  let out = StringBuilder()
  let mut index = 0
  while index < count {
    out.write_string(text)
    index = index + 1
  }
  out.to_string()
}

///|
test "a repetition that can match nothing does not go round for ever" {
  // Both of these reach the same places over and over: the first repeats
  // something that can be empty, and the second has two ways of consuming the
  // same character. Neither can hang, and neither is exponential — the answer
  // is the same on a short text as on a long one.
  let a_run = repeated("a", 40)
  assert_false(matches("^(a*)*b$", a_run))
  assert_false(matches("^(a|a)*b$", a_run))
  assert_true(matches("^(a*)*b$", a_run + "b"))
  assert_true(matches("^(a|a)*b$", a_run + "b"))
  // Something that consumes nothing repeated a great many times still matches
  // where it should: the count is reached through the empty match, not by
  // consuming forty characters.
  assert_true(matches("^(a?){50}$", "aa"))
  assert_true(matches("^(a?){0,}$", ""))
  // A count with more digits than an Int holds is read as a count no text can
  // satisfy, which is what it is, rather than as the digits taken as a number
  // that wraps around to something small — and asking it of a text that cannot
  // hold that many is answered by the text running out, not by counting up.
  assert_false(matches("^a{9999999999}$", a_run))
  assert_false(matches("^a{9999999999,}$", a_run))
}

///|
test "a pattern is counted in characters rather than in code units" {
  // A character outside the basic plane is one character, so one `.` is the
  // whole of it and two of them are one too many: counting in code units would
  // have made the emoji two.
  assert_true(matches("^.$", "😀"))
  assert_true(matches("^[\\s\\S]$", "😀"))
  // A pair of escapes standing for one of those characters is not read at all:
  // each half is a surrogate and a surrogate is not a character, so there is
  // nothing here for the pair to match with.
  assert_true(refusal("^\\uD83D\\uDE00$").contains("does not name a character"))
}

///|
test "an anchored pattern is looked for at one position" {
  // The `^` fails everywhere but the start, which is what makes the search over
  // the positions of the text a walk rather than a cost: a pattern that says
  // where it starts is tried where it says.
  assert_true(matches_only("^\\d{4}-\\d{2}-\\d{2}$", "2026-09-25"))
  assert_true(
    matches_only(
      "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", "a.b+1@moonbit.example",
    ),
  )
  assert_true(matches_only("^[a-z]([a-z0-9-]*[a-z0-9])?$", "moon-json-2"))
}
