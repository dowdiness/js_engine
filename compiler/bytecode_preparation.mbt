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
  match function.header_provenance {
    None => ()
    Some(provenance) => {
      let expected = match provenance.expected_preparation {
        Some(preparation) => preparation.lexical_bindings
        None =>
          raise @errors.InternalError(
            message="bytecode child preparation snapshot is missing lexical facts",
          )
      }
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
        let (expected_binding, actual_binding) = (
          expected[index],
          actual[index],
        )
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
  }
}

///|
fn verify_function_declaration_preparation(
  function : BytecodeFunction,
  function_path : Array[Int],
  consumers : Array[(String, Int)],
) -> Unit raise Error {
  let actual = function.preparation.function_declarations
  if actual.length() != consumers.length() {
    bytecode_preparation_mismatch_for_verification(
      function_path,
      "DeclareFunction source count",
      -1,
      actual.length().to_string(),
      consumers.length().to_string(),
    )
  }
  for index in 0..<actual.length() {
    let actual_declaration = actual[index]
    let (consumer_name, consumer_child_index) = consumers[index]
    if consumer_name != actual_declaration.name {
      bytecode_preparation_mismatch_for_verification(
        function_path,
        "function declaration name",
        index,
        consumer_name,
        actual_declaration.name,
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
    guard bytecode_source_identity_equal(
      actual_declaration.source_identity,
      child.source_identity,
    ) else {
      bytecode_preparation_mismatch_for_verification(
        function_path, "function declaration source identity", index, "child source identity",
        "mismatch",
      )
    }
    match child.name {
      Some(child_name) if child_name == consumer_name => ()
      Some(child_name) =>
        bytecode_preparation_mismatch_for_verification(
          function_path, "function declaration child name", index, consumer_name,
          child_name,
        )
      None =>
        bytecode_preparation_mismatch_for_verification(
          function_path, "function declaration child name", index, consumer_name,
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
fn bytecode_signature_facts_equal(
  left : BytecodeSignatureValidation,
  right : BytecodeSignatureValidation,
) -> Bool {
  left.effective_name == right.effective_name &&
  left.enclosing_strict == right.enclosing_strict &&
  Array::equal(left.params, right.params) &&
  left.rest_param == right.rest_param &&
  left.body_has_use_strict == right.body_has_use_strict
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
  match provenance {
    Some(provenance) => {
      let expected_preparation = match provenance.expected_preparation {
        Some(preparation) => preparation
        None =>
          raise @errors.InternalError(
            message="bytecode child preparation snapshot is missing signature facts",
          )
      }
      let expected_facts = match expected_preparation.signature_validation {
        Some(facts) => facts
        None =>
          raise @errors.InternalError(
            message="bytecode child preparation snapshot has no signature facts",
          )
      }
      if facts.effective_name != provenance.signature_name ||
        facts.enclosing_strict != provenance.enclosing_strict ||
        !Array::equal(facts.params, provenance.params) ||
        facts.rest_param != provenance.rest_param ||
        !bytecode_signature_facts_equal(facts, expected_facts) {
        raise @errors.InternalError(
          message="bytecode signature provenance mismatch at nested depth " +
            function_path.length().to_string(),
        )
      }
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
  if facts.body_has_use_strict != function.body_has_use_strict {
    bytecode_preparation_mismatch_for_verification(
      function_path,
      "signature source strictness",
      -1,
      bytecode_bool_for_verification(facts.body_has_use_strict),
      bytecode_bool_for_verification(function.body_has_use_strict),
    )
  }
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
  let expected_identity = match expected_consumer {
    Some(consumer) =>
      BytecodeSourceIdentity::child(
        parent.source_identity.program_identity,
        child.source_unit,
        child.source_point_owner,
        parent.source_point_owner,
        child_index,
        consumer,
      )
    None =>
      raise @errors.InternalError(
        message="bytecode child consumer form is missing",
      )
  }
  let child_identity_matches = bytecode_source_identity_equal(
    child.source_identity,
    expected_identity,
  )
  let provenance_identity_matches = match provenance.child_source_identity {
    Some(identity) =>
      bytecode_source_identity_equal(identity, expected_identity)
    None => false
  }
  let source_text_matches = provenance.exact_source_text == child.source_text
  guard physical_equal(
      provenance.program_identity,
      parent.source_identity.program_identity,
    ) &&
    provenance.parent_source_point_owner == parent.source_point_owner &&
    provenance.child_index == child_index &&
    child_identity_matches &&
    provenance_identity_matches &&
    source_text_matches &&
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
  match function.header_provenance {
    Some(provenance) => {
      let expected_preparation = match provenance.expected_preparation {
        Some(preparation) => preparation
        None =>
          raise @errors.InternalError(
            message="bytecode child preparation snapshot is missing capability facts",
          )
      }
      let expected_capability = expected_preparation.activation_capability
      let actual_capability = function.preparation.activation_capability
      guard @runtime.executor_activation_capability_summary_equal(
        expected_capability, actual_capability,
      ) else {
        raise @errors.InternalError(
          message="bytecode activation capability provenance mismatch at nested depth " +
            function_path.length().to_string(),
        )
      }
    }
    None => ()
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
