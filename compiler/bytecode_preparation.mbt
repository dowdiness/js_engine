///|
// Preparation is a compiler-only product.  It contains immutable names,
// declaration order, and source locations; runtime Binding cells, mutable
// environments, callbacks, and executable AST nodes never cross this boundary.

///|
fn prepare_lexical_bindings(
  stmts : Array[@ast.Stmt],
) -> Array[BytecodeLexicalBinding] {
  let bindings : Array[BytecodeLexicalBinding] = []
  for stmt in stmts {
    match stmt {
      VarDecl(LetKind, name, _, loc) =>
        bindings.push({ kind: BytecodeLet, name, loc })
      VarDecl(ConstKind, name, _, loc) =>
        bindings.push({ kind: BytecodeConst, name, loc })
      StmtList(children, _) =>
        for child in prepare_lexical_bindings_from_stmt_list(children) {
          bindings.push(child)
        }
      _ => ()
    }
  }
  bindings
}

///|
fn prepare_lexical_bindings_from_stmt_list(
  stmts : Array[@ast.Stmt],
) -> Array[BytecodeLexicalBinding] {
  prepare_lexical_bindings(stmts)
}

///|
fn bytecode_ext_params_from_names_for_preparation(
  params : Array[String],
) -> Array[@ast.Param] {
  let ext_params : Array[@ast.Param] = []
  for name in params {
    ext_params.push({
      name,
      default_val: None,
      pattern: None,
      is_rest_pattern: false,
    })
  }
  ext_params
}

///|
fn prepare_function_signature(
  enclosing_strict : Bool,
  name : String?,
  params : Array[String],
  rest_param : String?,
  body : Array[@ast.Stmt],
) -> BytecodeSignatureValidation raise Error {
  match rest_param {
    Some(rest_param) =>
      @runtime.validate_function_signature_ext(
        enclosing_strict,
        name,
        bytecode_ext_params_from_names_for_preparation(params),
        Some(rest_param),
        body,
      )
    None =>
      @runtime.validate_function_signature(enclosing_strict, name, params, body)
  }
  SignatureValidated
}

///|
fn prepare_bytecode_function(
  body : Array[@ast.Stmt],
  function_declarations : Array[BytecodeFunctionDeclaration],
  signature_validation : BytecodeSignatureValidation,
) -> BytecodePreparation {
  BytecodePreparation(
    lexical_bindings=prepare_lexical_bindings(body),
    function_declarations~,
    signature_validation~,
  )
}

///|
fn verify_bytecode_preparation(
  function : BytecodeFunction,
  function_path : Array[Int],
) -> Unit raise Error {
  match function.preparation.signature_validation {
    SignatureValidated => ()
    SignaturePending =>
      raise @errors.InternalError(
        message="bytecode function preparation was not verified at nested depth " +
          function_path.length().to_string(),
      )
  }
  for declaration in function.preparation.function_declarations {
    guard declaration.child_index >= 0 &&
      declaration.child_index < function.children.length() else {
      raise @errors.InternalError(
        message="bytecode function declaration preparation child index is invalid at line " +
          declaration.loc.line.to_string(),
      )
    }
  }
  for child_index, child in function.children {
    let child_path = function_path.copy()
    child_path.push(child_index)
    verify_bytecode_preparation(child, child_path)
  }
}
