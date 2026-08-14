# Bytecode candidate preparation: responsibility and lifetime map

Issue #911 is a pure preparation seam. This map is based on
`3c7d030855ad9ccb68215e0834fd17d0c666ada5` and records the boundary that the
four implementation slices preserve.

## Preserved assumptions

1. Lowering, verification, and candidate selection stay deterministic compiler
   core operations; runtime effects stay in the imperative activation shell.
2. `BytecodeProgram` and `VerifiedBytecodeFunction` remain AST-free verified
   executable carriers; the candidate envelope is a separate compiler-owned
   value.
3. A selection is made before activation and is never changed after an
   executor frame or observable effect has started.

## Current (old) responsibility map

| Boundary | Current owner | Current value/lifetime | Gap exposed by #911 |
| --- | --- | --- | --- |
| Script parse | `@parser` / `Engine::eval` | AST statements live through `Interpreter::run`; persistent `Engine` retains resulting globals | No compiler-owned per-activation pair is retained by the stable path |
| Tree root activation | `Interpreter::run` and tree-walker runtime | `Array[@ast.Stmt]` is evaluated in the current interpreter/environment | No typed candidate outcome precedes the tree activation |
| Tree nested function | runtime `FuncData` / `FuncDataExt` created by tree evaluation | Function body AST and closure environment live in the JavaScript function value until it is collected | No corresponding verified candidate or identity is retained |
| Bytecode root creation | `build_script_bytecode` → `compile_bytecode_function` → `finalize_bytecode_program` | mutable `BytecodeUnverifiedProgram` becomes `BytecodeProgram` with `VerifiedBytecodeFunction` root | Any nested lowering rejection aborts the whole build |
| Bytecode nested creation | `BytecodeBuilder::add_function` at declaration/expression/method/arrow sites | child `BytecodeFunction` is indexed in parent and verified recursively | Child lowering cannot produce a typed local unsupported result |
| Bytecode activation choice | private `select_bytecode_function_activation` | scans one verified function only; no retained choice | Choice is not paired with tree body or carried through later calls |
| Bytecode callable creation | `make_bytecode_func`, named/method/arrow variants | creates `ExecutorCallableData` retaining `BytecodeExecutorCode` → verified function | Creation is already an activation/runtime boundary and is too late for pure preparation |
| First runtime-state boundary | `start_bytecode_frame` / `ExecutorCode::start` | creates `BytecodeFrame`, binds/hoists runtime environment state | Must not be reached by candidate preparation |
| Persistent later call | `Engine::eval` → global function binding → `Engine::call_json` → `Interpreter::call_value` | callable owns tree body or executor code and closure; `Engine` owns interpreter/realm/queues | Candidate lifetime must survive root preparation without creating either callable |

## Tree/bytecode creation and consumer map

`BytecodeBuilder::add_function` appends children in source encounter order and
captures the parent source-point owner, child index, and consumer form in
`BytecodeHeaderProvenance`. The current consumers are:

| Consumer form | Lowering site | Bytecode instruction | Tree counterpart |
| --- | --- | --- | --- |
| `DeclareFunctionConsumer(name)` | function declarations | `DeclareFunction` / `MakeFunction` during hoisting | `FuncData` with declaration body |
| `FunctionConsumer` | anonymous function expressions | `MakeFunction` | anonymous `FuncData` |
| `NamedFunctionConsumer(name)` | named function expressions | `MakeNamedFunction` | named `FuncData` with self-name binding |
| `MethodFunctionConsumer` | object method shorthand/accessor value | `MakeMethodFunction` | method `FuncData`, non-constructable, home object |
| `ComputedMethodFunctionConsumer` | computed object method | `MakeComputedMethodFunction` | method `FuncData`, computed-key consumer |
| `ArrowFunctionConsumer` | arrow expressions | `MakeArrowFunction` | `ArrowFunc`/`ArrowFuncExt` body with lexical receiver |

The compiler must retain this ordering and exact consumer fact for every child;
names alone are not an identity key. Nested children repeat the same relation
recursively.

## New responsibility/lifetime map

| Value | Owner | Contents | Lifetime / first effect |
| --- | --- | --- | --- |
| `CandidateProgram` | compiler preparation package | root candidate plus immutable compilation identity | returned to caller; no runtime state or callable is created |
| `CandidateFunction` | compiler preparation core | stable source identity, tree body/consumer metadata, optional verified bytecode, typed `CandidateSelection`, child candidates | retained by the candidate program through later activation planning |
| `CandidateSelection` | compiler instruction/lowering core | `UseBytecode` with eligibility or `UseTreeWalker` with typed `LoweringUnsupported` or `ActivationUnsupported` | pure value; consumed only before frame/callable creation |
| tree candidate payload | compiler core | copied AST body and immutable signature/consumer facts, not an `Environment` or `Value` | later materialization may create a tree callable; preparation itself has no effects |
| verified bytecode payload | compiler core | existing `VerifiedBytecodeFunction` only when finalization succeeds | later materialization may create executor code; preparation itself creates no frame |
| source identity | existing per-compilation `BytecodeSourceIdentity` | opaque `Ref[Unit]` compilation token, source unit/owner, parent owner, child index, consumer form | copied with the candidate; rejects foreign compilation and coordinated swaps |

The first runtime-state boundary remains `ExecutorCode::start`/
`start_bytecode_frame` (and the analogous tree callable activation). Candidate
preparation ends before `ExecutorCallableData`, `ExecutorCode`,
`BytecodeFrame`, `Environment`, `Realm`, queue, output, or JavaScript `Value`
creation.

## Identity proof and decision

The current `BytecodeSourceIdentity` is already sufficient for candidate
pairing. It combines a per-lowering opaque `program_identity` token with the
shared source unit, function-local source-point owner, parent owner, child
index, and consumer form. Existing verifier tests prove that:

- two equal-source compilations have distinct physical program tokens;
- a child transplanted from another compilation is rejected;
- same-name sibling source/identity swaps are rejected;
- coordinated parent/index/consumer provenance mutations are rejected.

Therefore #911 does **not** add `CandidateFunctionId`, a global registry, name
map, source hash, AST physical equality, or source-text matching. The candidate
envelope reuses and validates the existing identity facts rather than creating a
second semantic registry.

## Unsupported propagation characterization

Today `bytecode_reject` raises `BytecodeUnsupportedSignal` from whichever
`compile_bytecode_function` is active; `lower_script_to_bytecode` catches that
signal only around the complete root build/finalization. Consequently an
unsupported nested body rejects the whole script, even when the parent body is
otherwise eligible. Slice 1 adds a RED and a characterization test for this
behavior; later slices replace only nested propagation with function-local typed
outcomes. Parser, verifier, internal, and identity defects remain failures.

## Forbidden scope for #911

No `Engine` routing, virtual override/default change, public facade change,
runtime compiler import, new JavaScript operation family, post-start fallback,
replay, or executor/frame/callable materialization is part of this map or its
implementation.
