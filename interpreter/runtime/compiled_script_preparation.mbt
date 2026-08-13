///|
// Immutable root-script facts consumed by the compiled-script runtime entry.
// The constructor accepts source AST only at the lowering boundary; the value
// retained by a compiled program contains declaration facts and a settled
// early-error result, never executable source nodes.
pub struct CompiledScriptLexicalBinding {
  priv kind : BindingKind
  priv name : String
}

///|
pub fn CompiledScriptLexicalBinding::CompiledScriptLexicalBinding(
  kind~ : BindingKind,
  name~ : String,
) -> CompiledScriptLexicalBinding {
  { kind, name }
}

///|
// The settlement token is created only by source validation. Its reference
// identity binds the retained error (including its typed location data) to
// the lowering operation that produced the preparation; callers cannot forge
// a matching token by supplying an arbitrary Error value.
pub struct CompiledScriptEarlyErrorSettlement {
  priv token : Ref[Unit]
  priv error : Error?
}

///|
pub struct CompiledScriptPreparation {
  priv strict : Bool
  priv var_names : Array[String]
  priv function_names : Array[String]
  priv lexical_bindings : Array[CompiledScriptLexicalBinding]
  priv early_error_settlement : CompiledScriptEarlyErrorSettlement?
}

///|
pub fn CompiledScriptPreparation::CompiledScriptPreparation(
  strict~ : Bool,
  var_names~ : Array[String],
  function_names~ : Array[String],
  lexical_bindings~ : Array[CompiledScriptLexicalBinding],
) -> CompiledScriptPreparation {
  {
    strict,
    var_names: var_names.copy(),
    function_names: function_names.copy(),
    lexical_bindings: lexical_bindings.copy(),
    early_error_settlement: None,
  }
}

///|
// Attach the source-validation result through its opaque settlement
// capability. A general facts constructor intentionally cannot accept Error.
pub fn CompiledScriptPreparation::with_early_error_settlement(
  strict~ : Bool,
  var_names~ : Array[String],
  function_names~ : Array[String],
  lexical_bindings~ : Array[CompiledScriptLexicalBinding],
  settlement~ : CompiledScriptEarlyErrorSettlement,
) -> CompiledScriptPreparation {
  {
    strict,
    var_names: var_names.copy(),
    function_names: function_names.copy(),
    lexical_bindings: lexical_bindings.copy(),
    early_error_settlement: Some(settlement),
  }
}

///|
// Verify the immutable root setup envelope against compiler-derived facts
// without exposing its backing arrays or the runtime Binding representation.
// Early-error construction is intentionally not repeated here; it is settled
// once at lowering and carried as part of the same envelope.
pub fn compiled_script_preparation_matches(
  preparation : CompiledScriptPreparation,
  strict : Bool,
  var_names : Array[String],
  function_names : Array[String],
  lexical_bindings : Array[CompiledScriptLexicalBinding],
  expected_settlement : CompiledScriptEarlyErrorSettlement,
) -> Bool {
  let settlement_matches = match preparation.early_error_settlement {
    Some(actual) => physical_equal(actual.token, expected_settlement.token)
    None => false
  }
  if preparation.strict != strict ||
    !Array::equal(preparation.var_names, var_names) ||
    !Array::equal(preparation.function_names, function_names) ||
    preparation.lexical_bindings.length() != lexical_bindings.length() ||
    !settlement_matches {
    return false
  }
  for index in 0..<lexical_bindings.length() {
    let actual = preparation.lexical_bindings[index]
    let expected = lexical_bindings[index]
    if actual.kind != expected.kind || actual.name != expected.name {
      return false
    }
  }
  true
}

///|
// This is the only source-AST-facing operation for root compiled-script
// preparation. It captures the early-error result before finalization while
// leaving error construction and conversion to the runtime entry.
pub fn prepare_compiled_script_early_error(
  stmts : Array[@ast.Stmt],
  strict : Bool,
) -> CompiledScriptEarlyErrorSettlement {
  let error : Error? = try {
    validate_compiled_script_early_errors(stmts, strict)
    None
  } catch {
    error => Some(error)
  }
  { token: { val: () }, error }
}

///|
fn Interpreter::apply_compiled_script_preparation(
  self : Interpreter,
  preparation : CompiledScriptPreparation,
) -> Unit raise Error {
  match preparation.early_error_settlement {
    Some(settlement) =>
      match settlement.error {
        Some(error) => raise error
        None => ()
      }
    None => ()
  }
  check_global_function_declarations(self, preparation.function_names)
  check_global_var_declarations(
    self,
    preparation.function_names,
    preparation.var_names,
  )
  for name in preparation.var_names {
    self.define_compiled_binding(
      self.global,
      @ast.VarKind::VarKind,
      name,
      Value::Undefined,
      false,
    )
  }
  for binding in preparation.lexical_bindings {
    match binding.kind {
      LetBinding => self.global.def_let_tdz_if_absent(binding.name)
      ConstBinding => self.global.def_const_tdz_if_absent(binding.name)
      _ =>
        raise @errors.InternalError(
          message="compiled script preparation contains a non-lexical binding",
        )
    }
  }
}
