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

**Goal:** Identify and fix real O(bad) behavior after reproducing it in an
isolated benchmark.

**Steps:**

1. Identify current timeout files from fresh test262 artifacts.
2. Reduce one timeout to a microbenchmark.
3. Stop if the benchmark cannot reproduce the bottleneck.
4. Fix the measured path and keep the benchmark.

**Fixed (2026-07-03):**

- `String.prototype.repeat` with empty string + large count: added
  `if str.length() == 0 { return "" }` early return before the loop
  (11000ms → 0ms). Also added §21.1.3.13 max-length overflow guard for
  non-empty strings. Fixed 1 timeout file (2 modes).

- `[[SetPrototypeOf]]` cycle detection: `Object.setPrototypeOf(Object.prototype, ...)`
  and `Object.prototype.__proto__ = ...` had no cycle detection, allowing them
  to create prototype chain cycles that caused infinite loops in subsequent
  chain walks. Added `ordinary_set_prototype` helper in `prototype_ops.mbt` with
  spec-compliant §10.1.3 cycle detection. Applied to all 3 paths: `__proto__`
  setter, `Object.setPrototypeOf` static, `Reflect.setPrototypeOf` runtime.
  Fixed 3 timeout files (6 modes).

**Fixed (2026-07-03):**

- RegExp character class escape tests (7 files, 14 modes, pending CI
  validation): `^\S+$`, `^\s+$`, `^\d+$` and similar quantifier + character
  class shorthand patterns on large Unicode strings were timing out because
  `match_sequence_candidates` eagerly collected ALL quantified match states (up
  to ~2.2M entries) before trying any candidate. Added
  `is_simple_quantified_inner` + `quantified_match_count` fast-path in
  `match_sequence_candidates`: for quantified `Literal`/`Dot`/`CharClass` inner
  nodes, scan forward once to count max matches without allocating intermediate
  state arrays, then try the longest position first against the rest of the
  pattern. Early-break on first success (safe because these nodes advance
  exactly 1 char per match and never set captures). Verified manually: 2.1M-char
  `^\S+$` test completes (~17s, was timeout at 30s+). Does NOT fix unquantified
  single-char-class matches (`/\d/.test(large_str)`) — that bottleneck is in
  `regex_search`'s position-by-position loop and remains as a separate issue.

**Remaining (test-side workload, not engine bugs):**

- `decodeURI`/`decodeURIComponent`: Sputnik test with 4 nested loops (~1.3M
  iterations calling decodeURI each time).
- `Function.prototype.toString`: walks all intrinsic objects with O(n²)
  `visited.includes()` check.

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
- ~~Parameter TDZ pre-declaration: class constructors fixed in PR #481 (780ef66).~~
  ~~`call.mbt` and `generator.mbt` still skip destructuring-param BoundNames~~
  ~~and still blindly pre-declare the synthetic `"$rest"` for rest patterns.~~
  ~~Apply the same `walk_pattern_idents` pattern from construct.mbt.~~
- **Fixed 2026-07-03**: `call.mbt` and `generator.mbt` now use `walk_pattern_idents`
  for destructuring-param BoundNames in TDZ pre-declaration and only pre-declare
  `rest_param` for simple (non-destructuring) rest parameters. Verified: 2267 local
  tests, 372 function-dstr test262 tests, 35 language/destructuring/binding test262
  tests all pass (pre-existing assignment dstr failures unrelated).

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
