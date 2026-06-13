///|
/// Source kinds for preparation inputs. Each kind determines which strictness
/// inheritance rules and early-error families apply.
///
/// See architecture-execution-plan-2026-06-12.md §5 for the full preparation
/// boundary specification.
pub(all) enum SourceKind {
  Script
  Module
  DirectEval
  IndirectEval
  FunctionConstructor
  GeneratorFunctionConstructor
  AsyncFunctionConstructor
  AsyncGeneratorFunctionConstructor
  BytecodeLowering
} derive(Debug, Eq)

///|
/// Scan the directive prologue and return whether "use strict" is present.
///
/// Per ES2024 §11.2.1: a directive is an ExpressionStatement consisting of a
/// StringLiteral at the start of a function body or script. Only the exact
/// string "use strict" without escape sequences activates strict mode.
pub fn has_use_strict(stmts : Array[@ast.Stmt]) -> Bool {
  for stmt in stmts {
    match stmt {
      // String-literal directive: check if it is "use strict"; keep scanning
      // otherwise (other string directives are part of the prologue).
      ExprStmt(StringLit(s, has_escape, _, _), _) =>
        if s == "use strict" && !has_escape {
          return true
        }
      // Non-string ExprStmt or any other statement ends the directive prologue.
      _ => break
    }
  }
  false
}

///|
/// Return whether a body is strict given its own directive prologue and the
/// inherited strictness from the enclosing context.
pub fn body_is_strict(
  stmts : Array[@ast.Stmt],
  inherited_strict : Bool,
) -> Bool {
  inherited_strict || has_use_strict(stmts)
}
