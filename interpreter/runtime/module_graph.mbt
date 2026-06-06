///|
priv enum ModuleExportResolution {
  Resolved(Value)
  NotFound
  Ambiguous
}

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
  records_by_specifier : Map[String, ModuleRunRecord],
) -> Unit raise Error {
  match stmt {
    ExportNamedDecl(None, specifiers, Some(source), _, loc) =>
      for spec in specifiers {
        let value = match
          self.resolve_module_export_from_source(
            source,
            spec.local_name,
            records_by_specifier,
            {},
          ) {
          Resolved(v) => v
          Ambiguous =>
            raise @errors.SyntaxError(
              message="Ambiguous export '\{spec.local_name}' from module '\{source}' at line \{loc.line}, col \{loc.col}",
            )
          NotFound =>
            raise @errors.SyntaxError(
              message="Module '\{source}' does not export '\{spec.local_name}' at line \{loc.line}, col \{loc.col}",
            )
        }
        self.module_exports[spec.exported] = value
      }
    ExportAllDecl(Some(ns_name), source, _, loc) => {
      let src_exports = self.module_exports_for_source(source, loc)
      self.module_exports[ns_name] = self.create_module_namespace_object(
        src_exports,
      )
    }
    ExportAllDecl(None, _, _, _) => ()
    StmtList(stmts, _) =>
      for inner in stmts {
        self.instantiate_indirect_exports_from_stmt(inner, records_by_specifier)
      }
    _ => ()
  }
}

///|
fn Interpreter::instantiate_module_star_exports(
  self : Interpreter,
  record : ModuleRunRecord,
  records_by_specifier : Map[String, ModuleRunRecord],
) -> Unit raise Error {
  for name in self.module_get_exported_names(record, records_by_specifier, {}) {
    if name != "default" {
      match self.resolve_module_export(record, name, records_by_specifier, {}) {
        Resolved(value) => self.module_exports[name] = value
        NotFound | Ambiguous => ()
      }
    }
  }
}

///|
fn Interpreter::instantiate_module_indirect_exports(
  self : Interpreter,
  record : ModuleRunRecord,
  records_by_specifier : Map[String, ModuleRunRecord],
) -> Unit raise Error {
  self.with_module_exports(record.exports, fn() raise {
    with_cleared_active_callee_realm(self.realm_state, fn() raise {
      for stmt in record.stmts {
        self.instantiate_indirect_exports_from_stmt(stmt, records_by_specifier)
      }
      self.instantiate_module_star_exports(record, records_by_specifier)
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
fn collect_module_dependency_edges_from_stmt(
  stmt : @ast.Stmt,
  edges : Array[(String, Bool)],
) -> Unit {
  match stmt {
    ImportDecl(_, _, _, source, _, _) => edges.push((source, true))
    ExportNamedDecl(_, _, Some(source), _, _) => edges.push((source, false))
    ExportAllDecl(_, source, _, _) => edges.push((source, false))
    StmtList(stmts, _) =>
      for inner in stmts {
        collect_module_dependency_edges_from_stmt(inner, edges)
      }
    _ => ()
  }
}

///|
fn ModuleRunRecord::dependency_edges(
  self : ModuleRunRecord,
) -> Array[(String, Bool)] {
  let edges : Array[(String, Bool)] = []
  for stmt in self.stmts {
    collect_module_dependency_edges_from_stmt(stmt, edges)
  }
  edges
}

///|
fn ModuleRunRecord::dependencies(self : ModuleRunRecord) -> Array[String] {
  let deps : Array[String] = []
  for edge in self.dependency_edges() {
    deps.push(edge.0)
  }
  deps
}

///|
fn module_export_resolution_same(
  a : ModuleExportResolution,
  b : ModuleExportResolution,
) -> Bool {
  match (a, b) {
    (Resolved(av), Resolved(bv)) => strict_equal(av, bv)
    _ => false
  }
}

///|
fn add_module_export_name(
  names : Array[String],
  seen : Map[String, Bool],
  name : String,
) -> Unit {
  if !seen.contains(name) {
    seen[name] = true
    names.push(name)
  }
}

///|
fn pattern_exports_name(pattern : @ast.Pattern, export_name : String) -> Bool {
  match pattern {
    IdentPat(name) => name == export_name
    DefaultPat(inner_pat, _) => pattern_exports_name(inner_pat, export_name)
    AssignTarget(_) => false
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(p) => if pattern_exports_name(p, export_name) { return true }
          None => ()
        }
      }
      match rest {
        Some(p) => pattern_exports_name(p, export_name)
        None => false
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        if pattern_exports_name(prop.value, export_name) {
          return true
        }
      }
      match rest {
        Some(p) => pattern_exports_name(p, export_name)
        None => false
      }
    }
  }
}

///|
fn decl_exports_name(decl : @ast.Stmt, export_name : String) -> Bool {
  match decl {
    VarDecl(_, name, _, _) => name == export_name
    FuncDecl(name, _, _, _) => name == export_name
    FuncDeclExt(name, _, _, _, _) => name == export_name
    GeneratorDecl(name, _, _, _) => name == export_name
    GeneratorDeclExt(name, _, _, _, _) => name == export_name
    AsyncFuncDecl(name, _, _, _) => name == export_name
    AsyncFuncDeclExt(name, _, _, _, _) => name == export_name
    AsyncGeneratorDecl(name, _, _, _) => name == export_name
    AsyncGeneratorDeclExt(name, _, _, _, _) => name == export_name
    ClassDecl(name, _, _, _) => name == export_name
    DestructureDecl(_, pattern, _, _) =>
      pattern_exports_name(pattern, export_name)
    StmtList(stmts, _) => {
      for stmt in stmts {
        if decl_exports_name(stmt, export_name) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
fn collect_decl_export_names(
  decl : @ast.Stmt,
  names : Array[String],
  seen : Map[String, Bool],
) -> Unit {
  match decl {
    VarDecl(_, name, _, _)
    | FuncDecl(name, _, _, _)
    | FuncDeclExt(name, _, _, _, _)
    | GeneratorDecl(name, _, _, _)
    | GeneratorDeclExt(name, _, _, _, _)
    | AsyncFuncDecl(name, _, _, _)
    | AsyncFuncDeclExt(name, _, _, _, _)
    | AsyncGeneratorDecl(name, _, _, _)
    | AsyncGeneratorDeclExt(name, _, _, _, _)
    | ClassDecl(name, _, _, _) => add_module_export_name(names, seen, name)
    DestructureDecl(_, pattern, _, _) =>
      collect_pattern_export_names(pattern, names, seen)
    StmtList(stmts, _) =>
      for stmt in stmts {
        collect_decl_export_names(stmt, names, seen)
      }
    _ => ()
  }
}

///|
fn collect_pattern_export_names(
  pattern : @ast.Pattern,
  names : Array[String],
  seen : Map[String, Bool],
) -> Unit {
  match pattern {
    IdentPat(name) => add_module_export_name(names, seen, name)
    DefaultPat(inner_pat, _) =>
      collect_pattern_export_names(inner_pat, names, seen)
    AssignTarget(_) => ()
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(p) => collect_pattern_export_names(p, names, seen)
          None => ()
        }
      }
      match rest {
        Some(p) => collect_pattern_export_names(p, names, seen)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        collect_pattern_export_names(prop.value, names, seen)
      }
      match rest {
        Some(p) => collect_pattern_export_names(p, names, seen)
        None => ()
      }
    }
  }
}

///|
fn module_record_has_direct_export_name(
  record : ModuleRunRecord,
  export_name : String,
) -> Bool {
  for stmt in record.stmts {
    match stmt {
      ExportNamedDecl(Some(decl), _, _, _, _) =>
        if decl_exports_name(decl, export_name) {
          return true
        }
      ExportNamedDecl(None, specifiers, None, _, _) =>
        for spec in specifiers {
          if spec.exported == export_name {
            return true
          }
        }
      ExportDefaultDecl(_, _) => if export_name == "default" { return true }
      ExportAllDecl(Some(ns_name), _, _, _) =>
        if ns_name == export_name {
          return true
        }
      StmtList(stmts, _) =>
        for inner in stmts {
          match inner {
            ExportNamedDecl(Some(decl), _, _, _, _) =>
              if decl_exports_name(decl, export_name) {
                return true
              }
            ExportNamedDecl(None, specifiers, None, _, _) =>
              for spec in specifiers {
                if spec.exported == export_name {
                  return true
                }
              }
            ExportDefaultDecl(_, _) =>
              if export_name == "default" {
                return true
              }
            ExportAllDecl(Some(ns_name), _, _, _) =>
              if ns_name == export_name {
                return true
              }
            _ => ()
          }
        }
      _ => ()
    }
  }
  false
}

///|
fn collect_module_direct_export_names_from_stmt(
  stmt : @ast.Stmt,
  names : Array[String],
  seen : Map[String, Bool],
) -> Unit {
  match stmt {
    ExportNamedDecl(Some(decl), _, _, _, _) =>
      collect_decl_export_names(decl, names, seen)
    ExportNamedDecl(None, specifiers, _, _, _) =>
      for spec in specifiers {
        add_module_export_name(names, seen, spec.exported)
      }
    ExportDefaultDecl(_, _) => add_module_export_name(names, seen, "default")
    ExportAllDecl(Some(ns_name), _, _, _) =>
      add_module_export_name(names, seen, ns_name)
    StmtList(stmts, _) =>
      for inner in stmts {
        collect_module_direct_export_names_from_stmt(inner, names, seen)
      }
    _ => ()
  }
}

///|
fn module_export_names_from_exports_map(
  exports_map : Map[String, Value],
) -> Array[String] {
  let names : Array[String] = []
  exports_map.each(fn(k, v) {
    if !is_private_module_export_entry(k, v) {
      names.push(k)
    }
  })
  names
}

///|
fn collect_module_star_sources_from_stmt(
  stmt : @ast.Stmt,
  sources : Array[String],
) -> Unit {
  match stmt {
    ExportAllDecl(None, source, _, _) => sources.push(source)
    StmtList(stmts, _) =>
      for inner in stmts {
        collect_module_star_sources_from_stmt(inner, sources)
      }
    _ => ()
  }
}

///|
fn ModuleRunRecord::star_sources(self : ModuleRunRecord) -> Array[String] {
  let sources : Array[String] = []
  for stmt in self.stmts {
    collect_module_star_sources_from_stmt(stmt, sources)
  }
  sources
}

///|
fn Interpreter::module_get_exported_names_from_source(
  self : Interpreter,
  source : String,
  records_by_specifier : Map[String, ModuleRunRecord],
  seen : Map[String, Bool],
) -> Array[String] raise Error {
  match records_by_specifier.get(source) {
    Some(record) =>
      self.module_get_exported_names(record, records_by_specifier, seen)
    None =>
      module_export_names_from_exports_map(
        self.module_exports_for_source(source, @token.Loc::default()),
      )
  }
}

///|
fn Interpreter::module_get_exported_names(
  self : Interpreter,
  record : ModuleRunRecord,
  records_by_specifier : Map[String, ModuleRunRecord],
  seen_modules : Map[String, Bool],
) -> Array[String] raise Error {
  if seen_modules.contains(record.specifier) {
    return []
  }
  seen_modules[record.specifier] = true
  let names : Array[String] = []
  let seen_names : Map[String, Bool] = {}
  for stmt in record.stmts {
    collect_module_direct_export_names_from_stmt(stmt, names, seen_names)
  }
  for source in record.star_sources() {
    for
      name in self.module_get_exported_names_from_source(
        source, records_by_specifier, seen_modules,
      ) {
      if name != "default" {
        add_module_export_name(names, seen_names, name)
      }
    }
  }
  names
}

///|
fn Interpreter::resolve_module_export_from_source(
  self : Interpreter,
  source : String,
  export_name : String,
  records_by_specifier : Map[String, ModuleRunRecord],
  resolve_set : Map[String, Bool],
) -> ModuleExportResolution raise Error {
  match records_by_specifier.get(source) {
    Some(record) =>
      self.resolve_module_export(
        record, export_name, records_by_specifier, resolve_set,
      )
    None =>
      match
        module_export_map_get_public(
          self.module_exports_for_source(source, @token.Loc::default()),
          export_name,
        ) {
        Some(value) => Resolved(value)
        None => NotFound
      }
  }
}

///|
fn Interpreter::resolve_explicit_indirect_export_from_stmt(
  self : Interpreter,
  stmt : @ast.Stmt,
  export_name : String,
  records_by_specifier : Map[String, ModuleRunRecord],
  resolve_set : Map[String, Bool],
) -> ModuleExportResolution raise Error {
  match stmt {
    ExportNamedDecl(None, specifiers, Some(source), _, _) =>
      for spec in specifiers {
        if spec.exported == export_name {
          return self.resolve_module_export_from_source(
            source,
            spec.local_name,
            records_by_specifier,
            resolve_set,
          )
        }
      }
    StmtList(stmts, _) =>
      for inner in stmts {
        match
          self.resolve_explicit_indirect_export_from_stmt(
            inner, export_name, records_by_specifier, resolve_set,
          ) {
          NotFound => ()
          other => return other
        }
      }
    _ => ()
  }
  NotFound
}

///|
fn Interpreter::resolve_module_export(
  self : Interpreter,
  record : ModuleRunRecord,
  export_name : String,
  records_by_specifier : Map[String, ModuleRunRecord],
  resolve_set : Map[String, Bool],
) -> ModuleExportResolution raise Error {
  let resolve_key = record.specifier + "\u0000" + export_name
  if resolve_set.contains(resolve_key) {
    return NotFound
  }
  resolve_set[resolve_key] = true
  if module_record_has_direct_export_name(record, export_name) {
    return match module_export_map_get_public(record.exports, export_name) {
      Some(value) => Resolved(value)
      None => NotFound
    }
  }
  match
    self.resolve_explicit_indirect_export_from_stmt(
      StmtList(record.stmts, @token.Loc::default()),
      export_name,
      records_by_specifier,
      resolve_set,
    ) {
    NotFound => ()
    other => return other
  }
  if export_name == "default" {
    return NotFound
  }
  let mut star_resolution : ModuleExportResolution = NotFound
  for source in record.star_sources() {
    match
      self.resolve_module_export_from_source(
        source, export_name, records_by_specifier, resolve_set,
      ) {
      NotFound => ()
      Ambiguous => return Ambiguous
      Resolved(value) => {
        let next_resolution = Resolved(value)
        match star_resolution {
          NotFound => star_resolution = next_resolution
          Resolved(_) =>
            if !module_export_resolution_same(star_resolution, next_resolution) {
              return Ambiguous
            }
          Ambiguous => return Ambiguous
        }
      }
    }
  }
  star_resolution
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
fn should_skip_weak_module_back_edge(
  record : ModuleRunRecord,
  dependency : String,
  strong : Bool,
  records_by_specifier : Map[String, ModuleRunRecord],
) -> Bool {
  !strong &&
  module_dependency_path_exists(
    dependency,
    record.specifier,
    records_by_specifier,
    {},
  )
}

///|
fn Interpreter::visit_module_dependencies_first(
  self : Interpreter,
  record : ModuleRunRecord,
  records_by_specifier : Map[String, ModuleRunRecord],
  state : Map[String, Int],
  action : (Interpreter, ModuleRunRecord) -> Unit raise Error,
) -> Unit raise Error {
  match state.get(record.specifier) {
    Some(2) => return
    Some(1) => return
    _ => ()
  }
  state[record.specifier] = 1
  for edge in record.dependency_edges() {
    let dependency = edge.0
    let strong = edge.1
    if should_skip_weak_module_back_edge(
        record, dependency, strong, records_by_specifier,
      ) {
      continue
    }
    match records_by_specifier.get(dependency) {
      Some(dep_record) =>
        self.visit_module_dependencies_first(
          dep_record, records_by_specifier, state, action,
        )
      None => ()
    }
  }
  action(self, record)
  state[record.specifier] = 2
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
          ExportNamedDecl(None, _, Some(_), _, _) => ()
          ExportAllDecl(_, _, _, _) => ()
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
          Some(value) if module_export_entry_is_live_cell(value) => ()
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
  self.instantiate_module_indirect_exports(record, {})
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
  let records_by_specifier : Map[String, ModuleRunRecord] = {}
  for record in records {
    records_by_specifier[record.specifier] = record
  }
  let indirect_state : Map[String, Int] = {}
  for record in records {
    self.visit_module_dependencies_first(
      record,
      records_by_specifier,
      indirect_state,
      fn(interp, rec) raise {
        interp.instantiate_module_indirect_exports(rec, records_by_specifier)
      },
    )
  }
  for record in records {
    self.instantiate_module_imports(record)
  }
  let evaluation_state : Map[String, Int] = {}
  for record in records {
    self.visit_module_dependencies_first(
      record,
      records_by_specifier,
      evaluation_state,
      fn(interp, rec) raise { ignore(interp.evaluate_module_record(rec)) },
    )
  }
  match records.last() {
    Some(last_record) => self.materialize_module_record(last_record)
    None => {}
  }
}
