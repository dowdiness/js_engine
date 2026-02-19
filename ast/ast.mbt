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
} derive(Show, Eq)

///|
pub(all) enum UnaryOp {
  Neg
  Pos
  Not
  Typeof
  Void
  Delete
  BitNot
} derive(Show, Eq)

///|
pub(all) enum UpdateOp {
  Increment
  Decrement
} derive(Show, Eq)

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
} derive(Show, Eq)

///|
pub(all) enum VarKind {
  LetKind
  ConstKind
  VarKind
} derive(Show, Eq)

///|
pub(all) enum PropKind {
  Init // normal property
  Get // getter
  Set // setter
  Spread // spread property: { ...expr }
} derive(Show, Eq)

///|
pub(all) struct Property {
  key : Expr // StringLit for static keys, any Expr for computed keys
  value : Expr
  kind : PropKind
  computed : Bool // true for [expr]: value syntax
} derive(Show, Eq)

///|
pub(all) struct SwitchCase {
  condition : Expr?
  body : Array[Stmt]
} derive(Show, Eq)

///|
pub(all) enum Expr {
  NumberLit(Double, @token.Loc)
  StringLit(String, Bool, @token.Loc) // value, has_escape, loc
  BoolLit(Bool, @token.Loc)
  NullLit(@token.Loc)
  UndefinedLit(@token.Loc)
  Ident(String, @token.Loc)
  Binary(BinOp, Expr, Expr, @token.Loc)
  Unary(UnaryOp, Expr, @token.Loc)
  Assign(String, Expr, @token.Loc)
  Call(Expr, Array[Expr], @token.Loc)
  Member(Expr, String, @token.Loc)
  Ternary(Expr, Expr, Expr, @token.Loc)
  FuncExpr(String?, Array[String], Array[Stmt], @token.Loc)
  FuncExprExt(String?, Array[Param], String?, Array[Stmt], @token.Loc) // name, params, rest_param, body
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
  TemplateLit(Array[String], Array[Expr], @token.Loc)
  ArrowFunc(Array[String], Array[Stmt], @token.Loc)
  ArrowFuncExt(Array[Param], String?, Array[Stmt], @token.Loc) // params, rest_param, body
  SpreadExpr(Expr, @token.Loc)
  RegexLit(String, String, @token.Loc) // pattern, flags
  DestructureAssign(Pattern, Expr, @token.Loc)
  OptionalMember(Expr, String, @token.Loc) // obj?.prop
  OptionalComputedMember(Expr, Expr, @token.Loc) // obj?.[expr]
  OptionalCall(Expr, Array[Expr], @token.Loc) // func?.(args)
  // Class expressions
  ClassExpr(String?, Expr?, Array[ClassMethod], @token.Loc) // name, superclass, methods
  SuperCall(Array[Expr], @token.Loc) // super(args)
  SuperMember(String, @token.Loc) // super.prop
  SuperComputedMember(Expr, @token.Loc) // super[expr]
  NewTargetExpr(@token.Loc) // new.target
  TaggedTemplate(Expr, Array[String], Array[Expr], @token.Loc) // tag`str${expr}str`
  // Generator expressions
  GeneratorExpr(String?, Array[String], Array[Stmt], @token.Loc) // name, params, body
  GeneratorExprExt(String?, Array[Param], String?, Array[Stmt], @token.Loc) // name, params, rest_param, body
  // Yield expression
  YieldExpr(Expr?, Bool, @token.Loc) // argument, delegate (yield* vs yield)
} derive(Show, Eq)

///|
pub(all) struct Param {
  name : String
  default_val : Expr?
  pattern : Pattern? // For destructuring parameters like ({x, y}) or ([a, b])
} derive(Show, Eq)

///|
pub(all) enum Pattern {
  IdentPat(String)
  ArrayPat(Array[Pattern?], Pattern?) // elements (None = hole), rest pattern
  ObjectPat(Array[PropPat], Pattern?) // properties, rest pattern
  DefaultPat(Pattern, Expr) // pattern with default initializer: pat = expr
  AssignTarget(Expr) // member expression target for destructuring assignment: [obj.x] = [1]
} derive(Show, Eq)

///|
pub(all) struct PropPat {
  key : String
  value : Pattern
  default_val : Expr?
} derive(Show, Eq)

///|
pub(all) struct ImportSpecifier {
  local_name : String // local binding name
  imported : String // name exported by the module
} derive(Show, Eq)

///|
pub(all) struct ExportSpecifier {
  local_name : String // local binding name
  exported : String // name to export as
} derive(Show, Eq)

///|
pub(all) struct ClassMethod {
  key : Expr // StringLit for static keys, any Expr for computed keys
  value : Expr // Usually FuncExpr or FuncExprExt
  kind : PropKind // Init for regular method, Get for getter, Set for setter
  computed : Bool // true for [expr]() syntax
  is_static : Bool // true for static methods
} derive(Show, Eq)

///|
pub(all) enum Stmt {
  ExprStmt(Expr, @token.Loc)
  VarDecl(VarKind, String, Expr?, @token.Loc)
  Block(Array[Stmt], @token.Loc)
  StmtList(Array[Stmt], @token.Loc) // Multiple statements without new scope (for comma-separated decls)
  IfStmt(Expr, Stmt, Stmt?, @token.Loc)
  WhileStmt(Expr, Stmt, @token.Loc)
  ForStmt(Stmt?, Expr?, Expr?, Stmt, @token.Loc)
  FuncDecl(String, Array[String], Array[Stmt], @token.Loc)
  FuncDeclExt(String, Array[Param], String?, Array[Stmt], @token.Loc) // name, params, rest_param, body
  ReturnStmt(Expr?, @token.Loc)
  BreakStmt(String?, @token.Loc)
  ContinueStmt(String?, @token.Loc)
  ThrowStmt(Expr, @token.Loc)
  TryCatchStmt(Array[Stmt], String?, Array[Stmt]?, Array[Stmt]?, @token.Loc)
  SwitchStmt(Expr, Array[SwitchCase], @token.Loc)
  DoWhileStmt(Stmt, Expr, @token.Loc)
  ForInStmt(VarKind?, String, Expr, Stmt, @token.Loc)
  ForOfStmt(VarKind?, String, Expr, Stmt, @token.Loc)
  ForInStmtPat(VarKind?, Pattern, Expr, Stmt, @token.Loc)
  ForOfStmtPat(VarKind?, Pattern, Expr, Stmt, @token.Loc)
  ForInExpr(Expr, Expr, Stmt, @token.Loc) // for (expr in obj) where expr is member/computed
  ForOfExpr(Expr, Expr, Stmt, @token.Loc) // for (expr of iterable) where expr is member/computed
  DestructureDecl(VarKind, Pattern, Expr, @token.Loc)
  LabeledStmt(String, Stmt, @token.Loc)
  // Generator declarations
  GeneratorDecl(String, Array[String], Array[Stmt], @token.Loc) // name, params, body
  GeneratorDeclExt(String, Array[Param], String?, Array[Stmt], @token.Loc) // name, params, rest_param, body
  // Class declaration
  ClassDecl(String, Expr?, Array[ClassMethod], @token.Loc) // name, superclass, methods
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
    @token.Loc
  )
  // export { spec1, spec2 }
  // export { spec1 } from 'source' (re-export)
  ExportNamedDecl(
    Stmt?, // declaration (var/let/const/func/class)
    Array[ExportSpecifier], // named specifiers
    String?, // source for re-export
    @token.Loc
  )
  // export default expression
  ExportDefaultDecl(Expr, @token.Loc)
  // export * from 'source'
  // export * as name from 'source'
  ExportAllDecl(
    String?, // optional alias: export * as name
    String, // source module
    @token.Loc
  )
} derive(Show, Eq)

///|
pub(all) struct Program {
  stmts : Array[Stmt]
} derive(Show, Eq)
