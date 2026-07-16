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

- RegExp character class escape tests (all 7 timeout files resolved):
  - **Quantified fast-path** (PR #485): `^\S+$`, `^\s+$`, `^\d+$` — added
    `is_simple_quantified_inner` + `quantified_match_count` in
    `match_sequence_candidates`. For quantified `Literal`/`Dot`/`CharClass` inner
    nodes, scan forward once to count max matches without allocating intermediate
    state arrays, then try the longest position first against the rest of the
    pattern. Early-break on first success.
  - **Unquantified scan-forward** (PR #485): `/\d/`, `/\d/`, `/\S/` — added
    `has_first_char_bound` + `advance_to_candidate` helpers that skip
    non-matching positions in bulk. For patterns with a bounded first character
    (Literal, CharClass, Quantified with min>0), the search loop advances past
    positions that can never match, reducing 1.1M-position scans to 1 iteration
    when no match exists. Also applied to `regex_search_all`.
**Remaining (test-side workload, not engine bugs):**

- `decodeURI`/`decodeURIComponent`: Sputnik test with 4 nested loops (~1.3M
  iterations calling decodeURI each time).
- `Function.prototype.toString`: walks all intrinsic objects with O(n²)
  `visited.includes()` check.

## Adoption Stage 1 follow-up PRs

Keep these separate from the stable embedding documentation PR.

### External-consumer CI fixture

- Add a standalone MoonBit module under an integration-fixture directory that
  starts with no js_engine internals and imports only the root
  `dowdiness/js_engine` package.
- Point the fixture at the checkout under review rather than a published
  Mooncakes version, so pull-request CI validates the candidate source.
- Reproduce the documented persistent Rule Engine scenario using only
  `Engine`, `eval`, `call_json`, and MoonBit `Json`.
- Run the fixture on `native`, `js`, `wasm`, and `wasm-gc` in a dedicated CI
  matrix. Keep this checkout-under-review gate distinct from the release
  checklist's Mooncakes installation smoke test.
- Fail if the fixture directly imports `interpreter`, `interpreter/runtime`,
  parser, AST, or compiler packages.

### Embedding baselines

- In a separate benchmark PR, measure one-shot `run` and repeated persistent
  `Engine::call_json` scenarios with fixed source/data and recorded toolchain
  metadata.
- Treat the results as baselines only. Do not propose an optimization unless an
  isolated microbenchmark reproduces a concrete bottleneck.

## Feature projects

These are larger than one small cleanup PR; split them before implementation.
They belong to the parallel conformance quality stream described in
[ROADMAP.md](ROADMAP.md#continuing-quality-streams), not to the ordered adoption
stages.

### Async-generator destructuring in `for await`

**Source:** `scripts/test262_skip_metadata.json` — 146 path-specific exceptions
with rationale `async-generator destructuring in for-await-of` (plus one legacy
`star-iterable.js` spec-draft exception). There is no `async-iteration`
blanket skip; core `for await`, async iterators, and async generators ship in
PR #494 and follow-ups.

**Goal:** Reproduce one path-skipped `for-await-of` async-generator
destructuring file, read its Test262 `info` field, and land a narrow fix. Do
not claim full async-iteration conformance until these exceptions shrink from
measured CI runs.

### RegExp Unicode/property gaps

Known remaining RegExp issues include:

- Supplementary-plane `.` matching without `u`.
- RegExp flag getters called on plain objects.
- `flags` getter property coercion behavior.
- RegExp subclass `exec` / `match` / `replace` forwarding through the prototype
  chain.
- Duplicate named groups in disjoint alternatives (ES2024 behavior).

Work one cohort at a time and verify against the exact spec algorithm for that
RegExp method or accessor. Lookbehind `(?<=...)` / `(?<!...)` shipped in PR
#493; `regexp-lookbehind` is not in shared skip metadata.

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
- Full BigInt rollout.
- Broad RegExp Unicode property table strategy.
- Large architecture package splits without an invariant-pinning plan.
