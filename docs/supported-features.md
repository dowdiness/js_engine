# Supported Features

Reference: which ES2015+ categories work, which partially work, which are behind an opt-in flag, and which aren't implemented at all. Numbers are from [test262](https://github.com/tc39/test262). For live headline status and in-progress work, see [ROADMAP.md](ROADMAP.md); for the per-commit history of improvements, see [archive/phase-history.md](archive/phase-history.md).

**Overall**: 44,933 / 53,208 test262 tasks passing (**84.4%**) on the full 2026-02-22 run. Strict and non-strict modes are tested for every file.

---

## Per-Category Pass Rates

Top failing categories from the full test262 run (2026-02-22, strict + non-strict):

| Category | Pass | Fail | Rate | Priority |
|----------|------|------|------|----------|
| built-ins/Array | 4,573 | 1,249 | 78.5% | Medium |
| built-ins/Object | 5,642 | 1,102 | 83.7% | Medium |
| language/expressions | 10,024 | 853 | 92.2% | Medium |
| built-ins/TypedArray | 802 | 752 | 51.6% | Medium |
| language/statements | 7,615 | 647 | 92.2% | Medium |
| built-ins/RegExp | 1,102 | 586 | 65.3% | Medium |
| annexB/language | 404 | 439 | 47.9% | Medium |
| built-ins/Proxy | 224 | 310 | 41.9% | Medium |
| built-ins/String | 2,160 | 257 | 89.4% | Medium |
| built-ins/TypedArrayConstructors | 489 | 228 | 68.2% | Medium |
| built-ins/Function | 610 | 182 | 77.0% | Medium |
| language/eval-code | 283 | 169 | 62.6% | Medium |
| built-ins/Uint8Array | 16 | 120 | 11.8% | Medium |
| language/module-code | 193 | 119 | 61.9% | Medium |
| built-ins/Promise | 1,162 | 98 | 92.2% | Medium |
| built-ins/Reflect | 210 | 96 | 68.6% | Medium |
| built-ins/JSON | 180 | 90 | 66.7% | Medium |
| annexB/built-ins | 354 | 86 | 80.5% | Low (--annex-b) |
| language/import | 17 | 82 | 17.2% | Medium |
| language/identifiers | 335 | 80 | 80.7% | Medium |
| language/literals | 581 | 60 | 90.6% | Medium |
| built-ins/DataView | 700 | 54 | 92.8% | Medium |
| built-ins/Date | 1,112 | 54 | 95.4% | ✅ Done (8C) |
| built-ins/GeneratorPrototype | 78 | 44 | 63.9% | Medium |
| built-ins/Number | 640 | 30 | 95.5% | ✅ Done |
| built-ins/Map | 365 | 24 | 93.8% | Medium |
| built-ins/WeakMap | 257 | 22 | 92.1% | Medium |
| built-ins/Math | 626 | 18 | 97.2% | ✅ Done |
| built-ins/Set | 370 | 14 | 96.4% | ✅ Done |
| built-ins/WeakSet | 156 | 12 | 92.9% | Medium |
| built-ins/Boolean | 99 | 0 | 100.0% | ✅ Done |
| built-ins/Infinity | 10 | 0 | 100.0% | ✅ Done |
| built-ins/NaN | 10 | 0 | 100.0% | ✅ Done |
| built-ins/undefined | 12 | 0 | 100.0% | ✅ Done |
| built-ins/isFinite | 30 | 0 | 100.0% | ✅ Done |
| built-ins/isNaN | 30 | 0 | 100.0% | ✅ Done |
| built-ins/ThrowTypeError | 25 | 1 | 96.2% | ✅ Done (P24, was 0.0%) |
| language/line-terminators | 82 | 0 | 100.0% | ✅ Done (P24, was 68.3%) |
| language/block-scope | 215 | 0 | 100.0% | ✅ Done |
| language/white-space | 134 | 0 | 100.0% | ✅ Done (P14, P23) |
| language/asi | 204 | 0 | 100.0% | ✅ Done |
| language/keywords | 50 | 0 | 100.0% | ✅ Done |
| language/comments | 46 | 0 | 100.0% | ✅ Done |
| language/punctuators | 22 | 0 | 100.0% | ✅ Done |

## High-Performing Categories (>90% pass rate, strict + non-strict)

| Category | Pass | Fail | Rate |
|----------|------|------|------|
| built-ins/Boolean | 99 | 0 | 100.0% |
| built-ins/Infinity | 10 | 0 | 100.0% |
| built-ins/NaN | 10 | 0 | 100.0% |
| built-ins/eval | 18 | 0 | 100.0% |
| built-ins/isFinite | 30 | 0 | 100.0% |
| built-ins/isNaN | 30 | 0 | 100.0% |
| built-ins/undefined | 12 | 0 | 100.0% |
| language/asi | 204 | 0 | 100.0% |
| language/block-scope | 215 | 0 | 100.0% |
| language/comments | 46 | 0 | 100.0% |
| language/export | 3 | 0 | 100.0% |
| language/identifier-resolution | 20 | 0 | 100.0% |
| language/keywords | 50 | 0 | 100.0% |
| language/line-terminators | 82 | 0 | 100.0% |
| language/punctuators | 22 | 0 | 100.0% |
| language/source-text | 2 | 0 | 100.0% |
| language/white-space | 134 | 0 | 100.0% |
| language/function-code | 277 | 4 | 98.6% |
| language/future-reserved-words | 84 | 1 | 98.8% |
| language/directive-prologue | 61 | 1 | 98.4% |
| built-ins/parseInt | 108 | 2 | 98.2% |
| built-ins/parseFloat | 106 | 2 | 98.1% |
| built-ins/decodeURI | 106 | 2 | 98.1% |
| built-ins/NativeErrors | 172 | 4 | 97.7% |
| built-ins/Math | 626 | 18 | 97.2% |
| built-ins/Set | 370 | 14 | 96.4% |
| built-ins/decodeURIComponent | 106 | 4 | 96.4% |
| built-ins/ThrowTypeError | 25 | 1 | 96.2% |
| language/reserved-words | 51 | 2 | 96.2% |
| built-ins/Date | 1,112 | 54 | 95.4% |
| built-ins/Number | 640 | 30 | 95.5% |
| language/types | 198 | 9 | 95.7% |
| built-ins/Map | 365 | 24 | 93.8% |
| built-ins/global | 52 | 4 | 92.9% |
| built-ins/WeakSet | 156 | 12 | 92.9% |
| built-ins/DataView | 700 | 54 | 92.8% |
| built-ins/Promise | 1,162 | 98 | 92.2% |
| language/expressions | 10,024 | 853 | 92.2% |
| language/statements | 7,615 | 647 | 92.2% |
| built-ins/WeakMap | 257 | 22 | 92.1% |
| built-ins/Symbol | 138 | 12 | 92.0% |
| language/literals | 581 | 60 | 90.6% |

---

## Annex B / Legacy Features (`--annex-b` flag)

**Status**: In progress. Deprecated and legacy ECMAScript features are gated behind the `--annex-b` CLI flag, suppressed by default. Phase 21 added `annex_b~` gating to `get_string_method` for HTML string methods.

**Rationale**: Annex B features are deprecated, banned in strict mode, and irrelevant to modern JavaScript. Implementing them unconditionally adds complexity and pollutes the core engine. Gating them behind a flag keeps the default engine clean while allowing opt-in for legacy compatibility testing.

### Design

```bash
# Default: strict-modern behavior, no Annex B
node engine.js 'with ({x: 1}) { print(x) }'
# => SyntaxError: 'with' statement is not supported

# Opt-in: enable Annex B legacy features
node engine.js --annex-b 'with ({x: 1}) { print(x) }'
# => 1
```

- **CLI**: `--annex-b` flag parsed in `cmd/main/main.mbt`, passed to interpreter as `self.annex_b : Bool`
- **Test262 runner**: `test262-runner.py` passes `--annex-b` for tests in `annexB/` directories
- **Metadata parsing**: `test262-runner.py` and `test262-analyze.py` share `test262_utils.py` and run with or without PyYAML installed
- **Feature gating**: Each Annex B feature checks `self.annex_b` before enabling legacy behavior

### Features to gate behind `--annex-b`

| Feature | Tests | Notes |
|---------|-------|-------|
| `with` statement | — | ✅ Done (P22). Object environment record, SyntaxError in strict mode |
| Legacy octal literals (`0777`) | ~30 | `0`-prefixed octals in sloppy mode |
| Legacy octal escapes (`\077`) | ~20 | Octal escape sequences in strings |
| `__proto__` property | ~40 | `Object.prototype.__proto__` getter/setter |
| HTML comment syntax (`<!--`, `-->`) | ~10 | HTML-style comments in script code |
| `String.prototype.{anchor,big,blink,...}` | ~58 fail | ✅ Gated in P21. HTML wrapper methods (`"str".bold()` → `"<b>str</b>"`) |
| `RegExp.prototype.compile` | ~10 | Legacy RegExp recompilation |
| `escape()`/`unescape()` | ~20 | Legacy encoding functions |
| Block-level function declarations (sloppy) | ~106 fail | ✅ Mostly done (P22). `annexB/language` 38.1% → 87.0%; remaining edge cases |

**Estimated total**: ~164 tests currently failing due to missing/incomplete Annex B features (was ~844 pre-P22)

### Priority

Low. These features are not required for modern JavaScript usage. Implement only after core ES2015+ compliance targets are met (>85% pass rate on non-Annex B tests).

---

## Skipped Features (~20,497 tests)

Features whose test262 tests are excluded from the pass/fail counts above. These are not currently implemented.

| Feature | Skipped | Notes |
|---------|---------|-------|
| Temporal | 4,482 | TC39 Stage 3 date/time API |
| async-iteration | 3,731 | Requires async generators |
| class-methods-private | 1,304 | #privateMethod |
| BigInt | 1,250 | Arbitrary precision integers |
| class-static-methods-private | 1,133 | static #method |
| class-fields-public | 723 | Public field declarations |
| regexp-unicode-property | 679 | Unicode property escapes |
| module | 422 | import/export implemented; 338 in module dirs + 84 module-flagged tests in other dirs |
| generators | — | ✅ No longer skipped (implemented in Phase 8) |
| Proxy/Reflect | — | ✅ No longer skipped (implemented in Phase 15) |
| TypedArray/ArrayBuffer/DataView | — | ✅ No longer skipped (implemented in Phase 16) |
