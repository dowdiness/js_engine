# Plan 002: Implement spec-ordered JSON serialization through runtime operations

> **Executor instructions**: Follow every step and verification gate. Stop and
> report instead of improvising when a STOP condition occurs. Update this plan's
> row in `plans/README.md` when complete.
>
> **Drift check (run first)**:
> `git diff --stat f806f28..HEAD -- interpreter/stdlib/builtins_json.mbt interpreter/runtime/enumerable_own_properties.mbt interpreter/runtime/array_like.mbt interpreter/stdlib/builtins_array_init.mbt js_engine_test.mbt scripts/architecture_representation_access.json`
> Any semantic mismatch with the excerpts below is a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: bug, tech-debt
- **Planned at**: commit `f806f28`, 2026-07-13

## Why this matters

`JSON.stringify` currently has separate direct-representation branches for
ordinary objects, arrays, proxies, Map, Set, and Promise. Those branches bypass
observable ECMAScript operations: ordinary and array accessors do not run, and
enumerable expando properties on bag-bearing exotics disappear. The direct
reads also broke the repository's representation-boundary audit. The fix must
follow the distinct `SerializeJSONArray` and `SerializeJSONObject` algorithms;
it must not flatten their different ordering, length, key-selection, replacer,
proxy, and abrupt-completion rules into one convenience helper.

## Current state

- `interpreter/stdlib/builtins_json.mbt:119-167` builds replacer `PropertyList`
  by pattern matching Array/Proxy representation and reading elements directly.
- `interpreter/stdlib/builtins_json.mbt:518-530` implements a stdlib-local
  `json_is_array_like` by recursively inspecting Proxy target fields.
- `interpreter/stdlib/builtins_json.mbt:653-788` has separate proxy-array and
  proxy-object serializers using runtime operations.
- `interpreter/stdlib/builtins_json.mbt:803-839` correctly performs `toJSON`
  lookup before invoking the replacer. Preserve this ordering.
- `interpreter/stdlib/builtins_json.mbt:840-919` hardcodes Map/Set/Promise as
  `{}` and reads `ArrayData.elements` directly.
- `interpreter/stdlib/builtins_json.mbt:948-1110` walks ordinary-object bags,
  descriptors, callable fields, and values directly rather than invoking
  `[[Get]]`.
- `interpreter/runtime/enumerable_own_properties.mbt:24-113` already owns
  enumerable own string-key collection for Object/Array/Proxy, including proxy
  `ownKeys` and `getOwnPropertyDescriptor` traps; `:117-259` demonstrates
  getter-aware values/entries via `Interpreter::get_property`. Its fallback for
  other exotic values is currently empty.
- `interpreter/runtime/array_like.mbt:648-671` and
  `interpreter/stdlib/builtins_array_init.mbt:1175-1195` contain separate
  IsArray-style proxy unwrapping. Do not add a third copy.
- `test262/test/built-ins/JSON/stringify/value-array-abrupt.js:13-65` requires
  array serialization to use `LengthOfArrayLike` and indexed `Get`, propagating
  abrupt completion.
- `docs/design/architecture-redesign-2026-06-12.md:208-218` makes runtime
  semantic operations the only cross-boundary API for observable property,
  proxy, call, conversion, and iteration behavior.

Observed at `f806f28`:

- An enumerable getter at array index `0` is skipped: no side effect and `[0]`
  instead of `[1]`.
- An enumerable ordinary-object getter is skipped: no side effect and `{}`
  instead of `{"x":1}`.
- A Map with enumerable `x = 1` serializes as `{}` instead of `{"x":1}`;
  Set and Promise follow the same hardcoded branch.
- `make architecture-audit` fails with new and stale JSON representation-access
  categories. State, import, and surface checks pass; the representation scan is
  the failing gate.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Runtime API discovery | `moon ide doc '@runtime.object_keys' '@runtime.Interpreter::get_property' '@runtime.to_array_like_length_interp'` | exact available signatures, or a documented IDE limitation |
| Focused facade tests | `moon test js_engine_test.mbt --filter '*JSON.stringify*'` | all selected tests pass after implementation |
| Exact Test262 contract | `make test262-runner-mbt ARGS='--engine "moon run cmd/main --" --test262 ./test262 --filter built-ins/JSON/stringify/value-array-abrupt.js --output /tmp/json-value-array-abrupt.json --summary'` | both applicable modes pass; output only under `/tmp` |
| Typecheck after every source edit | `moon check` | exit 0 |
| Architecture gate | `make architecture-audit` | exit 0; no unclassified/stale representation access |
| Full tests | `moon test` | exit 0 |
| Interfaces/format | `moon info && moon fmt && moon check` | all exit 0; intentional interface diff only |

## Suggested executor toolkit

- Read `skill://moonbit-agent-guide`, `skill://moonbit-verification`, and
  `skill://systematic-debugging` if available.
- Read the current ECMAScript algorithms and targeted Test262 `info` fields for
  `JSON.stringify`, `SerializeJSONProperty`, `SerializeJSONArray`,
  `SerializeJSONObject`, and `IsArray` before designing helpers.

## Scope

**In scope**:

- `js_engine_test.mbt` — end-to-end regressions through `@js_engine.run`.
- `interpreter/stdlib/builtins_json.mbt` — algorithm orchestration.
- `interpreter/runtime/enumerable_own_properties.mbt` — only if the existing
  runtime key operation must cover Map/Set/Promise and other object exotics.
- `interpreter/runtime/array_like.mbt` — only for one canonical runtime IsArray
  operation if no correct API already exists.
- `interpreter/stdlib/builtins_array_init.mbt` — only to make `Array.isArray`
  consume that canonical operation.
- `scripts/architecture_representation_access.json` — remove stale entries or
  update deliberately retained debt only after code no longer violates the
  intended boundary.
- Generated interfaces changed by `moon info`, never by hand.

**Out of scope**:

- Unifying the three intentional property-dispatch families.
- Rewriting JSON parsing/reviver semantics except where shared IsArray/key
  operations replace direct representation access without behavior change.
- New JSON features such as parse-with-source, BigInt, or raw JSON.
- Hand-editing generated interface files or merely refreshing audit fingerprints
  to bless avoidable direct access.
- Performance work without a reproducing benchmark.

## Git workflow

- Branch: `fix/json-stringify-semantic-operations`.
- Keep tests and semantic fix in one bugfix commit unless a runtime-facade
  extraction is independently reviewable; if split, commit the facade refactor
  first only after characterization tests exist, then the JSON behavior fix.
- Suggested messages: `refactor(runtime): expose JSON property operations` and
  `fix(json): honor observable serialization operations`.
- Do not push/open a PR unless instructed.

## Steps

### Step 1: Complete the mandatory impact and type audit

1. Find every caller of `json_stringify_value`, proxy serializers,
   `json_is_array_like`, `object_keys`, and every IsArray implementation.
2. For each serialization entry path, record possible values: ordinary Object,
   Array, Proxy (including revoked/nested), Map, Set, Promise, callable Object,
   module namespace, boxed primitive, and any other object-valued variant.
3. Read each applicable spec algorithm and write a compact ordering table:
   `toJSON`; replacer call; object/callable decision; IsArray; array length/index
   access; object PropertyList or enumerable keys; per-property `Get`; cycle
   stack; indentation.
4. State assumptions in at most three lines. Include that runtime is the sole
   owner of observable property/proxy semantics and that array/object algorithms
   remain separate.

**Verify**: every current `match val` object variant is classified. If an object
variant cannot be assigned to SerializeJSONArray or SerializeJSONObject using
spec IsArray, stop and resolve the model before editing.

### Step 2: Add failing end-to-end characterization tests

In `js_engine_test.mbt`, extend the existing JSON test area. Use
`json_inspect` on output arrays. Add cases for:

**SerializeJSONArray**

- Index accessor getter runs once and its returned value is serialized.
- Throwing index getter propagates the thrown JavaScript error.
- Length/index lookup through an array Proxy observes the required `get` traps
  and propagates revocation/abrupt completion.
- A hole serializes as `null`, including a prototype getter case if supported by
  the current property model.
- Cycles still throw after moving access through semantic operations.

**SerializeJSONObject**

- Ordinary enumerable getter runs once; non-enumerable getter does not run.
- Key list is captured before getter side effects add a new property, while
  values are fetched later through `Get`.
- Enumerable expando properties on Map, Set, and Promise serialize as ordinary
  object properties; their collection/internal-slot contents do not.
- Proxy `ownKeys`, `getOwnPropertyDescriptor`, and `get` traps remain ordered and
  revoked proxies throw.

**Shared prelude and PropertyList**

- `toJSON` runs before replacer and receives the correct key.
- Replacer `PropertyList` preserves its specified order, deduplicates names, and
  filters object keys while array serialization still uses indices.
- Replacer-array elements are obtained through semantic `Get`, including
  accessors/proxies and abrupt completion.
- Function/callable values remain omitted where required.

**Verify**: run `moon test js_engine_test.mbt --filter '*JSON.stringify*'` before
implementation. The new getter/expando cases must fail for the reproduced
reasons; existing proxy/toJSON/replacer controls must remain green. If multiple
unrelated failures obscure the contract, split fixtures without weakening them.

### Step 3: Establish one runtime IsArray operation

First search for an existing public runtime IsArray operation. If one exists and
matches §7.2.2 including nested/revoked Proxy behavior, reuse it. Otherwise:

1. Add one runtime operation in the cohesive array-like runtime file.
2. Define its contract from §7.2.2, including abrupt behavior for revoked Proxy
   rather than returning a misleading Boolean.
3. Make both JSON and `Array.isArray` call it.
4. Delete stdlib-local recursive target inspection once all callers migrate.

Do not expose Proxy fields to stdlib through the new API. Do not merge this with
array length/index retrieval.

**Verify after each source-file edit**: run `moon check` and fix all diagnostics
before editing the next file. Then run focused existing `Array.isArray` and JSON
Proxy tests. Expected: behavior unchanged except correctly propagated revoked
Proxy semantics.

### Step 4: Implement `SerializeJSONArray` using the exact operations

Refactor the array path so it:

1. Uses the original value as receiver, including Proxy-wrapped arrays.
2. Gets length through the existing interpreter-aware LengthOfArrayLike
   operation.
3. Iterates numeric string keys in ascending range and performs
   `SerializeJSONProperty`/`Get` for each; never reads `ArrayData.elements`.
4. Converts unsupported/undefined array elements to `null` as specified.
5. Preserves stack-based cycle detection, indentation, replacer, `toJSON`, and
   abrupt completion ordering.

A helper may represent this algorithm, but it must be array-specific and accept
all state explicitly. It must not collect enumerable object keys.

**Verify immediately**: `moon check`, then the focused array tests and exact
`value-array-abrupt.js` runner command. Expected: all pass in both applicable
modes.

### Step 5: Implement `SerializeJSONObject` through runtime key/value operations

Refactor the object path so it:

1. Uses `PropertyList` verbatim when present; otherwise obtains enumerable own
   string keys in spec order through a runtime operation.
2. Extends that runtime operation to bag-bearing exotic objects where necessary,
   rather than matching their representation in stdlib.
3. Performs `Get` on the original receiver for each selected key so accessors and
   Proxy traps run with correct receiver semantics.
4. Handles Map/Set/Promise and other non-array objects by their own enumerable
   properties; never serializes internal collection contents unless exposed as
   ordinary enumerable properties.
5. Preserves key-snapshot timing, per-key value timing, cycle detection,
   omission rules, indentation, `toJSON`, and replacer order.

Do not reuse `Object.entries` if doing so would eagerly read all values before
serialization/replacer sequencing. Prefer a keys-only semantic operation plus
per-key `Get`.

**Verify after each source edit**: `moon check`. Then run focused ordinary,
exotic-expando, proxy, PropertyList, toJSON, and replacer tests.

### Step 6: Retire representation access instead of blessing it

Run `make architecture-audit` and inspect every remaining JSON finding.

- Remove inventory entries whose direct access no longer exists.
- For a residual access, first determine whether an existing runtime operation
  should own it.
- Classify residual debt only when the design explicitly requires it; record a
  narrow rationale and exact fingerprint.
- Do not copy the audit's “found” values wholesale into metadata.

**Verify**: `make architecture-audit` exits 0 with no unclassified or stale
entry, and the total JSON representation-debt footprint does not increase.

### Step 7: Final verification

Run in order:

1. Focused `js_engine_test.mbt` JSON tests.
2. Exact Test262 `value-array-abrupt.js` command writing to `/tmp`.
3. Any other targeted JSON Test262 files cited by the new regressions.
4. `moon test`
5. `make architecture-audit`
6. `moon info`; review all `.mbti` diffs for intentional runtime API changes.
7. `moon fmt`
8. `moon check`
9. Re-run focused JSON tests and `make architecture-audit` after formatting.

## Test plan

Tests must defend observable order and abrupt completion, not source shape. The
minimum matrix is array getter/throw/hole/proxy/cycle; object getter/key snapshot;
Map/Set/Promise expandos; PropertyList ordering/dedup/filter; toJSON-before-
replacer; proxy trap/revocation. Existing `js_engine_test.mbt:2274-2280` is the
facade-test pattern. The Test262 `value-array-abrupt.js` result is an independent
spec fixture and must pass, not merely execute.

## Done criteria

- [ ] Caller/type audit and three-line assumptions are recorded.
- [ ] Every new behavioral test was demonstrated failing before implementation.
- [ ] SerializeJSONArray uses runtime length/index `Get` operations and has no
      direct Array/Proxy representation read.
- [ ] SerializeJSONObject uses a keys-only semantic operation plus per-key `Get`;
      Map/Set/Promise expandos are preserved.
- [ ] `toJSON`, replacer, PropertyList, proxy traps, cycles, holes, and abrupt
      completions satisfy the test matrix.
- [ ] `value-array-abrupt.js` passes in both applicable modes.
- [ ] `make architecture-audit` exits 0 without blindly expanding debt metadata.
- [ ] Focused tests and full `moon test` pass.
- [ ] `moon info` interface changes are intentional and reviewed.
- [ ] `moon fmt` and final `moon check` pass.
- [ ] Only in-scope files are modified and the index status is updated.

## STOP conditions

Stop and report if:

- The current ECMAScript/Test262 algorithms contradict the ordering table.
- A proposed helper would merge SerializeJSONArray and SerializeJSONObject or
  eagerly read object values before the spec permits.
- Correctness requires reopening the intentional three-family property dispatch
  decision.
- The only route to green architecture audit appears to be broad allowlisting.
- A runtime operation would expose representation fields rather than hide them.
- A source edit cannot pass `moon check` before another file must change.
- A test or audit gate fails twice after a reasonable correction.

## Maintenance notes

Future JSON features must build on the spec algorithm boundaries established
here. Reviewers should scrutinize order: `toJSON`, replacer, IsArray,
PropertyList/key snapshot, per-key Get, and cycle stack are independently
observable. Any runtime API added here should remain semantic and representation-
opaque; generated-interface growth is acceptable only when it replaces direct
stdlib access.
