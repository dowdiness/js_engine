///|
test "pattern immediate children visit object property in source order" {
  let loc = @token.Loc::default()
  let property : @ast.PropPat = {
    key: "value",
    key_lex_form: @token.LexForm::LexNormal,
    key_loc: loc,
    value: @ast.Pattern::IdentPat("value"),
    default_val: Some(@ast.Expr::Ident("default", loc)),
    computed_key: Some(@ast.Expr::Ident("computed", loc)),
  }
  let pattern = @ast.Pattern::ObjectPat([property], None)
  let seen : Array[String] = []
  let _ = @ast.pattern_immediate_children_any(
    pattern,
    _ => {
      seen.push("value-pattern")
      false
    },
    expr => {
      match expr {
        @ast.Expr::Ident(name, _) => {
          seen.push(name)
          false
        }
        _ => false
      }
    },
  )
  json_inspect(seen, content=["computed", "value-pattern", "default"])
}
