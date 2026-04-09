///|
fn setup_symbol_builtins(env : Environment) -> Unit {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  // Descriptor for well-known symbol properties: { writable: false, enumerable: false, configurable: false }
  let wks_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
  }
  // Descriptor for methods: { writable: true, enumerable: false, configurable: true }
  let method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  // Create well-known symbols
  let iterator_sym = new_symbol(Some("Symbol.iterator"))
  // Store globally for iterator protocol support
  well_known_iterator_sym.val = Some(iterator_sym)
  let to_primitive_sym = new_symbol(Some("Symbol.toPrimitive"))
  well_known_toprimitive_sym.val = Some(to_primitive_sym)
  let to_string_tag_sym = new_symbol(Some("Symbol.toStringTag"))
  well_known_tostringtag_sym.val = Some(to_string_tag_sym)
  let has_instance_sym = new_symbol(Some("Symbol.hasInstance"))
  // Store globally for instanceof operator support
  well_known_hasinstance_sym.val = Some(has_instance_sym)
  let is_concat_spreadable_sym = new_symbol(Some("Symbol.isConcatSpreadable"))
  well_known_isconcatspreadable_sym.val = Some(is_concat_spreadable_sym)
  let species_sym = new_symbol(Some("Symbol.species"))
  well_known_species_sym.val = Some(species_sym)
  let match_sym = new_symbol(Some("Symbol.match"))
  well_known_match_sym.val = Some(match_sym)
  let match_all_sym = new_symbol(Some("Symbol.matchAll"))
  well_known_matchall_sym.val = Some(match_all_sym)
  let replace_sym = new_symbol(Some("Symbol.replace"))
  well_known_replace_sym.val = Some(replace_sym)
  let search_sym = new_symbol(Some("Symbol.search"))
  well_known_search_sym.val = Some(search_sym)
  let split_sym = new_symbol(Some("Symbol.split"))
  well_known_split_sym.val = Some(split_sym)
  let unscopables_sym = new_symbol(Some("Symbol.unscopables"))
  well_known_unscopables_sym.val = Some(unscopables_sym)
  let async_iterator_sym = new_symbol(Some("Symbol.asyncIterator"))
  well_known_async_iterator_sym.val = Some(async_iterator_sym)

  // Symbol prototype
  let symbol_proto_props : Map[String, Value] = {}
  let symbol_proto_descs : Map[String, PropDescriptor] = {}
  symbol_proto_props["toString"] = make_method_func("toString", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Symbol(sym) =>
        match sym.description {
          Some(desc) => String_("Symbol(\{desc})")
          None => String_("Symbol()")
        }
      Object(data) =>
        // Support Symbol wrapper objects (e.g. Object(sym).toString())
        match data.properties.get("[[SymbolData]]") {
          Some(Symbol(sym)) =>
            match sym.description {
              Some(desc) => String_("Symbol(\{desc})")
              None => String_("Symbol()")
            }
          _ =>
            raise @errors.TypeError(
              message="Symbol.prototype.toString requires a Symbol",
            )
        }
      _ =>
        raise @errors.TypeError(
          message="Symbol.prototype.toString requires a Symbol",
        )
    }
  })
  symbol_proto_descs["toString"] = method_desc
  symbol_proto_props["valueOf"] = make_method_func("valueOf", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Symbol(_) => this_val
      Object(data) =>
        // Support Symbol wrapper objects
        match data.properties.get("[[SymbolData]]") {
          Some(sym) => sym
          _ =>
            raise @errors.TypeError(
              message="Symbol.prototype.valueOf requires a Symbol",
            )
        }
      _ =>
        raise @errors.TypeError(
          message="Symbol.prototype.valueOf requires a Symbol",
        )
    }
  })
  symbol_proto_descs["valueOf"] = method_desc
  // Symbol.prototype.description - getter per ES spec
  // Stored as a getter descriptor (not a plain value)
  let description_getter = make_method_func("get description", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Symbol(sym) =>
        match sym.description {
          Some(desc) => String_(desc)
          None => Undefined
        }
      Object(data) =>
        match data.properties.get("[[SymbolData]]") {
          Some(Symbol(sym)) =>
            match sym.description {
              Some(desc) => String_(desc)
              None => Undefined
            }
          _ =>
            raise @errors.TypeError(
              message="Symbol.prototype.description requires a Symbol",
            )
        }
      _ =>
        raise @errors.TypeError(
          message="Symbol.prototype.description requires a Symbol",
        )
    }
  })
  // Set a placeholder in properties so hasOwnProperty returns true
  symbol_proto_props["description"] = Undefined
  symbol_proto_descs["description"] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(description_getter),
    setter: None,
  }

  // Symbol.prototype[@@toPrimitive](hint)
  let symbol_proto_sym_props : Map[Int, Value] = {}
  let symbol_proto_sym_descs : Map[Int, PropDescriptor] = {}
  let toprimitive_method = make_method_func("[Symbol.toPrimitive]", 1, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Symbol(_) => this_val
      Object(data) =>
        match data.properties.get("[[SymbolData]]") {
          Some(sym) => sym
          _ =>
            raise @errors.TypeError(
              message="Symbol[Symbol.toPrimitive] requires a Symbol",
            )
        }
      _ =>
        raise @errors.TypeError(
          message="Symbol[Symbol.toPrimitive] requires a Symbol",
        )
    }
  })
  symbol_proto_sym_props[to_primitive_sym.id] = toprimitive_method
  symbol_proto_sym_descs[to_primitive_sym.id] = {
    ..wks_desc,
    configurable: true,
  }

  // Symbol.prototype[@@toStringTag] = "Symbol"
  symbol_proto_sym_props[to_string_tag_sym.id] = String_("Symbol")
  symbol_proto_sym_descs[to_string_tag_sym.id] = nf_desc

  let symbol_proto : Value = Object({
    properties: symbol_proto_props,
    symbol_properties: symbol_proto_sym_props,
    prototype: get_obj_proto(),
    callable: None,
    class_name: "Symbol",
    descriptors: symbol_proto_descs,
    symbol_descriptors: symbol_proto_sym_descs,
    extensible: true,
  })

  // Symbol constructor properties
  let symbol_props : Map[String, Value] = {}
  let symbol_descs : Map[String, PropDescriptor] = {}
  symbol_props["prototype"] = symbol_proto
  symbol_descs["prototype"] = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
  }

  // Well-known symbols as static properties (all { writable: false, enumerable: false, configurable: false })
  symbol_props["iterator"] = Symbol(iterator_sym)
  symbol_descs["iterator"] = { ..wks_desc }
  symbol_props["toPrimitive"] = Symbol(to_primitive_sym)
  symbol_descs["toPrimitive"] = { ..wks_desc }
  symbol_props["toStringTag"] = Symbol(to_string_tag_sym)
  symbol_descs["toStringTag"] = { ..wks_desc }
  symbol_props["hasInstance"] = Symbol(has_instance_sym)
  symbol_descs["hasInstance"] = { ..wks_desc }
  symbol_props["isConcatSpreadable"] = Symbol(is_concat_spreadable_sym)
  symbol_descs["isConcatSpreadable"] = { ..wks_desc }
  symbol_props["species"] = Symbol(species_sym)
  symbol_descs["species"] = { ..wks_desc }
  symbol_props["match"] = Symbol(match_sym)
  symbol_descs["match"] = { ..wks_desc }
  symbol_props["matchAll"] = Symbol(match_all_sym)
  symbol_descs["matchAll"] = { ..wks_desc }
  symbol_props["replace"] = Symbol(replace_sym)
  symbol_descs["replace"] = { ..wks_desc }
  symbol_props["search"] = Symbol(search_sym)
  symbol_descs["search"] = { ..wks_desc }
  symbol_props["split"] = Symbol(split_sym)
  symbol_descs["split"] = { ..wks_desc }
  symbol_props["unscopables"] = Symbol(unscopables_sym)
  symbol_descs["unscopables"] = { ..wks_desc }
  symbol_props["asyncIterator"] = Symbol(async_iterator_sym)
  symbol_descs["asyncIterator"] = { ..wks_desc }

  // Symbol.for(key) - returns symbol from global registry
  // Spec: 1. Let stringKey be ? ToString(key).  (throws TypeError for symbols)
  symbol_props["for"] = make_static_func_with_length("for", 1, fn(args) raise {
    let arg = if args.length() > 0 { args[0] } else { Undefined }
    let key : String = match arg {
      Symbol(_) =>
        raise @errors.TypeError(
          message="Cannot convert a Symbol value to a string",
        )
      _ => arg.to_string()
    }
    match global_symbol_registry.get(key) {
      Some(sym) => Symbol(sym)
      None => {
        let sym = new_symbol(Some(key))
        global_symbol_registry[key] = sym
        symbol_registry_reverse[sym.id] = key // O(1) reverse lookup
        Symbol(sym)
      }
    }
  })
  symbol_descs["for"] = method_desc

  // Symbol.keyFor(sym) - returns key for symbol in global registry (O(1) via reverse lookup)
  symbol_props["keyFor"] = make_static_func_with_length("keyFor", 1, fn(
    args,
  ) raise {
    let sym = if args.length() > 0 { args[0] } else { Undefined }
    match sym {
      Symbol(sym_data) =>
        match symbol_registry_reverse.get(sym_data.id) {
          Some(key) => String_(key)
          None => Undefined
        }
      _ => raise @errors.TypeError(message="Symbol.keyFor requires a symbol")
    }
  })
  symbol_descs["keyFor"] = method_desc

  // Symbol constructor - cannot be called with new, only as function
  symbol_props["name"] = String_("Symbol")
  symbol_descs["name"] = nf_desc
  symbol_props["length"] = Number(0.0)
  symbol_descs["length"] = nf_desc
  env.def_builtin(
    "Symbol",
    Object({
      properties: symbol_props,
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        NonConstructableCallable("Symbol", fn(args) raise {
          let description : String? = if args.length() > 0 {
            match args[0] {
              Undefined => None
              Symbol(_) =>
                raise @errors.TypeError(
                  message="Cannot convert a Symbol value to a string",
                )
              _ => Some(args[0].to_string())
            }
          } else {
            None
          }
          Symbol(new_symbol(description))
        }),
      ),
      class_name: "Function",
      descriptors: symbol_descs,
      symbol_descriptors: {},
      extensible: true,
    }),
  )
  env.def_builtin("[[SymbolPrototype]]", symbol_proto)
  symbol_prototype_ref.val = Some(symbol_proto)
  // Set Symbol.prototype.constructor = Symbol
  match symbol_proto {
    Object(data) => {
      let ctor = env.get("Symbol") catch { _ => Undefined }
      data.properties["constructor"] = ctor
      data.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }
}
