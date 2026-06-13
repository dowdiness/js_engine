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
  // Scan the directive prologue: the longest sequence of ExpressionStatements
  // consisting entirely of StringLiterals at the beginning of the body.
  // Only the literal string "use strict" WITHOUT escape sequences activates strict mode.
  for i = 0; i < stmts.length(); i = i + 1 {
    match stmts[i] {
      ExprStmt(StringLit(s, has_escape, _, _), _) =>
        if s == "use strict" && !has_escape {
          return true
        }
      // Continue scanning — other string directives are part of the prologue
      _ => break // Non-string ExprStmt or other statement ends the prologue
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
