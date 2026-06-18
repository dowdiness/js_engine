# Executed Roadmap History

> **Status:** ARCHIVED — historical roadmap material moved out of
> [../ROADMAP.md](../ROADMAP.md) on 2026-06-18 so the roadmap can stay focused
> on current direction. Do not use the counts below as current conformance data;
> regenerate current Test262 numbers with `make test262-report`.

This file preserves completed planning notes that used to live in the active
roadmap. Older phase-by-phase implementation notes are in
[phase-history.md](phase-history.md).

---

## Recent completed batches before the 2026-06-14 roadmap snapshot

The 2026-06-14 roadmap status block summarized PRs through #314, followed later
by the Stage 8-10 architecture and performance work. Key completed batches:

- PRs #116/#118: async/generator function `.length` conformance.
- PR #119: Annex B §B.3.3.3 eval-code conflict skip.
- PRs #120/#121: TypedArray ValidateTypedArray rollout.
- PR #122: Array iteration model (`array_index_lookup_result`).
- PR #123/#191: Array sort/reverse/copyWithin/fill hole lifecycle.
- PR #133–#152: Stage 2c RealmState ambient-state migration.
- PRs #157–#186: opt-in bytecode/IR prototype.
- PRs #194–#202: RegExp prototype triage (accessors, Symbol.replace/match/split/matchAll).
- PR #246: test262 runner ergonomics (task lists, slicing, sharding, resume).
- PRs #247–#263: stdlib builtin helper pilot and method-descriptor rollout.
- PRs #286/#290: MoonBit tooling promotion (Phase 3/4).
- PRs #291–#293: CI opts sharding 2×45min → 8×11min.
- PRs #298–#302: CI UX (progress bar, ETA, exit-code vocabulary, diff-only failures).
- PRs #217–#227: module graph live bindings and namespace semantics.
- PR #303: destructuring iterator protocol (empty-pattern GetIterator, lref-before-next ordering).
- PR #306: ES2016 fixes (Array.prototype.includes, exponentiation operator).
- PR #308: TDZ sloppy-mode SyntaxError and cover-grammar member target.
- PR #313: interpreter-context coercions in built-ins.
- PRs #335–#343: Stage 8 architecture — runtime ops for representation access.
- PRs #312/#314: architecture audit tooling (import boundary + representation access).

---

## Targeted verification history

- 2026-02-11: `language/block-scope` slice is 106/106 passing (39 skipped).
- 2026-02-12: `built-ins/Promise` slice is 599/599 passing (100%, 41 skipped). `language/block-scope` is 106/106 passing (100%, 39 skipped).
- 2026-02-13: `language/white-space` slice is 66/67 passing (98.5%, was 73.1%). Small compliance sweep completed. Proxy/Reflect implemented: Proxy 94.5% (257/272), Reflect 99.3% (152/153).
- 2026-04-23: Reserved-word follow-up passes both targeted strict and non-strict slices. `language/reserved-words` is 53 passed / 53 executed / 53 discovered. `language/future-reserved-words` is 85 passed / 85 executed / 85 discovered.

---

## Phase 16–24 completion notes

Detailed notes for earlier phases are in [phase-history.md](phase-history.md).

- **Phase 16 (2026-02-14)**: TypedArray/ArrayBuffer/DataView implemented. 9 typed array types, DataView getter/setter methods, ArrayBuffer slice/detach. 79 new unit tests. Full test262 re-run: +2,142 tests passing (20,870 → 23,012), pass rate 82.7% → 83.7%.
- **Phase 17 (2026-02-14)**: TypedArray prototype chain conformance. Created `%TypedArray%` intrinsic constructor and per-type constructor `[[Prototype]]` chains. TypedArray 55.1% → 92.8% (+293), TypedArrayConstructors 86.1% → 94.4% (+30).
- **Phase 18 (2026-02-14)**: Boxed primitives (`new String/Number/Boolean`), `Object()` ToObject wrapping, ToPrimitive coercion in `loose_equal`, and TypedArray constructor name fix. Estimated +162 targeted tests.
- **Phase 19 (2026-02-15)**: Symbol/TypedArray prototype fixes and full re-run verification. Registered `[[SymbolPrototype]]` and `[[FunctionPrototype]]`; Reflect reached 100%. Full test262 re-run: +525 tests passing (23,012 → 23,537), pass rate 83.7% → 85.6%.
- **Phase 20 (2026-02-15)**: WeakMap/WeakSet, iterator prototypes, RegExp improvements. WeakMap and WeakSet reached 100%; Map reached 100%; shared iterator prototypes and major RegExp features landed. Full test262 re-run: +223 tests passing (23,537 → 23,760), pass rate 85.6% → 86.1%.
- **Phase 20 review fixes (2026-02-15)**: Review fixes for regex, WeakMap/WeakSet, and array properties. Full test262 re-run: +89 tests passing (23,760 → 23,849), pass rate 86.1% → 86.4%.
- **Phase 21 (2026-02-16)**: Annex B `get_string_method` gating and conformance fixes. Full test262 re-run: +26 tests passing (23,849 → 23,875), pass rate 86.4% → 86.5%.
- **Phase 22 (2026-02-17)**: Tier 1+2 conformance improvements: string escape sequences, `%ThrowTypeError%`, `with`, Annex B block-level function hoisting, RegExp symbol methods, import syntax validation. Full test262 re-run: +587 tests passing (23,875 → 24,462), pass rate 86.5% → 88.1%.
- **Phase 23 (2026-02-18)**: Tier 4 polish and edge cases: globalThis properties, full LineTerminator support, directive prologue fix, GeneratorFunction constructor, generator prototype chain fix, eval completion values, ASI restricted productions, Unicode whitespace rejection in identifier escapes. Full test262 re-run: +57 tests passing (24,462 → 24,519), pass rate 88.1% → 88.8%.
- **Pre-Stage-C TypeError bundle (2026-04-21, PRs #70 + #71)**: Four narrow TypeError gates from the missing-TypeError cluster and method-shorthand non-constructor support. Net +22 test262, 0 regressions, +38 unit tests.
- **Phase 24 (2026-02-22)**: Compiler warning cleanup and strict-mode test262 expansion. Fixed all 34 MoonBit compiler warnings. Test runner now tests both strict and non-strict modes separately (92,291 tasks from 48,157 files). Full test262 re-run: 84.4% pass rate (44,933/53,208 tasks). Build produced 0 warnings.

### Phase summary table

| Phase | Tests | Cumulative | Key changes |
|-------|-------|------------|-------------|
| 1-5 | — | 6,351 | Core language, classes, promises, iterators, skip list cleanup |
| 6A-6G | +~2,350 | ~8,500 | Parser fixes, prototype chains, destructuring, tagged templates |
| 6H | +1,202 | 9,489 | Error prototype chain fix |
| 6I-6L | +56 | 9,545 | Leading decimals, canonical indices, PR review fixes |
| 7A | — | 9,545 | Full accessor descriptor support |
| 7B | +1,047 | 10,592 | Unicode escapes in identifiers, strings, template literals |
| 7C-E | +65 | 10,657 | Bare for-of/for-in, get/set as identifiers, Math function lengths |
| 7F | +202 | 10,864 | ES Modules |
| 8 | +452 | 11,316 | ES6 generators |
| 8B | +17 | 11,333 | Test262 harness functions |
| 8C | +345 | 11,678 | Date object |
| JS Target | — | — | JS backend support, Error toString fix, backend-specific argv handling |
| 9 | +7,439 | 19,117 | Error diagnostics, generator methods, destructuring defaults, parser cleanup |
| 10 | — | — | Object descriptor compliance |
| 11 | +603 | 19,720 | eval() semantics |
| 12 | +3 | 19,723 | Strict-mode prerequisite bundle |
| 13 | +1,080 | 20,803 | Promise species constructor and sloppy-mode fixes |
| 14 | +67 | 20,870 | Small compliance sweep |
| 15 | +877 | 21,747 | Proxy/Reflect |
| 16 | +2,142 | 23,012 | TypedArray/ArrayBuffer/DataView |
| 17 | +323 | ~23,335 | TypedArray prototype chain |
| 18 | +162 | ~23,500 | Boxed primitives |
| 19 | +525 | 23,537 | Symbol/TypedArray prototype fixes |
| 20 | +223 | 23,760 | WeakMap/WeakSet, iterator prototypes, RegExp improvements |
| 20-fix | +89 | 23,849 | Regex, WeakMap/WeakSet, array-property review fixes |
| 21 | +26 | 23,875 | Annex B string-method gating |
| 22 | +587 | 24,462 | `with`, Annex B hoisting, RegExp symbol methods, string escapes |
| 23 | +57 | 24,519 | Tier 4 polish |
| 24 | — | 44,933† | Strict + non-strict runner expansion, warning cleanup |

† Phase 24 changed methodology: runner now tests strict and non-strict modes separately, so its count is not directly comparable to older file-level phase counts.

---

## Historical path-to-90 snapshot

The following planning numbers were calculated from CI run 24885185424
(2026-04-24, tip `b225cda`). They are retained as historical context only and
are not the current headline status. Refresh with `make test262-report` before
using any number in planning or release material.

At that snapshot, reaching 90% passed/executed required roughly 579 more strict
passes and 1,081 more non-strict passes. Reaching 90% passed/discovered also
required unskipping large feature buckets such as class-private and RegExp
Unicode property escapes.

### Projected impact under pre-Phase-24 methodology

| Milestone | Tests fixed | Cumulative | Rate (file-level, pre-P24) |
|-----------|-------------|------------|----------------------------|
| Pre-P22 baseline | — | 23,875 | 86.5% |
| Tier 1+2 (P22) | +587 | 24,462 | 88.1% |
| Tier 4 (P23) | +57 | 24,519 | 88.8% |
| Tier 1d + regex replace (2026-04-16) | ~+60 | ~24,579 | ~89.0% |
| Proxy trap invariants (2026-04-16) | +136 | ~24,715 | ~89.5% |
| Remaining Tier 4 (4g modules) | ~50-100 | ~24,815 | ~89.9% |

---

## Stale failure-clustering snapshot from 2026-04-16

> **Stale warning:** This table pre-dates PRs #64-#75 and the fixture-resolver
> fix. Keep it only as a record of how failures were once clustered.

| Category | Pass | Fail | Rate | Top failure causes |
|----------|------|------|------|--------------------|
| `built-ins/Array` | 4,664 | 1,157 | 80.1% | Species, sparse arrays, iteration model |
| `language/expressions` | ~10,810 | ~1,018 | ~91.4% | Scattered; class-private skipped |
| `language/statements` | ~7,615 | ~647 | ~89.8% | Scattered; class-private skipped |
| `built-ins/RegExp` | ~1,148 | ~628 | ~64.6% | No lookbehind, subclass exec forwarding |
| `built-ins/Proxy` | 366 | 170 | 68.3% | Improved 2026-04-16; remaining set receiver, setPrototypeOf, GOPD cases |
| `built-ins/Object` | ~5,658 | ~1,092 | ~83.8% | Descriptor edge cases |
| `built-ins/String` | ~2,405 | ~216 | ~91.6% | Improved 2026-04-16 |
| `built-ins/Function` | 608 | 206 | 74.7% | Constructor edge cases, prototype descriptors |
| `language/eval-code` | 283 | 169 | 62.6% | Strict scoping, var hoisting edge cases |
| `built-ins/RegExpStringIteratorPrototype` | 20 | 14 | 58.8% | Remaining needed lazy exec() |

---

## Completed and remaining feature-target history

| Feature | Historical status |
|---------|-------------------|
| TypedArray prototype chain | Done (Phase 17-19) |
| Boxed primitives | Done (Phase 18-19) |
| RegExp improvements | Named groups done (PR #47); symbol methods done (P22); lookbehind and Unicode property escapes remain current work |
| WeakMap/WeakSet | Done (Phase 20) |
| Class public fields | Done before 2026-04-16; feature flags removed |
| Class private fields/methods | Not done; remains current work |
| async/await | Done (PR #45); async iteration remains current work |
| RegExpStringIteratorPrototype | Mostly done by 2026-04-16 |
| Regex callback replace | Done 2026-04-16 |
| Date object | Done (8C+9) |
| eval() | Done (P5), with ongoing edge-case fixes |
| Proxy/Reflect | Main implementation done (Phase 15-19), later invariant and dispatcher fixes continued |
| Promise improvements | Done (Phase 13) |
| TypedArray/ArrayBuffer/DataView | Done (Phase 16-19) |

---

## Completed structural refactoring stages

The active roadmap now points at the latest architecture direction. Completed
stages below are archived for continuity.

- **Stage A — PropertyBag extraction**: done 2026-04-17, PR #49. Consolidated `properties / symbol_properties / descriptors / symbol_descriptors` into `PropertyBag` across object variants.
- **Stage B.1 — `[[Set]]` dispatcher**: done in PR #69. Proxy/Reflect `[[Set]]` threads receivers through prototype walks and lands writes per ES §10.1.9.2.
- **Stage B.2 — `[[GetOwnProperty]]` / `[[DefineOwnProperty]]` dispatchers**: done in PR #72. Descriptor operations route through shared dispatchers and centralize Proxy invariant checks.
- **Stage C — `ArrayData.bag`**: done 2026-04-23. Array named, symbol, length override, indexed-descriptor, and prototype override state moved into the embedded `PropertyBag`.
- **Stage B.3 — `[[HasProperty]]` dispatcher**: done 2026-04-23. `in`, `Reflect.has`, Proxy `has`, proxy-in-prototype chains, array prototype overrides, callable `Function.prototype` fallback, and `with` binding lookup share the key-aware HasProperty path.
- **Post-B.3 language follow-up — strict reserved early errors**: done 2026-04-23. Strict reserved IdentifierReference, binding, and assignment-target uses are rejected by AST early errors, including unreachable branches.
