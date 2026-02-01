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
  BitAnd
  BitOr
  BitXor
  LShift
  RShift
  URShift
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
pub(all) struct Property {
  key : String
  value : Expr
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
  ReturnStmt(Expr?, @token.Loc)
  BreakStmt(@token.Loc)
  ContinueStmt(@token.Loc)
  ThrowStmt(Expr, @token.Loc)
  TryCatchStmt(Array[Stmt], String?, Array[Stmt]?, Array[Stmt]?, @token.Loc)
  SwitchStmt(Expr, Array[SwitchCase], @token.Loc)
  DoWhileStmt(Stmt, Expr, @token.Loc)
  ForInStmt(VarKind?, String, Expr, Stmt, @token.Loc)
  LabeledStmt(String, Stmt, @token.Loc)
} derive(Show, Eq)

///|
pub(all) struct Program {
  stmts : Array[Stmt]
} derive(Show, Eq)
