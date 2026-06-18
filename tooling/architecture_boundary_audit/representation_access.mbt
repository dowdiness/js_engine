///|
const REPRESENTATION_ACCESS_SCHEMA_VERSION = 1

///|
struct RepresentationPattern {
  id : String
  pattern : String
  kind : String
  reason : String
  tokens : Array[String]
} derive(Debug)

///|
struct RepresentationDebt {
  path : String
  pattern_id : String
  allowed_count : Int
  fingerprint : String
  owner : String
  retire_by_stage : String
  reason : String
} derive(Debug)

///|
struct RepresentationRules {
  scan_roots : Array[String]
  ignore_globs : Array[String]
  representation_patterns : Array[RepresentationPattern]
  allowlisted_access : Array[RepresentationDebt]
} derive(Debug)

///|
struct RepresentationAccess {
  path : String
  line : Int
  pattern_id : String
  kind : String
  reason : String
  token : String
  signature : String
} derive(Debug)

///|
fn representation_path(root : String) -> String {
  @path_utils.join_path(root, "scripts/architecture_representation_access.json")
}

///|
fn decode_int_field(
  data : Map[String, Json],
  key : String,
  path : String,
) -> Int raise {
  @json.from_json(require_field(data, key, path)) catch {
    _ => schema_error(path, "\{key} must be an integer")
  }
}

///|
fn validate_representation_schema_version(
  data : Map[String, Json],
  path : String,
) -> Unit raise {
  let version : Int = @json.from_json(require_field(data, "version", path)) catch {
    _ => schema_error(path, "version must be an integer")
  }
  if version != REPRESENTATION_ACCESS_SCHEMA_VERSION {
    schema_error(
      path,
      "version must be \{REPRESENTATION_ACCESS_SCHEMA_VERSION}",
    )
  }
}

///|
fn pattern_tokens(pattern : String) -> Array[String] {
  let tokens : Array[String] = []
  for raw in pattern.split("|") {
    let token = raw.trim().to_owned()
    if token != "" {
      tokens.push(token)
    }
  }
  tokens
}

///|
fn decode_representation_pattern(
  data : Map[String, Json],
  path : String,
) -> RepresentationPattern raise {
  let id = decode_string_field(data, "id", path)
  let pattern = decode_string_field(data, "pattern", path)
  let kind = decode_string_field(data, "kind", path)
  let reason = decode_string_field(data, "reason", path)
  let tokens = pattern_tokens(pattern)
  if id == "" {
    schema_error(path, "representation pattern id must not be empty")
  }
  if tokens.length() == 0 {
    schema_error(
      path,
      "representation pattern \{id} must list at least one token",
    )
  }
  if kind == "" {
    schema_error(path, "representation pattern \{id} kind must not be empty")
  }
  if reason == "" {
    schema_error(path, "representation pattern \{id} reason must not be empty")
  }
  { id, pattern, kind, reason, tokens }
}

///|
fn decode_representation_debt(
  data : Map[String, Json],
  path : String,
) -> RepresentationDebt raise {
  let path_value = normalize_rel_path(decode_string_field(data, "path", path))
  let pattern_id = decode_string_field(data, "pattern_id", path)
  let allowed_count = decode_int_field(data, "allowed_count", path)
  let fingerprint = decode_string_field(data, "fingerprint", path)
  let owner = decode_string_field(data, "owner", path)
  let retire_by_stage = decode_string_field(data, "retire_by_stage", path)
  let reason = decode_string_field(data, "reason", path)
  if path_value == "" || path_value == "." {
    schema_error(path, "allowlisted representation path must be a file path")
  }
  if pattern_id == "" {
    schema_error(
      path, "allowlisted representation pattern_id must not be empty",
    )
  }
  if allowed_count <= 0 {
    schema_error(
      path, "allowlisted representation allowed_count must be positive",
    )
  }
  if fingerprint == "" {
    schema_error(
      path, "allowlisted representation fingerprint must not be empty",
    )
  }
  if owner == "" {
    schema_error(path, "allowlisted representation owner must not be empty")
  }
  if retire_by_stage == "" {
    schema_error(
      path, "allowlisted representation retire_by_stage must not be empty",
    )
  }
  if reason == "" {
    schema_error(path, "allowlisted representation reason must not be empty")
  }
  {
    path: path_value,
    pattern_id,
    allowed_count,
    fingerprint,
    owner,
    retire_by_stage,
    reason,
  }
}

///|
fn representation_pattern_exists(
  patterns : Array[RepresentationPattern],
  id : String,
) -> Bool {
  patterns.any(pattern => pattern.id == id)
}

///|
fn validate_representation_rules(
  rules : RepresentationRules,
  path : String,
) -> Unit raise {
  if rules.scan_roots.length() == 0 {
    schema_error(path, "scan_roots must list at least one root")
  }
  if rules.representation_patterns.length() == 0 {
    schema_error(path, "representation_patterns must list at least one pattern")
  }
  let seen_patterns : Map[String, Unit] = {}
  for pattern in rules.representation_patterns {
    if seen_patterns.contains(pattern.id) {
      schema_error(path, "duplicate representation pattern id: \{pattern.id}")
    }
    seen_patterns[pattern.id] = ()
  }
  let seen_debt : Map[String, Unit] = {}
  for debt in rules.allowlisted_access {
    if !representation_pattern_exists(
        rules.representation_patterns,
        debt.pattern_id,
      ) {
      schema_error(
        path,
        "allowlisted representation pattern_id is unknown: \{debt.pattern_id}",
      )
    }
    let key = "\{debt.path}:\{debt.pattern_id}"
    if seen_debt.contains(key) {
      schema_error(path, "duplicate allowlisted representation access: \{key}")
    }
    seen_debt[key] = ()
  }
}

///|
fn load_representation_rules(root : String) -> RepresentationRules raise {
  let path = representation_path(root)
  let data = decode_object(@json.parse(@fs.read_file_to_string(path)), path)
  validate_representation_schema_version(data, path)
  let scan_roots = decode_string_array_field(data, "scan_roots", path).map(root => {
    normalize_rel_path(root)
  })
  let ignore_globs = decode_string_array_field(data, "ignore_globs", path)
  let raw_patterns = decode_object_array_field(
    data, "representation_patterns", path,
  )
  let raw_debt = decode_object_array_field(data, "allowlisted_access", path)
  let rules = {
    scan_roots,
    ignore_globs,
    representation_patterns: raw_patterns.map(pattern => {
      decode_representation_pattern(pattern, path)
    }),
    allowlisted_access: raw_debt.map(debt => {
      decode_representation_debt(debt, path)
    }),
  }
  validate_representation_rules(rules, path)
  rules
}

///|
fn is_ascii_identifier_char(ch : UInt16) -> Bool {
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  (ch >= '0' && ch <= '9') ||
  ch == '_'
}

///|
fn token_match_has_boundaries(
  line : String,
  token : String,
  index : Int,
) -> Bool {
  let left_ok = if is_ascii_identifier_char(token[0]) {
    index == 0 || !is_ascii_identifier_char(line[index - 1])
  } else {
    true
  }
  let end = index + token.length()
  let last = token[token.length() - 1]
  let right_ok = if is_ascii_identifier_char(last) {
    end >= line.length() || !is_ascii_identifier_char(line[end])
  } else {
    true
  }
  left_ok && right_ok
}

///|
fn starts_with_at(line : String, token : String, index : Int) -> Bool {
  let end = index + token.length()
  end <= line.length() && line[index:end].to_owned() == token
}

///|
fn is_multiline_string_content_line(line : String) -> Bool {
  let trimmed = line.trim().to_owned()
  trimmed.has_prefix("#|") || trimmed.has_prefix("$|")
}

///|
fn find_block_comment_close(line : String, start : Int) -> Int? {
  let len = line.length()
  let mut index = start
  while index + 1 < len {
    if line[index] == '*' && line[index + 1] == '/' {
      return Some(index)
    }
    index += 1
  }
  None
}

///|
fn code_without_comments(line : String) -> String {
  if is_multiline_string_content_line(line) {
    return ""
  }
  let len = line.length()
  let parts : Array[String] = []
  let mut segment_start = 0
  let mut index = 0
  let mut in_string = false
  let mut escaped = false
  while index < len {
    if in_string {
      if escaped {
        escaped = false
      } else if line[index] == '\\' {
        escaped = true
      } else if line[index] == '"' {
        in_string = false
      }
      index += 1
    } else if line[index] == '"' {
      in_string = true
      index += 1
    } else if line[index] == '/' && index + 1 < len && line[index + 1] == '/' {
      parts.push(line[segment_start:index].to_owned())
      return parts.join("")
    } else if line[index] == '/' && index + 1 < len && line[index + 1] == '*' {
      parts.push(line[segment_start:index].to_owned())
      match find_block_comment_close(line, index + 2) {
        Some(close) => {
          index = close + 2
          segment_start = index
        }
        None => return parts.join("")
      }
    } else {
      index += 1
    }
  }
  parts.push(line[segment_start:].to_owned())
  parts.join("")
}

///|
fn representation_signature_line(line : String) -> String {
  code_without_comments(line).trim().to_owned()
}

///|
fn count_token_in_code_line(line : String, token : String) -> Int {
  let code = code_without_comments(line)
  let len = code.length()
  let mut index = 0
  let mut count = 0
  let mut in_string = false
  let mut escaped = false
  while index < len {
    if in_string {
      if escaped {
        escaped = false
      } else if code[index] == '\\' {
        escaped = true
      } else if code[index] == '"' {
        in_string = false
      }
      index += 1
    } else if code[index] == '"' {
      in_string = true
      index += 1
    } else if starts_with_at(code, token, index) &&
      token_match_has_boundaries(code, token, index) {
      count += 1
      index += token.length()
    } else {
      index += 1
    }
  }
  count
}

///|
fn representation_ignore_glob_matches(glob : String, rel_path : String) -> Bool {
  match glob {
    "**/*_test.mbt" => rel_path.has_suffix("_test.mbt")
    "**/*_wbtest.mbt" => rel_path.has_suffix("_wbtest.mbt")
    "**/pkg.generated.mbti" => rel_path.has_suffix("pkg.generated.mbti")
    _ => normalize_rel_path(glob) == rel_path
  }
}

///|
fn should_ignore_representation_path(
  rel_path : String,
  rules : RepresentationRules,
) -> Bool {
  rules.ignore_globs.any(glob => {
    representation_ignore_glob_matches(glob, rel_path)
  })
}

///|
fn collect_representation_files(
  root : String,
  rel_path : String,
  rules : RepresentationRules,
  out : Array[String],
) -> Unit raise {
  let full_path = @path_utils.join_path(root, rel_path)
  if @fs.is_file(full_path) {
    if rel_path.has_suffix(".mbt") &&
      !should_ignore_representation_path(rel_path, rules) {
      out.push(rel_path)
    }
  } else if @fs.is_dir(full_path) && !should_skip_dir(rel_path) {
    let entries = @fs.read_dir(full_path)
    entries.sort()
    for entry in entries {
      if !entry.has_prefix(".") {
        collect_representation_files(
          root,
          @path_utils.join_path(rel_path, entry),
          rules,
          out,
        )
      }
    }
  }
}

///|
fn discover_representation_files(
  root : String,
  rules : RepresentationRules,
) -> Array[String] raise {
  let files : Array[String] = []
  let metadata_path = representation_path(root)
  for scan_root in rules.scan_roots {
    let full_path = @path_utils.join_path(root, scan_root)
    if !@fs.path_exists(full_path) {
      schema_error(metadata_path, "scan root not found: \{scan_root}")
    }
    collect_representation_files(root, scan_root, rules, files)
  }
  files.sort()
  files
}

///|
fn scan_representation_file(
  root : String,
  rel_path : String,
  rules : RepresentationRules,
  out : Array[RepresentationAccess],
) -> Unit raise {
  let source = @fs.read_file_to_string(@path_utils.join_path(root, rel_path))
  let lines = source.split("\n").map(line => line.to_owned()).to_array()
  for line_index, line in lines {
    let line_number = line_index + 1
    let signature_line = representation_signature_line(line)
    for pattern in rules.representation_patterns {
      for token in pattern.tokens {
        let matches = count_token_in_code_line(line, token)
        for _i in 0..<matches {
          out.push({
            path: rel_path,
            line: line_number,
            pattern_id: pattern.id,
            kind: pattern.kind,
            reason: pattern.reason,
            token,
            signature: "\{token}:\{signature_line}",
          })
        }
      }
    }
  }
}

///|
fn discover_representation_accesses(
  root : String,
  rules : RepresentationRules,
) -> Array[RepresentationAccess] raise {
  let accesses : Array[RepresentationAccess] = []
  for rel_path in discover_representation_files(root, rules) {
    scan_representation_file(root, rel_path, rules, accesses)
  }
  accesses.sort_by(fn(a, b) {
    let ak = "\{a.path}:\{a.line}:\{a.pattern_id}:\{a.token}"
    let bk = "\{b.path}:\{b.line}:\{b.pattern_id}:\{b.token}"
    ak.compare(bk)
  })
  accesses
}

///|
fn representation_area(path : String) -> String {
  if path.has_prefix("compiler/") || path == "compiler" {
    "compiler"
  } else if path.has_prefix("interpreter/stdlib/") ||
    path == "interpreter/stdlib" {
    "stdlib"
  } else {
    "unknown"
  }
}

///|
fn representation_access_key(access : RepresentationAccess) -> String {
  "\{access.path}:\{access.pattern_id}"
}

///|
fn representation_debt_key(debt : RepresentationDebt) -> String {
  "\{debt.path}:\{debt.pattern_id}"
}

///|
fn representation_debt_for_key(
  rules : RepresentationRules,
  key : String,
) -> RepresentationDebt? {
  for debt in rules.allowlisted_access {
    if representation_debt_key(debt) == key {
      return Some(debt)
    }
  }
  None
}

///|
fn representation_access_counts(
  accesses : Array[RepresentationAccess],
) -> Map[String, Int] {
  let counts : Map[String, Int] = {}
  for access in accesses {
    let key = representation_access_key(access)
    let current = match counts.get(key) {
      Some(value) => value
      None => 0
    }
    counts[key] = current + 1
  }
  counts
}

///|
fn fingerprint_hash_part(
  text : String,
  initial : Int,
  multiplier : Int,
  modulo : Int,
) -> Int {
  let mut hash = initial
  for ch in text {
    hash = (hash * multiplier + ch.to_int()) % modulo
  }
  hash
}

///|
fn representation_fingerprint(signatures : Array[String]) -> String {
  let mut h1 = 0
  let mut h2 = 0
  let mut total_len = 0
  for signature in signatures {
    total_len += signature.length()
    h1 = (h1 + fingerprint_hash_part(signature, 17, 31, 1000003)) % 1000003
    h2 = (h2 + fingerprint_hash_part(signature, 29, 37, 1000033)) % 1000033
  }
  "\{signatures.length()}:\{total_len}:\{h1}:\{h2}"
}

///|
fn representation_access_fingerprints(
  accesses : Array[RepresentationAccess],
) -> Map[String, String] {
  let signatures_by_key : Map[String, Array[String]] = {}
  for access in accesses {
    let key = representation_access_key(access)
    match signatures_by_key.get(key) {
      Some(signatures) => signatures.push(access.signature)
      None => signatures_by_key[key] = [access.signature]
    }
  }
  let fingerprints : Map[String, String] = {}
  for key, signatures in signatures_by_key {
    fingerprints[key] = representation_fingerprint(signatures)
  }
  fingerprints
}

///|
fn representation_fingerprint_matches(
  debt : RepresentationDebt,
  access_counts : Map[String, Int],
  access_fingerprints : Map[String, String],
) -> Bool {
  let key = representation_debt_key(debt)
  match (access_counts.get(key), access_fingerprints.get(key)) {
    (Some(count), Some(fingerprint)) =>
      count == debt.allowed_count && fingerprint == debt.fingerprint
    _ => false
  }
}

///|
fn representation_debt_list_line(
  access : RepresentationAccess,
  debt : RepresentationDebt,
) -> String {
  "\{access.path}:\{access.line} [\{representation_area(access.path)}] \{access.pattern_id}: \{access.token} -- DEBT \{debt.retire_by_stage} (owner: \{debt.owner}): \{debt.reason}"
}

///|
fn representation_unclassified_list_line(
  access : RepresentationAccess,
) -> String {
  "\{access.path}:\{access.line} [\{representation_area(access.path)}] \{access.pattern_id}: \{access.token} -- UNCLASSIFIED"
}

///|
fn representation_failure_line(access : RepresentationAccess) -> String {
  "- \{access.path}:\{access.line} [\{representation_area(access.path)}] \{access.pattern_id}: \{access.token}"
}

///|
fn render_representation_report(
  accesses : Array[RepresentationAccess],
  rules : RepresentationRules,
  list_representation~ : Bool,
) -> (Array[String], Array[String], Int) {
  let stdout_lines : Array[String] = []
  let stderr_lines : Array[String] = []
  let unclassified : Array[RepresentationAccess] = []
  let access_counts = representation_access_counts(accesses)
  let access_fingerprints = representation_access_fingerprints(accesses)
  let seen_counts : Map[String, Int] = {}
  for access in accesses {
    let key = representation_access_key(access)
    let ordinal = match seen_counts.get(key) {
      Some(value) => value + 1
      None => 1
    }
    seen_counts[key] = ordinal
    match representation_debt_for_key(rules, key) {
      Some(debt) =>
        if ordinal <= debt.allowed_count &&
          representation_fingerprint_matches(
            debt, access_counts, access_fingerprints,
          ) {
          if list_representation {
            stdout_lines.push(representation_debt_list_line(access, debt))
          }
        } else {
          if list_representation {
            stdout_lines.push(representation_unclassified_list_line(access))
          }
          unclassified.push(access)
        }
      None => {
        if list_representation {
          stdout_lines.push(representation_unclassified_list_line(access))
        }
        unclassified.push(access)
      }
    }
  }

  let stale : Array[RepresentationDebt] = []
  for debt in rules.allowlisted_access {
    if !representation_fingerprint_matches(
        debt, access_counts, access_fingerprints,
      ) {
      stale.push(debt)
    }
  }
  stale.sort_by(fn(a, b) {
    representation_debt_key(a).compare(representation_debt_key(b))
  })

  if unclassified.length() > 0 || stale.length() > 0 {
    stderr_lines.push("architecture representation audit failed:")
    if unclassified.length() > 0 {
      stderr_lines.push("")
      stderr_lines.push("unclassified representation access:")
      for access in unclassified {
        stderr_lines.push(representation_failure_line(access))
      }
    }
    if stale.length() > 0 {
      stderr_lines.push("")
      stderr_lines.push("stale allowlist entries:")
      for debt in stale {
        let key = representation_debt_key(debt)
        let found = match access_counts.get(key) {
          Some(value) => value
          None => 0
        }
        let found_fingerprint = match access_fingerprints.get(key) {
          Some(value) => value
          None => "none"
        }
        stderr_lines.push(
          "- \{key} expected \{debt.allowed_count}/\{debt.fingerprint}, found \{found}/\{found_fingerprint}",
        )
      }
    }
    (stdout_lines, stderr_lines, 1)
  } else {
    stdout_lines.push(
      "ok: architecture representation access matches inventory (\{accesses.length()} classified accesses)",
    )
    (stdout_lines, stderr_lines, 0)
  }
}

///|
fn run_import_boundary(
  root~ : String,
  list_imports~ : Bool,
) -> (Array[String], Array[String], Int) raise {
  let rules = load_rules(root)
  let edges = discover_import_edges(root)
  render_import_report(edges, rules, list_imports~)
}

///|
fn run_representation_access(
  root~ : String,
  list_representation~ : Bool,
) -> (Array[String], Array[String], Int) raise {
  let rules = load_representation_rules(root)
  let accesses = discover_representation_accesses(root, rules)
  render_representation_report(accesses, rules, list_representation~)
}
