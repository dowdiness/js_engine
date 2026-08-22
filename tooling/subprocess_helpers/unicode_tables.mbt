///|
const UNICODE_URL_PREFIX = "https://www.unicode.org/Public/"

///|
const UNICODE_PROPERTIES_URL_SUFFIX = "/ucd/DerivedCoreProperties.txt"

///|
const UNICODE_CASE_FOLDING_URL_SUFFIX = "/ucd/CaseFolding.txt"

///|
const UNICODE_FETCH_TIMEOUT_MS = 120000

///|
const LOOKUP_FNS =
  #|///|
  #|/// Binary search across sorted, non-overlapping `(lo, hi)` ranges.
  #|fn in_ranges(table : ArrayView[(Int, Int)], cp : Int) -> Bool {
  #|  let mut lo = 0
  #|  let mut hi = table.length()
  #|  while lo < hi {
  #|    let mid = (lo + hi) / 2
  #|    let (rlo, rhi) = table[mid]
  #|    if cp < rlo {
  #|      hi = mid
  #|    } else if cp > rhi {
  #|      lo = mid + 1
  #|    } else {
  #|      return true
  #|    }
  #|  }
  #|  false
  #|}
  #|
  #|///|
  #|/// Returns true if `cp` has the Unicode `ID_Start` property (UAX #31 / ES262 §11.6).
  #|fn is_id_start(cp : Int) -> Bool {
  #|  in_ranges(id_start_ranges[:], cp)
  #|}
  #|
  #|///|
  #|/// Returns true if `cp` has the Unicode `ID_Continue` property.
  #|fn is_id_continue(cp : Int) -> Bool {
  #|  in_ranges(id_continue_ranges[:], cp)
  #|}
  #|

///|
const CASE_FOLD_LOOKUP_FNS =
  #|///|
  #|/// ECMAScript RegExp Canonicalize for Unicode ignore-case mode.
  #|fn unicode_simple_fold(cp : Int) -> Int {
  #|  let mut lo = 0
  #|  let mut hi = unicode_simple_fold_mappings.length()
  #|  while lo < hi {
  #|    let mid = (lo + hi) / 2
  #|    let (source, target) = unicode_simple_fold_mappings[mid]
  #|    if cp < source {
  #|      hi = mid
  #|    } else if cp > source {
  #|      lo = mid + 1
  #|    } else {
  #|      return target
  #|    }
  #|  }
  #|  cp
  #|}
  #|
  #|///|
  #|/// Whether some code point in `[range_lo, range_hi]` canonicalizes to
  #|/// `folded_cp`. The inverse table keeps class matching logarithmic in the
  #|/// number of Unicode mappings instead of scanning the full table.
  #|fn unicode_simple_fold_equivalent_in_range(
  #|  folded_cp : Int,
  #|  range_lo : Int,
  #|  range_hi : Int,
  #|) -> Bool {
  #|  if unicode_simple_fold(folded_cp) == folded_cp &&
  #|    folded_cp >= range_lo &&
  #|    folded_cp <= range_hi {
  #|    return true
  #|  }
  #|  let mut lo = 0
  #|  let mut hi = unicode_simple_fold_inverse.length()
  #|  while lo < hi {
  #|    let mid = (lo + hi) / 2
  #|    if unicode_simple_fold_inverse[mid].0 < folded_cp {
  #|      lo = mid + 1
  #|    } else {
  #|      hi = mid
  #|    }
  #|  }
  #|  while lo < unicode_simple_fold_inverse.length() &&
  #|        unicode_simple_fold_inverse[lo].0 == folded_cp {
  #|    let source = unicode_simple_fold_inverse[lo].1
  #|    if source >= range_lo && source <= range_hi {
  #|      return true
  #|    }
  #|    lo += 1
  #|  }
  #|  false
  #|}
  #|

///|
pub struct UnicodeConfig {
  priv unicode_version : String
  priv output : String
  priv case_fold_output : String?
  priv fetch_timeout_ms : Int
} derive(Debug)

///|
pub fn UnicodeConfig::UnicodeConfig(
  unicode_version~ : String,
  output~ : String,
  case_fold_output? : String? = None,
  fetch_timeout_ms? : Int = UNICODE_FETCH_TIMEOUT_MS,
) -> UnicodeConfig {
  { unicode_version, output, case_fold_output, fetch_timeout_ms }
}

///|
fn unicode_properties() -> Array[String] {
  ["ID_Start", "ID_Continue"]
}

///|
fn unicode_data_url(version : String) -> String {
  UNICODE_URL_PREFIX + version + UNICODE_PROPERTIES_URL_SUFFIX
}

///|
fn unicode_case_folding_url(version : String) -> String {
  UNICODE_URL_PREFIX + version + UNICODE_CASE_FOLDING_URL_SUFFIX
}

///|
fn table_name(prop : String) -> String {
  prop.to_lower() + "_ranges"
}

///|
fn parse_codepoint(raw : StringView) -> Int raise {
  @string.parse_int(raw.trim(), base=16)
}

///|
fn parse_range_field(field : StringView) -> (Int, Int) raise {
  match field.split_once("..") {
    Some((lo, hi)) => (parse_codepoint(lo), parse_codepoint(hi))
    None => {
      let cp = parse_codepoint(field)
      (cp, cp)
    }
  }
}

///|
fn merge_ranges(ranges : Array[(Int, Int)]) -> Array[(Int, Int)] {
  if ranges.is_empty() {
    []
  } else {
    let sorted = ranges.copy()
    sorted.sort()
    let merged : Array[(Int, Int)] = [sorted[0]]
    for item in sorted[1:] {
      let lo = item.0
      let hi = item.1
      let prev = merged[merged.length() - 1]
      let prev_lo = prev.0
      let prev_hi = prev.1
      if lo <= prev_hi + 1 {
        merged[merged.length() - 1] = (prev_lo, @cmp.maximum(prev_hi, hi))
      } else {
        merged.push((lo, hi))
      }
    }
    merged
  }
}

///|
fn parse_unicode_property(
  text : String,
  property_name : String,
) -> Array[(Int, Int)] raise {
  let ranges : Array[(Int, Int)] = []
  for raw in splitlines(text) {
    let line = match raw.split_once("#") {
      Some((before, _)) => before.trim().to_owned()
      None => raw.trim().to_owned()
    }
    if line == "" {
      continue
    }
    match line.split_once(";") {
      Some((cp_field, prop_field)) if prop_field.trim() == property_name =>
        ranges.push(parse_range_field(cp_field.trim()))
      _ => ()
    }
  }
  merge_ranges(ranges)
}

///|
/// Parse the Unicode simple/default case-fold mappings used by ECMA-262
/// Canonicalize. Full (`F`) and Turkic (`T`) mappings are deliberately omitted.
fn parse_simple_case_folding(text : String) -> Array[(Int, Int)] raise {
  let mappings : Array[(Int, Int)] = []
  for raw in splitlines(text) {
    let line = match raw.split_once("#") {
      Some((before, _)) => before.trim().to_owned()
      None => raw.trim().to_owned()
    }
    guard line != "" else { continue }
    match line.split_once(";") {
      Some((source_field, rest)) =>
        match rest.split_once(";") {
          Some((status_field, mapping_and_suffix)) => {
            let status = status_field.trim()
            guard status == "C" || status == "S" else { continue }
            let mapping_field = match mapping_and_suffix.split_once(";") {
              Some((mapping, _)) => mapping
              None => mapping_and_suffix
            }
            mappings.push(
              (
                parse_codepoint(source_field.trim()),
                parse_codepoint(mapping_field.trim()),
              ),
            )
          }
          None => ()
        }
      None => ()
    }
  }
  mappings.sort()
  mappings
}

///|
fn hex4(value : Int) -> String {
  value.to_string(radix=16).to_upper().pad_start(4, '0')
}

///|
fn emit_unicode_tables(
  version : String,
  tables : Map[String, Array[(Int, Int)]],
) -> String {
  let lines : Array[String] = []
  lines.push("// AUTOGENERATED by make unicode-tables — do not edit by hand.")
  lines.push("// Source: DerivedCoreProperties.txt @ Unicode " + version)
  lines.push(
    "// Properties: " +
    unicode_properties().join(", ") +
    " (ECMAScript §11.6 / UAX #31 R1)",
  )
  lines.push("")
  for name in unicode_properties() {
    let ranges = match tables.get(name) {
      Some(value) => value
      None => []
    }
    lines.push("///|")
    lines.push(
      "/// " + ranges.length().to_string() + " ranges, sorted and coalesced.",
    )
    lines.push("let " + table_name(name) + " : Array[(Int, Int)] = [")
    for item in ranges {
      lines.push("  (0x" + hex4(item.0) + ", 0x" + hex4(item.1) + "),")
    }
    lines.push("]")
    lines.push("")
  }
  lines.push(LOOKUP_FNS)
  lines.join("\n")
}

///|
fn emit_case_folding_table(
  version : String,
  mappings : Array[(Int, Int)],
) -> String {
  let inverse = mappings.map(pair => (pair.1, pair.0))
  inverse.sort()
  let lines : Array[String] = [
    "// AUTOGENERATED by make unicode-tables — do not edit by hand.",
    "// Source: CaseFolding.txt @ Unicode " + version,
    "// Mappings: status C + S (ECMAScript RegExp Canonicalize)",
    "",
    "///|",
    "/// " + mappings.length().to_string() + " mappings, sorted by source.",
    "let unicode_simple_fold_mappings : Array[(Int, Int)] = [",
  ]
  for mapping in mappings {
    lines.push("  (0x" + hex4(mapping.0) + ", 0x" + hex4(mapping.1) + "),")
  }
  lines.push("]")
  lines.push("")
  lines.push("///|")
  lines.push(
    "/// " +
    inverse.length().to_string() +
    " mappings, sorted by target/source.",
  )
  lines.push("let unicode_simple_fold_inverse : Array[(Int, Int)] = [")
  for mapping in inverse {
    lines.push("  (0x" + hex4(mapping.0) + ", 0x" + hex4(mapping.1) + "),")
  }
  lines.push("]")
  lines.push("")
  lines.push(CASE_FOLD_LOOKUP_FNS)
  lines.join("\n")
}

///|
async fn fetch_unicode_data(version : String, timeout_ms : Int) -> String {
  let url = unicode_data_url(version)
  let result = @async.with_timeout_opt(timeout_ms, () => @http.get(url))
  match result {
    None =>
      fail(
        "Unicode data fetch timed out after " + timeout_ms.to_string() + " ms",
      )
    Some((response, body)) => {
      if response.code != 200 {
        fail(
          "Unicode data fetch failed with HTTP status " +
          response.code.to_string(),
        )
      }
      body.text()
    }
  }
}

///|
async fn fetch_case_folding_data(version : String, timeout_ms : Int) -> String {
  let url = unicode_case_folding_url(version)
  let result = @async.with_timeout_opt(timeout_ms, () => @http.get(url))
  match result {
    None =>
      fail(
        "Unicode data fetch timed out after " + timeout_ms.to_string() + " ms",
      )
    Some((response, body)) => {
      if response.code != 200 {
        fail(
          "Unicode data fetch failed with HTTP status " +
          response.code.to_string(),
        )
      }
      body.text()
    }
  }
}

///|
pub async fn run_unicode_tables(config : UnicodeConfig) -> ToolRun {
  let stderr = StringBuilder()
  let url = unicode_data_url(config.unicode_version)
  stderr.write_string("Fetching " + url + "\n")
  let text = fetch_unicode_data(config.unicode_version, config.fetch_timeout_ms)
  let tables : Map[String, Array[(Int, Int)]] = Map([])
  for name in unicode_properties() {
    tables[name] = parse_unicode_property(text, name)
  }
  let output = emit_unicode_tables(config.unicode_version, tables)
  let case_fold_artifact = match config.case_fold_output {
    Some(path) => {
      let case_fold_url = unicode_case_folding_url(config.unicode_version)
      stderr.write_string("Fetching " + case_fold_url + "\n")
      let case_fold_text = fetch_case_folding_data(
        config.unicode_version,
        config.fetch_timeout_ms,
      )
      let mappings = parse_simple_case_folding(case_fold_text)
      Some(
        (
          path,
          emit_case_folding_table(config.unicode_version, mappings),
          mappings.length(),
        ),
      )
    }
    None => None
  }
  @afs.write_file(config.output, output, create_mode=CreateOrTruncate)
  let mut count = 0
  for value in tables.values() {
    count += value.length()
  }
  stderr.write_string(
    "Wrote " + config.output + " (" + count.to_string() + " ranges)\n",
  )
  match case_fold_artifact {
    Some((path, case_fold_output, mapping_count)) => {
      @afs.write_file(path, case_fold_output, create_mode=CreateOrTruncate)
      stderr.write_string(
        "Wrote " + path + " (" + mapping_count.to_string() + " mappings)\n",
      )
    }
    None => ()
  }
  { stdout: "", stderr: stderr.to_string(), code: 0 }
}
