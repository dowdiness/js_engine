# Strict-mode legacy octal — follow-up items

These items were intentionally scoped OUT of the main implementation (`feat/strict-legacy-octal-early-errors`). Filed here for tracking; the user should decide whether to open GH issues or keep as docs.

## Follow-up A: Template literal raw/cooked split + strict legacy octals

**Status:** Pre-existing limitation, exposed but not closed by this PR.

**Symptoms:**
- `` `\1` `` (untagged template literal) in strict mode does NOT raise SyntaxError, but per ES262 §12.9.6.1 it should.
- `` tag`\1` `` (tagged template literal) sets `raw == cooked` at `interpreter/runtime/eval_expr.mbt:600`, but per ES2018+ spec the raw should preserve the literal source bytes (`\1`) and the cooked should be `undefined` for invalid escapes.

**Root cause:** AST stores only `Array[String]` for template chunks (`ast/ast.mbt:127`). Lexer cooks templates immediately and discards raw/provenance (`lexer/lexer.mbt:282`, `:1015`). Fixing requires:

1. AST surgery: split `TemplateLit`/`TaggedTemplate` quasi storage into `Array[(raw : String, cooked : String?)]` or similar.
2. Lexer changes: emit raw alongside cooked; mark cooked=`None` on invalid escapes.
3. Tagged-template runtime fix: use raw for the `raw` array property.
4. Validator extension: walk template quasis and check for legacy-octal escapes when strict.

**Estimated scope:** 500+ LOC across 5+ files. Separate PR-sized.

---

## Follow-up B: Leading-zero fractional/exponent numeric forms

**Status:** Spec resolved 2026-05-10. Implementation pending on branch
`fix/strict-leading-zero-decimal`.

### Spec resolution

ES262 §12.8.3 + Annex B §B.1.1 (sub-clause "Numeric Literals") together
specify three relevant productions:

```
DecimalIntegerLiteral ::          (main spec, with Annex B addition)
  0
  NonZeroDigit
  NonZeroDigit NumericLiteralSeparator? DecimalDigits
  NonOctalDecimalIntegerLiteral   ← Annex B addition; forbidden in strict

LegacyOctalIntegerLiteral ::      (Annex B; forbidden in strict)
  0 OctalDigit
  LegacyOctalIntegerLiteral OctalDigit

NonOctalDecimalIntegerLiteral ::  (Annex B; forbidden in strict)
  0 NonOctalDigit                 (NonOctalDigit ::= 8 | 9)
  LegacyOctalLikeDecimalIntegerLiteral NonOctalDigit
  NonOctalDecimalIntegerLiteral DecimalDigit
```

`DecimalLiteral` allows `DecimalIntegerLiteral . DecimalDigits?` and
`DecimalIntegerLiteral ExponentPart`. Critically, **`LegacyOctalIntegerLiteral`
is NOT a sub-production of `DecimalIntegerLiteral`** — so it cannot be
followed by `.` or `e/E`.

Mapping to the three open questions:

1. **`01.2` is SyntaxError in all modes.** The integer part `01` matches
   only `LegacyOctalIntegerLiteral`. That production cannot have a
   fractional part attached. There is no other production that accepts
   `01` as an integer (it is not `0`, not a `NonZeroDigit`, not a
   `NonZeroDigit NumericLiteralSeparator? DecimalDigits` form, and not a
   `NonOctalDecimalIntegerLiteral` because there is no `8` or `9`).

2. **`01e2` is SyntaxError in all modes**, by the same reasoning.

3. **`0.5` is valid in all modes.** It parses as
   `DecimalIntegerLiteral=0 . DecimalDigits=5` — the main-spec path,
   never Annex B.

4. **`08.1` is valid in sloppy, SyntaxError in strict.** The integer
   part `08` matches `NonOctalDecimalIntegerLiteral`, which Annex B
   adds as a sub-production of `DecimalIntegerLiteral`. So
   `DecimalIntegerLiteral=08 . DecimalDigits=1` parses; the Annex B
   extension itself is forbidden in strict, raising the early error.

5. **`08e2` is valid in sloppy, SyntaxError in strict**, identical
   reasoning.

### V8 verification (Node.js v24.14.1, 2026-05-10)

| Literal | Sloppy | Strict | Spec category |
|---------|--------|--------|---------------|
| `01.2`  | SyntaxError | SyntaxError | LegacyOctal-prefix + `.` (no production) |
| `01e2`  | SyntaxError | SyntaxError | LegacyOctal-prefix + `e` (no production) |
| `0.5`   | `0.5` | `0.5` | DecimalLiteral via `0 . DecimalDigits` |
| `08.1`  | `8.1` | SyntaxError | NonOctalDecimal + `.` (Annex B; sloppy only) |
| `08e2`  | `800` | SyntaxError | NonOctalDecimal + `e` (Annex B; sloppy only) |
| `0.1e2` | `10` | `10` | DecimalLiteral via `0 . DecimalDigits ExponentPart` |
| `00.5`  | SyntaxError | SyntaxError | LegacyOctal-prefix + `.` |
| `001.2` | SyntaxError | SyntaxError | LegacyOctal-prefix + `.` |
| `07.5`  | SyntaxError | SyntaxError | LegacyOctal-prefix + `.` |

V8 matches the spec reading exactly.

### Current lexer behavior (bug surface)

`lexer/lexer.mbt` currently mishandles both buckets:

- **LegacyOctal-prefix forms (`01.2`, `01e2`, etc.):** the legacy-octal
  branch at `lexer/lexer.mbt:670-697` `continue`s immediately after
  emitting the integer token, so `01.2` tokenises as three tokens
  (`Number(1)`, `.`, `Number(2)`) instead of raising a SyntaxError.
- **NonOctalDecimal forms (`08.1`, `08e2`):** PR #98's L1 fix
  defensively cleared `is_non_octal_decimal_int` at the fraction
  (`lexer.mbt:742`) and exponent (`:793`) entry points. This causes
  these literals to be tagged `LexNormal` instead of
  `NumberNonOctalDecimalInt`, so the strict early-error walker never
  rejects them. Empirical V8 says they should error in strict; the
  defensive clearing was wrong and must be reverted.

### Design

Two surgical lexer changes, no AST/walker changes (the validator at
`hoisting.mbt:558-565` already raises the right errors for both
`NumberLegacyOctalInt` and `NumberNonOctalDecimalInt` lex_forms):

1. **Reject LegacyOctal + fraction/exponent in the lexer (all modes).**
   Inside the `if is_legacy_octal { ... }` block at
   `lexer.mbt:670-697`, after the digit-scan loop and before emitting
   the token, peek at the current char.
   - If `.` followed by a `DecimalDigit`, raise SyntaxError (it's a
     fractional continuation, e.g. `01.2`).
   - If `e` or `E`, raise SyntaxError (exponent grammar entry; V8
     rejects `01e2`, `01eFoo`, `01e` alike).
   - If `.` followed by a non-digit (identifier, EOF, etc.), DO NOT
     raise — it's member access (`01.toString()` is valid sloppy code,
     evaluates to `"1"`). Originally the design called for an
     unconditional `.` rejection, but Codex review on PR #99 caught
     the regression: V8 lexes `01.toString` as `Number(1) . toString`.

2. **Stop clearing `is_non_octal_decimal_int` at fraction/exponent
   entry.** Remove the two `is_non_octal_decimal_int = false`
   assignments at `lexer.mbt:742` and `:793` (and the deferred-decision
   comments above them). The lex_form will then carry through to the
   validator, which raises the existing strict-mode error.

### Test coverage

In `lexer_test.mbt`: positive (sloppy) cases for `08.1`, `08e2`,
`0.5`, `0.1e2`; negative cases for `01.2`, `01e2`, `00.5`, `001.2`,
`07.5` (expect SyntaxError from the lexer in any mode).

In `interpreter_test.mbt`: strict-mode `eval` cases proving `08.1` /
`08e2` raise SyntaxError under `"use strict"`.

### Estimated scope

~30 LOC of lexer change, ~50 LOC of tests. PR-sized.

---

## Follow-up C: YieldExpr is not visited by the early-error walker

**Status:** ✅ **CLOSED** by PR #98 (`7e635f9`, merged 2026-05-10). Audit found three walker gaps in one pass: `YieldExpr` argument, `SuperCall` arguments, and `ClassExpr`/`ClassDecl` superclass expression. Codex review surfaced an additional §15.7.1 invariant — class heritage is strict-mode code regardless of surrounding context — which was fixed in the same PR.

---

### Original analysis (preserved for context)

**Status:** Pre-existing limitation, **discovered during Task 13** of this PR.

**Symptoms:**
- A legacy octal inside a `yield` expression body in a strict generator is NOT caught:
  ```js
  "use strict";
  function* g() { yield "\1"; }   // should be SyntaxError; currently silent
  ```
- The Task 13 implementer worked around this by simplifying the GeneratorFunction-constructor test to use plain `"\1"` instead of `yield "\1"`.

**Root cause:** `validate_block_early_errors_expr` in `interpreter/runtime/hoisting.mbt` falls through to the `_ => ()` wildcard for `YieldExpr` and possibly other expression variants (audit needed).

**Fix:** Add `YieldExpr(inner, _) => validate_block_early_errors_expr(inner, strict_context)` arm. Same for any other expression variant that has child expressions but isn't currently visited.

**Estimated scope:** Small (5-10 lines). Should bundle with a walker-completeness audit (any other expression variant currently falling through?).

---

## Decision points for user

1. **GH issues or docs?** Filing as GH issues makes them discoverable in the issue tracker but creates noise. Keeping as docs (this file) is lighter but easier to forget. Recommendation: file Follow-up A and Follow-up C as GH issues (they have clear acceptance criteria), keep Follow-up B in docs until spec questions resolve.

2. **Bundle Follow-up C into the current PR?** It's a small fix and was discovered during this work. Arguments for bundling: cohesion, completeness. Arguments against: scope creep, risk of widening the diff that's already large. Recommendation: keep separate (post-merge follow-up) — the current PR is already broad and the YieldExpr gap is genuinely orthogonal (it would be a problem regardless of legacy-octal handling).

---

## Resolution log

- **Follow-up A (templates)** — filed as GitHub issue #96. Open.
- **Follow-up C (YieldExpr/walker completeness)** — filed as GitHub issue #97, closed by PR #98 (`7e635f9`, 2026-05-10). Scope expanded during implementation: the audit also caught `SuperCall` and `ClassExpr`/`ClassDecl` superclass gaps, plus a Codex-surfaced §15.7.1 invariant on class heritage strictness.
- **Follow-up B (leading-zero fractional/exponent)** — spec resolved 2026-05-10 (see § "Spec resolution" above). Implementation in progress on branch `fix/strict-leading-zero-decimal`.
