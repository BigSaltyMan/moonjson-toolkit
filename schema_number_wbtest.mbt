///|
test "schema numbers normalize signs digits and decimal exponents" {
  for
    (raw, negative, digits, exponent) in [
      ("1.2e1", false, "12", "0"),
      ("100e-2", false, "1", "0"),
      ("0.001e3", false, "1", "0"),
      ("-1200.00e+0002", true, "12", "4"),
      ("1.0e-1", false, "1", "-1"),
      ("0", false, "0", "0"),
      ("-0.0e-1000", false, "0", "0"),
    ] {
    let number = schema_number(raw)
    assert_eq(number.negative, negative)
    assert_eq(number.digits, digits)
    assert_eq(number.exponent.to_string(), exponent)
  }
}

///|
test "schema integer detection uses the mathematical value" {
  for
    raw in [
      "1", "1.0", "1e3", "1.2e1", "100e-2", "0.001e3", "0", "-0", "0e-1000", "-1.2e1",
    ] {
    assert_true(is_whole_number(raw))
  }
  for raw in ["1e-1", "1.0e-1", "12e-1", "-1e-1", "1e-400", "-0.001", "123e-2"] {
    assert_false(is_whole_number(raw))
  }
}

///|
test "exact comparison orders signed numbers and reverses with its arguments" {
  let ordered = [
    "-1e401", "-1e400", "-9007199254740993", "-9007199254740992", "-1", "-0.1", "-1e-400",
    "0", "1e-400", "0.1", "0.10000000000000001", "1", "9007199254740992", "9007199254740993",
    "1e400", "1e401",
  ]
  for i, left in ordered {
    for j, right in ordered {
      assert_eq(schema_number_compare(left, right), i.compare(j))
      assert_eq(
        schema_number_compare(left, right),
        -schema_number_compare(right, left),
      )
    }
  }
  for
    (left, right) in [
      ("1", "1.0"),
      ("1", "1e0"),
      ("-12", "-1.2e1"),
      ("0", "-0"),
      ("0.0", "0e100"),
      ("-0e-1000", "0"),
      ("100e-2", "1"),
      ("0.001e3", "1"),
      ("12300e-2", "1.23e2"),
    ] {
    assert_true(schema_number_equal(left, right))
    assert_true(schema_number_equal(right, left))
  }
}

///|
test "arbitrary size exponents carry borrow and compare without expansion" {
  let nines = String::make(512, '9')
  let power = "1" + String::make(512, '0')
  let positive = schema_number("1e" + power)
  assert_eq(positive.digits.length(), 1)
  assert_true(positive.is_integer())
  assert_true(schema_number_equal("1e" + power, "10e" + nines))
  assert_true(schema_number_equal("1e-" + power, "0.1e-" + nines))
  assert_true(schema_number_compare("1e" + power, "9e" + nines) > 0)
  assert_true(schema_number_compare("1e-" + power, "1e-" + nines) < 0)
  assert_false(is_whole_number("1e-" + power))
  assert_true(is_whole_number("-0e-" + power))
  assert_eq(schema_number_count("1e" + power), Err(UnsupportedFeature))
  assert_eq(schema_number_count("1e-" + power), Err(InvalidSchema))
  assert_eq(schema_number("1e1000000").digits.length(), 1)
  assert_true(schema_number_compare("1e1000000", "9e999999") > 0)
  assert_true(schema_number_compare("1e-1000000", "0") > 0)
}

///|
test "bounded counts validate before converting to Int" {
  for
    (raw, expected) in [
      ("0", 0),
      ("-0e-999999999999999999", 0),
      ("1.2e1", 12),
      ("100e-2", 1),
      ("0.001e3", 1),
      ("1000000000", 1000000000),
      ("1e9", 1000000000),
      ("1000000000.0", 1000000000),
    ] {
    assert_eq(schema_number_count(raw), Ok(expected))
  }
  for raw in ["-1", "1e-1", "1e-400", "-0.1", "1000000000.1"] {
    assert_eq(schema_number_count(raw), Err(InvalidSchema))
  }
  for raw in ["1000000001", "1e10", "1e400", "1.000000001e9"] {
    assert_eq(schema_number_count(raw), Err(UnsupportedFeature))
  }
}
