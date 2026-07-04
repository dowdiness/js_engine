# js_engine — JavaScript interpreter in MoonBit

Conventions and tooling guide for humans and AI agents working on this repo. `CLAUDE.md` is a symlink to this file.

## Repository Overview

This module is a MoonBit JavaScript interpreter. The root package `@js_engine` is the user-facing facade. Internal layers include `token`, `errors`, `ast`, `lexer`, `parser`, `interpreter`, `interpreter/runtime`, and `interpreter/stdlib`. Executable entry points live in `cmd/main`, Test262 tooling lives under `scripts/`, and benchmark code lives in `benchmarks`.

## Commands

```bash
moon check && moon test   # Lint + test
moon info && moon fmt     # Before committing
```

## Package Map

A `SessionStart` hook runs `scripts/package-overview.sh` to provide a live package map. Use `moon ide outline <path>` to explore any package's public API. `moon.mod` holds module dependencies.

## ES Spec Discipline

When implementing or debugging JavaScript built-in methods:

1. **Verify against the spec, not against sibling methods.** Methods that look structurally similar (e.g., `forEach` vs `find`) often have deliberately different semantics. Never assume one method's behavior applies to another.
2. **Read the spec algorithm for the specific method** before claiming it's buggy or before implementing a fix. The test262 `info` field quotes the exact spec steps — use it.
3. **Do not copy-paste implementations between methods.** Start from the spec algorithm for each. ES5 methods (`forEach`, `map`, `filter`) and ES6+ methods (`find`, `findIndex`, `includes`) differ on hole handling, return values, and species usage by design.

## Test262 Reporting Convention

When citing a test262 figure — in docs, commit messages, PR descriptions, release notes, or any conversation with the user — follow this rule:

1. **Always per-mode.** The runner tests each file twice (strict and non-strict) and the two outcomes differ. Say which mode, or report both. Never sum them — each file is counted once per mode, so a sum double-counts.
2. **Always both denominators.** Quote **Passed / Executed** *and* **Passed / Discovered** (or at minimum mention the skip count alongside the rate). A bare "85% on test262" hides that ~40% of discovered files are skipped for unimplemented features, and Passed / Executed rises mechanically as more features land in the skip list.
3. **Pull numbers from CI, not from doc prose.** Other documents' headline numbers drift; the authoritative source is the latest successful run of `.github/workflows/test262.yml`, with raw counts in the uploaded `test262-*-results.json` artifact.
4. **Label methodology on cross-version comparisons.** The runner switched from single-mode to per-mode in Phase 24 (2026-02-22). Pre-Phase-24 numbers (e.g. the v0.1.0 `39.4%`) are not directly comparable to current per-mode figures. When comparing, say so.
5. **Skip-list changes move both rates in opposite directions.** Implementing a previously-skipped feature grows the Executed denominator; until all its tests pass, Passed / Executed can drop even as Passed / Discovered rises. Expect and explain this.

See [docs/ROADMAP.md § How to read these rates](docs/ROADMAP.md#how-to-read-these-rates) for the reader-facing version, and [docs/RELEASING.md](docs/RELEASING.md) for the release checklist that enforces these rules at version-cut time.

**Tooling.** `make test262-report` (native `cmd/report_test262`) pulls numbers directly from a CI run's artifacts and emits a paste-ready block. Use `ARGS="--format=table"` for ROADMAP/README (default) or `ARGS="--format=changelog"` for CHANGELOG entries. Never hand-edit the generated numbers; if they look wrong, fix the upstream.

## Test262 Tool Boundaries

- The native MoonBit runner `cmd/test262_runner` (invoked by `make test262` / `test262-quick` / `test262-filter` and by CI) is authoritative for Test262 execution and applying skip decisions.
- `scripts/test262_skip_metadata.json` is the single edit point for shared skip metadata used by runner/analyzer tooling.
- `test262-analyze` (native `cmd/test262_analyze`, authoritative) is a non-authoritative metadata helper. It uses shared skip metadata but does not execute the engine, expand per-mode tasks, resolve fixtures, or observe runtime failures. Do not use its output as conformance data or as the skip-list source of truth.
- After editing shared skip metadata, run `make test262-validate-skips`. It detects dead or unknown metadata entries only; it does not run Test262 or produce conformance numbers.
- `make test262-report` (native `cmd/report_test262`) plus CI artifacts are authoritative for current conformance numbers.
- **Updating `test262-baseline.json`**: run `python3 scripts/set-baseline.py` after any batch of PRs that recovers more than ~100 tests. It reads `passed` counts from the latest successful *main-branch* CI run and subtracts a configurable buffer (default 100). Never copy numbers manually from a PR-branch CI run: PR branches can diverge from main before merging and produce outlier counts. Use `--dry-run` to preview changes, `--run-id` to target a specific run.
- **Verifying CI claims in compacted session summaries**: before investigating any test regression described in a compacted summary, read the raw step log directly — `gh run view <id> --log | grep "Report newly-failed"`. Session summaries can confuse the *Recovered* (newly-passing) and *Newly-failing* columns; the raw log line is unambiguous.

## Snapshot Assertions

- Use `json_inspect` for arrays or structured data when JSON/data semantics are what the test should assert.
- Use `inspect` only when MoonBit `Show` output itself is the behavior being asserted.
- Deprecated `inspect` snapshot migration work is complete; historical notes are archived in [docs/archive/agent-todo-history.md](docs/archive/agent-todo-history.md#migrate-remaining-deprecated-inspect-snapshots--done-2026-05-14).

## Documentation

Key entry points:

- [docs/README.md](docs/README.md) — docs index, audience-separated
- [docs/development.md](docs/development.md) — maintainer workflow
- [docs/ROADMAP.md](docs/ROADMAP.md) — test262 pass rate, failure breakdown, next phase targets
- [docs/agent-todo.md](docs/agent-todo.md) — small AI-friendly tasks
- [docs/GLOSSARY.md](docs/GLOSSARY.md) — terminology

Docs rules:

- Architecture docs = principles only, never reference specific types/fields/lines
- Code is the source of truth — if a doc and the code disagree, the doc is wrong
- Verify changed claims against source code, tests, package config, scripts, or CI config before editing docs
- Mark unverifiable claims as "unverified" or remove them; do not invent support status, APIs, or design goals
- Keep `README.mbt.md` user-facing; put maintainer workflow in `docs/development.md` and agent-only workflow in `AGENTS.md`
- Do not hand-edit generated or frequently changing Test262 numbers; use `make test262-report`
- Do not edit `pkg.generated.mbti` files manually; regenerate them with `moon info`
- Completed/superseded material belongs under `docs/archive/`

---

# MoonBit Conventions

The rest of this file is project-agnostic MoonBit conventions. Inlined here so the repo is self-contained for contributors who don't use Claude Code. If you maintain a personal global copy (`~/.claude/moonbit-base.md`), keep them in sync.

## Quick Reference

| When...                    | Use...                              | Not...                        |
|----------------------------|-------------------------------------|-------------------------------|
| Top-level fixed value      | `const`                             | `let`                         |
| Local immutable binding    | `let`                               | `const` (illegal in functions)|
| Mutable variable           | `let mut`                           |                               |
| Bail out early             | `guard`                             | `if ... { return }`           |
| Branch on variants         | `match`                             | chained `if/else`             |
| Simple boolean             | `if/else`                           |                               |
| Struct construction        | `fn Type::Type(...)` constructor    | old `fn new()` inside body    |
| Empty callback body        | `() => ()`                          | `() => {}` (map literal!)     |
| Tuple field access         | `.0`                                | `._` (deprecated)             |
| Fallible return type       | `T!Error` with `!` propagation      | `try?` (won't catch abort)    |
| Iteration                  | `for .. in`                         | `loop` (deprecated)           |
| Visibility default         | `pub`                               | `pub(all)` unless needed      |
| Re-export from dependency    | `pub using @pkg { type T }`       | manual wrapper functions      |
| Foreign trait + foreign type | tuple-struct wrapper              | direct impl (orphan rule)     |
| Unimplemented placeholder  | `...`                               | leaving in committed code     |
| Debug snapshots            | `derive(Debug)` + `debug_inspect`/`to_repr` | container `Show` output |
| Regex matching             | `s =~ re"pattern"`                  | `lexmatch`/`lexmatch?` (deprecated) |
| Reduce nesting in DSLs     | `<\|` reverse pipeline              | deeply nested parentheses     |

## MoonBit Code Search

Prefer `moon ide` over grep/glob for MoonBit-specific code search. These commands use the compiler's semantic understanding, not text matching.

```bash
moon ide peek-def SyncEditor              # Go-to-definition with context
moon ide peek-def -loc editor/foo.mbt:5   # Definition at cursor position
moon ide find-references SyncEditor       # All usages across codebase
moon ide outline editor/                  # Package structure overview
moon ide doc "String::*rev*"              # API discovery with wildcards
```

Symbol syntax: `Symbol`, `@pkg.Symbol`, `Type::method`, `@pkg.Type::method`.

Use `moon ide` for finding definitions, tracing usages, understanding package APIs, and discovering methods. Fall back to grep only for non-MoonBit files or cross-language patterns.

### Convention Audit Commands

`moon ide` audits **semantic** properties (symbols, types, visibility). Grep audits **stylistic** choices (which keyword was used). Both are needed.

```bash
# Semantic audits (moon ide)
moon ide analyze <pkg> | grep "can be removed"       # Over-exposed pub(all)
moon ide analyze <pkg> | grep "usage: 0"             # Unused public APIs
moon ide outline <pkg> | grep ' | let '              # Top-level let → review if should be const
moon ide outline <pkg> | grep 'const'                # Verify const usage exists
moon ide find-references abort --loc <file:line>      # abort sites → potential guard candidates
moon ide doc --dump /tmp/symbols.jsonl                # Full symbol dump (NEVER pass a source file path — it overwrites!)

# Stylistic audits (grep — moon ide can't see keywords like return/if/guard)
grep -rn 'if .* { return' <pkg>/*.mbt                # guard candidates (early return)
grep -rn '() => {}' <pkg>/*.mbt                      # Empty callback anti-pattern
```

## Bindings & Visibility

- **`const`** for top-level compile-time constants — **top-level only, cannot appear inside functions** (unlike JavaScript/TypeScript). When defining a fixed value at module scope (magic numbers, sizes, thresholds, string keys), always use `const`, not `let`.

  ```moonbit
  const MAX_SIZE = 1024      // correct — top-level fixed value → const
  const PREFIX = "incr"      // correct — top-level fixed string → const
  //! let MAX_SIZE = 1024    // wrong — use const for top-level fixed values

  fn main {
    let x = 10               // correct — immutable local binding
    let mut i = 10            // correct — mutable local binding
    //! const LOCAL = 10      // ILLEGAL — const cannot appear inside functions
  }
  ```

- **Visibility:** `pub` exposes a symbol to direct dependents only. `pub(all)` exposes it transitively to all downstream packages. `pub(open)` on enums allows downstream packages to add variants. Use `pub` by default; only use `pub(all)` for types/functions that downstream-of-downstream consumers need, and `pub(open)` only for intentionally extensible enums.
- **Constructor aliases:** `using @pkg { type T }` imports a constructor alias so `T(args)` works instead of `@pkg.T(args)`. `#alias(Name)` on a type definition creates a local alias. Both work with tuple structs, structs with custom constructors, and single-constructor errors.

  ```moonbit
  using @ref { type Ref }
  let r = Ref(42)             // instead of @ref.Ref(42)
  ```

- **Re-exports with `pub using`:** `pub using @pkg { type T, trait Trait, fn_name }` both re-exports symbols to consumers AND makes them available locally without prefix. Use this for facade packages that provide backward compatibility during package splits.

  ```moonbit
  // In facade package — re-exports all DSP types from @dsp
  pub using @dsp {
    type AudioBuffer,
    type DspContext,
    type Waveform,
    trait ArithSym,
    is_finite,
  }
  ```

  **What works through `pub using`:** function calls, type annotations, method calls on re-exported types, trait bounds, enum pattern matching via `Type::Constructor`. **What doesn't:** bare enum constructors via `@pkg.Constructor` (use `using @pkg { type T }` + `T::Constructor(args)` instead — this is standard MoonBit, not a `pub using` limitation). The `.mbti` interface shows re-exported types with their canonical origin (e.g., `@dsp.AudioBuffer`), but consumer code using the facade path still compiles.
- **Naming:** `snake_case` for functions, methods, variables, and modules. `PascalCase` for types, enums, and constructors. `SCREAMING_SNAKE_CASE` for `const` constants.

## Control Flow

- **Decision tree:**

  ```
  Need to bail out early (precondition, unwrap, validation)?
    ├── yes → guard (bool or pattern — keeps happy path unindented)
    └── no → Destructuring enum/Option/Result variants?
          ├── yes → match (exhaustive, compiler-checked)
          └── no → if/else (simple boolean)
  ```

  **`guard`** filters out the bad case so the rest of the function stays flat. Prefer `guard` over `if ... { return }` or nested `match` when only one branch exits early.

  ```moonbit
  guard let Some(x) = opt else { return Err("missing") }
  guard n > 0 else { fail("n must be positive") }
  // happy path continues here — no nesting
  ```

- **Iteration:** `for .. in` with accumulator state. `loop` keyword is deprecated.

  ```moonbit
  // Preferred: for-in with accumulator
  for x in xs; sum = 0 {
    continue sum + x
  } nobreak { sum }

  // Also fine: for-in with mut for simple cases
  let mut acc = 0
  for i in 0..<n { acc += xs[i] }
  ```

- **Regex matching:** Use `s =~ re"pattern"` for regex. Patterns compose with `+` (concat), `|` (alternation), `as name` (captures), and `before=`/`after~` (surrounding text bindings).

  ```moonbit
  let s = "==abc=="
  let _ = s =~ re"abc"                                      // simple match
  let _ = s =~ (re"a" + re"bc", )                           // pattern composition
  let _ = s =~ (((re"x" as x) | re"b") + re"bc", before=y, after~) // captures + context
  ```

- **Reverse pipeline `<|`:** Reduces nesting in DSL/view code. `f <| args` is equivalent to `f(args)`.

  ```moonbit
  fn view() -> Html {
    div <| [
      text("hello"),
      ul <| [ li("item 1"), li("item 2") ],
    ]
  }
  ```

- **StringView/ArrayView patterns:** Use `.view()` for prefix/suffix matching with `match`:

  ```moonbit
  match s.view() {
    [.."let", ..rest] => ...  // prefix match
    [a, ..rest, b] => ...     // first and last
    [] => ...                 // empty
  }
  ```

## Functions & Types

- **Arrow functions:** `() => expr` (zero params, single expression), `() => { stmts }` (multi-statement), `x => expr` (one param), `(x, y) => expr` (multiple params). Empty body: `() => ()` — not `() => {}` which MoonBit parses as a map literal. Named functions (`pub fn`, `fn name(...)`) are unaffected.
- **Custom constructors for structs:** Define a constructor method named after the type, `fn Type::Type(...) -> Type`. This enables `Type(...)` construction syntax with labelled/optional parameters, validation, and defaults without repeating a signature inside the struct body. Applies regardless of visibility — `pub`, `pub(all)`, and `priv` structs all benefit from consistent call syntax and future-proof validation hooks. Prefer this over bare struct literals `{ field: value }`.

  ```moonbit
  struct MyStruct {
    x : Int
    y : Int
  } derive(Debug)

  fn MyStruct::MyStruct(x~ : Int, y? : Int = x) -> MyStruct {
    { x, y }
  }

  let s = MyStruct(x=1)  // usage — like enum constructors
  ```

  If a public API already exposes `Type::new`, preserve compatibility with `#alias(new)` on the constructor method, or use `#alias(new, deprecated="message")` when intentionally migrating callers.

  ```moonbit
  pub(all) struct Box[T] {
    val : T
  }

  #alias(new)
  fn[T] Box::Box(value : T) -> Box[T] { { val: value } }

  let b : Box[Int] = Box(42)
  ```

- **Trait impl:** `pub impl Trait for Type with method(self) { ... }` — one method per impl block.
- **Orphan rule** (error 4061): can't impl foreign trait for foreign type — use a private tuple-struct wrapper.
- **Error handling:** use `Unit!Error` or `T!Error` for fallible return types. Normal calls auto-propagate errors (zero syntax cost). `try?` converts to `Result[T, E]` (preserves concrete `E`). `abort` is NOT catchable — prefer `fail("msg")` for defect detection (catchable + source location).
- **TODO syntax:** `...` is a placeholder for unimplemented code. It type-checks as any type but aborts at runtime. Do not leave `...` in committed code.

## Testing

- **Files:** `*_test.mbt` (blackbox), `*_wbtest.mbt` (whitebox), `*_benchmark.mbt`.
- **Assertions:** Use `json_inspect` for JSON/data snapshots, `debug_inspect` for Debug snapshots, `inspect` only when `Show` output itself is the behavior under test, and `@qc` for properties.
- **Panic tests:** name starts with `"panic "` — test runner expects `abort()`.
- **Blackbox tests** cannot construct internal structs — use whitebox tests or expose constructors.
- **Block-style:** Code organized in `///|` separated blocks.
- **Format:** Always `moon info && moon fmt` before committing.

## Pitfalls

- `._` syntax is deprecated — use `.0` for tuple access.
- Old newtype syntax `type T UnderlyingType` is removed — use `struct T(UnderlyingType)`.
- `ref` is a reserved keyword — do not use as variable/field names.
- `() => {}` is a map literal, not an empty function body — use `() => ()`.
- `loop` keyword is deprecated — use `for .. in`.
- `try?` does not catch `abort`.
- For cross-target builds, use per-file conditional compilation rather than `supported-targets` in `moon.pkg.json`.

## Code Changes & Review

- Before suggesting code removal, check if symbols are re-exported as public API for downstream consumers. Do not delete structs/types that appear unused internally but may be part of the library's public interface.
- Never dismiss a review request — always do a thorough line-by-line review even if changes seem minor.
- Check for: integer overflow, zero/negative inputs, boundary validation, generation wrap-around.
- Do not suggest deleting public API types (Id structs, etc.) as "unused" — they may be needed by downstream consumers.
- Verify method names match actual API before writing tests (e.g., check if it's `insert` vs `add_local_op`).
- **Edit numbering discipline.** Every edit that inserts or deletes lines changes all subsequent line numbers. After any edit with non-zero net line change, `read` the file (or at least the affected ranges) before the next `edit` call. Never rely on numbers from before the insert/delete. (Missed this in PR #492: helper insertion shifted the 3-byte utf-8 branch by 14 lines, causing a closing brace to be consumed by a SWAP.)

## Debug Methodology

When investigating a `TypeError: X is not a function` or a property access returning `undefined`:

1. **Does the thing exist?** Before investigating whether X's behavior is wrong, check `typeof target.X` — it may be `undefined` (property doesn't exist at all).
2. **What would make it exist?** If missing, trace the prototype chain (`Object.getPrototypeOf`), not the property descriptor. The root cause may be a disconnected prototype rather than a wrong descriptor.
3. **What would prove the assumption wrong?** Before writing a fix for assumption A ("the descriptor value is wrong"), write one test query that would disprove A ("`typeof this.propertyIsEnumerable` is `function`"). Run it first.
4. **Filter specificity.** When running `make test262-filter`, remember FILTER uses substring `contains` on the normalized test path. A short prefix like `"decodeURI"` may match unrelated tests (`language/literals/decodeURI/...`). Narrow the filter to the full directory segment: `"built-ins/decodeURI"` or a specific filename.

## Development Workflow

### Performance Optimization Rule

Before designing any performance optimization, write a microbenchmark that **reproduces the claimed bottleneck** in isolation. If the benchmark can't demonstrate the problem, stop and re-evaluate. Stale profiling data and O(bad) complexity are not proof of a real problem.

### Incremental Edit Rule

**CRITICAL:** After every file edit, run `moon check` before proceeding to the next file. If there are errors, fix them immediately before continuing with the plan.

### Standard Workflow

1. Make edits
2. `moon check` — Lint
3. `moon test` — Run tests
4. `moon test --update` — Update snapshots (if behavior changed)
5. `moon prove` — Verify `proof_ensure` properties (if `proof-enabled: true` in `moon.pkg`)
6. `moon info` — Update `.mbti` interfaces
7. Check `git diff *.mbti` — Verify API changes
8. `moon fmt` — Format

### Workspace Commands

For multi-project workspaces (monorepos with multiple `moon.mod` files):

- `moon work init` — Initialize a workspace
- `moon work use <path>` — Add a project to the workspace
- `moon work sync` — Sync dependencies across workspace members

## Git & PR Workflow

- Always check if git is initialized before running git commands.
- After rebase operations, verify files are in the correct directories.
- When asked to "commit remaining files", interpret generously even if phrasing is unclear.
- When merging PRs, always verify CI status is actually passing (not skipped) before proceeding. Never represent CI as green if any checks were skipped or failed.
- After rebasing or refactoring, verify file paths haven't shifted unexpectedly. Run `git diff --stat` to confirm only intended files changed.
