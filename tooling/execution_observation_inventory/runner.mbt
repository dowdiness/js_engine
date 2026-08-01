///|
fn inventory_path(root : String) -> String {
  @path_utils.join_path(root, "scripts/execution_observation_inventory.json")
}

///|
fn validate_source_evidence(
  root : String,
  evidence : Array[EvidenceReference],
) -> Result[Unit, String] {
  for item in evidence {
    let parts = item.reference.split("#").to_array()
    let relative_path = parts[0].to_owned()
    let anchor = parts[1].to_owned()
    let source_path = @path_utils.join_path(root, relative_path)
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
    let source = @fs.read_file_to_string(source_path) catch {
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
pub fn run(root~ : String) -> (Array[String], Array[String], Int) raise {
  let path = inventory_path(root)
  let source = @fs.read_file_to_string(path)
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
