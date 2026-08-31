///|
fn BytecodeActivationUnsupportedReason::display_text(
  self : BytecodeActivationUnsupportedReason,
) -> String {
  match self {
    SuperPropertyAccess => "super property access"
    SuperComputedPropertyAccess => "super computed property access"
    BinaryOperation => "binary operation"
    UnaryNumericConversion => "unary numeric conversion"
    DeleteName => "delete name"
    DeleteProperty => "delete property"
    DeleteComputedProperty => "delete computed property"
    TemplateInterpolation => "template interpolation"
    UpdateName => "update name"
    UpdateLocal => "update local"
    UpdateEnvSlot => "update environment slot"
    ConditionalComputedUpdate => "conditional computed update"
    ForInEnumeration => "for-in enumeration"
    ArraySpread => "array spread"
    ArgumentSpread => "argument spread"
    ConstructSpread => "construct spread"
    ObjectPropertyKey => "object property key"
    ObjectSpread => "object spread"
    SynchronousPropertyAssignment => "synchronous property assignment"
    SynchronousComputedPropertyAssignment =>
      "synchronous computed property assignment"
    ConditionalComputedProperty => "conditional computed property"
    ComputedAssignmentRead => "computed assignment read"
    ConditionalComputedAssignment => "conditional computed assignment"
    DestructuringAssignment => "destructuring assignment"
    SuperPropertyCall => "super property call"
    SuperComputedPropertyCall => "super computed property call"
    DirectEval => "direct eval"
    ConditionalComputedCall => "conditional computed call"
  }
}

///|
fn candidate_route_path_json(path : Array[Int]) -> Json {
  Json::array(
    path.map(index => Json::number(index.to_double(), repr=index.to_string())),
  )
}

///|
fn candidate_route_name_json(name : String?) -> Json {
  match name {
    Some(name) => Json::string(name)
    None => Json::null()
  }
}

///|
fn candidate_route_plan_record(
  candidate : CandidateFunction,
  path : Array[Int],
) -> Json {
  let (executor, reason_phase, reason) = match candidate.selection {
    UseBytecode(_) => ("bytecode", Json::null(), Json::null())
    UseTreeWalker(CandidateLoweringUnsupported(unsupported)) =>
      (
        "tree",
        Json::string("lowering"),
        Json::string(unsupported.reason.display_text()),
      )
    UseTreeWalker(CandidateActivationUnsupported(unsupported)) =>
      (
        "tree",
        Json::string("activation"),
        Json::string(unsupported.reason.display_text()),
      )
  }
  Json::object({
    "path": candidate_route_path_json(path),
    "name": candidate_route_name_json(candidate.name),
    "executor": Json::string(executor),
    "reason_phase": reason_phase,
    "reason": reason,
  })
}

///|
fn candidate_route_plan_records(
  candidate : CandidateFunction,
  path : Array[Int],
) -> (Array[Json], Int, Int, Int, Int) {
  let records = [candidate_route_plan_record(candidate, path)]
  let (initial_bytecode, initial_tree, initial_lowering, initial_activation) = match
    candidate.selection {
    UseBytecode(_) => (1, 0, 0, 0)
    UseTreeWalker(CandidateLoweringUnsupported(_)) => (0, 1, 1, 0)
    UseTreeWalker(CandidateActivationUnsupported(_)) => (0, 1, 0, 1)
  }
  let mut bytecode = initial_bytecode
  let mut tree = initial_tree
  let mut lowering = initial_lowering
  let mut activation = initial_activation
  for child_index, child in candidate.children {
    let child_path = path.copy()
    child_path.push(child_index)
    let (
      child_records,
      child_bytecode,
      child_tree,
      child_lowering,
      child_activation,
    ) = candidate_route_plan_records(child, child_path)
    records.append(child_records)
    bytecode += child_bytecode
    tree += child_tree
    lowering += child_lowering
    activation += child_activation
  }
  (records, bytecode, tree, lowering, activation)
}

///|
/// Return measurement data for the verified static executor selection.
///
/// This unstable profiling projection does not describe JavaScript semantics,
/// execute JavaScript, or alter the default candidate policy. Function paths
/// are child indexes rooted at the script function.
pub fn profile_candidate_route_plan_json(
  stmts : Array[@ast.Stmt],
) -> Json raise Error {
  let program = prepare_candidate_program(stmts)
  let (records, bytecode, tree, lowering, activation) = candidate_route_plan_records(
    program.root,
    [],
  )
  Json::object({
    "schema_version": Json::number(1.0, repr="1"),
    "summary": Json::object({
      "functions": Json::number(
        records.length().to_double(),
        repr=records.length().to_string(),
      ),
      "bytecode": Json::number(bytecode.to_double(), repr=bytecode.to_string()),
      "tree": Json::number(tree.to_double(), repr=tree.to_string()),
      "lowering_unsupported": Json::number(
        lowering.to_double(),
        repr=lowering.to_string(),
      ),
      "activation_unsupported": Json::number(
        activation.to_double(),
        repr=activation.to_string(),
      ),
    }),
    "functions": Json::array(records),
  })
}
