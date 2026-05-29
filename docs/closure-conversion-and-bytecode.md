# Closure Conversion and Bytecode Direction

This note records the current optimization decision for the interpreter
execution path.

## Decision

Closure conversion stays as an experimental, opt-in benchmark path. Do not keep
expanding it into a second complete JavaScript interpreter.

Execution-speed work now has an initial compact, opt-in bytecode prototype.
Future broadening should continue in that direction. Closure analysis remains
useful there, but the representation should be explicit locals, environment
slots, and captured variables rather than one MoonBit closure per AST node.

## Current Closure-Conversion Role

The closure-conversion prototype is useful because it measures a real source of
overhead: repeatedly matching AST nodes while evaluating hot code. It currently
has public opt-in entry points through `run_compiled` and the
`--closure-conversion` CLI flag, and benchmark coverage for the primary
comparison workloads.

Primary metrics:

- `pipeline/exec/evaluate`
- `pipeline/closure_conversion/evaluate`
- `baseline/exec/closure_factory`
- `baseline/closure_conversion/closure_factory`

Use fresh benchmark output for numbers. Do not copy timing figures from this
document into release notes or planning docs; timings vary by backend,
hardware, and local noise.

## Why Not Expand It Broadly

The prototype has already needed special handling for semantics that are
central to JavaScript correctness: direct eval scope, proxy behavior,
strict-function validation, constructor calls, and host output. Continuing to
add syntax would duplicate more behavior from the tree-walking interpreter.

That duplication is the main risk. Every duplicated semantic path needs its own
tests, review, and future maintenance. The project gets more long-term value
from keeping semantics centralized and lowering execution overhead below that
boundary.

## External Engine Research

The survey did not find production JavaScript engines using "compile each AST
node into a host-language closure" as the main interpreter architecture. The
common production pattern is bytecode or a compact internal representation, with
closure variables represented explicitly as locals, registers, slots, upvalues,
or environment records.

Observed designs:

| Engine | Relevant design | Lesson for this repo |
|---|---|---|
| [QuickJS](https://bellard.org/quickjs/quickjs.html#Bytecode) | Compiles directly to stack bytecode, runs bytecode optimization passes, computes max stack size at compile time, and optimizes closure-variable access. | A compact bytecode can remove AST dispatch and still treat closure access as a first-class runtime concern. |
| [Moddable XS](https://www.moddable.com/documentation/xs/XS%20Scopes) | Scopes identifiers so variables can be accessed by index, and creates closures with only the variables that enclosed functions need. Direct `eval` and `with` force more conservative lookup bytecodes. | This is the closest match to the closure-conversion goal: do closure analysis, but lower it into indexed slots and bytecode rather than host closures. |
| [Hermes](https://engineering.fb.com/2019/07/12/android/hermes/) | Uses ahead-of-time bytecode precompilation for startup, memory, and bundle-size goals; explicitly chose no JIT for its original mobile workload. | A non-JIT engine can still justify a compiler and bytecode VM when startup and memory matter. |
| [JerryScript](https://jerryscript.net/internals/) | Parser translates source directly into bytecode without building an AST; a VM interprets the prepared bytecode. | Very small engines still choose bytecode because it is compact and keeps execution state explicit. |
| [Duktape](https://wiki.duktape.org/compiler.html) | Compiles to bytecode, constants, metadata, and function templates. Function templates are instantiated into closures with lexical environments. It also maps many function-local identifiers to registers when dynamic constructs permit it. | Direct `eval`, `with`, catch bindings, and closure capture are the hard parts. The compiler must preserve slow paths for dynamic scope cases. |
| [V8 Ignition](https://v8.dev/blog/ignition-interpreter) | V8 compiles functions to concise register bytecode and executes that bytecode in an interpreter. V8 also has JIT tiers, but Ignition itself is relevant as a bytecode-interpreter design. | Even a large JIT engine benefits from bytecode as the baseline representation; bytecode can reduce memory and simplify pipeline boundaries. |

The shared conclusion is not "closure analysis is useless." It is the opposite:
closure information is valuable when it informs a compact execution
representation. The part to avoid is making every AST node become a MoonBit
closure with duplicated JavaScript semantics.

## Implementation Lessons From This Prototype

The prototype taught us where the performance opportunity is and where the
maintenance risk starts.

Useful findings:

- AST dispatch overhead is measurable on the closure-heavy benchmark path.
- The primary metrics now make before/after comparisons reproducible.
- Function bodies, calls, property access, assignments, constructor calls, and
  loop control can be compiled enough to exercise realistic hot paths.
- `run_compiled` and `--closure-conversion` give an opt-in surface for
  experiments without changing the default interpreter.

Correctness traps encountered:

- Direct `eval` cannot be lowered as an ordinary call; it needs caller
  environment and strictness.
- `instanceof` must preserve Proxy and `@@hasInstance` behavior.
- Function expressions with a strict directive prologue must validate
  signatures when the expression evaluates.
- Constructable functions need prototype wiring, method-shorthand must remain
  non-constructable, and constructor returns must distinguish object-like and
  primitive values.
- The current host `console.log` behavior is a tree-walker special case, not an
  ordinary global binding.
- JavaScript `throw` uses the catchable error channel, while `return`, `break`,
  and `continue` use runtime signals. Compiled execution must preserve that
  split.
- Script execution needs the runtime envelope for static early errors, hoisting,
  current-interpreter setup, and JavaScript error wrapping.

These are all solvable individually, but solving them inside closure conversion
duplicates more of the interpreter. Bytecode should instead route through shared
runtime helpers and keep one semantic owner for each JavaScript behavior.

## Bytecode / IR Direction

An initial opt-in stack-bytecode prototype shipped in `50bcb94`. It does not
change `run`; ordinary library and CLI execution still use the tree-walking
interpreter. The prototype is entered explicitly through
`compile_script_to_bytecode`, `run_bytecode_script`, or `BytecodeProgram::run`,
and benchmark coverage includes the closure-factory and pipeline-evaluate
bytecode rows.

The prototype's job is to reduce AST dispatch on the primary workload shape
without creating a second semantic owner. It routes script setup and core
JavaScript operations through runtime helpers: static early errors and hoisting
use the compiled-script runtime envelope; name lookup, assignment, update,
binary operations, array creation, property/computed lookup, calls, function
naming/signature validation, and JavaScript exception raising delegate back to
runtime code.

Continue the bytecode/IR track with these constraints:

1. Keep `run` on the existing interpreter until bytecode has enough correctness
   coverage and benchmark evidence.
2. Reuse runtime helpers for JavaScript semantics instead of reimplementing
   property access, calls, construction, operators, descriptors, and errors in
   the compiler.
3. Represent execution state explicitly: instruction pointer, value stack or
   registers, locals, lexical environment slots, and captured upvalues.
4. Keep the closure-factory and pipeline-evaluate benchmark subset stable before
   broadening syntax.
5. Compare bytecode results against the existing interpreter in tests for every
   supported construct.
6. Reject unsupported semantics explicitly instead of silently changing behavior.

The current high-level opcode surface covers:

- constants and simple moves: load constant/`undefined`/`this`, load/store
  name, load/store function-local slot, define binding
- completion and control flow: set completion, pop, jump, conditional jump,
  return, throw
- expressions: supported eager binary operations including `in` and
  `instanceof`, selected unary operations (`-`, `+`, `!`, `~`, `void`, and
  `typeof`), jump-lowered `&&`, `||`, `??`, ternary conditionals, comma
  expressions, template literals, regex literals, identifier update,
  anonymous function naming
- object interaction: array creation without holes/spread, simple object
  literals with static data properties, property get, computed get, and
  property/computed assignment through runtime setters
- calls and construction: ordinary calls, receiver-preserving
  property/computed calls, and non-spread `new` expressions
- closures: function declarations and anonymous function expressions backed by
  runtime compiled functions

The shipped milestone covers the primary workload shape: function declarations
and anonymous expressions, calls, non-spread construction, arrays,
member/computed access, assignments, `for`/`while` loops, `return`, and `throw`.
`break`, `continue`, spread, and broader syntax remain future work and should
land only with compare-against-tree-walker tests.

## Current Explicit Bytecode Rejections

The compiler currently raises an `InternalError` prefixed
`bytecode prototype unsupported:` for these cases:

- `block lexical declaration`
- `block function declaration`
- `block var declaration`
- `control-flow function declaration`
- `control-flow var declaration`
- `for lexical initializer`
- `statement kind`
- `for initializer`
- `spread argument`
- `arguments object`
- `delete operator`
- `named function expression`
- `array hole or spread element`
- `object literal accessor property`
- `object literal spread property`
- `object literal computed property`
- `object literal method property`
- `object literal __proto__ property`
- `object literal property key`
- `console member`
- `direct eval call`
- `expression kind`
- `rest parameter`
- `default or destructuring parameter`

Keep this list fail-fast. When broadening bytecode syntax, remove a rejection
only after adding tests that compare the bytecode path with the tree-walking
interpreter for the newly supported construct.

## Guardrails

- Before designing a performance optimization, add or reuse a benchmark that
  reproduces the bottleneck.
- Keep both closure conversion and bytecode behind opt-in entry points.
- Keep `run` on the tree-walking interpreter until bytecode has stronger
  correctness coverage and benchmark evidence.
- Avoid expanding closure conversion unless a small patch is needed to keep the
  benchmark path honest.
- Reuse runtime helpers; reject unsupported semantics explicitly.
- Do not broaden bytecode syntax without compare-against-tree-walker tests.
- Prefer bytecode/IR work that removes dispatch overhead while preserving one
  semantic owner for JavaScript behavior.
