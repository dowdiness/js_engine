///|
/// Reflect `[[Get]]` / `[[Set]]` value-path internal operations relocated from
/// `interpreter/stdlib/builtins_reflect.mbt` so that stdlib calls a runtime
/// operation instead of reaching into PropertyBag representation internals
/// (`bag.properties` / `bag.descriptors` / `bag.symbol_properties` /
/// `bag.symbol_descriptors`) for the receiver-aware get/set paths (architecture
/// redesign Stage 8, following #335 own-property-keys, #338 integrity, #339
/// keys/values/entries, #340 prototype ops, #341 Proxy revoke).
///
/// These reproduce the existing Reflect.get / Reflect.set behavior verbatim.
/// They are the VALUE path and are intentionally distinct from #340's
/// `prototype_ops.mbt` (the prototype path); do not unify them.
///
/// Preserved-as-is (NOT "fixed" here):
/// - `reflect_get_with_receiver` reimplements receiver-aware `[[Get]]` rather
///   than routing through `Interpreter::get_property`, because `get_property`
///   uses its `obj` argument as both lookup target and receiver and has no
///   receiver parameter — routing through it would silently drop Reflect.get's
///   custom (3rd-argument) receiver. Aligning this with the internal
///   receiver-preserving walk (`get_property_from_prototype`) is a separate
///   behavior-preserving refactor, not this move.
/// - `reflect_set_preflight_blocks` is a TARGET-side own-descriptor check
///   (OrdinarySet §10.1.9.2 steps 1 / 3.a / 4) that Reflect.set performs before
///   delegating to `Interpreter::set_property`. It is deliberately distinct from
///   `set_property`'s internal RECEIVER-side blocker (`existing_receiver_desc_blocks`,
///   step 3.e), which uses a different predicate (any-accessor vs getter-only).
///   That Reflect.set patches `[[Set]]` externally with a target-side check
///   `set_property` does not perform internally is a latent design smell; moving
///   the check into `set_property` is behavior-changing for direct assignment and
///   is tracked as a follow-up, NOT done here.

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
  // Find an own accessor getter and call it with `receiver`; otherwise fall
  // back to the own data slot. An own descriptor whose getter is None and a
  // missing descriptor both fall through to the stored property value.
  fn try_get_with_receiver(obj : Value) -> Value? raise {
    guard obj is Object(data) else { return None }
    match key {
      Value::Symbol(sym) =>
        match data.bag.symbol_descriptors.get(sym.id) {
          Some({ getter: Some(getter), .. }) =>
            Some(interp.call_value(getter, receiver, [], loc))
          _ => data.bag.symbol_properties.get(sym.id)
        }
      _ =>
        match data.bag.descriptors.get(key_str) {
          Some({ getter: Some(getter), .. }) =>
            Some(interp.call_value(getter, receiver, [], loc))
          _ => data.bag.properties.get(key_str)
        }
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
      while current is Object(data) {
        match try_get_with_receiver(current) {
          Some(v) => return v
          None => current = data.prototype
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

///|
/// target-side own-descriptor pre-flight blocker for Reflect.set (§28.1.13 →
/// OrdinarySet §10.1.9.2 steps 1 / 3.a / 4). Returns `true` when Reflect.set
/// must short-circuit to `false` without delegating to
/// `Interpreter::set_property` (own getter-only accessor, or own non-writable
/// DATA property); `false` to proceed.
///
/// Pre-flight own-descriptor blockers (spec-safe): own accessor getter-
/// only or own non-writable DATA → return false. The former `!extensible
/// && !has(P)` short-circuits were wrong because an inherited setter can
/// still run successfully on a non-extensible target (Codex Q6).
///
/// The non-writable check requires `setter is None` alongside
/// `getter is None` — accessor descriptors default `writable=false`, so a
/// setter-only accessor (getter=None, setter=Some(_), writable=false)
/// would otherwise be preemptively rejected instead of invoking the
/// setter through the dispatcher.
///
/// Relationship to the relocated source: the stdlib method's inline
/// `return Value::Bool(false)` early-returns are consolidated here into a single
/// boolean predicate over the own descriptor (the op returns the block decision,
/// not the method's Value); the stdlib call site re-expresses the short-circuit
/// as `if reflect_set_preflight_blocks(...) { return Value::Bool(false) }`.
pub fn reflect_set_preflight_blocks(
  target : Value,
  prop_key : Value,
  key_str : String,
) -> Bool {
  guard target is Object(data) else { return false }
  let own_desc = match prop_key {
    Symbol(sym) => data.bag.symbol_descriptors.get(sym.id)
    _ => data.bag.descriptors.get(key_str)
  }
  match own_desc {
    // Own getter-only accessor, or own non-writable data descriptor → block.
    Some(desc) =>
      (desc.getter is Some(_) && desc.setter is None) ||
      (desc.getter is None && desc.setter is None && !desc.writable)
    None => false
  }
}
