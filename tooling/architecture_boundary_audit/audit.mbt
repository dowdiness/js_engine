///|
const BOUNDARY_RULES_SCHEMA_VERSION = 1

///|
struct PackageGroup {
  name : String
  packages : Array[String]
} derive(Debug)

///|
struct ImportRule {
  from : String
  to : String
  scope : String
  reason : String
} derive(Debug)

///|
struct ImportDebt {
  from : String
  to : String
  scope : String
  owner : String
  retire_by_stage : String
  reason : String
} derive(Debug)

///|
struct BoundaryRules {
  groups : Array[PackageGroup]
  allowed_imports : Array[ImportRule]
  allowlisted_import_debt : Array[ImportDebt]
} derive(Debug)

///|
struct ImportEdge {
  from : String
  to : String
  import_path : String
  scope : String
  manifest_path : String
  is_local : Bool
} derive(Debug)

///|
enum ImportClassification {
  Allowed(String)
  Debt(retire_by_stage~ : String, String)
  Ignored(String)
  Unclassified
} derive(Debug)

///|
fn[T] schema_error(path : String, message : String) -> T raise {
  fail("\{path}: \{message}")
}

///|
fn join_path(left : String, right : String) -> String {
  if left == "" || left == "." {
    right
  } else if left.has_suffix("/") {
    left + right
  } else {
    left + "/" + right
  }
}

///|
fn normalize_rel_path(path : String) -> String {
  let normalized = path.replace_all(old="\\", new="/")
  if normalized == "" {
    "."
  } else if normalized.has_prefix("./") {
    normalize_rel_path(normalized[2:].to_owned())
  } else if normalized.has_suffix("/") {
    normalize_rel_path(normalized[:normalized.length() - 1].to_owned())
  } else {
    normalized
  }
}

///|
fn manifest_rel_path(rel_dir : String) -> String {
  if rel_dir == "." || rel_dir == "" {
    "moon.pkg"
  } else {
    join_path(rel_dir, "moon.pkg")
  }
}

///|
fn rules_path(root : String) -> String {
  join_path(root, "scripts/architecture_boundary_rules.json")
}

///|
fn decode_object(json : Json, path : String) -> Map[String, Json] raise {
  @json.from_json(json) catch {
    _ => schema_error(path, "metadata must be a JSON object")
  }
}

///|
fn require_field(
  data : Map[String, Json],
  key : String,
  path : String,
) -> Json raise {
  match data.get(key) {
    Some(value) => value
    None => schema_error(path, "missing key: \{key}")
  }
}

///|
fn decode_string_field(
  data : Map[String, Json],
  key : String,
  path : String,
) -> String raise {
  @json.from_json(require_field(data, key, path)) catch {
    _ => schema_error(path, "\{key} must be a string")
  }
}

///|
fn decode_string_array_field(
  data : Map[String, Json],
  key : String,
  path : String,
) -> Array[String] raise {
  @json.from_json(require_field(data, key, path)) catch {
    _ => schema_error(path, "\{key} must be an array of strings")
  }
}

///|
fn decode_object_array_field(
  data : Map[String, Json],
  key : String,
  path : String,
) -> Array[Map[String, Json]] raise {
  @json.from_json(require_field(data, key, path)) catch {
    _ => schema_error(path, "\{key} must be an array of objects")
  }
}

///|
fn validate_scope(scope : String, path : String) -> Unit raise {
  match scope {
    "prod" | "test" | "wbtest" | "any" => ()
    _ =>
      schema_error(path, "scope must be prod, test, wbtest, or any: \{scope}")
  }
}

///|
fn validate_schema_version(
  data : Map[String, Json],
  path : String,
) -> Unit raise {
  let version : Int = @json.from_json(require_field(data, "version", path)) catch {
    _ => schema_error(path, "version must be an integer")
  }
  if version != BOUNDARY_RULES_SCHEMA_VERSION {
    schema_error(path, "version must be \{BOUNDARY_RULES_SCHEMA_VERSION}")
  }
}

///|
fn decode_package_group(
  data : Map[String, Json],
  path : String,
) -> PackageGroup raise {
  let name = decode_string_field(data, "name", path)
  let packages = decode_string_array_field(data, "packages", path)
  if name == "" {
    schema_error(path, "package group name must not be empty")
  }
  if packages.length() == 0 {
    schema_error(path, "package group \{name} must list at least one package")
  }
  { name, packages }
}

///|
fn decode_import_rule(
  data : Map[String, Json],
  path : String,
) -> ImportRule raise {
  let from = normalize_rel_path(decode_string_field(data, "from", path))
  let to = normalize_rel_path(decode_string_field(data, "to", path))
  let scope = decode_string_field(data, "scope", path)
  validate_scope(scope, path)
  let reason = decode_string_field(data, "reason", path)
  { from, to, scope, reason }
}

///|
fn decode_import_debt(
  data : Map[String, Json],
  path : String,
) -> ImportDebt raise {
  let from = normalize_rel_path(decode_string_field(data, "from", path))
  let to = normalize_rel_path(decode_string_field(data, "to", path))
  let scope = decode_string_field(data, "scope", path)
  validate_scope(scope, path)
  let owner = decode_string_field(data, "owner", path)
  let retire_by_stage = decode_string_field(data, "retire_by_stage", path)
  let reason = decode_string_field(data, "reason", path)
  { from, to, scope, owner, retire_by_stage, reason }
}

///|
fn load_rules(root : String) -> BoundaryRules raise {
  let path = rules_path(root)
  let data = decode_object(@json.parse(@fs.read_file_to_string(path)), path)
  validate_schema_version(data, path)
  let raw_groups = decode_object_array_field(data, "package_groups", path)
  let raw_allowed = decode_object_array_field(data, "allowed_imports", path)
  let raw_debt = decode_object_array_field(
    data, "allowlisted_import_debt", path,
  )
  {
    groups: raw_groups.map(group => decode_package_group(group, path)),
    allowed_imports: raw_allowed.map(rule => decode_import_rule(rule, path)),
    allowlisted_import_debt: raw_debt.map(debt => decode_import_debt(debt, path)),
  }
}

///|
fn module_name(root : String) -> String raise {
  let path = join_path(root, "moon.mod")
  let lines = @fs.read_file_to_string(path)
    .split("\n")
    .map(line => line.to_owned())
    .to_array()
  for line in lines {
    let trimmed = line.trim().to_owned()
    if trimmed.has_prefix("name") {
      let strings = quoted_strings(trimmed)
      guard strings.length() > 0 else {
        schema_error(path, "moon.mod name must be quoted")
      }
      return strings[0]
    }
  }
  schema_error(path, "moon.mod must declare module name")
}

///|
fn is_skipped_dir_segment(segment : String) -> Bool {
  match segment {
    ".git" | ".mooncakes" | "_build" | "test262" | "graphify-out" => true
    _ => false
  }
}

///|
fn should_skip_dir(rel_path : String) -> Bool {
  let parts = rel_path.split("/").map(part => part.to_owned()).to_array()
  parts.any(is_skipped_dir_segment)
}

///|
fn collect_manifest_dirs(
  root : String,
  rel_dir : String,
  out : Array[String],
) -> Unit raise {
  let full_dir = if rel_dir == "." { root } else { join_path(root, rel_dir) }
  let entries = @fs.read_dir(full_dir)
  entries.sort()
  for entry in entries {
    let rel_path = if rel_dir == "." {
      entry
    } else {
      join_path(rel_dir, entry)
    }
    let full_path = join_path(full_dir, entry)
    if entry == "moon.pkg" && @fs.is_file(full_path) {
      out.push(rel_dir)
    } else if @fs.is_dir(full_path) &&
      !should_skip_dir(rel_path) &&
      !entry.has_prefix(".") {
      collect_manifest_dirs(root, rel_path, out)
    }
  }
}

///|
fn discover_manifest_dirs(root : String) -> Array[String] raise {
  let out : Array[String] = []
  collect_manifest_dirs(root, ".", out)
  out.sort()
  out
}

///|
fn quoted_strings(text : String) -> Array[String] {
  let values : Array[String] = []
  let len = text.length()
  let mut index = 0
  while index < len {
    if text[index] == '"' {
      index += 1
      let start = index
      while index < len && text[index] != '"' {
        index += 1
      }
      if index < len {
        values.push(text[start:index].to_owned())
      }
    }
    index += 1
  }
  values
}

///|
fn strip_comment_suffix(text : String) -> String {
  let len = text.length()
  let mut index = 0
  let mut in_string = false
  while index < len {
    if text[index] == '"' {
      in_string = !in_string
      index += 1
    } else if in_string && text[index] == '\\' {
      index += 2
    } else if !in_string && text[index] == '/' && index + 1 < len {
      if text[index + 1] == '/' || text[index + 1] == '*' {
        return text[:index].to_owned()
      }
      index += 1
    } else {
      index += 1
    }
  }
  text
}

///|
fn scope_from_import_close(rest : String) -> String {
  let strings = quoted_strings(strip_comment_suffix(rest))
  if strings.any(value => value == "test") {
    "test"
  } else if strings.any(value => value == "wbtest") {
    "wbtest"
  } else {
    "prod"
  }
}

///|
fn local_import_rel(module_path : String, import_path : String) -> String? {
  if import_path == module_path {
    Some(".")
  } else {
    let prefix = module_path + "/"
    if import_path.has_prefix(prefix) {
      Some(normalize_rel_path(import_path[prefix.length():].to_owned()))
    } else {
      None
    }
  }
}

///|
fn push_import_edges(
  edges : Array[ImportEdge],
  from : String,
  manifest_path : String,
  module_path : String,
  pending_imports : Array[String],
  scope : String,
) -> Unit {
  for import_path in pending_imports {
    match local_import_rel(module_path, import_path) {
      Some(to) =>
        edges.push({
          from,
          to,
          import_path,
          scope,
          manifest_path,
          is_local: true,
        })
      None =>
        edges.push({
          from,
          to: import_path,
          import_path,
          scope,
          manifest_path,
          is_local: false,
        })
    }
  }
}

///|
fn collect_import_strings(text : String, pending : Array[String]) -> Unit {
  for value in quoted_strings(strip_comment_suffix(text)) {
    pending.push(value)
  }
}

///|
fn parse_manifest_import_edges(
  source : String,
  from : String,
  manifest_path : String,
  module_path : String,
) -> Array[ImportEdge] {
  let edges : Array[ImportEdge] = []
  let pending : Array[String] = []
  let lines = source.split("\n").map(line => line.to_owned()).to_array()
  let mut in_import = false
  for raw_line in lines {
    let line = raw_line.trim().to_owned()
    if !in_import {
      guard line.has_prefix("import") && line.contains("{") else { continue }
      in_import = true
      pending.clear()
      let after_open = match line.split_once("{") {
        Some((_, rest)) => rest.to_owned()
        None => ""
      }
      match after_open.split_once("}") {
        Some((before_close, after_close)) => {
          collect_import_strings(before_close.to_owned(), pending)
          let scope = scope_from_import_close(after_close.to_owned())
          push_import_edges(
            edges, from, manifest_path, module_path, pending, scope,
          )
          pending.clear()
          in_import = false
        }
        None => collect_import_strings(after_open, pending)
      }
    } else {
      match line.split_once("}") {
        Some((before_close, after_close)) => {
          collect_import_strings(before_close.to_owned(), pending)
          let scope = scope_from_import_close(after_close.to_owned())
          push_import_edges(
            edges, from, manifest_path, module_path, pending, scope,
          )
          pending.clear()
          in_import = false
        }
        None => collect_import_strings(line, pending)
      }
    }
  }
  edges
}

///|
fn discover_import_edges(root : String) -> Array[ImportEdge] raise {
  let module_path = module_name(root)
  let edges : Array[ImportEdge] = []
  for rel_dir in discover_manifest_dirs(root) {
    let manifest_path = manifest_rel_path(rel_dir)
    let full_path = join_path(root, manifest_path)
    let source = @fs.read_file_to_string(full_path)
    for
      edge in parse_manifest_import_edges(
        source,
        normalize_rel_path(rel_dir),
        manifest_path,
        module_path,
      ) {
      edges.push(edge)
    }
  }
  edges.sort_by(fn(a, b) {
    let ak = "\{a.manifest_path}:\{a.to}:\{a.scope}"
    let bk = "\{b.manifest_path}:\{b.to}:\{b.scope}"
    ak.compare(bk)
  })
  edges
}

///|
fn pattern_matches(pattern : String, pkg : String) -> Bool {
  if pattern == pkg {
    true
  } else if pattern.has_suffix("/*") {
    let prefix = pattern[:pattern.length() - 1].to_owned()
    pkg.has_prefix(prefix)
  } else {
    false
  }
}

///|
fn package_groups_for(rules : BoundaryRules, pkg : String) -> Array[String] {
  let names : Array[String] = []
  for group in rules.groups {
    if group.packages.any(pattern => pattern_matches(pattern, pkg)) {
      names.push(group.name)
    }
  }
  names
}

///|
fn ignored_source_group(groups : Array[String]) -> String? {
  for group in groups {
    match group {
      "commands" | "tooling" | "benchmarks" => return Some(group)
      _ => ()
    }
  }
  None
}

///|
fn scope_matches(rule_scope : String, edge_scope : String) -> Bool {
  rule_scope == "any" || rule_scope == edge_scope
}

///|
fn import_rule_matches(rule : ImportRule, edge : ImportEdge) -> Bool {
  rule.from == edge.from &&
  rule.to == edge.to &&
  scope_matches(rule.scope, edge.scope)
}

///|
fn import_debt_matches(debt : ImportDebt, edge : ImportEdge) -> Bool {
  debt.from == edge.from &&
  debt.to == edge.to &&
  scope_matches(debt.scope, edge.scope)
}

///|
fn classify_import(
  edge : ImportEdge,
  rules : BoundaryRules,
) -> ImportClassification {
  let source_groups = package_groups_for(rules, edge.from)
  match ignored_source_group(source_groups) {
    Some(group) => return Ignored("\{group} package")
    None => ()
  }
  if !edge.is_local {
    let target_groups = package_groups_for(rules, edge.import_path)
    if target_groups.any(group => group == "external") {
      return Ignored("external dependency")
    }
    return Unclassified
  }
  for rule in rules.allowed_imports {
    if import_rule_matches(rule, edge) {
      return Allowed(rule.reason)
    }
  }
  for debt in rules.allowlisted_import_debt {
    if import_debt_matches(debt, edge) {
      return Debt(retire_by_stage=debt.retire_by_stage, debt.reason)
    }
  }
  Unclassified
}

///|
fn import_edge_key(edge : ImportEdge) -> String {
  "\{edge.from} -> \{edge.to} [\{edge.scope}]"
}

///|
fn list_line(edge : ImportEdge, rules : BoundaryRules) -> String {
  let prefix = import_edge_key(edge)
  match classify_import(edge, rules) {
    Allowed(reason) => "\{prefix} -- allowed: \{reason}"
    Debt(retire_by_stage~, reason) =>
      "\{prefix} -- DEBT \{retire_by_stage}: \{reason}"
    Ignored(reason) => "\{prefix} -- ignored: \{reason}"
    Unclassified => "\{prefix} -- UNCLASSIFIED"
  }
}

///|
fn failure_line(edge : ImportEdge) -> String {
  "- \{edge.manifest_path}: \{import_edge_key(edge)}"
}

///|
fn debt_key(debt : ImportDebt) -> String {
  "\{debt.from} -> \{debt.to} [\{debt.scope}]"
}

///|
fn stale_allowlist_entries(
  edges : Array[ImportEdge],
  rules : BoundaryRules,
) -> Array[ImportDebt] {
  let stale : Array[ImportDebt] = []
  for debt in rules.allowlisted_import_debt {
    let found = edges.any(edge => {
      edge.is_local && import_debt_matches(debt, edge)
    })
    if !found {
      stale.push(debt)
    }
  }
  stale.sort_by(fn(a, b) { debt_key(a).compare(debt_key(b)) })
  stale
}

///|
fn render_import_report(
  edges : Array[ImportEdge],
  rules : BoundaryRules,
  list_imports~ : Bool,
) -> (Array[String], Array[String], Int) {
  let stdout_lines : Array[String] = []
  let stderr_lines : Array[String] = []
  if list_imports {
    for edge in edges {
      stdout_lines.push(list_line(edge, rules))
    }
  }

  let unclassified = edges.filter(edge => {
    classify_import(edge, rules) is Unclassified
  })
  let stale = stale_allowlist_entries(edges, rules)
  if unclassified.length() > 0 || stale.length() > 0 {
    stderr_lines.push("architecture boundary audit failed:")
    if unclassified.length() > 0 {
      stderr_lines.push("")
      stderr_lines.push("unclassified imports:")
      for edge in unclassified {
        stderr_lines.push(failure_line(edge))
      }
    }
    if stale.length() > 0 {
      stderr_lines.push("")
      stderr_lines.push("stale allowlist entries:")
      for debt in stale {
        stderr_lines.push("- \{debt_key(debt)}")
      }
    }
    (stdout_lines, stderr_lines, 1)
  } else {
    let local_imports = edges.filter(edge => edge.is_local)
    let debt_count = edges
      .filter(edge => classify_import(edge, rules) is Debt(_))
      .length()
    stdout_lines.push(
      "ok: architecture import boundaries match rules (\{local_imports.length()} imports, \{debt_count} allowlisted debts)",
    )
    (stdout_lines, stderr_lines, 0)
  }
}

///|
fn append_lines(target : Array[String], source : Array[String]) -> Unit {
  for line in source {
    target.push(line)
  }
}

///|
pub fn run(
  root~ : String,
  list_imports~ : Bool,
  list_representation? : Bool = false,
) -> (Array[String], Array[String], Int) raise {
  let stdout_lines : Array[String] = []
  let stderr_lines : Array[String] = []
  let (import_stdout, import_stderr, import_code) = run_import_boundary(
    root~,
    list_imports~,
  )
  append_lines(stdout_lines, import_stdout)
  append_lines(stderr_lines, import_stderr)

  let (rep_stdout, rep_stderr, representation_code) = run_representation_access(
    root~,
    list_representation~,
  )
  append_lines(stdout_lines, rep_stdout)
  append_lines(stderr_lines, rep_stderr)
  let code = if import_code != 0 || representation_code != 0 { 1 } else { 0 }
  (stdout_lines, stderr_lines, code)
}
