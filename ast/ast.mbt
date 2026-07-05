///|
pub(all) enum BinOp {
  Add
  Sub
  Mul
  Div
  Mod
  EqEq
  EqEqEq
  NotEq
  NotEqEq
  Lt
  Gt
  LtEq
  GtEq
  And
  Or
  NullishCoalesce // ??
  BitAnd
  BitOr
  BitXor
  LShift
  RShift
  URShift
  Exp
  In
  Instanceof
} derive(Debug, Eq)

///|
pub(all) enum UnaryOp {
  Neg
  Pos
  Not
  Typeof
  Void
  Delete
  BitNot
} derive(Debug, Eq)

///|
pub(all) enum UpdateOp {
  Increment
  Decrement
} derive(Debug, Eq)

///|
pub(all) enum CompoundOp {
  AddAssign
  SubAssign
  MulAssign
  DivAssign
  ModAssign
  ExpAssign
  BitAndAssign
  BitOrAssign
  BitXorAssign
  LShiftAssign
  RShiftAssign
  URShiftAssign
  LogicalAndAssign // &&=
  LogicalOrAssign // ||=
  NullishAssign // ??=
} derive(Debug, Eq)

///|
pub(all) enum VarKind {
  LetKind
  ConstKind
  VarKind
} derive(Debug, Eq)

///|
pub(all) enum PropKind {
  Init // normal property
  Get // getter
  Set // setter
  Spread // spread property: { ...expr }
} derive(Debug, Eq)

///|
pub(all) struct Property {
  key : Expr // StringLit for static keys, any Expr for computed keys
  value : Expr
  kind : PropKind
  computed : Bool // true for [expr]: value syntax
  // True for method-shorthand (`{ m() {} }`, `{ *m() {} }`, `{ async m() {} }`)
  // and for getters/setters. False for `key: value` entries even when the
  // value happens to be a function. Drives whether the function gets a
  // §15.2.5 FunctionExpressionName self-binding when evaluated.
  is_method : Bool
} derive(Debug, Eq)

///|
pub(all) struct SwitchCase {
  condition : Expr?
  body : Array[Stmt]
} derive(Debug, Eq)

///|
pub(all) enum Expr {
  NumberLit(Double, @token.LexForm, @token.Loc)
  StringLit(String, Bool, @token.LexForm, @token.Loc) // value, has_escape, lex_form, loc
  BoolLit(Bool, @token.Loc)
  NullLit(@token.Loc)
  UndefinedLit(@token.Loc)
  ArrayHole(@token.Loc) // elision in array literal: [1,,3] → hole at index 1
  Ident(String, @token.Loc)
  Binary(BinOp, Expr, Expr, @token.Loc)
  Unary(UnaryOp, Expr, @token.Loc)
  Assign(String, Expr, @token.Loc)
  Call(Expr, Array[Expr], @token.Loc)
  Member(Expr, String, @token.Loc)
  Ternary(Expr, Expr, Expr, @token.Loc)
  FuncExpr(String?, Array[String], Array[Stmt], @token.Loc, String?)
  FuncExprExt(String?, Array[Param], String?, Array[Stmt], @token.Loc, String?) // name, params, rest_param, body, source_text
  Grouping(Expr, @token.Loc)
  ObjectLit(Array[Property], @token.Loc)
  ArrayLit(Array[Expr], @token.Loc)
  ComputedMember(Expr, Expr, @token.Loc)
  MemberAssign(Expr, String, Expr, @token.Loc)
  ComputedAssign(Expr, Expr, Expr, @token.Loc)
  NewExpr(Expr, Array[Expr], @token.Loc)
  ThisExpr(@token.Loc)
  UpdateExpr(UpdateOp, Expr, Bool, @token.Loc)
  CompoundAssign(CompoundOp, Expr, Expr, @token.Loc)
  Comma(Expr, Expr, @token.Loc)
  TemplateLit(Array[(String, String?)], Array[Expr], @token.Loc) // quasis: (raw, cooked?)
  ArrowFunc(Array[String], Array[Stmt], @token.Loc, String?)
  ArrowFuncExt(Array[Param], String?, Array[Stmt], @token.Loc, String?) // params, rest_param, body, source_text
  SpreadExpr(Expr, @token.Loc)
  RegexLit(String, String, @token.Loc) // pattern, flags
  DestructureAssign(Pattern, Expr, @token.Loc)
  OptionalMember(Expr, String, @token.Loc) // obj?.prop
  OptionalComputedMember(Expr, Expr, @token.Loc) // obj?.[expr]
  OptionalCall(Expr, Array[Expr], @token.Loc) // func?.(args)
  ChainMember(Expr, String, @token.Loc) // optional chain continuation .prop
  ChainComputedMember(Expr, Expr, @token.Loc) // optional chain continuation [expr]
  // Class expressions
  ClassExpr(String?, Expr?, Array[ClassMember], @token.Loc, String?) // name, superclass, members, source_text
  SuperCall(Array[Expr], @token.Loc) // super(args)
  SuperMember(String, @token.Loc) // super.prop
  SuperComputedMember(Expr, @token.Loc) // super[expr]
  NewTargetExpr(@token.Loc) // new.target
  TaggedTemplate(Expr, Array[(String, String?)], Array[Expr], @token.Loc) // tag, quasis (raw, cooked?), exprs
  // Generator expressions
  GeneratorExpr(String?, Array[String], Array[Stmt], @token.Loc, String?) // name, params, body, source_text
  GeneratorExprExt(
    String?,
    Array[Param],
    String?,
    Array[Stmt],
    @token.Loc,
    String?
  ) // name, params, rest_param, body, source_text
  // Yield expression
  YieldExpr(Expr?, Bool, @token.Loc) // argument, delegate (yield* vs yield)
  // Async function expressions
  AsyncFuncExpr(String?, Array[String], Array[Stmt], @token.Loc, String?) // name, params, body, source_text
  AsyncFuncExprExt(
    String?,
    Array[Param],
    String?,
    Array[Stmt],
    @token.Loc,
    String?
  ) // name, params, rest_param, body, source_text
  // Async arrow functions
  AsyncArrowFunc(Array[String], Array[Stmt], @token.Loc, String?) // params, body, source_text
  AsyncArrowFuncExt(Array[Param], String?, Array[Stmt], @token.Loc, String?) // params, rest_param, body, source_text
  // Async generator expressions
  AsyncGeneratorExpr(String?, Array[String], Array[Stmt], @token.Loc, String?) // name, params, body, source_text
  AsyncGeneratorExprExt(
    String?,
    Array[Param],
    String?,
    Array[Stmt],
    @token.Loc,
    String?
  ) // name, params, rest_param, body, source_text
  // Await expression
  AwaitExpr(Expr, @token.Loc) // argument
  // Annex B §B.3.4: f()=g() non-strict — eval call for side effects, then throw ReferenceError (strict: SyntaxError)
  WebCompatCallAssign(Expr, Expr, @token.Loc)
} derive(Debug, Eq)

///|
pub(all) struct Param {
  name : String
  default_val : Expr?
  pattern : Pattern? // For destructuring parameters like ({x, y}) or ([a, b])
  is_rest_pattern : Bool // true only for destructuring rest parameters like ...[x]
} derive(Debug, Eq)

///|
pub(all) enum Pattern {
  IdentPat(String)
  ArrayPat(Array[Pattern?], Pattern?) // elements (None = hole), rest pattern
  ObjectPat(Array[PropPat], Pattern?) // properties, rest pattern
  DefaultPat(Pattern, Expr) // pattern with default initializer: pat = expr
  AssignTarget(Expr) // member expression target for destructuring assignment: [obj.x] = [1]
} derive(Debug, Eq)

///|
pub(all) struct PropPat {
  key : String
  key_lex_form : @token.LexForm // provenance for strict-mode legacy-octal validation
  key_loc : @token.Loc // location of the key token, for error pinpointing
  value : Pattern
  default_val : Expr?
  computed_key : Expr? // For computed property keys: { [expr]: pattern }
} derive(Debug, Eq)

///|
pub(all) struct ImportSpecifier {
  local_name : String // local binding name
  imported : String // name exported by the module
} derive(Debug, Eq)

///|
pub(all) struct ExportSpecifier {
  local_name : String // local binding name
  exported : String // name to export as
} derive(Debug, Eq)

///|
pub(all) struct ClassMethod {
  key : Expr // StringLit for static keys, any Expr for computed keys
  value : Expr // Usually FuncExpr or FuncExprExt
  kind : PropKind // Init for regular method, Get for getter, Set for setter
  computed : Bool // true for [expr]() syntax
  is_static : Bool // true for static methods
} derive(Debug, Eq)

///|
pub(all) struct ClassField {
  key : Expr // StringLit for string keys, any Expr for computed keys
  initializer : Expr? // None if no `= expr`
  computed : Bool // true for [expr] syntax
  is_static : Bool // true for static fields
} derive(Debug, Eq)

///|
pub(all) enum ClassMember {
  Method(ClassMethod)
  Field(ClassField)
} derive(Debug, Eq)

///|
pub(all) enum Stmt {
  ExprStmt(Expr, @token.Loc)
  VarDecl(VarKind, String, Expr?, @token.Loc)
  Block(Array[Stmt], @token.Loc)
  StmtList(Array[Stmt], @token.Loc) // Multiple statements without new scope (for comma-separated decls)
  IfStmt(Expr, Stmt, Stmt?, @token.Loc)
  WhileStmt(Expr, Stmt, @token.Loc)
  ForStmt(Stmt?, Expr?, Expr?, Stmt, @token.Loc)
  FuncDecl(String, Array[String], Array[Stmt], @token.Loc, String?)
  FuncDeclExt(String, Array[Param], String?, Array[Stmt], @token.Loc, String?) // name, params, rest_param, body, source_text
  ReturnStmt(Expr?, @token.Loc)
  BreakStmt(String?, @token.Loc)
  ContinueStmt(String?, @token.Loc)
  ThrowStmt(Expr, @token.Loc)
  TryCatchStmt(Array[Stmt], Pattern?, Array[Stmt]?, Array[Stmt]?, @token.Loc)
  SwitchStmt(Expr, Array[SwitchCase], @token.Loc)
  DoWhileStmt(Stmt, Expr, @token.Loc)
  ForInStmt(VarKind?, String, Expr, Stmt, @token.Loc)
  ForOfStmt(VarKind?, String, Expr, Stmt, @token.Loc)
  ForInStmtPat(VarKind?, Pattern, Expr, Stmt, @token.Loc)
  ForOfStmtPat(VarKind?, Pattern, Expr, Stmt, @token.Loc)
  ForInExpr(Expr, Expr, Stmt, @token.Loc) // for (expr in obj) where expr is member/computed
  ForOfExpr(Expr, Expr, Stmt, @token.Loc) // for (expr of iterable) where expr is member/computed
  // Async for-await-of statements
  AsyncForOfStmt(VarKind?, String, Expr, Stmt, @token.Loc) // for await (var x of iterable)
  AsyncForOfStmtPat(VarKind?, Pattern, Expr, Stmt, @token.Loc) // for await (var [a,b] of iterable)
  AsyncForOfExpr(Expr, Expr, Stmt, @token.Loc) // for await (expr of iterable) where expr is member/computed
  DestructureDecl(VarKind, Pattern, Expr, @token.Loc)
  LabeledStmt(String, Stmt, @token.Loc)
  // Generator declarations
  GeneratorDecl(String, Array[String], Array[Stmt], @token.Loc, String?) // name, params, body, source_text
  GeneratorDeclExt(
    String,
    Array[Param],
    String?,
    Array[Stmt],
    @token.Loc,
    String?
  ) // name, params, rest_param, body, source_text
  // Async function declarations
  AsyncFuncDecl(String, Array[String], Array[Stmt], @token.Loc, String?) // name, params, body, source_text
  AsyncFuncDeclExt(
    String,
    Array[Param],
    String?,
    Array[Stmt],
    @token.Loc,
    String?
  ) // name, params, rest_param, body, source_text
  // Async generator declarations
  AsyncGeneratorDecl(String, Array[String], Array[Stmt], @token.Loc, String?) // name, params, body, source_text
  AsyncGeneratorDeclExt(
    String,
    Array[Param],
    String?,
    Array[Stmt],
    @token.Loc,
    String?
  ) // name, params, rest_param, body, source_text
  // Class declaration
  ClassDecl(String, Expr?, Array[ClassMember], @token.Loc, String?) // name, superclass, members, source_text
  // With statement (sloppy mode only)
  WithStmt(Expr, Stmt, @token.Loc) // with(expr) stmt
  // Module declarations
  // import defaultExport from 'source'
  // import { spec1, spec2 } from 'source'
  // import * as namespace from 'source'
  // import 'source' (side effect only)
  ImportDecl(
    String?, // default import name
    Array[ImportSpecifier], // named imports: { a, b as c }
    String?, // namespace import: * as name
    String, // module source string
    @token.LexForm, // source_lex_form: provenance for strict validator
    @token.Loc
  )
  // export { spec1, spec2 }
  // export { spec1 } from 'source' (re-export)
  ExportNamedDecl(
    Stmt?, // declaration (var/let/const/func/class)
    Array[ExportSpecifier], // named specifiers
    String?, // source for re-export
    @token.LexForm, // source_lex_form: LexNormal if no source
    @token.Loc
  )
  // export default expression
  ExportDefaultDecl(Expr, @token.Loc)
  // export * from 'source'
  // export * as name from 'source'
  ExportAllDecl(
    String?, // optional alias: export * as name
    String, // source module
    @token.LexForm, // source_lex_form: provenance for strict validator
    @token.Loc
  )
} derive(Debug, Eq)

///|
pub(all) struct Program {
  stmts : Array[Stmt]
} derive(Debug, Eq)

// Show impls delegating to Debug (derive(Show) is deprecated in MoonBit v0.9)

///|
pub impl Show for BinOp with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for UnaryOp with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for UpdateOp with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for CompoundOp with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for VarKind with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for PropKind with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for Property with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for SwitchCase with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for Expr with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for Param with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for Pattern with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for PropPat with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for ImportSpecifier with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for ExportSpecifier with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for ClassMethod with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for ClassField with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for ClassMember with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for Stmt with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub impl Show for Program with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}
