///|
pub(all) enum BindingKind {
  LetBinding
  ConstBinding
  VarBinding
  // §9.1.1.1 CreateImmutableBinding(N, false): immutable but S=false means
  // TypeError only in strict mode; non-strict assignment is silently ignored.
  // Used for named function expression self-name bindings per §14.1.22.
  FunctionNameBinding
} derive(Debug, Eq)

///|
pub impl Show for BindingKind with fn output(self, logger) {
  Debug::to_repr(self).output(logger)
}

///|
pub(all) struct Binding {
  mut value : Value
  kind : BindingKind
  mut initialized : Bool
  // Annex B §B.3.3.3: set when this binding was created or marked eligible
  // by the Annex B block-level function extension. Runtime block-entry
  // reinit only updates bindings whose `annex_b_hoisted` is true — this
  // prevents overwriting genuine lex bindings while allowing updates to
  // params (LetBinding kind) reused by the extension.
  mut annex_b_hoisted : Bool
  // True if this binding was created as a function parameter (including
  // rest parameters). Parameters share BindingKind=LetBinding with real
  // `let` declarations, but §B.3.4 treats `var name` as non-conflicting
  // with params (so Annex B hoist may tag them), while real `let` must
  // suppress the extension. This flag is the only runtime-distinguishable
  // signal, since at tag-time both are `initialized=true`.
  is_parameter : Bool
}

///|
pub(all) struct Environment {
  bindings : Map[String, Binding]
  parent : Environment?
  mut is_var_scope : Bool // true for function/global scopes (where var is hoisted to)
  mut with_object : Value? // For 'with' statement: the live object to proxy lookups through
  mut realm_state : RealmState? // Realm that owns host-installed builtin functions.
  mut interpreter_context : Interpreter? // Interpreter explicitly threaded through this scope chain.
  /// Registry of class_names that carry [[ErrorData]] semantics.
  /// Populated by register_error_ctor / register_aggregate_error_ctor at
  /// stdlib init time; consumed by Error.isError.  Stored per-Environment so
  /// future Realm work isolates correctly.
  error_class_names : Map[String, Unit]
  /// Internal marker names used for scope metadata that must not collide with
  /// real JavaScript bindings. Static markers use a fixed key; eval-created
  /// deletable vars use `eval_deletable_var_marker(name)` per binding.
  markers : Map[String, Bool]
}

///|
const EVAL_DELETABLE_VAR_PREFIX = "[[EvalDeletableVar]]:"

///|
fn eval_deletable_var_marker(name : String) -> String {
  EVAL_DELETABLE_VAR_PREFIX + name
}

///|
const EVAL_FUNCTION_RECONCILE_MARKER = "[[EvalFunctionReconcile]]"

///|
const THIS_INITIALIZED_BY_SUPER_MARKER = "[[ThisInitializedBySuper]]"

///|
pub fn Environment::new(parent? : Environment? = None) -> Environment {
  let (realm_state, interpreter_context) = match parent {
    Some(parent) => (parent.realm_state, parent.interpreter_context)
    None => (None, None)
  }
  {
    bindings: {},
    parent,
    is_var_scope: false,
    with_object: None,
    realm_state,
    interpreter_context,
    error_class_names: {},
    markers: {},
  }
}

///|
fn Environment::set_marker(self : Environment, name : String) -> Unit {
  self.markers[name] = true
}

///|
fn Environment::has_marker(self : Environment, name : String) -> Bool {
  self.markers.contains(name)
}

///|
fn Environment::has_marker_in_chain(self : Environment, name : String) -> Bool {
  if self.markers.contains(name) {
    true
  } else {
    match self.parent {
      Some(parent) => parent.has_marker_in_chain(name)
      None => false
    }
  }
}

///|
/// Walk up the scope chain to find the nearest variable environment
/// (function or global scope where var declarations are hoisted to).
pub fn Environment::find_var_env(self : Environment) -> Environment {
  guard !self.is_var_scope else { return self }
  match self.parent {
    Some(parent) => parent.find_var_env()
    None => self // Global scope (no parent) is always a variable scope
  }
}

///|
pub fn Environment::def(
  self : Environment,
  name : String,
  value : Value,
  kind : BindingKind,
) -> Unit raise Error {
  match self.bindings.get(name) {
    Some(existing) =>
      // var can redeclare var, but nothing else can redeclare
      if kind == VarBinding && existing.kind == VarBinding {
        // Allow var/var redeclaration - just update the value
        existing.value = value
      } else {
        raise @errors.SyntaxError(
          message="Identifier '\{name}' has already been declared",
        )
      }
    None =>
      self.bindings[name] = {
        value,
        kind,
        initialized: true,
        annex_b_hoisted: false,
        is_parameter: false,
      }
  }
}

///|
/// Define a function parameter binding. Parameters are stored as
/// `LetBinding` with `is_parameter: true` so the Annex B block-level
/// function extension can distinguish them from real `let` declarations.
pub fn Environment::def_parameter(
  self : Environment,
  name : String,
  value : Value,
) -> Unit raise Error {
  if self.bindings.contains(name) {
    raise @errors.SyntaxError(
      message="Identifier '\{name}' has already been declared",
    )
  }
  self.bindings[name] = {
    value,
    kind: LetBinding,
    initialized: true,
    annex_b_hoisted: false,
    is_parameter: true,
  }
}

///|
/// Define a TDZ binding (let/const before initialization)
pub fn Environment::def_tdz(
  self : Environment,
  name : String,
  kind : BindingKind,
) -> Unit raise Error {
  if self.bindings.contains(name) {
    raise @errors.SyntaxError(
      message="Identifier '\{name}' has already been declared",
    )
  }
  self.bindings[name] = {
    value: Undefined,
    kind,
    initialized: false,
    annex_b_hoisted: false,
    is_parameter: false,
  }
}

///|
/// Initialize a TDZ binding (when declaration is executed)
pub fn Environment::initialize(
  self : Environment,
  name : String,
  value : Value,
) -> Unit raise Error {
  match self.bindings.get(name) {
    Some(binding) => {
      binding.value = value
      binding.initialized = true
    }
    None =>
      raise @errors.InternalError(
        message="Cannot initialize non-existent binding '\{name}'",
      )
  }
}

///|
/// Walk the scope chain to find an existing binding for `name` and
/// initialize it with `value`. Unlike `initialize`, which only looks at
/// the local env, this climbs parents. Needed for `super()` to write
/// `this` back to the derived class's param env when body execution
/// happens in a separate body env (§10.2.11 split). For derived-constructor
/// TDZ `this`, the write follows BindThisValue and rejects a second
/// initialization.
pub fn Environment::initialize_in_chain(
  self : Environment,
  name : String,
  value : Value,
) -> Unit raise Error {
  match self.bindings.get(name) {
    Some(binding) => {
      if name == "this" {
        let initialized_by_super = self.has_marker(
          THIS_INITIALIZED_BY_SUPER_MARKER,
        )
        if binding.initialized &&
          (binding.kind == LetBinding || initialized_by_super) {
          raise @errors.ReferenceError(
            message="Super constructor may only be called once",
          )
        }
      }
      binding.value = value
      binding.initialized = true
      if name == "this" {
        self.set_marker(THIS_INITIALIZED_BY_SUPER_MARKER)
      }
    }
    None =>
      match self.parent {
        Some(parent) => parent.initialize_in_chain(name, value)
        None =>
          raise @errors.InternalError(
            message="Cannot initialize non-existent binding '\{name}' in chain",
          )
      }
  }
}

///|
pub fn Environment::def_builtin(
  self : Environment,
  name : String,
  value : Value,
) -> Unit {
  let bound_value = match self.realm_state {
    Some(realm_state) =>
      stamp_function_realm_from_state_if_unstamped(value, realm_state)
    None => value
  }
  self.bindings[name] = {
    value: bound_value,
    kind: VarBinding,
    initialized: true,
    annex_b_hoisted: false,
    is_parameter: false,
  }
}

///|
pub fn Environment::has(self : Environment, name : String) -> Bool raise Error {
  self.resolve_binding_env(name) is Some(_)
}

///|
fn Environment::resolve_binding_env(
  self : Environment,
  name : String,
) -> Environment? raise Error {
  // Check with_object first for 'with' statement environments
  match self.with_object {
    Some(obj) => {
      let has_with = with_object_has(self.interpreter_context, obj, name)
      if has_with {
        return Some(self)
      }
    }
    None => ()
  }
  match self.bindings.get(name) {
    Some(_) => Some(self)
    None =>
      match self.parent {
        Some(parent) => parent.resolve_binding_env(name)
        None => None
      }
  }
}

///|
/// Walk up the scope chain to find a var-compatible binding with the given
/// name. Formal parameters are included because sloppy function-body `var`
/// declarations may redeclare and update mapped parameter bindings.
pub fn Environment::has_var(self : Environment, name : String) -> Bool {
  match self.bindings.get(name) {
    Some(binding) =>
      if binding.kind == VarBinding || binding.is_parameter {
        true
      } else {
        // Name exists but is let/const — continue searching parent scopes
        match self.parent {
          Some(parent) => parent.has_var(name)
          None => false
        }
      }
    None =>
      match self.parent {
        Some(parent) => parent.has_var(name)
        None => false
      }
  }
}

///|
/// Assign to the nearest var-compatible binding with the given name, skipping
/// real let/const bindings in intervening scopes. This is needed for eval'd var
/// declarations that must target the function scope's var or parameter binding,
/// even when a block-scoped let/const shadows the name in between.
pub fn Environment::assign_var(
  self : Environment,
  name : String,
  value : Value,
) -> Unit raise Error {
  match self.bindings.get(name) {
    Some(binding) =>
      if binding.kind == VarBinding || binding.is_parameter {
        binding.value = value
      } else {
        // Skip real let/const binding, look in parent
        match self.parent {
          Some(parent) => parent.assign_var(name, value)
          None => raise @errors.ReferenceError(message="\{name} is not defined")
        }
      }
    None =>
      match self.parent {
        Some(parent) => parent.assign_var(name, value)
        None => raise @errors.ReferenceError(message="\{name} is not defined")
      }
  }
}

///|
pub fn Environment::get(self : Environment, name : String) -> Value raise Error {
  self.get_with_strict(name, false)
}

///|
fn Environment::get_with_strict(
  self : Environment,
  name : String,
  strict : Bool,
) -> Value raise Error {
  // Check with_object first for 'with' statement environments
  match self.with_object {
    Some(obj) => {
      let result = with_object_get(self.interpreter_context, obj, name, strict~)
      match result {
        Some(v) => return v
        None => ()
      }
    }
    None => ()
  }
  match self.bindings.get(name) {
    Some(binding) =>
      if !binding.initialized {
        raise @errors.ReferenceError(
          message="Cannot access '\{name}' before initialization",
        )
      } else {
        resolve_module_export_value(binding.value)
      }
    None =>
      match self.parent {
        Some(parent) => parent.get_with_strict(name, strict)
        None => raise @errors.ReferenceError(message="\{name} is not defined")
      }
  }
}

///|
pub fn Environment::assign(
  self : Environment,
  name : String,
  value : Value,
) -> Unit raise Error {
  self.assign_with_strict(name, value, false)
}

///|
fn Environment::assign_with_strict(
  self : Environment,
  name : String,
  value : Value,
  strict : Bool,
) -> Unit raise Error {
  // Check with_object first for 'with' statement environments
  match self.with_object {
    Some(obj) => {
      let had_own = with_object_has_own_direct(obj, name)
      if with_object_has(self.interpreter_context, obj, name) {
        match self.interpreter_context {
          Some(_) =>
            if strict && had_own && !with_object_has_own_direct(obj, name) {
              raise @errors.ReferenceError(message="\{name} is not defined")
            }
          None => ()
        }
        with_object_set(self.interpreter_context, obj, name, value, strict~)
        return
      }
    }
    None => ()
  }
  match self.bindings.get(name) {
    Some(binding) => assign_binding_value(binding, name, value, strict)
    None =>
      match self.parent {
        Some(parent) => parent.assign_with_strict(name, value, strict)
        None => raise @errors.ReferenceError(message="\{name} is not defined")
      }
  }
}

///|
fn Environment::assign_resolved(
  self : Environment,
  name : String,
  value : Value,
  strict : Bool,
) -> Unit raise Error {
  match self.with_object {
    Some(obj) => {
      match self.interpreter_context {
        Some(interp) =>
          if strict && !interp.has_property_key(obj, String_(name)) {
            raise @errors.ReferenceError(message="\{name} is not defined")
          }
        None => ()
      }
      with_object_set(self.interpreter_context, obj, name, value, strict~)
      return
    }
    None => ()
  }
  match self.bindings.get(name) {
    Some(binding) => assign_binding_value(binding, name, value, strict)
    None => raise @errors.ReferenceError(message="\{name} is not defined")
  }
}

///|
fn assign_binding_value(
  binding : Binding,
  name : String,
  value : Value,
  strict : Bool,
) -> Unit raise Error {
  if !binding.initialized {
    raise @errors.ReferenceError(
      message="Cannot access '\{name}' before initialization",
    )
  } else if binding.kind == ConstBinding {
    raise @errors.TypeError(message="Assignment to constant variable '\{name}'")
  } else if binding.kind == FunctionNameBinding {
    if strict {
      raise @errors.TypeError(
        message="Assignment to constant variable '\{name}'",
      )
    }
    // Non-strict: silently ignore per §9.1.1.1 CreateImmutableBinding(N, false)
  } else {
    binding.value = value
  }
}

///|
/// Check if a property is blocked by @@unscopables on the binding object
fn is_blocked_by_unscopables(
  interp : Interpreter,
  obj : Value,
  name : String,
) -> Bool raise Error {
  let unscopables_sym = interp.realm_state.well_known_symbols.unscopables
  let unscopables = interp.get_computed_property(
    obj,
    Symbol(unscopables_sym),
    @token.Loc::default(),
  )
  if is_object_value(unscopables) {
    is_truthy(interp.get_property(unscopables, name, @token.Loc::default()))
  } else {
    false
  }
}

///|
/// Check if a with-object (or its prototype chain) has a property
fn with_object_has(
  interp_context : Interpreter?,
  obj : Value,
  name : String,
) -> Bool raise Error {
  match interp_context {
    Some(interp) =>
      if interp.has_property_key(obj, String_(name)) {
        return !is_blocked_by_unscopables(interp, obj, name)
      } else {
        return false
      }
    None => ()
  }
  let mut current = obj
  while true {
    match current {
      Object(data) => {
        if data.bag.properties.contains(name) {
          return true
        }
        // Check descriptors (for accessor-only properties)
        if data.bag.descriptors.contains(name) {
          return true
        }
        current = data.prototype
      }
      _ => break
    }
  }
  false
}

///|
/// Get a property from a with-object (walking prototype chain)
fn with_object_has_own_direct(obj : Value, name : String) -> Bool {
  match obj {
    Object(data) =>
      data.bag.properties.contains(name) || data.bag.descriptors.contains(name)
    _ => false
  }
}

///|
fn with_object_get(
  interp_context : Interpreter?,
  obj : Value,
  name : String,
  strict? : Bool = false,
) -> Value? raise Error {
  match interp_context {
    Some(interp) => {
      // Check if the property exists (spec's HasProperty). For proxies
      // this triggers the has trap exactly once.
      let has_prop = interp.has_property_key(obj, String_(name))
      if has_prop {
        // Record own-property status BEFORE the @@unscopables getter
        // runs, since the getter may delete own properties as a side
        // effect. Use non-trapping direct-bag check for this.
        let had_own = with_object_has_own_direct(obj, name)
        if !is_blocked_by_unscopables(interp, obj, name) {
          // The property is not blocked. If the unscopables getter
          // deleted an own property, check whether the prototype
          // chain still provides it (non-proxy path).
          let still_own = with_object_has_own_direct(obj, name)
          if had_own &&
            !still_own &&
            !interp.has_property_key(obj, String_(name)) {
            return if strict {
              raise @errors.ReferenceError(message="\{name} is not defined")
            } else {
              Some(Undefined)
            }
          }
          return Some(interp.get_property(obj, name, @token.Loc::default()))
        }
      }
      return None
    }
    None => ()
  }
  let mut current = obj
  while true {
    match current {
      Object(data) => {
        match data.bag.properties.get(name) {
          Some(v) => return Some(v)
          None => ()
        }
        current = data.prototype
      }
      _ => break
    }
  }
  None
}

///|
/// Set a property on a with-object (always sets on the own object)
fn with_object_set(
  interp_context : Interpreter?,
  obj : Value,
  name : String,
  value : Value,
  strict? : Bool = false,
) -> Unit raise Error {
  match interp_context {
    Some(interp) => {
      let _ = interp.set_property(
        obj,
        name,
        value,
        @token.Loc::default(),
        strict~,
      )
      return
    }
    None => ()
  }
  match obj {
    Object(data) => data.bag.properties[name] = value
    _ => ()
  }
}

///|
/// Find the with-object for a name (walking up env chain to find a with env containing this name)
pub fn Environment::find_with_object(
  self : Environment,
  name : String,
) -> Value? raise Error {
  match self.with_object {
    Some(obj) =>
      if with_object_has(self.interpreter_context, obj, name) {
        return Some(obj)
      }
    None => ()
  }
  match self.parent {
    Some(parent) => parent.find_with_object(name)
    None => None
  }
}
