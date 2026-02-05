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
}

///|
pub fn Environment::new(parent? : Environment? = None) -> Environment {
  { bindings: {}, parent }
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
pub fn Environment::get(self : Environment, name : String) -> Value raise Error {
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
