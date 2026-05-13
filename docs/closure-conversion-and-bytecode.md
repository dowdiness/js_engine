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
