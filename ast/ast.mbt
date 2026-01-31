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
} derive(Show, Eq)

///|
pub(all) enum UnaryOp {
  Neg
  Not
  Typeof
} derive(Show, Eq)

///|
pub(all) enum VarKind {
  LetKind
  ConstKind
  VarKind
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
} derive(Show, Eq)

///|
pub(all) struct Program {
  stmts : Array[Stmt]
} derive(Show, Eq)
