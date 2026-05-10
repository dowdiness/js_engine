///| Whitebox tests for private parsing helpers in conversions.mbt.

///|
test "parse_hex_string - lowercase digits" {
  inspect(parse_hex_string("ff"), content="255")
}

///|
test "parse_hex_string - uppercase digits" {
  inspect(parse_hex_string("FF"), content="255")
}

///|
test "parse_hex_string - mixed case" {
  inspect(parse_hex_string("aB"), content="171")
}

///|
test "parse_hex_string - single digit" {
  inspect(parse_hex_string("f"), content="15")
}

///|
test "parse_hex_string - zero" {
  inspect(parse_hex_string("0"), content="0")
}

///|
test "parse_hex_string - multi digit" {
  inspect(parse_hex_string("10"), content="16")
}

///|
test "parse_hex_string - empty string returns NaN" {
  inspect(parse_hex_string("").is_nan(), content="true")
}

///|
test "parse_hex_string - invalid char returns NaN" {
  inspect(parse_hex_string("fg").is_nan(), content="true")
}

///|
test "parse_hex_string - invalid char mid-string returns NaN" {
  inspect(parse_hex_string("1g2").is_nan(), content="true")
}

///|
test "parse_binary_string - valid" {
  inspect(parse_binary_string("101"), content="5")
}

///|
test "parse_binary_string - zero" {
  inspect(parse_binary_string("0"), content="0")
}

///|
test "parse_binary_string - one" {
  inspect(parse_binary_string("1"), content="1")
}

///|
test "parse_binary_string - all zeros" {
  inspect(parse_binary_string("000"), content="0")
}

///|
test "parse_binary_string - empty string returns NaN" {
  inspect(parse_binary_string("").is_nan(), content="true")
}

///|
test "parse_binary_string - digit 2 returns NaN" {
  inspect(parse_binary_string("102").is_nan(), content="true")
}

///|
test "parse_binary_string - letter returns NaN" {
  inspect(parse_binary_string("1a0").is_nan(), content="true")
}

///|
test "parse_octal_string - valid" {
  inspect(parse_octal_string("17"), content="15")
}

///|
test "parse_octal_string - zero" {
  inspect(parse_octal_string("0"), content="0")
}

///|
test "parse_octal_string - max digit 7" {
  inspect(parse_octal_string("7"), content="7")
}

///|
test "parse_octal_string - multi digit" {
  inspect(parse_octal_string("10"), content="8")
}

///|
test "parse_octal_string - empty string returns NaN" {
  inspect(parse_octal_string("").is_nan(), content="true")
}

///|
test "parse_octal_string - digit 8 returns NaN" {
  inspect(parse_octal_string("18").is_nan(), content="true")
}

///|
test "parse_octal_string - digit 9 returns NaN" {
  inspect(parse_octal_string("19").is_nan(), content="true")
}

///|
test "parse_octal_string - letter returns NaN" {
  inspect(parse_octal_string("1a").is_nan(), content="true")
}
