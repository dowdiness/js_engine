///|
/// Object integrity abstract operations. All observable object operations go
/// through the canonical internal-method dispatchers so Proxy traps run in the
/// order required by SetIntegrityLevel / TestIntegrityLevel.

///|
priv enum IntegrityLevel {
  Sealed
  Frozen
}

///|
/// The descriptor applied by SetIntegrityLevel for one existing property.
/// Accessors have no writable attribute, so freezing only clears configurable.
fn integrity_descriptor(
  level : IntegrityLevel,
  current : PropDescriptor?,
) -> PartialDescriptor {
  match (level, current) {
    (Frozen, Some(desc)) if !desc.is_accessor =>
      {
        ..PartialDescriptor::empty(),
        writable: Some(false),
        configurable: Some(false),
      }
    _ => { ..PartialDescriptor::empty(), configurable: Some(false) }
  }
}

///|
/// Pure TestIntegrityLevel decision for one present own descriptor.
fn descriptor_has_integrity(
  level : IntegrityLevel,
  desc : PropDescriptor,
) -> Bool {
  guard !desc.configurable else { return false }
  match level {
    Frozen => desc.is_accessor || !desc.writable
    Sealed => true
  }
}

///|
/// Canonical `[[PreventExtensions]]` dispatcher used by Object integrity
/// builtins. Proxy paths invoke the trap and preserve its Boolean completion.
fn Interpreter::prevent_extensions_internal(
  self : Interpreter,
  obj : Value,
) -> Bool raise Error {
  match obj {
    Value::Proxy(proxy_data) => proxy_prevent_extensions(self, proxy_data)
    Object(data) => {
      data.extensible = false
      true
    }
    Array(data) => {
      data.extensible = false
      true
    }
    Map(_) | Set(_) | Promise(_) => true
    _ => true
  }
}

///|
/// Canonical `[[IsExtensible]]` dispatcher used by TestIntegrityLevel and
/// Object.isExtensible. Proxy paths invoke the trap.
fn Interpreter::is_extensible_internal(
  self : Interpreter,
  obj : Value,
) -> Bool raise Error {
  match obj {
    Object(data) => data.extensible
    Array(data) => data.extensible
    Value::Proxy(proxy_data) => proxy_is_extensible(self, proxy_data)
    _ => false
  }
}

///|
/// ES §7.3.15 SetIntegrityLevel.
fn Interpreter::set_integrity_level(
  self : Interpreter,
  obj : Value,
  level : IntegrityLevel,
) -> Value raise Error {
  guard is_object_value(obj) else { return obj }
  guard self.prevent_extensions_internal(obj) else {
    raise @errors.TypeError(message="Cannot prevent extensions on object")
  }
  let keys = self.own_property_keys(obj)
  for key in keys {
    let current = match level {
      Sealed => None
      Frozen =>
        match self.get_own_property(obj, key) {
          Some((desc, _)) => Some(desc)
          None => None
        }
    }
    // Frozen skips keys that disappeared after [[OwnPropertyKeys]]. Sealed
    // follows the spec and still attempts DefinePropertyOrThrow for each key.
    if level is Frozen && current is None {
      continue
    }
    let succeeded = self.define_own_property(
      obj,
      key,
      integrity_descriptor(level, current),
      @token.Loc::default(),
    )
    guard succeeded else {
      raise @errors.TypeError(message="Cannot set object integrity level")
    }
  }
  obj
}

///|
/// ES §7.3.16 TestIntegrityLevel.
fn Interpreter::test_integrity_level(
  self : Interpreter,
  obj : Value,
  level : IntegrityLevel,
) -> Value raise Error {
  guard is_object_value(obj) else { return Bool(true) }
  guard !self.is_extensible_internal(obj) else { return Bool(false) }
  let keys = self.own_property_keys(obj)
  for key in keys {
    match self.get_own_property(obj, key) {
      Some((desc, _)) if !descriptor_has_integrity(level, desc) =>
        return Bool(false)
      _ => ()
    }
  }
  Bool(true)
}

///|
/// SetIntegrityLevel(O, frozen) backing for Object.freeze (§20.1.2.6).
pub fn set_integrity_frozen(
  interp : Interpreter,
  obj : Value,
) -> Value raise Error {
  interp.set_integrity_level(obj, Frozen)
}

///|
/// SetIntegrityLevel(O, sealed) backing for Object.seal (§20.1.2.20).
pub fn set_integrity_sealed(
  interp : Interpreter,
  obj : Value,
) -> Value raise Error {
  interp.set_integrity_level(obj, Sealed)
}

///|
/// O.`[[PreventExtensions]]`() backing for Object.preventExtensions
/// (§20.1.2.17). A falsy Proxy trap result is an exceptional completion here.
pub fn object_prevent_extensions(
  interp : Interpreter,
  obj : Value,
) -> Value raise Error {
  guard is_object_value(obj) else { return obj }
  guard interp.prevent_extensions_internal(obj) else {
    raise @errors.TypeError(message="Cannot prevent extensions on object")
  }
  obj
}

///|
/// TestIntegrityLevel(O, frozen) backing for Object.isFrozen (§20.1.2.13).
pub fn test_integrity_frozen(
  interp : Interpreter,
  obj : Value,
) -> Value raise Error {
  interp.test_integrity_level(obj, Frozen)
}

///|
/// TestIntegrityLevel(O, sealed) backing for Object.isSealed (§20.1.2.15).
pub fn test_integrity_sealed(
  interp : Interpreter,
  obj : Value,
) -> Value raise Error {
  interp.test_integrity_level(obj, Sealed)
}

///|
/// O.`[[IsExtensible]]`() backing for Object.isExtensible (§20.1.2.12).
pub fn object_is_extensible(
  interp : Interpreter,
  obj : Value,
) -> Value raise Error {
  Bool(interp.is_extensible_internal(obj))
}
