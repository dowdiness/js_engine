# Self-Hosting js_engine via MoonBit's JavaScript Target

## Executive Summary

This document researches what is needed to **self-host this JavaScript engine by compiling it to JavaScript** using MoonBit's JS backend. The goal: produce a standalone `.js` file that *is itself* a JavaScript interpreter -- a JS engine running inside a JS runtime.

**Bottom line: The codebase is remarkably well-positioned for this.** There are no `extern "wasm"` FFI calls, no platform-specific code, and only one trivial external dependency (`@env.args()` for CLI argument parsing). The entire 27,378-line engine is pure MoonBit.

---

## 1. Current Architecture

```text
Source Code (MoonBit)
    ↓  moon build [--target wasm-gc]
WASM binary
    ↓  moon run cmd/main -- '<js code>'
Output (via moonrun / V8)
```

The engine is a tree-walking interpreter with 3 stages:
- **Lexer** (`lexer/`) → tokens
- **Parser** (`parser/`) → AST
- **Interpreter** (`interpreter/`) → execution result

All stages are pure MoonBit with no FFI calls.

---

## 2. What MoonBit's JS Target Provides

MoonBit supports `--target js` which compiles MoonBit source to standalone JavaScript files.

```bash
moon build --target js          # Compile to JS
moon run cmd/main --target js   # Run via Node.js
moon test --target js           # Run tests on JS backend
```

### Key properties of JS output:
- Output goes to `target/js/release/build/`
- Module format configurable: ESM (default), CJS, or IIFE
- TypeScript `.d.ts` declarations auto-generated
- Source maps supported (`--debug` flag)
- MoonBit `String` maps directly to JS `string` (zero conversion cost)
- All numeric types map to JS `number` (IEEE 754 double)

---

## 3. Compatibility Audit of This Codebase

### 3.1 External Dependencies

| Package | Used In | JS-Target Compatible? | Notes |
|---|---|---|---|
| `moonbitlang/core/env` | `cmd/main/main.mbt` | **Yes** | `@env.args()` returns CLI args; works on JS via `process.argv` |
| `moonbitlang/core/strconv` | `lexer/`, `interpreter/` | **Yes** | Pure computation, no platform dependency |
| `moonbitlang/core/math` | `interpreter/` | **Yes** | Maps to `Math.*` on JS target |

### 3.2 FFI Usage

```text
$ grep -r 'extern\s+"(wasm\|js)"' --include="*.mbt" .
(no results)
```

**Zero FFI calls.** The entire codebase is pure MoonBit with no `extern "wasm"` or `extern "js"` declarations. This is the ideal case for cross-target compilation.

### 3.3 Platform-Specific Code (Resolved)

The only platform interaction was `@env.args()` for CLI argument parsing. On the JS target, this returns raw `process.argv` (`["node", "script.js", source, ...]`), while on WASM the runtime strips the prefix so user args start at index 1.

**Solution implemented:** Backend-specific files using MoonBit's target file convention:
- `cmd/main/args.js.mbt` — reads source from `args[2]` (skipping `node` and script path)
- `cmd/main/args.wasm.mbt` / `args.wasm-gc.mbt` — reads source from `args[1]`

The shared `cmd/main/main.mbt` calls `get_source_arg() -> String?` defined in these files.

### 3.4 Data Structures

The engine uses:
- `Map[K, V]` (hash maps)
- `Array[T]` (growable arrays)
- `Ref[T]` (mutable references)
- Enum types with pattern matching
- String operations (indexing, slicing, comparison)

All of these compile to JavaScript without issues. `Map` becomes a JS `Map`, `Array` becomes a JS `Array`, `Ref` becomes a boxed object, and enums become tagged objects.

---

## 4. Steps to Self-Host

### Step 1: Build with `--target js`

```bash
moon build --target js
moon run cmd/main --target js -- 'console.log(1 + 2)'
```

This should work with **zero code changes** given the clean audit above.

### Step 2: Run Tests on JS Target

```bash
moon test --target js
```

Verify all MoonBit unit tests pass on the JS backend. Any failures would indicate:
- Integer overflow differences (MoonBit `Int` is 32-bit, but on JS target it's a double)
- Floating-point edge cases
- String encoding differences (unlikely since MoonBit `String` → JS `string` is identity)

### Step 3: Run Test262 on JS-Compiled Engine

Update the Makefile to support a JS-target test runner:

```makefile
test262-js: build-js test262-download
	python3 test262-runner.py \
		--engine "node target/js/release/build/cmd/main/main.mjs" \
		--test262 ./test262 \
		--output test262-results-js.json
```

Compare results between WASM and JS targets. Discrepancies indicate behavioral differences in the MoonBit JS backend.

### Step 4: Package as a Distributable Module

Configure `moon.pkg.json` for JS module output:

```json
{
  "link": {
    "js": {
      "format": "esm",
      "exports": ["run", "run_with_event_loop"]
    }
  }
}
```

This produces an importable ES module:

```javascript
import { run } from './js_engine.mjs';
const [output, result] = run('1 + 2');
console.log(result); // "3"
```

### Step 5: Browser Compatibility (Optional)

For browser usage, use IIFE format:

```json
{ "link": { "js": { "format": "iife" } } }
```

The engine has no file system dependencies (it reads source from a string argument), so it should run in browsers without polyfills.

---

## 5. Potential Issues & Mitigations

### 5.1 Numeric Precision

**Risk: Medium**

MoonBit's `Int` is 32-bit signed on WASM but becomes a JS `number` (float64) on the JS target. This affects:
- Bitwise operations (`|`, `&`, `^`, `<<`, `>>`, `>>>`) in the interpreter's implementation
- Integer overflow behavior in the lexer/parser

**Mitigation:** MoonBit's JS backend applies `| 0` coercion for 32-bit integer operations. The engine's own bitwise operations on JS *values* are implemented as MoonBit `Double` arithmetic already, so this is likely fine. Test262 will catch any regressions.

### 5.2 Performance

**Risk: Low-Medium**

The JS-compiled engine will be slower than the WASM version (WASM is 12-13x faster than JS in MoonBit benchmarks). However, MoonBit's JS output is still reportedly **8-25x faster** than hand-written JavaScript, thanks to:
- Tail-call-to-loop optimization
- Constant folding
- Iterator fusion
- Monomorphization

For a tree-walking interpreter, the overhead may be acceptable. The bottleneck is the interpreter loop, which is deeply recursive -- MoonBit's tail-call optimization should help significantly.

### 5.3 Bundle Size

**Risk: Low**

MoonBit's JS output is compact. The 27K LOC MoonBit source should produce a reasonably-sized JS bundle. Dead code elimination is performed at compile time. The `--target js` output is designed to be "npm-publishable."

### 5.4 Async/Event Loop

**Risk: Low**

The engine implements its own event loop with microtask and timer queues. This is application-level code (not relying on the host event loop), so it should work identically on both targets.

### 5.5 `@env.args()` Behavior (Resolved)

**Status: Fixed**

On the JS target, `@env.args()` returns raw `process.argv` (`["node", "script.js", source, ...]`), while on WASM the runtime provides `["program", source, ...]`. This caused the engine to try parsing the script path as JavaScript source.

**Solution:** Backend-specific `args.js.mbt` / `args.wasm.mbt` / `args.wasm-gc.mbt` files each define `get_source_arg() -> String?` with the correct index. See section 3.3.

---

## 6. The Meta-Circular Aspect

Once compiled to JavaScript, this engine becomes **a JavaScript interpreter written in JavaScript** -- a meta-circular interpreter (or more precisely, a *meta-interpreter*, since the host and guest languages are the same).

This opens up interesting possibilities:

1. **Self-interpretation**: Run the JS-compiled engine inside itself (N levels deep)
2. **Differential testing**: Compare the output of our interpreter vs the host V8/SpiderMonkey engine
3. **Browser playground**: Embed the interpreter in a web page for sandboxed JS execution
4. **npm distribution**: Publish as an npm package for sandboxed evaluation

### Self-Interpretation Test

```bash
# Compile to JS
moon build --target js

# The engine interprets itself interpreting "1+1"
# (requires the engine to support enough JS to run its own compiled output)
node main.mjs "$(cat main.mjs)"
# ^ This would require the engine to be much more complete (eval, modules, etc.)
```

True self-interpretation (running the compiled JS through itself) would require the engine to support enough JavaScript features to execute MoonBit's JS output, which includes:
- ES modules or equivalent
- Classes and prototypes
- Closures and higher-order functions
- Map, Set, and other built-in types
- The engine currently passes ~44% of Test262

This is a long-term goal that would improve naturally as Test262 compliance increases.

---

## 7. Recommended Approach

### Phase A: Validate JS Compilation — DONE

1. ~~Run `moon build --target js`~~ — builds with zero errors
2. ~~Run `moon test --target js`~~ — all 639 tests pass
3. ~~Manually test~~ — `node ./target/js/release/build/cmd/main/main.js 'console.log(1 + 2)'` outputs `3`
4. ~~Fix `@env.args()` index offset~~ — solved with backend-specific `args.js.mbt`

### Phase B: Test262 on JS Target — DONE

1. ~~Add CI workflow for JS-compiled engine~~ — `.github/workflows/test262.yml` builds with `moon build --target js` and runs via `node`
2. ~~Run full Test262 suite against JS-compiled engine~~ — 11,316/25,801 passed (43.86%)
3. CI uses `node target/js/release/build/cmd/main/main.js` directly (faster than `moon run`), 4 threads, 90-minute timeout

### Phase C: Distributable Package (Medium Effort)

1. Configure ESM output in `moon.pkg.json`
2. Create a public API surface suitable for `import`
3. Add TypeScript type declarations
4. Test in Node.js and browser environments
5. Consider npm packaging

### Phase D: Self-Interpretation (Long-term)

1. Increase Test262 pass rate toward the features MoonBit's JS output requires
2. Attempt to run the compiled JS output through the interpreter itself
3. Measure and optimize performance of self-interpreted execution

---

## 8. Summary

| Aspect | Status |
|---|---|
| JS target compilation | **Working** |
| Unit tests (639) | **All passing** on both WASM-GC and JS targets |
| FFI calls ported | **0** (none needed) |
| Code changes required | **3 new files** (backend-specific argv), **1 edit** (Error toString) |
| Build command | `moon build --target js` |
| Run command | `node ./target/js/release/build/cmd/main/main.js '<code>'` |
| Test262 pass rate | **43.86%** (11,316/25,801) on JS target |

The codebase's pure-MoonBit, zero-FFI architecture made JS-target compilation straightforward. The only issues encountered were the `process.argv` offset difference (solved with backend-specific files) and Error object toString formatting (solved by checking `class_name`).
