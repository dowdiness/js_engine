# Closure Conversion and Bytecode Direction

This note records the current optimization decision for the interpreter
execution path.

## Decision

Closure conversion stays as an experimental, opt-in benchmark path. Do not keep
expanding it into a second complete JavaScript interpreter.

Future execution-speed work should move toward a compact bytecode or IR
interpreter. Closure analysis remains useful there, but the representation
should be explicit locals, environment slots, and captured variables rather
than one MoonBit closure per AST node.

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

The next optimization track should introduce a small bytecode or IR layer with
these constraints:

1. Keep `run` on the existing interpreter until bytecode has enough correctness
   coverage and benchmark evidence.
2. Reuse runtime helpers for JavaScript semantics instead of reimplementing
   property access, calls, construction, operators, descriptors, and errors in
   the compiler.
3. Represent execution state explicitly: instruction pointer, value stack or
   registers, locals, lexical environment slots, and captured upvalues.
4. Start with the closure-factory and pipeline-evaluate benchmark subset before
   broadening syntax.
5. Compare bytecode results against the existing interpreter in tests for every
   supported construct.

An initial opcode set should stay high-level enough to avoid duplicating spec
algorithms:

- constants and simple moves: load constant, load/store local, load/store
  lexical binding
- control flow: jump, conditional jump, return, throw
- expressions: unary, binary, ternary lowering
- object interaction: get property, set property, get computed, set computed
- calls: call, construct, spread argument expansion
- closures: create function, create arrow function, bind captured slots

The first milestone should compile the existing primary workload shape:
function declarations and expressions, calls, arrays, member access, assignments,
`for`/`while` loops, `return`, `break`, `continue`, and `throw`. New syntax
should be added only after the benchmark subset is stable.

## Guardrails

- Before designing a performance optimization, add or reuse a benchmark that
  reproduces the bottleneck.
- Keep the closure-conversion prototype behind its opt-in flag.
- Avoid expanding closure conversion unless a small patch is needed to keep the
  benchmark path honest.
- Prefer bytecode/IR work that removes dispatch overhead while preserving one
  semantic owner for JavaScript behavior.
