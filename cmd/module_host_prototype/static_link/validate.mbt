///|
// THROWAWAY: static ESM graph validation, not a full Module early-error pass.
// Spec: Source Text Module Records ParseModule / ResolveExport /
// InitializeEnvironment. Only identities and binding names cross this seam.
// No Runtime/Interpreter/Realm/Value or executable callback dependency.
// Recursive resolution is for small fixtures, not a stack-safety claim.
pub suberror LinkError {
  LinkError(
    kind~ : String,
    module_key~ : String,
    export_name~ : String,
    line~ : Int,
    column~ : Int
  )
}

///|
priv enum Target {
  Local(String)
  Indirect(String, String)
  Namespace(String)
  Default
}

///|
priv enum Binding {
  Named(String)
  Namespace
  Default
} derive(Eq)

///|
priv enum Resolution {
  Found(String, Binding)
  Missing
  Ambiguous
} derive(Eq)

///|
priv struct ModuleInfo {
  key : String
  imports : Map[String, (Target, @token.Loc)]
  exports : Map[String, (Target, @token.Loc)]
  stars : Array[String]
  locals : Array[String]
}

///|
fn ModuleInfo::ModuleInfo(key : String, locals : Array[String]) -> ModuleInfo {
  { key, imports: Map([]), exports: Map([]), stars: [], locals, }
}

///|
fn reject(
  kind : String,
  key : String,
  name : String,
  loc : @token.Loc,
) -> Unit raise LinkError {
  raise LinkError(
    kind~,
    module_key=key,
    export_name=name,
    line=loc.line,
    column=loc.col,
  )
}

///|
fn flatten(stmts : Array[@ast.Stmt]) -> Array[@ast.Stmt] {
  let work = stmts.rev()
  let out = []
  while work.pop() is Some(stmt) {
    match stmt {
      StmtList(children, _) => children.rev_each(child => work.push(child))
      _ => out.push(stmt)
    }
  }
  out
}

///|
fn declaration_names(stmt : @ast.Stmt) -> Array[String] {
  match stmt {
    StmtList(children, _) => {
      let names = []
      for child in flatten(children) {
        for name in declaration_names(child) {
          names.push(name)
        }
      }
      names
    }
    VarDecl(_, name, _, _) => [name]
    DestructureDecl(_, pattern, _, _) => @static_semantics.bound_names(pattern)
    FuncDecl(name, _, _, _, _)
    | FuncDeclExt(name, _, _, _, _, _)
    | GeneratorDecl(name, _, _, _, _)
    | GeneratorDeclExt(name, _, _, _, _, _)
    | AsyncFuncDecl(name, _, _, _, _)
    | AsyncFuncDeclExt(name, _, _, _, _, _)
    | AsyncGeneratorDecl(name, _, _, _, _)
    | AsyncGeneratorDeclExt(name, _, _, _, _, _)
    | ClassDecl(name, _, _, _, _) => [name]
    _ => []
  }
}

///|
fn default_target(expr : @ast.Expr) -> Target {
  match expr {
    FuncExpr(Some(name), _, _, _, _)
    | FuncExprExt(Some(name), _, _, _, _, _)
    | GeneratorExpr(Some(name), _, _, _, _)
    | GeneratorExprExt(Some(name), _, _, _, _, _)
    | AsyncFuncExpr(Some(name), _, _, _, _)
    | AsyncFuncExprExt(Some(name), _, _, _, _, _)
    | AsyncGeneratorExpr(Some(name), _, _, _, _)
    | AsyncGeneratorExprExt(Some(name), _, _, _, _, _)
    | ClassExpr(Some(name), _, _, _, _) => Local(name)
    _ => Default
  }
}

///|
fn ModuleInfo::add_export(
  self : ModuleInfo,
  name : String,
  target : Target,
  loc : @token.Loc,
) -> Unit raise LinkError {
  guard !self.exports.contains(name) else {
    reject("duplicate-export", self.key, name, loc)
    return
  }
  self.exports[name] = (target, loc)
}

///|
fn describe(
  key : String,
  stmts : Array[@ast.Stmt],
) -> ModuleInfo raise LinkError {
  let roots = flatten(stmts)
  let info = ModuleInfo(
    key,
    @static_semantics.collect_var_declared_names(stmts),
  )
  for stmt in roots {
    match stmt {
      ImportDecl(default_name, names, namespace_name, source, _, loc) => {
        if default_name is Some(name) {
          info.imports[name] = (Indirect(source, "default"), loc)
        }
        for spec in names {
          info.imports[spec.local_name] = (Indirect(source, spec.imported), loc)
        }
        if namespace_name is Some(name) {
          info.imports[name] = (Namespace(source), loc)
        }
      }
      ExportNamedDecl(Some(decl), _, _, _, loc) =>
        for name in declaration_names(decl) {
          info.locals.push(name)
          info.add_export(name, Local(name), loc)
        }
      ExportNamedDecl(None, names, source, _, loc) =>
        for spec in names {
          let target = match source {
            Some(source) => Indirect(source, spec.local_name)
            None => Local(spec.local_name)
          }
          info.add_export(spec.exported, target, loc)
        }
      ExportAllDecl(Some(name), source, _, loc) =>
        info.add_export(name, Namespace(source), loc)
      ExportAllDecl(None, source, _, _) => info.stars.push(source)
      ExportDefaultDecl(expr, loc) => {
        let target = default_target(expr)
        if target is Local(name) {
          info.locals.push(name)
        }
        info.add_export("default", target, loc)
      }
      _ =>
        for name in declaration_names(stmt) {
          info.locals.push(name)
        }
    }
  }
  // ParseModule converts imported-then-exported bindings into indirect entries.
  // This preserves binding identity through diamond-shaped star reexports.
  for name, (target, loc) in info.exports {
    if target is Local(local_name) {
      match info.imports.get(local_name) {
        Some((import_target, _)) => info.exports[name] = (import_target, loc)
        None =>
          if !info.locals.contains(local_name) {
            reject("missing-local-binding", key, local_name, loc)
          }
      }
    }
  }
  info
}

///|
fn resolve_export(
  graph : Map[String, ModuleInfo],
  key : String,
  name : String,
  seen : Array[(String, String)],
) -> Resolution {
  guard !seen.contains((key, name)) else { return Missing }
  seen.push((key, name))
  guard graph.get(key) is Some(info) else { return Missing }
  match info.exports.get(name) {
    Some((Local(binding), _)) => return Found(key, Named(binding))
    Some((Default, _)) => return Found(key, Default)
    Some((Namespace(source), _)) => return Found(source, Namespace)
    Some((Indirect(source, imported), _)) =>
      // Explicit resolution returns directly, even if it is missing; never
      // repair an invalid explicit export by falling back to a star export.
      return resolve_export(graph, source, imported, seen)
    None => ()
  }
  guard name != "default" else { return Missing }
  let mut result = Missing
  for source in info.stars {
    match resolve_export(graph, source, name, seen) {
      Missing => ()
      Ambiguous => return Ambiguous
      Found(_, _) as candidate =>
        match result {
          Missing => result = candidate
          _ => if result != candidate { return Ambiguous }
        }
    }
  }
  result
}

///|
fn require_resolution(
  graph : Map[String, ModuleInfo],
  owner : String,
  source : String,
  name : String,
  loc : @token.Loc,
) -> Unit raise LinkError {
  match resolve_export(graph, source, name, []) {
    Found(_, _) => ()
    Missing => reject("missing-export", owner, name, loc)
    Ambiguous => reject("ambiguous-export", owner, name, loc)
  }
}

///|
// Validate required named imports and every explicit indirect export, including
// unused reexports. Do not reject an unused ambiguity in a star export set.
// The caller has already resolved and loaded every reachable module.
pub fn validate(
  modules : Array[(String, Array[@ast.Stmt])],
) -> Unit raise LinkError {
  let graph : Map[String, ModuleInfo] = Map([])
  for (key, stmts) in modules {
    graph[key] = describe(key, stmts)
  }
  for _, info in graph {
    for _, (target, loc) in info.imports {
      if target is Indirect(source, name) {
        require_resolution(graph, info.key, source, name, loc)
      }
    }
    for name, (target, loc) in info.exports {
      if target is Indirect(_, _) {
        require_resolution(graph, info.key, info.key, name, loc)
      }
    }
  }
}
