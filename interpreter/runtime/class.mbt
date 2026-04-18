///|
/// Ensure a function body starts with "use strict" directive.
/// Returns the body unchanged if it already has one, or prepends the directive.
fn ensure_strict_body(body : Array[@ast.Stmt]) -> Array[@ast.Stmt] {
  if has_use_strict(body) {
    body
  } else {
    let strict_body : Array[@ast.Stmt] = [
      ExprStmt(
        StringLit("use strict", false, @token.Loc::default()),
        @token.Loc::default(),
      ),
    ]
    for s in body {
      strict_body.push(s)
    }
    strict_body
  }
}

///|
fn Interpreter::create_class(
  self : Interpreter,
  ctx : ExecContext,
  name : String,
  superclass_expr : @ast.Expr?,
  members : Array[@ast.ClassMember],
  env : Environment,
) -> Value raise Error {
  // Class bodies are always strict per spec
  let class_ctx : ExecContext = { strict: true, current_generator: None }
  // Evaluate superclass if present
  let (super_ctor, super_proto) : (Value?, Value) = match superclass_expr {
    Some(expr) => {
      let super_val = self.eval_expr(ctx, expr, env)
      match super_val {
        Null =>
          // `class C extends null {}` — legal per spec; the class is derived
          // (ConstructorKind "derived") so super() is required, but calling it
          // tries Construct(null, ...) which throws TypeError.  Represent this
          // as Some(Null) so construct_value follows the derived-class path.
          (Some(Null), Null)
        Object(super_data) =>
          match super_data.bag.properties.get("prototype") {
            Some(sp) => (Some(super_val), sp)
            None => (Some(super_val), Null)
          }
        _ =>
          raise @errors.TypeError(
            message="Class extends value is not a constructor",
          )
      }
    }
    None => (None, Null)
  }
  // Create the prototype object
  // Pre-insert constructor so it appears first in property enumeration order
  let proto_props : Map[String, Value] = { "constructor": Undefined }
  let proto_descriptors : Map[String, PropDescriptor] = {}
  let proto_symbol_props : Map[Int, Value] = {}
  let proto_symbol_descriptors : Map[Int, PropDescriptor] = {}
  // Create static properties map
  let static_props : Map[String, Value] = {}
  let static_descriptors : Map[String, PropDescriptor] = {}
  let static_symbol_props : Map[Int, Value] = {}
  let static_symbol_descriptors : Map[Int, PropDescriptor] = {}
  // Track constructor method
  let mut ctor_fn : (Array[@ast.Param], String?, Array[@ast.Stmt])? = None
  let mut ctor_param_count : Int = 0
  // Collect instance field initializers (evaluated during construction)
  let instance_fields : Array[ClassFieldInit] = []
  // Collect static field initializers (evaluated after class object is created)
  let static_fields : Array[ClassFieldInit] = []
  // Create method environments with [[SuperPrototype]] for super.method() support.
  // Base classes (no extends) still need these bindings: instance methods resolve
  // super against Object.prototype; static methods against Function.prototype.
  let instance_method_env : Environment = {
    let menv = Environment::new(parent=Some(env))
    let instance_super : Value = match super_ctor {
      Some(_) => super_proto
      None => self.global.get("[[ObjectPrototype]]") catch { _ => Null }
    }
    menv.def_builtin("[[SuperPrototype]]", instance_super)
    menv
  }
  let static_method_env : Environment = {
    let menv = Environment::new(parent=Some(env))
    let static_super : Value = match super_ctor {
      Some(sc) => sc
      None => self.global.get("[[FunctionPrototype]]") catch { _ => Null }
    }
    menv.def_builtin("[[SuperPrototype]]", static_super)
    menv
  }
  // Process all members (methods and fields)
  // Class bodies are always strict — computed property keys and method keys
  // must be evaluated as strict code per ES2022 §15.7.
  for mbr in members {
    match mbr {
      @ast.ClassMember::Field(f) => {
        // Evaluate key now (computed field keys are evaluated in order at class definition)
        // ToPropertyKey: keep Symbol as-is; coerce everything else to String once,
        // so side-effectful toString/valueOf don't re-run per-construction.
        let key_val : Value = match f.key {
          StringLit(s, _, _) => String_(s)
          _ => {
            let v = self.eval_expr(class_ctx, f.key, env)
            match v {
              Symbol(_) => v
              _ => String_(to_js_string(v))
            }
          }
        }
        let field_init : ClassFieldInit = {
          key: key_val,
          initializer: f.initializer,
          closure: if f.is_static {
            static_method_env
          } else {
            instance_method_env
          },
        }
        if f.is_static {
          static_fields.push(field_init)
        } else {
          instance_fields.push(field_init)
        }
      }
      @ast.ClassMember::Method(m) => { // method branch
        // Get the method key - could be string or symbol
        let key_val : Value = match m.key {
          StringLit(s, _, _) => String_(s)
          _ => self.eval_expr(class_ctx, m.key, env)
        }
        let method_key_str : String = match key_val {
          Symbol(_) => key_val.to_string()
          _ => to_js_string(key_val)
        }
        // Check if this is the constructor
        if method_key_str == "constructor" && !m.is_static {
          // Extract constructor params and body
          // Class bodies are always strict, so ensure constructor body has "use strict"
          match m.value {
            FuncExpr(_, param_names, body, _) => {
              let strict_body = ensure_strict_body(body)
              validate_function_signature(true, None, param_names, strict_body)
              // Wrap plain names as Param objects (no defaults/rest/patterns)
              let params : Array[@ast.Param] = param_names.map(fn(n) {
                ({ name: n, default_val: None, pattern: None } : @ast.Param)
              })
              ctor_fn = Some((params, None, strict_body))
              ctor_param_count = param_names.length()
            }
            FuncExprExt(_, params, rest, body, _) => {
              let strict_body = ensure_strict_body(body)
              validate_function_signature_ext(
                true,
                None,
                params,
                rest,
                strict_body,
              )
              ctor_fn = Some((params, rest, strict_body))
              // Length = number of params before the first one with a default
              let mut count = 0
              for p in params {
                if p.default_val is Some(_) {
                  break
                }
                count += 1
              }
              ctor_param_count = count
            }
            _ => ()
          }
          continue
        }
        // Create the method function value
        // Class methods are always strict — ensure body has "use strict"
        // Use the appropriate method environment for super.method() support
        let method_closure = if m.is_static {
          static_method_env
        } else {
          instance_method_env
        }
        let method_val : Value = match m.value {
          FuncExpr(fn_name, params, body, _) => {
            let strict_body = ensure_strict_body(body)
            validate_function_signature(true, fn_name, params, strict_body)
            let func_data : FuncData = {
              name: fn_name,
              params,
              body: strict_body,
              closure: method_closure,
              strict: true,
              // Class methods don't get a §15.2.5 self-name binding.
              has_name_binding: false,
            }
            make_func(func_data)
          }
          FuncExprExt(fn_name, params, rest, body, _) => {
            let strict_body = ensure_strict_body(body)
            validate_function_signature_ext(
              true, fn_name, params, rest, strict_body,
            )
            let func_data : FuncDataExt = {
              name: fn_name,
              params,
              rest_param: rest,
              body: strict_body,
              closure: method_closure,
              strict: true,
              has_name_binding: false,
            }
            make_func_ext(func_data)
          }
          _ => self.eval_expr(class_ctx, m.value, method_closure)
        }
        // Handle getter/setter vs regular method
        // Class methods are non-enumerable per spec
        // Set appropriate function name with get/set prefix
        match m.kind {
          Get => set_function_name(method_val, "get " + method_key_str)
          Set => set_function_name(method_val, "set " + method_key_str)
          _ => set_function_name(method_val, method_key_str)
        }
        match m.kind {
          Get =>
            // Getter method - store as accessor descriptor
            match key_val {
              Symbol(sym) => {
                let (props, descs) = if m.is_static {
                  (static_symbol_props, static_symbol_descriptors)
                } else {
                  (proto_symbol_props, proto_symbol_descriptors)
                }
                if !props.contains(sym.id) {
                  props[sym.id] = Undefined
                }
                let existing = descs.get(sym.id)
                descs[sym.id] = {
                  writable: false,
                  enumerable: false,
                  configurable: true,
                  getter: Some(method_val),
                  setter: match existing {
                    Some(d) => d.setter
                    None => None
                  },
                }
              }
              _ => {
                let (props, descs) = if m.is_static {
                  (static_props, static_descriptors)
                } else {
                  (proto_props, proto_descriptors)
                }
                if !props.contains(method_key_str) {
                  props[method_key_str] = Undefined
                }
                let existing = descs.get(method_key_str)
                descs[method_key_str] = {
                  writable: false,
                  enumerable: false,
                  configurable: true,
                  getter: Some(method_val),
                  setter: match existing {
                    Some(d) => d.setter
                    None => None
                  },
                }
              }
            }
          Set =>
            // Setter method - store as accessor descriptor
            match key_val {
              Symbol(sym) => {
                let (props, descs) = if m.is_static {
                  (static_symbol_props, static_symbol_descriptors)
                } else {
                  (proto_symbol_props, proto_symbol_descriptors)
                }
                if !props.contains(sym.id) {
                  props[sym.id] = Undefined
                }
                let existing = descs.get(sym.id)
                descs[sym.id] = {
                  writable: false,
                  enumerable: false,
                  configurable: true,
                  getter: match existing {
                    Some(d) => d.getter
                    None => None
                  },
                  setter: Some(method_val),
                }
              }
              _ => {
                let (props, descs) = if m.is_static {
                  (static_props, static_descriptors)
                } else {
                  (proto_props, proto_descriptors)
                }
                if !props.contains(method_key_str) {
                  props[method_key_str] = Undefined
                }
                let existing = descs.get(method_key_str)
                descs[method_key_str] = {
                  writable: false,
                  enumerable: false,
                  configurable: true,
                  getter: match existing {
                    Some(d) => d.getter
                    None => None
                  },
                  setter: Some(method_val),
                }
              }
            }
          _ => {
            // Regular method or Init
            let method_descriptor : PropDescriptor = {
              writable: true,
              enumerable: false,
              configurable: true,
              getter: None,
              setter: None,
            }
            // Store method in appropriate map based on key type (string vs symbol)
            match key_val {
              Symbol(sym) =>
                // Symbol key - store in symbol_properties
                if m.is_static {
                  static_symbol_props[sym.id] = method_val
                  static_symbol_descriptors[sym.id] = method_descriptor
                } else {
                  proto_symbol_props[sym.id] = method_val
                  proto_symbol_descriptors[sym.id] = method_descriptor
                }
              _ =>
                // String key - store in regular properties
                if m.is_static {
                  static_props[method_key_str] = method_val
                  static_descriptors[method_key_str] = method_descriptor
                } else {
                  proto_props[method_key_str] = method_val
                  proto_descriptors[method_key_str] = method_descriptor
                }
            }
          }
        }
      } // end Method arm
    } // end match member
  } // end for member in members
  // Create prototype object
  let proto = Object({
    bag: {
      properties: proto_props,
      symbol_properties: proto_symbol_props,
      descriptors: proto_descriptors,
      symbol_descriptors: proto_symbol_descriptors,
    },
    prototype: super_proto,
    callable: None,
    class_name: name,
    extensible: true,
  })
  // Add constructor back-reference to prototype
  // (will be set after class object is created)
  // The class function's [[Prototype]] is always the super class constructor
  // so that static inheritance works.  For `extends null` (super_ctor = Some(Null))
  // and for base classes (None), the class function inherits from Function.prototype.
  let class_proto = match super_ctor {
    Some(Null) | None =>
      self.global.get("[[FunctionPrototype]]") catch {
        _ => Null
      }
    Some(super_class) => super_class
  }
  // Create the class constructor function
  let class_obj = Object({
    bag: {
      properties: static_props,
      symbol_properties: static_symbol_props,
      descriptors: static_descriptors,
      symbol_descriptors: static_symbol_descriptors,
    },
    prototype: class_proto,
    callable: Some(
      ClassConstructor({
        name,
        proto,
        super_ctor,
        ctor_fn,
        closure: env,
        super_proto,
        instance_fields,
      }),
    ),
    class_name: "Function",
    extensible: true,
  })
  // Set prototype.constructor to point to the class (non-enumerable per spec)
  match proto {
    Object(proto_data) => {
      proto_data.bag.properties["constructor"] = class_obj
      proto_data.bag.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }
  // Add length, name, prototype properties to the class constructor per spec
  let non_enum_configurable : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  match class_obj {
    Object(class_data) => {
      // Add length (formal parameter count) - non-writable, non-enumerable, configurable
      class_data.bag.properties["length"] = Number(ctor_param_count.to_double())
      class_data.bag.descriptors["length"] = non_enum_configurable
      // Add name - non-writable, non-enumerable, configurable
      if name != "" {
        class_data.bag.properties["name"] = String_(name)
        class_data.bag.descriptors["name"] = non_enum_configurable
      }
      // Add prototype - non-writable, non-enumerable, non-configurable
      class_data.bag.properties["prototype"] = proto
      class_data.bag.descriptors["prototype"] = {
        writable: false,
        enumerable: false,
        configurable: false,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }
  // Evaluate static field initializers (run once at class definition time)
  // Per ES2022 spec, static fields are initialized after the class object is created.
  // We also bind the class name here so self-referential initializers like
  // `class C { static self = C }` can resolve C during evaluation.
  let static_init_base : Environment = if name != "" {
    let e = Environment::new(parent=Some(static_method_env))
    e.def_builtin(name, class_obj)
    e
  } else {
    static_method_env
  }
  // Class bodies (including field initializers) are always strict per spec
  for sf in static_fields {
    let key_str : String = match sf.key {
      String_(s) => s
      Symbol(sym) => sym.id.to_string() // use id for symbol-keyed static fields
      _ => to_js_string(sf.key)
    }
    let value : Value = match sf.initializer {
      Some(expr) => {
        // Evaluate initializer with `this` = class_obj and class name in scope
        let field_env = Environment::new(parent=Some(static_init_base))
        field_env.def_builtin("this", class_obj)
        self.eval_expr(class_ctx, expr, field_env)
      }
      None => Undefined
    }
    match class_obj {
      Object(class_data) =>
        match sf.key {
          Symbol(sym) => {
            if !class_data.bag.symbol_properties.contains(sym.id) &&
              !class_data.extensible {
              raise @errors.TypeError(
                message="Cannot define static field on non-extensible object",
              )
            }
            match class_data.bag.symbol_descriptors.get(sym.id) {
              Some(d) =>
                if !d.configurable {
                  raise @errors.TypeError(
                    message="Cannot redefine non-configurable static class field",
                  )
                }
              None => ()
            }
            class_data.bag.symbol_properties[sym.id] = value
            class_data.bag.symbol_descriptors[sym.id] = {
              writable: true,
              enumerable: true,
              configurable: true,
              getter: None,
              setter: None,
            }
          }
          _ => {
            if !class_data.bag.properties.contains(key_str) &&
              !class_data.extensible {
              raise @errors.TypeError(
                message="Cannot define static field on non-extensible object",
              )
            }
            match class_data.bag.descriptors.get(key_str) {
              Some(d) =>
                if !d.configurable {
                  raise @errors.TypeError(
                    message="Cannot redefine non-configurable static class field",
                  )
                }
              None => ()
            }
            class_data.bag.properties[key_str] = value
            class_data.bag.descriptors[key_str] = {
              writable: true,
              enumerable: true,
              configurable: true,
              getter: None,
              setter: None,
            }
          }
        }
      _ => ()
    }
  }
  class_obj
}
