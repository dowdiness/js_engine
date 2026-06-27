# JS Engine Roadmap

This roadmap is for current direction only. Completed plans and stale planning
snapshots live in [archive/executed-roadmap-history.md](archive/executed-roadmap-history.md)
and the older [archive/phase-history.md](archive/phase-history.md).

## Current Status

**Test262** — CI run [28279305916](https://github.com/dowdiness/js_engine/actions/runs/28279305916)
on tip `39c6bc1` (main, 2026-06-27).

Each test file runs twice, once in strict mode and once in non-strict mode. The
two modes are reported separately because summing them would double-count files.

To refresh this block, run `make test262-report`; do not copy numbers from
other documentation. For release notes, use `make test262-report
ARGS="--format=changelog"`.

| Mode | Discovered | Skipped | Executed | Passed | Failed | Timeout/Err | Passed / Executed | Passed / Discovered |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| strict | 44,986 | 18,119 | 26,846 | 26,011 | 835 | 20 | **96.9%** | 57.8% |
| non-strict | 47,692 | 18,660 | 29,011 | 27,774 | 1,237 | 20 | **95.7%** | 58.2% |

ES2015 specifically: strict **97.7%** P/E (9,895 / 10,131; 160 skipped),
non-strict **97.5%** P/E (10,353 / 10,620; 159 skipped) — the roadmap 95%
ES2015 target is achieved.

CI regression baseline: `test262-baseline.json`. Minimums are 27,650 non-strict
passed and 25,800 strict passed, updated 2026-06-26. The checked-in report above
is +124 / +211 above those minimums.

**Unit tests**: run `moon test` for the current local count; this section only
tracks the checked-in Test262 snapshot.

### How to read these rates

Quote **both** denominators whenever you cite a test262 figure, and always say
which mode you mean.

| Column | What it means | Pitfall |
|---|---|---|
| **Passed / Executed** | The headline rate engines usually quote. Numerator and denominator both exclude skipped files. | Rises mechanically when more tests get skipped, so it is not a reliability signal on its own. A feature whose tests are 100% skipped contributes 0 to this ratio. |
| **Passed / Discovered** | Broader spec-coverage figure. Skipped files count as un-passed, so it only moves when the engine itself improves. | Falls when the test262 suite adds new-edition tests faster than we implement them, even if the engine is unchanged. |

Skips dominate the gap: class-private fields/methods, async iteration, Temporal,
BigInt, RegExp Unicode properties, and related feature buckets. Implementing one
of these narrows the gap between the two rates — and can briefly lower Passed /
Executed as previously skipped tests start executing and failing.

**Do not sum strict and non-strict figures.** Each file is run in both modes, so
adding them double-counts the underlying test files. Report per-mode or not at
all. See [TEST262.md](TEST262.md#output-format) for the runner-level definition
and [supported-features.md](supported-features.md) for per-category pass rates,
Annex B legacy features, and not-yet-implemented features.

---

## Active Roadmap

### 1. Keep conformance data fresh

Before changing release notes, planning targets, or public claims, regenerate the
Test262 block from CI artifacts with `make test262-report`. Do not hand-edit the
numbers. If a release is being cut, use `make test262-report
ARGS="--format=changelog"` for the changelog block.

### 2. Close large skipped-feature buckets

These are the main drivers of the gap between Passed / Executed and Passed /
Discovered:

| Feature bucket | Why it matters | Current direction |
|----------------|----------------|-------------------|
| Class private fields/methods | Large skipped class-private suite; required for modern class semantics. | Add `#name` parsing, private-name lexical resolution, per-class brands, brand checks, and private storage for fields/methods/accessors/static members. |
| Async iteration | Large skipped async-iteration suite; builds on existing async/await and iterator support. | Implement async iterator protocol, `for await`, async generator interactions, and harness-safe scheduling semantics. |
| RegExp lookbehind and Unicode property escapes | High-impact RegExp skips and failures. | Lookbehind requires reverse matching from the current position; Unicode properties require a data-table strategy. |
| BigInt | Broad modern-JS feature bucket. | Requires value representation, literal parsing, arithmetic/comparison/coercion rules, typed-array/DataView interactions, and skip-list rollout. |
| Temporal | Large skipped suite but high implementation cost. | Treat as a later feature unless a narrower compatibility target emerges. |

### 3. Reduce distributed failures

No single small fix is expected to unlock hundreds of remaining executed tests.
Use the runner to drill into current failure clusters, then land narrow,
spec-anchored fixes with targeted verification. Prefer test262 `info` fields and
spec algorithms over analogy with sibling built-ins.

Useful workflow:

```bash
make test262-filter ARGS="--filter <path-or-category> --summary"
make test262-report
```

### 4. Tighten architecture boundaries as optimization paths grow

Mutable realm-state ownership is now a maintenance invariant, not the active
redesign pressure: the architecture-state audit inventory is empty
(`scripts/architecture_state_classified_mutable_state.json` is `{}`). Keep that
gate green, but focus new architecture work on boundary clarity between the
runtime semantic owner, stdlib bootstrap, static-semantic preparation, and
compiler/bytecode experiments. The current design context is in
[architecture-redesign-2026-06-12.md](design/architecture-redesign-2026-06-12.md)
and [architecture-execution-plan-2026-06-12.md](design/architecture-execution-plan-2026-06-12.md).

Completed realm-state, representation-access, and dispatcher stages are archived
in [archive/executed-roadmap-history.md](archive/executed-roadmap-history.md#completed-structural-refactoring-stages).

### 5. Keep bytecode optimization disciplined

Closure conversion and the opt-in bytecode prototype are benchmark paths, not a
second semantic interpreter. Keep JavaScript semantics centralized in runtime
helpers and leave default `run` on the tree-walking interpreter unless a
microbenchmark demonstrates the bottleneck. See
[closure-conversion-and-bytecode.md](design/closure-conversion-and-bytecode.md).

### 6. Maintain JavaScript target viability

The engine builds with MoonBit's JS target and runs on Node.js:

```bash
moon build --target js
node ./_build/js/debug/build/cmd/main/main.js 'console.log(1 + 2)'
# => 3
```

Future JS-target work:

- Re-verify the JS-target unit-test count after recent unit-test growth.
- Package an npm distribution only after deciding ESM/CJS output and sandboxing boundaries.
- Explore a browser playground once filesystem assumptions are isolated.
- Treat self-interpretation as long-term research; it depends on higher support for the JavaScript emitted by MoonBit.

For historical JS-target analysis, see [SELF_HOST_JS_RESEARCH.md](design/SELF_HOST_JS_RESEARCH.md).

---

## History

- [archive/executed-roadmap-history.md](archive/executed-roadmap-history.md) — completed roadmap plans, stale planning snapshots, and executed structural stages moved out of this file.
- [archive/phase-history.md](archive/phase-history.md) — older detailed implementation notes for completed phases.
- [archive/](archive/) — completed or superseded design documents.

For design principles, value model, control flow, and host integration, see
[architecture.md](design/architecture.md).
