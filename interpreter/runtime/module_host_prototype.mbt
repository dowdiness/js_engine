///|
// THROWAWAY: prototype/module-host-contract only. Not a supported API.
// This is the existing run_modules orchestration with its parse step removed.
// It exposes the missing prepared-code seam without changing production paths.
// AST storage is an experimental vehicle, not a representation decision.
pub fn Interpreter::prototype_run_prepared_modules(
  self : Interpreter,
  modules : Array[(String, Array[@ast.Stmt])],
  phase : Ref[String],
) -> Map[String, Value] raise {
  phase.val = "instantiate"
  let records : Array[ModuleRunRecord] = []
  for (specifier, stmts) in modules {
    let record : ModuleRunRecord = {
      specifier,
      stmts,
      exports: Map([]),
      env: self.new_module_environment(),
    }
    records.push(record)
    self.register_module(specifier, record.exports)
  }
  for record in records {
    self.instantiate_module_record(record)
  }
  let by_specifier : Map[String, ModuleRunRecord] = Map([])
  for record in records {
    by_specifier[record.specifier] = record
  }
  let indirect_state : Map[String, Int] = Map([])
  for record in records {
    self.visit_module_dependencies_first(record, by_specifier, indirect_state, (
      interp,
      rec,
    ) => interp.instantiate_module_indirect_exports(rec, by_specifier))
  }
  for record in records {
    self.instantiate_module_imports(record)
  }
  phase.val = "evaluate"
  let evaluation_state : Map[String, Int] = Map([])
  for record in records {
    self.visit_module_dependencies_first(
      record,
      by_specifier,
      evaluation_state,
      (interp, rec) => ignore(interp.evaluate_module_record(rec)),
    )
  }
  phase.val = "materialize"
  match records.last() {
    Some(record) => self.materialize_module_record(record)
    None => Map([])
  }
}
