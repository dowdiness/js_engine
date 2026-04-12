# Agent Task Queue

Tasks are ordered by effort/impact. Each is self-contained enough to complete in one session.
Completed tasks should be struck through and dated.

---

## Next PR: Small Compliance Wins

**Branch**: create `claude/compliance-quick-wins-<id>` off `main`
**Goal**: Unlock 4 skipped feature flags, ~80–150 new test262 passes

### Task 1 — Unlock `regexp-dotall` (already implemented, zero-code change)

The `s` flag is fully implemented in `interpreter/builtins_regex.mbt`:
- `dot_all: Bool` in `RegexFlags` struct (line ~556)
- `dot_all` is set from `flags.contains("s")` at line ~899
- `.` matching logic already respects `dot_all` at line ~578
- The `dotAll` property on RegExp instances returns `true`/`false`
- The `flags` string includes `"s"` when set

**Test to confirm it works today:**
```bash
moon run cmd/main -- 'print(/foo.bar/s.test("foo\nbar")); print(/x/s.dotAll); print(/x/s.flags);'
# Expected: true / true / s
```

**Action**: In `test262-runner.py`, remove `"regexp-dotall"` from `SKIP_FEATURES`.
Run `python3 test262-runner.py --filter "built-ins/RegExp" --summary` to confirm pass rate improves.

---

### Task 2 — Add `Promise.withResolvers()`

**Spec**: https://tc39.es/ecma262/#sec-promise.withresolvers
**Feature flag**: `"promise-with-resolvers"` in `SKIP_FEATURES`
**File**: `interpreter/builtins_promise.mbt`

**Algorithm** (simple):
```js
Promise.withResolvers = function() {
  let resolve, reject;
  const promise = new Promise((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}
```

**Implementation**: Add a `make_interp_static_func_with_length("withResolvers", 0, fn(interp, args) raise { ... })` entry in the Promise constructor's properties map. Use `interp.call_value` with the Promise constructor to create the promise, capturing the resolve/reject via a native closure.

Look at how `Promise.resolve` and `Promise.reject` are implemented in `builtins_promise.mbt` for the pattern.

After implementing: remove `"promise-with-resolvers"` from `SKIP_FEATURES` and run
`python3 test262-runner.py --filter "built-ins/Promise" --summary`.

---

### Task 3 — Add `Promise.try()`

**Spec**: https://tc39.es/ecma262/#sec-promise.try
**Feature flag**: `"promise-try"` in `SKIP_FEATURES`
**File**: `interpreter/builtins_promise.mbt`

**Algorithm**:
```js
Promise.try = function(callbackFn, ...args) {
  // 1. Let C be this (the Promise constructor)
  // 2. If C is not an object, throw TypeError
  // 3. Return PromiseResolve(C, callbackFn(...args))
  //    - i.e. call callbackFn synchronously; if it throws, return a rejected promise
  try {
    return Promise.resolve(callbackFn(...args));
  } catch (e) {
    return Promise.reject(e);
  }
}
```

Same file and pattern as `withResolvers`. After implementing: remove `"promise-try"` from `SKIP_FEATURES`.

---

### Task 4 — Audit and unlock `async-functions`

**Feature flag**: `"async-functions"` in `SKIP_FEATURES`

**Current state** (verified 2026-04-12):
- `async function`, `async () =>`, `await expr` all parse and execute correctly
- `async function f(x) { return x * 2; }` and multi-level `await` work
- `for await...of` does NOT parse (that's `async-iteration`, separate flag — keep skipped)

**Investigation steps**:
1. Run the async-functions subset:
   ```bash
   python3 test262-runner.py --filter "language/statements/async-function" --summary
   python3 test262-runner.py --filter "language/expressions/async-arrow-function" --summary
   python3 test262-runner.py --filter "built-ins/AsyncFunction" --summary
   ```
   Do this BEFORE removing the flag — re-enable temporarily in test code or run with `--include-skipped` if supported.

   Alternatively: temporarily comment out `"async-functions"` from `SKIP_FEATURES`, run the filter, restore.

2. Review failures. Common gaps:
   - `AsyncFunction` constructor (`new AsyncFunction(...)`)
   - `async function*.length` / `.name` property descriptors
   - Top-level return value from async functions (should always be a Promise)
   - Rejected promise on thrown error propagation timing

3. Fix whatever is failing, then remove `"async-functions"` from `SKIP_FEATURES`.

**Note**: Keep `"async-iteration"` in `SKIP_FEATURES` — `for await` is not yet parsed
(SyntaxError: `Expected LParen, got Ident("await")` at the `for await` statement).

---

## Later PR: `regexp-named-groups`

**Feature flag**: `"regexp-named-groups"` in `SKIP_FEATURES`
**Estimated tests**: ~100+

**Current state**: Fails with `SyntaxError: Invalid regex: nothing to repeat` when parsing `(?<name>...)`.
The issue is in the regex parser in `interpreter/builtins_regex.mbt` — it doesn't recognize
`(?<name>` as a named capture group; it tries to parse `<` as something else and fails.

**What needs to happen**:
1. In the regex parser, handle `(?<name>...)` syntax — parse the group name and store it
2. After a match, populate `match.groups` object with named captures
3. `String.prototype.replace(regex, fn)` with named groups passes named keys to the callback
4. `String.prototype.matchAll` with named groups

This is a self-contained regex engine change. Study the existing capture group handling in
`builtins_regex.mbt` before starting.

---

## Later PR: `for-await` / `async-iteration`

**Feature flag**: `"async-iteration"` in `SKIP_FEATURES`
**Estimated tests**: ~200+

**Current state**: `for await (const v of iterable)` fails to parse.
The parser (`parser/`) needs a `ForAwait` AST node and the interpreter needs to handle
async iteration protocol (`Symbol.asyncIterator`, `next()` returning Promises).

This is a medium-effort feature. The generator/iterator infrastructure in
`interpreter/generator.mbt` and `interpreter/iterators.mbt` is the foundation — read
those first.

---

## Later PR: Stage 3/4 Sub-package Extraction

**Now unblocked** — `moon` is installed at `~/.moon/bin/moon`.

**Context**: The previous architectural PR extracted `HostEnv` and split `builtins_object.mbt`
into four files, all within the `interpreter/` package (no import changes needed).

Stage 3/4 would create actual MoonBit sub-packages with their own `moon.pkg` files,
requiring import declarations. This is a larger change and should be its own PR.

**Proposed split**:
- `interpreter/runtime/` — core execution types: `Value`, `Environment`, `Interpreter` struct, `HostEnv`
- `interpreter/stdlib/` — built-in method implementations: all `builtins_*.mbt` files

**Prerequisites**:
1. Run the stdlib coupling audit: grep all `builtins_*.mbt` for direct access to
   `interp.generator_objects`, `interp.module_registry`, `interp.module_exports`,
   `interp.host.timer_queue`, `interp.host.microtask_queue` — these cross-package
   accesses would need to become public API
2. Decide what goes in `runtime/` vs `stdlib/` vs stays in the root `interpreter/` package
3. Plan the `moon.pkg` dependency graph (no cycles allowed)

The MoonBit sub-package mechanism works: each directory under `interpreter/` with a
`moon.pkg` file becomes an independent package that other packages can import.
