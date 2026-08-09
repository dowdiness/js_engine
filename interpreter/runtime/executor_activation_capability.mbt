// Immutable, runtime-owned proof facts for the exact tree activation subset.
// The classifier below is deliberately callback-free: it only inspects the
// supplied parameter names and source statements.

///|
priv enum ExecutorActivationCallTarget {
  ExecutorActivationDirectBinding(String)
  ExecutorActivationStaticOwnDataMember(String, String)
}

///|
priv struct ExecutorActivationDirectCallRequirement {
  target : ExecutorActivationCallTarget
  argument_count : Int
}

///|
fn executor_activation_call_name(
  requirement : ExecutorActivationDirectCallRequirement,
) -> String {
  match requirement.target {
    ExecutorActivationDirectBinding(name) => name
    ExecutorActivationStaticOwnDataMember(_, property) => property
  }
}

///|
priv struct ExecutorActivationCapabilitySummary {
  parameter_count : Int
  direct_calls : Array[ExecutorActivationDirectCallRequirement]
}

///|
fn ExecutorActivationCapabilitySummary::ExecutorActivationCapabilitySummary(
  parameter_count~ : Int,
  direct_calls~ : Array[ExecutorActivationDirectCallRequirement],
) -> ExecutorActivationCapabilitySummary {
  { parameter_count, direct_calls: direct_calls.copy() }
}

///|
priv enum ExecutorActivationCapabilityValueProof {
  ExecutorActivationCapabilityNumber
  ExecutorActivationCapabilityBoolean
}

///|
priv struct ExecutorActivationCapabilityExpressionProof {
  value : ExecutorActivationCapabilityValueProof
  direct_calls : Array[ExecutorActivationDirectCallRequirement]
}

///|
fn ExecutorActivationCapabilityExpressionProof::ExecutorActivationCapabilityExpressionProof(
  value~ : ExecutorActivationCapabilityValueProof,
  direct_calls~ : Array[ExecutorActivationDirectCallRequirement],
) -> ExecutorActivationCapabilityExpressionProof {
  { value, direct_calls: direct_calls.copy() }
}

///|
priv struct ExecutorActivationCapabilityStatementProof {
  direct_calls : Array[ExecutorActivationDirectCallRequirement]
  guaranteed_return : Bool
}

///|
fn ExecutorActivationCapabilityStatementProof::ExecutorActivationCapabilityStatementProof(
  direct_calls~ : Array[ExecutorActivationDirectCallRequirement],
  guaranteed_return~ : Bool,
) -> ExecutorActivationCapabilityStatementProof {
  { direct_calls: direct_calls.copy(), guaranteed_return }
}

///|
fn executor_activation_direct_call_target_name(expr : @ast.Expr) -> String? {
  match expr {
    Ident(name, _) if name != "eval" => Some(name)
    Grouping(inner, _) => executor_activation_direct_call_target_name(inner)
    _ => None
  }
}

///|
fn executor_activation_call_requirement(
  expr : @ast.Expr,
  argument_count : Int,
) -> ExecutorActivationDirectCallRequirement? {
  match executor_activation_direct_call_target_name(expr) {
    Some(name) =>
      return Some({
        target: ExecutorActivationDirectBinding(name),
        argument_count,
      })
    None => ()
  }
  match expr {
    Member(Ident(receiver, _), property, _) =>
      Some({
        target: ExecutorActivationStaticOwnDataMember(receiver, property),
        argument_count,
      })
    Grouping(inner, _) =>
      executor_activation_call_requirement(inner, argument_count)
    _ => None
  }
}

///|
fn executor_activation_merge_direct_calls(
  left : Array[ExecutorActivationDirectCallRequirement],
  right : Array[ExecutorActivationDirectCallRequirement],
) -> Array[ExecutorActivationDirectCallRequirement] {
  let merged = left.copy()
  merged.append(right)
  merged
}

///|
fn executor_activation_capability_expression(
  expr : @ast.Expr,
  params : Array[String],
) -> ExecutorActivationCapabilityExpressionProof? {
  match expr {
    NumberLit(_, _, _) =>
      Some(
        ExecutorActivationCapabilityExpressionProof(
          value=ExecutorActivationCapabilityNumber,
          direct_calls=[],
        ),
      )
    Ident(name, _) if params.contains(name) =>
      Some(
        ExecutorActivationCapabilityExpressionProof(
          value=ExecutorActivationCapabilityNumber,
          direct_calls=[],
        ),
      )
    Grouping(inner, _) =>
      executor_activation_capability_expression(inner, params)
    Binary(op, left, right, _) => {
      let left_proof = match
        executor_activation_capability_expression(left, params) {
        Some(proof) => proof
        None => return None
      }
      let right_proof = match
        executor_activation_capability_expression(right, params) {
        Some(proof) => proof
        None => return None
      }
      let direct_calls = executor_activation_merge_direct_calls(
        left_proof.direct_calls,
        right_proof.direct_calls,
      )
      let value = match (op, left_proof.value, right_proof.value) {
        (
          Add
          | Sub,
          ExecutorActivationCapabilityNumber,
          ExecutorActivationCapabilityNumber,
        ) => ExecutorActivationCapabilityNumber
        (
          EqEqEq,
          ExecutorActivationCapabilityNumber,
          ExecutorActivationCapabilityNumber,
        ) => ExecutorActivationCapabilityBoolean
        _ => return None
      }
      Some(ExecutorActivationCapabilityExpressionProof(value~, direct_calls~))
    }
    Call(callee, args, _) => {
      guard executor_activation_call_requirement(callee, args.length())
        is Some(requirement) else {
        return None
      }
      match requirement.target {
        ExecutorActivationDirectBinding(name) =>
          if params.contains(name) {
            return None
          }
        ExecutorActivationStaticOwnDataMember(receiver, _) =>
          if params.contains(receiver) {
            return None
          }
      }
      let direct_calls : Array[ExecutorActivationDirectCallRequirement] = []
      for arg in args {
        let argument_proof = match
          executor_activation_capability_expression(arg, params) {
          Some(proof) => proof
          None => return None
        }
        guard argument_proof.value is ExecutorActivationCapabilityNumber else {
          return None
        }
        direct_calls.append(argument_proof.direct_calls)
      }
      direct_calls.push(requirement)
      Some(
        ExecutorActivationCapabilityExpressionProof(
          value=ExecutorActivationCapabilityNumber,
          direct_calls~,
        ),
      )
    }
    _ => None
  }
}

///|
fn executor_activation_capability_statement(
  stmt : @ast.Stmt,
  params : Array[String],
) -> ExecutorActivationCapabilityStatementProof? {
  match stmt {
    Block(stmts, _) | StmtList(stmts, _) =>
      executor_activation_capability_statements(stmts, params)
    ExprStmt(expr, _) => {
      let proof = match
        executor_activation_capability_expression(expr, params) {
        Some(proof) => proof
        None => return None
      }
      Some(
        ExecutorActivationCapabilityStatementProof(
          direct_calls=proof.direct_calls,
          guaranteed_return=false,
        ),
      )
    }
    IfStmt(condition, then_branch, else_branch, _) => {
      let condition_proof = match
        executor_activation_capability_expression(condition, params) {
        Some(proof) => proof
        None => return None
      }
      let then_proof = match
        executor_activation_capability_statement(then_branch, params) {
        Some(proof) => proof
        None => return None
      }
      let (else_proof, has_else) = match else_branch {
        Some(branch) =>
          match executor_activation_capability_statement(branch, params) {
            Some(proof) => (proof, true)
            None => return None
          }
        None =>
          (
            ExecutorActivationCapabilityStatementProof(
              direct_calls=[],
              guaranteed_return=false,
            ),
            false,
          )
      }
      let branch_calls = executor_activation_merge_direct_calls(
        then_proof.direct_calls,
        else_proof.direct_calls,
      )
      let direct_calls = executor_activation_merge_direct_calls(
        condition_proof.direct_calls,
        branch_calls,
      )
      Some(
        ExecutorActivationCapabilityStatementProof(
          direct_calls~,
          guaranteed_return=has_else &&
            then_proof.guaranteed_return &&
            else_proof.guaranteed_return,
        ),
      )
    }
    ReturnStmt(Some(expr), _) => {
      guard executor_activation_capability_expression(expr, params)
        is Some({ value: ExecutorActivationCapabilityNumber, direct_calls }) else {
        return None
      }
      Some(
        ExecutorActivationCapabilityStatementProof(
          direct_calls~,
          guaranteed_return=true,
        ),
      )
    }
    _ => None
  }
}

///|
fn executor_activation_capability_statements(
  stmts : Array[@ast.Stmt],
  params : Array[String],
) -> ExecutorActivationCapabilityStatementProof? {
  for stmt in stmts; direct_calls = [], guaranteed_return = false {
    let statement_proof = match
      executor_activation_capability_statement(stmt, params) {
      Some(proof) => proof
      None => return None
    }
    let merged_calls = executor_activation_merge_direct_calls(
      direct_calls,
      statement_proof.direct_calls,
    )
    continue merged_calls,
      guaranteed_return || statement_proof.guaranteed_return
  } nobreak {
    Some(
      ExecutorActivationCapabilityStatementProof(
        direct_calls~,
        guaranteed_return~,
      ),
    )
  }
}

///|
// Classify source facts without consulting an environment or invoking any
// callback. The returned summary owns only scalars and strings.
fn executor_activation_capability_summary(
  params : Array[String],
  body : Array[@ast.Stmt],
) -> ExecutorActivationCapabilitySummary? {
  guard executor_activation_capability_statements(body, params)
    is Some({ direct_calls, guaranteed_return: true }) else {
    return None
  }
  Some(
    ExecutorActivationCapabilitySummary(
      parameter_count=params.length(),
      direct_calls~,
    ),
  )
}
