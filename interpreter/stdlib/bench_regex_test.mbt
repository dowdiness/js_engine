///|
/// Test: scan-forward optimization for digit pattern on large non-matching string
test "regex digit scan-forward on large non-matching string" {
  let input = "x".repeat(500000)
  let result = regex_search("\\d", "", input) catch { _ => None }
  match result {
    None => ()
    Some(_) => fail("expected None")
  }
}

///|
/// Test: digit pattern finds match at end of large string
test "regex digit scan-forward finds match at end" {
  let input = "x".repeat(500000) + "7"
  let result = regex_search("\\d", "", input) catch { _ => None }
  match result {
    None => fail("expected match")
    Some(_) => ()
  }
}

///|
/// Test: non-whitespace pattern on whitespace-only string
test "regex non-whitespace scan-forward on whitespace-only string" {
  let input = " ".repeat(500000)
  let result = regex_search("\\S", "", input) catch { _ => None }
  match result {
    None => ()
    Some(_) => fail("expected None")
  }
}

///|
/// Test: Literal search with scan-forward
test "regex literal scan-forward on large non-matching string" {
  let input = "x".repeat(500000)
  let result = regex_search("z", "", input) catch { _ => None }
  match result {
    None => ()
    Some(_) => fail("expected None")
  }
}

///|
/// Test: Literal search finds match at end
test "regex literal scan-forward finds match at end" {
  let input = "x".repeat(500000) + "z"
  let result = regex_search("z", "", input) catch { _ => None }
  match result {
    None => fail("expected match")
    Some(_) => ()
  }
}

///|
/// Test: Character class a-z with scan-forward
test "regex char-class scan-forward on non-lowercase string" {
  let input = "9".repeat(500000)
  let result = regex_search("[a-z]", "", input) catch { _ => None }
  match result {
    None => ()
    Some(_) => fail("expected None")
  }
}

///|
/// Test: Quantified pattern with min>0 (has_first_char_bound) scan-forward
test "regex quantified scan-forward on non-matching string" {
  let input = "x".repeat(500000)
  let result = regex_search("\\d+", "", input) catch { _ => None }
  match result {
    None => ()
    Some(_) => fail("expected None")
  }
}

///|
/// Test: Group pattern with first-char bound
test "regex group scan-forward on non-matching string" {
  let input = "x".repeat(500000)
  let result = regex_search("(a)", "", input) catch { _ => None }
  match result {
    None => ()
    Some(_) => fail("expected None")
  }
}

///|
/// Test: Sequence scan-forward via first child
test "regex sequence scan-forward on non-matching string" {
  let input = "x".repeat(500000)
  let result = regex_search("ab", "", input) catch { _ => None }
  match result {
    None => ()
    Some(_) => fail("expected None")
  }
}
