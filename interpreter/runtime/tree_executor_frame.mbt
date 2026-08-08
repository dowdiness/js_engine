// Private resumable tree-walker adapter for the closed ordinary UserFunc
// subset admitted below. The executor-neutral coordinator remains the only
// owner of nested calls and activation lifecycle.

///|
priv struct TreeExecutorCode {
  body : Array[@ast.Stmt]
}

///|
fn TreeExecutorCode::TreeExecutorCode(
  body : Array[@ast.Stmt],
) -> TreeExecutorCode {
  { body: body.copy() }
}

///|
priv enum TreeExecutorWork {
  TreeExecuteStatements(Array[@ast.Stmt], Int)
  TreeExecuteStatement(@ast.Stmt)
  TreeEvaluateExpression(@ast.Expr)
  TreeApplyBinary(@ast.BinOp, @token.Loc)
  TreeSelectBranch(@ast.Stmt, @ast.Stmt?)
  TreeDiscardValue
  TreeReturnValue
  TreeFinishCall(Int, @token.Loc)
}

///|
priv struct TreeExecutorFrame {
  env : Environment
  ctx : ExecContext
  work : Array[TreeExecutorWork]
  values : Array[Value]
  mut awaiting_child : Bool
  mut completed : Bool
}

///|
fn TreeExecutorFrame::TreeExecutorFrame(
  body : Array[@ast.Stmt],
  env : Environment,
  ctx : ExecContext,
) -> TreeExecutorFrame {
  {
    env,
    ctx,
    work: [TreeExecuteStatements(body.copy(), 0)],
    values: [],
    awaiting_child: false,
    completed: false,
  }
}

///|
fn TreeExecutorFrame::pop_value(
  self : TreeExecutorFrame,
  context : String,
) -> Value raise Error {
  match self.values.pop() {
    Some(value) => value
    None =>
      raise @errors.InternalError(
        message="tree executor value stack underflow while " + context,
      )
  }
}

///|
fn tree_executor_call_target_supported(expr : @ast.Expr) -> Bool {
  match expr {
    Ident(name, _) => name != "eval"
    Grouping(inner, _) => tree_executor_call_target_supported(inner)
    _ => false
  }
}

///|
fn tree_executor_expression_supported(expr : @ast.Expr) -> Bool {
  match expr {
    NumberLit(_, _, _) | Ident(_, _) => true
    Grouping(inner, _) => tree_executor_expression_supported(inner)
    Binary(op, left, right, _) =>
      (op == Add || op == Sub || op == EqEqEq) &&
      tree_executor_expression_supported(left) &&
      tree_executor_expression_supported(right)
    Call(callee, args, _) => {
      guard tree_executor_call_target_supported(callee) else { return false }
      for arg in args {
        guard tree_executor_expression_supported(arg) else { return false }
      }
      true
    }
    _ => false
  }
}

///|
fn tree_executor_statement_supported(stmt : @ast.Stmt) -> Bool {
  match stmt {
    ExprStmt(expr, _) => tree_executor_expression_supported(expr)
    Block(stmts, _) | StmtList(stmts, _) =>
      tree_executor_statements_supported(stmts)
    IfStmt(condition, then_branch, else_branch, _) => {
      let supported_else = match else_branch {
        Some(branch) => tree_executor_statement_supported(branch)
        None => true
      }
      tree_executor_expression_supported(condition) &&
      tree_executor_statement_supported(then_branch) &&
      supported_else
    }
    ReturnStmt(value, _) =>
      match value {
        Some(expr) => tree_executor_expression_supported(expr)
        None => true
      }
    _ => false
  }
}

///|
fn tree_executor_statements_supported(stmts : Array[@ast.Stmt]) -> Bool {
  for stmt in stmts {
    guard tree_executor_statement_supported(stmt) else { return false }
  }
  true
}

///|
fn tree_executor_callable(data : FuncData) -> ExecutorCallableData? {
  guard tree_executor_statements_supported(data.body) else { return None }
  let code = TreeExecutorCode(data.body)
  Some({
    name: data.name.unwrap_or(""),
    params: data.params.copy(),
    closure: data.closure,
    strict: data.strict,
    code: code as &ExecutorCode,
    rest_param: None,
    constructable: !data.is_method,
    self_name: if data.has_name_binding {
      data.name
    } else {
      None
    },
    define_arguments_object: true,
    kind: OrdinaryExecutorCallable,
  })
}

///|
impl ExecutorCode for TreeExecutorCode with fn start(self, _interp, prepared) {
  TreeExecutorFrame(self.body, prepared.environment(), prepared.context())
  as &ExecutorActivationFrame
}

///|
impl ExecutorActivationFrame for TreeExecutorFrame with fn step(self, interp) {
  if self.awaiting_child {
    raise @errors.InternalError(
      message="tree executor frame stepped while awaiting a child completion",
    )
  }
  if self.completed {
    raise @errors.InternalError(
      message="tree executor frame stepped after completion",
    )
  }
  while !self.work.is_empty() {
    let work = self.work.pop().unwrap()
    match work {
      TreeExecuteStatements(stmts, index) =>
        if index < stmts.length() {
          self.work.push(TreeExecuteStatements(stmts, index + 1))
          self.work.push(TreeExecuteStatement(stmts[index]))
        }
      TreeExecuteStatement(stmt) => {
        interp.observe_execution_step()
        match stmt {
          ExprStmt(expr, _) => {
            self.work.push(TreeDiscardValue)
            self.work.push(TreeEvaluateExpression(expr))
          }
          Block(stmts, _) | StmtList(stmts, _) =>
            self.work.push(TreeExecuteStatements(stmts, 0))
          IfStmt(condition, then_branch, else_branch, _) => {
            self.work.push(TreeSelectBranch(then_branch, else_branch))
            self.work.push(TreeEvaluateExpression(condition))
          }
          ReturnStmt(value, _) =>
            match value {
              Some(expr) => {
                self.work.push(TreeReturnValue)
                self.work.push(TreeEvaluateExpression(expr))
              }
              None => {
                self.completed = true
                return executor_activation_return(Undefined)
              }
            }
          _ =>
            raise @errors.InternalError(
              message="unsupported statement entered tree executor frame",
            )
        }
      }
      TreeEvaluateExpression(expr) => {
        interp.observe_execution_step()
        match expr {
          NumberLit(number, _, _) => self.values.push(Number(number))
          Ident(name, _) =>
            self.values.push(
              interp.eval_identifier_reference(self.ctx, name, self.env),
            )
          Grouping(inner, _) => self.work.push(TreeEvaluateExpression(inner))
          Binary(op, left, right, loc) => {
            self.work.push(TreeApplyBinary(op, loc))
            self.work.push(TreeEvaluateExpression(right))
            self.work.push(TreeEvaluateExpression(left))
          }
          Call(callee, args, loc) => {
            self.work.push(TreeFinishCall(args.length(), loc))
            for arg in args.rev_iter() {
              self.work.push(TreeEvaluateExpression(arg))
            }
            self.work.push(TreeEvaluateExpression(callee))
          }
          _ =>
            raise @errors.InternalError(
              message="unsupported expression entered tree executor frame",
            )
        }
      }
      TreeApplyBinary(op, loc) => {
        let right = self.pop_value("reading a binary right operand")
        let left = self.pop_value("reading a binary left operand")
        self.values.push(
          eval_binary_op(op, left, right, loc, interp=Some(interp)),
        )
      }
      TreeSelectBranch(then_branch, else_branch) => {
        let condition = self.pop_value("selecting an if branch")
        if is_truthy(condition) {
          self.work.push(TreeExecuteStatement(then_branch))
        } else {
          match else_branch {
            Some(branch) => self.work.push(TreeExecuteStatement(branch))
            None => ()
          }
        }
      }
      TreeDiscardValue => {
        let _ = self.pop_value("discarding an expression result")
      }
      TreeReturnValue => {
        let value = self.pop_value("returning from a function")
        self.completed = true
        return executor_activation_return(value)
      }
      TreeFinishCall(arg_count, loc) => {
        guard self.values.length() >= arg_count + 1 else {
          raise @errors.InternalError(
            message="tree executor value stack underflow while preparing a call",
          )
        }
        let base = self.values.length() - arg_count - 1
        let callee = self.values[base]
        let args = Array::makei(arg_count, i => self.values[base + i + 1])
        self.values.truncate(base)
        self.awaiting_child = true
        return executor_activation_call(callee, Undefined, args, loc)
      }
    }
  }
  self.completed = true
  executor_activation_normal(Undefined)
}

///|
impl ExecutorActivationFrame for TreeExecutorFrame with fn deliver_activation_completion(
  self,
  completion,
) {
  guard self.awaiting_child else {
    raise @errors.InternalError(
      message="tree executor completion has no pending consumer",
    )
  }
  self.awaiting_child = false
  match completion {
    ExecutorActivationCompletionNormal(value) => self.values.push(value)
    ExecutorActivationCompletionAbrupt(error) => raise error
  }
}
