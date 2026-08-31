// Isolates ordinary lexical binding reads after the post-#1009 Navier-Stokes
// profile identified Environment::get_with_strict as the largest caller of
// Map[String, Binding]::get. Setup and correctness checks stay outside timing.

///|
const BINDING_READ_NAME_COUNT : Int = 64

///|
const BINDING_READ_ROUNDS : Int = 16

///|
test "isolate/runtime/binding_read" (b : @bench.T) {
  let local_env = @runtime.Environment::new()
  let child_env = @runtime.Environment::new(parent=Some(local_env))
  let names : Array[String] = []
  let slots : Array[@runtime.EnvironmentSlot] = []
  for index in 0..<BINDING_READ_NAME_COUNT {
    let name = "binding_" + index.to_string()
    names.push(name)
    local_env.def(
      name,
      @runtime.Value::Number(1.0),
      @runtime.BindingKind::VarBinding,
    )
    slots.push(local_env.resolve_slot(name).unwrap())
  }
  guard local_env.get(names[0]).to_string() == "1" else {
    abort("current-environment binding read pre-check failed")
  }
  guard child_env.get(names[0]).to_string() == "1" else {
    abort("parent-environment binding read pre-check failed")
  }
  guard slots[0].read().to_string() == "1" else {
    abort("resolved-slot binding read pre-check failed")
  }
  b.bench(name="current environment name lookup", fn() {
    try {
      let mut value = @runtime.Value::Undefined
      for _ in 0..<BINDING_READ_ROUNDS {
        for name in names {
          value = local_env.get(name)
        }
      }
      b.keep(value)
    } catch {
      _ => abort("current-environment binding read raised unexpectedly")
    }
  })
  b.bench(name="one-parent environment name lookup", fn() {
    try {
      let mut value = @runtime.Value::Undefined
      for _ in 0..<BINDING_READ_ROUNDS {
        for name in names {
          value = child_env.get(name)
        }
      }
      b.keep(value)
    } catch {
      _ => abort("parent-environment binding read raised unexpectedly")
    }
  })
  b.bench(name="resolved slot read control", fn() {
    try {
      let mut value = @runtime.Value::Undefined
      for _ in 0..<BINDING_READ_ROUNDS {
        for slot in slots {
          value = slot.read()
        }
      }
      b.keep(value)
    } catch {
      _ => abort("resolved-slot binding read raised unexpectedly")
    }
  })
}
