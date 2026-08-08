// Private resumable tree-walker adapter for the closed ordinary UserFunc
// subset admitted below. The executor-neutral coordinator remains the only
// owner of nested calls and activation lifecycle.

///|
priv struct TreeActivationPlan {
  body : Array[@ast.Stmt]
  call_targets : Map[String, Value]
}

///|
fn TreeActivationPlan::TreeActivationPlan(
  body : Array[@ast.Stmt],
  call_targets : Map[String, Value],
) -> TreeActivationPlan {
  { body: body.copy(), call_targets: call_targets.copy() }
}

///|
priv struct TreeExecutorCode {
  plan : TreeActivationPlan
}

///|
fn TreeExecutorCode::TreeExecutorCode(
  plan : TreeActivationPlan,
) -> TreeExecutorCode {
  { plan, }
}

///|
priv enum TreeExecutorWork {
  TreeExecuteStatements(Array[@ast.Stmt], Int)
  TreeExecuteStatement(@ast.Stmt)
  TreeEvaluateExpression(@ast.Expr)
  TreeApplyBinary(@ast.BinOp)
  TreeSelectBranch(@ast.Stmt, @ast.Stmt?)
  TreeDiscardValue
  TreeReturnValue
  TreeFinishCall(Int, @token.Loc)
}

///|
priv struct TreeExecutorFrame {
  env : Environment
  ctx : ExecContext
  call_targets : Map[String, Value]
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
  call_targets : Map[String, Value],
) -> TreeExecutorFrame {
  {
    env,
    ctx,
    call_targets: call_targets.copy(),
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
fn tree_executor_call_target_name(expr : @ast.Expr) -> String? {
  match expr {
    Ident(name, _) if name != "eval" => Some(name)
    Grouping(inner, _) => tree_executor_call_target_name(inner)
    _ => None
  }
}

///|
priv enum TreeExecutorValueProof {
  TreeExecutorNumber
  TreeExecutorBoolean
}

///|
fn tree_executor_has_object_identity(
  objects : Array[ObjectData],
  candidate : ObjectData,
) -> Bool {
  for object in objects {
    guard !physical_equal(object, candidate) else { return true }
  }
  false
}

///|
fn tree_executor_resolve_callee(closure : Environment, name : String) -> Value? {
  Some(closure.get(name)) catch {
    _ => None
  }
}

///|
fn tree_executor_expression_plan(
  expr : @ast.Expr,
  params : Array[String],
  closure : Environment,
  visiting : Array[ObjectData],
  call_count : Ref[Int],
  call_targets : Map[String, Value]?,
) -> TreeExecutorValueProof? {
  match expr {
    NumberLit(_, _, _) => Some(TreeExecutorNumber)
    Ident(name, _) if params.contains(name) => Some(TreeExecutorNumber)
    Grouping(inner, _) =>
      tree_executor_expression_plan(
        inner, params, closure, visiting, call_count, call_targets,
      )
    Binary(op, left, right, _) => {
      let left_proof = tree_executor_expression_plan(
        left, params, closure, visiting, call_count, call_targets,
      )
      let right_proof = tree_executor_expression_plan(
        right, params, closure, visiting, call_count, call_targets,
      )
      match (op, left_proof, right_proof) {
        (Add | Sub, Some(TreeExecutorNumber), Some(TreeExecutorNumber)) =>
          Some(TreeExecutorNumber)
        (EqEqEq, Some(TreeExecutorNumber), Some(TreeExecutorNumber)) =>
          Some(TreeExecutorBoolean)
        _ => None
      }
    }
    Call(callee, args, _) => {
      guard tree_executor_call_target_name(callee) is Some(name) else {
        return None
      }
      guard !params.contains(name) else { return None }
      call_count.val += 1
      guard call_count.val <= 1 else { return None }
      for arg in args {
        guard tree_executor_expression_plan(
            arg, params, closure, visiting, call_count, call_targets,
          )
          is Some(TreeExecutorNumber) else {
          return None
        }
      }
      guard tree_executor_resolve_callee(closure, name) is Some(target) else {
        return None
      }
      guard tree_executor_callable_graph_safe(target, args.length(), visiting) else {
        return None
      }
      match call_targets {
        Some(targets) => targets[name] = target
        None => ()
      }
      Some(TreeExecutorNumber)
    }
    _ => None
  }
}

///|
fn tree_executor_statement_plan(
  stmt : @ast.Stmt,
  params : Array[String],
  closure : Environment,
  visiting : Array[ObjectData],
  call_count : Ref[Int],
  call_targets : Map[String, Value]?,
) -> Bool {
  match stmt {
    Block(stmts, _) | StmtList(stmts, _) =>
      tree_executor_statements_plan(
        stmts, params, closure, visiting, call_count, call_targets,
      )
    IfStmt(condition, then_branch, else_branch, _) => {
      let supported_else = match else_branch {
        Some(branch) =>
          tree_executor_statement_plan(
            branch, params, closure, visiting, call_count, call_targets,
          )
        None => true
      }
      tree_executor_expression_plan(
        condition, params, closure, visiting, call_count, call_targets,
      )
      is Some(_) &&
      tree_executor_statement_plan(
        then_branch, params, closure, visiting, call_count, call_targets,
      ) &&
      supported_else
    }
    ReturnStmt(value, _) =>
      match value {
        Some(expr) =>
          tree_executor_expression_plan(
            expr, params, closure, visiting, call_count, call_targets,
          )
          is Some(TreeExecutorNumber)
        None => false
      }
    _ => false
  }
}

///|
fn tree_executor_statements_plan(
  stmts : Array[@ast.Stmt],
  params : Array[String],
  closure : Environment,
  visiting : Array[ObjectData],
  call_count : Ref[Int],
  call_targets : Map[String, Value]?,
) -> Bool {
  for stmt in stmts {
    guard tree_executor_statement_plan(
      stmt, params, closure, visiting, call_count, call_targets,
    ) else {
      return false
    }
  }
  true
}

///|
fn tree_executor_statement_returns(stmt : @ast.Stmt) -> Bool {
  match stmt {
    ReturnStmt(_, _) => true
    Block(stmts, _) | StmtList(stmts, _) =>
      tree_executor_statements_return(stmts)
    IfStmt(_, then_branch, Some(else_branch), _) =>
      tree_executor_statement_returns(then_branch) &&
      tree_executor_statement_returns(else_branch)
    _ => false
  }
}

///|
fn tree_executor_statements_return(stmts : Array[@ast.Stmt]) -> Bool {
  for stmt in stmts {
    guard !tree_executor_statement_returns(stmt) else { return true }
  }
  false
}

///|
fn tree_executor_callable_graph_safe(
  callable : Value,
  arg_count : Int,
  visiting : Array[ObjectData],
) -> Bool {
  guard callable is Object(object_data) else { return false }
  let (params, body, closure) = match object_data.callable {
    Some(UserFunc(data)) => (data.params, data.body, data.closure)
    Some(ExecutorCallable(data)) =>
      match data.activation_source_contract {
        Some(contract) => (data.params, contract.body, data.closure)
        None => return false
      }
    _ => return false
  }
  guard arg_count == params.length() else { return false }
  guard !tree_executor_has_object_identity(visiting, object_data) else {
    return true
  }
  let next_visiting = visiting.copy()
  next_visiting.push(object_data)
  let call_count : Ref[Int] = { val: 0 }
  tree_executor_statements_plan(
    body,
    params,
    closure,
    next_visiting,
    call_count,
    None,
  ) &&
  tree_executor_statements_return(body)
}

///|
fn tree_executor_callable(
  callable : Value,
  data : FuncData,
  args : Array[Value],
) -> ExecutorCallableData? {
  guard args.length() == data.params.length() else { return None }
  for arg in args {
    guard arg is Number(_) else { return None }
  }
  let visiting : Array[ObjectData] = match callable {
    Object(object_data) => [object_data]
    _ => return None
  }
  let call_count : Ref[Int] = { val: 0 }
  let call_targets : Map[String, Value] = Map([])
  guard tree_executor_statements_plan(
      data.body,
      data.params,
      data.closure,
      visiting,
      call_count,
      Some(call_targets),
    ) &&
    tree_executor_statements_return(data.body) else {
    return None
  }
  let code = TreeExecutorCode(TreeActivationPlan(data.body, call_targets))
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
    activation_source_contract: None,
  })
}

///|
impl ExecutorCode for TreeExecutorCode with fn start(self, _interp, prepared) {
  TreeExecutorFrame(
    self.plan.body,
    prepared.environment(),
    prepared.context(),
    self.plan.call_targets,
  )
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
          Binary(op, left, right, _) => {
            self.work.push(TreeApplyBinary(op))
            self.work.push(TreeEvaluateExpression(right))
            self.work.push(TreeEvaluateExpression(left))
          }
          Call(callee, args, loc) => {
            guard tree_executor_call_target_name(callee) is Some(name) &&
              self.call_targets.get(name) is Some(target) else {
              raise @errors.InternalError(
                message="tree executor call target was absent from its activation plan",
              )
            }
            self.work.push(TreeFinishCall(args.length(), loc))
            for arg in args.rev_iter() {
              self.work.push(TreeEvaluateExpression(arg))
            }
            self.values.push(target)
          }
          _ =>
            raise @errors.InternalError(
              message="unsupported expression entered tree executor frame",
            )
        }
      }
      TreeApplyBinary(op) => {
        let right = self.pop_value("reading a binary right operand")
        let left = self.pop_value("reading a binary left operand")
        let result = match (op, left, right) {
          (Add, Number(a), Number(b)) => Number(a + b)
          (Sub, Number(a), Number(b)) => Number(a - b)
          (EqEqEq, a, b) => Bool(strict_equal(a, b))
          _ =>
            raise @errors.InternalError(
              message="tree executor numeric proof was violated",
            )
        }
        self.values.push(result)
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
