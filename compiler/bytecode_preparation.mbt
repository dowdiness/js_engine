///|
// Preparation is a compiler-only product. It contains immutable names,
// declaration order, source locations, and an opaque runtime-owned activation
// proof; runtime Binding cells, mutable environments, callbacks, and
// executable AST nodes never cross this boundary.

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
  {
    effective_name: name,
    enclosing_strict,
    params: params.copy(),
    rest_param,
    body_has_use_strict: @static_semantics.has_use_strict(body),
  }
}

///|
fn prepare_bytecode_function(
  params : Array[String],
  body : Array[@ast.Stmt],
  function_declarations : Array[BytecodeFunctionDeclaration],
  signature_validation : BytecodeSignatureValidation,
) -> BytecodePreparation {
  let activation_capability = @runtime.prepare_executor_activation_capability(
    params, body,
  )
  BytecodePreparation(
    lexical_bindings=prepare_lexical_bindings(body),
    function_declarations~,
    signature_validation=Some(signature_validation),
    activation_capability~,
  )
}

///|
// Re-derive lexical facts independently at the verification boundary. This
// intentionally does not reuse the lowering accumulator: source_body is the
// authority, so a swapped/deleted/reordered preparation entry cannot verify.
fn derive_lexical_bindings_for_verification(
  stmts : Array[@ast.Stmt],
) -> Array[BytecodeLexicalBinding] {
  let bindings : Array[BytecodeLexicalBinding] = []
  for stmt in stmts {
    match stmt {
      VarDecl(LetKind, name, _, loc) =>
        bindings.push({ kind: BytecodeLet, name, loc })
      VarDecl(ConstKind, name, _, loc) =>
        bindings.push({ kind: BytecodeConst, name, loc })
      StmtList(children, _) => {
        let nested = derive_lexical_bindings_for_verification(children)
        bindings.append(nested)
      }
      _ => ()
    }
  }
  bindings
}

///|
fn bytecode_lexical_kind_name_for_verification(
  kind : BytecodeLexicalKind,
) -> String {
  match kind {
    BytecodeLet => "let"
    BytecodeConst => "const"
  }
}

///|
fn bytecode_lexical_kind_equal_for_verification(
  left : BytecodeLexicalKind,
  right : BytecodeLexicalKind,
) -> Bool {
  match (left, right) {
    (BytecodeLet, BytecodeLet) | (BytecodeConst, BytecodeConst) => true
    _ => false
  }
}

///|
fn derive_function_declarations_for_verification(
  stmts : Array[@ast.Stmt],
) -> Array[(String, Array[@ast.Stmt], @token.Loc)] {
  // Keep the source body with its declaration location. Names alone are not
  // an identity: duplicate declarations must bind to their exact child.
  let declarations : Array[(String, Array[@ast.Stmt], @token.Loc)] = []
  for stmt in stmts {
    match stmt {
      FuncDecl(name, _, body, loc, _) => declarations.push((name, body, loc))
      FuncDeclExt(name, _, _, body, loc, _) =>
        declarations.push((name, body, loc))
      StmtList(children, _) =>
        declarations.append(
          derive_function_declarations_for_verification(children),
        )
      _ => ()
    }
  }
  declarations
}

///|
fn collect_declare_function_consumers_for_verification(
  code : Array[BytecodeInstr],
) -> Array[(String, Int)] {
  let consumers : Array[(String, Int)] = []
  for instruction in code {
    match instruction {
      DeclareFunction(name, child_index) => consumers.push((name, child_index))
      _ => ()
    }
  }
  consumers
}

///|
fn bytecode_preparation_mismatch_for_verification(
  function_path : Array[Int],
  category : String,
  index : Int,
  expected : String,
  actual : String,
) -> Unit raise Error {
  raise @errors.InternalError(
    message="bytecode " +
      category +
      " mismatch at nested depth " +
      function_path.length().to_string() +
      " index " +
      index.to_string() +
      ": expected " +
      expected +
      ", got " +
      actual,
  )
}

///|
fn verify_lexical_preparation(
  function : BytecodeFunction,
  function_path : Array[Int],
) -> Unit raise Error {
  let expected = derive_lexical_bindings_for_verification(function.source_body)
  let actual = function.preparation.lexical_bindings
  if expected.length() != actual.length() {
    bytecode_preparation_mismatch_for_verification(
      function_path,
      "lexical binding count",
      -1,
      expected.length().to_string(),
      actual.length().to_string(),
    )
  }
  for index in 0..<expected.length() {
    let (expected_binding, actual_binding) = (expected[index], actual[index])
    if !bytecode_lexical_kind_equal_for_verification(
        expected_binding.kind,
        actual_binding.kind,
      ) {
      bytecode_preparation_mismatch_for_verification(
        function_path,
        "lexical binding kind",
        index,
        bytecode_lexical_kind_name_for_verification(expected_binding.kind),
        bytecode_lexical_kind_name_for_verification(actual_binding.kind),
      )
    }
    if expected_binding.name != actual_binding.name {
      bytecode_preparation_mismatch_for_verification(
        function_path,
        "lexical binding name",
        index,
        expected_binding.name,
        actual_binding.name,
      )
    }
    if expected_binding.loc != actual_binding.loc {
      bytecode_preparation_mismatch_for_verification(
        function_path,
        "lexical binding location",
        index,
        expected_binding.loc.to_string(),
        actual_binding.loc.to_string(),
      )
    }
  }
}

///|
fn verify_function_declaration_preparation(
  function : BytecodeFunction,
  function_path : Array[Int],
) -> Unit raise Error {
  let expected = derive_function_declarations_for_verification(
    function.source_body,
  )
  let actual = function.preparation.function_declarations
  let consumers = collect_declare_function_consumers_for_verification(
    function.code,
  )
  if expected.length() != actual.length() {
    bytecode_preparation_mismatch_for_verification(
      function_path,
      "function declaration preparation count",
      -1,
      expected.length().to_string(),
      actual.length().to_string(),
    )
  }
  if expected.length() != consumers.length() {
    bytecode_preparation_mismatch_for_verification(
      function_path,
      "DeclareFunction source count",
      -1,
      expected.length().to_string(),
      consumers.length().to_string(),
    )
  }
  for index in 0..<expected.length() {
    let (expected_name, expected_body, expected_loc) = expected[index]
    let actual_declaration = actual[index]
    let (consumer_name, consumer_child_index) = consumers[index]
    if expected_name != actual_declaration.name {
      bytecode_preparation_mismatch_for_verification(
        function_path,
        "function declaration name",
        index,
        expected_name,
        actual_declaration.name,
      )
    }
    if expected_name != consumer_name {
      bytecode_preparation_mismatch_for_verification(
        function_path, "DeclareFunction name", index, expected_name, consumer_name,
      )
    }
    if expected_loc != actual_declaration.loc {
      bytecode_preparation_mismatch_for_verification(
        function_path,
        "function declaration location",
        index,
        expected_loc.to_string(),
        actual_declaration.loc.to_string(),
      )
    }
    if actual_declaration.child_index != consumer_child_index {
      bytecode_preparation_mismatch_for_verification(
        function_path,
        "function declaration child index",
        index,
        consumer_child_index.to_string(),
        actual_declaration.child_index.to_string(),
      )
    }
    guard actual_declaration.child_index >= 0 &&
      actual_declaration.child_index < function.children.length() else {
      bytecode_preparation_mismatch_for_verification(
        function_path,
        "function declaration child index bounds",
        index,
        "0..<" + function.children.length().to_string(),
        actual_declaration.child_index.to_string(),
      )
    }
    let child = function.children[actual_declaration.child_index]
    guard physical_equal(child.source_body, expected_body) else {
      bytecode_preparation_mismatch_for_verification(
        function_path,
        "function declaration child source body",
        index,
        "source body at " + expected_loc.to_string(),
        "child " + actual_declaration.child_index.to_string(),
      )
    }
    match child.name {
      Some(child_name) if child_name == expected_name => ()
      Some(child_name) =>
        bytecode_preparation_mismatch_for_verification(
          function_path, "function declaration child name", index, expected_name,
          child_name,
        )
      None =>
        bytecode_preparation_mismatch_for_verification(
          function_path, "function declaration child name", index, expected_name,
          "<anonymous>",
        )
    }
  }
}

///|
fn bytecode_signature_name_for_verification(name : String?) -> String {
  match name {
    Some(name) => name
    None => "<none>"
  }
}

///|
fn bytecode_bool_for_verification(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
fn validate_current_signature_for_verification(
  function : BytecodeFunction,
  function_path : Array[Int],
) -> Unit raise Error {
  try {
    match function.rest_param {
      Some(rest_param) =>
        @runtime.validate_function_signature_ext(
          function.enclosing_strict,
          function.signature_name,
          bytecode_ext_params_from_names_for_preparation(function.params),
          Some(rest_param),
          function.source_body,
        )
      None =>
        @runtime.validate_function_signature(
          function.enclosing_strict,
          function.signature_name,
          function.params,
          function.source_body,
        )
    }
  } catch {
    _ =>
      raise @errors.InternalError(
        message="bytecode signature validation failed at nested depth " +
          function_path.length().to_string(),
      )
  }
}

///|
fn verify_signature_preparation(
  function : BytecodeFunction,
  function_path : Array[Int],
) -> Unit raise Error {
  let facts = match function.preparation.signature_validation {
    Some(facts) => facts
    None =>
      raise @errors.InternalError(
        message="bytecode function preparation was not verified at nested depth " +
          function_path.length().to_string(),
      )
  }
  if facts.effective_name != function.signature_name {
    bytecode_preparation_mismatch_for_verification(
      function_path,
      "signature effective name",
      -1,
      bytecode_signature_name_for_verification(facts.effective_name),
      bytecode_signature_name_for_verification(function.signature_name),
    )
  }
  if facts.enclosing_strict != function.enclosing_strict {
    bytecode_preparation_mismatch_for_verification(
      function_path,
      "signature enclosing strictness",
      -1,
      bytecode_bool_for_verification(facts.enclosing_strict),
      bytecode_bool_for_verification(function.enclosing_strict),
    )
  }
  if facts.params.length() != function.params.length() {
    bytecode_preparation_mismatch_for_verification(
      function_path,
      "signature parameter count",
      -1,
      facts.params.length().to_string(),
      function.params.length().to_string(),
    )
  }
  for index in 0..<facts.params.length() {
    if facts.params[index] != function.params[index] {
      bytecode_preparation_mismatch_for_verification(
        function_path,
        "signature parameter name",
        index,
        facts.params[index],
        function.params[index],
      )
    }
  }
  if facts.rest_param != function.rest_param {
    bytecode_preparation_mismatch_for_verification(
      function_path,
      "signature rest parameter",
      -1,
      bytecode_signature_name_for_verification(facts.rest_param),
      bytecode_signature_name_for_verification(function.rest_param),
    )
  }
  let source_body_has_use_strict = @static_semantics.has_use_strict(
    function.source_body,
  )
  if facts.body_has_use_strict != source_body_has_use_strict {
    bytecode_preparation_mismatch_for_verification(
      function_path,
      "signature source strictness",
      -1,
      bytecode_bool_for_verification(facts.body_has_use_strict),
      bytecode_bool_for_verification(source_body_has_use_strict),
    )
  }
  if function.body_has_use_strict != source_body_has_use_strict {
    bytecode_preparation_mismatch_for_verification(
      function_path,
      "function source strictness",
      -1,
      bytecode_bool_for_verification(source_body_has_use_strict),
      bytecode_bool_for_verification(function.body_has_use_strict),
    )
  }
  validate_current_signature_for_verification(function, function_path)
}

///|
fn verify_bytecode_preparation(
  function : BytecodeFunction,
  function_path : Array[Int],
) -> Unit raise Error {
  verify_lexical_preparation(function, function_path)
  verify_function_declaration_preparation(function, function_path)
  verify_signature_preparation(function, function_path)
  guard @runtime.verify_executor_activation_capability(
    function.params,
    function.source_body,
    function.preparation.activation_capability,
  ) else {
    raise @errors.InternalError(
      message="bytecode activation capability was not prepared from its own " +
        "source at nested depth " +
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
