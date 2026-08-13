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
priv struct BytecodeFunctionConsumerScan {
  by_child : Array[BytecodeFunctionConsumerForm?]
  declarations : Array[(String, Int)]
  invalid_index : Bool
}

///|
fn bytecode_function_consumer_for_verification(
  instruction : BytecodeInstr,
) -> (BytecodeFunctionConsumerForm, Int)? {
  match instruction {
    DeclareFunction(name, index) => Some((DeclareFunctionConsumer(name), index))
    MakeFunction(index) => Some((FunctionConsumer, index))
    MakeNamedFunction(index, name) => Some((NamedFunctionConsumer(name), index))
    MakeMethodFunction(index) => Some((MethodFunctionConsumer, index))
    MakeComputedMethodFunction(index) =>
      Some((ComputedMethodFunctionConsumer, index))
    MakeArrowFunction(index) => Some((ArrowFunctionConsumer, index))
    _ => None
  }
}

///|
fn scan_bytecode_function_consumers_for_verification(
  code : Array[BytecodeInstr],
  child_count : Int,
) -> BytecodeFunctionConsumerScan raise Error {
  let by_child : Array[BytecodeFunctionConsumerForm?] = Array::makei(
    child_count,
    _ => None,
  )
  let declarations : Array[(String, Int)] = []
  let mut invalid_index = false
  for instruction in code {
    match instruction {
      DeclareFunction(name, index) => declarations.push((name, index))
      _ => ()
    }
    match bytecode_function_consumer_for_verification(instruction) {
      Some((consumer, index)) =>
        if index < 0 || index >= child_count {
          invalid_index = true
        } else {
          match by_child[index] {
            Some(_) =>
              raise @errors.InternalError(
                message="bytecode child consumer index is duplicated",
              )
            None => by_child[index] = Some(consumer)
          }
        }
      None => ()
    }
  }
  { by_child, declarations, invalid_index }
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
  consumers : Array[(String, Int)],
) -> Unit raise Error {
  let expected = derive_function_declarations_for_verification(
    function.source_body,
  )
  let actual = function.preparation.function_declarations
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
  provenance : BytecodeHeaderProvenance?,
) -> Unit raise Error {
  let facts = match function.preparation.signature_validation {
    Some(facts) => facts
    None =>
      raise @errors.InternalError(
        message="bytecode function preparation was not verified at nested depth " +
          function_path.length().to_string(),
      )
  }
  let source_body = match provenance {
    Some(provenance) => provenance.origin_body
    None => function.source_body
  }
  let source_body_has_use_strict = @static_semantics.has_use_strict(source_body)
  match provenance {
    Some(provenance) =>
      if facts.effective_name != provenance.signature_name ||
        facts.enclosing_strict != provenance.enclosing_strict ||
        !Array::equal(facts.params, provenance.params) ||
        facts.rest_param != provenance.rest_param ||
        facts.body_has_use_strict != source_body_has_use_strict {
        raise @errors.InternalError(
          message="bytecode signature provenance mismatch at nested depth " +
            function_path.length().to_string(),
        )
      }
    None => ()
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
fn verify_bytecode_child_provenance(
  parent : BytecodeFunction,
  child : BytecodeFunction,
  child_index : Int,
  function_path : Array[Int],
  expected_consumer : BytecodeFunctionConsumerForm?,
) -> Unit raise Error {
  let provenance = match child.header_provenance {
    Some(provenance) => provenance
    None =>
      raise @errors.InternalError(
        message="bytecode child header provenance missing at nested depth " +
          function_path.length().to_string(),
      )
  }
  let parent_strict = parent.enclosing_strict || parent.body_has_use_strict
  let consumer_matches = match expected_consumer {
    Some(expected) => expected == provenance.consumer_form
    None => false
  }
  guard provenance.parent_source_point_owner == parent.source_point_owner &&
    provenance.child_index == child_index &&
    physical_equal(provenance.origin_body, child.source_body) &&
    provenance.enclosing_strict == parent_strict &&
    provenance.name == child.name &&
    consumer_matches else {
    bytecode_preparation_mismatch_for_verification(
      function_path, "child provenance", child_index, "verified", "mismatch",
    )
  }
}

///|
fn verify_bytecode_preparation(
  function : BytecodeFunction,
  function_path : Array[Int],
) -> Unit raise Error {
  let consumer_scan = scan_bytecode_function_consumers_for_verification(
    function.code,
    function.children.length(),
  )
  verify_lexical_preparation(function, function_path)
  verify_function_declaration_preparation(
    function,
    function_path,
    consumer_scan.declarations,
  )
  verify_signature_preparation(
    function,
    function_path,
    function.header_provenance,
  )
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
  if !consumer_scan.invalid_index {
    for child_index, child in function.children {
      let child_path = function_path.copy()
      child_path.push(child_index)
      match consumer_scan.by_child[child_index] {
        Some(expected) =>
          verify_bytecode_child_provenance(
            function,
            child,
            child_index,
            child_path,
            Some(expected),
          )
        None =>
          bytecode_preparation_mismatch_for_verification(
            child_path, "child consumer", child_index, "present", "missing",
          )
      }
    }
  }
  for child_index, child in function.children {
    let child_path = function_path.copy()
    child_path.push(child_index)
    verify_bytecode_preparation(child, child_path)
  }
}
