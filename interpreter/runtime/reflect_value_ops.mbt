///|
/// Reflect `[[Get]]` / `[[Set]]` value-path internal operations relocated from
/// `interpreter/stdlib/builtins_reflect.mbt` so that stdlib calls a runtime
/// operation instead of reaching into PropertyBag representation internals
/// (`bag.properties` / `bag.descriptors` / `bag.symbol_properties` /
/// `bag.symbol_descriptors`) for the receiver-aware get/set paths (architecture
/// redesign Stage 8, following #335 own-property-keys, #338 integrity, #339
/// keys/values/entries, #340 prototype ops, #341 Proxy revoke).
///
/// This reproduces the existing Reflect.get behavior verbatim. It is the VALUE
/// path and is intentionally distinct from #340's `prototype_ops.mbt` (the
/// prototype path); do not unify them.
///
/// Preserved-as-is (NOT "fixed" here):
/// - `reflect_get_with_receiver` reimplements receiver-aware `[[Get]]` rather
///   than routing through `Interpreter::get_property`, because `get_property`
///   uses its `obj` argument as both lookup target and receiver and has no
///   receiver parameter — routing through it would silently drop Reflect.get's
///   custom (3rd-argument) receiver. Aligning this with the internal
///   receiver-preserving walk (`get_property_from_prototype`) is a separate
///   behavior-preserving refactor, not this move.

///|
/// target receiver-aware `[[Get]]` backing for Reflect.get (§28.1.7). Argument
/// validation and the non-object TypeError check stay at the stdlib boundary;
/// this op performs the receiver-aware descriptor walk verbatim. The former
/// `try_get_with_receiver` closure's captures are threaded as parameters; its
/// body is unchanged.
pub fn reflect_get_with_receiver(
  interp : Interpreter,
  target : Value,
  key : Value,
  receiver : Value,
  loc : @token.Loc,
) -> Value raise Error {
  let key_str = match key {
    Symbol(_) => ""
    _ => key.to_string()
  }
  // Helper to find accessor descriptor and call with receiver
  fn try_get_with_receiver(obj : Value) -> Value? raise {
    match obj {
      Object(data) =>
        match key {
          Value::Symbol(sym) =>
            match data.bag.symbol_descriptors.get(sym.id) {
              Some(desc) =>
                match desc.getter {
                  Some(getter) =>
                    Some(interp.call_value(getter, receiver, [], loc))
                  None =>
                    match data.bag.symbol_properties.get(sym.id) {
                      Some(v) => Some(v)
                      None => None
                    }
                }
              None =>
                match data.bag.symbol_properties.get(sym.id) {
                  Some(v) => Some(v)
                  None => None
                }
            }
          _ =>
            match data.bag.descriptors.get(key_str) {
              Some(desc) =>
                match desc.getter {
                  Some(getter) =>
                    Some(interp.call_value(getter, receiver, [], loc))
                  None =>
                    match data.bag.properties.get(key_str) {
                      Some(v) => Some(v)
                      None => None
                    }
                }
              None =>
                match data.bag.properties.get(key_str) {
                  Some(v) => Some(v)
                  None => None
                }
            }
        }
      _ => None
    }
  }

  // Check target first
  match try_get_with_receiver(target) {
    Some(v) => v
    None => {
      // Walk prototype chain
      let mut current = match target {
        Object(data) => data.prototype
        _ => Null
      }
      while true {
        match current {
          Object(data) =>
            match try_get_with_receiver(current) {
              Some(v) => return v
              None => current = data.prototype
            }
          Null => break
          _ => break
        }
      }
      // Fall back to regular property access unconditionally.
      // Accessor getters with receiver were already handled in
      // try_get_with_receiver above; remaining cases are data reads
      // or absent properties, neither of which depends on receiver equality.
      match key {
        Symbol(_) => interp.get_computed_property(target, key, loc)
        _ => interp.get_property(target, key_str, loc)
      }
    }
  }
}
