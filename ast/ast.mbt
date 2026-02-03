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
  StringLit(String, @token.Loc)
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
} derive(Show, Eq)

///|
pub(all) struct Param {
  name : String
  default_val : Expr?
} derive(Show, Eq)

///|
pub(all) enum Pattern {
  IdentPat(String)
  ArrayPat(Array[Pattern?], Pattern?) // elements (None = hole), rest pattern
  ObjectPat(Array[PropPat], Pattern?) // properties, rest pattern
} derive(Show, Eq)

///|
pub(all) struct PropPat {
  key : String
  value : Pattern
  default_val : Expr?
} derive(Show, Eq)

///|
pub(all) enum Stmt {
  ExprStmt(Expr, @token.Loc)
  VarDecl(VarKind, String, Expr?, @token.Loc)
  Block(Array[Stmt], @token.Loc)
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
  DestructureDecl(VarKind, Pattern, Expr, @token.Loc)
  LabeledStmt(String, Stmt, @token.Loc)
} derive(Show, Eq)

///|
pub(all) struct Program {
  stmts : Array[Stmt]
} derive(Show, Eq)
