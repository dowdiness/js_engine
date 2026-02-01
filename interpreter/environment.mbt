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
  if self.bindings.contains(name) {
    raise Failure::Failure("Variable '\{name}' is already declared")
  }
  self.bindings[name] = { value, kind }
}

///|
pub fn Environment::def_builtin(
  self : Environment,
  name : String,
  value : Value,
) -> Unit {
  self.bindings[name] = { value, kind: VarBinding }
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
    Some(binding) => binding.value
    None =>
      match self.parent {
        Some(parent) => parent.get(name)
        None => raise Failure::Failure("'\{name}' is not defined")
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
      if binding.kind == ConstBinding {
        raise Failure::Failure("Assignment to constant variable '\{name}'")
      } else {
        binding.value = value
      }
    None =>
      match self.parent {
        Some(parent) => parent.assign(name, value)
        None => raise Failure::Failure("'\{name}' is not defined")
      }
  }
}
