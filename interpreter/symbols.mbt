///|
/// Flag set by eval_new before calling a NativeCallable so the callee can
/// distinguish `new Foo()` from `Foo()`.  Safe because NativeCallable has
/// no Interpreter access and therefore cannot re-enter eval_new.
pub let is_constructing : Ref[Bool] = { val: false }

///|
/// Check if a Value is a constructor (has [[Construct]] internal method)
pub fn is_constructor_value(v : Value) -> Bool {
  match v {
    Object(data) =>
      match data.callable {
        Some(UserFunc(_)) | Some(UserFuncExt(_)) => true
        Some(NativeCallable(_, _)) => true
        Some(ClassConstructor(_)) => true
        Some(ConstructorOnlyCallable(_, _)) => true
        Some(BoundFunc(target, _, _)) => is_constructor_value(target)
        Some(NonConstructableCallable(_, _)) => false
        Some(MethodCallable(_, _)) => false
        Some(InterpreterCallable(_, _)) =>
          // InterpreterCallable is a constructor if it has a prototype property
          // (builtin constructors like Map, Set, Promise have prototype)
          data.properties.contains("prototype")
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
/// Global counter for generating unique symbol IDs
let symbol_id_counter : Ref[Int] = { val: 0 }

///|
/// Global map of all symbols by ID (for looking up symbols from property keys)
let all_symbols : Map[Int, SymbolData] = {}

///|
/// Create a new symbol with a unique ID
pub fn new_symbol(description : String?) -> SymbolData {
  let id = symbol_id_counter.val
  symbol_id_counter.val = id + 1
  let sym : SymbolData = { id, description }
  all_symbols[id] = sym
  sym
}

///|
/// Get a symbol by its ID
pub fn get_symbol_by_id(id : Int) -> SymbolData? {
  all_symbols.get(id)
}

///|
/// Global symbol registry for Symbol.for() and Symbol.keyFor()
let global_symbol_registry : Map[String, SymbolData] = {}

///|
/// Reverse lookup: symbol ID -> registry key (for O(1) Symbol.keyFor)
let symbol_registry_reverse : Map[Int, String] = {}

///|
/// Well-known Symbol.iterator - stored globally for iterator protocol support
pub let well_known_iterator_sym : Ref[SymbolData?] = { val: None }

///|
/// Well-known Symbol.asyncIterator - stored globally for async iteration support
pub let well_known_async_iterator_sym : Ref[SymbolData?] = { val: None }

///|
/// Well-known Symbol.hasInstance - stored globally for instanceof operator support
pub let well_known_hasinstance_sym : Ref[SymbolData?] = { val: None }

///|
/// Get the well-known Symbol.iterator
pub fn get_iterator_symbol() -> SymbolData {
  match well_known_iterator_sym.val {
    Some(sym) => sym
    None => abort("Symbol.iterator not initialized")
  }
}

///|
/// Get the well-known Symbol.asyncIterator
pub fn get_async_iterator_symbol() -> SymbolData {
  match well_known_async_iterator_sym.val {
    Some(sym) => sym
    None => abort("Symbol.asyncIterator not initialized")
  }
}

///|
/// Get the well-known Symbol.hasInstance
pub fn get_hasinstance_symbol() -> SymbolData {
  match well_known_hasinstance_sym.val {
    Some(sym) => sym
    None => abort("Symbol.hasInstance not initialized")
  }
}

///|
/// Well-known Symbol.isConcatSpreadable
pub let well_known_isconcatspreadable_sym : Ref[SymbolData?] = { val: None }

///|
pub fn get_isconcatspreadable_symbol() -> SymbolData {
  match well_known_isconcatspreadable_sym.val {
    Some(sym) => sym
    None => abort("Symbol.isConcatSpreadable not initialized")
  }
}

///|
/// Well-known Symbol.toPrimitive - stored globally for @@toPrimitive support
pub let well_known_toprimitive_sym : Ref[SymbolData?] = { val: None }

///|
/// Get the well-known Symbol.toPrimitive
pub fn get_toprimitive_symbol() -> SymbolData {
  match well_known_toprimitive_sym.val {
    Some(sym) => sym
    None => abort("Symbol.toPrimitive not initialized")
  }
}

///|
/// Well-known Symbol.toStringTag - stored globally for @@toStringTag support
pub let well_known_tostringtag_sym : Ref[SymbolData?] = { val: None }

///|
/// Get the well-known Symbol.toStringTag
pub fn get_tostringtag_symbol() -> SymbolData {
  match well_known_tostringtag_sym.val {
    Some(sym) => sym
    None => abort("Symbol.toStringTag not initialized")
  }
}

///|
/// Well-known Symbol.match - stored globally for RegExp @@match support
pub let well_known_match_sym : Ref[SymbolData?] = { val: None }

///|
/// Well-known Symbol.replace - stored globally for RegExp @@replace support
pub let well_known_replace_sym : Ref[SymbolData?] = { val: None }

///|
/// Well-known Symbol.search - stored globally for RegExp @@search support
pub let well_known_search_sym : Ref[SymbolData?] = { val: None }

///|
/// Well-known Symbol.species - stored globally for @@species support
pub let well_known_species_sym : Ref[SymbolData?] = { val: None }

///|
/// Get the well-known Symbol.species
pub fn get_species_symbol() -> SymbolData {
  match well_known_species_sym.val {
    Some(sym) => sym
    None => abort("Symbol.species not initialized")
  }
}

///|
/// Well-known Symbol.matchAll - stored globally for RegExp @@matchAll support
pub let well_known_matchall_sym : Ref[SymbolData?] = { val: None }

///|
/// Well-known Symbol.split - stored globally for RegExp @@split support
pub let well_known_split_sym : Ref[SymbolData?] = { val: None }

///|
/// Get the well-known Symbol.match
pub fn get_match_symbol() -> SymbolData {
  match well_known_match_sym.val {
    Some(sym) => sym
    None => abort("Symbol.match not initialized")
  }
}

///|
/// Get the well-known Symbol.replace
pub fn get_replace_symbol() -> SymbolData {
  match well_known_replace_sym.val {
    Some(sym) => sym
    None => abort("Symbol.replace not initialized")
  }
}

///|
/// Get the well-known Symbol.search
pub fn get_search_symbol() -> SymbolData {
  match well_known_search_sym.val {
    Some(sym) => sym
    None => abort("Symbol.search not initialized")
  }
}

///|
/// Get the well-known Symbol.split
pub fn get_split_symbol() -> SymbolData {
  match well_known_split_sym.val {
    Some(sym) => sym
    None => abort("Symbol.split not initialized")
  }
}

///|
/// Get the well-known Symbol.matchAll
pub fn get_matchall_symbol() -> SymbolData {
  match well_known_matchall_sym.val {
    Some(sym) => sym
    None => abort("Symbol.matchAll not initialized")
  }
}

///|
/// Well-known Symbol.unscopables - stored globally for with statement support
pub let well_known_unscopables_sym : Ref[SymbolData?] = { val: None }

///|
/// Get the well-known Symbol.unscopables
pub fn get_unscopables_symbol() -> SymbolData {
  match well_known_unscopables_sym.val {
    Some(sym) => sym
    None => abort("Symbol.unscopables not initialized")
  }
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
        match obj_data.symbol_descriptors.get(sym.id) {
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
        match obj_data.symbol_properties.get(sym.id) {
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
