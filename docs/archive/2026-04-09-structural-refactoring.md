# Structural Refactoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split oversized files in the interpreter package into focused, single-responsibility files to improve navigability, cohesion, and reduce coupling — without changing any behavior.

**Architecture:** All splits are within the same MoonBit package (`interpreter/`). MoonBit packages span all `.mbt` files in a directory, so file splits have zero impact on visibility, imports, or linking. The existing 881 tests serve as a complete regression gate.

**Tech Stack:** MoonBit, `moon check`, `moon test`

---

## Extraction Strategy

All file extractions follow the same mechanical process:

1. **Read** the source file to identify exact function boundaries
2. **Write** the new file with the extracted functions (preserve all comments and doc-strings)
3. **Edit** the source file to remove the extracted content
4. **Verify** with `moon check && moon test`

Extract from the **bottom** of each file upward so that line numbers for remaining content stay stable.

---

## Phase 1: Split `interpreter.mbt` (10,699 lines → 10 files)

### Task 1: Extract `modules.mbt`

**Files:**
- Create: `interpreter/modules.mbt`
- Modify: `interpreter/interpreter.mbt`

**Functions to extract** (bottom of file, ~314 lines):
- `Interpreter::exec_import()`
- `Interpreter::exec_export_named()`
- `Interpreter::exec_export_all()`
- `Interpreter::extract_export_names()`
- `Interpreter::extract_pattern_export_names()`
- `Interpreter::register_module()`
- `Interpreter::run_module()`

- [ ] **Step 1: Read interpreter.mbt and identify boundaries**

Run: Grep for `^fn Interpreter::exec_import` to find the start line. Read from that line to end of file. The block starts with `exec_import` and ends at the last line of `run_module` (EOF).

- [ ] **Step 2: Write `interpreter/modules.mbt`**

Write the extracted functions to the new file. No imports needed — same package.

- [ ] **Step 3: Remove extracted content from `interpreter/interpreter.mbt`**

Delete from the `///|` doc-comment above `exec_import` through end of file.

- [ ] **Step 4: Verify**

Run: `moon check && moon test`
Expected: All 881 tests pass.

- [ ] **Step 5: Commit**

```bash
git add interpreter/modules.mbt interpreter/interpreter.mbt
git commit -m "refactor(interpreter): extract ES module support to modules.mbt"
```

---

### Task 2: Extract `operators.mbt`

**Files:**
- Create: `interpreter/operators.mbt`
- Modify: `interpreter/interpreter.mbt`

**Functions to extract** (~383 lines, now at bottom after Task 1):
- `Interpreter::eval_update()`
- `Interpreter::eval_compound_assign()`
- `Interpreter::eval_logical_assign_and()`
- `Interpreter::eval_logical_assign_or()`
- `Interpreter::eval_nullish_assign()`

- [ ] **Step 1: Read and identify boundaries**

Grep for `^fn Interpreter::eval_update` to find the start. The block ends at the last line before the content removed in Task 1 (now EOF).

- [ ] **Step 2: Write `interpreter/operators.mbt`**

- [ ] **Step 3: Remove extracted content from `interpreter/interpreter.mbt`**

- [ ] **Step 4: Verify**

Run: `moon check && moon test`
Expected: All 881 tests pass.

- [ ] **Step 5: Commit**

```bash
git add interpreter/operators.mbt interpreter/interpreter.mbt
git commit -m "refactor(interpreter): extract update/compound/logical assignment ops to operators.mbt"
```

---

### Task 3: Extract `class.mbt`

**Files:**
- Create: `interpreter/class.mbt`
- Modify: `interpreter/interpreter.mbt`

**Functions to extract** (~358 lines):
- `ensure_strict_body()`
- `Interpreter::create_class()`

- [ ] **Step 1-5:** Same mechanical process. Grep for `^fn ensure_strict_body`.

- [ ] **Commit message:** `refactor(interpreter): extract class creation to class.mbt`

---

### Task 4: Extract `construct.mbt`

**Files:**
- Create: `interpreter/construct.mbt`
- Modify: `interpreter/interpreter.mbt`

**Functions to extract** (~774 lines):
- `Interpreter::eval_new()`
- `is_object_like_for_constructor_return()`
- `make_constructor_instance()`
- `make_arguments_object()`
- `format_loc_context()`
- `maybe_set_promise_constructor()`
- `Interpreter::construct_value()`

- [ ] **Step 1-5:** Same process. Grep for `^fn Interpreter::eval_new`.

- [ ] **Commit message:** `refactor(interpreter): extract construction logic to construct.mbt`

---

### Task 5: Extract `property.mbt`

**Files:**
- Create: `interpreter/property.mbt`
- Modify: `interpreter/interpreter.mbt`

**Functions to extract** (~1777 lines):
- `Interpreter::get_property()`
- `lookup_builtin_proto()`
- `Interpreter::get_computed_property()`
- `Interpreter::set_property()`
- `Interpreter::set_computed_property()`

- [ ] **Step 1-5:** Same process. Grep for `^fn Interpreter::get_property\b`.

- [ ] **Commit message:** `refactor(interpreter): extract property access to property.mbt`

---

### Task 6: Extract `call.mbt`

**Files:**
- Create: `interpreter/call.mbt`
- Modify: `interpreter/interpreter.mbt`

**Functions to extract** (~952 lines):
- `Interpreter::spread_iterable()`
- `Interpreter::eval_args_with_spread()`
- `is_eval_function()`
- `unwrap_grouping()`
- `Interpreter::perform_eval()`
- `Interpreter::eval_call()`
- `Interpreter::call_value()`
- `Interpreter::eval_member()`
- `get_bound_func_name()`
- `get_func_length()`

- [ ] **Step 1-5:** Same process. Grep for `^fn Interpreter::spread_iterable`.

- [ ] **Commit message:** `refactor(interpreter): extract function calling to call.mbt`

---

### Task 7: Extract `eval_expr.mbt`

**Files:**
- Create: `interpreter/eval_expr.mbt`
- Modify: `interpreter/interpreter.mbt`

**Functions to extract** (~1754 lines):
- `Interpreter::eval_expr()`
- `Interpreter::eval_binary()`
- `eval_binary_op()`
- `get_symbol_method()`
- `instanceof_prototype_chain()`
- `get_constructor_prototype()`
- `strict_equal()`
- `loose_equal()`
- `Interpreter::is_immutable_global()`
- `Interpreter::eval_unary()`

- [ ] **Step 1-5:** Same process. Grep for `^fn Interpreter::eval_expr\b`.

Note: `eval_unary` immediately follows `is_immutable_global` and precedes the content removed in Task 6. This forms one contiguous block from `eval_expr` through `eval_unary`.

- [ ] **Commit message:** `refactor(interpreter): extract expression evaluation to eval_expr.mbt`

---

### Task 8: Extract `destructuring.mbt`

**Files:**
- Create: `interpreter/destructuring.mbt`
- Modify: `interpreter/interpreter.mbt`

**Functions to extract** (~860 lines, two contiguous blocks now adjacent):
- `Interpreter::bind_pattern()`
- `Interpreter::assign_pattern()`
- `Interpreter::assign_to_expr()`
- `close_iterator()`
- `Interpreter::exec_try_catch()`

Note: `close_iterator` and `exec_try_catch` originally sat between destructuring and eval_expr. After extracting eval_expr (Task 7), they are now at the bottom of the remaining content, directly below `assign_to_expr`. Extract the entire contiguous block from `bind_pattern` through `exec_try_catch`.

Design note: `close_iterator` is a for-of/destructuring concern (closing iterators on break/return). `exec_try_catch` is a statement concern but sits here due to original file ordering. If desired, `exec_try_catch` could be moved to `exec_stmt.mbt` in a later pass, but keeping the extraction contiguous is simpler and the cohesion impact is minimal.

- [ ] **Step 1-5:** Same process. Grep for `^fn Interpreter::bind_pattern`.

- [ ] **Commit message:** `refactor(interpreter): extract destructuring and try-catch to destructuring.mbt`

---

### Task 9: Extract `hoisting.mbt`

**Files:**
- Create: `interpreter/hoisting.mbt`
- Modify: `interpreter/interpreter.mbt`

**Functions to extract** (~1545 lines):
- `collect_pattern_var_names()`
- `add_lexical_decl_name()`
- `collect_pattern_decl_names()`
- `collect_block_lexical_decl_names_from_stmt()`
- `collect_block_var_decl_names_from_stmt()`
- `validate_block_statement_list_early_errors()`
- `validate_block_early_errors_expr()`
- `validate_block_early_errors_stmt()`
- `Interpreter::validate_block_early_errors()`
- `collect_eval_var_names_from_stmt()`
- `collect_eval_var_names()`
- `hoist_pattern()`
- `hoist_var_declarations_from_stmt()`
- `hoist_block_func_declarations()`
- `Interpreter::hoist_declarations()`
- `hoist_block_tdz()`
- `hoist_pattern_tdz()`

- [ ] **Step 1-5:** Same process. Grep for `^fn collect_pattern_var_names`.

- [ ] **Commit message:** `refactor(interpreter): extract hoisting and early errors to hoisting.mbt`

---

### Task 10: Extract `exec_stmt.mbt`

**Files:**
- Create: `interpreter/exec_stmt.mbt`
- Modify: `interpreter/interpreter.mbt`

**Functions to extract** (~1584 lines):
- `Interpreter::exec_stmt()`
- `collect_for_in_keys()`
- `is_declaration_stmt()`
- `Interpreter::exec_stmts()`

These are now at the bottom of the remaining content (after all previous extractions removed everything below them).

- [ ] **Step 1-5:** Same process. Grep for `^fn Interpreter::exec_stmt\b`.

- [ ] **Commit message:** `refactor(interpreter): extract statement execution to exec_stmt.mbt`

---

### Task 10 Checkpoint: Verify `interpreter.mbt` Core

After all extractions, `interpreter.mbt` should contain only (~400 lines):
- `is_anonymous_function_definition()` — expression categorization utility
- `Signal` enum, `Microtask` struct, `TimerTask` struct
- `Interpreter` struct definition
- `Interpreter::new()` — constructor with global setup
- `has_use_strict()`, `is_strict_reserved_word()`, `validate_strict_binding_name()`
- `check_duplicate_params()`, `check_duplicate_params_ext()`
- `is_function_strict()`, `validate_function_signature()`, `validate_function_signature_ext()`
- `should_reconcile_eval_function_decl()`, `Interpreter::mirror_to_global()`
- `Interpreter::run()` — main entry point

- [ ] **Verify line count:** `wc -l interpreter/interpreter.mbt` should be ~400 lines
- [ ] **Verify tests:** `moon check && moon test` — all 881 pass

---

## Phase 2: Split `builtins.mbt` (6,046 lines → 6 files)

### Task 11: Extract `builtins_math.mbt`

**Files:**
- Create: `interpreter/builtins_math.mbt`
- Modify: `interpreter/builtins.mbt`

**Functions to extract:**
- `setup_math_builtins()`

Grep for `^fn setup_math_builtins`. Extract from the `///|` above it to the line before `register_error_ctor`.

- [ ] **Steps 1-5:** Extract, verify with `moon check && moon test`, commit.

- [ ] **Commit message:** `refactor(interpreter): extract Math builtins to builtins_math.mbt`

---

### Task 12: Extract `builtins_error.mbt`

**Files:**
- Create: `interpreter/builtins_error.mbt`
- Modify: `interpreter/builtins.mbt`

**Functions to extract:**
- `register_error_ctor()`
- `register_aggregate_error_ctor()`

Grep for `^fn register_error_ctor`. Extract from there through the end of `register_aggregate_error_ctor` (before `trim_start`).

- [ ] **Commit message:** `refactor(interpreter): extract Error constructors to builtins_error.mbt`

---

### Task 13: Extract `builtins_number.mbt`

**Files:**
- Create: `interpreter/builtins_number.mbt`
- Modify: `interpreter/builtins.mbt`

**Functions to extract:**
- `trim_start()` (parsing utility used by number parsing)
- `is_parse_whitespace()`
- `char_to_digit()`
- `setup_number_builtins()`
- `get_number_method()`
- `format_number_precision()`

Grep for `^fn trim_start`. Extract from there through `format_number_precision` (before `json_escape_string`).

Note: `trim_start` and `is_parse_whitespace` are also used by `parseInt` in the remaining builtins.mbt. Since all files share the package, this works without issues.

- [ ] **Commit message:** `refactor(interpreter): extract Number builtins to builtins_number.mbt`

---

### Task 14: Extract `builtins_json.mbt`

**Files:**
- Create: `interpreter/builtins_json.mbt`
- Modify: `interpreter/builtins.mbt`

**Functions to extract:**
- `setup_json_builtins()`
- `json_parse()`
- `json_internalize()`
- `json_stringify_value()`
- `json_escape_string()`

Grep for `^fn setup_json_builtins`. Note that `json_escape_string` may not be contiguous with the others (it was originally between `format_number_precision` and `setup_function_builtins`). After Task 13 extracts `format_number_precision`, verify the order. Extract all JSON-related functions.

- [ ] **Commit message:** `refactor(interpreter): extract JSON builtins to builtins_json.mbt`

---

### Task 15: Extract `builtins_function.mbt`

**Files:**
- Create: `interpreter/builtins_function.mbt`
- Modify: `interpreter/builtins.mbt`

**Functions to extract:**
- `setup_function_builtins()`

Grep for `^fn setup_function_builtins`. Extract to the line before `uri_encode`.

- [ ] **Commit message:** `refactor(interpreter): extract Function.prototype builtins to builtins_function.mbt`

---

### Task 15 Checkpoint: Verify `builtins.mbt` Core

After all extractions, `builtins.mbt` should contain (~2400 lines):
- `func_body_has_use_strict()` — directive prologue scanner
- `setup_builtins()` — main coordinator + global constants + eval, isNaN, isFinite, parseInt, parseFloat
- `setup_symbol_builtins()` — Symbol constructor and well-known symbols
- `setup_iterator_protocol()` — IteratorResult, generator function constructor
- URI codec functions: `uri_encode()`, `is_uri_reserved()`, `uri_decode()`, `hex_char_value()`, `decode_percent_byte()`
- Annex B: `js_escape()`, `js_unescape()`
- `setup_harness_builtins()` — test262 harness support

These remaining functions are all part of global scope initialization — good cohesion.

- [ ] **Verify:** `moon check && moon test` — all 881 pass.

---

## Phase 3: Split `value.mbt` (2,192 lines → 6 files)

### Task 16: Extract `iterators.mbt`

**Files:**
- Create: `interpreter/iterators.mbt`
- Modify: `interpreter/value.mbt`

**Functions to extract** (bottom of file):
- `get_iterator_proto()`
- `get_array_iterator_proto()`
- `make_array_iterator_value()`
- `get_string_iterator_proto()`
- `make_string_iterator_value()`
- `sort_property_keys()`

Grep for `^pub fn get_iterator_proto`. Extract from there to EOF.

- [ ] **Commit message:** `refactor(interpreter): extract iterator protocol to iterators.mbt`

---

### Task 17: Extract `conversions.mbt`

**Files:**
- Create: `interpreter/conversions.mbt`
- Modify: `interpreter/value.mbt`

**Functions to extract:**
- `is_truthy()`
- `call_callable_direct()` (used by ToPrimitive)
- `set_function_name()`
- `is_callable()`
- `has_property()`
- `lookup_property_chain()`
- `lookup_symbol_property_chain()`
- `to_primitive_number()`
- `to_primitive_default()`
- `is_js_whitespace_code()`
- `js_trim_whitespace()`
- `to_number()`
- `to_primitive_string()`
- `to_js_string()`
- `to_index()`
- `to_int32()`
- `type_of()`

Grep for `^pub fn is_truthy`. Extract the contiguous block from `is_truthy` through `type_of`.

- [ ] **Commit message:** `refactor(interpreter): extract type conversions to conversions.mbt`

---

### Task 18: Extract `factories.mbt`

**Files:**
- Create: `interpreter/factories.mbt`
- Modify: `interpreter/value.mbt`

**Functions to extract:**
- `make_func()`
- `make_func_ext()`
- `get_func_proto()`
- `get_obj_proto()`
- `get_string_proto()`
- `get_number_proto()`
- `get_boolean_proto()`
- `get_symbol_proto()`
- `make_native_func()`
- `make_native_func_with_length()`
- `make_static_func()`
- `make_static_func_with_length()`
- `make_method_func()`
- `make_interp_method_func()`
- `make_object()`
- `make_plain_object()`

Grep for `^pub fn make_func\b`. Extract the contiguous block.

- [ ] **Commit message:** `refactor(interpreter): extract value factories to factories.mbt`

---

### Task 19: Extract `symbols.mbt`

**Files:**
- Create: `interpreter/symbols.mbt`
- Modify: `interpreter/value.mbt`

**Functions to extract:**
- `is_constructor_value()`
- `is_function_value()`
- `new_symbol()`
- `get_symbol_by_id()`
- All well-known symbol getters: `get_iterator_symbol()`, `get_async_iterator_symbol()`, `get_hasinstance_symbol()`, `get_isconcatspreadable_symbol()`, `get_toprimitive_symbol()`, `get_tostringtag_symbol()`, `get_species_symbol()`, `get_match_symbol()`, `get_replace_symbol()`, `get_search_symbol()`, `get_split_symbol()`, `get_matchall_symbol()`, `get_unscopables_symbol()`
- `get_tostringtag_value()`
- All global `Ref` and `Map` state for symbol registry (e.g., `symbol_counter`, `symbol_registry`, well-known symbol refs)

Grep for `^pub fn is_constructor_value` to find the start. The block ends before `make_func`.

**Important:** Also extract the global `let` declarations for the symbol registry that precede these functions. Search for `let symbol_counter`, `let symbol_registry`, and all `let xxx_symbol : Ref` declarations.

- [ ] **Commit message:** `refactor(interpreter): extract symbol registry to symbols.mbt`

---

### Task 20: Extract `array_side_tables.mbt`

**Files:**
- Create: `interpreter/array_side_tables.mbt`
- Modify: `interpreter/value.mbt`

**Functions to extract:**
- Global `let array_iterator_overrides`
- Global `let array_named_props`
- Global `let array_symbol_props`
- `set_array_named_prop()`
- `get_array_named_prop()`
- `set_array_symbol_prop()`
- `get_array_symbol_prop()`
- `set_array_iterator_override()`
- `get_array_iterator_override()`

These follow immediately after `new_promise_data()`.

- [ ] **Commit message:** `refactor(interpreter): extract array side tables to array_side_tables.mbt`

---

### Task 20 Checkpoint: Verify `value.mbt` Core

After all extractions, `value.mbt` should contain only type definitions (~165 lines):
- `FuncData`, `FuncDataExt` structs
- `Callable` enum
- `PropDescriptor` struct
- `ObjectData`, `ArrayData`, `SymbolData`, `MapData`, `SetData` structs
- `PromiseState` enum, `PromiseReaction` struct, `PromiseReactionType` enum, `PromiseData` struct
- `new_promise_data()` factory

- [ ] **Verify:** `moon check && moon test` — all 881 pass.

---

## Phase 4: Clean Root Package

### Task 21: Remove demo functions from `js_engine.mbt`

**Files:**
- Modify: `js_engine.mbt`
- Modify: `js_engine_test.mbt`

- [ ] **Step 1: Remove `fib()` and `sum()` from `js_engine.mbt`**

Delete the `fib` function (lines 1-9) and `sum` function (lines 11-22).

- [ ] **Step 2: Remove corresponding tests from `js_engine_test.mbt`**

Delete the `test "fib"` block and the `test "sum"` block.

- [ ] **Step 3: Verify**

Run: `moon check && moon test`
Expected: 879 tests pass (2 removed).

- [ ] **Step 4: Commit**

```bash
git add js_engine.mbt js_engine_test.mbt
git commit -m "refactor: remove demo functions (fib, sum) from public API"
```

---

## Final Verification

- [ ] Run `moon check && moon test` — expect 879 tests pass
- [ ] Run `wc -l interpreter/*.mbt | sort -rn` — verify no file exceeds ~2500 lines (excluding test file)
- [ ] Run `moon info` to confirm package API is unchanged (110 pub decls in interpreter, minus 2 root pub decls removed)

## Resulting File Structure

```
interpreter/
  interpreter.mbt      ~400 lines  Core: structs, new(), run(), validation helpers
  exec_stmt.mbt        ~1584 lines Statement execution
  eval_expr.mbt        ~1754 lines Expression evaluation, binary/unary ops, comparisons
  call.mbt             ~952 lines  Function calling, eval, argument spreading
  construct.mbt        ~774 lines  Object construction, arguments object
  class.mbt            ~358 lines  Class creation
  property.mbt         ~1777 lines Property get/set, computed property, prototype chain
  hoisting.mbt         ~1545 lines Var hoisting, TDZ, early error validation
  destructuring.mbt    ~860 lines  Pattern binding/assignment, try-catch, iterator close
  operators.mbt        ~383 lines  Update, compound assignment, logical assignment
  modules.mbt          ~314 lines  ES module import/export/registration
  value.mbt            ~165 lines  Type definitions only
  symbols.mbt          ~280 lines  Symbol registry, well-known symbols
  conversions.mbt      ~730 lines  Type coercion (ToPrimitive, ToNumber, ToString)
  factories.mbt        ~500 lines  Value constructors (make_func, make_object, etc.)
  iterators.mbt        ~370 lines  Iterator protocol, array/string iterators
  array_side_tables.mbt ~100 lines Array property side tables
  environment.mbt      348 lines   (unchanged)
  errors.mbt           160 lines   (unchanged)
  generator.mbt        1180 lines  (unchanged)
  async.mbt            598 lines   (unchanged)
  builtins.mbt         ~2400 lines Global setup coordinator, symbols, iterators, URI
  builtins_math.mbt    ~414 lines  (new) Math object
  builtins_error.mbt   ~380 lines  (new) Error constructors
  builtins_number.mbt  ~700 lines  (new) Number constructor, parsing helpers
  builtins_json.mbt    ~1200 lines (new) JSON parse/stringify
  builtins_function.mbt ~408 lines (new) Function.prototype (bind/call/apply)
  builtins_object.mbt  5865 lines  (unchanged)
  builtins_string.mbt  1830 lines  (unchanged)
  builtins_array.mbt   1628 lines  (unchanged)
  builtins_date.mbt    1916 lines  (unchanged)
  builtins_promise.mbt 1855 lines  (unchanged)
  builtins_regex.mbt   1457 lines  (unchanged)
  builtins_map_set.mbt 1424 lines  (unchanged)
  builtins_reflect.mbt 1038 lines  (unchanged)
  builtins_weakmap_set.mbt 883 lines (unchanged)
  builtins_typedarray.mbt 2759 lines (unchanged)
  builtins_dataview.mbt 801 lines  (unchanged)
  builtins_arraybuffer.mbt 416 lines (unchanged)
  builtins_proxy.mbt   236 lines   (unchanged)
  interpreter_test.mbt 9021 lines  (unchanged)
```
