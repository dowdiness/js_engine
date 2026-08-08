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
    call_targets,
    work: [TreeExecuteStatements(body, 0)],
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
fn tree_executor_has_object_identity(
  objects : Array[ObjectData],
  candidate : ObjectData,
) -> Bool {
  for object in objects {
    if physical_equal(object, candidate) {
      return true
    }
  }
  false
}

///|
fn tree_executor_resolve_callee(closure : Environment, name : String) -> Value? {
  match callback_free_binding_in_plain_chain(closure, name) {
    CallbackFreeBindingPresent(value) => Some(value)
    CallbackFreeBindingMissing | CallbackFreeBindingUnsafe => None
  }
}

///|
priv struct TreeExecutorCallableProof {
  object_data : ObjectData
  summary : ExecutorActivationCapabilitySummary
  parameter_count : Int
  closure : Environment
}

///|
fn TreeExecutorCallableProof::TreeExecutorCallableProof(
  object_data~ : ObjectData,
  summary~ : ExecutorActivationCapabilitySummary,
  parameter_count~ : Int,
  closure~ : Environment,
) -> TreeExecutorCallableProof {
  { object_data, summary, parameter_count, closure }
}

///|
priv struct TreeExecutorResolvedDirectCall {
  callee : String
  target : Value
}

///|
priv struct TreeExecutorGraphAdmission {
  direct_call : TreeExecutorResolvedDirectCall?
}

///|
fn TreeExecutorGraphAdmission::TreeExecutorGraphAdmission(
  direct_call~ : TreeExecutorResolvedDirectCall?,
) -> TreeExecutorGraphAdmission {
  { direct_call, }
}

///|
fn tree_executor_callable_proof(callable : Value) -> TreeExecutorCallableProof? {
  guard callable is Object(object_data) else { return None }
  match object_data.callable {
    Some(UserFunc(data)) =>
      match executor_activation_capability_summary(data.params, data.body) {
        Some(summary) if summary.parameter_count == data.params.length() =>
          Some(
            TreeExecutorCallableProof(
              object_data~,
              summary~,
              parameter_count=data.params.length(),
              closure=data.closure,
            ),
          )
        _ => None
      }
    Some(ExecutorCallable(data)) =>
      match data.activation_capability_summary {
        Some(summary) if summary.parameter_count == data.params.length() =>
          Some(
            TreeExecutorCallableProof(
              object_data~,
              summary~,
              parameter_count=data.params.length(),
              closure=data.closure,
            ),
          )
        _ => None
      }
    _ => None
  }
}

///|
priv enum TreeExecutorGraphAdmissionNodeDecision {
  TreeExecutorGraphAdmissionRejected
  TreeExecutorGraphAdmissionAlreadyVisited
  TreeExecutorGraphAdmissionLeaf
  TreeExecutorGraphAdmissionFollow(ExecutorActivationDirectCallRequirement)
}

///|
fn tree_executor_graph_admission_node_decision(
  proof : TreeExecutorCallableProof,
  arg_count : Int,
  visited : Array[ObjectData],
) -> TreeExecutorGraphAdmissionNodeDecision {
  guard proof.summary.parameter_count == proof.parameter_count &&
    arg_count == proof.summary.parameter_count else {
    return TreeExecutorGraphAdmissionRejected
  }
  guard !tree_executor_has_object_identity(visited, proof.object_data) else {
    return TreeExecutorGraphAdmissionAlreadyVisited
  }
  match proof.summary.direct_call {
    None => TreeExecutorGraphAdmissionLeaf
    Some(edge) => TreeExecutorGraphAdmissionFollow(edge)
  }
}

///|
priv struct TreeExecutorGraphAdmissionWork {
  proof : TreeExecutorCallableProof
  arg_count : Int
  is_root : Bool
}

///|
fn TreeExecutorGraphAdmissionWork::TreeExecutorGraphAdmissionWork(
  proof~ : TreeExecutorCallableProof,
  arg_count~ : Int,
  is_root~ : Bool,
) -> TreeExecutorGraphAdmissionWork {
  { proof, arg_count, is_root }
}

///|
// Validate the closed callable graph without host recursion or source-AST
// inspection for an ExecutorCallable child. UserFunc children derive their
// summary once here; executor children contribute only stored proof facts.
fn tree_executor_callable_graph_admission(
  proof : TreeExecutorCallableProof,
  arg_count : Int,
) -> TreeExecutorGraphAdmission? {
  let visited : Array[ObjectData] = []
  let work = [TreeExecutorGraphAdmissionWork(proof~, arg_count~, is_root=true)]
  let mut root_direct_call : TreeExecutorResolvedDirectCall? = None
  while !work.is_empty() {
    let current = work.pop().unwrap()
    match
      tree_executor_graph_admission_node_decision(
        current.proof,
        current.arg_count,
        visited,
      ) {
      TreeExecutorGraphAdmissionRejected => return None
      TreeExecutorGraphAdmissionAlreadyVisited => ()
      TreeExecutorGraphAdmissionLeaf => visited.push(current.proof.object_data)
      TreeExecutorGraphAdmissionFollow(edge) => {
        visited.push(current.proof.object_data)
        let target = match
          tree_executor_resolve_callee(current.proof.closure, edge.callee) {
          Some(target) => target
          None => return None
        }
        let target_proof = match tree_executor_callable_proof(target) {
          Some(proof) => proof
          None => return None
        }
        if current.is_root {
          root_direct_call = Some({ callee: edge.callee, target })
        }
        work.push(
          TreeExecutorGraphAdmissionWork(
            proof=target_proof,
            arg_count=edge.argument_count,
            is_root=false,
          ),
        )
      }
    }
  }
  Some(TreeExecutorGraphAdmission(direct_call=root_direct_call))
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
  let proof = match tree_executor_callable_proof(callable) {
    Some(proof) => proof
    None => return None
  }
  let admission = match
    tree_executor_callable_graph_admission(proof, args.length()) {
    Some(admission) => admission
    None => return None
  }
  let call_targets : Map[String, Value] = Map([])
  match admission.direct_call {
    Some(edge) => call_targets[edge.callee] = edge.target
    None => ()
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
    define_arguments_object: false,
    kind: OrdinaryExecutorCallable,
    activation_capability_summary: None,
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
          ReturnStmt(Some(expr), _) => {
            self.work.push(TreeReturnValue)
            self.work.push(TreeEvaluateExpression(expr))
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
            guard executor_activation_direct_call_target_name(callee)
              is Some(name) &&
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
