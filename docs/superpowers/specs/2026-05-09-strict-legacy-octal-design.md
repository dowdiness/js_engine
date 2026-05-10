# Strict-mode legacy octal/non-octal-decimal early errors — design

**Date:** 2026-05-09
**Status:** Design — pending Codex round-3 sign-off and writing-plans handoff
**Scope:** PR #91 follow-up #2

## Goal

Implement ES262 §12.8.4.1 (NumericLiteral) and §12.9.4.1 (StringLiteral) static early errors for legacy forms in strict mode:

- **StringLiteral**: `LegacyOctalEscapeSequence` (`\1`–`\7`), `NonOctalDecimalEscapeSequence` (`\0` followed by DecimalDigit, `\8`, `\9`)
- **NumericLiteral**: `LegacyOctalIntegerLiteral` (`0777`), `NonOctalDecimalIntegerLiteral` (`08`, `09`)

Currently the lexer accepts all of these unconditionally and the runtime never errors. This PR makes them `SyntaxError` in strict mode while preserving Annex B compatibility in non-strict.

## Non-goals (deferred follow-ups)

1. **Template literals** (`` `\1` `` in untagged, cooked vs raw separation in tagged). Requires AST surgery: current `TemplateLit`/`TaggedTemplate` stores only `Array[String]` for cooked values; tagged-template `raw` is currently set equal to cooked at `eval_expr.mbt:600`, which is already a spec bug independent of this work. Filing a separate follow-up issue.
2. **Leading-zero fractional/exponent forms** (`01.2`, `01e2`). Needs spec re-read of ES262 §12.8.3 + Annex B §B.1.1 to determine which Annex B production they fall under (or whether they're SyntaxError in all modes). Filing a separate follow-up issue.

## Architecture facts (verified before designing)

The codebase is a tree-walking MoonBit interpreter with this pipeline:

- **Lexer** (`lexer/lexer.mbt`): produces `Array[Token]`. No scope awareness. The legacy-octal-number branch at line 646 already comments *"let the interpreter/parser reject it in strict mode"* — this PR fulfills that deliberate TODO.
- **Parser** (`parser/`): produces AST. Identifies scope boundaries; does not determine strict-mode.
- **Interpreter** (`interpreter/runtime/`): determines strict-mode at scope-entry via `has_use_strict(stmts)` in `interpreter.mbt:229`, scanning the directive prologue (longest leading run of `ExprStmt(StringLit(_, has_escape, _))`) for an unescaped `"use strict"`.

Critically, the codebase **already has a one-shot pre-execution AST walker** for static early errors: `validate_block_early_errors_expr`/`_stmt`/`_pattern` family in `hoisting.mbt` (446–700+), invoked at:

- script entry: `interpreter.mbt:517`
- direct/indirect eval entry: `call.mbt:387`
- (NOT currently invoked at module entry, Function constructor, GeneratorFunction, AsyncFunction — gaps)

This walker tracks `strict_context` as it descends, with `child_strict = enclosing || has_use_strict(body)` at function/arrow/generator/async scope boundaries. Class bodies are validated with `strict_context = true` unconditionally. Crucially, **never-called function bodies ARE pre-walked** by this validator — so this PR does not have the "scope-entry only" limitation I initially mis-assumed.

The integration strategy is therefore: **extend the existing walker, do not create a new one.**

## Design

### 1. Lexer tags tokens with a `LexForm` enum

Add a single field to the `Token` struct (not to TokenKind variants — minimizes match-site churn given the high number of TokenKind consumers):

```moonbit
// token/token.mbt
pub(all) enum LexForm {
  LexNormal
  StringLegacyOctalEscape    // \1-\7, \8, \9, or \0 followed by DecimalDigit
  NumberLegacyOctalInt        // 0777
  NumberNonOctalDecimalInt    // 08, 09
} derive(Eq, Debug)

pub(all) struct Token {
  kind : TokenKind
  loc : Loc
  raw : String
  lex_form : LexForm   // NEW; defaults to LexNormal
} derive(Eq, Debug)
```

`Token::new` factory grows a `lex_form?: LexForm = LexNormal` parameter (MoonBit labelled-with-default), so existing call sites need no change.

### 2. Lexer rules (corrected per Codex round-1)

#### String escape arm at `lexer.mbt:902`

| Source | Current | New behavior |
|---|---|---|
| `\0` not followed by DecimalDigit | NUL | NUL, `lex_form = LexNormal` |
| `\0` followed by `0`–`9` | parsed as legacy octal | parsed as before, `lex_form = StringLegacyOctalEscape` |
| `\1`–`\7` (any context) | parsed as legacy octal | parsed as before, `lex_form = StringLegacyOctalEscape` |
| `\8`, `\9` | currently fall through `_` arm at `lexer.mbt:979`, become `8`/`9` literally (backslash dropped) | NEW explicit arm: produce `8`/`9` literally, `lex_form = StringLegacyOctalEscape` |

Important: a single `lex_form` field on the token captures the entire string — if any escape in the string is legacy-octal, the whole token is tagged. There is no per-position tracking; one bit per string is enough.

#### Number arms at `lexer.mbt:586`–`688`

| Source | Current | New behavior |
|---|---|---|
| `0777` (legacy octal int, line 646) | parsed as octal | parsed as before, `lex_form = NumberLegacyOctalInt` |
| `08`, `09` (line 657 fallthrough to decimal) | parsed as decimal | track via local flag, `lex_form = NumberNonOctalDecimalInt` |
| `01.2`, `01e2` (deferred) | currently parsed by some path — needs spec re-read | OUT OF SCOPE; file follow-up |

### 3. AST changes

```moonbit
// ast/ast.mbt
StringLit(String, Bool, LexForm, @token.Loc)   // value, has_escape (existing), lex_form (NEW), loc
NumberLit(Double, LexForm, @token.Loc)         // value, lex_form (NEW), loc
```

`has_escape` stays where it is (parser derives via `tok.raw.length() != s.length() + 2` at `expr.mbt:693`). It's a separate concern with working code; rewriting is scope creep.

### 4. Parser propagation across all eight AST literal-position sinks

Codex round 2 enumerated eight positions where a literal can appear. All must propagate `lex_form` from the source token:

1. **Primary-expression StringLit** (`expr.mbt:693`) — main path; read from `tok.lex_form`
2. **Primary-expression NumberLit** — same
3. **ObjectLit property key — string** (`expr.mbt:1216`): currently `StringLit(name, false, kloc)`, hardcoding both flags. Read from token.
4. **ObjectLit property key — numeric normalized to string** (`expr.mbt:1220`, `2021`): currently drops `Number(v)` to `StringLit`. Carry `tok.lex_form` to the new `StringLit`.
5. **ClassMember key — string** (`expr.mbt:2017`): same shape as #3
6. **ClassMember key — numeric** (`expr.mbt:2021`): same shape as #4
7. **Object-generator method key** (`expr.mbt:955`): same shape as #3
8. **ObjectPat property key** (`stmt.mbt:867`, `expr_to_pattern` at `expr.mbt:1763`): `PropPat.key` is currently a plain `String` (`ast.mbt:179`). Add `key_lex_form : LexForm` field to `PropPat`.

For positions where the parser builds a synthetic StringLit from an identifier (e.g. shorthand `{x}` → key `"x"`), pass `LexNormal` — identifiers can't carry these escapes.

#### Module-source provenance

`ImportDecl`, `ExportAllDecl`, `ExportNamedDecl(..., Some(source), ...)` carry source strings as plain `String` (`ast.mbt:264`). Add a parallel `source_lex_form : LexForm` field to each.

### 5. Validator integration — extend existing walker

Three classes of edits in `hoisting.mbt`:

#### A. Add leaf cases to `validate_block_early_errors_expr`

```moonbit
StringLit(_, _, lex_form, loc) =>
  validate_strict_lex_form(lex_form, loc, strict_context)
NumberLit(_, lex_form, loc) =>
  validate_strict_lex_form(lex_form, loc, strict_context)
```

Where `validate_strict_lex_form` is:

```moonbit
fn validate_strict_lex_form(
  form : LexForm, loc : Loc, strict_context : Bool
) -> Unit raise Error {
  if !strict_context { return }
  match form {
    LexNormal => ()
    StringLegacyOctalEscape =>
      raise @errors.SyntaxError(
        message="Octal escape sequences are not allowed in strict mode",
      )
    NumberLegacyOctalInt =>
      raise @errors.SyntaxError(
        message="Octal literals are not allowed in strict mode",
      )
    NumberNonOctalDecimalInt =>
      raise @errors.SyntaxError(
        message="Decimals with leading zeros are not allowed in strict mode",
      )
  }
}
```

#### B. Visit currently-unvisited key positions

The existing walker handles `ObjectLit prop.key` (line 663), `Field.computed key + initializer` (with strict=true) — but NOT:

- `ClassMember::Method m.key` (only `m.value` is visited at line 974) → ADD: visit `m.key` with `strict_context=true`
- `ClassMember::Field f.key` when not computed → ADD: visit with `strict_context=true`
- `ObjectPat prop.key` (only `computed_key` and defaults are visited at line 517) → ADD: visit pattern key's lex_form

#### C. Visit currently-unvisited statement positions

`validate_block_early_errors_stmt` (`hoisting.mbt:1000`) currently unwraps only `ExportNamedDecl(Some(decl), ...)` and `ExportDefaultDecl(...)`. ADD cases for:

- `ImportDecl(..., source, ...)` → check `source_lex_form` with `strict_context=true` (modules always strict — but the script-entry walker is invoked with the script's strict context, so we must pass strict explicitly here OR rely on module-loader entry plumbing — see §6)
- `ExportAllDecl(..., source, ...)` → same
- `ExportNamedDecl(_, Some(source), ...)` re-export → same

### 6. New walker entry points

The walker is currently invoked at script entry (`interpreter.mbt:517`) and eval entry (`call.mbt:387`). Add:

| Entry point | File / line | Strict context |
|---|---|---|
| Module loader | `modules.mbt:303` area | Always `true` (modules always strict) |
| `new Function(...)` body | `builtins_function.mbt:358` | `has_use_strict(body)` |
| `new GeneratorFunction(...)` body | `generator.mbt:260` | `has_use_strict(body)` |
| `new AsyncFunction(...)` body | `async.mbt:660` | `has_use_strict(body)` |

### 7. Error messages

Match the spec phrasing approximately, distinguishing the three lex-form cases (V8 distinguishes them too):

- `StringLegacyOctalEscape` → *"Octal escape sequences are not allowed in strict mode"*
- `NumberLegacyOctalInt` → *"Octal literals are not allowed in strict mode"*
- `NumberNonOctalDecimalInt` → *"Decimals with leading zeros are not allowed in strict mode"*

Loc is the literal's loc (preserved through propagation).

## Edge cases — expected behavior matrix

| Case | Expected | Why |
|---|---|---|
| `"use strict"; "\1"` | SyntaxError | strict scope, tagged StringLit |
| `"\1"; "use strict";` | SyntaxError | directive prologue tolerates the tagged literal (has_escape=true → not "use strict"); next directive activates strict; walker then finds tagged literal |
| `function f() { "use strict"; "\1"; }` (outer non-strict) | SyntaxError | inner function strict; walker descends with `child_strict=true` |
| `function f() { "\1"; }` (outer non-strict, no inner directive) | OK | not strict |
| `"use \x20strict"; "\1"` | OK | directive `has_escape=true` disqualifies it; scope not strict |
| `if (false) { "\1" }` (in strict module) | SyntaxError | dead-code branches still validated; static early error |
| `eval("'use strict'; \"\\1\"")` | SyntaxError | eval scope strict; existing call.mbt path validates |
| `"\0"` (bare NUL) | OK in strict | spec exception; lexer must NOT tag |
| `"\08"` | SyntaxError in strict | `\0`+digit → NonOctalDecimalEscape; tagged |
| `"\1"` (bare, no following digit) | SyntaxError in strict | LegacyOctalEscape; tagged ALWAYS |
| `"\8"`, `"\9"` | SyntaxError in strict | NonOctalDecimalEscape; tagged |
| `0` (plain decimal) | OK | not tagged |
| `0777` (in strict) | SyntaxError | NumberLegacyOctalInt |
| `08`, `09` (in strict) | SyntaxError | NumberNonOctalDecimalInt |
| `({ "\1": 0 })` in strict | SyntaxError | ObjectLit prop key carries lex_form |
| `({ 08: 1 })` in strict | SyntaxError | numeric prop key normalized to StringLit, lex_form preserved |
| `class C { "\1"(){} }` | SyntaxError | class body strict; method key visited |
| `class C { 0777(){} }` | SyntaxError | class body strict; numeric method key visited |
| `let { "\1": x } = o` in strict | SyntaxError | ObjectPat key carries lex_form, validator visits |
| `import x from "\1"` | SyntaxError | modules always strict; ImportDecl source carries lex_form, walker visits |
| `new Function('"use strict"; "\\1"')` | SyntaxError | constructor body validated with strict from has_use_strict |
| `` `\1` `` (untagged template) in strict | NOT YET — deferred to follow-up | template AST not rich enough |
| `` tag`\1` `` (tagged template) | NOT YET — deferred | needs raw/cooked split |
| `01.2`, `01e2` | NOT YET — deferred | needs spec re-read |

## Test plan

### Unit tests

- `lexer/lexer_test.mbt` block: per-form token tagging
  - `\0`, `\08`, `\1`–`\7`, `\8`, `\9` → expected `lex_form` on token
  - `0`, `0777`, `08`, `09`, `0o777`, `0b101`, `0x1A` → expected `lex_form`
- `parser/parser_test.mbt` block: AST propagation
  - Property keys in object literals (string and numeric)
  - Class member keys (string and numeric)
  - Object pattern keys
  - Module specifiers in import/export
- `interpreter/interpreter_test.mbt` block: every row of the edge-case matrix above

### test262 cohorts

Per project convention (`docs/RELEASING.md`), use `make test262-report` for baseline + post-change comparison. Per memory note `feedback_test262_reporting_conventions.md`, report per-mode strict + non-strict, both Passed/Executed and Passed/Discovered.

Targeted cohorts:

- `language/literals/string/legacy-non-octal-escape-sequence-*`
- `language/literals/string/legacy-octal-escape-sequence-*`
- `language/literals/numeric/non-octal-decimal-integer*`
- `language/literals/numeric/legacy-octal*`
- `language/expressions/object/method-definition/early-errors-*`
- `language/statements/class/early-errors-*`
- `language/module-code/early-errors-*`

### Regression check

Critical risk: this PR changes the meaning of `\1` in string literals (currently always parsed as legacy octal; now SyntaxError in strict). Some currently-passing tests may have relied on the silent acceptance.

Procedure:
1. Run `make test262-report` on `main` to capture baseline
2. Apply the change
3. Run again
4. Diff the result-set; investigate any test that flipped passing→failing

## Implementation order (writing-plans handoff scope)

This spec describes WHAT and WHY; the implementation plan (next document) will describe HOW and the execution order. At a high level the planner should consider:

1. AST type changes first (define `LexForm`, extend `StringLit`/`NumberLit`/`Property`/`ClassMember`/`ObjectPat`/`ImportDecl`/`ExportAllDecl`/`ExportNamedDecl`)
2. Token struct change
3. Lexer site updates (string escape arm, number legacy-octal branch, number non-octal-decimal fallthrough, new `\8`/`\9` arm)
4. Parser propagation across all eight literal-position sinks
5. Validator extension (leaf cases + key visits + statement cases)
6. New entry points (module loader, three Function constructors)
7. Test additions
8. test262 baseline + diff verification

Each step ends with `moon check` per the Incremental Edit Rule.

## Open questions for round 3 / writing-plans

- The `\8`/`\9` arm needs a precise insertion point in the lexer match; current code routes them through `_` (bytes preserved as `8`/`9`). The new arm must run BEFORE the wildcard.
- Confirm `Token::new` callers can adopt the new optional parameter without churn (search for usages).
- Decide whether `validate_block_early_errors_stmt`'s new ImportDecl/ExportAllDecl/ExportNamedDecl cases should always assume `strict_context=true` (modules always strict) or trust the caller's `strict_context`. The latter is cleaner; the module-loader entry must pass `true`.

---

*Reviewed twice by Codex (rounds 1 & 2). Round 1 caught: wrong `\0` rule, missing existing walker, dropped property-key/class-key/module-source provenance, missing constructor entry points. Round 2 caught: template literals scope hazard, module-source statement-level visits missing, direct-property-key hardcoded zeros, object-pattern key sink, leading-zero exponent/fractional ambiguity.*
