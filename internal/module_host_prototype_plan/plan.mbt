///|
// THROWAWAY internal interchange, not a public Program representation.
// Neither compiler AST nor Runtime values/environments occur in this package.
// Arrays are privately owned by the probe; this is not enforced immutability.
pub(all) enum Binding {
  Local(String, String)
  Default(String)
  Namespace(String)
} derive(ToJson)

///|
pub struct ModulePlan {
  key : String
  dependencies : Array[String]
  imports : Array[(String, Binding)]
  exports : Array[(String, Binding)]
} derive(ToJson)

///|
pub fn ModulePlan::ModulePlan(
  key : String,
  dependencies : Array[String],
  imports : Array[(String, Binding)],
  exports : Array[(String, Binding)],
) -> ModulePlan {
  { key, dependencies, imports, exports, }
}

///|
pub struct Plan {
  modules : Array[ModulePlan]
} derive(ToJson)

///|
pub fn Plan::Plan(modules : Array[ModulePlan]) -> Plan {
  { modules, }
}
