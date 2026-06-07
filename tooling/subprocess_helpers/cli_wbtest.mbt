///|
test "repo_default_path resolves defaults from native build executable path" {
  let path = repo_default_path(
    "_build/native/debug/build/cmd/generate_unicode_id_tables/generate_unicode_id_tables.exe",
    "lexer/unicode_id.mbt",
  )
  assert_true(path.has_suffix("/lexer/unicode_id.mbt"))
  assert_true(@fs.path_exists(path))
}
