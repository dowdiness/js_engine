# Bytecode execution representation contract

Date: 2026-07-29.

## Status

Proposed for #601. It becomes accepted when merged and linked from the owning
issue. It changes no runtime behavior; it fixes the representation contract for
the compiler and runtime work that follows.

## Context

Issue #601 asks whether the engine needs a backend-neutral executable IR between
prepared source and stack bytecode. At first that extra layer looks attractive:
tree-walk and bytecode must agree on JavaScript behavior, and another IR might
appear to give them a common language.

The current architecture does not support that expectation. Tree-walk executes
AST independently. Closure conversion is still available as an opt-in compiled
path, but it executes MoonBit closures over AST nodes and is frozen under its
legacy retirement policy
([closure-conversion-and-bytecode.md](../design/closure-conversion-and-bytecode.md)).
No register, AOT, or native-code backend exists. Stack bytecode is therefore the
only compiled representation eligible to grow.

The package boundary already separates the responsibilities that really are
shared. Static facts such as strictness, declaration plans, early errors,
capture analysis, dynamic-scope analysis, and source identity belong in
`static_semantics` preparation products. JavaScript internal methods belong
behind runtime-operation interfaces. The dependency remains `compiler` →
`runtime`: `compiler/moon.pkg` imports `interpreter/runtime`, while
`interpreter/runtime/moon.pkg` does not import `compiler`.

That leaves a narrower question. Does another executable layer remove complexity
from more than one current consumer, or does it merely translate once into the
stack instructions that already execute?

## Decision

Deepen the existing stack bytecode as the sole long-term compiled executable
representation (**Alternative B**). Add a pure verifier between lowering and
execution. Keep instructions, functions, and frames executor-private. Keep
runtime operations as the sole owner of JavaScript semantics.

A separate backend-neutral ExecutionIR (**Alternative A**) is rejected because
it has one eligible consumer and fails both the adapter and deletion tests.
Replacing stack bytecode with a register/basic-block representation
(**Alternative C**) is rejected because no benchmark identifies the stack model
itself as the bottleneck.

This decision removes a speculative layer, not the remaining risks. Current
bytecode can still carry executable AST, runtime `Value`, and mutable `Binding`
representations; it can still enter guest calls synchronously; and malformed
bytecode has no pre-execution proof. Stack bytecode is acceptable only if those
leaks are removed and its verifier and control flow remain local to the closed
instruction set. Failure on either point reopens the representation decision.

---

## 1. Why a separate ExecutionIR does not pay for itself

### Adapter test

A shared executable representation is justified when two concrete adapters need
it. Only the stack VM consumes compiled instructions today:

- Tree-walk remains an independent AST executor.
- Closure conversion in `compiler/closure_conversion.mbt` consumes AST through
  MoonBit closures. Adapting it would expand a path that is explicitly frozen.
- Register, AOT, and native-code consumers are hypothetical.

`BytecodeInstr` in `compiler/bytecode_ir.mbt` is intentionally stack-shaped.
`Dup`, `Pop`, accumulator operations, conditional jumps, and
receiver-preserving call preparation encode one operand-stack discipline. A
future register or basic-block backend would not reuse those mechanics
unchanged.

The facts shared with tree-walk already have an owner in static preparation, and
the semantics shared with tree-walk already have an owner in runtime operations.
A new executable IR would sit between those boundaries and one stack-bytecode
lowerer.

### Deletion test

Removing that proposed IR would restore the direct path that already exists:
prepared AST and facts → stack-bytecode lowering. Translation logic would return
to one lowerer; it would not reappear across several adapters. The extra module
would therefore add a vocabulary and translation pass without localizing
repeated complexity.

Under the anti-speculation rule in the architecture execution plan §1.7, a new
boundary needs multiple concrete consumers or proven semantic duplication that
it removes. Neither condition holds.

### Alternatives at a glance

| Criterion | A: shared ExecutionIR | B: deepen stack bytecode | C: register/basic-block |
|---|---|---|---|
| Concrete consumers | One eligible consumer | One consumer, one representation | One rewritten consumer |
| Deletion result | Restores direct lowering | No intermediate layer to delete | Not applicable |
| Semantic hard cases | Still owned by runtime and dispatcher | Ownership remains explicit | Same ownership as B |
| Migration cost | New IR, adapter, and translation pass | Verifier and boundary tightening | Rewrite instructions, lowering, VM, and tests |
| Evidence | No second consumer | Matches current architecture | No stack-specific benchmark |

---

## 2. Representation contract

### 2.1 Lowering, verification, and execution

The executable path has three stages.

1. **Private unverified lowering product.** `BytecodeBuilder` produces a private
   program/function tree. During construction it may contain unresolved patches
   or incomplete accumulator sequences. The current public `BytecodeProgram` is
   not this builder product.
2. **Pure verifier.** The verifier checks jump and handler targets, stack shape
   at joins, slot/constant/child indices, terminators, source identity, and
   required observation coverage. It returns a typed result without touching
   the interpreter, environment, realm, or host state. It proves structural
   integrity, not JavaScript behavior.
3. **Verified executable data.** The experimental public `BytecodeProgram`
   remains a facade with private fields and wraps only verified executable data.
   Unverified builder state cannot reach `run_bytecode_function`.

The bytecode/tree-walker equivalence harness remains responsible for behavioral
correctness. The verifier cannot replace it: structurally valid instructions can
still implement the wrong ECMAScript algorithm.

### 2.2 Private executor state

`BytecodeInstr`, `BytecodeFunction`, `BytecodeFrame`, `BytecodeBuilder`,
`BytecodeLocalPlan`, `BytecodeRunResult`, `BytecodeForInState`, and patch
contexts remain private to `compiler`. The experimental public surface remains
`BytecodeProgram`, `compile_script_to_bytecode`, `run_bytecode_script`, and
`BytecodeProgram::run`.

The target activation seam
([engine-activation-continuation-contract.md](engine-activation-continuation-contract.md))
sits above tree-walk and bytecode adapters without importing bytecode internals.
Under #631, a private `BytecodeFrame` yields requests and completions when an
operation may call guest code; it does not expose its instruction pointer,
operand stack, or frame state through the public seam.

### 2.3 Runtime operations own JavaScript semantics

Instructions own dispatch, frame mechanics, and control transfer. Runtime
operations own ECMAScript decisions. The VM already delegates substantial work:

- binary and unary operations to `@runtime.eval_binary_op` and
  `@runtime.eval_unary_value_op`;
- property get, set, and delete to `interp.get_property`,
  `interp.set_property`, and `@runtime.eval_delete_property`;
- calls and construction to `interp.call_value` and `interp.construct_value`;
- name access to `interp.get_compiled_name` and
  `interp.assign_compiled_name`;
- array and object creation to `@runtime.make_array`, `@runtime.make_object`,
  and `@runtime.apply_array_literal_element`;
- direct eval to `interp.call_direct_eval_or_shadowed`;
- conversions to `@runtime.to_number`, `@runtime.to_js_string`, and
  `@runtime.to_property_key`;
- JavaScript exception raising to `@runtime.raise_js_exception`.

The boundary is incomplete. `UpdateLocal` still performs conversion and
arithmetic inline, template accumulation still makes a string decision locally,
and property assignment still manipulates references in the VM. Stages 7–12
must move those semantic decisions outward rather than adding new ones to
bytecode.

### 2.4 Executable representation must not leak AST or runtime storage

Four current forms cross the intended boundary.

- `AssignDestructure(@runtime.DestructurePlan)` carries an immutable, closed
  plan for the currently admitted identifier/static-key/nested
  array/object/hole/rest subset. Small closed tags such as `@ast.BinOp` may
  remain temporarily as operation identifiers only; they must never trigger
  AST evaluation. The plan is lowered once and is the sole executable
  destructuring authority in bytecode; runtime owns iterator, property, and
  binding semantics. Defaults, computed keys, and member targets remain
  lowering-time unsupported.
  Issue #636 owns its next preparation/lowering migration.
- Finalized bytecode carriers contain no executable `Stmt`, `Expr`, or
  `Pattern` AST. Function preparation retains copied signature facts,
  declaration/lexical setup facts, and an opaque runtime activation-capability
  summary. Child provenance is tied to the existing
  `SourceUnitHandle`/`SourcePointOwnerId` pair, parent owner, child index, and
  closed consumer form; no parallel source-ID registry is introduced. Exact
  parser source text is copied separately as immutable metadata for
  `Function.prototype.toString` and is never reconstructed from bytecode.
  Finalization verifies the typed identity, text, header facts, and immutable
  preparation snapshot without re-reading an AST body. Root scripts carry a
  `CompiledScriptPreparation` envelope containing strictness, declaration
  names, lexical TDZ facts, and settled early-error state. The runtime remains
  the owner of global-object/property attributes, declaration conflicts,
  binding/TDZ mutation, active realm installation, and JavaScript exception
  conversion. The bytecode runtime entry receives only that envelope. The
  settled early-error result is carried by an opaque, per-lowering settlement
  token; finalization compares that token with the independently retained root
  provenance before constructing the verified carrier, so a general facts
  constructor cannot replace or omit the result.
  Tree-walk's source-backed classified-function factories still use `source_body`
  for their existing capability admission; that is outside the finalized
  bytecode boundary. The typed AST audit resolves every executable identifier
  through MoonBit's inferred hover type, fails closed on unresolved candidates,
  scans both finalized IR and VM code, and permits only the structurally
  identified AST-free destructuring-plan instruction payload.
- `LoadConst(Value)` and `SetCompletionValue(Value)` embed runtime
  representation. The instruction stream must instead contain private literal
  descriptors or recipes. The verifier checks them, and execution materializes
  runtime values through runtime operations. This needs a focused follow-up
  after #601; #634 owns lowering outcomes, not constant encoding.
- Environment slots currently retain mutable `Binding` references, and
  `bind_env_slots` accesses `Environment.bindings` directly. #638 must replace
  that access with runtime-owned slot handles.

Closure-conversion activation helpers are not a fifth source of reusable
machinery. That path is frozen and must not supply new activation patterns or
semantic special cases to bytecode.

### 2.5 Source identity and observation

Every required observation point must resolve to source identity and span
metadata through a stable private source-point ID or equivalent table-backed
handle. Lowering emits explicit, non-removable observation points. The verifier
checks their references and ensures mandatory paths cannot bypass them.
Tree-walk and bytecode report through the same execution-control seam defined
for #617.

Current `@token.Loc` operands provide coordinates on selected instructions, but
they neither identify the owning source nor cover every required observation.
They are migration input, not the completed contract. #330 must establish the
observation-coverage matrix before #635 can turn coverage into a precise
invariant.

### 2.6 Effects come from the closed instruction set

Effect information is derived by exhaustive matching on the private instruction
enum; instructions do not carry unchecked effect annotations. The derivation
keeps unlike effects separate:

- **May throw:** fallible runtime paths such as binary/unary operations, calls,
  construction, property operations, name/environment access, direct eval,
  destructuring, spread, regular-expression creation, and explicit `Throw`.
- **May call guest code:** calls, construction, direct eval, property/internal
  methods, iteration, and `ToPrimitive`-class conversions. Creating a function
  value alone does not call guest code.
- **Frame read/write:** operand-stack and local-slot mechanics, private to the
  executor.
- **Environment/heap read/write:** runtime-owned environments, objects,
  properties, and iterators.
- **May enqueue:** runtime operations that can enqueue host jobs; host policy
  remains outside bytecode.
- **Observation barrier:** the source-linked points defined above.

The verifier consumes these derived effects when checking observation and
control-flow requirements. Classification follows the runtime operation reached
by an instruction, not the opcode name alone.

### 2.7 References, direct eval, and dynamic scope

Property assignment preserves the object/key/value reference through
`ReadPropertyForAssign`, `ReadComputedForAssign`, `SetProperty`, `SetComputed`,
`DropPropertyAssignReference`, and `DropComputedAssignReference`. Method calls
preserve the receiver through `PreparePropertyCall`, `PrepareComputedCall`,
`CallWithReceiver`, and `CallSpreadWithReceiver`. These are frame conventions;
the runtime operation still owns assignment and call semantics.

`CallDirectEval` passes caller strictness and environment to
`interp.call_direct_eval_or_shadowed`. Direct eval must observe the caller's
lexical environment and dynamic-scope state, including whether `eval` is
shadowed. It therefore forces conservative environment planning. `with` remains
unsupported. Future dynamic-scope support must keep affected names in
runtime-owned environment slots. The current `needs_own_env` flag is evidence
from lowering, not a complete prepared dynamic-scope plan.

### 2.8 Abrupt completion and `finally`

Flat bytecode must represent handler/finalizer metadata and save or resume an
abrupt completion. Normal, return, break, continue, throw, and runtime-abrupt
completion all enter a pending `finally`. Normal completion of `finally`
resumes the saved completion; an abrupt `finally` replaces it.

Bytecode does not support try/catch/finally today; lowering selects the private
pre-execution unsupported outcome for it. The contract claims representational
capability, not current syntax support. Stage 11 and #385 own the
representation work. #630 establishes tree-walker continuation behavior, while
#631 integrates bytecode with the dispatcher.

### 2.9 Dispatcher and fallback boundary

The target engine dispatcher owns mixed tree/bytecode/native activations.
Current bytecode instead re-enters `interp.call_value` and
`interp.construct_value` synchronously. Under #631, the VM returns a request and
continuation, the dispatcher schedules the activation, and the private frame
resumes exactly once with its result or abrupt completion.

Fallback to tree-walk is only a pre-execution lowering or verification outcome.
Once bytecode execution starts, no instruction failure, unsupported condition,
or continuation failure may switch executors, whether or not an observable
effect has occurred. The same operation must never execute once in bytecode and
again in tree-walk.

---

## 3. Worked scenarios

The representation choice survives only if evaluation order, re-entry, abrupt
completion, dynamic scope, and observation keep the same owners.

### Local loop

```javascript
var sum = 0;
for (var i = 0; i < n; i++) { sum = sum + i; }
```

Stack bytecode uses `LoadLocal`, `BinaryOp`, `StoreLocal`, `UpdateLocal`, and a
conditional back-edge. The verifier checks stack shape and jump targets;
runtime operations own addition. A shared ExecutionIR would add one translation
before the same stack sequence. Registers would change storage shape but not
semantics, and no measurement requires that rewrite.

### Method call and receiver

```javascript
obj.m(arg)
```

Lowering evaluates `obj`, then `PreparePropertyCall("m", loc)` reads the member
and preserves `[obj, callee]`. Arguments follow in source order;
`CallWithReceiver(1, loc)` consumes receiver, callee, and arguments. A shared IR
would have to preserve the same order through another translation. Registers
could preserve the receiver elsewhere, but would not change the runtime call
operation that owns the semantics.

### Getter or Proxy re-entry

```javascript
return 1 + o.x;
```

Runtime property operations own getter and Proxy behavior. Today
`GetProperty("x", loc)` enters that path synchronously. Under #631, bytecode
yields a property-result continuation, the dispatcher runs the getter or trap,
and the resumed value reaches `BinaryOp(Add, loc)` exactly once. ExecutionIR and
register bytecode would still need the same suspension and dispatcher; neither
moves the semantic boundary.

### Abrupt completion through `finally`

```javascript
try { throw new Error("x"); } finally { cleanup(); }
```

Verified handler/finalizer metadata routes the saved throw through `cleanup()`.
Bytecode owns the control transfer, runtime operations own JavaScript completion
semantics, and the dispatcher schedules guest calls reached from the finalizer.
A shared IR would encode that metadata only to translate it again for its sole
stack consumer. Registers would change frame storage, not completion ownership.

### Direct eval

```javascript
function f(x) { return eval(x); }
```

`CallDirectEval(loc)` passes the caller environment, strictness, and arguments to
`interp.call_direct_eval_or_shadowed`, which also decides whether `eval` is
shadowed. `needs_own_env` currently retains the required environment. Neither a
shared IR nor registers remove this runtime obligation.

### Observation and source identity

An executable statement or expression that requires observation must cross an
explicit point carrying a stable source reference. The verifier checks reference
validity and path coverage; `@token.Loc` alone is insufficient. A shared IR
would add another place where those points could be lost or reordered. Register
shape does not change the requirement.

---

## 4. Public surface and migration

The compiler entry points remain experimental. `BytecodeProgram`,
`compile_script_to_bytecode`, `run_bytecode_script`, and
`BytecodeProgram::run` may change or disappear under the execution plan's
surface taxonomy. The verifier, unverified builder product, and verified
executable data remain private. Generated `.mbti` changes caused by tighter
boundaries are intentional but must still be reviewed.

The representation can be tightened vertically rather than through a big-bang
rewrite:

| Issue | Responsibility |
|---|---|
| #634 | Structured pre-execution lowering outcomes |
| #330 | Structured equivalence outcomes and observation coverage |
| #635 | Pure verifier and verified executable wrapper |
| #636 | Remove executable AST and source-body leakage |
| #638 | Replace direct `Binding` access with runtime-owned environment slots |
| #637 | Establish the executor-neutral function activation seam |
| #630 | Build the engine dispatcher and explicit continuations for tree-walk |
| #631 | Adapt bytecode mixed calls and re-entry to that dispatcher |
| #385 (after foundations) | Add verified bytecode handler/finalizer control-flow representation |
| Follow-up after #601 | Replace embedded `Value` constants with bytecode literals or recipes |

Issue #634 is the first vertical slice: it separates compiled, unsupported,
frontend/JavaScript diagnostic, and engine-defect outcomes without changing the
instruction representation. #330 may define observation coverage in parallel.
No syntax-breadth or performance work should precede the verifier and typed
outcomes. Every slice keeps bytecode/tree-walker equivalence tests for the
behavior it touches.

---

## 5. Revisit and stop conditions

Revisit this decision when a second concrete compiled backend exists, when an
isolated benchmark proves a stack-specific limit that cannot be removed within
the current representation, or when verifier/control-flow invariants require a
richer CFG than the closed instruction set can express. Runtime helper cost,
environment lookup, or dispatch overhead does not by itself justify replacing
the stack model.

Stop an implementation slice if the verifier must import JavaScript semantics,
constant materialization requires semantic changes in the same patch, AST
removal changes behavior without a tree-walker comparison test, or #631 can only
proceed by exposing private frame internals.

Stack bytecode remains sufficient only while structural verification, source
observation, and continuation control remain expressible without a second
executable language.

## Validation basis

This decision was checked against `compiler/bytecode_ir.mbt`,
`compiler/bytecode_lower.mbt`, `compiler/bytecode_vm.mbt`,
`compiler/closure_conversion.mbt`, `compiler/moon.pkg`, and
`interpreter/runtime/moon.pkg`; the architecture execution plan
([architecture-execution-plan-2026-06-12.md](../design/architecture-execution-plan-2026-06-12.md));
and the activation continuation contract
([engine-activation-continuation-contract.md](engine-activation-continuation-contract.md)).
