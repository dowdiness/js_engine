///|
const SKIP_METADATA_SCHEMA_VERSION = 1

///|
/// Parsed shared Test262 skip metadata.
///
/// Keep the fields private so consumers use `skip_reason` instead of copying
/// classification logic.
pub struct SkipMetadata {
  priv features : Map[String, Bool]
  priv flags : Map[String, Bool]
  priv path_suffixes : Map[String, String]
} derive(Debug)

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
fn skip_metadata_path(root~ : String) -> String {
  join_path(root, "scripts/test262_skip_metadata.json")
}

///|
fn[T] schema_error(path : String, message : String) -> T raise {
  fail("\{path}: \{message}")
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
fn validate_schema_keys(data : Map[String, Json], path : String) -> Unit raise {
  let allowed : Map[String, Bool] = {
    "schema_version": true,
    "skip_features": true,
    "skip_flags": true,
    "skip_path_suffixes": true,
  }
  for key, _ in data {
    if !allowed.contains(key) {
      schema_error(path, "unknown key: \{key}")
    }
  }
  for key, _ in allowed {
    if !data.contains(key) {
      schema_error(path, "missing key: \{key}")
    }
  }
}

///|
fn decode_schema_version(data : Map[String, Json], path : String) -> Unit raise {
  let raw = require_field(data, "schema_version", path)
  let version : Int = @json.from_json(raw) catch {
    _ => schema_error(path, "schema_version must be an integer")
  }
  if version != SKIP_METADATA_SCHEMA_VERSION {
    schema_error(path, "schema_version must be \{SKIP_METADATA_SCHEMA_VERSION}")
  }
}

///|
fn decode_string_array(
  data : Map[String, Json],
  key : String,
  path : String,
) -> Array[String] raise {
  let raw = require_field(data, key, path)
  let values : Array[String] = @json.from_json(raw) catch {
    _ => schema_error(path, "\{key} must be an array of strings")
  }
  let seen : Map[String, Bool] = {}
  for value in values {
    if seen.contains(value) {
      schema_error(path, "\{key} must not contain duplicate entries: \{value}")
    }
    seen[value] = true
  }
  values
}

///|
fn decode_string_map(
  data : Map[String, Json],
  key : String,
  path : String,
) -> Map[String, String] raise {
  let raw = require_field(data, key, path)
  @json.from_json(raw) catch {
    _ => schema_error(path, "\{key} must be an object of string reasons")
  }
}

///|
fn string_membership(values : Array[String]) -> Map[String, Bool] {
  let out : Map[String, Bool] = {}
  for value in values {
    out[value] = true
  }
  out
}

///|
fn load_skip_metadata_file(path : String) -> SkipMetadata raise {
  let data = decode_object(@json.parse(@fs.read_file_to_string(path)), path)
  validate_schema_keys(data, path)
  decode_schema_version(data, path)
  {
    features: string_membership(
      decode_string_array(data, "skip_features", path),
    ),
    flags: string_membership(decode_string_array(data, "skip_flags", path)),
    path_suffixes: decode_string_map(data, "skip_path_suffixes", path),
  }
}

///|
/// Load shared Test262 skip metadata from `scripts/test262_skip_metadata.json`
/// under `root`.
pub fn load_skip_metadata(root~ : String) -> SkipMetadata raise {
  load_skip_metadata_file(skip_metadata_path(root~))
}

///|
/// Return the metadata skip reason for one Test262 file, or `None` when the
/// metadata does not skip it. `mode` should be `Some("strict")`,
/// `Some("non-strict")`, or `None` for analyzer-style census mode.
pub fn SkipMetadata::skip_reason(
  self : SkipMetadata,
  filepath : String,
  features : ArrayView[String],
  flags : ArrayView[String],
  mode : String?,
) -> String? {
  if filepath.contains("_FIXTURE") {
    return Some("fixture file")
  }

  let normalized_path = filepath.replace_all(old="\\", new="/")
  for suffix, reason in self.path_suffixes {
    if normalized_path.has_suffix(suffix) {
      return Some(reason)
    }
  }

  for flag in flags {
    if self.flags.contains(flag) {
      return Some("unsupported flag: \{flag}")
    }
  }

  match mode {
    Some("non-strict") =>
      if flags.any(flag => flag == "onlyStrict") {
        return Some("requires strict mode")
      }
    Some("strict") =>
      if flags.any(flag => flag == "noStrict") {
        return Some("cannot run in strict mode")
      }
    _ => ()
  }

  for feature in features {
    if self.features.contains(feature) {
      return Some("unsupported feature: \{feature}")
    }
  }

  None
}
