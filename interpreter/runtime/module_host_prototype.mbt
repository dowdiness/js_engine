///|
// THROWAWAY: prototype/module-host-contract only. Not a supported API.

///|
fn Interpreter::prototype_binding_value(
  self : Interpreter,
  binding : @prototype_plan.Binding,
  records : Map[String, ModuleRunRecord],
) -> Value {
  match binding {
    Local(key, name) => make_module_export_cell(name, name, records[key].env)
    Default(key) => make_module_import_cell("default", records[key].exports)
    Namespace(key) => self.create_module_namespace_object(records[key].exports)
  }
}

///|
// Sync-only entry DFS: RequestedModules source order; a back edge does not
// execute its ancestor. No TLA/SCC promise/error-retry semantics are claimed.
fn Interpreter::prototype_evaluate_entry(
  self : Interpreter,
  key : String,
  records : Map[String, ModuleRunRecord],
  plans : Map[String, @prototype_plan.ModulePlan],
  visited : Map[String, Bool],
) -> Unit raise {
  guard !visited.contains(key) else { return }
  visited[key] = true
  for dependency in plans[key].dependencies {
    self.prototype_evaluate_entry(dependency, records, plans, visited)
  }
  ignore(self.evaluate_module_record(records[key]))
}

///|
// Returns live lookup, not a materialized exports snapshot. The callback owns
// Session cells only; the shared symbolic plan contains no Realm or Value.
pub fn Interpreter::prototype_instantiate_plan(
  self : Interpreter,
  entry : String,
  modules : Array[(String, Array[@ast.Stmt])],
  plan : @prototype_plan.Plan,
  phase : Ref[String],
) -> ((String) -> Value raise) raise {
  phase.val = "instantiate"
  let records : Map[String, ModuleRunRecord] = Map([])
  for (specifier, stmts) in modules {
    let record : ModuleRunRecord = {
      specifier,
      stmts,
      exports: Map([]),
      env: self.new_module_environment(),
    }
    records[specifier] = record
    self.register_module(specifier, record.exports)
  }
  for (specifier, _) in modules {
    // Existing local declaration/TDZ hoisting only, not graph resolution.
    self.instantiate_module_record(records[specifier])
  }
  let plans : Map[String, @prototype_plan.ModulePlan] = Map([])
  // Namespace construction snapshots names, so allocate every export key first.
  for module_plan in plan.modules {
    plans[module_plan.key] = module_plan
    let exports = records[module_plan.key].exports
    for (name, _) in module_plan.exports {
      if !exports.contains(name) {
        exports[name] = make_module_tdz_marker(name)
      }
    }
  }
  for module_plan in plan.modules {
    let record = records[module_plan.key]
    for (name, binding) in module_plan.exports {
      // A synthetic default is initialized by evaluation in its owning map.
      // Do not replace it with a getter pointing recursively at itself.
      guard !(binding is Default(key) &&
        key == module_plan.key &&
        name == "default") else {
        continue
      }
      record.exports[name] = self.prototype_binding_value(binding, records)
    }
  }
  for module_plan in plan.modules {
    for (name, binding) in module_plan.imports {
      records[module_plan.key].env.def(
        name,
        self.prototype_binding_value(binding, records),
        ConstBinding,
      )
    }
  }
  phase.val = "evaluate"
  self.prototype_evaluate_entry(entry, records, plans, Map([]))
  let exports = records[entry].exports
  phase.val = "ready"
  name => {
    guard module_export_map_get_public(exports, name) is Some(value) else {
      fail("missing entrypoint: " + name)
    }
    resolve_module_export_value(value)
  }
}
