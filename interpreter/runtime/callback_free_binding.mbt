///|
priv enum CallbackFreeBindingSnapshot {
  CallbackFreeBindingMissing
  CallbackFreeBindingPresent(Value)
  CallbackFreeBindingUnsafe
}

///|
fn callback_free_binding_value_is_unsafe(value : Value) -> Bool {
  match value {
    Object(data) =>
      data.class_name == MODULE_NAMESPACE_CACHE_CLASS ||
      data.class_name == "ModuleTDZ" ||
      data.class_name == "ModuleExportCell"
    _ => false
  }
}

///|
fn callback_free_binding_snapshot(
  env : Environment,
  name : String,
) -> CallbackFreeBindingSnapshot {
  guard env.with_object is None else { return CallbackFreeBindingUnsafe }
  match env.bindings.get(name) {
    None => CallbackFreeBindingMissing
    Some(binding) if !binding.initialized => CallbackFreeBindingUnsafe
    Some(binding) if callback_free_binding_value_is_unsafe(binding.value) =>
      CallbackFreeBindingUnsafe
    Some(binding) => CallbackFreeBindingPresent(binding.value)
  }
}

///|
fn callback_free_binding_in_plain_chain(
  env : Environment,
  name : String,
) -> CallbackFreeBindingSnapshot {
  let mut current : Environment? = Some(env)
  while true {
    match current {
      None => return CallbackFreeBindingMissing
      Some(candidate) =>
        match callback_free_binding_snapshot(candidate, name) {
          CallbackFreeBindingMissing => current = candidate.parent
          CallbackFreeBindingPresent(value) =>
            return CallbackFreeBindingPresent(value)
          CallbackFreeBindingUnsafe => return CallbackFreeBindingUnsafe
        }
    }
  }
  CallbackFreeBindingMissing
}
