///|
fn inventory_path(root : String) -> String {
  @path_utils.join_path(root, "scripts/execution_observation_inventory.json")
}

///|
fn validate_source_evidence(
  root : String,
  evidence : Array[EvidenceReference],
) -> Result[Unit, String] {
  let absolute_root = @path_utils.absolute_path(root)
  let canonical_root = match canonical_realpath(absolute_root) {
    Ok(path) => path
    Err(_) => return Err("repository root cannot be canonicalized: " + root)
  }
  let root_prefix = if absolute_root.has_suffix("/") {
    absolute_root
  } else {
    absolute_root + "/"
  }
  let canonical_root_prefix = if canonical_root.has_suffix("/") {
    canonical_root
  } else {
    canonical_root + "/"
  }
  for item in evidence {
    let parts = item.reference.split("#").to_array()
    let relative_path = parts[0].to_owned()
    let anchor = parts[1].to_owned()
    let source_path = @path_utils.absolute_path(
      @path_utils.join_path(absolute_root, relative_path),
    )
    if source_path == absolute_root || !source_path.has_prefix(root_prefix) {
      return Err(
        "row " +
        item.row_id +
        ": " +
        item.field +
        " evidence path escapes repository root: " +
        relative_path,
      )
    }
    let is_file = @fs.is_file(source_path) catch { _ => false }
    if !@fs.path_exists(source_path) || !is_file {
      return Err(
        "row " +
        item.row_id +
        ": " +
        item.field +
        " evidence path does not exist or is not a file: " +
        relative_path,
      )
    }
    let canonical_source = match canonical_realpath(source_path) {
      Ok(path) => path
      Err(_) =>
        return Err(
          "row " +
          item.row_id +
          ": " +
          item.field +
          " evidence path could not be canonicalized: " +
          relative_path,
        )
    }
    if canonical_source == canonical_root ||
      !canonical_source.has_prefix(canonical_root_prefix) {
      return Err(
        "row " +
        item.row_id +
        ": " +
        item.field +
        " evidence path escapes repository root: " +
        relative_path,
      )
    }
    let source = @fs.read_file_to_string(canonical_source) catch {
      _ =>
        return Err(
          "row " +
          item.row_id +
          ": " +
          item.field +
          " evidence path is not readable: " +
          relative_path,
        )
    }
    if !source.contains(anchor) {
      return Err(
        "row " +
        item.row_id +
        ": " +
        item.field +
        " evidence anchor not found in " +
        relative_path +
        ": " +
        anchor,
      )
    }
  }
  Ok(())
}

///|
pub fn run(root~ : String) -> (Array[String], Array[String], Int) {
  let path = inventory_path(root)
  let source = @fs.read_file_to_string(path) catch {
    _ =>
      return (
        [],
        [
          "execution observation inventory failed:", "- inventory manifest could not be read",
        ],
        1,
      )
  }
  match validate_manifest_and_collect_evidence(source, path) {
    Ok(evidence) =>
      match validate_source_evidence(root, evidence) {
        Ok(_) => (["ok: execution observation inventory is valid"], [], 0)
        Err(message) =>
          ([], ["execution observation inventory failed:", "- " + message], 1)
      }
    Err(message) =>
      ([], ["execution observation inventory failed:", "- " + message], 1)
  }
}
