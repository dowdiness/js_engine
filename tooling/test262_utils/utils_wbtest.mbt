///|
struct ParseFrontmatterCase {
  name : String
  source : String
  expected : Json
} derive(Debug)

///|
struct AsListCase {
  name : String
  input : Json
  expected : Array[Json]
} derive(Debug)

///|
struct UtilityParityCases {
  parse_cases : Array[ParseFrontmatterCase]
  as_list_cases : Array[AsListCase]
} derive(Debug)

///|
fn fixture_field(data : Map[String, Json], key : String) -> Json raise {
  match data.get(key) {
    Some(value) => value
    None => fail("missing fixture field: \{key}")
  }
}

///|
fn fixture_string(data : Map[String, Json], key : String) -> String raise {
  @json.from_json(fixture_field(data, key)) catch {
    _ => fail("fixture field must be string: \{key}")
  }
}

///|
fn decode_parse_case(data : Map[String, Json]) -> ParseFrontmatterCase raise {
  {
    name: fixture_string(data, "name"),
    source: fixture_string(data, "source"),
    expected: fixture_field(data, "expected"),
  }
}

///|
fn decode_as_list_case(data : Map[String, Json]) -> AsListCase raise {
  {
    name: fixture_string(data, "name"),
    input: fixture_field(data, "input"),
    expected: @json.from_json(fixture_field(data, "expected")) catch {
      _ => fail("as_list expected field must be array")
    },
  }
}

///|
fn load_utility_parity_cases(path : String) -> UtilityParityCases raise {
  let root : Map[String, Json] = @json.from_json(
    @json.parse(@fs.read_file_to_string(path)),
  )
  let parse_raw : Array[Map[String, Json]] = @json.from_json(
    fixture_field(root, "parse_yaml_frontmatter"),
  )
  let as_list_raw : Array[Map[String, Json]] = @json.from_json(
    fixture_field(root, "as_list"),
  )
  {
    parse_cases: parse_raw.map(decode_parse_case),
    as_list_cases: as_list_raw.map(decode_as_list_case),
  }
}

///|
fn parsed_frontmatter_to_json(value : Map[String, Json]?) -> Json {
  match value {
    Some(data) => Json::object(data)
    None => Json::null()
  }
}

///|
fn assert_json_equal(
  name : String,
  actual : Json,
  expected : Json,
) -> Unit raise {
  guard Json::equal(actual, expected) else {
    fail("\{name}; got \{actual.stringify()}, expected \{expected.stringify()}")
  }
}

///|
test "parse_yaml_frontmatter matches shared fallback parity fixtures" {
  let cases = load_utility_parity_cases(
    "scripts/test262_utils_parity_cases.json",
  )
  assert_true(cases.parse_cases.length() > 0)
  for case in cases.parse_cases {
    assert_json_equal(
      case.name,
      parsed_frontmatter_to_json(parse_yaml_frontmatter(case.source)),
      case.expected,
    )
  }
}

///|
test "as_list matches shared parity fixtures" {
  let cases = load_utility_parity_cases(
    "scripts/test262_utils_parity_cases.json",
  )
  assert_true(cases.as_list_cases.length() > 0)
  for case in cases.as_list_cases {
    assert_json_equal(
      case.name,
      Json::array(as_list(Some(case.input))),
      Json::array(case.expected),
    )
  }
}
