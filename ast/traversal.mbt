///|
/// Returns whether any immediate expression child of `expr` satisfies `visit`.
///
/// Immediate children are the expression-valued edges represented directly by
/// the expression node: operands, arguments, literal elements and properties,
/// template substitutions, destructuring RHS expressions, and a class's
/// superclass. Function bodies, parameter lists, static blocks, and class
/// member containers are not edges of this traversal. In particular,
/// `ClassExpr` emits only its optional superclass; consumers with class-specific
/// policies must handle class members locally.
///
/// The node itself is not passed to `visit`, and this function never recurses.
/// Children are visited left-to-right and stop at the first `true` result.
pub fn expr_immediate_children_any(
  expr : Expr,
  visit : (Expr) -> Bool,
) -> Bool {
  match expr {
    Binary(_, left, right, _)
    | Comma(left, right, _)
    | ComputedMember(left, right, _)
    | OptionalComputedMember(left, right, _)
    | ChainComputedMember(left, right, _) =>
      visit(left) || visit(right)
    ComputedAssign(obj, key, value, _) =>
      visit(obj) || visit(key) || visit(value)
    Unary(_, inner, _)
    | Grouping(inner, _)
    | SpreadExpr(inner, _)
    | AwaitExpr(inner, _)
    | Member(inner, _, _)
    | OptionalMember(inner, _, _)
    | ChainMember(inner, _, _)
    | PrivateMember(inner, _, _)
    | Assign(_, inner, _)
    | UpdateExpr(_, inner, _, _)
    | SuperComputedMember(inner, _) => visit(inner)
    MemberAssign(obj, _, value, _)
    | PrivateMemberAssign(obj, _, value, _)
    | CompoundAssign(_, obj, value, _)
    | WebCompatCallAssign(obj, value, _) =>
      visit(obj) || visit(value)
    Ternary(condition, then_expr, else_expr, _) =>
      visit(condition) || visit(then_expr) || visit(else_expr)
    Call(callee, args, _)
    | NewExpr(callee, args, _)
    | OptionalCall(callee, args, _) => {
      if visit(callee) {
        true
      } else {
        for arg in args {
          if visit(arg) {
            break true
          }
        } nobreak {
          false
        }
      }
    }
    SuperCall(args, _) =>
      for arg in args {
        if visit(arg) {
          break true
        }
      } nobreak {
        false
      }
    ArrayLit(elements, _) =>
      for element in elements {
        if visit(element) {
          break true
        }
      } nobreak {
        false
      }
    ObjectLit(properties, _) =>
      for property in properties {
        if visit(property.key) || visit(property.value) {
          break true
        }
      } nobreak {
        false
      }
    TemplateLit(_, expressions, _) =>
      for expression in expressions {
        if visit(expression) {
          break true
        }
      } nobreak {
        false
      }
    TaggedTemplate(tag, _, expressions, _) => {
      if visit(tag) {
        true
      } else {
        for expression in expressions {
          if visit(expression) {
            break true
          }
        } nobreak {
          false
        }
      }
    }
    DestructureAssign(_, value, _) => visit(value)
    YieldExpr(argument, _, _) => match argument {
      Some(argument) => visit(argument)
      None => false
    }
    ClassExpr(_, superclass, _, _, _) => match superclass {
      Some(superclass) => visit(superclass)
      None => false
    }
    NumberLit(_, _, _)
    | StringLit(_, _, _, _)
    | BoolLit(_, _)
    | NullLit(_)
    | UndefinedLit(_)
    | ArrayHole(_)
    | Ident(_, _)
    | ThisExpr(_)
    | RegexLit(_, _, _)
    | PrivateIdent(_, _)
    | FuncExpr(_, _, _, _, _)
    | FuncExprExt(_, _, _, _, _, _)
    | ArrowFunc(_, _, _, _)
    | ArrowFuncExt(_, _, _, _, _)
    | GeneratorExpr(_, _, _, _, _)
    | GeneratorExprExt(_, _, _, _, _, _)
    | AsyncFuncExpr(_, _, _, _, _)
    | AsyncFuncExprExt(_, _, _, _, _, _)
    | AsyncArrowFunc(_, _, _, _)
    | AsyncArrowFuncExt(_, _, _, _, _)
    | AsyncGeneratorExpr(_, _, _, _, _)
    | AsyncGeneratorExprExt(_, _, _, _, _, _)
    | SuperMember(_, _)
    | NewTargetExpr(_) => false
  }
}

///|
/// Returns whether any immediate pattern child of `pattern` satisfies
/// `visit_pattern` or any embedded expression child satisfies `visit_expr`.
///
/// Immediate pattern children are nested patterns, array/rest elements,
/// object/rest values, and assignment targets. Embedded expression edges are
/// object computed keys and defaults, pattern defaults, and assignment-target
/// expressions. Children are visited in source order, left-to-right, and stop
/// at the first `true` result. This function never recurses and allocates no
/// child collection.
pub fn pattern_immediate_children_any(
  pattern : Pattern,
  visit_pattern : (Pattern) -> Bool,
  visit_expr : (Expr) -> Bool,
) -> Bool {
  match pattern {
    IdentPat(_) => false
    DefaultPat(inner, default_expr) =>
      visit_pattern(inner) || visit_expr(default_expr)
    ArrayPat(elements, rest) => {
      let elements_result = for element in elements {
        match element {
          Some(element) =>
            if visit_pattern(element) {
              break true
            }
          None => ()
        }
      } nobreak {
        false
      }
      if elements_result {
        true
      } else {
        match rest {
          Some(rest) => visit_pattern(rest)
          None => false
        }
      }
    }
    ObjectPat(properties, rest) => {
      let properties_result = for property in properties {
        if (
          match property.computed_key {
            Some(key) => visit_expr(key)
            None => false
          }
        ) {
          break true
        }
        if (
          match property.default_val {
            Some(default_expr) => visit_expr(default_expr)
            None => false
          }
        ) {
          break true
        }
        if visit_pattern(property.value) {
          break true
        }
      } nobreak {
        false
      }
      if properties_result {
        true
      } else {
        match rest {
          Some(rest) => visit_pattern(rest)
          None => false
        }
      }
    }
    AssignTarget(expr) => visit_expr(expr)
  }
}
