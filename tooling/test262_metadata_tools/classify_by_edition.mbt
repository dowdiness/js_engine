///|
struct FailureRecord {
  path : String
  reason : String
} derive(Debug)

///|
struct EditionBucket {
  total : Int
  passed : Int
  failed : Int
  skipped : Int
  timeout : Int
  error : Int
  failures : Array[FailureRecord]
} derive(Debug)

///|
struct ResultRecord {
  path : String
  status : String
  reason : String
} derive(Debug)

///|
struct ResultFileData {
  mode : String
  results : Array[ResultRecord]
} derive(Debug)

///|
fn empty_bucket() -> EditionBucket {
  {
    total: 0,
    passed: 0,
    failed: 0,
    skipped: 0,
    timeout: 0,
    error: 0,
    failures: [],
  }
}

///|
fn bucket_record(
  bucket : EditionBucket,
  status : String,
  path~ : String,
  reason~ : String,
) -> EditionBucket {
  let failures = bucket.failures.copy()
  let mut passed = bucket.passed
  let mut failed = bucket.failed
  let mut skipped = bucket.skipped
  let mut timeout = bucket.timeout
  let mut error = bucket.error
  match status {
    "pass" => passed += 1
    "fail" => {
      failed += 1
      failures.push({ path, reason })
    }
    "skip" => skipped += 1
    "timeout" => {
      timeout += 1
      failures.push({
        path,
        reason: if reason == "" {
          "timeout"
        } else {
          reason
        },
      })
    }
    "error" => {
      error += 1
      failures.push({
        path,
        reason: if reason == "" {
          "error"
        } else {
          reason
        },
      })
    }
    _ => ()
  }
  { total: bucket.total + 1, passed, failed, skipped, timeout, error, failures }
}

///|
fn bucket_executed(bucket : EditionBucket) -> Int {
  bucket.passed + bucket.failed
}

///|
fn bucket_timeout_error(bucket : EditionBucket) -> Int {
  bucket.timeout + bucket.error
}

///|
fn bucket_passed_over_executed(bucket : EditionBucket) -> String {
  pct_string(bucket.passed, bucket_executed(bucket), 1)
}

///|
fn bucket_passed_over_discovered(bucket : EditionBucket) -> String {
  pct_string(bucket.passed, bucket.total, 1)
}

///|
fn bucket_add(left : EditionBucket, right : EditionBucket) -> EditionBucket {
  {
    total: left.total + right.total,
    passed: left.passed + right.passed,
    failed: left.failed + right.failed,
    skipped: left.skipped + right.skipped,
    timeout: left.timeout + right.timeout,
    error: left.error + right.error,
    failures: [],
  }
}

///|
fn feature_edition() -> Map[String, String] {
  {
    "arrow-function": "ES2015",
    "class": "ES2015",
    "computed-property-names": "ES2015",
    "const": "ES2015",
    "default-parameters": "ES2015",
    "destructuring-assignment": "ES2015",
    "destructuring-binding": "ES2015",
    "for-of": "ES2015",
    "generators": "ES2015",
    "let": "ES2015",
    "new.target": "ES2015",
    "rest-parameters": "ES2015",
    "super": "ES2015",
    "template": "ES2015",
    "tail-call-optimization": "ES2015",
    "ArrayBuffer": "ES2015",
    "DataView": "ES2015",
    "DataView.prototype.getFloat32": "ES2015",
    "DataView.prototype.getFloat64": "ES2015",
    "DataView.prototype.getInt16": "ES2015",
    "DataView.prototype.getInt32": "ES2015",
    "DataView.prototype.getInt8": "ES2015",
    "DataView.prototype.getUint16": "ES2015",
    "DataView.prototype.getUint32": "ES2015",
    "DataView.prototype.setUint8": "ES2015",
    "Int8Array": "ES2015",
    "Int16Array": "ES2015",
    "Int32Array": "ES2015",
    "Uint8Array": "ES2015",
    "Uint16Array": "ES2015",
    "Uint32Array": "ES2015",
    "Uint8ClampedArray": "ES2015",
    "Float32Array": "ES2015",
    "Float64Array": "ES2015",
    "TypedArray": "ES2015",
    "Map": "ES2015",
    "Set": "ES2015",
    "WeakMap": "ES2015",
    "WeakSet": "ES2015",
    "Promise": "ES2015",
    "Proxy": "ES2015",
    "Reflect": "ES2015",
    "Reflect.construct": "ES2015",
    "Reflect.set": "ES2015",
    "Reflect.setPrototypeOf": "ES2015",
    "proxy-missing-checks": "ES2015",
    "Symbol": "ES2015",
    "Symbol.hasInstance": "ES2015",
    "Symbol.isConcatSpreadable": "ES2015",
    "Symbol.iterator": "ES2015",
    "Symbol.match": "ES2015",
    "Symbol.replace": "ES2015",
    "Symbol.search": "ES2015",
    "Symbol.species": "ES2015",
    "Symbol.split": "ES2015",
    "Symbol.toPrimitive": "ES2015",
    "Symbol.toStringTag": "ES2015",
    "Symbol.unscopables": "ES2015",
    "String.fromCodePoint": "ES2015",
    "String.prototype.includes": "ES2015",
    "u180e": "ES2015",
    "cross-realm": "ES2015",
    "caller": "ES2015",
    "exponentiation": "ES2016",
    "Array.prototype.includes": "ES2016",
    "async-functions": "ES2017",
    "Atomics": "ES2017",
    "SharedArrayBuffer": "ES2017",
    "async-iteration": "ES2018",
    "object-rest": "ES2018",
    "object-spread": "ES2018",
    "Promise.prototype.finally": "ES2018",
    "regexp-dotall": "ES2018",
    "regexp-lookbehind": "ES2018",
    "regexp-named-groups": "ES2018",
    "regexp-unicode-property-escapes": "ES2018",
    "Symbol.asyncIterator": "ES2018",
    "Array.prototype.flat": "ES2019",
    "Array.prototype.flatMap": "ES2019",
    "Object.fromEntries": "ES2019",
    "optional-catch-binding": "ES2019",
    "String.prototype.trimEnd": "ES2019",
    "String.prototype.trimStart": "ES2019",
    "string-trimming": "ES2019",
    "Symbol.prototype.description": "ES2019",
    "json-superset": "ES2019",
    "well-formed-json-stringify": "ES2019",
    "stable-array-sort": "ES2019",
    "BigInt": "ES2020",
    "coalesce-expression": "ES2020",
    "optional-chaining": "ES2020",
    "dynamic-import": "ES2020",
    "export-star-as-namespace-from-module": "ES2020",
    "for-in-order": "ES2020",
    "globalThis": "ES2020",
    "import.meta": "ES2020",
    "Promise.allSettled": "ES2020",
    "String.prototype.matchAll": "ES2020",
    "Promise.any": "ES2021",
    "AggregateError": "ES2021",
    "WeakRef": "ES2021",
    "FinalizationRegistry": "ES2021",
    "logical-assignment-operators": "ES2021",
    "numeric-separator-literal": "ES2021",
    "String.prototype.replaceAll": "ES2021",
    "class-fields-public": "ES2022",
    "class-fields-private": "ES2022",
    "class-fields-private-in": "ES2022",
    "class-methods-private": "ES2022",
    "class-static-fields-public": "ES2022",
    "class-static-fields-private": "ES2022",
    "class-static-methods-private": "ES2022",
    "class-static-block": "ES2022",
    "top-level-await": "ES2022",
    "Array.prototype.at": "ES2022",
    "String.prototype.at": "ES2022",
    "TypedArray.prototype.at": "ES2022",
    "Object.hasOwn": "ES2022",
    "error-cause": "ES2022",
    "regexp-match-indices": "ES2022",
    "Array.prototype.values": "ES2022",
    "Object.is": "ES2022",
    "arbitrary-module-namespace-names": "ES2022",
    "nonextensible-applies-to-private": "ES2022",
    "String.prototype.endsWith": "ES2015",
    "Symbol.matchAll": "ES2020",
    "array-find-from-last": "ES2023",
    "change-array-by-copy": "ES2023",
    "hashbang": "ES2023",
    "symbols-as-weakmap-keys": "ES2023",
    "arraybuffer-transfer": "ES2024",
    "promise-with-resolvers": "ES2024",
    "resizable-arraybuffer": "ES2024",
    "String.prototype.isWellFormed": "ES2024",
    "String.prototype.toWellFormed": "ES2024",
    "Atomics.waitAsync": "ES2024",
    "regexp-v-flag": "ES2024",
    "align-detached-buffer-semantics-with-web-reality": "ES2024",
    "stable-typedarray-sort": "ES2024",
    "Array.fromAsync": "ES2024",
    "array-grouping": "ES2024",
    "iterator-helpers": "ES2025",
    "set-methods": "ES2025",
    "promise-try": "ES2025",
    "RegExp.escape": "ES2025",
    "regexp-modifiers": "ES2025",
    "Float16Array": "ES2025",
    "json-modules": "ES2025",
    "import-attributes": "ES2025",
    "Math.sumPrecise": "ES2025",
    "uint8array-base64": "ES2025",
    "Error.isError": "ES2025",
    "json-parse-with-source": "ES2025",
    "regexp-duplicate-named-groups": "ES2025",
    "upsert": "ES2025",
    "__proto__": "Annex B",
    "__getter__": "Annex B",
    "__setter__": "Annex B",
    "Intl-enumeration": "Intl (ECMA-402)",
    "intl-normative-optional": "Intl (ECMA-402)",
    "Intl.DateTimeFormat-datetimestyle": "Intl (ECMA-402)",
    "Intl.DateTimeFormat-dayPeriod": "Intl (ECMA-402)",
    "Intl.DateTimeFormat-extend-timezonename": "Intl (ECMA-402)",
    "Intl.DateTimeFormat-formatRange": "Intl (ECMA-402)",
    "Intl.DateTimeFormat-fractionalSecondDigits": "Intl (ECMA-402)",
    "Intl.DisplayNames": "Intl (ECMA-402)",
    "Intl.DisplayNames-v2": "Intl (ECMA-402)",
    "Intl.DurationFormat": "Intl (ECMA-402)",
    "Intl.ListFormat": "Intl (ECMA-402)",
    "Intl.Locale": "Intl (ECMA-402)",
    "Intl.Locale-info": "Intl (ECMA-402)",
    "Intl.NumberFormat-unified": "Intl (ECMA-402)",
    "Intl.RelativeTimeFormat": "Intl (ECMA-402)",
    "Intl.Segmenter": "Intl (ECMA-402)",
    "Intl.Era-monthcode": "Intl (ECMA-402)",
    "Temporal": "Stage 3",
    "decorators": "Stage 3",
    "source-phase-imports": "Stage 3",
    "source-phase-imports-module-source": "Stage 3",
    "explicit-resource-management": "Stage 3",
    "import-defer": "Stage 3",
    "joint-iteration": "Stage 3",
    "iterator-sequencing": "Stage 3",
    "ShadowRealm": "Stage 3",
    "immutable-arraybuffer": "Stage 3",
    "Atomics.pause": "Stage 3",
  }
}

///|
fn edition_order() -> Array[String] {
  [
    "Pre-ES2015 (baseline)", "ES2015", "ES2016", "ES2017", "ES2018", "ES2019", "ES2020",
    "ES2021", "ES2022", "ES2023", "ES2024", "ES2025", "Annex B", "Intl (ECMA-402)",
    "Stage 3", "Unmapped",
  ]
}

///|
fn edition_rank(edition : String) -> Int {
  for i, known in edition_order() {
    if known == edition {
      return i
    }
  }
  edition_order().length()
}

///|
fn path_edition_fallback() -> Array[(String, String)] {
  [
    ("/built-ins/AsyncFromSyncIteratorPrototype/", "ES2018"),
    ("/built-ins/AsyncGeneratorFunction/", "ES2018"),
    ("/built-ins/AsyncGeneratorPrototype/", "ES2018"),
    ("/built-ins/AsyncFunction/", "ES2017"),
    ("/built-ins/Atomics/", "ES2017"),
    ("/built-ins/SharedArrayBuffer/", "ES2017"),
    ("/built-ins/AggregateError/", "ES2021"),
    ("/built-ins/WeakRef/", "ES2021"),
    ("/built-ins/FinalizationRegistry/", "ES2021"),
    ("/built-ins/BigInt/", "ES2020"),
    ("/built-ins/Temporal/", "Stage 3"),
    ("/built-ins/ShadowRealm/", "Stage 3"),
    ("/built-ins/DisposableStack/", "Stage 3"),
    ("/built-ins/AsyncDisposableStack/", "Stage 3"),
    ("/built-ins/SuppressedError/", "Stage 3"),
    ("/built-ins/Iterator/", "ES2025"),
    ("/built-ins/Promise/", "ES2015"),
    ("/built-ins/Map/", "ES2015"),
    ("/built-ins/Set/", "ES2015"),
    ("/built-ins/WeakMap/", "ES2015"),
    ("/built-ins/WeakSet/", "ES2015"),
    ("/built-ins/Proxy/", "ES2015"),
    ("/built-ins/Reflect/", "ES2015"),
    ("/built-ins/Symbol/", "ES2015"),
    ("/built-ins/Generator", "ES2015"),
    ("/built-ins/TypedArray", "ES2015"),
    ("/built-ins/DataView/", "ES2015"),
    ("/built-ins/ArrayBuffer/", "ES2015"),
    ("/built-ins/Int8Array/", "ES2015"),
    ("/built-ins/Int16Array/", "ES2015"),
    ("/built-ins/Int32Array/", "ES2015"),
    ("/built-ins/Uint8Array/", "ES2015"),
    ("/built-ins/Uint16Array/", "ES2015"),
    ("/built-ins/Uint32Array/", "ES2015"),
    ("/built-ins/Uint8ClampedArray/", "ES2015"),
    ("/built-ins/Float32Array/", "ES2015"),
    ("/built-ins/Float64Array/", "ES2015"),
    ("/built-ins/ThrowTypeError/", "ES2015"),
    ("/built-ins/MapIteratorPrototype/", "ES2015"),
    ("/built-ins/SetIteratorPrototype/", "ES2015"),
    ("/built-ins/ArrayIteratorPrototype/", "ES2015"),
    ("/built-ins/StringIteratorPrototype/", "ES2015"),
    ("/built-ins/IteratorPrototype/", "ES2015"),
    ("/language/module-code/", "ES2015"),
    ("/language/import/", "ES2015"),
    ("/language/export/", "ES2015"),
    ("/language/statements/class/", "ES2015"),
    ("/language/expressions/class/", "ES2015"),
    ("/language/expressions/arrow-function/", "ES2015"),
    ("/language/expressions/template-literal/", "ES2015"),
    ("/language/expressions/tagged-template/", "ES2015"),
    ("/language/expressions/generators/", "ES2015"),
    ("/language/statements/generators/", "ES2015"),
    ("/language/statements/for-of/", "ES2015"),
    ("/language/statements/let/", "ES2015"),
    ("/language/statements/const/", "ES2015"),
    ("/language/expressions/yield/", "ES2015"),
    ("/language/statements/async-function/", "ES2017"),
    ("/language/expressions/async-function/", "ES2017"),
    ("/language/expressions/async-arrow-function/", "ES2017"),
  ]
}

///|
fn line_leading_whitespace(line : String) -> Int {
  let mut count = 0
  while count < line.length() && (line[count] == ' ' || line[count] == '\t') {
    count += 1
  }
  count
}

///|
fn extract_features(text : String) -> Array[String] {
  guard text.find("/*---") is Some(start) else { return [] }
  let content_start = start + "/*---".length()
  guard text[content_start:].find("---*/") is Some(relative_end) else {
    return []
  }
  let fm = text[content_start:content_start + relative_end].trim().to_owned()
  let lines = fm.split("\n").map(line => line.to_owned()).to_array()
  for line in lines {
    if line.has_prefix("features:") {
      let rest = line["features:".length():].trim().to_owned()
      if rest.has_prefix("[") {
        match rest.find("]") {
          Some(close) => {
            let inner = rest[1:close].to_owned()
            let out : Array[String] = []
            for item in inner.split(",") {
              let value = item.trim().to_owned()
              if value != "" {
                out.push(value)
              }
            }
            return out
          }
          None => ()
        }
      }
    }
  }
  for i, line in lines {
    if line.has_prefix("features:") && line["features:".length():].trim() == "" {
      let out : Array[String] = []
      let mut j = i + 1
      while j < lines.length() {
        let candidate = lines[j]
        let stripped = candidate.trim().to_owned()
        if line_leading_whitespace(candidate) >= 2 && stripped.has_prefix("-") {
          let value = stripped[1:].trim().to_owned()
          if value == "" {
            break
          }
          out.push(value)
          j += 1
        } else {
          break
        }
      }
      return out
    }
  }
  []
}

///|
fn classify_path_by_edition(
  path : String,
  features : Array[String],
) -> (String, Array[String]) {
  if path.contains("/annexB/") ||
    path.has_prefix("annexB/") ||
    path.contains("/test/annexB/") {
    return ("Annex B", [])
  }
  if path.contains("/intl402/") || path.contains("/test/intl402/") {
    return ("Intl (ECMA-402)", [])
  }
  if features.length() == 0 {
    for entry in path_edition_fallback() {
      if path.contains(entry.0) {
        return (entry.1, [])
      }
    }
    return ("Pre-ES2015 (baseline)", [])
  }
  let editions : Array[String] = []
  let unmapped_seen = @set.Set::default()
  let feature_map = feature_edition()
  for feature in features {
    match feature_map.get(feature) {
      Some(edition) => editions.push(edition)
      None => unmapped_seen.add(feature)
    }
  }
  let unmapped : Array[String] = []
  for feature in unmapped_seen {
    unmapped.push(feature)
  }
  unmapped.sort()
  if editions.length() == 0 {
    return ("Unmapped", unmapped)
  }
  let mut best = editions[0]
  for edition in editions {
    if edition_rank(edition) > edition_rank(best) {
      best = edition
    }
  }
  (best, unmapped)
}

///|
fn json_string_field(data : Map[String, Json], key : String) -> String raise {
  match data.get(key) {
    Some(raw) =>
      @json.from_json(raw) catch {
        _ => fail("result field must be string: " + key)
      }
    None => fail("missing result field: " + key)
  }
}

///|
fn json_optional_string_field(data : Map[String, Json], key : String) -> String {
  match data.get(key) {
    Some(raw) => @json.from_json(raw) catch { _ => "" }
    None => ""
  }
}

///|
fn load_result_file(path : String) -> ResultFileData raise {
  let root : Map[String, Json] = @json.from_json(
    @json.parse(@fs.read_file_to_string(path)),
  )
  let raw_results : Array[Map[String, Json]] = match root.get("results") {
    Some(raw) => @json.from_json(raw) catch { _ => [] }
    None => []
  }
  let results : Array[ResultRecord] = []
  for raw in raw_results {
    results.push({
      path: json_string_field(raw, "path"),
      status: json_string_field(raw, "status"),
      reason: json_optional_string_field(raw, "reason"),
    })
  }
  let mode = if results.length() > 0 {
    match raw_results[0].get("mode") {
      Some(raw) =>
        @json.from_json(raw) catch {
          _ => @path_utils.basename(path)
        }
      None => @path_utils.basename(path)
    }
  } else {
    @path_utils.basename(path)
  }
  { mode, results }
}

///|
fn result_abs_path(path : String, test262_root : String) -> String {
  let normalized = @path_utils.normalize_path(path)
  if normalized.has_prefix("/") || normalized.has_prefix("test262/") {
    normalized
  } else {
    @path_utils.join_path(test262_root, normalized)
  }
}

///|
fn classify_result_records(
  records : Array[ResultRecord],
  test262_root : String,
) -> (Map[String, EditionBucket], Map[String, Int]) {
  let buckets : Map[String, EditionBucket] = {}
  let unmapped_counts : Map[String, Int] = {}
  let feature_cache : Map[String, Array[String]] = {}
  for record in records {
    let features = match feature_cache.get(record.path) {
      Some(cached) => cached
      None => {
        let abs_path = result_abs_path(record.path, test262_root)
        let parsed = python_text_newlines(@fs.read_file_to_string(abs_path)) catch {
          _ => ""
        }
        let extracted = if parsed == "" { [] } else { extract_features(parsed) }
        feature_cache[record.path] = extracted
        extracted
      }
    }
    let (edition, unmapped) = classify_path_by_edition(record.path, features)
    let bucket = match buckets.get(edition) {
      Some(existing) => existing
      None => empty_bucket()
    }
    buckets[edition] = bucket_record(
      bucket,
      record.status,
      path=record.path,
      reason=record.reason,
    )
    for feature in unmapped {
      increment_count(unmapped_counts, feature)
    }
  }
  (buckets, unmapped_counts)
}

///|
fn sorted_edition_keys(buckets : Map[String, EditionBucket]) -> Array[String] {
  let keys : Array[String] = []
  for key, _ in buckets {
    keys.push(key)
  }
  keys.sort_by(fn(a, b) {
    let by_rank = edition_rank(a).compare(edition_rank(b))
    if by_rank != 0 {
      by_rank
    } else {
      a.compare(b)
    }
  })
  keys
}

///|
fn render_classify_table(
  mode : String,
  buckets : Map[String, EditionBucket],
) -> Array[String] {
  let lines : Array[String] = [
    "### " + mode,
    "",
    "| Edition | Discovered | Skipped | Executed | Passed | Failed | Timeout/Err | Passed / Executed | Passed / Discovered |",
    "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
  ]
  let mut totals = empty_bucket()
  let fully_skipped : Array[(String, Int)] = []
  for edition in sorted_edition_keys(buckets) {
    let bucket = buckets[edition]
    if bucket.total == 0 {
      continue
    }
    totals = bucket_add(totals, bucket)
    if bucket_executed(bucket) == 0 &&
      bucket.passed == 0 &&
      bucket.failed == 0 &&
      bucket.timeout == 0 &&
      bucket.error == 0 {
      fully_skipped.push((edition, bucket.total))
      continue
    }
    lines.push(
      "| " +
      edition +
      " | " +
      comma_int(bucket.total) +
      " | " +
      comma_int(bucket.skipped) +
      " | " +
      comma_int(bucket_executed(bucket)) +
      " | " +
      comma_int(bucket.passed) +
      " | " +
      comma_int(bucket.failed) +
      " | " +
      comma_int(bucket_timeout_error(bucket)) +
      " | " +
      bucket_passed_over_executed(bucket) +
      "% | " +
      bucket_passed_over_discovered(bucket) +
      "% |",
    )
  }
  lines.push(
    "| **Total** | **" +
    comma_int(totals.total) +
    "** | **" +
    comma_int(totals.skipped) +
    "** | **" +
    comma_int(bucket_executed(totals)) +
    "** | **" +
    comma_int(totals.passed) +
    "** | **" +
    comma_int(totals.failed) +
    "** | **" +
    comma_int(bucket_timeout_error(totals)) +
    "** | **" +
    bucket_passed_over_executed(totals) +
    "%** | **" +
    bucket_passed_over_discovered(totals) +
    "%** |",
  )
  if fully_skipped.length() > 0 {
    let parts : Array[String] = []
    for entry in fully_skipped {
      parts.push(entry.0 + " (" + comma_int(entry.1) + ")")
    }
    lines.push("")
    lines.push(
      "_Fully-skipped buckets (no tests executed) folded into Total: " +
      parts.join(", ") +
      "._",
    )
  }
  lines
}

///|
fn first_line(value : String) -> String {
  match value.split_once("\n") {
    Some((line, _)) => line.trim().to_owned()
    None => value.trim().to_owned()
  }
}

///|
fn collapse_js_paths(value : String) -> String {
  let out = StringBuilder()
  let len = value.length()
  let mut i = 0
  while i < len {
    if value[i] == '/' {
      let start = i
      let mut j = i + 1
      let mut js_end : Int? = None
      while j < len && value[j] != ' ' && value[j] != '\t' && value[j] != '\n' {
        if j + 3 <= len && value[j:j + 3] == ".js" {
          js_end = Some(j + 3)
          break
        }
        j += 1
      }
      match js_end {
        Some(end_index) => {
          out.write_string("<file>")
          i = end_index
          continue
        }
        None => {
          out.write_char(value[start].unsafe_to_char())
          i = start + 1
          continue
        }
      }
    }
    out.write_char(value[i].unsafe_to_char())
    i += 1
  }
  out.to_string()
}

///|
fn collapse_line_numbers(value : String) -> String {
  let out = StringBuilder()
  let len = value.length()
  let mut i = 0
  while i < len {
    if i + 5 <= len && value[i:i + 5] == "line " {
      let mut j = i + 5
      if j < len && value[j] >= '0' && value[j] <= '9' {
        while j < len && value[j] >= '0' && value[j] <= '9' {
          j += 1
        }
        out.write_string("line N")
        i = j
        continue
      }
    }
    out.write_char(value[i].unsafe_to_char())
    i += 1
  }
  out.to_string()
}

///|
fn collapse_large_numbers(value : String) -> String {
  let out = StringBuilder()
  let len = value.length()
  let mut i = 0
  while i < len {
    if value[i] >= '0' && value[i] <= '9' {
      let start = i
      while i < len && value[i] >= '0' && value[i] <= '9' {
        i += 1
      }
      if i - start >= 2 {
        out.write_string("N")
      } else {
        out.write_string(value[start:i].to_owned())
      }
      continue
    }
    out.write_char(value[i].unsafe_to_char())
    i += 1
  }
  out.to_string()
}

///|
fn collapse_quoted(
  value : String,
  quote : UInt16,
  replacement : String,
) -> String {
  let out = StringBuilder()
  let len = value.length()
  let mut i = 0
  while i < len {
    if value[i] == quote {
      let mut j = i + 1
      while j < len && value[j] != quote && j - i - 1 <= 40 {
        j += 1
      }
      if j < len && value[j] == quote && j - i - 1 <= 40 {
        out.write_string(replacement)
        i = j + 1
        continue
      }
    }
    out.write_char(value[i].unsafe_to_char())
    i += 1
  }
  out.to_string()
}

///|
fn reason_key(reason : String) -> String {
  if reason == "" {
    return "(no reason)"
  }
  let collapsed = collapse_quoted(
    collapse_quoted(
      collapse_large_numbers(
        collapse_line_numbers(collapse_js_paths(first_line(reason))),
      ),
      '\'',
      "'…'",
    ),
    '"',
    "\"…\"",
  )
  if collapsed.length() > 120 {
    collapsed[:120].to_owned()
  } else {
    collapsed
  }
}

///|
fn top_subdir(path : String, depth~ : Int) -> String {
  let parts = @path_utils.path_components(@path_utils.normalize_path(path))
  let end = if depth < parts.length() { depth } else { parts.length() }
  [ for i in 0..<end => parts[i] ].join("/")
}

///|
fn render_failure_analysis(
  mode : String,
  buckets : Map[String, EditionBucket],
  edition_filter : String?,
  top_n : Int,
) -> Array[String] {
  let lines : Array[String] = ["## Failure analysis — " + mode]
  for edition in sorted_edition_keys(buckets) {
    if edition_filter is Some(filter) && edition != filter {
      continue
    }
    let bucket = buckets[edition]
    if bucket.failures.length() == 0 {
      continue
    }
    lines.push("")
    lines.push(
      "### " +
      edition +
      " — " +
      bucket.failures.length().to_string() +
      " failures",
    )
    let subdir_counts : Map[String, Int] = {}
    for failure in bucket.failures {
      increment_count(subdir_counts, top_subdir(failure.path, depth=4))
    }
    lines.push("")
    lines.push("**Top directories:**")
    lines.push("")
    lines.push("| Count | Directory |")
    lines.push("|---:|---|")
    for i, key in sorted_count_keys_desc(subdir_counts) {
      if i < top_n {
        lines.push(
          "| " +
          map_get_count(subdir_counts, key).to_string() +
          " | `" +
          key +
          "` |",
        )
      }
    }
    let reason_counts : Map[String, Int] = {}
    for failure in bucket.failures {
      increment_count(reason_counts, reason_key(failure.reason))
    }
    lines.push("")
    lines.push("**Top failure reasons:**")
    lines.push("")
    lines.push("| Count | Reason |")
    lines.push("|---:|---|")
    for i, key in sorted_count_keys_desc(reason_counts) {
      if i < top_n {
        let safe = key.replace_all(old="|", new="\\|")
        lines.push(
          "| " +
          map_get_count(reason_counts, key).to_string() +
          " | `" +
          safe +
          "` |",
        )
      }
    }
  }
  lines
}

///|
fn append_section(
  output : Array[String],
  section : Array[String],
  leading_blank~ : Bool,
) -> Unit {
  if leading_blank && output.length() > 0 {
    output.push("")
  }
  for line in section {
    output.push(line)
  }
}

///|
fn classify_json_int(value : Int) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn edition_bucket_json(bucket : EditionBucket) -> Json {
  let executed = bucket_executed(bucket)
  let rate = if executed > 0 {
    bucket.passed.to_double() / executed.to_double() * 100.0
  } else {
    0.0
  }
  let discovered_rate = if bucket.total > 0 {
    bucket.passed.to_double() / bucket.total.to_double() * 100.0
  } else {
    0.0
  }
  Json::object({
    "total": classify_json_int(bucket.total),
    "executed": classify_json_int(executed),
    "passed": classify_json_int(bucket.passed),
    "failed": classify_json_int(bucket.failed),
    "skipped": classify_json_int(bucket.skipped),
    "timeouts": classify_json_int(bucket.timeout),
    "errors": classify_json_int(bucket.error),
    "rate": Json::number(rate),
    "discovered_rate": Json::number(discovered_rate),
  })
}

///|
fn editions_json(buckets : Map[String, EditionBucket]) -> Json {
  let editions : Map[String, Json] = {}
  for edition in sorted_edition_keys(buckets) {
    let bucket = buckets[edition]
    if bucket.total == 0 {
      continue
    }
    editions[edition] = edition_bucket_json(bucket)
  }
  Json::object(editions)
}

///|
/// Classify existing Test262 result artifacts by ECMAScript edition.
///
/// This reads existing result artifacts only. It does not run the engine.
pub fn run_classify_by_edition(
  result_paths : Array[String],
  test262_root? : String = ".",
  show_unmapped? : Bool = false,
  list_failures? : Bool = false,
  edition_filter? : String? = None,
  top? : Int = 15,
  json_output? : String = "",
) -> ToolRun raise {
  let all_unmapped : Map[String, Int] = {}
  let stdout_lines : Array[String] = []
  let failure_sections : Array[Array[String]] = []
  let mode_editions : Map[String, Json] = {}
  for result_path in result_paths {
    let data = load_result_file(result_path)
    let (buckets, unmapped) = classify_result_records(
      data.results,
      test262_root,
    )
    if json_output != "" {
      mode_editions[data.mode] = editions_json(buckets)
    }
    append_section(
      stdout_lines,
      render_classify_table(data.mode, buckets),
      leading_blank=stdout_lines.length() > 0,
    )
    if list_failures {
      failure_sections.push(
        render_failure_analysis(data.mode, buckets, edition_filter, top),
      )
    }
    for feature, count in unmapped {
      all_unmapped[feature] = map_get_count(all_unmapped, feature) + count
    }
  }
  if list_failures {
    stdout_lines.push("")
    stdout_lines.push("---")
    for section in failure_sections {
      append_section(stdout_lines, section, leading_blank=true)
    }
  }
  if show_unmapped && all_unmapped.length() > 0 {
    stdout_lines.push("")
    stdout_lines.push("### Unmapped features (add to FEATURE_EDITION)")
    stdout_lines.push("")
    for feature in sorted_count_keys_desc(all_unmapped) {
      stdout_lines.push(
        "- `" +
        feature +
        "` — " +
        map_get_count(all_unmapped, feature).to_string() +
        " tests",
      )
    }
  }
  if json_output != "" {
    let payload : Map[String, Json] = {
      "editions": Json::object(mode_editions),
    }
    @fs.write_string_to_file(
      json_output,
      Json::object(payload).stringify(indent=2) + "\n",
    )
  }
  { stdout_lines, stderr_lines: [], code: 0 }
}
