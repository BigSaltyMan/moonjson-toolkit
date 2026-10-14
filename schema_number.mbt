///|
/// Exact decimal arithmetic for schema assertions only. A nonzero value is
/// sign * digits * 10^exponent, with no leading or trailing zero digits.
/// The exponent stores its value with arbitrary precision, never as an Int.
priv struct SchemaNumber {
  negative : Bool
  digits : String
  exponent : @bigint.BigInt
}

///|
/// Read a valid JSON number supplied by the JSON parser. Storage depends on
/// the written numeral, not on the size of the value or its exponent.
fn schema_number(raw : String) -> SchemaNumber {
  let chars = raw.to_array()
  let negative = chars[0] == '-'
  let mut index = if negative { 1 } else { 0 }
  let digits : Array[Char] = []
  let mut fraction = false
  let mut fraction_length = 0
  while index < chars.length() && chars[index] != 'e' && chars[index] != 'E' {
    if chars[index] == '.' {
      fraction = true
    } else {
      digits.push(chars[index])
      if fraction {
        fraction_length = fraction_length + 1
      }
    }
    index = index + 1
  }
  let mut first = 0
  while first < digits.length() && digits[first] == '0' {
    first = first + 1
  }
  if first == digits.length() {
    return { negative: false, digits: "0", exponent: 0N, }
  }
  let mut last = digits.length()
  while digits[last - 1] == '0' {
    last = last - 1
  }
  let exponent = if index == chars.length() {
    0N
  } else {
    // BigInt's decimal reader does not accept the optional plus sign.
    let start = if chars[index + 1] == '+' { index + 2 } else { index + 1 }
    @bigint.BigInt::from_string(String::from_array(chars[start:]))
  }
  {
    negative,
    digits: String::from_array(digits[first:last]),
    exponent: exponent +
    @bigint.BigInt::from_int(digits.length() - last - fraction_length),
  }
}

///|
fn SchemaNumber::is_integer(self : SchemaNumber) -> Bool {
  self.exponent >= 0N
}

///|
/// Compare normalized magnitudes, padding only during digit inspection. No
/// string of exponent-sized zeros is ever allocated, even for huge exponents.
fn SchemaNumber::compare(self : SchemaNumber, other : SchemaNumber) -> Int {
  if self.digits == "0" || other.digits == "0" {
    if self.digits == other.digits {
      return 0
    }
    if self.digits == "0" {
      return if other.negative { 1 } else { -1 }
    }
    return if self.negative { -1 } else { 1 }
  }
  if self.negative != other.negative {
    return if self.negative { -1 } else { 1 }
  }
  let magnitude = self.exponent + @bigint.BigInt::from_int(self.digits.length())
  let other_magnitude = other.exponent +
    @bigint.BigInt::from_int(other.digits.length())
  let mut order = magnitude.compare(other_magnitude)
  if order == 0 {
    let left = self.digits.to_array()
    let right = other.digits.to_array()
    for index in 0..<Int::max(left.length(), right.length()) {
      let first = if index < left.length() { left[index] } else { '0' }
      let second = if index < right.length() { right[index] } else { '0' }
      order = first.compare(second)
      if order != 0 {
        break
      }
    }
  }
  if self.negative {
    -order
  } else {
    order
  }
}

///|
fn schema_number_compare(left : String, right : String) -> Int {
  schema_number(left).compare(schema_number(right))
}

///|
fn schema_number_equal(left : String, right : String) -> Bool {
  schema_number_compare(left, right) == 0
}

///|
fn schema_number_gcd(
  first : @bigint.BigInt,
  second : @bigint.BigInt,
) -> @bigint.BigInt {
  let mut a = first
  let mut b = second
  while b != 0N {
    let remainder = a % b
    a = b
    b = remainder
  }
  a
}

///|
/// The divisor has been prechecked as strictly positive. Reduce A/B, then
/// cancel the denominator using the factors of 10 provided by the exponent.
/// Loops depend on coefficient sizes, never on the exponent's numeric value.
fn schema_number_multiple_of(value_raw : String, divisor_raw : String) -> Bool {
  let value = schema_number(value_raw)
  if value.digits == "0" {
    return true
  }
  let divisor = schema_number(divisor_raw)
  let delta = value.exponent - divisor.exponent
  if delta < 0N {
    // Normalization removed every trailing zero from A. Its reduced numerator
    // A/g divides A and therefore cannot contain a factor of 10 either. A
    // negative delta would require one or more such factors, so it cannot match.
    return false
  }
  let a = @bigint.BigInt::from_string(value.digits)
  let b = @bigint.BigInt::from_string(divisor.digits)
  let mut denominator = b / schema_number_gcd(a, b)
  for factor in [2N, 5N] {
    let mut count = 0N
    while denominator % factor == 0N {
      denominator = denominator / factor
      count = count + 1N
      if count > delta {
        return false
      }
    }
  }
  denominator == 1N
}

///|
/// Convert only after exact integer and range checks. The implementation cap
/// guarantees at most ten digits and an exponent from zero through nine.
fn schema_number_count(raw : String) -> Result[Int, SchemaProblemKind] {
  let number = schema_number(raw)
  if number.negative || !number.is_integer() {
    return Err(InvalidSchema)
  }
  if number.compare(schema_number("1000000000")) > 0 {
    return Err(UnsupportedFeature)
  }
  let mut count = 0
  for digit in number.digits.to_array() {
    count = count * 10 + digit.to_int() - '0'.to_int()
  }
  // The exact comparison above proves this conversion cannot overflow.
  for _ in 0..<number.exponent.to_int() {
    count = count * 10
  }
  Ok(count)
}
