///|
fn setup_symbol_builtins(
  env : Environment,
  realm_state : @runtime.RealmState,
) -> Unit {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  // Descriptor for well-known symbol properties: { writable: false, enumerable: false, configurable: false }
  let wks_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  // Descriptor for methods: { writable: true, enumerable: false, configurable: true }
  let method_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  // Well-known symbols are allocated from the SymbolState passed to public
  // setup, so standalone setup_builtins reserves the same IDs Symbol() uses.
  let symbols = realm_state.symbols
  let well_known = symbols.well_known_symbols()
  let iterator_sym = well_known.iterator
  let to_primitive_sym = well_known.to_primitive
  let to_string_tag_sym = well_known.to_string_tag
  let has_instance_sym = well_known.has_instance
  let is_concat_spreadable_sym = well_known.is_concat_spreadable
  let species_sym = well_known.species
  let match_sym = well_known.match_sym
  let match_all_sym = well_known.match_all
  let replace_sym = well_known.replace
  let search_sym = well_known.search
  let split_sym = well_known.split
  let unscopables_sym = well_known.unscopables
  let async_iterator_sym = well_known.async_iterator

  // Symbol prototype
  let symbol_proto_props : Map[String, Value] = {}
  let symbol_proto_descs : Map[String, PropDescriptor] = {}
  symbol_proto_props["toString"] = @runtime.make_method_func(
    name="toString",
    length=0,
    fn(this_val, _args) raise {
      match this_val {
        Value::Symbol(sym) =>
          match sym.description {
            Some(desc) => Value::String_("Symbol(\{desc})")
            None => Value::String_("Symbol()")
          }
        Object(data) =>
          // Support Symbol wrapper objects (e.g. Object(sym).toString())
          match data.bag.internal_slots.get(@runtime.SymbolData) {
            Some(Value::Symbol(sym)) =>
              match sym.description {
                Some(desc) => Value::String_("Symbol(\{desc})")
                None => Value::String_("Symbol()")
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
    },
  )
  symbol_proto_descs["toString"] = method_desc
  symbol_proto_props["valueOf"] = @runtime.make_method_func(
    name="valueOf",
    length=0,
    fn(this_val, _args) raise {
      match this_val {
        Symbol(_) => this_val
        Object(data) =>
          // Support Symbol wrapper objects
          match data.bag.internal_slots.get(@runtime.SymbolData) {
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
    },
  )
  symbol_proto_descs["valueOf"] = method_desc
  // Symbol.prototype.description - getter per ES spec
  // Stored as a getter descriptor (not a plain value)
  let description_getter = @runtime.make_method_func(
    name="get description",
    length=0,
    fn(this_val, _args) raise {
      match this_val {
        Value::Symbol(sym) =>
          match sym.description {
            Some(desc) => Value::String_(desc)
            None => Undefined
          }
        Object(data) =>
          match data.bag.internal_slots.get(@runtime.SymbolData) {
            Some(Value::Symbol(sym)) =>
              match sym.description {
                Some(desc) => Value::String_(desc)
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
    },
  )
  // Set a placeholder in properties so hasOwnProperty returns true
  symbol_proto_props["description"] = Undefined
  symbol_proto_descs["description"] = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: Some(description_getter),
    setter: None,
    is_accessor: true,
  }

  // Symbol.prototype[@@toPrimitive](hint)
  let symbol_proto_sym_props : Map[Int, Value] = {}
  let symbol_proto_sym_descs : Map[Int, PropDescriptor] = {}
  let toprimitive_method = @runtime.make_method_func(
    name="[Symbol.toPrimitive]",
    length=1,
    fn(this_val, _args) raise {
      match this_val {
        Symbol(_) => this_val
        Object(data) =>
          match data.bag.internal_slots.get(@runtime.SymbolData) {
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
    },
  )
  symbol_proto_sym_props[to_primitive_sym.id] = toprimitive_method
  symbol_proto_sym_descs[to_primitive_sym.id] = {
    ..wks_desc,
    configurable: true,
  }

  // Symbol.prototype[@@toStringTag] = "Symbol"
  symbol_proto_sym_props[to_string_tag_sym.id] = Value::String_("Symbol")
  symbol_proto_sym_descs[to_string_tag_sym.id] = nf_desc

  let symbol_proto : Value = Value::Object({
    bag: {
      properties: symbol_proto_props,
      symbol_properties: symbol_proto_sym_props,
      descriptors: symbol_proto_descs,
      symbol_descriptors: symbol_proto_sym_descs,
      internal_slots: {},
      host_slots: {},
    },
    prototype: @runtime.get_obj_proto(realm_state=Some(realm_state)),
    callable: None,
    class_name: "Symbol",
    extensible: true,
    arraybuffer_state: None,
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
    is_accessor: false,
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
  symbol_props["for"] = @runtime.make_native_func(name="for", length=1, fn(
    args,
  ) raise {
    let arg = if args.length() > 0 { args[0] } else { Undefined }
    let key : String = match arg {
      Symbol(_) =>
        raise @errors.TypeError(
          message="Cannot convert a Symbol value to a string",
        )
      _ => arg.to_string()
    }
    match symbols.global_symbol_registry.get(key) {
      Some(sym) => Value::Symbol(sym)
      None => {
        let sym = symbols.new_symbol(Some(key))
        symbols.global_symbol_registry[key] = sym
        symbols.symbol_registry_reverse[sym.id] = key // O(1) reverse lookup
        Value::Symbol(sym)
      }
    }
  })
  symbol_descs["for"] = method_desc

  // Symbol.keyFor(sym) - returns key for symbol in global registry (O(1) via reverse lookup)
  symbol_props["keyFor"] = @runtime.make_native_func(name="keyFor", length=1, fn(
    args,
  ) raise {
    let sym = if args.length() > 0 { args[0] } else { Undefined }
    match sym {
      Symbol(sym_data) =>
        match symbols.symbol_registry_reverse.get(sym_data.id) {
          Some(key) => Value::String_(key)
          None => Undefined
        }
      _ => raise @errors.TypeError(message="Symbol.keyFor requires a symbol")
    }
  })
  symbol_descs["keyFor"] = method_desc

  // Symbol constructor - cannot be called with new, only as function
  symbol_props["name"] = Value::String_("Symbol")
  symbol_descs["name"] = nf_desc
  symbol_props["length"] = Value::Number(0.0)
  symbol_descs["length"] = nf_desc
  let symbol_ctor : Value = Value::Object({
    bag: {
      properties: symbol_props,
      symbol_properties: {},
      descriptors: symbol_descs,
      symbol_descriptors: {},
      internal_slots: {},
      host_slots: {},
    },
    prototype: Null,
    callable: Some(
      InterpreterCallableWithContext("Symbol", fn(
        _interp,
        context,
        _this_val,
        args,
      ) raise {
        if context.is_constructing() {
          raise @errors.TypeError(message="Symbol is not a constructor")
        }
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
        Symbol(symbols.new_symbol(description))
      }),
    ),
    class_name: "Function",
    extensible: true,
    arraybuffer_state: None,
  })
  env.def_builtin("[[SymbolPrototype]]", symbol_proto)
  @runtime.install_realm_pinned_builtin_constructor(
    env,
    realm_state.symbol_prototype,
    "Symbol",
    symbol_ctor,
    symbol_proto,
    prototype_install=@runtime.BuiltinCtorPrototypeInstall::PreBagged,
    wire_proto_constructor=true,
  )
}
