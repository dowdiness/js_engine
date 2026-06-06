///|
/// Execute an import declaration
fn Interpreter::exec_import(
  self : Interpreter,
  default_import : String?,
  specifiers : Array[@ast.ImportSpecifier],
  namespace_import : String?,
  source : String,
  env : Environment,
  loc : @token.Loc,
) -> Signal raise Error {
  // Look up module in registry; fall back to module_loader if provided
  let module_exports = match self.module_registry.get(source) {
    Some(exports) => exports
    None =>
      match self.host.module_loader {
        Some(ModuleLoader(load)) => {
          let exports = load(source)
          // Cache the result so repeated imports of the same specifier are free
          self.module_registry[source] = exports
          exports
        }
        None =>
          raise @errors.SyntaxError(
            message="Cannot find module '\{source}' at line \{loc.line}, col \{loc.col}",
          )
      }
  }
  // import defaultExport from 'source'
  match default_import {
    Some(name) =>
      match module_export_map_get_public(module_exports, "default") {
        Some(_) =>
          env.def(
            name,
            make_module_import_cell("default", module_exports),
            ConstBinding,
          )
        None =>
          raise @errors.SyntaxError(
            message="Module '\{source}' does not have a default export at line \{loc.line}, col \{loc.col}",
          )
      }
    None => ()
  }
  // import { name1, name2 as alias } from 'source'
  for spec in specifiers {
    match module_export_map_get_public(module_exports, spec.imported) {
      Some(_) =>
        env.def(
          spec.local_name,
          make_module_import_cell(spec.imported, module_exports),
          ConstBinding,
        )
      None =>
        raise @errors.SyntaxError(
          message="Module '\{source}' does not export '\{spec.imported}' at line \{loc.line}, col \{loc.col}",
        )
    }
  }
  // import * as namespace from 'source'
  match namespace_import {
    Some(name) =>
      env.def(
        name,
        self.create_module_namespace_object(module_exports),
        ConstBinding,
      )
    None => ()
  }
  Normal(Undefined)
}

///|
/// Execute a named export declaration
fn Interpreter::exec_export_named(
  self : Interpreter,
  ctx : ExecContext,
  decl : @ast.Stmt?,
  specifiers : Array[@ast.ExportSpecifier],
  source : String?,
  env : Environment,
  loc : @token.Loc,
) -> Signal raise Error {
  // export let/const/var/function/class ...
  match decl {
    Some(inner_decl) => {
      let signal = self.exec_stmt(ctx, inner_decl, env)
      // Record declared names for final materialization. During evaluation,
      // predeclared ModuleExportCell entries read directly from `env`.
      self.extract_export_names(inner_decl)
      return signal
    }
    None => ()
  }
  // export { name1, name2 as alias } [from 'source']
  match source {
    Some(src) => {
      // Re-export from another module. Keep any ModuleExportCell intact so
      // namespace objects observe live values while a cycle is evaluating.
      let src_exports = match self.module_registry.get(src) {
        Some(exports) => exports
        None =>
          match self.host.module_loader {
            Some(ModuleLoader(load)) => {
              let exports = load(src)
              self.module_registry[src] = exports
              exports
            }
            None =>
              raise @errors.SyntaxError(
                message="Cannot find module '\{src}' at line \{loc.line}, col \{loc.col}",
              )
          }
      }
      for spec in specifiers {
        let value = match
          module_export_map_get_public(src_exports, spec.local_name) {
          Some(v) => v
          None =>
            raise @errors.SyntaxError(
              message="Module '\{src}' does not export '\{spec.local_name}' at line \{loc.line}, col \{loc.col}",
            )
        }
        self.module_exports[spec.exported] = value
      }
    }
    None =>
      // Local export: defer final resolution for live bindings.
      for spec in specifiers {
        self.module_export_bindings.push((spec.exported, spec.local_name))
      }
  }
  Normal(Undefined)
}

///|
/// Execute export * from 'source' or export * as name from 'source'
fn Interpreter::exec_export_all(
  self : Interpreter,
  ns_alias : String?,
  source : String,
  loc : @token.Loc,
) -> Signal raise Error {
  let src_exports = match self.module_registry.get(source) {
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
  match ns_alias {
    Some(name) =>
      // export * as name from 'source' - create namespace object
      self.module_exports[name] = self.create_module_namespace_object(
        src_exports,
      )
    None =>
      // export * from 'source' - re-export all (except default)
      src_exports.each(fn(k, v) {
        let should_copy = match self.module_exports.get(k) {
          Some(Object(data)) if data.class_name == "ModuleTDZ" => true
          Some(_) => false
          None => true
        }
        if k != "default" &&
          !is_private_module_export_entry(k, v) &&
          should_copy {
          self.module_exports[k] = v
        }
      })
  }
  Normal(Undefined)
}

///|
/// Record exported names from a declaration for deferred resolution (live bindings)
fn Interpreter::extract_export_names(
  self : Interpreter,
  decl : @ast.Stmt,
) -> Unit {
  match decl {
    VarDecl(_, name, _, _) => self.module_export_bindings.push((name, name))
    FuncDecl(name, _, _, _) => self.module_export_bindings.push((name, name))
    FuncDeclExt(name, _, _, _, _) =>
      self.module_export_bindings.push((name, name))
    GeneratorDecl(name, _, _, _) =>
      self.module_export_bindings.push((name, name))
    GeneratorDeclExt(name, _, _, _, _) =>
      self.module_export_bindings.push((name, name))
    AsyncFuncDecl(name, _, _, _) =>
      self.module_export_bindings.push((name, name))
    AsyncFuncDeclExt(name, _, _, _, _) =>
      self.module_export_bindings.push((name, name))
    AsyncGeneratorDecl(name, _, _, _) =>
      self.module_export_bindings.push((name, name))
    AsyncGeneratorDeclExt(name, _, _, _, _) =>
      self.module_export_bindings.push((name, name))
    ClassDecl(name, _, _, _) => self.module_export_bindings.push((name, name))
    DestructureDecl(_, pattern, _, _) =>
      self.extract_pattern_export_names(pattern)
    StmtList(stmts, _) =>
      for stmt in stmts {
        self.extract_export_names(stmt)
      }
    _ => ()
  }
}

///|
/// Record names from a destructuring pattern for deferred export resolution
fn Interpreter::extract_pattern_export_names(
  self : Interpreter,
  pattern : @ast.Pattern,
) -> Unit {
  match pattern {
    IdentPat(name) => self.module_export_bindings.push((name, name))
    DefaultPat(inner_pat, _) => self.extract_pattern_export_names(inner_pat)
    AssignTarget(_) => () // member expressions don't export names
    ArrayPat(elements, rest) => {
      for elem in elements {
        match elem {
          Some(p) => self.extract_pattern_export_names(p)
          None => ()
        }
      }
      match rest {
        Some(p) => self.extract_pattern_export_names(p)
        None => ()
      }
    }
    ObjectPat(props, rest) => {
      for prop in props {
        self.extract_pattern_export_names(prop.value)
      }
      match rest {
        Some(p) => self.extract_pattern_export_names(p)
        None => ()
      }
    }
  }
}

///|
/// Register a module's exports in the module registry
pub fn Interpreter::register_module(
  self : Interpreter,
  specifier : String,
  exports : Map[String, Value],
) -> Unit {
  self.module_registry[specifier] = exports
}
