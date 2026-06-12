///|
const TAXONOMY_SCHEMA_VERSION = 1

///|
struct PackageDefault {
  pkg : String
  category : String
  reason : String
} derive(Debug)

///|
struct SymbolOverride {
  pkg : String
  symbol : String
  category : String
  reason : String
} derive(Debug)

///|
struct TaxonomyRules {
  package_defaults : Array[PackageDefault]
  symbol_overrides : Array[SymbolOverride]
} derive(Debug)

///|
struct PackageSurface {
  pkg : String
  mbti_path : String
  symbols : Array[String]
} derive(Debug)

///|
enum SurfaceClassification {
  ClassifiedDefault(String, String)
  ClassifiedOverride(String, String)
  Unclassified
} derive(Debug, Eq)

///|
fn taxonomy_rules_path(root : String) -> String {
  join_path(root, "scripts/architecture_surface_taxonomy.json")
}

///|
fn validate_taxonomy_schema_version(
  data : Map[String, Json],
  path : String,
) -> Unit raise {
  let version : Int = @json.from_json(require_field(data, "version", path)) catch {
    _ => schema_error(path, "version must be an integer")
  }
  if version != TAXONOMY_SCHEMA_VERSION {
    schema_error(path, "version must be \{TAXONOMY_SCHEMA_VERSION}")
  }
}

///|
fn decode_package_default(
  data : Map[String, Json],
  path : String,
) -> PackageDefault raise {
  let pkg = decode_string_field(data, "package", path)
  let category = decode_string_field(data, "category", path)
  let reason = decode_string_field(data, "reason", path)
  { pkg, category, reason }
}

///|
fn decode_symbol_override(
  data : Map[String, Json],
  path : String,
) -> SymbolOverride raise {
  let pkg = decode_string_field(data, "package", path)
  let symbol = decode_string_field(data, "symbol", path)
  let category = decode_string_field(data, "category", path)
  let reason = decode_string_field(data, "reason", path)
  { pkg, symbol, category, reason }
}

///|
fn load_taxonomy(root : String) -> TaxonomyRules raise {
  let path = taxonomy_rules_path(root)
  let data = decode_object(@json.parse(@fs.read_file_to_string(path)), path)
  validate_taxonomy_schema_version(data, path)
  let raw_defaults = decode_object_array_field(data, "package_defaults", path)
  let raw_overrides = decode_object_array_field(data, "symbol_overrides", path)
  {
    package_defaults: raw_defaults.map(d => decode_package_default(d, path)),
    symbol_overrides: raw_overrides.map(o => decode_symbol_override(o, path)),
  }
}

///|
fn extract_fn_name_from(after_fn : String) -> String? {
  let name = match after_fn.split_once("(") {
    Some((before, _)) => before.trim().to_owned()
    None => after_fn.trim().to_owned()
  }
  if name == "" {
    None
  } else {
    Some(name)
  }
}

///|
fn extract_mbti_symbol(line : String) -> String? {
  let stripped = if line.has_prefix("pub(all) ") {
    line[9:]
  } else if line.has_prefix("pub ") {
    line[4:]
  } else {
    return None
  }
  let content = stripped.to_owned()
  // Skip trait implementations and re-exports
  if content.has_prefix("impl ") || content.has_prefix("using ") {
    return None
  }
  // Functions: pub fn name(...) or pub fn[T] Type::method(...)
  if content.has_prefix("fn ") || content.has_prefix("fn[") {
    if content.has_prefix("fn[") {
      match content.split_once("]") {
        Some((_, rest)) =>
          extract_fn_name_from(rest.to_owned().trim().to_owned())
        None => None
      }
    } else {
      extract_fn_name_from(content[3:].to_owned())
    }
    // Named types: enum, struct, suberror, typealias
  } else if content.has_prefix("enum ") ||
    content.has_prefix("struct ") ||
    content.has_prefix("suberror ") ||
    content.has_prefix("typealias ") {
    match content.split_once(" ") {
      None => None
      Some((_, after_kw)) => {
        let after_kw = after_kw.to_owned()
        let name = match after_kw.split_once(" ") {
          Some((before, _)) => before.trim().to_owned()
          None =>
            match after_kw.split_once("{") {
              Some((before, _)) => before.trim().to_owned()
              None => after_kw.trim().to_owned()
            }
        }
        if name == "" {
          None
        } else {
          Some(name)
        }
      }
    }
    // Constants: pub const NAME : Type = ...
  } else if content.has_prefix("const ") {
    let after_kw = content[6:].to_owned()
    let name = match after_kw.split_once(" ") {
      Some((before, _)) => before.trim().to_owned()
      None => after_kw.trim().to_owned()
    }
    if name == "" {
      None
    } else {
      Some(name)
    }
  } else {
    None
  }
}

///|
fn parse_mbti(source : String) -> (String, Array[String]) {
  let symbols : Array[String] = []
  let mut pkg_name = ""
  for raw_line in source.split("\n") {
    let line = raw_line.trim().to_owned()
    if line.has_prefix("package ") {
      let strings = quoted_strings(line)
      if strings.length() > 0 {
        pkg_name = strings[0]
      }
    } else {
      match extract_mbti_symbol(line) {
        Some(name) => symbols.push(name)
        None => ()
      }
    }
  }
  (pkg_name, symbols)
}

///|
fn mbti_path_for_dir(rel_dir : String) -> String {
  if rel_dir == "." || rel_dir == "" {
    "pkg.generated.mbti"
  } else {
    join_path(rel_dir, "pkg.generated.mbti")
  }
}

///|
fn collect_mbti_dirs(
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
    if entry == "pkg.generated.mbti" && @fs.is_file(full_path) {
      out.push(rel_dir)
    } else if @fs.is_dir(full_path) &&
      !should_skip_dir(rel_path) &&
      !entry.has_prefix(".") {
      collect_mbti_dirs(root, rel_path, out)
    }
  }
}

///|
fn discover_package_surfaces(root : String) -> Array[PackageSurface] raise {
  let dirs : Array[String] = []
  collect_mbti_dirs(root, ".", dirs)
  dirs.sort()
  let surfaces : Array[PackageSurface] = []
  for rel_dir in dirs {
    let mbti_path = mbti_path_for_dir(rel_dir)
    let full_path = join_path(root, mbti_path)
    let source = @fs.read_file_to_string(full_path)
    let (pkg_name, symbols) = parse_mbti(source)
    if pkg_name != "" {
      surfaces.push({ pkg: pkg_name, mbti_path, symbols })
    }
  }
  surfaces
}

///|
fn taxonomy_pkg_matches(pattern : String, pkg_name : String) -> Bool {
  if pattern == pkg_name {
    true
  } else if pattern.has_suffix("/*") {
    let prefix = pattern[:pattern.length() - 1].to_owned()
    pkg_name.has_prefix(prefix)
  } else {
    false
  }
}

///|
fn find_package_default(
  rules : TaxonomyRules,
  pkg_name : String,
) -> PackageDefault? {
  for def in rules.package_defaults {
    if taxonomy_pkg_matches(def.pkg, pkg_name) {
      return Some(def)
    }
  }
  None
}

///|
fn find_symbol_override(
  rules : TaxonomyRules,
  pkg_name : String,
  symbol : String,
) -> SymbolOverride? {
  for ov in rules.symbol_overrides {
    if ov.pkg == pkg_name && ov.symbol == symbol {
      return Some(ov)
    }
  }
  None
}

///|
fn classify_symbol(
  pkg_name : String,
  symbol : String,
  rules : TaxonomyRules,
) -> SurfaceClassification {
  match find_symbol_override(rules, pkg_name, symbol) {
    Some(ov) => ClassifiedOverride(ov.category, ov.reason)
    None =>
      match find_package_default(rules, pkg_name) {
        Some(def) => ClassifiedDefault(def.category, def.reason)
        None => Unclassified
      }
  }
}

///|
fn stale_symbol_overrides(
  surfaces : Array[PackageSurface],
  rules : TaxonomyRules,
) -> Array[SymbolOverride] {
  let stale : Array[SymbolOverride] = []
  for ov in rules.symbol_overrides {
    let exists = surfaces.any(fn(s) {
      s.pkg == ov.pkg && s.symbols.any(fn(sym) { sym == ov.symbol })
    })
    if !exists {
      stale.push(ov)
    }
  }
  stale.sort_by(fn(a, b) {
    let ak = "\{a.pkg}:\{a.symbol}"
    let bk = "\{b.pkg}:\{b.symbol}"
    ak.compare(bk)
  })
  stale
}

///|
fn render_surface_report(
  surfaces : Array[PackageSurface],
  rules : TaxonomyRules,
  list_surfaces~ : Bool,
) -> (Array[String], Array[String], Int) {
  let stdout_lines : Array[String] = []
  let stderr_lines : Array[String] = []
  if list_surfaces {
    for surface in surfaces {
      for symbol in surface.symbols {
        let key = "\{surface.pkg}: \{symbol}"
        match classify_symbol(surface.pkg, symbol, rules) {
          ClassifiedOverride(category, _reason) =>
            stdout_lines.push("\{key} -- \{category} (override)")
          ClassifiedDefault(category, _reason) =>
            stdout_lines.push("\{key} -- \{category} (package default)")
          Unclassified => stdout_lines.push("\{key} -- UNCLASSIFIED")
        }
      }
    }
  }
  let mut has_unclassified = false
  for surface in surfaces {
    if has_unclassified {
      break
    }
    for symbol in surface.symbols {
      if classify_symbol(surface.pkg, symbol, rules) is Unclassified {
        has_unclassified = true
        break
      }
    }
  }
  let stale = stale_symbol_overrides(surfaces, rules)
  if has_unclassified || stale.length() > 0 {
    stderr_lines.push("architecture surface taxonomy failed:")
    if has_unclassified {
      stderr_lines.push("")
      stderr_lines.push("unclassified public surfaces:")
      for surface in surfaces {
        for symbol in surface.symbols {
          if classify_symbol(surface.pkg, symbol, rules) is Unclassified {
            stderr_lines.push("- package \{surface.pkg}: \{symbol}")
          }
        }
      }
    }
    if stale.length() > 0 {
      stderr_lines.push("")
      stderr_lines.push("stale symbol overrides:")
      for ov in stale {
        stderr_lines.push("- package \{ov.pkg}: \{ov.symbol}")
      }
    }
    (stdout_lines, stderr_lines, 1)
  } else {
    let pkg_count = surfaces.length()
    let mut sym_count = 0
    for surface in surfaces {
      sym_count += surface.symbols.length()
    }
    let mut defaulted_count = 0
    for surface in surfaces {
      match find_package_default(rules, surface.pkg) {
        Some(_) => defaulted_count += 1
        None => ()
      }
    }
    stdout_lines.push(
      "ok: architecture surface taxonomy covers generated interfaces (\{pkg_count} packages, \{sym_count} symbols, \{defaulted_count} package-defaulted)",
    )
    (stdout_lines, stderr_lines, 0)
  }
}

///|
fn run_surface_taxonomy(
  root~ : String,
  list_surfaces~ : Bool,
) -> (Array[String], Array[String], Int) raise {
  let rules = load_taxonomy(root)
  let surfaces = discover_package_surfaces(root)
  render_surface_report(surfaces, rules, list_surfaces~)
}
