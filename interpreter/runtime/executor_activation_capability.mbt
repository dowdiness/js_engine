// Immutable, runtime-owned proof facts for the exact tree activation subset.
// The classifier below is deliberately callback-free: it only inspects the
// supplied parameter names and source statements.

///|
priv struct ExecutorActivationDirectCallRequirement {
  callee : String
  argument_count : Int
}

///|
priv struct ExecutorActivationCapabilitySummary {
  parameter_count : Int
  direct_call : ExecutorActivationDirectCallRequirement?
}

///|
fn ExecutorActivationCapabilitySummary::ExecutorActivationCapabilitySummary(
  parameter_count~ : Int,
  direct_call~ : ExecutorActivationDirectCallRequirement?,
) -> ExecutorActivationCapabilitySummary {
  { parameter_count, direct_call }
}

///|
priv enum ExecutorActivationCapabilityValueProof {
  ExecutorActivationCapabilityNumber
  ExecutorActivationCapabilityBoolean
}

///|
priv struct ExecutorActivationCapabilityExpressionProof {
  value : ExecutorActivationCapabilityValueProof
  direct_call : ExecutorActivationDirectCallRequirement?
}

///|
fn ExecutorActivationCapabilityExpressionProof::ExecutorActivationCapabilityExpressionProof(
  value~ : ExecutorActivationCapabilityValueProof,
  direct_call~ : ExecutorActivationDirectCallRequirement?,
) -> ExecutorActivationCapabilityExpressionProof {
  { value, direct_call }
}

///|
priv struct ExecutorActivationCapabilityStatementProof {
  direct_call : ExecutorActivationDirectCallRequirement?
  guaranteed_return : Bool
}

///|
fn ExecutorActivationCapabilityStatementProof::ExecutorActivationCapabilityStatementProof(
  direct_call~ : ExecutorActivationDirectCallRequirement?,
  guaranteed_return~ : Bool,
) -> ExecutorActivationCapabilityStatementProof {
  { direct_call, guaranteed_return }
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
fn executor_activation_merge_direct_calls(
  left : ExecutorActivationDirectCallRequirement?,
  right : ExecutorActivationDirectCallRequirement?,
) -> ExecutorActivationDirectCallRequirement?? {
  match (left, right) {
    (Some(_), Some(_)) => None
    (Some(edge), None) => Some(Some(edge))
    (None, Some(edge)) => Some(Some(edge))
    (None, None) => Some(None)
  }
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
          direct_call=None,
        ),
      )
    Ident(name, _) if params.contains(name) =>
      Some(
        ExecutorActivationCapabilityExpressionProof(
          value=ExecutorActivationCapabilityNumber,
          direct_call=None,
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
      let direct_call = match
        executor_activation_merge_direct_calls(
          left_proof.direct_call,
          right_proof.direct_call,
        ) {
        Some(edge) => edge
        None => return None
      }
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
      Some(ExecutorActivationCapabilityExpressionProof(value~, direct_call~))
    }
    Call(callee, args, _) => {
      guard executor_activation_direct_call_target_name(callee) is Some(name) else {
        return None
      }
      guard !params.contains(name) else { return None }
      for arg in args {
        guard executor_activation_capability_expression(arg, params)
          is Some(
            { value: ExecutorActivationCapabilityNumber, direct_call: None }
          ) else {
          return None
        }
      }
      Some(
        ExecutorActivationCapabilityExpressionProof(
          value=ExecutorActivationCapabilityNumber,
          direct_call=Some({ callee: name, argument_count: args.length() }),
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
          direct_call=proof.direct_call,
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
              direct_call=None,
              guaranteed_return=false,
            ),
            false,
          )
      }
      let branch_call = match
        executor_activation_merge_direct_calls(
          then_proof.direct_call,
          else_proof.direct_call,
        ) {
        Some(edge) => edge
        None => return None
      }
      let direct_call = match
        executor_activation_merge_direct_calls(
          condition_proof.direct_call,
          branch_call,
        ) {
        Some(edge) => edge
        None => return None
      }
      Some(
        ExecutorActivationCapabilityStatementProof(
          direct_call~,
          guaranteed_return=has_else &&
            then_proof.guaranteed_return &&
            else_proof.guaranteed_return,
        ),
      )
    }
    ReturnStmt(Some(expr), _) => {
      guard executor_activation_capability_expression(expr, params)
        is Some({ value: ExecutorActivationCapabilityNumber, direct_call }) else {
        return None
      }
      Some(
        ExecutorActivationCapabilityStatementProof(
          direct_call~,
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
  let no_call : ExecutorActivationDirectCallRequirement? = None
  for stmt in stmts; direct_call = no_call, guaranteed_return = false {
    let statement_proof = match
      executor_activation_capability_statement(stmt, params) {
      Some(proof) => proof
      None => return None
    }
    let merged_call = match
      executor_activation_merge_direct_calls(
        direct_call,
        statement_proof.direct_call,
      ) {
      Some(edge) => edge
      None => return None
    }
    continue merged_call, guaranteed_return || statement_proof.guaranteed_return
  } nobreak {
    Some(
      ExecutorActivationCapabilityStatementProof(
        direct_call~,
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
    is Some({ direct_call, guaranteed_return: true }) else {
    return None
  }
  Some(
    ExecutorActivationCapabilitySummary(
      parameter_count=params.length(),
      direct_call~,
    ),
  )
}
