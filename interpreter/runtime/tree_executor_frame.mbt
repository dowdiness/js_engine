// Private resumable tree-walker adapter for the closed ordinary UserFunc
// subset admitted below. The executor-neutral coordinator remains the only
// owner of nested calls and activation lifecycle.

///|
priv struct TreeExecutorPlannedCall {
  callee : Value
  this_value : Value
}

///|
fn TreeExecutorPlannedCall::TreeExecutorPlannedCall(
  callee~ : Value,
  this_value~ : Value,
) -> TreeExecutorPlannedCall {
  { callee, this_value }
}

///|
priv struct TreeActivationPlan {
  body : Array[@ast.Stmt]
  calls : Map[String, TreeExecutorPlannedCall]
}

///|
fn TreeActivationPlan::TreeActivationPlan(
  body : Array[@ast.Stmt],
  calls : Map[String, TreeExecutorPlannedCall],
) -> TreeActivationPlan {
  { body: body.copy(), calls: calls.copy() }
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
  calls : Map[String, TreeExecutorPlannedCall]
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
  calls : Map[String, TreeExecutorPlannedCall],
) -> TreeExecutorFrame {
  {
    env,
    ctx,
    calls,
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
fn tree_executor_call_key(
  requirement : ExecutorActivationDirectCallRequirement,
) -> String? {
  match requirement.target {
    ExecutorActivationDirectBinding(_) =>
      Some(executor_activation_call_name(requirement))
    ExecutorActivationStaticOwnDataMember(receiver, _) =>
      Some(receiver + "." + executor_activation_call_name(requirement))
  }
}

///|
fn tree_executor_resolve_call(
  closure : Environment,
  requirement : ExecutorActivationDirectCallRequirement,
) -> (String, Value, Value)? {
  let key = match tree_executor_call_key(requirement) {
    Some(key) => key
    None => return None
  }
  match requirement.target {
    ExecutorActivationDirectBinding(name) =>
      match tree_executor_resolve_callee(closure, name) {
        Some(target) => Some((key, target, Undefined))
        None => None
      }
    ExecutorActivationStaticOwnDataMember(receiver_name, property_name) => {
      let receiver = match
        tree_executor_resolve_callee(closure, receiver_name) {
        Some(receiver) => receiver
        None => return None
      }
      guard receiver is Object(data) &&
        data.class_name == "Object" &&
        data.callable is None &&
        data.arraybuffer_state is None &&
        data.bag.internal_slots.is_empty() &&
        data.bag.host_slots.is_empty() else {
        return None
      }
      match data.bag.descriptors.get(property_name) {
        Some(descriptor) if descriptor.is_accessor => return None
        _ => ()
      }
      match data.bag.properties.get(property_name) {
        Some(target) => Some((key, target, receiver))
        None => None
      }
    }
  }
}

///|
priv enum TreeExecutorGraphCallable {
  TreeExecutorGraphUserFunc(FuncData)
  TreeExecutorGraphExecutorCallable(ExecutorCallableData)
}

///|
fn tree_executor_graph_copy_func_data(data : FuncData) -> FuncData {
  {
    name: data.name,
    params: data.params.copy(),
    body: data.body.copy(),
    closure: data.closure,
    strict: data.strict,
    has_name_binding: data.has_name_binding,
    is_method: data.is_method,
    source_text: data.source_text,
    materializer: data.materializer,
  }
}

///|
fn tree_executor_graph_copy_capability_summary(
  summary : ExecutorActivationCapabilitySummary,
) -> ExecutorActivationCapabilitySummary {
  ExecutorActivationCapabilitySummary(
    parameter_count=summary.parameter_count,
    direct_calls=summary.direct_calls,
  )
}

///|
fn tree_executor_graph_copy_executor_data(
  data : ExecutorCallableData,
) -> ExecutorCallableData {
  let activation_capability_summary = match data.activation_capability_summary {
    Some(summary) => Some(tree_executor_graph_copy_capability_summary(summary))
    None => None
  }
  {
    name: data.name,
    params: data.params.copy(),
    closure: data.closure,
    strict: data.strict,
    code: data.code,
    rest_param: data.rest_param,
    constructable: data.constructable,
    self_name: data.self_name,
    define_arguments_object: data.define_arguments_object,
    kind: data.kind,
    activation_capability_summary,
    source_text: data.source_text,
  }
}

///|
priv struct TreeExecutorCallableProof {
  callable : TreeExecutorGraphCallable
  object_data : ObjectData
  summary : ExecutorActivationCapabilitySummary
  parameter_count : Int
  closure : Environment
}

///|
fn TreeExecutorCallableProof::TreeExecutorCallableProof(
  callable~ : TreeExecutorGraphCallable,
  object_data~ : ObjectData,
  summary~ : ExecutorActivationCapabilitySummary,
  parameter_count~ : Int,
  closure~ : Environment,
) -> TreeExecutorCallableProof {
  { callable, object_data, summary, parameter_count, closure }
}

///|
priv struct TreeExecutorGraphEdge {
  call_key : String
  target : Value
  this_value : Value
  target_object_data : ObjectData
  argument_count : Int
  target_node_index : Int
}

///|
fn TreeExecutorGraphEdge::TreeExecutorGraphEdge(
  call_key~ : String,
  target~ : Value,
  this_value~ : Value,
  target_object_data~ : ObjectData,
  argument_count~ : Int,
  target_node_index~ : Int,
) -> TreeExecutorGraphEdge {
  {
    call_key,
    target,
    this_value,
    target_object_data,
    argument_count,
    target_node_index,
  }
}

///|
priv struct TreeExecutorGraphBuildNode {
  callable : TreeExecutorGraphCallable
  object_data : ObjectData
  parameter_count : Int
  mut edges : Array[TreeExecutorGraphEdge]
}

///|
fn TreeExecutorGraphBuildNode::TreeExecutorGraphBuildNode(
  callable~ : TreeExecutorGraphCallable,
  object_data~ : ObjectData,
  parameter_count~ : Int,
) -> TreeExecutorGraphBuildNode {
  { callable, object_data, parameter_count, edges: [] }
}

///|
priv struct TreeExecutorGraphNode {
  callable : TreeExecutorGraphCallable
  object_data : ObjectData
  parameter_count : Int
  edges : Array[TreeExecutorGraphEdge]
}

///|
fn TreeExecutorGraphNode::TreeExecutorGraphNode(
  callable~ : TreeExecutorGraphCallable,
  object_data~ : ObjectData,
  parameter_count~ : Int,
  edges~ : Array[TreeExecutorGraphEdge],
) -> TreeExecutorGraphNode {
  { callable, object_data, parameter_count, edges: edges.copy() }
}

///|
priv struct TreeExecutorGraphArena {
  nodes : Array[TreeExecutorGraphNode]
}

///|
fn TreeExecutorGraphArena::TreeExecutorGraphArena(
  build_nodes : Array[TreeExecutorGraphBuildNode],
) -> TreeExecutorGraphArena {
  let nodes : Array[TreeExecutorGraphNode] = []
  for node in build_nodes {
    nodes.push(
      TreeExecutorGraphNode(
        callable=node.callable,
        object_data=node.object_data,
        parameter_count=node.parameter_count,
        edges=node.edges,
      ),
    )
  }
  { nodes, }
}

///|
priv struct TreeExecutorGraphCursor {
  arena : TreeExecutorGraphArena
  node_index : Int
}

///|
fn TreeExecutorGraphCursor::TreeExecutorGraphCursor(
  arena~ : TreeExecutorGraphArena,
  node_index~ : Int,
) -> TreeExecutorGraphCursor {
  { arena, node_index }
}

///|
priv struct TreeExecutorGraphAdmission {
  arena : TreeExecutorGraphArena
  root_node_index : Int
}

///|
fn TreeExecutorGraphAdmission::TreeExecutorGraphAdmission(
  arena~ : TreeExecutorGraphArena,
  root_node_index~ : Int,
) -> TreeExecutorGraphAdmission {
  { arena, root_node_index }
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
              callable=TreeExecutorGraphUserFunc(
                tree_executor_graph_copy_func_data(data),
              ),
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
              callable=TreeExecutorGraphExecutorCallable(
                tree_executor_graph_copy_executor_data(data),
              ),
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
  TreeExecutorGraphAdmissionFollow(
    Array[ExecutorActivationDirectCallRequirement]
  )
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
  if proof.summary.direct_calls.is_empty() {
    TreeExecutorGraphAdmissionLeaf
  } else {
    TreeExecutorGraphAdmissionFollow(proof.summary.direct_calls.copy())
  }
}

///|
priv struct TreeExecutorGraphAdmissionWork {
  proof : TreeExecutorCallableProof
  arg_count : Int
  node_index : Int
}

///|
fn TreeExecutorGraphAdmissionWork::TreeExecutorGraphAdmissionWork(
  proof~ : TreeExecutorCallableProof,
  arg_count~ : Int,
  node_index~ : Int,
) -> TreeExecutorGraphAdmissionWork {
  { proof, arg_count, node_index }
}

///|
fn tree_executor_graph_find_node(
  nodes : Array[TreeExecutorGraphBuildNode],
  object_data : ObjectData,
) -> Int? {
  for index = 0; index < nodes.length(); index = index + 1 {
    if physical_equal(nodes[index].object_data, object_data) {
      return Some(index)
    }
  }
  None
}

///|
fn tree_executor_graph_append_node(
  nodes : Array[TreeExecutorGraphBuildNode],
  scheduled : Array[Bool],
  proof : TreeExecutorCallableProof,
) -> Int {
  let node_index = nodes.length()
  nodes.push(
    TreeExecutorGraphBuildNode(
      callable=proof.callable,
      object_data=proof.object_data,
      parameter_count=proof.parameter_count,
    ),
  )
  scheduled.push(false)
  node_index
}

///|
// Validate and freeze the complete callable graph without host recursion or
// source-AST inspection for an ExecutorCallable child. UserFunc children
// derive their summary once here; executor children contribute only stored
// proof facts. The local build arrays are published only after every edge has
// resolved, validated, and received a stable node index.
fn tree_executor_callable_graph_admission(
  proof : TreeExecutorCallableProof,
  arg_count : Int,
) -> TreeExecutorGraphAdmission? {
  let visited : Array[ObjectData] = []
  let nodes : Array[TreeExecutorGraphBuildNode] = []
  let scheduled : Array[Bool] = []
  let root_node_index = tree_executor_graph_append_node(nodes, scheduled, proof)
  scheduled[root_node_index] = true
  let work = [
    TreeExecutorGraphAdmissionWork(
      proof~,
      arg_count~,
      node_index=root_node_index,
    ),
  ]
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
      TreeExecutorGraphAdmissionLeaf => {
        visited.push(current.proof.object_data)
        nodes[current.node_index].edges = []
      }
      TreeExecutorGraphAdmissionFollow(edges) => {
        visited.push(current.proof.object_data)
        let next_work : Array[TreeExecutorGraphAdmissionWork] = []
        let resolved_edges : Array[TreeExecutorGraphEdge] = []
        for edge in edges {
          let (call_key, target, this_value) = match
            tree_executor_resolve_call(current.proof.closure, edge) {
            Some(resolved) => resolved
            None => return None
          }
          let target_proof = match tree_executor_callable_proof(target) {
            Some(proof) => proof
            None => return None
          }
          guard edge.argument_count == target_proof.parameter_count else {
            return None
          }
          let target_node_index = match
            tree_executor_graph_find_node(nodes, target_proof.object_data) {
            Some(index) => {
              guard nodes[index].parameter_count == target_proof.parameter_count else {
                return None
              }
              index
            }
            None =>
              tree_executor_graph_append_node(nodes, scheduled, target_proof)
          }
          resolved_edges.push(
            TreeExecutorGraphEdge(
              call_key~,
              target~,
              this_value~,
              target_object_data=target_proof.object_data,
              argument_count=edge.argument_count,
              target_node_index~,
            ),
          )
          if !tree_executor_has_object_identity(
              visited,
              target_proof.object_data,
            ) &&
            !scheduled[target_node_index] {
            scheduled[target_node_index] = true
            next_work.push(
              TreeExecutorGraphAdmissionWork(
                proof=target_proof,
                arg_count=edge.argument_count,
                node_index=target_node_index,
              ),
            )
          }
        }
        nodes[current.node_index].edges = resolved_edges
        for next in next_work.rev_iter() {
          work.push(next)
        }
      }
    }
  }
  Some(
    TreeExecutorGraphAdmission(
      arena=TreeExecutorGraphArena(nodes),
      root_node_index~,
    ),
  )
}

///|
fn tree_executor_graph_select_edge(
  cursor : TreeExecutorGraphCursor,
  callee : Value,
  argument_count : Int,
) -> TreeExecutorGraphEdge? {
  guard callee is Object(object_data) else { return None }
  guard cursor.node_index >= 0 &&
    cursor.node_index < cursor.arena.nodes.length() else {
    return None
  }
  let node = cursor.arena.nodes[cursor.node_index]
  for edge in node.edges {
    if edge.argument_count == argument_count &&
      physical_equal(edge.target_object_data, object_data) {
      return Some(edge)
    }
  }
  None
}

///|
fn tree_executor_graph_node_executable(
  node : TreeExecutorGraphNode,
) -> ExecutorCallableData? {
  match node.callable {
    TreeExecutorGraphUserFunc(data) => {
      let calls : Map[String, TreeExecutorPlannedCall] = Map([])
      for edge in node.edges {
        calls[edge.call_key] = TreeExecutorPlannedCall(
          callee=edge.target,
          this_value=edge.this_value,
        )
      }
      let code = TreeExecutorCode(TreeActivationPlan(data.body, calls))
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
        source_text: None,
      })
    }
    TreeExecutorGraphExecutorCallable(executable) => Some(executable)
  }
}

///|
priv struct TreeExecutorAdmission {
  executable : ExecutorCallableData
  cursor : TreeExecutorGraphCursor
}

///|
fn TreeExecutorAdmission::TreeExecutorAdmission(
  executable~ : ExecutorCallableData,
  cursor~ : TreeExecutorGraphCursor,
) -> TreeExecutorAdmission {
  { executable, cursor }
}

///|
fn tree_executor_callable_admission(
  callable : Value,
  data : FuncData,
  args : Array[Value],
) -> TreeExecutorAdmission? {
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
  let cursor = TreeExecutorGraphCursor(
    arena=admission.arena,
    node_index=admission.root_node_index,
  )
  let root_node = admission.arena.nodes[admission.root_node_index]
  let executable = match tree_executor_graph_node_executable(root_node) {
    Some(executable) => executable
    None => return None
  }
  Some(TreeExecutorAdmission(executable~, cursor~))
}

///|
fn tree_executor_graph_target(
  cursor : TreeExecutorGraphCursor,
  edge : TreeExecutorGraphEdge,
) -> TreeExecutorAdmission? {
  guard edge.target_node_index >= 0 &&
    edge.target_node_index < cursor.arena.nodes.length() else {
    return None
  }
  let target_cursor = TreeExecutorGraphCursor(
    arena=cursor.arena,
    node_index=edge.target_node_index,
  )
  let target_node = cursor.arena.nodes[edge.target_node_index]
  guard physical_equal(target_node.object_data, edge.target_object_data) &&
    target_node.parameter_count == edge.argument_count else {
    return None
  }
  let executable = match tree_executor_graph_node_executable(target_node) {
    Some(executable) => executable
    None => return None
  }
  Some(TreeExecutorAdmission(executable~, cursor=target_cursor))
}

///|
impl ExecutorCode for TreeExecutorCode with fn start(self, _interp, prepared) {
  TreeExecutorFrame(
    self.plan.body,
    prepared.environment(),
    prepared.context(),
    self.plan.calls,
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
            guard executor_activation_call_requirement(callee, args.length())
              is Some(requirement) &&
              tree_executor_call_key(requirement) is Some(key) &&
              self.calls.get(key) is Some(call) else {
              raise @errors.InternalError(
                message="tree executor call target was absent from its activation plan",
              )
            }
            self.work.push(TreeFinishCall(args.length(), loc))
            for arg in args.rev_iter() {
              self.work.push(TreeEvaluateExpression(arg))
            }
            self.values.push(call.callee)
            self.values.push(call.this_value)
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
        guard self.values.length() >= arg_count + 2 else {
          raise @errors.InternalError(
            message="tree executor value stack underflow while preparing a call",
          )
        }
        let base = self.values.length() - arg_count - 2
        let callee = self.values[base]
        let this_value = self.values[base + 1]
        let args = Array::makei(arg_count, i => self.values[base + i + 2])
        self.values.truncate(base)
        self.awaiting_child = true
        return executor_activation_call(callee, this_value, args, loc)
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
    ExecutorActivationCompletionReference(_) =>
      raise @errors.InternalError(
        message="tree executor received an unexpected binding reference completion",
      )
    ExecutorActivationCompletionNormal(value) => self.values.push(value)
    ExecutorActivationCompletionAbrupt(error) => raise error
  }
}
