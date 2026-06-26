# Agent Task Queue

Active, AI-sized follow-up tasks for `js_engine`. Keep this file focused on
unresolved work. Completed plans and historical investigation notes live in
[archive/agent-todo-history.md](archive/agent-todo-history.md).

Before starting a task:

1. Verify the issue still reproduces against current `main`.
2. Read the relevant test262 `info` field and spec algorithm.
3. Land narrow fixes with targeted tests before widening scope.
4. For performance work, write a microbenchmark that reproduces the bottleneck
   before designing an optimization.

---

## High-priority conformance tasks

### Algorithmic timeouts

**Required skill:** `moonbit-perf-investigation`.

**Goal:** Identify and fix real O(bad) behavior only after reproducing it in an
isolated benchmark.

**Steps:**

1. Identify current timeout files from fresh test262 artifacts.
2. Reduce one timeout to a microbenchmark.
3. Stop if the benchmark cannot reproduce the bottleneck.
4. Fix the measured path and keep the benchmark.

---

## Feature projects

These are larger than one small cleanup PR; split them before implementation.
See [ROADMAP.md](ROADMAP.md#active-roadmap) for the broader feature-bucket view.

### `for await` / async iteration

**Feature flag:** `async-iteration` in shared skip metadata.

**Current state:** `for await (const v of iterable)` still needs parser and
runtime support.

**Likely slices:**

- Parser/AST support for `for await`.
- Async iterator protocol lookup (`Symbol.asyncIterator`, fallback policy, and
  `next()` Promise handling).
- Interpreter execution semantics and abrupt-completion cleanup.
- Async generator interactions, if needed by the chosen test262 slice.

### RegExp lookbehind assertions

**Feature flag:** `regexp-lookbehind`.

**Goal:** Implement `(?<=...)` and `(?<!...)` without regressing existing
lookahead, capture, and replacement semantics.

**Notes:** Requires backward matching from the current position; do not model it
as simple lookahead reuse without checking capture ordering and zero-width edge
cases.

### RegExp Unicode/property gaps

Known remaining RegExp issues include:

- Supplementary-plane `.` matching without `u`.
- RegExp flag getters called on plain objects.
- `flags` getter property coercion behavior.
- RegExp subclass `exec` / `match` / `replace` forwarding through the prototype
  chain.
- Duplicate named groups in disjoint alternatives (ES2024 behavior).

Work one cohort at a time and verify against the exact spec algorithm for that
RegExp method or accessor.

### Dynamic constructor coercion gaps

Shared gaps across `Function`, `GeneratorFunction`, and `AsyncFunction`:

- Use ES `ToString` rather than MoonBit `.to_string()` for parameter/body
  coercion.
- Preserve left-to-right coercion order: parameters first, body last.
- Check constructor `[[Prototype]]` inheritance for Generator/AsyncFunction
  constructors.
- Ensure engine errors converted to JS values get the correct prototype chain.

### Class-private fields/methods

Large skipped-feature bucket. Split before implementation:

- `#name` parsing for fields, methods, accessors, static variants.
- Lexical private-name resolution.
- Per-class brands and brand checks.
- Private field/method/accessor storage and inheritance behavior.

### BigInt

Large skipped-feature bucket. Requires design before implementation:

- Value representation and literal parsing.
- Arithmetic/comparison/coercion semantics.
- Interactions with typed arrays/DataView and built-ins.
- Skip-list rollout strategy.

---

## Architecture and refactoring tasks

### Proxy internal operation forwarding

Remaining known proxy-forwarding gaps:

- `create_list_from_array_like` bypasses Proxy traps by reading storage directly.
- `unwrap_proxy_target` fails for non-Object proxy targets.

Verify current failures first; several older Proxy items have already shipped.

### Module instantiation-phase support

Sibling fixture resolution is fixed, but self-import and cyclic module tests need
ES module instantiation semantics: pre-bind exports before evaluation. Treat this
as engine work, not a test262 runner gap.

### §10.2.11 parameter/body environment divergences

Remaining known function-environment gaps:

- The engine collapses spec `env → varEnv → lexEnv` into fewer runtime envs in
  some parameter-default cases.
- Parameter TDZ pre-declaration is incomplete for forward references in defaults.

Keep fixes narrow; these interact with `arguments`, rest/destructuring params,
class constructors, generators, and async paths.

### PropertyDescriptor typestate builder exploration

**Status:** exploratory, needs a short design note before code.

Prototype a small builder that makes data descriptors and accessor descriptors
mutually exclusive at compile time. Evaluate ergonomics at a few representative
call sites before deciding whether a full migration is worth it.

---

## Documentation and tooling follow-ups

### TypedArray historical-rate discrepancy

A past doc refresh exposed a large mismatch between older single-mode TypedArray
figures and newer per-mode reports. Before citing old TypedArray rates, either:

- explain the methodology/skip-list difference, or
- rerun a current TypedArray filter and update the doc from current data.

### Per-edition supported-features tables

`docs/supported-features.md` still depends on classifier output quality. If the
edition tables lose ES2016–ES2024 granularity, inspect the classifier map and
formatter before refreshing docs.

---

## Deferred / large projects

These are real work but not good default one-session tasks:

- Temporal.
- Full class-private rollout.
- Full BigInt rollout.
- Broad RegExp Unicode property table strategy.
- Large architecture package splits without an invariant-pinning plan.
