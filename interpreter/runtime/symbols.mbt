///|
/// Flag set by eval_new before calling a NativeCallable so the callee can
/// distinguish `new Foo()` from `Foo()`.  Safe because NativeCallable has
/// no Interpreter access and therefore cannot re-enter eval_new.
pub let is_constructing : Ref[Bool] = { val: false }

///|
fn interpreter_callable_is_constructor(data : ObjectData) -> Bool {
  data.bag.properties.contains("prototype") &&
  data.class_name != "GeneratorFunction" &&
  data.class_name != "AsyncGeneratorFunction"
}

///|
/// Check if a Value is a constructor (has [[Construct]] internal method)
pub fn is_constructor_value(v : Value) -> Bool {
  match v {
    Object(data) =>
      match data.callable {
        Some(UserFunc(fd)) => !fd.is_method
        Some(UserFuncExt(fd)) => !fd.is_method
        Some(NativeCallable(_, _)) => true
        Some(ClassConstructor(_)) => true
        Some(ConstructorOnlyCallable(_, _)) => true
        Some(BoundFunc(target, _, _)) => is_constructor_value(target)
        Some(NonConstructableCallable(_, _)) => false
        Some(NonConstructableInterpreterCallable(_, _)) => false
        Some(MethodCallable(_, _)) => false
        Some(InterpreterCallable(_, _)) =>
          // InterpreterCallable is a constructor if it has a prototype property
          // (builtin constructors like Map, Set, Promise have prototype).
          // Generator functions are the spec-visible exception: they have a
          // prototype property but no [[Construct]].
          interpreter_callable_is_constructor(data)
        Some(ArrowFunc(_)) | Some(ArrowFuncExt(_)) => false
        Some(FuncCallMethod(_)) | Some(FuncApplyMethod(_)) => false
        None => false
      }
    Proxy(pd) =>
      match pd.target {
        Some(inner) => is_constructor_value(inner)
        None => false
      }
    _ => false
  }
}

///|
/// Check if a Value is a function (has a callable)
pub fn is_function_value(v : Value) -> Bool {
  match v {
    Object(data) => data.callable is Some(_)
    _ => false
  }
}

///|
/// Check if a Value is an object per ES Type(v) is Object (§6.1.7).
/// Returns true for any Value variant that represents a JavaScript object
/// reference; false for language primitives (Number, String_, Bool, Null,
/// Undefined, Symbol, BigInt).
pub fn is_object_value(v : Value) -> Bool {
  match v {
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => true
    _ => false
  }
}

///|
/// Per-interpreter symbol state: ID counter, all-symbols table,
/// and the Symbol.for() / Symbol.keyFor() registry.
/// Passed through setup functions so that closures can capture it
/// without needing an Interpreter reference.
pub(all) struct SymbolState {
  symbol_id_counter : Ref[Int]
  all_symbols : Map[Int, SymbolData]
  global_symbol_registry : Map[String, SymbolData]
  symbol_registry_reverse : Map[Int, String]
  well_known_symbols_cache : Ref[WellKnownSymbols?]
}

///|
pub fn SymbolState::new() -> SymbolState {
  {
    symbol_id_counter: { val: 0 },
    all_symbols: {},
    global_symbol_registry: {},
    symbol_registry_reverse: {},
    well_known_symbols_cache: { val: None },
  }
}

///|
/// Create a new symbol with a unique ID, registering it in this SymbolState.
pub fn SymbolState::new_symbol(
  self : SymbolState,
  description : String?,
) -> SymbolData {
  let id = self.symbol_id_counter.val
  self.symbol_id_counter.val = id + 1
  let sym : SymbolData = { id, description }
  self.all_symbols[id] = sym
  sym
}

///|
/// Get a symbol by its ID from this SymbolState.
pub fn SymbolState::get_symbol_by_id(
  self : SymbolState,
  id : Int,
) -> SymbolData? {
  self.all_symbols.get(id)
}

///|
/// Realm-owned well-known symbol identities.
///
/// These values are allocated from the realm's SymbolState before user code can
/// create symbols, preserving the existing well-known symbol IDs while moving
/// ownership out of per-symbol module globals.
pub(all) struct WellKnownSymbols {
  iterator : SymbolData
  async_iterator : SymbolData
  has_instance : SymbolData
  is_concat_spreadable : SymbolData
  to_primitive : SymbolData
  to_string_tag : SymbolData
  match_sym : SymbolData
  match_all : SymbolData
  replace : SymbolData
  search : SymbolData
  species : SymbolData
  split : SymbolData
  unscopables : SymbolData
}

///|
fn WellKnownSymbols::WellKnownSymbols(
  symbols : SymbolState,
) -> WellKnownSymbols {
  {
    iterator: symbols.new_symbol(Some("Symbol.iterator")),
    to_primitive: symbols.new_symbol(Some("Symbol.toPrimitive")),
    to_string_tag: symbols.new_symbol(Some("Symbol.toStringTag")),
    has_instance: symbols.new_symbol(Some("Symbol.hasInstance")),
    is_concat_spreadable: symbols.new_symbol(Some("Symbol.isConcatSpreadable")),
    species: symbols.new_symbol(Some("Symbol.species")),
    match_sym: symbols.new_symbol(Some("Symbol.match")),
    match_all: symbols.new_symbol(Some("Symbol.matchAll")),
    replace: symbols.new_symbol(Some("Symbol.replace")),
    search: symbols.new_symbol(Some("Symbol.search")),
    split: symbols.new_symbol(Some("Symbol.split")),
    unscopables: symbols.new_symbol(Some("Symbol.unscopables")),
    async_iterator: symbols.new_symbol(Some("Symbol.asyncIterator")),
  }
}

///|
let legacy_well_known_symbols : Ref[WellKnownSymbols?] = { val: None }

///|
fn install_well_known_symbols(symbols : WellKnownSymbols) -> Unit {
  legacy_well_known_symbols.val = Some(symbols)
}

///|
pub fn SymbolState::well_known_symbols(self : SymbolState) -> WellKnownSymbols {
  match self.well_known_symbols_cache.val {
    Some(symbols) => {
      install_well_known_symbols(symbols)
      symbols
    }
    None => {
      let symbols = WellKnownSymbols(self)
      self.well_known_symbols_cache.val = Some(symbols)
      install_well_known_symbols(symbols)
      symbols
    }
  }
}

///|
fn installed_well_known_symbols() -> WellKnownSymbols {
  match legacy_well_known_symbols.val {
    Some(symbols) => symbols
    None => abort("well-known symbols not initialized")
  }
}

///|
/// Get the well-known Symbol.iterator
pub fn get_iterator_symbol() -> SymbolData {
  installed_well_known_symbols().iterator
}

///|
/// Get the well-known Symbol.asyncIterator
pub fn get_async_iterator_symbol() -> SymbolData {
  installed_well_known_symbols().async_iterator
}

///|
/// Get the well-known Symbol.hasInstance
pub fn get_hasinstance_symbol() -> SymbolData {
  installed_well_known_symbols().has_instance
}

///|
pub fn get_isconcatspreadable_symbol() -> SymbolData {
  installed_well_known_symbols().is_concat_spreadable
}

///|
/// Get the well-known Symbol.toPrimitive
pub fn get_toprimitive_symbol() -> SymbolData {
  installed_well_known_symbols().to_primitive
}

///|
/// Get the well-known Symbol.toStringTag
pub fn get_tostringtag_symbol() -> SymbolData {
  installed_well_known_symbols().to_string_tag
}

///|
/// Get the well-known Symbol.species
pub fn get_species_symbol() -> SymbolData {
  installed_well_known_symbols().species
}

///|
/// Get the well-known Symbol.match
pub fn get_match_symbol() -> SymbolData {
  installed_well_known_symbols().match_sym
}

///|
/// Get the well-known Symbol.replace
pub fn get_replace_symbol() -> SymbolData {
  installed_well_known_symbols().replace
}

///|
/// Get the well-known Symbol.search
pub fn get_search_symbol() -> SymbolData {
  installed_well_known_symbols().search
}

///|
/// Get the well-known Symbol.split
pub fn get_split_symbol() -> SymbolData {
  installed_well_known_symbols().split
}

///|
/// Get the well-known Symbol.matchAll
pub fn get_matchall_symbol() -> SymbolData {
  installed_well_known_symbols().match_all
}

///|
/// Get the well-known Symbol.unscopables
pub fn get_unscopables_symbol() -> SymbolData {
  installed_well_known_symbols().unscopables
}

///|
/// Get the Symbol.toStringTag value by walking the prototype chain.
/// Checks symbol properties and evaluates getter descriptors if present.
/// Per spec, errors thrown by @@toStringTag getters propagate to the caller.
pub fn get_tostringtag_value(data : ObjectData) -> String? raise Error {
  let sym = get_tostringtag_symbol()
  // Walk the object and its prototype chain
  let mut current : Value = Object(data)
  while true {
    match current {
      Object(obj_data) => {
        // Check for getter descriptor on symbol property
        match obj_data.bag.symbol_descriptors.get(sym.id) {
          Some(desc) =>
            match desc.getter {
              Some(getter_fn) =>
                // Call the getter with the original object as `this`
                match getter_fn {
                  Object(getter_data) =>
                    match getter_data.callable {
                      Some(MethodCallable(_, f)) => {
                        let result = f(Object(data), [])
                        match result {
                          String_(s) => return Some(s)
                          _ => return None
                        }
                      }
                      Some(NativeCallable(_, f))
                      | Some(NonConstructableCallable(_, f)) => {
                        let result = f([Object(data)])
                        match result {
                          String_(s) => return Some(s)
                          _ => return None
                        }
                      }
                      _ => return None
                    }
                  _ => return None
                }
              None => ()
            }
          None => ()
        }
        // Check direct symbol property value
        match obj_data.bag.symbol_properties.get(sym.id) {
          Some(String_(s)) => return Some(s)
          Some(_) => return None // non-string toStringTag, short-circuit per spec
          None => ()
        }
        current = obj_data.prototype
      }
      _ => break
    }
  }
  None
}
