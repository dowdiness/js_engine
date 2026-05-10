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

**Status:** Spec-corner case; needs careful re-read of ES262 §12.8.3 + Annex B §B.1.1 before designing.

**Symptoms:**
- `01.2`, `01e2`, `0.1e2` — currently parsed (or not) inconsistently. The legacy-octal-int branch at `lexer/lexer.mbt:645` returns early before the decimal/exponent scanner runs.

**Open questions:**
1. Is `01.2` a valid `DecimalLiteral`, `LegacyOctalIntegerLiteral` (no, no fraction), `NonOctalDecimalIntegerLiteral` (no, no 8/9), or `SyntaxError` in all modes?
2. Is `01e2` covered by NonOctalDecimalIntegerLiteral (Annex B §B.1.1) which permits exponents on leading-zero forms?
3. Should `0.5` (single-zero followed by fraction) be rejected in strict? Currently passes; spec arguably allows it as DecimalLiteral.

**Action:** Re-read spec carefully, write small test cases, decide tagging + error policy. Likely small PR (~50 LOC) once the spec questions are resolved.

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
- **Follow-up B (leading-zero fractional/exponent)** — still open in this doc; spec re-read pending.
