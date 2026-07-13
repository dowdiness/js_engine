///|
test "tokenize_command splits on whitespace" {
  json_inspect(tokenize_command("a b\tc\nd"), content=["a", "b", "c", "d"])
}

///|
test "tokenize_command treats empty quotes as adjacent segments" {
  json_inspect(tokenize_command("a\"\"b"), content=["ab"])
  json_inspect(tokenize_command("''"), content=[""])
}

///|
test "tokenize_command preserves backslash inside single quotes" {
  json_inspect(tokenize_command("cmd 'foo\\bar'"), content=["cmd", "foo\\bar"])
}

///|
test "tokenize_command applies selective escapes inside double quotes" {
  json_inspect(tokenize_command("a\"b\\\"c\"d"), content=["ab\"cd"])
  json_inspect(tokenize_command("a\"\\\\b\""), content=["a\\b"])
  json_inspect(tokenize_command("a\"\\$b\""), content=["a$b"])
  json_inspect(tokenize_command("a\"\\`b\""), content=["a`b"])
  let newline_cmd = StringBuilder()
  newline_cmd.write_string("a\"\\")
  newline_cmd.write_char('\n')
  newline_cmd.write_string("b\"")
  json_inspect(tokenize_command(newline_cmd.to_string()), content=["a\nb"])
  json_inspect(tokenize_command("a\"\\nb\""), content=["a\\nb"])
}

///|
test "tokenize_command escapes the next character when unquoted" {
  json_inspect(tokenize_command("a\\ b"), content=["a b"])
}

///|
test "tokenize_command keeps a trailing backslash literally" {
  json_inspect(tokenize_command("a\\"), content=["a\\"])
}

///|
test "tokenize_command rejects unmatched quotes" {
  try {
    ignore(tokenize_command("'open"))
    abort("expected failure")
  } catch {
    _ => ()
  }
}

///|
test "tokenize_command does not perform shell expansion" {
  json_inspect(tokenize_command("echo $HOME *.js"), content=[
    "echo", "$HOME", "*.js",
  ])
}

///|
test "tokenize_command handles quoted command strings for subprocess launch" {
  json_inspect(tokenize_command("sh -c \"printf 'hi there'\""), content=[
    "sh", "-c", "printf 'hi there'",
  ])
}
