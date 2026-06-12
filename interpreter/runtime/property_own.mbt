///|
/// Sort property keys per OrdinaryOwnPropertyKeys spec order:
/// 1. Integer indices in ascending numeric order
/// 2. Other string keys in insertion order
pub fn sort_property_keys(props : Map[String, Value]) -> Array[String] {
  let int_keys : Array[String] = []
  let str_keys : Array[String] = []
  props.each(fn(k, _v) {
    // Skip internal slots (e.g., [[BooleanData]], [[NumberData]], [[StringData]])
    if k.has_prefix("[[") {
      return
    }
    let idx = @string.parse_int(k) catch { _ => -1 }
    if idx >= 0 && idx.to_string() == k {
      int_keys.push(k)
    } else {
      str_keys.push(k)
    }
  })
  // Sort integer keys by numeric value
  int_keys.sort_by(fn(a, b) {
    let na = @string.parse_int(a) catch { _ => 0 }
    let nb = @string.parse_int(b) catch { _ => 0 }
    na - nb
  })
  let result : Array[String] = []
  for k in int_keys {
    result.push(k)
  }
  for k in str_keys {
    result.push(k)
  }
  result
}

///|
/// Validate non-configurable property constraints per ES spec [[DefineOwnProperty]].
/// Throws TypeError if the proposed descriptor change violates invariants.
/// This is the sole authority for descriptor mutation constraints in the runtime.
pub fn validate_non_configurable(
  existing : PropDescriptor,
  prop_display : String,
  is_accessor : Bool,
  is_data : Bool,
  has_value : Bool,
  new_writable : Bool?,
  new_enumerable : Bool?,
  new_configurable : Bool?,
  new_getter : Value?,
  new_setter : Value?,
  get_old_value : () -> Value,
  get_new_value : () -> Value?,
) -> Unit raise Error {
  if existing.configurable {
    return
  }
  let existing_is_accessor = existing.is_accessor
  // Cannot change between accessor and data
  if existing_is_accessor && is_data {
    raise @errors.TypeError(
      message="Cannot redefine non-configurable property: \{prop_display}",
    )
  }
  if !existing_is_accessor && is_accessor {
    raise @errors.TypeError(
      message="Cannot redefine non-configurable property: \{prop_display}",
    )
  }
  let enumerable_ok = match new_enumerable {
    Some(e) => e == existing.enumerable
    None => true
  }
  let configurable_ok = match new_configurable {
    Some(c) => c == existing.configurable
    None => true
  }
  // Non-configurable accessor: validate getter/setter identity
  if existing_is_accessor && is_accessor {
    let getter_ok = match new_getter {
      Some(g) =>
        match existing.getter {
          Some(eg) => strict_equal(g, eg)
          None => g is Undefined
        }
      None => true
    }
    let setter_ok = match new_setter {
      Some(s) =>
        match existing.setter {
          Some(es) => strict_equal(s, es)
          None => s is Undefined
        }
      None => true
    }
    if !(enumerable_ok && configurable_ok && getter_ok && setter_ok) {
      raise @errors.TypeError(
        message="Cannot redefine non-configurable property: \{prop_display}",
      )
    }
  }
  // Non-configurable data: validate writable/value
  if !existing_is_accessor && !is_accessor {
    let writable_ok = match new_writable {
      Some(w) => if !existing.writable && w { false } else { true }
      None => true
    }
    let value_ok = if !existing.writable && has_value {
      match get_new_value() {
        Some(v) => strict_equal(v, get_old_value())
        None => true
      }
    } else {
      true
    }
    if !(writable_ok && enumerable_ok && configurable_ok && value_ok) {
      raise @errors.TypeError(
        message="Cannot redefine non-configurable property: \{prop_display}",
      )
    }
  }
  // Generic descriptor (no accessor/data fields)
  if !is_accessor && !is_data {
    if !(enumerable_ok && configurable_ok) {
      raise @errors.TypeError(
        message="Cannot redefine non-configurable property: \{prop_display}",
      )
    }
  }
}

// ---------------------------------------------------------------------------
// Stage B.2: ordinary [[GetOwnProperty]] / [[DefineOwnProperty]]
// ---------------------------------------------------------------------------

///|
/// ES §7.2.11 SameValue. Differs from `strict_equal` on two cases:
/// - SameValue(NaN, NaN) = true        (strict_equal: false)
/// - SameValue(+0, -0) = false         (strict_equal: true)
/// VAP §10.1.6.3 step 4.b.iii uses SameValue to check whether a value change
/// on a non-writable non-configurable data property is a no-op.
fn same_value_for_vap(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Number(x), Number(y)) =>
      if x.is_nan() && y.is_nan() {
        true
      } else if x == 0.0 && y == 0.0 {
        // +0 and -0 compare equal under ==; distinguish by reciprocal sign
        1.0 / x == 1.0 / y
      } else {
        x == y
      }
    _ => strict_equal(a, b)
  }
}

///|
/// Extract the stored own value for `key` on `val`. Mirrors the key-aware
/// reader used in proxy helpers but surfaced here for VAP's value-change
/// check (step 4.b.iii).
pub fn ordinary_get_own_value_for_descriptor(
  val : Value,
  key : Value,
) -> Value raise Error {
  match key {
    Symbol(sym) => {
      let bag_opt = match val {
        Object(data) => Some(data.bag)
        Map(data) => Some(data.bag)
        Set(data) => Some(data.bag)
        Promise(data) => Some(data.bag)
        Array(arr) => Some(arr.bag)
        _ => None
      }
      match bag_opt {
        Some(bag) =>
          match bag.symbol_properties.get(sym.id) {
            Some(v) => v
            None => Undefined
          }
        None => Undefined
      }
    }
    _ => {
      let k = to_js_string(key)
      match val {
        Object(data) =>
          match data.bag.properties.get(k) {
            Some(v) => v
            None => Undefined
          }
        Map(data) =>
          match data.bag.properties.get(k) {
            Some(v) => v
            None => Undefined
          }
        Set(data) =>
          match data.bag.properties.get(k) {
            Some(v) => v
            None => Undefined
          }
        Promise(data) =>
          match data.bag.properties.get(k) {
            Some(v) => v
            None => Undefined
          }
        Array(arr) => {
          if k == "length" {
            return match get_array_length_override(arr) {
              Some(n64) => Value::Number(n64.to_double())
              None => Value::Number(arr.elements.length().to_double())
            }
          }
          let idx = @string.parse_int(k) catch { _ => -1 }
          if idx >= 0 && idx.to_string() == k && idx < arr.elements.length() {
            return arr.elements[idx]
          }
          match arr.bag.properties.get(k) {
            Some(v) => v
            None => Undefined
          }
        }
        _ => Undefined
      }
    }
  }
}

///|
/// ES §10.1.5 `OrdinaryGetOwnProperty(O, P)`. Returns the stored descriptor
/// for an own property on `val`. For Array, synthesizes descriptors for
/// `length` and in-range indexed elements per §10.4.2. Returns `None` if the
/// property is not own.
pub fn ordinary_get_own_property(
  val : Value,
  key : Value,
) -> PropDescriptor? raise Error {
  match key {
    Symbol(sym) => {
      let bag_opt = match val {
        Object(data) => Some(data.bag)
        Map(data) => Some(data.bag)
        Set(data) => Some(data.bag)
        Promise(data) => Some(data.bag)
        Array(arr) => Some(arr.bag)
        _ => None
      }
      match bag_opt {
        Some(bag) =>
          // A symbol property might have a descriptor OR just a value entry.
          match bag.symbol_descriptors.get(sym.id) {
            Some(d) => Some(d)
            None =>
              if bag.symbol_properties.contains(sym.id) {
                Some({
                  writable: true,
                  enumerable: true,
                  configurable: true,
                  getter: None,
                  setter: None,
                  is_accessor: false,
                })
              } else {
                None
              }
          }
        None => None
      }
    }
    _ => {
      let k = to_js_string(key)
      match val {
        Object(data) => ordinary_get_own_string_desc(data.bag, k)
        Map(data) => ordinary_get_own_string_desc(data.bag, k)
        Set(data) => ordinary_get_own_string_desc(data.bag, k)
        Promise(data) => ordinary_get_own_string_desc(data.bag, k)
        Array(arr) => {
          if k == "length" {
            return Some({
              writable: arr.length_writable,
              enumerable: false,
              configurable: false,
              getter: None,
              setter: None,
              is_accessor: false,
            })
          }
          let idx = @string.parse_int(k) catch { _ => -1 }
          if idx >= 0 &&
            idx.to_string() == k &&
            idx < arr.elements.length() &&
            !arr.holes.contains(idx) {
            return match arr.bag.descriptors.get(k) {
              Some(desc) => Some(desc)
              None =>
                Some({
                  writable: true,
                  enumerable: true,
                  configurable: true,
                  getter: None,
                  setter: None,
                  is_accessor: false,
                })
            }
          }
          ordinary_get_own_string_desc(arr.bag, k)
        }
        _ => None
      }
    }
  }
}

///|
fn ordinary_get_own_string_desc(
  bag : PropertyBag,
  key : String,
) -> PropDescriptor? {
  match bag.descriptors.get(key) {
    Some(d) => Some(d)
    None =>
      if bag.properties.contains(key) {
        Some({
          writable: true,
          enumerable: true,
          configurable: true,
          getter: None,
          setter: None,
          is_accessor: false,
        })
      } else {
        None
      }
  }
}

///|
/// Is `val` extensible per ES §10.1.3? Only ObjectData tracks extensibility;
/// Array/Map/Set/Promise lack a per-instance extensibility slot and are
/// always reported extensible. Adding extensibility tracking to those four
/// variants is a structural follow-up tracked alongside their general
/// prototype-slot gap.
fn ordinary_is_extensible(val : Value) -> Bool {
  match val {
    Object(data) => data.extensible
    Array(_) | Map(_) | Set(_) | Promise(_) => true
    _ => false
  }
}

///|
/// Is `val` one of the "object-like" Value variants that can own properties?
/// Primitives and Proxy are excluded from the ordinary path.
fn is_ordinary_object_like(val : Value) -> Bool {
  match val {
    Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) => true
    _ => false
  }
}

///|
/// VAP step 4 compatibility check: given `current` is non-configurable and
/// `partial` proposes a change, decide whether the change is permitted.
/// Returns `true` if compatible (proceed to apply); `false` if the change
/// must be rejected (VAP returns false without writing).
fn is_compatible_with_non_configurable(
  current : PropDescriptor,
  partial : PartialDescriptor,
  current_value : Value,
) -> Bool {
  // §10.1.6.3 step 4.a: cannot change configurable false -> true.
  match partial.configurable {
    Some(true) => return false
    _ => ()
  }
  // Step 4.b: cannot change enumerable.
  match partial.enumerable {
    Some(e) => if e != current.enumerable { return false }
    None => ()
  }
  let current_is_accessor = current.is_accessor
  let partial_is_accessor = partial.is_accessor()
  let partial_is_data = partial.is_data()
  // Step 4.c: cannot toggle accessor <-> data when non-configurable.
  if current_is_accessor && partial_is_data {
    return false
  }
  if !current_is_accessor && partial_is_accessor {
    return false
  }
  if current_is_accessor && partial_is_accessor {
    // Step 4.d: non-configurable accessor — getter/setter identity must
    // not change (SameValue).
    if partial.has_getter {
      let g_matches = match current.getter {
        Some(cg) => same_value_for_vap(partial.getter.unwrap_or(Undefined), cg)
        None => partial.getter is Some(Undefined) || partial.getter is None
      }
      if !g_matches {
        return false
      }
    }
    if partial.has_setter {
      let s_matches = match current.setter {
        Some(cs) => same_value_for_vap(partial.setter.unwrap_or(Undefined), cs)
        None => partial.setter is Some(Undefined) || partial.setter is None
      }
      if !s_matches {
        return false
      }
    }
  }
  if !current_is_accessor && !partial_is_accessor {
    // Step 4.e: non-configurable non-writable data — value change must be
    // SameValue; writable false -> true is forbidden.
    if !current.writable {
      match partial.writable {
        Some(true) => return false
        _ => ()
      }
      match partial.value {
        Some(v) => if !same_value_for_vap(v, current_value) { return false }
        None => ()
      }
    }
  }
  true
}

///|
/// Merge a PartialDescriptor into an existing PropDescriptor, returning the
/// new descriptor. Fields absent from `partial` preserve `current`'s value.
/// When accessor fields transition between has/hasn't, the storage reflects
/// the partial's presence.
fn merge_partial_into(
  current : PropDescriptor,
  partial : PartialDescriptor,
) -> PropDescriptor {
  let writable = match partial.writable {
    Some(w) => w
    None => current.writable
  }
  let enumerable = match partial.enumerable {
    Some(e) => e
    None => current.enumerable
  }
  let configurable = match partial.configurable {
    Some(c) => c
    None => current.configurable
  }
  let getter = if partial.has_getter {
    match partial.getter {
      Some(Undefined) | None => None
      Some(g) => Some(g)
    }
  } else {
    current.getter
  }
  let setter = if partial.has_setter {
    match partial.setter {
      Some(Undefined) | None => None
      Some(s) => Some(s)
    }
  } else {
    current.setter
  }
  // Preserve accessor type: if partial explicitly introduces accessor fields
  // (has_getter or has_setter), result is accessor. If partial introduces data
  // fields (value or writable), result is data. Otherwise inherit from current.
  let is_accessor = if partial.has_getter || partial.has_setter {
    true
  } else if partial.value is Some(_) || partial.writable is Some(_) {
    false
  } else {
    current.is_accessor
  }
  { writable, enumerable, configurable, getter, setter, is_accessor }
}

///|
/// Build a fresh PropDescriptor for an absent key, filling omitted fields
/// with defaults per ES §6.2.5.5 CompletePropertyDescriptor: absent
/// writable/enumerable/configurable default to `false`; accessor fields
/// default to `None`.
fn complete_partial_for_new(partial : PartialDescriptor) -> PropDescriptor {
  let writable = partial.writable.unwrap_or(false)
  let enumerable = partial.enumerable.unwrap_or(false)
  let configurable = partial.configurable.unwrap_or(false)
  let getter = if partial.has_getter {
    match partial.getter {
      Some(Undefined) | None => None
      Some(g) => Some(g)
    }
  } else {
    None
  }
  let setter = if partial.has_setter {
    match partial.setter {
      Some(Undefined) | None => None
      Some(s) => Some(s)
    }
  } else {
    None
  }
  let is_accessor = partial.has_getter || partial.has_setter
  { writable, enumerable, configurable, getter, setter, is_accessor }
}

///|
/// Write a merged/completed descriptor into `bag` at `key`. Also writes the
/// value portion if the partial contained one (data descriptor), so subsequent
/// `bag.properties` reads return the correct value.
fn apply_descriptor_to_bag(
  bag : PropertyBag,
  key : Value,
  desc : PropDescriptor,
  value_opt : Value?,
) -> Unit raise Error {
  match key {
    Symbol(sym) => {
      bag.symbol_descriptors[sym.id] = desc
      match value_opt {
        Some(v) => bag.symbol_properties[sym.id] = v
        None =>
          if !bag.symbol_properties.contains(sym.id) {
            bag.symbol_properties[sym.id] = Undefined
          }
      }
    }
    _ => {
      // ToPropertyKey-aligned coercion — for object-typed keys this invokes
      // Symbol.toPrimitive / toString via to_js_string rather than MoonBit's
      // Value::to_string (which produces a debug string for objects and
      // would write to a different slot than the validation pipeline read).
      let k = to_js_string(key)
      bag.descriptors[k] = desc
      match value_opt {
        Some(v) => bag.properties[k] = v
        None => if !bag.properties.contains(k) { bag.properties[k] = Undefined }
      }
    }
  }
}

///|
/// ES §6.2.5.5 `ToPropertyDescriptor`. Extract a PartialDescriptor from a JS
/// attrs object, invoking getters and reading inherited properties per spec.
/// Throws TypeError if:
/// - attrs is not an object
/// - both data (value/writable) and accessor (get/set) fields appear
/// - get or set is non-callable non-undefined
pub fn Interpreter::partial_descriptor_from_attrs(
  self : Interpreter,
  attrs : Value,
  loc : @token.Loc,
) -> PartialDescriptor raise Error {
  if !is_object_value(attrs) {
    raise @errors.TypeError(
      message="Property description must be an object: \{attrs.to_string()}",
    )
  }
  let has_value = has_property(attrs, "value", interp=Some(self))
  let has_writable = has_property(attrs, "writable", interp=Some(self))
  let has_get = has_property(attrs, "get", interp=Some(self))
  let has_set = has_property(attrs, "set", interp=Some(self))
  if (has_value || has_writable) && (has_get || has_set) {
    raise @errors.TypeError(
      message="Invalid property descriptor. Cannot both specify accessors and a value or writable attribute",
    )
  }
  let value = if has_value {
    Some(self.get_property(attrs, "value", loc))
  } else {
    None
  }
  let writable = if has_writable {
    Some(is_truthy(self.get_property(attrs, "writable", loc)))
  } else {
    None
  }
  let enumerable = if has_property(attrs, "enumerable", interp=Some(self)) {
    Some(is_truthy(self.get_property(attrs, "enumerable", loc)))
  } else {
    None
  }
  let configurable = if has_property(attrs, "configurable", interp=Some(self)) {
    Some(is_truthy(self.get_property(attrs, "configurable", loc)))
  } else {
    None
  }
  let getter = if has_get {
    let g = self.get_property(attrs, "get", loc)
    match g {
      Undefined => None
      Object(data) => {
        if data.callable is None {
          raise @errors.TypeError(
            message="Getter must be a function: \{g.to_string()}",
          )
        }
        Some(g)
      }
      _ =>
        raise @errors.TypeError(
          message="Getter must be a function: \{g.to_string()}",
        )
    }
  } else {
    None
  }
  let setter = if has_set {
    let s = self.get_property(attrs, "set", loc)
    match s {
      Undefined => None
      Object(data) => {
        if data.callable is None {
          raise @errors.TypeError(
            message="Setter must be a function: \{s.to_string()}",
          )
        }
        Some(s)
      }
      _ =>
        raise @errors.TypeError(
          message="Setter must be a function: \{s.to_string()}",
        )
    }
  } else {
    None
  }
  {
    value,
    writable,
    enumerable,
    configurable,
    getter,
    setter,
    has_getter: has_get,
    has_setter: has_set,
  }
}

///|
/// Convert a stored PropDescriptor into a plain JS descriptor object for
/// Object.getOwnPropertyDescriptor / Reflect.getOwnPropertyDescriptor
/// callers. Emits value + writable for data descriptors; get + set for
/// accessor descriptors.
pub fn descriptor_to_value(
  desc : PropDescriptor,
  value : Value,
  realm_state? : RealmState? = None,
) -> Value {
  let props : Map[String, Value] = {}
  if desc.is_accessor {
    props["get"] = desc.getter.unwrap_or(Undefined)
    props["set"] = desc.setter.unwrap_or(Undefined)
  } else {
    props["value"] = value
    props["writable"] = Value::Bool(desc.writable)
  }
  props["enumerable"] = Value::Bool(desc.enumerable)
  props["configurable"] = Value::Bool(desc.configurable)
  Value::Object({
    bag: {
      properties: props,
      symbol_properties: {},
      descriptors: {},
      symbol_descriptors: {},
    },
    prototype: get_obj_proto(realm_state~),
    extensible: true,
    arraybuffer_state: None,
    callable: None,
    class_name: "Object",
  })
}

///|
/// ES [[DefineOwnProperty]] dispatcher — routes Proxy targets through the
/// defineProperty trap (`proxy_define_property`), others through
/// `ordinary_define_own_property`. This is the main entry point builtins
/// and internal callers should use.
pub fn Interpreter::define_own_property(
  self : Interpreter,
  val : Value,
  key : Value,
  partial : PartialDescriptor,
  loc : @token.Loc,
) -> Bool raise Error {
  match val {
    Value::Proxy(pdata) => proxy_define_property(self, pdata, key, partial)
    _ => self.ordinary_define_own_property(val, key, partial, loc)
  }
}

///|
fn typedarray_index_own_descriptor() -> PropDescriptor {
  {
    writable: true,
    enumerable: true,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}

///|
fn ordinary_get_own_property_pair(
  val : Value,
  key : Value,
) -> (PropDescriptor, Value)? raise Error {
  match ordinary_get_own_property(val, key) {
    None => None
    Some(desc) => Some((desc, ordinary_get_own_value_for_descriptor(val, key)))
  }
}

///|
fn Interpreter::typedarray_get_own_property_pair(
  self : Interpreter,
  data : ObjectData,
  key : Value,
) -> (PropDescriptor, Value)? raise Error {
  match key {
    String_(s) =>
      match classify_typedarray_string_key(s) {
        Some(idx) =>
          if idx >= 0 &&
            (self.stdlib_hooks.typedarray_is_valid_index)(
              data,
              idx,
              self.realm_state,
            ) {
            let value = (self.stdlib_hooks.typedarray_get_index)(
              data,
              idx,
              self.realm_state,
            )
            if value is Undefined {
              None
            } else {
              Some((typedarray_index_own_descriptor(), value))
            }
          } else {
            None
          }
        None => ordinary_get_own_property_pair(Object(data), key)
      }
    _ => ordinary_get_own_property_pair(Object(data), key)
  }
}

///|
/// ES [[GetOwnProperty]] dispatcher — Proxy targets route through
/// `proxy_get_own_property`, TypedArrays synthesize integer-indexed element
/// descriptors per §10.4.5.1, and others route through
/// `ordinary_get_own_property`.
/// Returns `(descriptor, value)` pairs so the trap-provided value in the
/// Proxy case flows through (PropDescriptor has no `value` slot — the
/// value is stored separately on the bag or synthesized by the trap).
pub fn Interpreter::get_own_property(
  self : Interpreter,
  val : Value,
  key : Value,
) -> (PropDescriptor, Value)? raise Error {
  let prop_key = to_property_key(key, interp=Some(self))
  match val {
    Value::Proxy(pdata) => proxy_get_own_property(self, pdata, prop_key)
    Object(data) if data.class_name == "Module" =>
      self.module_namespace_get_own_property_pair(data, prop_key)
    Object(data) if is_typedarray_class(data.class_name) =>
      self.typedarray_get_own_property_pair(data, prop_key)
    _ => ordinary_get_own_property_pair(val, prop_key)
  }
}

///|
fn Interpreter::typedarray_define_own_property_numeric(
  self : Interpreter,
  data : ObjectData,
  key : Value,
  partial : PartialDescriptor,
) -> Bool? raise Error {
  match key {
    String_(s) =>
      match classify_typedarray_string_key(s) {
        Some(idx) => {
          if idx < 0 ||
            !(self.stdlib_hooks.typedarray_is_valid_index)(
              data,
              idx,
              self.realm_state,
            ) {
            return Some(false)
          }
          if partial.is_accessor() {
            return Some(false)
          }
          match partial.configurable {
            Some(false) => return Some(false)
            _ => ()
          }
          match partial.enumerable {
            Some(false) => return Some(false)
            _ => ()
          }
          match partial.writable {
            Some(false) => return Some(false)
            _ => ()
          }
          match partial.value {
            Some(value) => {
              let num = self.to_number(value)
              (self.stdlib_hooks.typedarray_set_index)(
                data,
                idx,
                num,
                self.realm_state,
              )
            }
            None => ()
          }
          Some(true)
        }
        None => None
      }
    _ => None
  }
}

///|
/// ES §10.1.6 `OrdinaryDefineOwnProperty(O, P, Desc)` + §10.4.2.1 Array
/// exotic dispatch + §10.4.5.3 IntegerIndexed exotic dispatch. Returns `true`
/// on success, `false` on rejection (the caller — Object.defineProperty
/// throws, Reflect.defineProperty returns false).
pub fn Interpreter::ordinary_define_own_property(
  self : Interpreter,
  val : Value,
  key : Value,
  partial : PartialDescriptor,
  loc : @token.Loc,
) -> Bool raise Error {
  // Exotic dispatch
  match val {
    Object(data) if data.class_name == "Module" =>
      match
        self.module_namespace_define_own_property(
          data,
          to_property_key(key, interp=Some(self)),
          partial,
        ) {
        Some(result) => return result
        None => ()
      }
    Object(data) if is_typedarray_class(data.class_name) =>
      match self.typedarray_define_own_property_numeric(data, key, partial) {
        Some(result) => return result
        None => ()
      }
    Array(arr) => return self.array_define_own_property(arr, key, partial, loc)
    _ => ()
  }
  if !is_ordinary_object_like(val) {
    return false
  }
  let existing = ordinary_get_own_property(val, key)
  let extensible = ordinary_is_extensible(val)
  match existing {
    None => {
      if !extensible {
        return false
      }
      let full = complete_partial_for_new(partial)
      let value_opt = partial.value
      ordinary_write(val, key, full, value_opt)
      true
    }
    Some(current) => {
      // Fast-pass: all configurable changes are allowed.
      if !current.configurable {
        let cur_val = ordinary_get_own_value_for_descriptor(val, key)
        if !is_compatible_with_non_configurable(current, partial, cur_val) {
          return false
        }
      }
      let merged = merge_partial_into(current, partial)
      // §10.1.6.3 step 4.b: when descriptor type changes, clear the fields
      // that don't apply to the new type.
      let current_is_accessor = current.is_accessor
      let final_desc = if partial.is_accessor() && !current_is_accessor {
        // Data → Accessor: writable not meaningful for accessor; set to false.
        { ..merged, writable: false }
      } else if partial.is_data() && current_is_accessor {
        // Accessor → Data: clear residual getter/setter so the merged
        // descriptor is a pure data descriptor. Without this, reads via
        // ordinary_get_value would still fire the old getter.
        { ..merged, getter: None, setter: None }
      } else {
        merged
      }
      ordinary_write(val, key, final_desc, partial.value)
      true
    }
  }
}

///|
/// Dispatch descriptor + value write to the appropriate bag, given the
/// receiver has already been classified as object-like (not Array).
fn ordinary_write(
  val : Value,
  key : Value,
  desc : PropDescriptor,
  value_opt : Value?,
) -> Unit raise Error {
  match val {
    Object(data) => apply_descriptor_to_bag(data.bag, key, desc, value_opt)
    Map(data) => apply_descriptor_to_bag(data.bag, key, desc, value_opt)
    Set(data) => apply_descriptor_to_bag(data.bag, key, desc, value_opt)
    Promise(data) => apply_descriptor_to_bag(data.bag, key, desc, value_opt)
    _ => ()
  }
}

///|
/// ES §10.4.2.1 Array exotic `[[DefineOwnProperty]]`. Dispatches on:
/// - key == "length" -> array_set_length (§10.4.2.4 with partial truncation).
/// - key is array index -> ordinary-style write against `bag`, plus grow
///   elements to idx+1 (ArraySetLength auto-grow) ONLY when descriptor is the
///   default-data shape. Non-default (configurable:false / writable:false /
///   enumerable:false) descriptors on indexed elements return false pending
///   Stage C's per-index descriptor storage.
/// - Other keys -> ordinary-style write against arr.bag.
pub fn Interpreter::array_define_own_property(
  self : Interpreter,
  arr : ArrayData,
  key : Value,
  partial : PartialDescriptor,
  loc : @token.Loc,
) -> Bool raise Error {
  let _ = loc
  match key {
    Symbol(sym) => {
      // Symbol keys flow through bag.symbol_*; treat as ordinary ordinary.
      let existing = match arr.bag.symbol_descriptors.get(sym.id) {
        Some(d) => Some(d)
        None =>
          if arr.bag.symbol_properties.contains(sym.id) {
            Some({
              writable: true,
              enumerable: true,
              configurable: true,
              getter: None,
              setter: None,
              is_accessor: false,
            })
          } else {
            None
          }
      }
      match existing {
        None => {
          let full = complete_partial_for_new(partial)
          apply_descriptor_to_bag(arr.bag, key, full, partial.value)
          true
        }
        Some(current) => {
          if !current.configurable {
            let cur_val = match arr.bag.symbol_properties.get(sym.id) {
              Some(v) => v
              None => Undefined
            }
            if !is_compatible_with_non_configurable(current, partial, cur_val) {
              return false
            }
          }
          let merged = merge_partial_into(current, partial)
          let final_desc = if !merged.is_accessor && current.is_accessor {
            { ..merged, getter: None, setter: None }
          } else if merged.is_accessor && !current.is_accessor {
            { ..merged, writable: false }
          } else {
            merged
          }
          apply_descriptor_to_bag(arr.bag, key, final_desc, partial.value)
          true
        }
      }
    }
    _ => {
      // ToPropertyKey-aligned coercion (matches ordinary_define_own_property's
      // apply_descriptor_to_bag path). Value::to_string() produces a debug
      // string for object keys; to_js_string invokes ToPrimitive/toString.
      let k = to_js_string(key)
      if k == "length" {
        return self.array_set_length(arr, partial)
      }
      // Is this an array index?
      let idx = @string.parse_int(k) catch { _ => -1 }
      let is_index = idx >= 0 && idx.to_string() == k
      if is_index {
        // Check length writable if we're extending. Compare against the
        // logical length (override when sparse), not physical elements count.
        let logical_len = match get_array_length_override(arr) {
          Some(n64) => n64.to_int()
          None => arr.elements.length()
        }
        if idx >= logical_len && !arr.length_writable {
          return false
        }
        let had_index = idx < arr.elements.length() && !arr.holes.contains(idx)
        if !had_index && !arr.extensible {
          return false
        }
        // Grow elements to idx+1 with Undefined filler. Intermediate indices
        // (old_length..idx) become spec-level holes; the target index `idx`
        // is real and has its hole flag cleared below.
        while arr.elements.length() < idx {
          let pad_idx = arr.elements.length()
          arr.elements.push(Undefined)
          arr.holes[pad_idx] = ()
        }
        while arr.elements.length() <= idx {
          arr.elements.push(Undefined)
        }
        match arr.bag.descriptors.get(k) {
          Some(current) => {
            if !current.configurable {
              if !is_compatible_with_non_configurable(
                  current,
                  partial,
                  arr.elements[idx],
                ) {
                return false
              }
            }
            let merged = merge_partial_into(current, partial)
            // Clear fields that become invalid after a descriptor-kind transition.
            arr.bag.descriptors[k] = if !merged.is_accessor &&
              current.is_accessor {
              { ..merged, getter: None, setter: None }
            } else if merged.is_accessor && !current.is_accessor {
              { ..merged, writable: false }
            } else {
              merged
            }
          }
          None =>
            if had_index {
              let current = {
                writable: true,
                enumerable: true,
                configurable: true,
                getter: None,
                setter: None,
                is_accessor: false,
              }
              arr.bag.descriptors[k] = merge_partial_into(current, partial)
            } else {
              arr.bag.descriptors[k] = complete_partial_for_new(partial)
            }
        }
        arr.holes.remove(idx)
        match partial.value {
          Some(v) => arr.elements[idx] = v
          None => ()
        }
        return true
      }
      // Check for large valid array index: integers in [2^31, 2^32-2] that
      // parse_int can't handle. Use Double to detect them, then store in the
      // bag (can't materialise elements for a 4-billion-slot array) while
      // still updating the logical length override.
      let large_idx64 : Int64? = try {
        let n = @string.parse_double(k)
        let i64 = n.to_int64()
        if n >= 2147483648.0 &&
          n == i64.to_double() &&
          i64 <= 4294967294L &&
          i64.to_string() == k {
          Some(i64)
        } else {
          None
        }
      } catch {
        _ => None
      }
      match large_idx64 {
        Some(idx64) => {
          let logical_len = match get_array_length_override(arr) {
            Some(n64) => n64
            None => arr.elements.length().to_int64()
          }
          if idx64 >= logical_len && !arr.length_writable {
            return false
          }
          let existing = ordinary_get_own_string_desc(arr.bag, k)
          match existing {
            None => {
              if !arr.extensible {
                return false
              }
              let full = complete_partial_for_new(partial)
              apply_descriptor_to_bag(arr.bag, key, full, partial.value)
            }
            Some(current) => {
              if !current.configurable {
                let cur_val = match arr.bag.properties.get(k) {
                  Some(v) => v
                  None => Undefined
                }
                if !is_compatible_with_non_configurable(
                    current, partial, cur_val,
                  ) {
                  return false
                }
              }
              let merged = merge_partial_into(current, partial)
              let final_desc = if !merged.is_accessor && current.is_accessor {
                { ..merged, getter: None, setter: None }
              } else if merged.is_accessor && !current.is_accessor {
                { ..merged, writable: false }
              } else {
                merged
              }
              apply_descriptor_to_bag(arr.bag, key, final_desc, partial.value)
            }
          }
          let new_len = idx64 + 1L
          if new_len > logical_len {
            set_array_length_override(arr, new_len)
          }
          return true
        }
        None => ()
      }
      // Named non-index property — ordinary write against bag.
      let existing = ordinary_get_own_string_desc(arr.bag, k)
      match existing {
        None => {
          if !arr.extensible {
            return false
          }
          let full = complete_partial_for_new(partial)
          apply_descriptor_to_bag(arr.bag, key, full, partial.value)
          true
        }
        Some(current) => {
          if !current.configurable {
            let cur_val = match arr.bag.properties.get(k) {
              Some(v) => v
              None => Undefined
            }
            if !is_compatible_with_non_configurable(current, partial, cur_val) {
              return false
            }
          }
          let merged = merge_partial_into(current, partial)
          let final_desc = if !merged.is_accessor && current.is_accessor {
            { ..merged, getter: None, setter: None }
          } else if merged.is_accessor && !current.is_accessor {
            { ..merged, writable: false }
          } else {
            merged
          }
          apply_descriptor_to_bag(arr.bag, key, final_desc, partial.value)
          true
        }
      }
    }
  }
}

///|
/// ES §10.4.2.4 `ArraySetLength`. The partial truncation loop is the
/// crux of this algorithm — see the Learn by Doing contribution point.
pub fn Interpreter::array_set_length(
  self : Interpreter,
  arr : ArrayData,
  partial : PartialDescriptor,
) -> Bool raise Error {
  let _ = self
  // §15.4.5.1 step 3.a.i: length is always a non-configurable data property.
  // Trying to make it an accessor → TypeError.
  if partial.is_accessor() {
    return false
  }
  // length is always non-configurable and non-enumerable — reject any
  // attempt to flip those attributes regardless of whether value is present.
  if partial.configurable is Some(true) {
    return false
  }
  if partial.enumerable is Some(true) {
    return false
  }
  // Step 1-2: if Desc.[[Value]] absent, just adjust attributes.
  let new_len_value = match partial.value {
    Some(v) => v
    None => {
      // No value change — only length_writable / other attrs. Validate:
      // can't flip non-configurable (length is always non-configurable).
      if partial.configurable is Some(true) {
        return false
      }
      match partial.enumerable {
        Some(true) => return false
        _ => ()
      }
      // writable false->true is forbidden once frozen.
      if !arr.length_writable && partial.writable is Some(true) {
        return false
      }
      match partial.writable {
        Some(false) => arr.length_writable = false
        _ => ()
      }
      return true
    }
  }
  // Step 3-5: coerce to uint32 and validate. Use Int64 and match the
  // set_property "length" path (§7.1.6 ToUint32 + integer-valued check):
  // n must be a non-NaN integer in [0, 2^32-1]. Int32 narrowing would
  // incorrectly reject valid uint32 values > 2^31-1.
  let n = self.to_number(new_len_value)
  if n.is_nan() || n < 0.0 || n > 4294967295.0 || n != @math.floor(n) {
    raise @errors.RangeError(message="Invalid array length")
  }
  let new_len64 = n.to_int64()
  let cur_len64 = match get_array_length_override(arr) {
    Some(len) => len
    None => arr.elements.length().to_int64()
  }
  // Step 6: extension requires writable length; no-op (equal) always succeeds.
  if new_len64 > cur_len64 {
    if !arr.length_writable {
      return false
    }
    // Mirror the bounded grow in `set_property`'s length path
    // (property_set.mbt §10.4.2.4 step 3.b): only materialise small gaps.
    // Larger gaps fall back to the logical-length override so something like
    // `Object.defineProperty(arr, "length", { value: 1e9 })` doesn't try to
    // allocate a billion slots.
    let physical_len64 = arr.elements.length().to_int64()
    if new_len64 > physical_len64 &&
      new_len64 - physical_len64 <= 100000L &&
      new_len64 <= 0x7FFFFFFFL {
      let prev_len = arr.elements.length()
      while arr.elements.length().to_int64() < new_len64 {
        arr.elements.push(Undefined)
      }
      for j in prev_len..<arr.elements.length() {
        arr.holes.set(j, ())
      }
    }
    if new_len64 > arr.elements.length().to_int64() {
      set_array_length_override(arr, new_len64)
    } else {
      clear_array_length_override(arr)
    }
    match partial.writable {
      Some(false) => arr.length_writable = false
      _ => ()
    }
    return true
  }
  if new_len64 == cur_len64 {
    match partial.writable {
      Some(false) => arr.length_writable = false
      _ => ()
    }
    return true
  }
  // Step 7: if length is non-writable, truncation rejected.
  if !arr.length_writable {
    return false
  }
  // Step 8-9: defer writable:false until after truncation; remember intent.
  let lock_after = partial.writable is Some(false)
  match cleanup_sparse_array_indices_above_length(arr, new_len64) {
    Some(blocked_len) => {
      set_array_length_override(arr, blocked_len)
      if lock_after {
        arr.length_writable = false
      }
      return false
    }
    None => ()
  }
  // Step 10: partial-truncation loop. Delete indices in descending order.
  // `new_len64` safely fits in Int for truncation targets (must be less
  // than current length, which is bounded by JS engine).
  let new_len = if new_len64 > 0x7FFFFFFFL {
    0x7FFFFFFF
  } else {
    new_len64.to_int()
  }
  let mut i = arr.elements.length() - 1
  while i >= new_len {
    // Per §10.4.2.4 step 14.b: if element is non-configurable, stop.
    match arr.bag.descriptors.get(i.to_string()) {
      Some(desc) =>
        if !desc.configurable {
          let blocked_len = i.to_int64() + 1L
          if blocked_len > arr.elements.length().to_int64() {
            set_array_length_override(arr, blocked_len)
          } else {
            clear_array_length_override(arr)
          }
          if lock_after {
            arr.length_writable = false
          }
          return false
        }
      None => ()
    }
    let _removed = arr.elements.pop()
    let _ = arr.bag.descriptors.remove(i.to_string())
    let _ = arr.holes.remove(i)
    i = i - 1
  }
  cleanup_holes_above_length(arr.holes, new_len64)
  if new_len64 > arr.elements.length().to_int64() {
    set_array_length_override(arr, new_len64)
  } else {
    clear_array_length_override(arr)
  }
  if lock_after {
    arr.length_writable = false
  }
  true
}
