///|
#borrow(path)
extern "c" fn native_realpath(path : Bytes) -> Bytes = "moonbit_execution_observation_inventory_realpath"

///|
fn canonical_realpath(path : String) -> Result[String, String] {
  let canonical_bytes = native_realpath(@utf8.encode(path))
  if canonical_bytes.length() == 0 {
    Err("could not canonicalize path: " + path)
  } else {
    Ok(@utf8.decode(canonical_bytes[:])) catch {
      _ => Err("canonical path was not valid UTF-8: " + path)
    }
  }
}
