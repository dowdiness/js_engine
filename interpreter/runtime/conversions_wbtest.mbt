///| Whitebox tests for private parsing helpers in conversions.mbt.

///|
fn expect_double(
  actual : Double,
  expected : Double,
  label : String,
) -> Unit raise Error {
  guard actual == expected else {
    fail(
      label +
      ": expected " +
      expected.to_string() +
      ", got " +
      actual.to_string(),
    )
  }
}

///|
fn expect_nan(actual : Double, label : String) -> Unit raise Error {
  guard actual.is_nan() else {
    fail(label + ": expected NaN, got " + actual.to_string())
  }
}

///|
test "parse_hex_string - lowercase digits" {
  expect_double(parse_hex_string("ff"), 255.0, "ff")
}

///|
test "parse_hex_string - uppercase digits" {
  expect_double(parse_hex_string("FF"), 255.0, "FF")
}

///|
test "parse_hex_string - mixed case" {
  expect_double(parse_hex_string("aB"), 171.0, "aB")
}

///|
test "parse_hex_string - single digit" {
  expect_double(parse_hex_string("f"), 15.0, "f")
}

///|
test "parse_hex_string - zero" {
  expect_double(parse_hex_string("0"), 0.0, "0")
}

///|
test "parse_hex_string - multi digit" {
  expect_double(parse_hex_string("10"), 16.0, "10")
}

///|
test "parse_hex_string - empty string returns NaN" {
  expect_nan(parse_hex_string(""), "empty hex")
}

///|
test "parse_hex_string - invalid char returns NaN" {
  expect_nan(parse_hex_string("fg"), "fg")
}

///|
test "parse_hex_string - invalid char mid-string returns NaN" {
  expect_nan(parse_hex_string("1g2"), "1g2")
}

///|
test "parse_binary_string - valid" {
  expect_double(parse_binary_string("101"), 5.0, "101")
}

///|
test "parse_binary_string - zero" {
  expect_double(parse_binary_string("0"), 0.0, "0")
}

///|
test "parse_binary_string - one" {
  expect_double(parse_binary_string("1"), 1.0, "1")
}

///|
test "parse_binary_string - all zeros" {
  expect_double(parse_binary_string("000"), 0.0, "000")
}

///|
test "parse_binary_string - empty string returns NaN" {
  expect_nan(parse_binary_string(""), "empty binary")
}

///|
test "parse_binary_string - digit 2 returns NaN" {
  expect_nan(parse_binary_string("102"), "102")
}

///|
test "parse_binary_string - letter returns NaN" {
  expect_nan(parse_binary_string("1a0"), "1a0")
}

///|
test "parse_octal_string - valid" {
  expect_double(parse_octal_string("17"), 15.0, "17")
}

///|
test "parse_octal_string - zero" {
  expect_double(parse_octal_string("0"), 0.0, "0")
}

///|
test "parse_octal_string - max digit 7" {
  expect_double(parse_octal_string("7"), 7.0, "7")
}

///|
test "parse_octal_string - multi digit" {
  expect_double(parse_octal_string("10"), 8.0, "10")
}

///|
test "parse_octal_string - empty string returns NaN" {
  expect_nan(parse_octal_string(""), "empty octal")
}

///|
test "parse_octal_string - digit 8 returns NaN" {
  expect_nan(parse_octal_string("18"), "18")
}

///|
test "parse_octal_string - digit 9 returns NaN" {
  expect_nan(parse_octal_string("19"), "19")
}

///|
test "parse_octal_string - letter returns NaN" {
  expect_nan(parse_octal_string("1a"), "1a")
}
