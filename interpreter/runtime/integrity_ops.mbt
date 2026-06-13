///|
/// Object integrity operations (SetIntegrityLevel / TestIntegrityLevel /
/// `[[PreventExtensions]]` / `[[IsExtensible]]`) relocated from
/// `interpreter/stdlib/builtins_object_integrity.mbt` so that stdlib calls a
/// runtime operation instead of reaching into PropertyBag / ArrayData /
/// extensibility representation internals (architecture redesign Stage 8).
///
/// These reproduce the existing Object.freeze / seal / preventExtensions /
/// isFrozen / isSealed / isExtensible behavior verbatim, including the existing
/// asymmetries: freeze/seal do not invoke proxy traps, while preventExtensions
/// and isExtensible do; and isFrozen/isSealed treat arrays through the
/// non-object fallback (vacuously true) even though freeze genuinely freezes
/// array index slots. Preserving that behavior verbatim is intentional.

///|
/// Default descriptor for a key with no own descriptor: a plain
/// writable+enumerable+configurable data property.
fn default_descriptor() -> PropDescriptor {
  {
    writable: true,
    enumerable: true,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}

///|
/// SetIntegrityLevel(frozen): force a data property non-writable and
/// non-configurable while preserving every other slot.
fn frozen_descriptor(existing : PropDescriptor?) -> PropDescriptor {
  {
    ..existing.unwrap_or(default_descriptor()),
    writable: false,
    configurable: false,
  }
}

///|
/// SetIntegrityLevel(sealed): force a property non-configurable while
/// preserving writability and every other slot.
fn sealed_descriptor(existing : PropDescriptor?) -> PropDescriptor {
  { ..existing.unwrap_or(default_descriptor()), configurable: false }
}

///|
fn freeze_string_properties(bag : PropertyBag) -> Unit {
  // Own string keys plus accessor/descriptor-only keys not in `properties`.
  let keys = [ for k, _ in bag.properties => k ]
  for k, _ in bag.descriptors {
    if !bag.properties.contains(k) {
      keys.push(k)
    }
  }
  for key in keys {
    bag.descriptors[key] = frozen_descriptor(bag.descriptors.get(key))
  }
}

///|
fn freeze_symbol_properties(bag : PropertyBag) -> Unit {
  let sym_ids = [ for id, _ in bag.symbol_properties => id ]
  for id in sym_ids {
    bag.symbol_descriptors[id] = frozen_descriptor(
      bag.symbol_descriptors.get(id),
    )
  }
}

///|
fn freeze_array_index_properties(data : ArrayData) -> Unit {
  for i in 0..<data.elements.length() {
    if !data.holes.contains(i) {
      let key = i.to_string()
      data.bag.descriptors[key] = frozen_descriptor(
        data.bag.descriptors.get(key),
      )
    }
  }
}

///|
/// SetIntegrityLevel(O, frozen) backing for Object.freeze (§20.1.2.6).
pub fn set_integrity_frozen(obj : Value) -> Value raise Error {
  match obj {
    Object(data) => {
      if data.class_name == "Module" {
        let mut has_string_export = false
        data.bag.properties.each(fn(_, _) { has_string_export = true })
        if has_string_export {
          raise @errors.TypeError(
            message="Cannot freeze module namespace object",
          )
        }
      }
      data.extensible = false
      freeze_string_properties(data.bag)
      freeze_symbol_properties(data.bag)
      obj
    }
    Array(data) => {
      data.extensible = false
      data.length_writable = false
      freeze_array_index_properties(data)
      freeze_string_properties(data.bag)
      freeze_symbol_properties(data.bag)
      obj
    }
    _ => obj
  }
}

///|
/// SetIntegrityLevel(O, sealed) backing for Object.seal (§20.1.2.20).
pub fn set_integrity_sealed(obj : Value) -> Value {
  match obj {
    Object(data) => {
      data.extensible = false
      // Seal string properties. Unlike freeze, seal iterates own *properties*
      // only — descriptor-only keys are intentionally left as-is (preserved
      // pre-existing behavior).
      let keys = [ for key, _ in data.bag.properties => key ]
      for key in keys {
        data.bag.descriptors[key] = sealed_descriptor(
          data.bag.descriptors.get(key),
        )
      }
      // Seal symbol properties
      let sym_ids = [ for id, _ in data.bag.symbol_properties => id ]
      for id in sym_ids {
        data.bag.symbol_descriptors[id] = sealed_descriptor(
          data.bag.symbol_descriptors.get(id),
        )
      }
      obj
    }
    _ => obj
  }
}

///|
/// O.`[[PreventExtensions]]`() backing for Object.preventExtensions
/// (§20.1.2.17). Invokes the proxy trap for Proxy targets.
pub fn object_prevent_extensions(
  interp : Interpreter,
  obj : Value,
) -> Value raise Error {
  match obj {
    Value::Proxy(proxy_data) => {
      let _ = proxy_prevent_extensions(interp, proxy_data)
      obj
    }
    Object(data) => {
      data.extensible = false
      obj
    }
    Array(data) => {
      data.extensible = false
      obj
    }
    _ => obj
  }
}

///|
/// TestIntegrityLevel(O, frozen) backing for Object.isFrozen (§20.1.2.13).
pub fn test_integrity_frozen(obj : Value) -> Value {
  match obj {
    Object(data) => {
      if data.extensible {
        return Value::Bool(false)
      }
      if data.class_name == "Module" {
        let mut has_string_export = false
        data.bag.properties.each(fn(_, _) { has_string_export = true })
        if has_string_export {
          return Value::Bool(false)
        }
      }
      let mut frozen = true
      data.bag.properties.each(fn(k, _v) {
        match data.bag.descriptors.get(k) {
          Some(d) => if d.writable || d.configurable { frozen = false }
          None => frozen = false // No descriptor = writable+configurable
        }
      })
      Bool(frozen)
    }
    _ => Value::Bool(true) // Non-objects are vacuously frozen
  }
}

///|
/// TestIntegrityLevel(O, sealed) backing for Object.isSealed (§20.1.2.15).
pub fn test_integrity_sealed(obj : Value) -> Value {
  match obj {
    Object(data) => {
      if data.extensible {
        return Value::Bool(false)
      }
      let mut is_sealed = true
      data.bag.properties.each(fn(k, _v) {
        match data.bag.descriptors.get(k) {
          Some(d) => if d.configurable { is_sealed = false }
          None => is_sealed = false
        }
      })
      Bool(is_sealed)
    }
    _ => Value::Bool(true)
  }
}

///|
/// O.`[[IsExtensible]]`() backing for Object.isExtensible (§20.1.2.12).
/// Invokes the proxy trap for Proxy targets.
pub fn object_is_extensible(
  interp : Interpreter,
  obj : Value,
) -> Value raise Error {
  match obj {
    Object(data) => Bool(data.extensible)
    Array(data) => Bool(data.extensible)
    Value::Proxy(proxy_data) => Bool(proxy_is_extensible(interp, proxy_data))
    _ => Value::Bool(false)
  }
}
