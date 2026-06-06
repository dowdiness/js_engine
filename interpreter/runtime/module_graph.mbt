///|
fn Interpreter::predeclare_module_export_tdz(
  self : Interpreter,
  export_name : String,
) -> Unit {
  if !self.module_exports.contains(export_name) {
    self.module_exports[export_name] = make_module_tdz_marker(export_name)
  }
}

///|
fn Interpreter::predeclare_module_export_cell(
  self : Interpreter,
  export_name : String,
  local_name : String,
  env : Environment,
) -> Unit {
  if !self.module_exports.contains(export_name) {
    self.module_exports[export_name] = make_module_export_cell(
      export_name, local_name, env,
    )
  }
}

///|
fn Interpreter::predeclare_decl_exports(
  self : Interpreter,
  decl : @ast.Stmt,
  env : Environment,
) -> Unit {
  match decl {
    VarDecl(_, name, _, _) =>
      self.predeclare_module_export_cell(name, name, env)
    FuncDecl(name, _, _, _) =>
      self.predeclare_module_export_cell(name, name, env)
    FuncDeclExt(name, _, _, _, _) =>
      self.predeclare_module_export_cell(name, name, env)
    GeneratorDecl(name, _, _, _) =>
      self.predeclare_module_export_cell(name, name, env)
    GeneratorDeclExt(name, _, _, _, _) =>
      self.predeclare_module_export_cell(name, name, env)
    AsyncFuncDecl(name, _, _, _) =>
      self.predeclare_module_export_cell(name, name, env)
    AsyncFuncDeclExt(name, _, _, _, _) =>
      self.predeclare_module_export_cell(name, name, env)
    AsyncGeneratorDecl(name, _, _, _) =>
      self.predeclare_module_export_cell(name, name, env)
    AsyncGeneratorDeclExt(name, _, _, _, _) =>
      self.predeclare_module_export_cell(name, name, env)
    ClassDecl(name, _, _, _) =>
      self.predeclare_module_export_cell(name, name, env)
    DestructureDecl(_, pattern, _, _) =>
      self.predeclare_pattern_exports(pattern, env)
    StmtList(stmts, _) =>
      for stmt in stmts {
        self.predeclare_decl_exports(stmt, env)
      }
    _ => ()
  }
}

///|
fn Interpreter::predeclare_pattern_exports(
  self : Interpreter,
  pattern : @ast.Pattern,
  env : Environment,
) -> Unit {
  match pattern {
    IdentPat(name) => self.predeclare_module_export_cell(name, name, env)
    DefaultPat(inner_pat, _) => self.predeclare_pattern_exports(inner_pat, env)
    AssignTarget(_) => ()
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(p) => self.predeclare_pattern_exports(p, env)
          None => ()
        }
      }
      match rest {
        Some(p) => self.predeclare_pattern_exports(p, env)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        self.predeclare_pattern_exports(prop.value, env)
      }
      match rest {
        Some(p) => self.predeclare_pattern_exports(p, env)
        None => ()
      }
    }
  }
}

///|
fn Interpreter::predeclare_module_exports(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  env : Environment,
) -> Unit raise Error {
  for stmt in stmts {
    match stmt {
      ExportNamedDecl(decl, specifiers, source, _, _) => {
        match decl {
          Some(inner_decl) => self.predeclare_decl_exports(inner_decl, env)
          None => ()
        }
        match source {
          Some(_) =>
            for spec in specifiers {
              self.predeclare_module_export_tdz(spec.exported)
            }
          None =>
            for spec in specifiers {
              self.predeclare_module_export_cell(
                spec.exported,
                spec.local_name,
                env,
              )
            }
        }
      }
      ExportDefaultDecl(expr, _) =>
        if !self.predeclare_default_function_export(expr, env) {
          self.predeclare_module_export_tdz("default")
        }
      ExportAllDecl(Some(ns_name), _, _, _) =>
        self.predeclare_module_export_tdz(ns_name)
      StmtList(inner_stmts, _) =>
        self.predeclare_module_exports(inner_stmts, env)
      _ => ()
    }
  }
}

///|
fn Interpreter::materialize_module_exports(
  self : Interpreter,
) -> Map[String, Value] raise Error {
  let materialized : Map[String, Value] = {}
  self.module_exports.each(fn(k, v) raise {
    if !is_private_module_export_entry(k, v) {
      materialized[k] = resolve_module_export_value(v)
    }
  })
  materialized
}

///|
fn Interpreter::new_module_environment(
  self : Interpreter,
) -> Environment raise Error {
  let env = Environment::new(parent=Some(self.global))
  env.is_var_scope = true
  env.def("this", Undefined, ConstBinding)
  env
}

///|
fn[T] Interpreter::with_module_exports(
  self : Interpreter,
  exports_map : Map[String, Value],
  body : () -> T raise Error,
) -> T raise Error {
  let saved_exports = self.module_exports
  let saved_bindings = self.module_export_bindings
  self.module_exports = exports_map
  self.module_export_bindings = []
  try {
    let result = body()
    self.module_exports = saved_exports
    self.module_export_bindings = saved_bindings
    result
  } catch {
    e => {
      self.module_exports = saved_exports
      self.module_export_bindings = saved_bindings
      raise e
    }
  }
}

///|
fn Interpreter::instantiate_module_record(
  self : Interpreter,
  record : ModuleRunRecord,
) -> Unit raise Error {
  self.with_module_exports(record.exports, fn() raise {
    with_cleared_active_callee_realm(self.realm_state, fn() raise {
      self.validate_block_early_errors(record.stmts, true)
      self.hoist_declarations(record.stmts, record.env, strict=true)
      hoist_block_tdz(record.stmts, record.env)
      self.predeclare_module_exports(record.stmts, record.env)
    })
  })
}

///|
fn Interpreter::module_exports_for_source(
  self : Interpreter,
  source : String,
  loc : @token.Loc,
) -> Map[String, Value] raise Error {
  match self.module_registry.get(source) {
    Some(exports) => exports
    None =>
      match self.host.module_loader {
        Some(ModuleLoader(load)) => {
          let exports = load(source)
          self.module_registry[source] = exports
          exports
        }
        None =>
          raise @errors.SyntaxError(
            message="Cannot find module '\{source}' at line \{loc.line}, col \{loc.col}",
          )
      }
  }
}

///|
fn Interpreter::instantiate_indirect_exports_from_stmt(
  self : Interpreter,
  stmt : @ast.Stmt,
) -> Unit raise Error {
  match stmt {
    ExportNamedDecl(None, specifiers, Some(source), _, loc) => {
      let src_exports = self.module_exports_for_source(source, loc)
      for spec in specifiers {
        let value = match
          module_export_map_get_public(src_exports, spec.local_name) {
          Some(v) => v
          None =>
            raise @errors.SyntaxError(
              message="Module '\{source}' does not export '\{spec.local_name}' at line \{loc.line}, col \{loc.col}",
            )
        }
        self.module_exports[spec.exported] = value
      }
    }
    ExportAllDecl(None, source, _, loc) => {
      let src_exports = self.module_exports_for_source(source, loc)
      src_exports.each(fn(k, v) {
        if k != "default" &&
          !is_private_module_export_entry(k, v) &&
          !self.module_exports.contains(k) {
          self.module_exports[k] = v
        }
      })
    }
    StmtList(stmts, _) =>
      for inner in stmts {
        self.instantiate_indirect_exports_from_stmt(inner)
      }
    _ => ()
  }
}

///|
fn Interpreter::instantiate_module_indirect_exports(
  self : Interpreter,
  record : ModuleRunRecord,
) -> Unit raise Error {
  self.with_module_exports(record.exports, fn() raise {
    with_cleared_active_callee_realm(self.realm_state, fn() raise {
      for stmt in record.stmts {
        self.instantiate_indirect_exports_from_stmt(stmt)
      }
    })
  })
}

///|
fn Interpreter::instantiate_imports_from_stmt(
  self : Interpreter,
  stmt : @ast.Stmt,
  env : Environment,
) -> Unit raise Error {
  match stmt {
    ImportDecl(default_import, specifiers, namespace_import, source, _, loc) =>
      ignore(
        self.exec_import(
          default_import, specifiers, namespace_import, source, env, loc,
        ),
      )
    StmtList(stmts, _) =>
      for inner in stmts {
        self.instantiate_imports_from_stmt(inner, env)
      }
    _ => ()
  }
}

///|
fn Interpreter::instantiate_module_imports(
  self : Interpreter,
  record : ModuleRunRecord,
) -> Unit raise Error {
  self.with_module_exports(record.exports, fn() raise {
    with_cleared_active_callee_realm(self.realm_state, fn() raise {
      for stmt in record.stmts {
        self.instantiate_imports_from_stmt(stmt, record.env)
      }
    })
  })
}

///|
fn collect_module_dependencies_from_stmt(
  stmt : @ast.Stmt,
  deps : Array[String],
) -> Unit {
  match stmt {
    ImportDecl(_, _, _, source, _, _) => deps.push(source)
    ExportNamedDecl(_, _, Some(source), _, _) => deps.push(source)
    ExportAllDecl(_, source, _, _) => deps.push(source)
    StmtList(stmts, _) =>
      for inner in stmts {
        collect_module_dependencies_from_stmt(inner, deps)
      }
    _ => ()
  }
}

///|
fn ModuleRunRecord::dependencies(self : ModuleRunRecord) -> Array[String] {
  let deps : Array[String] = []
  for stmt in self.stmts {
    collect_module_dependencies_from_stmt(stmt, deps)
  }
  deps
}

///|
fn module_dependency_path_exists(
  start : String,
  target : String,
  records_by_specifier : Map[String, ModuleRunRecord],
  seen : Map[String, Bool],
) -> Bool {
  if start == target {
    return true
  }
  if seen.contains(start) {
    return false
  }
  seen[start] = true
  match records_by_specifier.get(start) {
    Some(record) =>
      for dependency in record.dependencies() {
        if module_dependency_path_exists(
            dependency, target, records_by_specifier, seen,
          ) {
          return true
        }
      }
    None => ()
  }
  false
}

///|
fn module_record_dependencies_ready(
  record : ModuleRunRecord,
  records_by_specifier : Map[String, ModuleRunRecord],
  evaluation_state : Map[String, Int],
) -> Bool {
  for dependency in record.dependencies() {
    match records_by_specifier.get(dependency) {
      Some(_) =>
        match evaluation_state.get(dependency) {
          Some(2) => ()
          _ =>
            if !module_dependency_path_exists(
                dependency,
                record.specifier,
                records_by_specifier,
                {},
              ) {
              return false
            }
        }
      None => ()
    }
  }
  true
}

///|
fn Interpreter::evaluate_module_record(
  self : Interpreter,
  record : ModuleRunRecord,
) -> Map[String, Value] raise Error {
  self.with_module_exports(record.exports, fn() raise {
    with_cleared_active_callee_realm(self.realm_state, fn() raise {
      let module_ctx : ExecContext = { strict: true, current_generator: None }
      for stmt in record.stmts {
        match stmt {
          ImportDecl(_, _, _, _, _, _) => ()
          _ =>
            match self.exec_stmt(module_ctx, stmt, record.env) {
              Normal(_) => ()
              ReturnSignal(_) =>
                raise @errors.SyntaxError(
                  message="return statement outside of function",
                )
              sig => raise_if_break_continue(sig)
            }
        }
      }
      // Resolve deferred export bindings from module environment. If
      // instantiation already installed a live export cell, keep it live for
      // dependents that execute later in the same module graph; final facade
      // results are materialized only after graph evaluation completes.
      for pair in self.module_export_bindings {
        let (export_name, local_name) = pair
        match self.module_exports.get(export_name) {
          Some(Object({ class_name: "ModuleExportCell", .. })) => ()
          _ => self.module_exports[export_name] = record.env.get(local_name)
        }
      }
      self.module_exports
    })
  })
}

///|
fn Interpreter::materialize_module_record(
  self : Interpreter,
  record : ModuleRunRecord,
) -> Map[String, Value] raise Error {
  self.with_module_exports(record.exports, fn() raise {
    self.materialize_module_exports()
  })
}

///|
fn Interpreter::run_module_into(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
  exports_map : Map[String, Value],
) -> Map[String, Value] raise Error {
  let record = {
    specifier: "<module>",
    stmts,
    exports: exports_map,
    env: self.new_module_environment(),
  }
  self.instantiate_module_record(record)
  self.instantiate_module_indirect_exports(record)
  self.instantiate_module_imports(record)
  ignore(self.evaluate_module_record(record))
  self.materialize_module_record(record)
}

///|
/// Run a module source and return its exports
pub fn Interpreter::run_module(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> Map[String, Value] raise Error {
  self.run_module_into(stmts, {})
}

///|
/// Run multiple modules with all specifiers registered before evaluation.
/// The graph pass evaluates provided dependencies before importers while still
/// letting self-imports and simple cyclic fixtures resolve through the registry.
pub fn Interpreter::run_modules(
  self : Interpreter,
  modules : Array[(String, String)],
) -> Map[String, Value] raise Error {
  let records : Array[ModuleRunRecord] = []
  let registrations : Array[(String, Map[String, Value])] = []
  for pair in modules {
    let (specifier, source) = pair
    let prog = @parser.parse(source)
    let exports : Map[String, Value] = {}
    let record = {
      specifier,
      stmts: prog.stmts,
      exports,
      env: self.new_module_environment(),
    }
    records.push(record)
    registrations.push((specifier, exports))
  }
  for pair in registrations {
    let (specifier, exports) = pair
    self.register_module(specifier, exports)
  }
  for record in records {
    self.instantiate_module_record(record)
  }
  for record in records {
    self.instantiate_module_indirect_exports(record)
  }
  for record in records {
    self.instantiate_module_imports(record)
  }
  let records_by_specifier : Map[String, ModuleRunRecord] = {}
  for record in records {
    records_by_specifier[record.specifier] = record
  }
  let evaluation_state : Map[String, Int] = {}
  let mut remaining = records.length()
  while remaining > 0 {
    let mut progressed = false
    for record in records {
      match evaluation_state.get(record.specifier) {
        Some(2) => ()
        _ =>
          if module_record_dependencies_ready(
              record, records_by_specifier, evaluation_state,
            ) {
            ignore(self.evaluate_module_record(record))
            evaluation_state[record.specifier] = 2
            remaining = remaining - 1
            progressed = true
          }
      }
    }
    if !progressed {
      for record in records {
        match evaluation_state.get(record.specifier) {
          Some(2) => ()
          _ => {
            ignore(self.evaluate_module_record(record))
            evaluation_state[record.specifier] = 2
            remaining = remaining - 1
            break
          }
        }
      }
    }
  }
  match records.last() {
    Some(last_record) => self.materialize_module_record(last_record)
    None => {}
  }
}
