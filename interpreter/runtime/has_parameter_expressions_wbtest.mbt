///|
fn nested_parameter_pattern(
  terminal : @ast.Pattern,
  depth : Int,
) -> @ast.Pattern {
  let loc = @token.Loc::default()
  let mut pattern = terminal
  for level in 0..<depth {
    if level % 2 == 0 {
      pattern = @ast.Pattern::ArrayPat([None, Some(pattern)], None)
    } else {
      let property : @ast.PropPat = {
        key: "value",
        key_lex_form: @token.LexForm::LexNormal,
        key_loc: loc,
        value: pattern,
        default_val: None,
        computed_key: None,
      }
      pattern = @ast.Pattern::ObjectPat([property], None)
    }
  }
  pattern
}

///|
fn pattern_parameter(pattern : @ast.Pattern) -> @ast.Param {
  {
    name: "$pattern",
    default_val: None,
    pattern: Some(pattern),
    is_rest_pattern: false,
  }
}

///|
test "has_parameter_expressions handles 4096 nested array/object patterns" {
  let loc = @token.Loc::default()
  let with_default = nested_parameter_pattern(
    @ast.Pattern::DefaultPat(
      @ast.Pattern::IdentPat("value"),
      @ast.Expr::NumberLit(1.0, @token.LexForm::LexNormal, loc),
    ),
    4096,
  )
  let without_expression = nested_parameter_pattern(
    @ast.Pattern::IdentPat("plain"),
    4096,
  )
  inspect(
    has_parameter_expressions([pattern_parameter(with_default)]),
    content="true",
  )
  inspect(
    has_parameter_expressions([pattern_parameter(without_expression)]),
    content="false",
  )
}

///|
test "has_parameter_expressions recognizes only parameter expression markers" {
  let loc = @token.Loc::default()
  let expr = @ast.Expr::Ident("marker", loc)
  let ident = @ast.Pattern::IdentPat("value")
  let property = (default_val : @ast.Expr?, computed_key : @ast.Expr?) => @ast.PropPat::{
    key: "value",
    key_lex_form: @token.LexForm::LexNormal,
    key_loc: loc,
    value: ident,
    default_val,
    computed_key,
  }
  let top_default : @ast.Param = {
    name: "value",
    default_val: Some(expr),
    pattern: None,
    is_rest_pattern: false,
  }
  inspect(has_parameter_expressions([top_default]), content="true")
  inspect(
    has_parameter_expressions([
      pattern_parameter(@ast.Pattern::DefaultPat(ident, expr)),
    ]),
    content="true",
  )
  inspect(
    has_parameter_expressions([
      pattern_parameter(@ast.Pattern::AssignTarget(expr)),
    ]),
    content="true",
  )
  inspect(
    has_parameter_expressions([
      pattern_parameter(
        @ast.Pattern::ObjectPat([property(Some(expr), None)], None),
      ),
    ]),
    content="true",
  )
  inspect(
    has_parameter_expressions([
      pattern_parameter(
        @ast.Pattern::ObjectPat([property(None, Some(expr))], None),
      ),
    ]),
    content="true",
  )
  inspect(
    has_parameter_expressions([
      pattern_parameter(@ast.Pattern::ArrayPat([None], Some(ident))),
    ]),
    content="false",
  )
  inspect(
    has_parameter_expressions([
      pattern_parameter(@ast.Pattern::ObjectPat([], Some(ident))),
    ]),
    content="false",
  )
}
