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
  // Look up module in registry
  let module_exports = match self.module_registry.get(source) {
    Some(exports) => exports
    None =>
      raise @errors.SyntaxError(
        message="Cannot find module '\{source}' at line \{loc.line}, col \{loc.col}",
      )
  }
  // import defaultExport from 'source'
  match default_import {
    Some(name) => {
      let value = match module_exports.get("default") {
        Some(v) => v
        None =>
          raise @errors.SyntaxError(
            message="Module '\{source}' does not have a default export at line \{loc.line}, col \{loc.col}",
          )
      }
      env.def(name, value, ConstBinding)
    }
    None => ()
  }
  // import { name1, name2 as alias } from 'source'
  for spec in specifiers {
    let value = match module_exports.get(spec.imported) {
      Some(v) => v
      None =>
        raise @errors.SyntaxError(
          message="Module '\{source}' does not export '\{spec.imported}' at line \{loc.line}, col \{loc.col}",
        )
    }
    env.def(spec.local_name, value, ConstBinding)
  }
  // import * as namespace from 'source'
  match namespace_import {
    Some(name) => {
      // Create a namespace object with all exports as properties
      let ns_props : Map[String, Value] = {}
      let ns_descs : Map[String, PropDescriptor] = {}
      module_exports.each(fn(k, v) {
        ns_props[k] = v
        ns_descs[k] = {
          writable: false,
          enumerable: true,
          configurable: false,
          getter: None,
          setter: None,
        }
      })
      let ns_obj : Value = Object({
        properties: ns_props,
        symbol_properties: {},
        prototype: Null,
        callable: None,
        class_name: "Module",
        descriptors: ns_descs,
        symbol_descriptors: {},
        extensible: false,
      })
      env.def(name, ns_obj, ConstBinding)
    }
    None => ()
  }
  Normal(Undefined)
}

///|
/// Execute a named export declaration
fn Interpreter::exec_export_named(
  self : Interpreter,
  decl : @ast.Stmt?,
  specifiers : Array[@ast.ExportSpecifier],
  source : String?,
  env : Environment,
  loc : @token.Loc,
) -> Signal raise Error {
  // export let/const/var/function/class ...
  match decl {
    Some(inner_decl) => {
      let signal = self.exec_stmt(inner_decl, env)
      // Record declared names for deferred resolution (live bindings)
      self.extract_export_names(inner_decl)
      return signal
    }
    None => ()
  }
  // export { name1, name2 as alias } [from 'source']
  match source {
    Some(src) => {
      // Re-export from another module - resolve immediately (source already finalized)
      let src_exports = match self.module_registry.get(src) {
        Some(exports) => exports
        None =>
          raise @errors.SyntaxError(
            message="Cannot find module '\{src}' at line \{loc.line}, col \{loc.col}",
          )
      }
      for spec in specifiers {
        let value = match src_exports.get(spec.local_name) {
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
      // Local export: defer resolution for live bindings
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
      raise @errors.SyntaxError(
        message="Cannot find module '\{source}' at line \{loc.line}, col \{loc.col}",
      )
  }
  match ns_alias {
    Some(name) => {
      // export * as name from 'source' - create namespace object
      let ns_props : Map[String, Value] = {}
      let ns_descs : Map[String, PropDescriptor] = {}
      src_exports.each(fn(k, v) {
        ns_props[k] = v
        ns_descs[k] = {
          writable: false,
          enumerable: true,
          configurable: false,
          getter: None,
          setter: None,
        }
      })
      let ns_obj : Value = Object({
        properties: ns_props,
        symbol_properties: {},
        prototype: Null,
        callable: None,
        class_name: "Module",
        descriptors: ns_descs,
        symbol_descriptors: {},
        extensible: false,
      })
      self.module_exports[name] = ns_obj
    }
    None =>
      // export * from 'source' - re-export all (except default)
      src_exports.each(fn(k, v) {
        if k != "default" {
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

///|
/// Run a module source and return its exports
pub fn Interpreter::run_module(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> Map[String, Value] raise Error {
  // Save and reset module exports for this module
  let saved_exports = self.module_exports
  let saved_bindings = self.module_export_bindings
  let saved_strict = self.strict
  self.module_exports = {}
  self.module_export_bindings = []
  // Create a module-scoped environment that inherits from global
  let module_env = Environment::new(parent=Some(self.global))
  try {
    // Modules are always strict mode
    self.strict = true
    // Static block-scoped redeclaration checks (applies to module code too).
    self.validate_block_early_errors(stmts, true)
    // Hoist var declarations and function declarations
    self.hoist_declarations(stmts, module_env)
    // Also hoist block-scoped (let/const/class) with TDZ
    hoist_block_tdz(stmts, module_env)
    for stmt in stmts {
      match self.exec_stmt(stmt, module_env) {
        Normal(_) => ()
        ReturnSignal(_) =>
          raise @errors.SyntaxError(
            message="return statement outside of function",
          )
        BreakSignal(_, _) =>
          raise @errors.SyntaxError(message="break statement outside of loop")
        ContinueSignal(_, _) =>
          raise @errors.SyntaxError(
            message="continue statement outside of loop",
          )
      }
    }
    self.strict = saved_strict
    // Resolve deferred export bindings from module environment (live bindings)
    for pair in self.module_export_bindings {
      let (export_name, local_name) = pair
      self.module_exports[export_name] = module_env.get(local_name)
    }
    let exports = self.module_exports
    self.module_exports = saved_exports
    self.module_export_bindings = saved_bindings
    exports
  } catch {
    e => {
      self.strict = saved_strict
      self.module_exports = saved_exports
      self.module_export_bindings = saved_bindings
      raise e
    }
  }
}
