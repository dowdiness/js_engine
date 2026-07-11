///|
struct ParityCase {
  name : String
  filepath : String
  features : Array[String]
  flags : Array[String]
  mode : String?
  reason : String?
} derive(Debug)

///|
fn parity_string_field(data : Map[String, Json], key : String) -> String raise {
  match data.get(key) {
    Some(raw) =>
      @json.from_json(raw) catch {
        _ => fail("parity case field must be string: \{key}")
      }
    None => fail("missing parity case field: \{key}")
  }
}

///|
fn parity_string_array_field(
  data : Map[String, Json],
  key : String,
) -> Array[String] raise {
  match data.get(key) {
    Some(raw) =>
      @json.from_json(raw) catch {
        _ => fail("parity case field must be string array: \{key}")
      }
    None => []
  }
}

///|
fn parity_optional_string_field(
  data : Map[String, Json],
  key : String,
) -> String? raise {
  match data.get(key) {
    Some(raw) =>
      if raw == Json::null() {
        None
      } else {
        Some(
          @json.from_json(raw) catch {
            _ => fail("parity case field must be string or null: \{key}")
          },
        )
      }
    None => None
  }
}

///|
fn decode_parity_case(data : Map[String, Json]) -> ParityCase raise {
  {
    name: parity_string_field(data, "name"),
    filepath: parity_string_field(data, "filepath"),
    features: parity_string_array_field(data, "features"),
    flags: parity_string_array_field(data, "flags"),
    mode: parity_optional_string_field(data, "mode"),
    reason: parity_optional_string_field(data, "reason"),
  }
}

///|
fn load_parity_cases(path : String) -> Array[ParityCase] raise {
  let raw_cases : Array[Map[String, Json]] = @json.from_json(
    @json.parse(@fs.read_file_to_string(path)),
  )
  raw_cases.map(decode_parity_case)
}

///|
test "loads strict shared skip metadata JSON" {
  let metadata = load_skip_metadata(root=".")
  assert_true(metadata.features.contains("BigInt"))
  assert_true(metadata.flags.contains("CanBlockIsFalse"))
  assert_true(metadata.flags.contains("CanBlockIsTrue"))
  assert_true(metadata.path_suffixes.length() > 0) // async-iteration failing paths
}

///|
test "skip_reason matches shared parity cases" {
  let metadata = load_skip_metadata(root=".")
  let cases = load_parity_cases(
    "scripts/test262_skip_metadata_parity_cases.json",
  )
  assert_true(cases.length() > 0)
  for case in cases {
    let reason = metadata.skip_reason(
      case.filepath,
      case.features,
      case.flags,
      case.mode,
    )
    guard reason == case.reason else {
      fail(
        "parity case failed: \{case.name}; got \{to_repr(reason)}, expected \{to_repr(case.reason)}",
      )
    }
  }
}
