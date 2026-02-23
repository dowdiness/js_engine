///|
pub(all) enum BindingKind {
  LetBinding
  ConstBinding
  VarBinding
} derive(Show, Eq)

///|
struct Binding {
  mut value : Value
  kind : BindingKind
  mut initialized : Bool
}

///|
pub(all) struct Environment {
  bindings : Map[String, Binding]
  parent : Environment?
  mut is_var_scope : Bool // true for function/global scopes (where var is hoisted to)
  mut with_object : Value? // For 'with' statement: the live object to proxy lookups through
}

///|
pub fn Environment::new(parent? : Environment? = None) -> Environment {
  { bindings: {}, parent, is_var_scope: false, with_object: None }
}

///|
/// Walk up the scope chain to find the nearest variable environment
/// (function or global scope where var declarations are hoisted to).
pub fn Environment::find_var_env(self : Environment) -> Environment {
  if self.is_var_scope {
    return self
  }
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
    None => self.bindings[name] = { value, kind, initialized: true }
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
  self.bindings[name] = { value: Undefined, kind, initialized: false }
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
pub fn Environment::def_builtin(
  self : Environment,
  name : String,
  value : Value,
) -> Unit {
  self.bindings[name] = { value, kind: VarBinding, initialized: true }
}

///|
pub fn Environment::has(self : Environment, name : String) -> Bool {
  // Check with_object first for 'with' statement environments
  match self.with_object {
    Some(obj) =>
      if with_object_has(obj, name) {
        return true
      }
    None => ()
  }
  match self.bindings.get(name) {
    Some(_) => true
    None =>
      match self.parent {
        Some(parent) => parent.has(name)
        None => false
      }
  }
}

///|
/// Walk up the scope chain to find a VarBinding with the given name.
/// Unlike `has`, this only matches VarBinding kind, so it won't
/// accidentally match a let/const in a parent scope.
pub fn Environment::has_var(self : Environment, name : String) -> Bool {
  match self.bindings.get(name) {
    Some(binding) =>
      if binding.kind == VarBinding {
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
/// Assign to the nearest VarBinding with the given name, skipping
/// any let/const bindings in intervening scopes. This is needed for
/// eval'd var declarations that must target the function scope's var,
/// even when a block-scoped let/const shadows the name in between.
pub fn Environment::assign_var(
  self : Environment,
  name : String,
  value : Value,
) -> Unit raise Error {
  match self.bindings.get(name) {
    Some(binding) =>
      if binding.kind == VarBinding {
        binding.value = value
      } else {
        // Skip non-var binding, look in parent
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
  // Check with_object first for 'with' statement environments
  match self.with_object {
    Some(obj) => {
      let result = with_object_get(obj, name)
      match result {
        Some(v) => return v
        None => ()
      }
    }
    None => ()
  }
  match self.bindings.get(name) {
    Some(binding) =>
      if not(binding.initialized) {
        raise @errors.ReferenceError(
          message="Cannot access '\{name}' before initialization",
        )
      } else {
        binding.value
      }
    None =>
      match self.parent {
        Some(parent) => parent.get(name)
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
  // Check with_object first for 'with' statement environments
  match self.with_object {
    Some(obj) =>
      if with_object_has(obj, name) {
        with_object_set(obj, name, value)
        return
      }
    None => ()
  }
  match self.bindings.get(name) {
    Some(binding) =>
      if not(binding.initialized) {
        raise @errors.ReferenceError(
          message="Cannot access '\{name}' before initialization",
        )
      } else if binding.kind == ConstBinding {
        raise @errors.TypeError(
          message="Assignment to constant variable '\{name}'",
        )
      } else {
        binding.value = value
      }
    None =>
      match self.parent {
        Some(parent) => parent.assign(name, value)
        None => raise @errors.ReferenceError(message="\{name} is not defined")
      }
  }
}

///|
/// Check if a property is blocked by @@unscopables on the binding object
fn is_blocked_by_unscopables(obj : Value, name : String) -> Bool {
  match obj {
    Object(data) => {
      let unscopables_sym = get_unscopables_symbol()
      // Walk prototype chain to find @@unscopables
      let mut current : Value = Object(data)
      while true {
        match current {
          Object(obj_data) => {
            match obj_data.symbol_properties.get(unscopables_sym.id) {
              Some(Object(unscopables_data)) => {
                // Check if the property name is truthy in the unscopables object
                match unscopables_data.properties.get(name) {
                  Some(v) => return is_truthy(v)
                  None => return false
                }
              }
              Some(_) => return false
              None => {
                current = obj_data.prototype
              }
            }
          }
          _ => break
        }
      }
      false
    }
    _ => false
  }
}

///|
/// Check if a with-object (or its prototype chain) has a property
fn with_object_has(obj : Value, name : String) -> Bool {
  let mut current = obj
  while true {
    match current {
      Object(data) => {
        if data.properties.contains(name) {
          // Check @@unscopables
          if is_blocked_by_unscopables(obj, name) {
            return false
          }
          return true
        }
        // Check descriptors (for accessor-only properties)
        if data.descriptors.contains(name) {
          if is_blocked_by_unscopables(obj, name) {
            return false
          }
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
fn with_object_get(obj : Value, name : String) -> Value? {
  let mut current = obj
  while true {
    match current {
      Object(data) => {
        match data.properties.get(name) {
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
fn with_object_set(obj : Value, name : String, value : Value) -> Unit {
  match obj {
    Object(data) => data.properties[name] = value
    _ => ()
  }
}

///|
/// Find the with-object for a name (walking up env chain to find a with env containing this name)
pub fn Environment::find_with_object(
  self : Environment,
  name : String
) -> Value? {
  match self.with_object {
    Some(obj) =>
      if with_object_has(obj, name) {
        return Some(obj)
      }
    None => ()
  }
  match self.parent {
    Some(parent) => parent.find_with_object(name)
    None => None
  }
}
