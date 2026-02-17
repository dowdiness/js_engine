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
  mut with_object : Value? // For object environment records (with statement)
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
  // Object environment record: check the object first
  match self.with_object {
    Some(obj) =>
      if obj_has_property(obj, name) {
        return true
      } else {
        return match self.parent {
          Some(parent) => parent.has(name)
          None => false
        }
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
  // Object environment record: check the object first
  match self.with_object {
    Some(obj) =>
      if obj_has_property(obj, name) {
        return obj_get_property(obj, name)
      } else {
        return match self.parent {
          Some(parent) => parent.get(name)
          None =>
            raise @errors.ReferenceError(message="\{name} is not defined")
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
  // Object environment record: check the object first
  match self.with_object {
    Some(obj) =>
      if obj_has_property(obj, name) {
        obj_set_property(obj, name, value)
        return
      } else {
        match self.parent {
          Some(parent) => return parent.assign(name, value)
          None =>
            raise @errors.ReferenceError(message="\{name} is not defined")
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
/// Check if an object (or its prototype chain) has a property.
fn obj_has_property(obj : Value, name : String) -> Bool {
  let mut current = obj
  while true {
    match current {
      Object(data) => {
        if data.properties.contains(name) {
          return true
        }
        current = data.prototype
      }
      Array(data) => {
        if name == "length" {
          return true
        }
        let idx = try { @strconv.parse_int(name) } catch { _ => -1 }
        if idx >= 0 && idx < data.elements.length() {
          return true
        }
        return false
      }
      _ => return false
    }
  }
  false
}

///|
/// Get a property from an object, walking the prototype chain.
fn obj_get_property(obj : Value, name : String) -> Value {
  let mut current = obj
  while true {
    match current {
      Object(data) =>
        match data.properties.get(name) {
          Some(val) => return val
          None => current = data.prototype
        }
      Array(data) => {
        if name == "length" {
          return Number(data.elements.length().to_double())
        }
        let idx = try { @strconv.parse_int(name) } catch { _ => -1 }
        if idx >= 0 && idx < data.elements.length() {
          return data.elements[idx]
        }
        return Undefined
      }
      _ => return Undefined
    }
  }
  Undefined
}

///|
/// Set a property on an object using [[Set]] semantics.
fn obj_set_property(obj : Value, name : String, value : Value) -> Unit {
  match obj {
    Object(data) => data.properties[name] = value
    Array(data) => {
      let idx = try { @strconv.parse_int(name) } catch { _ => -1 }
      if idx >= 0 && idx < data.elements.length() {
        data.elements[idx] = value
      }
    }
    _ => ()
  }
}
