///|
const SCHEMA_VERSION : Int = 1

///|
priv struct EvidenceReference {
  row_id : String
  field : String
  reference : String
}

///|
fn operation_families() -> Array[String] {
  [
    "statement dispatch", "expression dispatch", "bounded evaluation", "activation dispatch",
    "microtask policy", "timer policy",
  ]
}

///|
fn required_string(
  data : Map[String, Json],
  key : String,
  path : String,
) -> Result[String, String] {
  match data.get(key) {
    Some(value) => {
      let string_value : String = @json.from_json(value) catch {
        _ => return Err(path + ": " + key + " must be a string")
      }
      Ok(string_value)
    }
    None => Err(path + ": missing key: " + key)
  }
}

///|
fn validate_nonempty_string(
  data : Map[String, Json],
  key : String,
  path : String,
) -> Result[Unit, String] {
  let value = match required_string(data, key, path) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  if value == "" {
    return Err(path + ": " + key + " must not be empty")
  }
  Ok(())
}

///|
fn validate_operation_family(
  data : Map[String, Json],
  path : String,
) -> Result[Unit, String] {
  let family = match required_string(data, "operation_family", path) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  if !operation_families().any(candidate => candidate == family) {
    return Err(path + ": unknown operation_family: " + family)
  }
  Ok(())
}

///|
fn focused_reference_is_valid(value : String) -> Bool {
  let parts = value.split("#").to_array()
  parts.length() == 2 && parts[0].length() > 0 && parts[1].length() > 0
}

///|
fn validate_reference_array(
  data : Map[String, Json],
  key : String,
  path : String,
) -> Result[Array[String], String] {
  let values : Array[String] = match data.get(key) {
    Some(value) =>
      @json.from_json(value) catch {
        _ => return Err(path + ": " + key + " must be an array of strings")
      }
    None => return Err(path + ": missing key: " + key)
  }
  if values.length() == 0 {
    return Err(path + ": " + key + " must not be empty")
  }
  for value in values {
    if !focused_reference_is_valid(value) {
      return Err(
        path + ": " + key + " entries must be non-empty path#anchor references",
      )
    }
  }
  Ok(values)
}

///|
fn required_bool(
  data : Map[String, Json],
  key : String,
  path : String,
) -> Result[Bool, String] {
  match data.get(key) {
    Some(value) => {
      let bool_value : Bool = @json.from_json(value) catch {
        _ => return Err(path + ": " + key + " must be a boolean")
      }
      Ok(bool_value)
    }
    None => Err(path + ": missing key: " + key)
  }
}

///|
fn optional_string(
  data : Map[String, Json],
  key : String,
  path : String,
) -> Result[String?, String] {
  match data.get(key) {
    Some(value) => {
      let string_value : String = @json.from_json(value) catch {
        _ => return Err(path + ": " + key + " must be a string")
      }
      Ok(Some(string_value))
    }
    None => Ok(None)
  }
}

///|
fn issue_reference_is_positive_integer(issue : String) -> Bool {
  issue.length() > 1 &&
  issue[0] == '#' &&
  issue[1:].all(c => c >= '0' && c <= '9') &&
  issue[1:].any(c => c != '0')
}

///|
/// The seeded Stage 4 queue admits only these already-created tracking issues.
fn permitted_stage4_tracking_issues() -> Array[String] {
  [
    "#749", "#750", "#751", "#752", "#753", "#754", "#755", "#756", "#757", "#758",
    "#759", "#760", "#761",
  ]
}

///|
fn validate_row_metadata(
  data : Map[String, Json],
  path : String,
) -> Result[Unit, String] {
  match validate_nonempty_string(data, "entry_category", path) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  match required_string(data, "contract_observation_category", path) {
    Ok(
      "dispatch-point"
      | "host-source-parsing"
      | "fixed-size-bookkeeping"
      | "already-observed-loop"
      | "script-controlled-execution-time-loop"
    ) => ()
    Ok(value) =>
      return Err(path + ": invalid contract_observation_category: " + value)
    Err(message) => return Err(message)
  }
  validate_nonempty_string(data, "duplicate_charge_risk", path)
}

///|
fn validate_public_facade_evidence(
  data : Map[String, Json],
  path : String,
) -> Result[Array[String], String] {
  let required = match
    required_bool(data, "public_facade_evidence_required", path) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  match data.get("public_facade_evidence") {
    Some(value) => {
      let evidence : Array[String] = @json.from_json(value) catch {
        _ =>
          return Err(
            path + ": public_facade_evidence must be an array of strings",
          )
      }
      if required && evidence.length() == 0 {
        return Err(
          path + ": public_facade_evidence must not be empty when required",
        )
      }
      for reference in evidence {
        if !focused_reference_is_valid(reference) {
          return Err(
            path +
            ": public_facade_evidence entries must be non-empty path#anchor references",
          )
        }
      }
      Ok(evidence)
    }
    None if required => Err(path + ": missing key: public_facade_evidence")
    None => Ok([])
  }
}

///|
fn validate_status_and_ownership(
  data : Map[String, Json],
  permitted_issues : Array[String],
  path : String,
) -> Result[Unit, String] {
  let status = match required_string(data, "status", path) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  match status {
    "observed-exactly-once"
    | "duplicate-observed"
    | "unobserved"
    | "bounded-by-proof" => ()
    _ => return Err(path + ": invalid status: " + status)
  }
  let owner = match
    required_string(data, "owning_implementation_or_issue", path) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  if owner == "" {
    return Err(path + ": owning_implementation_or_issue must not be empty")
  }
  let issue = match optional_string(data, "tracking_issue", path) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  match status {
    "unobserved" => {
      guard issue is Some(issue) else {
        return Err(path + ": unobserved row requires tracking_issue")
      }
      if !issue_reference_is_positive_integer(issue) {
        return Err(
          path + ": tracking_issue must be a positive integer issue reference",
        )
      }
      if !permitted_issues.contains(issue) {
        return Err(
          path +
          ": tracking_issue is not in the permitted Stage 4 registry: " +
          issue,
        )
      }
      if owner != issue {
        return Err(path + ": unobserved row owner must equal tracking_issue")
      }
      Ok(())
    }
    _ => {
      if issue is Some(_) {
        return Err(path + ": only unobserved rows may have tracking_issue")
      }
      if owner.has_prefix("#") {
        return Err(path + ": non-unobserved row owner must not begin with #")
      }
      Ok(())
    }
  }
}

///|
fn validate_accounting_owners(
  data : Map[String, Json],
  path : String,
) -> Result[Unit, String] {
  match validate_nonempty_string(data, "current_accounting_owner", path) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  validate_nonempty_string(data, "intended_final_accounting_owner", path)
}

///|
fn validate_manifest_and_collect_evidence(
  text : String,
  path : String,
) -> Result[Array[EvidenceReference], String] {
  let json = @json.parse(text) catch {
    _ => return Err(path + ": invalid JSON")
  }
  let data : Map[String, Json] = @json.from_json(json) catch {
    _ => return Err(path + ": manifest must be a JSON object")
  }
  let version : Int = match data.get("version") {
    Some(value) =>
      @json.from_json(value) catch {
        _ => return Err(path + ": version must be an integer")
      }
    None => return Err(path + ": missing key: version")
  }
  if version != SCHEMA_VERSION {
    return Err(path + ": version must be " + SCHEMA_VERSION.to_string())
  }
  let rows : Array[Map[String, Json]] = match data.get("rows") {
    Some(value) =>
      @json.from_json(value) catch {
        _ => return Err(path + ": rows must be an array of objects")
      }
    None => return Err(path + ": missing key: rows")
  }
  let permitted_issues = permitted_stage4_tracking_issues()
  let ids : Map[String, Bool] = Map([])
  let final_owners : Map[String, String] = Map([])
  let evidence : Array[EvidenceReference] = []
  for row in rows {
    let id : String = match row.get("id") {
      Some(value) =>
        @json.from_json(value) catch {
          _ => return Err(path + ": row id must be a string")
        }
      None => return Err(path + ": missing key: id")
    }
    if ids.contains(id) {
      return Err(path + ": duplicate row identifier: " + id)
    }
    ids[id] = true
    let row_path = path + ".rows[" + id + "]"
    match validate_operation_family(row, row_path) {
      Ok(_) => ()
      Err(message) => return Err(message)
    }
    match validate_accounting_owners(row, row_path) {
      Ok(_) => ()
      Err(message) => return Err(message)
    }
    let final_owner = match
      required_string(row, "intended_final_accounting_owner", row_path) {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    if final_owners.contains(final_owner) {
      return Err(path + ": duplicate final accounting owner: " + final_owner)
    }
    final_owners[final_owner] = id
    match validate_status_and_ownership(row, permitted_issues, row_path) {
      Ok(_) => ()
      Err(message) => return Err(message)
    }
    let focused_evidence = match
      validate_reference_array(row, "focused_evidence", row_path) {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    for reference in focused_evidence {
      evidence.push({ row_id: id, field: "focused_evidence", reference })
    }
    match validate_row_metadata(row, row_path) {
      Ok(_) => ()
      Err(message) => return Err(message)
    }
    let public_facade_evidence = match
      validate_public_facade_evidence(row, row_path) {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    for reference in public_facade_evidence {
      evidence.push({ row_id: id, field: "public_facade_evidence", reference })
    }
  }
  for family in operation_families() {
    if !rows.any(row => {
        match row.get("operation_family") {
          Some(value) => {
            let candidate : String = @json.from_json(value) catch { _ => "" }
            candidate == family
          }
          None => false
        }
      }) {
      return Err(path + ": missing operation family: " + family)
    }
  }
  Ok(evidence)
}

///|
pub fn validate_manifest_text(
  text : String,
  path : String,
) -> Result[Unit, String] {
  match validate_manifest_and_collect_evidence(text, path) {
    Ok(_) => Ok(())
    Err(message) => Err(message)
  }
}
