///|
fn register_error_ctor(
  env : Environment,
  name : String,
  parent_proto : Value,
) -> Value {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let proto_props : Map[String, Value] = {}
  proto_props["name"] = Value::String_(name)
  proto_props["message"] = Value::String_("")
  proto_props["toString"] = @runtime.make_method_func("toString", 0, fn(
    this_val,
    _args,
  ) raise {
    // Step 1: If this is not an Object, throw TypeError
    match this_val {
      Object(_) => ()
      _ =>
        raise @errors.TypeError(
          message="Error.prototype.toString requires that 'this' be an Object",
        )
    }
    let name_val = match this_val {
      Object(data) =>
        match data.properties.get("name") {
          Some(v) => v
          None => Undefined
        }
      _ => Undefined
    }
    let name_str = match name_val {
      Undefined => "Error"
      Value::String_(s) => s
      other => other.to_string()
    }
    let msg_val = match this_val {
      Object(data) =>
        match data.properties.get("message") {
          Some(v) => v
          None => Undefined
        }
      _ => Undefined
    }
    let msg_str = match msg_val {
      Undefined => ""
      Value::String_(s) => s
      other => other.to_string()
    }
    if name_str == "" {
      Value::String_(msg_str)
    } else if msg_str == "" {
      Value::String_(name_str)
    } else {
      Value::String_(name_str + ": " + msg_str)
    }
  })
  let proto_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  // Error.prototype class_name should be "Object" per spec (not error type name)
  let proto_obj : Value = Value::Object({
    properties: proto_props,
    symbol_properties: {},
    prototype: parent_proto,
    callable: None,
    class_name: "Object",
    descriptors: {
      "name": proto_desc,
      "message": proto_desc,
      "toString": proto_desc,
    },
    symbol_descriptors: {},
    extensible: true,
  })
  // Determine the parent constructor's [[Prototype]] for the error constructor
  // For Error itself, it should be Function.prototype (Null for now, set later)
  // For NativeErrors, it should be the Error constructor
  let ctor_proto : Value = if name == "Error" {
    Null
  } else {
    match env.bindings.get("Error") {
      Some(binding) => binding.value
      None => Null
    }
  }
  let proto_nw_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
  }
  env.def_builtin(
    name,
    Value::Object({
      properties: {
        "prototype": proto_obj,
        "name": Value::String_(name),
        "length": Value::Number(1.0),
      },
      symbol_properties: {},
      prototype: ctor_proto,
      callable: Some(
        NativeCallable(name, fn(args) {
          let has_message = args.length() > 0 && !(args[0] is Undefined)
          let message = if has_message {
            match args[0] {
              Value::String_(s) => s
              other => other.to_string()
            }
          } else {
            ""
          }
          let err_props : Map[String, Value] = {}
          if has_message {
            err_props["message"] = Value::String_(message)
          }
          err_props["stack"] = Value::String_(name + ": " + message)
          let err_desc : PropDescriptor = {
            writable: true,
            enumerable: false,
            configurable: true,
            getter: None,
            setter: None,
          }
          let err_descs : Map[String, PropDescriptor] = { "stack": err_desc }
          if has_message {
            err_descs["message"] = err_desc
          }
          // Handle options parameter for cause
          if args.length() > 1 {
            match args[1] {
              Object(opts_data) =>
                if opts_data.properties.contains("cause") {
                  err_props["cause"] = opts_data.properties["cause"]
                  err_descs["cause"] = err_desc
                }
              _ => ()
            }
          }
          Value::Object({
            properties: err_props,
            symbol_properties: {},
            prototype: proto_obj,
            callable: None,
            class_name: name,
            descriptors: err_descs,
            symbol_descriptors: {},
            extensible: true,
          })
        }),
      ),
      class_name: "Function",
      descriptors: {
        "name": nf_desc,
        "length": nf_desc,
        "prototype": proto_nw_desc,
      },
      symbol_descriptors: {},
      extensible: true,
    }),
  )
  // Set ErrorType.prototype.constructor = ErrorType
  match proto_obj {
    Object(data) => {
      let ctor = env.get(name) catch { _ => Undefined }
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
  proto_obj
}

///|
fn register_aggregate_error_ctor(
  env : Environment,
  parent_proto : Value,
) -> Value {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let name = "AggregateError"
  let proto_props : Map[String, Value] = {}
  proto_props["name"] = Value::String_(name)
  proto_props["message"] = Value::String_("")
  proto_props["toString"] = @runtime.make_method_func("toString", 0, fn(
    this_val,
    _args,
  ) raise {
    match this_val {
      Object(_) => ()
      _ =>
        raise @errors.TypeError(
          message="Error.prototype.toString requires that 'this' be an Object",
        )
    }
    let name_val = match this_val {
      Object(data) =>
        match data.properties.get("name") {
          Some(v) => v
          None => Undefined
        }
      _ => Undefined
    }
    let name_str = match name_val {
      Undefined => "Error"
      Value::String_(s) => s
      other => other.to_string()
    }
    let msg_val = match this_val {
      Object(data) =>
        match data.properties.get("message") {
          Some(v) => v
          None => Undefined
        }
      _ => Undefined
    }
    let msg_str = match msg_val {
      Undefined => ""
      Value::String_(s) => s
      other => other.to_string()
    }
    if name_str == "" {
      Value::String_(msg_str)
    } else if msg_str == "" {
      Value::String_(name_str)
    } else {
      Value::String_(name_str + ": " + msg_str)
    }
  })
  let proto_desc : PropDescriptor = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let proto_obj : Value = Value::Object({
    properties: proto_props,
    symbol_properties: {},
    prototype: parent_proto,
    callable: None,
    class_name: "Object",
    descriptors: {
      "name": proto_desc,
      "message": proto_desc,
      "toString": proto_desc,
    },
    symbol_descriptors: {},
    extensible: true,
  })
  // AggregateError constructor's [[Prototype]] should be the Error constructor
  let ctor_proto : Value = match env.bindings.get("Error") {
    Some(binding) => binding.value
    None => Null
  }
  let proto_nw_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
  }
  env.def_builtin(
    name,
    Value::Object({
      properties: {
        "prototype": proto_obj,
        "length": Value::Number(2.0),
        "name": Value::String_(name),
      },
      symbol_properties: {},
      prototype: ctor_proto,
      callable: Some(
        NativeCallable(name, fn(args) {
          let errors_value : Value = if args.length() > 0 {
            args[0]
          } else {
            Value::Array({ elements: [] })
          }
          let message = if args.length() > 1 {
            match args[1] {
              Value::String_(s) => s
              Undefined => ""
              other => other.to_string()
            }
          } else {
            ""
          }
          let err_props : Map[String, Value] = {}
          err_props["errors"] = errors_value
          err_props["message"] = Value::String_(message)
          err_props["name"] = Value::String_(name)
          err_props["stack"] = Value::String_(name + ": " + message)
          // Handle options parameter for cause
          if args.length() > 2 {
            match args[2] {
              Object(opts_data) =>
                if opts_data.properties.contains("cause") {
                  err_props["cause"] = opts_data.properties["cause"]
                }
              _ => ()
            }
          }
          let err_desc : PropDescriptor = {
            writable: true,
            enumerable: false,
            configurable: true,
            getter: None,
            setter: None,
          }
          let err_descs : Map[String, PropDescriptor] = {
            "message": err_desc,
            "name": err_desc,
            "stack": err_desc,
          }
          if err_props.contains("cause") {
            err_descs["cause"] = err_desc
          }
          Value::Object({
            properties: err_props,
            symbol_properties: {},
            prototype: proto_obj,
            callable: None,
            class_name: name,
            descriptors: err_descs,
            symbol_descriptors: {},
            extensible: true,
          })
        }),
      ),
      class_name: "Function",
      descriptors: {
        "name": nf_desc,
        "length": nf_desc,
        "prototype": proto_nw_desc,
      },
      symbol_descriptors: {},
      extensible: true,
    }),
  )
  match proto_obj {
    Object(data) => {
      let ctor = env.get(name) catch { _ => Undefined }
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
  proto_obj
}
