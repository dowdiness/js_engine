///|
pub(all) struct FuncData {
  name : String?
  params : Array[String]
  body : Array[@ast.Stmt]
  closure : Environment
  strict : Bool
  // True only for named FunctionExpression per §15.2.5: such functions
  // get a dedicated funcEnv (between outer env and call-time param env)
  // holding an immutable self-name binding. Methods, class methods,
  // function declarations, and anonymous functions do NOT get this
  // binding — `name` is used only for `.name` display in those cases.
  has_name_binding : Bool
  // True for method-shorthand definitions in object literals
  // (e.g. `{ m() {} }`). Per ES §15.4.5 MethodDefinitionEvaluation,
  // such functions have no [[Construct]] internal method and must throw
  // TypeError when called via `new`. Class methods use a separate path.
  is_method : Bool
  source_text : String?
}

///|
pub(all) struct FuncDataExt {
  name : String?
  params : Array[@ast.Param]
  rest_param : String?
  body : Array[@ast.Stmt]
  closure : Environment
  strict : Bool
  has_name_binding : Bool
  // True for method-shorthand definitions in object literals
  // (e.g. `{ m() {} }`). Per ES §15.4.5 MethodDefinitionEvaluation,
  // such functions have no [[Construct]] internal method and must throw
  // TypeError when called via `new`. Class methods use a separate path.
  is_method : Bool
  source_text : String?
}

///|
pub(all) enum CallContext {
  Call
  Construct
  ConstructWithTarget(Value)
}

///|
pub fn CallContext::is_constructing(self : CallContext) -> Bool {
  match self {
    Call => false
    Construct | ConstructWithTarget(_) => true
  }
}

///|
pub fn CallContext::new_target(self : CallContext) -> Value? {
  match self {
    ConstructWithTarget(value) => Some(value)
    _ => None
  }
}

///|
pub(all) enum Callable {
  UserFunc(FuncData)
  ArrowFunc(FuncData)
  UserFuncExt(FuncDataExt)
  ArrowFuncExt(FuncDataExt)
  NativeCallable(String, (Array[Value]) -> Value raise Error)
  NativeCallableWithContext(
    String,
    (CallContext, Array[Value]) -> Value raise Error
  )
  NonConstructableCallable(String, (Array[Value]) -> Value raise Error) // like NativeCallable but throws on new
  BoundFunc(Value, Value, Array[Value]) // (target, this_val, bound_args)
  FuncCallMethod(Value) // .call proxy: captures target function
  FuncApplyMethod(Value) // .apply proxy: captures target function
  MethodCallable(String, (Value, Array[Value]) -> Value raise Error) // this-aware native method
  InterpreterCallable(
    String,
    (Interpreter, Value, Array[Value]) -> Value raise Error
  ) // needs interpreter for callback invocation
  InterpreterCallableWithContext(
    String,
    (Interpreter, CallContext, Value, Array[Value]) -> Value raise Error
  )
  NonConstructableInterpreterCallable(
    String,
    (Interpreter, Array[Value]) -> Value raise Error
  ) // like InterpreterCallable but throws TypeError on new
  ConstructorOnlyCallable(
    String,
    (Interpreter, Array[Value]) -> Value raise Error
  ) // like InterpreterCallable but throws on call without new
  ClassConstructor(ClassConstructorData)
}

///|
/// Named fields for a class constructor callable.
/// Replaces the former anonymous 6-tuple so call sites are self-documenting
/// and future fields (e.g. instance fields, private names) can be added
/// without positional reasoning.

///|
/// A single instance field initializer, captured at class definition time.
pub(all) struct ClassFieldInit {
  key : Value // already-evaluated key (String_ for string keys, Symbol for symbol keys)
  initializer : @ast.Expr? // None if no `= expr`; evaluated with `this` = new instance
  closure : Environment // lexical closure for evaluating the initializer
}

///|
pub(all) struct ClassConstructorData {
  name : String // class name
  proto : Value // prototype object given to new instances
  super_ctor : Value? // super constructor when class uses `extends`
  ctor_fn : (Array[@ast.Param], String?, Array[@ast.Stmt])? // (params, rest_name, body); None = no explicit ctor
  closure : Environment // lexical environment where the class was defined
  super_proto : Value // super class's prototype (bound as [[SuperPrototype]])
  instance_fields : Array[ClassFieldInit] // instance field initializers, run before ctor body
  source_text : String?
}

///|
pub(all) struct PropDescriptor {
  mut writable : Bool
  mut enumerable : Bool
  mut configurable : Bool
  mut getter : Value? // Accessor descriptor: get function (None if absent or undefined)
  mut setter : Value? // Accessor descriptor: set function (None if absent or undefined)
  // True iff this was defined as an accessor (via get/set) even when both
  // getter and setter are None (i.e., `{ get: undefined }`).
  mut is_accessor : Bool
}

///|
pub(all) enum InternalSlotKey {
  StringData
  NumberData
  BooleanData
  SymbolData
  PrimitiveValue
  ArrayLength
  TypedArrayName
  ViewedArrayBuffer
  ArrayBufferID
  ByteOffset
  ByteLength
  ArrayBufferByteLength
  DateValue
  ExportName
  NamespaceObject
  ExportValue
  SyncIterator
  SyncNextMethod
  SourceText
} derive(Eq, Hash, Debug)

///|
/// Unified named/symbol property + descriptor storage embedded in every
/// exotic Value variant. Consolidates what used to be four parallel fields
/// so descriptor invariants are enforced in one place.
pub(all) struct PropertyBag {
  properties : Map[String, Value] // User-visible string-keyed properties only
  symbol_properties : Map[Int, Value] // Symbol-keyed properties (key is symbol ID)
  descriptors : Map[String, PropDescriptor]
  symbol_descriptors : Map[Int, PropDescriptor] // Descriptors for symbol properties
  internal_slots : Map[InternalSlotKey, Value] // Engine-internal slots, invisible to enumeration
}

///|
/// Construct an empty PropertyBag.
pub fn PropertyBag::PropertyBag() -> PropertyBag {
  {
    properties: {},
    symbol_properties: {},
    descriptors: {},
    symbol_descriptors: {},
    internal_slots: {},
  }
}

///|
pub(all) struct ArrayBufferState {
  id_counter : Ref[Int]
  store : Map[Int, Array[Int]]
  detached : Map[Int, Bool]
}

///|
pub fn ArrayBufferState::ArrayBufferState() -> ArrayBufferState {
  { id_counter: { val: 0 }, store: {}, detached: {} }
}

///|
pub(all) struct ObjectData {
  bag : PropertyBag
  mut prototype : Value // Mutable to support Object.setPrototypeOf()
  callable : Callable?
  class_name : String
  mut extensible : Bool
  arraybuffer_state : ArrayBufferState?
}

///|
pub(all) struct ArrayData {
  elements : Array[Value]
  bag : PropertyBag
  // §10.4.2.4: tracks whether Array `length` is writable. Starts `true`;
  // set to `false` by Object.defineProperty(arr, "length", {writable: false}).
  mut length_writable : Bool
  // Tracks deleted (hole) indices so ordinary_get_own_property and
  // has_array_property correctly report them absent after `delete arr[i]`.
  holes : Map[Int, Unit]
  // §10.4.2 [[Extensible]]: false after Object.preventExtensions/seal/freeze.
  mut extensible : Bool
}

///|
/// Partial property descriptor for VAP (§10.1.6.3 `ValidateAndApplyPropertyDescriptor`)
/// inputs. Each field is independently absent (`None`) or present (`Some(_)`),
/// distinct from the stored `PropDescriptor` where every attribute has a
/// concrete value. `has_getter` / `has_setter` disambiguate "field absent"
/// from "getter: undefined" since a user can write `{ get: undefined }`.
pub(all) struct PartialDescriptor {
  value : Value? // None = absent; Some(v) = present (v may be Undefined)
  writable : Bool?
  enumerable : Bool?
  configurable : Bool?
  getter : Value? // valid only when has_getter == true
  setter : Value?
  has_getter : Bool
  has_setter : Bool
}

///|
/// Build a PartialDescriptor representing the "no attributes specified" case.
pub fn PartialDescriptor::empty() -> PartialDescriptor {
  {
    value: None,
    writable: None,
    enumerable: None,
    configurable: None,
    getter: None,
    setter: None,
    has_getter: false,
    has_setter: false,
  }
}

///|
/// Build a PartialDescriptor representing ES §7.3.5 `CreateDataPropertyOrThrow`
/// — every data attribute explicit with defaults `writable/enumerable/configurable = true`.
/// Used by the `[[Set]]` landing rule §10.1.9.2 step 3.f.
pub fn PartialDescriptor::data_default(v : Value) -> PartialDescriptor {
  {
    value: Some(v),
    writable: Some(true),
    enumerable: Some(true),
    configurable: Some(true),
    getter: None,
    setter: None,
    has_getter: false,
    has_setter: false,
  }
}

///|
/// Build a PartialDescriptor with only `value` set. Used by the `[[Set]]`
/// landing rule §10.1.9.2 step 3.e (existing writable-data descriptor: call
/// `[[DefineOwnProperty]]` with just { [[Value]]: V }).
pub fn PartialDescriptor::value_only(v : Value) -> PartialDescriptor {
  {
    value: Some(v),
    writable: None,
    enumerable: None,
    configurable: None,
    getter: None,
    setter: None,
    has_getter: false,
    has_setter: false,
  }
}

///|
/// ES §6.2.5.4 `IsAccessorDescriptor`: true iff either getter or setter is
/// explicitly present on the partial.
pub fn PartialDescriptor::is_accessor(self : PartialDescriptor) -> Bool {
  self.has_getter || self.has_setter
}

///|
/// ES §6.2.5.4 `IsDataDescriptor`: true iff either value or writable is
/// explicitly present on the partial.
pub fn PartialDescriptor::is_data(self : PartialDescriptor) -> Bool {
  self.value is Some(_) || self.writable is Some(_)
}

///|
/// ES §6.2.5.4 `IsGenericDescriptor`: neither data nor accessor — only
/// enumerable/configurable populated, or nothing at all.
pub fn PartialDescriptor::is_generic(self : PartialDescriptor) -> Bool {
  !self.is_data() && !self.is_accessor()
}

///|
/// Symbol data structure - each symbol has a unique ID and optional description
pub(all) struct SymbolData {
  id : Int // Unique identifier for this symbol
  description : String? // Optional description (the argument to Symbol())
}

///|
/// Map data structure - stores key-value pairs with insertion order preservation
/// Uses SameValueZero for key comparison (NaN === NaN, +0 === -0)
pub(all) struct MapData {
  entries : Array[(Value, Value)] // Array of (key, value) pairs
  entry_ids : Array[Int] // Stable record identities for live-iteration semantics
  mut next_entry_id : Int
  // None = use realm's Map.prototype; Some(Null) = explicit null; Some(v) = override
  mut prototype : Value?
  // Expando properties: stores instance fields from subclasses (class D extends Map)
  bag : PropertyBag
}

///|
/// Construct MapData with entries and an empty property bag (no expando properties).
pub fn MapData::MapData(
  entries : Array[(Value, Value)],
  prototype? : Value? = None,
) -> MapData {
  let entry_ids : Array[Int] = []
  for i in 0..<entries.length() {
    entry_ids.push(i)
  }
  {
    entries,
    entry_ids,
    next_entry_id: entries.length(),
    prototype,
    bag: PropertyBag(),
  }
}

///|
/// Set data structure - stores unique values with insertion order preservation
/// Uses SameValueZero for value comparison (NaN === NaN, +0 === -0)
pub(all) struct SetData {
  values : Array[Value] // Array of unique values (includes tombstoned slots when Some(tombstones))
  // tombstones is Some while tombstone mode is active (set by make_set_iterator or
  // forEach). delete/clear tombstone instead of compacting when Some, so that stored
  // numeric cursor indices remain valid across concurrent iterators.
  // Compaction ONLY happens at forEach exit when tombstones_pre_existed=false.
  // Iterator exhaustion does NOT compact — multiple live iterators share the same
  // tombstone set and compacting on one would corrupt the other's stored cursor.
  mut tombstones : @set.Set[Int]?
  // Counts active forEach calls. forEach uses this to guard the compaction it owns:
  // a nested for..of that exhausts inside a forEach body checks iteration_depth>0
  // to avoid compacting while the forEach cursor is still walking.
  mut iteration_depth : Int
  // None = use realm's Set.prototype; Some(Null) = explicit null; Some(v) = override
  mut prototype : Value?
  // Expando properties: stores instance fields from subclasses (class D extends Set)
  bag : PropertyBag
}

///|
/// Construct SetData with values and an empty property bag (no expando properties).
pub fn SetData::SetData(
  values : Array[Value],
  prototype? : Value? = None,
) -> SetData {
  {
    values,
    tombstones: None,
    iteration_depth: 0,
    prototype,
    bag: PropertyBag(),
  }
}

///|
/// Live element count — values.length() minus tombstoned slots.
pub fn SetData::effective_size(self : SetData) -> Int {
  let ts_count = match self.tombstones {
    None => 0
    Some(ts) => ts.length()
  }
  self.values.length() - ts_count
}

///|
/// Promise state per ECMAScript spec
pub(all) enum PromiseState {
  Pending
  Fulfilled
  Rejected
}

///|
/// Promise reaction record - stores callbacks for promise resolution
/// Each reaction contains the handler (onFulfilled or onRejected) and the
/// dependent promise's resolve/reject capabilities
pub(all) struct PromiseReaction {
  handler : Value? // The callback function (None means identity/thrower)
  resolve : Value // Resolve function for the dependent promise
  reject : Value // Reject function for the dependent promise
  reaction_type : PromiseReactionType // Fulfill or Reject
}

///|
pub(all) enum PromiseReactionType {
  Fulfill
  Reject
}

///|
/// Promise data structure per ECMAScript spec
/// Promises have a state, result value, and queues of pending reactions
pub(all) struct PromiseData {
  mut state : PromiseState
  mut result : Value // undefined when pending, result when settled
  fulfill_reactions : Array[PromiseReaction] // Called when fulfilled
  reject_reactions : Array[PromiseReaction] // Called when rejected
  mut is_handled : Bool // Whether .catch or second arg to .then was provided
  bag : PropertyBag
  // None = use realm's Promise.prototype; Some(Null) = explicit null; Some(v) = override
  mut prototype : Value?
}

///|
/// Create a new pending promise data structure
pub fn new_promise_data() -> PromiseData {
  {
    state: Pending,
    result: Undefined,
    fulfill_reactions: [],
    reject_reactions: [],
    is_handled: false,
    bag: PropertyBag(),
    prototype: None,
  }
}

///|
/// Proxy data structure - wraps a target and handler for meta-programming
pub(all) struct ProxyData {
  mut target : Value? // None when revoked
  mut handler : Value? // None when revoked
  is_callable : Bool // Set at creation time, persists after revocation
}

///|
pub(all) enum Value {
  Number(Double)
  String_(String)
  Bool(Bool)
  Null
  Undefined
  Object(ObjectData)
  Array(ArrayData)
  Symbol(SymbolData)
  Map(MapData)
  Set(SetData)
  Promise(PromiseData)
  Proxy(ProxyData)
}

///|
// Engine-private negative symbol IDs are reserved in docs/development.md.
// -1 and -2 are Array exotic override slots stored in PropertyBag symbol maps;
// they must not collide with function realm metadata or traversal markers.
const ARRAY_LENGTH_OVERRIDE_SYMBOL_ID = -1

///|
const ARRAY_PROTOTYPE_OVERRIDE_SYMBOL_ID = -2

///|
fn default_data_descriptor() -> PropDescriptor {
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
/// Store sparse Array length state in the ArrayData PropertyBag. This keeps
/// Array exotic state attached to the array object instead of a module-level
/// identity side table, using a non-forgeable internal symbol id so ordinary
/// string-keyed property lookup cannot observe it.
pub fn set_array_length_override(arr : ArrayData, len : Int64) -> Unit {
  arr.bag.symbol_properties[ARRAY_LENGTH_OVERRIDE_SYMBOL_ID] = Number(
    len.to_double(),
  )
}

///|
pub fn get_array_length_override(arr : ArrayData) -> Int64? {
  match arr.bag.symbol_properties.get(ARRAY_LENGTH_OVERRIDE_SYMBOL_ID) {
    Some(Number(n)) => Some(n.to_int64())
    _ => None
  }
}

///|
pub fn clear_array_length_override(arr : ArrayData) -> Unit {
  let _ = arr.bag.symbol_properties.remove(ARRAY_LENGTH_OVERRIDE_SYMBOL_ID)
  let _ = arr.bag.symbol_descriptors.remove(ARRAY_LENGTH_OVERRIDE_SYMBOL_ID)
}

///|
pub fn set_array_prototype_override(arr : ArrayData, proto : Value) -> Unit {
  arr.bag.symbol_properties[ARRAY_PROTOTYPE_OVERRIDE_SYMBOL_ID] = proto
}

///|
pub fn get_array_prototype_override(arr : ArrayData) -> Value? {
  arr.bag.symbol_properties.get(ARRAY_PROTOTYPE_OVERRIDE_SYMBOL_ID)
}

///|
pub fn set_array_named_prop(
  arr : ArrayData,
  key : String,
  value : Value,
) -> Unit {
  arr.bag.properties[key] = value
  if !arr.bag.descriptors.contains(key) {
    arr.bag.descriptors[key] = default_data_descriptor()
  }
}

///|
pub fn get_array_named_prop(arr : ArrayData, key : String) -> Value? {
  arr.bag.properties.get(key)
}

///|
pub fn set_array_symbol_prop(
  arr : ArrayData,
  sym_id : Int,
  value : Value,
) -> Unit {
  arr.bag.symbol_properties[sym_id] = value
  if !arr.bag.symbol_descriptors.contains(sym_id) {
    arr.bag.symbol_descriptors[sym_id] = default_data_descriptor()
  }
}

///|
pub fn get_array_symbol_prop(arr : ArrayData, sym_id : Int) -> Value? {
  arr.bag.symbol_properties.get(sym_id)
}

///|
pub fn set_array_iterator_override(
  arr : ArrayData,
  well_known_symbols~ : WellKnownSymbols,
  getter : Value?,
  value : Value?,
) -> Unit {
  let iterator_sym = well_known_symbols.iterator
  match value {
    Some(v) => arr.bag.symbol_properties[iterator_sym.id] = v
    None => {
      let _ = arr.bag.symbol_properties.remove(iterator_sym.id)
    }
  }
  arr.bag.symbol_descriptors[iterator_sym.id] = {
    writable: true,
    enumerable: false,
    configurable: true,
    getter,
    setter: None,
    is_accessor: getter is Some(_),
  }
}

///|
pub fn get_array_iterator_override(
  arr : ArrayData,
  well_known_symbols~ : WellKnownSymbols,
) -> (Value?, Value?) {
  let iterator_sym = well_known_symbols.iterator
  let getter = match arr.bag.symbol_descriptors.get(iterator_sym.id) {
    Some(desc) => desc.getter
    None => None
  }
  let value = arr.bag.symbol_properties.get(iterator_sym.id)
  (getter, value)
}

///|
pub suberror JsException {
  JsException(Value)
}

///|
pub impl Show for Value with fn output(self, logger) {
  match self {
    Number(n) => {
      // Format integers without decimal point
      let i = n.to_int()
      if i.to_double() == n && !n.is_inf() && !n.is_nan() {
        logger.write_string(i.to_string())
      } else {
        logger.write_string(n.to_string())
      }
    }
    String_(s) => logger.write_string(s)
    Bool(b) => logger.write_string(b.to_string())
    Null => logger.write_string("null")
    Undefined => logger.write_string("undefined")
    Object(data) =>
      match data.callable {
        Some(UserFunc(func)) =>
          match func.name {
            Some(n) => logger.write_string("function \{n}() { [code] }")
            None => logger.write_string("function() { [code] }")
          }
        Some(ArrowFunc(_)) | Some(ArrowFuncExt(_)) =>
          logger.write_string("() => { [code] }")
        Some(UserFuncExt(func)) =>
          match func.name {
            Some(n) => logger.write_string("function \{n}() { [code] }")
            None => logger.write_string("function() { [code] }")
          }
        Some(BoundFunc(_, _, _)) =>
          logger.write_string("function bound() { [native code] }")
        Some(NativeCallable(name, _))
        | Some(NativeCallableWithContext(name, _)) =>
          logger.write_string("function \{name}() { [native code] }")
        Some(NonConstructableCallable(name, _)) =>
          logger.write_string("function \{name}() { [native code] }")
        Some(FuncCallMethod(_)) =>
          logger.write_string("function call() { [native code] }")
        Some(FuncApplyMethod(_)) =>
          logger.write_string("function apply() { [native code] }")
        Some(MethodCallable(name, _)) =>
          logger.write_string("function \{name}() { [native code] }")
        Some(InterpreterCallable(name, _))
        | Some(InterpreterCallableWithContext(name, _)) =>
          logger.write_string("function \{name}() { [native code] }")
        Some(NonConstructableInterpreterCallable(name, _)) =>
          logger.write_string("function \{name}() { [native code] }")
        Some(ConstructorOnlyCallable(name, _)) =>
          logger.write_string("function \{name}() { [native code] }")
        Some(ClassConstructor({ name, .. })) =>
          logger.write_string("class \{name} { [code] }")
        None =>
          // Boxed primitive objects: unwrap to primitive string representation
          if data.class_name == "String" {
            match data.bag.internal_slots.get(StringData) {
              Some(String_(s)) => logger.write_string(s)
              _ => logger.write_string("[object String]")
            }
          } else if data.class_name == "Number" {
            match data.bag.internal_slots.get(NumberData) {
              Some(n) => n.output(logger)
              _ => logger.write_string("[object Number]")
            }
          } else if data.class_name == "Boolean" {
            match data.bag.internal_slots.get(BooleanData) {
              Some(Bool(b)) => logger.write_string(b.to_string())
              _ => logger.write_string("[object Boolean]")
            }
          } else if data.class_name.has_suffix("Error") {
            let name = match data.bag.properties.get("name") {
              Some(String_(s)) => s
              _ => data.class_name
            }
            let msg = match data.bag.properties.get("message") {
              Some(String_(s)) => s
              _ => ""
            }
            if msg == "" {
              logger.write_string(name)
            } else {
              logger.write_string(name + ": " + msg)
            }
          } else {
            logger.write_string("[object \{data.class_name}]")
          }
      }
    Array(data) =>
      logger.write_string(
        data.elements
        .map(fn(v) {
          match v {
            Undefined | Null => ""
            _ => v.to_string()
          }
        })
        .join(","),
      )
    Symbol(sym) =>
      match sym.description {
        Some(desc) => logger.write_string("Symbol(\{desc})")
        None => logger.write_string("Symbol()")
      }
    Map(_) => logger.write_string("[object Map]")
    Set(_) => logger.write_string("[object Set]")
    Promise(_) => logger.write_string("[object Promise]")
    Proxy(proxy_data) =>
      if proxy_data.is_callable {
        logger.write_string("function proxy() { [native code] }")
      } else {
        logger.write_string("[object Object]")
      }
  }
}
