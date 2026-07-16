# Architecture Stage 0 Implementation Specs — 2026-06-12

> Companion to [architecture-execution-plan-2026-06-12.md](architecture-execution-plan-2026-06-12.md).
>
> Stage 0 is guardrails and inventories only. It must not move semantic code,
> redesign runtime APIs, or broaden bytecode / closure-conversion behavior. Its
> job is to make future boundary drift visible before the architecture migration
> starts.

---

## 1. Scope

Stage 0 implements three guardrail/inventory tracks:

1. **Import-boundary audit** — package manifest imports must match the allowed
   dependency direction or an explicit temporary debt allowlist.
2. **Representation-access audit** — compiler and stdlib access to runtime
   representation internals must be visible and allowlisted until replaced by
   runtime operations.
3. **Surface taxonomy inventory** — generated public surfaces must be classified
   so removals are intentional and the no-internal-compatibility rule does not
   accidentally break stable user APIs.

Out of scope for Stage 0:

- Moving runtime, stdlib, compiler, parser, or AST code.
- Creating `static_semantics/`.
- Creating the runtime operation API.
- Changing JavaScript behavior.
- Expanding bytecode syntax support.
- Expanding closure-conversion syntax or semantics.
- Running or reporting Test262 conformance numbers.

## 2. Deliverables

Stage 0 is complete when the repo contains:

- a native MoonBit architecture-boundary audit command;
- JSON rule/allowlist metadata checked into `scripts/`;
- a Makefile target that runs the existing mutable-state audit plus the new
  boundary audit;
- documented current debt inventories for imports, representation access, and
  public surface taxonomy;
- CI or documented local workflow that can run the combined audit;
- no JavaScript semantic behavior changes.

Recommended new paths:

```text
tooling/architecture_boundary_audit/        audit library
cmd/architecture_boundary_audit/            native CLI wrapper
scripts/architecture_boundary_rules.json    import-boundary rules and debt
scripts/architecture_representation_access.json
scripts/architecture_surface_taxonomy.json
```

Recommended Make target:

```make
architecture-audit:
	$(MAKE) architecture-state-audit
	moon test --target native tooling/architecture_boundary_audit
	moon build --target native cmd/architecture_boundary_audit
	./_build/native/debug/build/cmd/architecture_boundary_audit/architecture_boundary_audit.exe --root .
```

Keep `make architecture-state-audit` intact; it already checks runtime/stdlib
module-level mutable state and should remain a focused guardrail.

## 3. Import-Boundary Audit Spec

### 3.1 Goal

Detect package imports that violate the intended dependency matrix unless they
are explicitly classified as temporary current debt.

### 3.2 Inputs

- All repo `moon.pkg` files, excluding `.mooncakes/` and build outputs.
- `scripts/architecture_boundary_rules.json`.

### 3.3 Rule file schema

Suggested shape:

```json
{
  "version": 1,
  "package_groups": [
    {
      "name": "frontend",
      "packages": ["token", "errors", "ast", "lexer", "parser"]
    },
    {
      "name": "runtime",
      "packages": ["interpreter/runtime"]
    },
    {
      "name": "stdlib",
      "packages": ["interpreter/stdlib"]
    },
    {
      "name": "compiler",
      "packages": ["compiler"]
    }
  ],
  "allowed_imports": [
    {
      "from": "lexer",
      "to": "token",
      "scope": "prod",
      "reason": "lexer emits tokens"
    },
    {
      "from": "parser",
      "to": "lexer",
      "scope": "prod",
      "reason": "parser facade parses source through lexer"
    },
    {
      "from": "interpreter/stdlib",
      "to": "interpreter/runtime",
      "scope": "prod",
      "reason": "stdlib is implemented on runtime semantic APIs"
    }
  ],
  "allowlisted_import_debt": [
    {
      "from": "interpreter/runtime",
      "to": "parser",
      "scope": "prod",
      "owner": "static-semantics extraction",
      "retire_by_stage": "Stage 4-6",
      "reason": "eval/function/module paths still parse source inside runtime before preparation boundary exists"
    }
  ]
}
```

Rules:

- `scope` values: `prod`, `test`, `wbtest`, or `any`.
- The audit must distinguish production imports from `for "test"` and
  `for "wbtest"` imports.
- Production and test debt should be allowlisted separately. A test-only import
  must not silently justify a production import.
- Unknown packages may be ignored only if they are explicitly classified as
  tooling, command, benchmark, or external dependency.

### 3.4 Initial package groups

Initial groups should reflect the current repo before target package splits:

```text
frontend-core: token, errors, ast, lexer, parser
runtime: interpreter/runtime
stdlib: interpreter/stdlib
wiring: interpreter
compiler: compiler
facade: .
commands: cmd/*
tooling: tooling/*
benchmarks: benchmarks
external: moonbitlang/*
```

The target architecture has finer packages, but Stage 0 must first guard the
current coarse package shape.

### 3.5 Output

Default success output:

```text
ok: architecture import boundaries match rules (N imports, M allowlisted debts)
```

Failure output should include one line per unclassified violation:

```text
architecture boundary audit failed:

unclassified imports:
- interpreter/runtime/moon.pkg: dowdiness/js_engine/parser [prod]

stale allowlist entries:
- interpreter/runtime -> parser [prod]
```

`--list` should print all imports with classification:

```text
interpreter/runtime -> parser [prod] -- DEBT Stage 4-6: eval/function/module paths still parse source inside runtime
stdlib -> runtime [prod] -- allowed: stdlib is implemented on runtime semantic APIs
```

### 3.6 Acceptance criteria

- Adding a new production import from frontend to runtime fails.
- Adding a new runtime-to-stdlib import fails.
- Removing an allowlisted import without updating metadata fails as stale debt.
- Test-only imports do not mask production imports.
- The command runs under native target.

## 4. Representation-Access Audit Spec

### 4.1 Goal

Detect compiler and stdlib access to runtime representation internals so that
future stages can replace those accesses with runtime operations.

This audit is an inventory and regression guard. It is not expected to be empty
on day one.

### 4.2 Inputs

- Source files under `compiler/` and `interpreter/stdlib/`.
- Optional later inclusion of `benchmarks/` and tests.
- `scripts/architecture_representation_access.json`.

### 4.3 Metadata schema

Suggested shape:

```json
{
  "version": 1,
  "scan_roots": ["compiler", "interpreter/stdlib"],
  "ignore_globs": ["**/*_test.mbt", "**/*_wbtest.mbt", "**/pkg.generated.mbti"],
  "representation_patterns": [
    {
      "id": "runtime-object-constructor",
      "pattern": "Value::Object|Object\\(",
      "kind": "constructor",
      "reason": "constructs runtime object representation directly"
    },
    {
      "id": "runtime-array-constructor",
      "pattern": "Value::Array|Array\\(",
      "kind": "constructor",
      "reason": "constructs runtime array representation directly"
    },
    {
      "id": "property-bag-access",
      "pattern": "\\.bag\\b|PropertyBag",
      "kind": "field-or-type",
      "reason": "observes or mutates object property storage"
    }
  ],
  "allowlisted_access": [
    {
      "path": "compiler/bytecode.mbt",
      "pattern_id": "property-bag-access",
      "owner": "runtime operation migration",
      "retire_by_stage": "Stage 7-8",
      "reason": "bytecode object literal accumulator still mutates object representation before ObjectCreateOps/PropertyOps exist"
    }
  ]
}
```

### 4.4 Initial pattern families

Start conservative but useful. The first version should catch at least these
families:

- raw `Value` object/array/map/set/promise/proxy constructors;
- runtime representation type names in compiler/stdlib:
  - `ObjectData`, `ArrayData`, `MapData`, `SetData`, `PromiseData`, `ProxyData`;
  - `PropertyBag`, `PropDescriptor`, `PartialDescriptor`;
  - `Callable`, `FuncData`, `FuncDataExt`, `ClassConstructorData`;
- direct representation fields:
  - `.bag`, `.elements`, `.holes`, `.callable`, `.prototype`, `.extensible`,
    `.target`, `.handler`, `.state`, `.result`, `.entries`, `.values`;
- direct mutation of representation maps/arrays through known fields;
- calls to representation constructors that should eventually become semantic
  builders.

Avoid pretending this is a full MoonBit parser. A line-oriented scanner is
acceptable for Stage 0 if the allowlist is precise and stale entries are
detected.

### 4.5 Output

Default success output:

```text
ok: architecture representation access matches inventory (N classified accesses)
```

Failure output:

```text
architecture representation audit failed:

unclassified representation access:
- compiler/bytecode.mbt:4790: property-bag-access: .bag

stale allowlist entries:
- compiler/bytecode.mbt:property-bag-access
```

`--list-representation` should print all classified accesses with retirement
stage.

### 4.6 Acceptance criteria

- Adding a new direct `Object({ ... })` construction in compiler without an
  allowlist entry fails.
- Removing an allowlisted direct access without removing metadata fails as stale
  debt.
- The audit can distinguish compiler debt from stdlib debt.
- The output names the owning migration stage for each retained debt.

## 5. Surface Taxonomy Inventory Spec

### 5.1 Goal

Classify public surfaces so the project can break accidental internal API
without accidentally changing the stable user facade.

### 5.2 Inputs

- Generated `pkg.generated.mbti` files after `moon info`.
- `scripts/architecture_surface_taxonomy.json`.

### 5.3 Taxonomy schema

Suggested shape:

```json
{
  "version": 1,
  "package_defaults": [
    {
      "package": "dowdiness/js_engine/interpreter/runtime",
      "category": "internal_api",
      "reason": "runtime representation is not a stable user facade"
    },
    {
      "package": "dowdiness/js_engine/compiler",
      "category": "experimental_public",
      "reason": "compiler entry points are opt-in experiments"
    }
  ],
  "symbol_overrides": [
    {
      "package": "dowdiness/js_engine",
      "symbol": "run",
      "category": "stable_user_facade",
      "reason": "documented library entry point"
    },
    {
      "package": "dowdiness/js_engine",
      "symbol": "run_compiled",
      "category": "experimental_public",
      "reason": "closure-conversion entry point; removable when closure legacy retires"
    }
  ]
}
```

Categories:

| Category | Meaning | Deletion rule |
|---|---|---|
| `stable_user_facade` | documented user API | preserve unless a separate product decision changes it |
| `experimental_public` | opt-in prototype surface | may rename/delete under the execution plan |
| `internal_api` | package-public implementation detail | may break freely when replaced by better boundary |
| `generated_interface_artifact` | public only because current package layout requires it | shrink intentionally |
| `benchmark_tooling_hook` | exposed for benchmark/tool runner integration | may break with same-stage tooling migration |

The Adoption Roadmap refines root-package user surfaces into the product-facing
categories `stable_embedding`, `compatibility`, and `advanced_internal`.
Package-level implementation categories above remain in use for non-root
packages. The current inventory in
[`scripts/architecture_surface_taxonomy.json`](../../scripts/architecture_surface_taxonomy.json)
is authoritative when this original Stage 0 expectation differs from the later
adoption classification.

### 5.4 Initial classification expectations

The first inventory should classify at least:

- root package `@js_engine`:
  - `run`, `run_module`, `run_modules`, `run_with_event_loop`,
    `run_microtask_checkpoint`, `run_timer_checkpoint`, and pending-queue
    helpers as `stable_user_facade` unless intentionally changed;
  - `run_compiled` as `experimental_public` tied to closure legacy;
- `compiler` package:
  - bytecode entry points as `experimental_public` until bytecode becomes a
    supported execution mode;
  - closure-conversion entry points as `experimental_public` with retirement
    stage;
- `interpreter/runtime` and `interpreter/stdlib` packages:
  - default to `internal_api` or `generated_interface_artifact` unless a symbol
    is explicitly promoted;
- `tooling/*`, `cmd/*`, and `benchmarks` surfaces:
  - `benchmark_tooling_hook` or tool-local internal category.

Do not require symbol-level classification of every runtime helper in the first
PR if package-level default classification is present. Require symbol-level
classification before deleting or promoting a symbol.

### 5.5 Output

Default success output:

```text
ok: architecture surface taxonomy covers generated interfaces (P packages, S symbols, U package-defaulted)
```

Failure output:

```text
architecture surface taxonomy failed:

unclassified public surfaces:
- package dowdiness/js_engine: run_new_mode

stale symbol overrides:
- package dowdiness/js_engine/compiler: run_bytecode_script
```

`--list-surfaces` should print classified symbols and category.

### 5.6 Acceptance criteria

- Adding a new root facade function fails until categorized.
- Removing a categorized symbol without updating taxonomy fails as stale.
- Runtime/stdlib package-level defaults prevent first-run noise but still allow
  symbol-level overrides.
- Interface changes from architecture PRs are reviewed against the taxonomy.

## 6. Native Command Shape

Prefer one native command with selective list flags:

```bash
./_build/native/debug/build/cmd/architecture_boundary_audit/architecture_boundary_audit.exe --root .
./_build/native/debug/build/cmd/architecture_boundary_audit/architecture_boundary_audit.exe --root . --list-imports
./_build/native/debug/build/cmd/architecture_boundary_audit/architecture_boundary_audit.exe --root . --list-representation
./_build/native/debug/build/cmd/architecture_boundary_audit/architecture_boundary_audit.exe --root . --list-surfaces
```

Suggested flags:

| Flag | Meaning |
|---|---|
| `--root <path>` | repository root, default `.` |
| `--list-imports` | print classified import edges |
| `--list-representation` | print classified representation accesses |
| `--list-surfaces` | print classified public surfaces |
| `--format text|json` | optional later extension; text is enough for first PR |

Exit codes:

- `0` when all audits pass.
- `1` when unclassified or stale entries are found.
- Non-1 only for tool defects, parse failures, or invalid metadata.

## 7. PR Breakdown

### PR 1 — Import-boundary audit skeleton

Scope:

- add `tooling/architecture_boundary_audit` and
  `cmd/architecture_boundary_audit`;
- parse `moon.pkg` import edges;
- add `scripts/architecture_boundary_rules.json`;
- add `--list-imports`;
- add Makefile target `architecture-audit` that runs existing state audit and
  the import-boundary audit.

Acceptance:

- current repo passes with current debt allowlisted;
- adding a forbidden import fails;
- removing an allowlisted import creates a stale-entry failure;
- `moon check`, `moon test tooling/architecture_boundary_audit`, and
  `make architecture-audit` pass.

### PR 2 — Representation-access inventory

Scope:

- extend the same tool with representation pattern scanning;
- add `scripts/architecture_representation_access.json`;
- add `--list-representation`;
- classify current compiler and stdlib direct representation access;
- keep the scanner conservative and text-based unless a semantic approach is
  clearly cheap.

Acceptance:

- current repo passes with current debt allowlisted;
- adding a new compiler representation access fails;
- stale allowlist entries fail;
- output identifies owner and retirement stage for each retained debt.

### PR 3 — Surface taxonomy inventory

Scope:

- extend the tool to parse generated interfaces or a stable enough outline of
  public package surfaces;
- add `scripts/architecture_surface_taxonomy.json`;
- add `--list-surfaces`;
- classify root facade, compiler experimental surfaces, runtime/stdlib package
  defaults, tooling, commands, and benchmarks.

Acceptance:

- current repo passes after `moon info`;
- adding a new root facade symbol fails until categorized;
- stale symbol overrides fail;
- runtime/stdlib package defaults avoid unhelpful first-run noise.

## 8. Verification Matrix

Every Stage 0 PR:

```bash
moon check
moon test
moon info
moon fmt
git diff --check
```

Additional per PR:

```bash
moon test --target native tooling/architecture_boundary_audit
moon build --target native cmd/architecture_boundary_audit
make architecture-audit
```

Do not run Test262 for Stage 0 unless the PR unexpectedly changes executable
engine behavior. If it does, stop: Stage 0 scope has been violated.

## 9. Stop Conditions

Stop and redesign the Stage 0 implementation if:

- the audit requires maintaining huge line-number-specific allowlists that churn
  on formatting;
- the import parser cannot distinguish production imports from test imports;
- runtime/stdlib package defaults hide new root facade or compiler experimental
  surfaces;
- the representation scanner produces so many false positives that new debt is
  not visible;
- implementing the audit starts moving semantic code;
- closure conversion receives new behavior while Stage 0 is in progress.

## 10. Open Questions Before Implementation

- Should the architecture-boundary audit be one command with three checks or
  three narrower commands? The spec prefers one command, but implementation may
  split if that keeps code simpler.
- Should surface taxonomy parse `.mbti` directly or use `moon ide outline`? The
  first implementation should choose the more stable input and document the
  trade-off.
- Which current runtime imports of parser should be assigned to preparation
  extraction versus later runtime operation work?
- Which representation patterns are useful enough for PR 2 without causing
  excessive false positives?
- Should the combined `architecture-audit` target be added to CI in PR 1 or
  after PR 3 when all inventories exist?
