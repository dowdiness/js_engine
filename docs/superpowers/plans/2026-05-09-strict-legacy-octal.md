# Strict-mode legacy octal/non-octal-decimal early errors — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `\1`-`\7`/`\8`/`\9`/`\0+digit` in StringLiterals and `0777`/`08`/`09` in NumericLiterals raise `SyntaxError` in strict-mode code, while preserving Annex B compatibility in non-strict.

**Architecture:** Lexer tags affected tokens with a `LexForm` enum field; parser propagates the tag through every AST literal-position sink (8 sites: primary expr, ObjectLit prop key, ClassMember key, ObjectPat prop key, 4 import/export source fields); the existing one-shot pre-execution walker `validate_block_early_errors_*` (`hoisting.mbt:446+`) is extended to raise on tagged leaves when `strict_context=true`. Four new walker entry points cover module-loader and the three Function-family constructors.

**Tech Stack:** MoonBit interpreter, `moon` toolchain, test262 conformance suite.

**Spec:** [docs/superpowers/specs/2026-05-09-strict-legacy-octal-design.md](../specs/2026-05-09-strict-legacy-octal-design.md)

**Out of scope (deferred follow-ups):** template literals (require AST raw/cooked split), leading-zero fractional/exponent forms (`01.2`, `01e2`).

---

## Task 0: Capture test262 baseline

**Files:** none modified — pre-PR snapshot only.

- [ ] **Step 1: Snapshot CI pass rates from latest main run**

Run: `gh run list --workflow=test262.yml --branch=main --limit=1 --json databaseId,conclusion,headSha`
Note the run ID and head SHA.

- [ ] **Step 2: Generate baseline report**

Run: `make test262-report > /tmp/test262-baseline-$(git rev-parse --short HEAD).txt`
Expected: paste-ready block with strict + non-strict P/E and P/D rates.

- [ ] **Step 3: Save baseline alongside the plan**

Run: `cp /tmp/test262-baseline-*.txt docs/superpowers/plans/2026-05-09-strict-legacy-octal-baseline.txt`

- [ ] **Step 4: Commit baseline**

```bash
git add docs/superpowers/plans/2026-05-09-strict-legacy-octal-baseline.txt
git commit -m "$(cat <<'EOF'
docs(plan): capture test262 baseline before legacy-octal work

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 1: Add `LexForm` enum and `Token.lex_form` field (additive)

**Files:**
- Modify: `token/token.mbt:1-173`
- Test: `token/token_test.mbt`

This is purely additive — every existing `Token` construction continues to work because the new field has a default.

- [ ] **Step 1: Add `LexForm` enum after the `Loc` block**

Insert in `token/token.mbt` after line 16 (`pub fn Loc::default()`):

```moonbit
///|
pub(all) enum LexForm {
  LexNormal
  StringLegacyOctalEscape
  NumberLegacyOctalInt
  NumberNonOctalDecimalInt
} derive(Eq, Debug)

///|
pub impl Show for LexForm with output(self, logger) {
  Debug::to_repr(self).output(logger)
}
```

- [ ] **Step 2: Add `lex_form` field to `Token` struct**

Modify `token/token.mbt:153-157` from:

```moonbit
pub(all) struct Token {
  kind : TokenKind
  loc : Loc
  raw : String
} derive(Eq, Debug)
```

to:

```moonbit
pub(all) struct Token {
  kind : TokenKind
  loc : Loc
  raw : String
  lex_form : LexForm
} derive(Eq, Debug)
```

- [ ] **Step 3: Update `Token::new` factory to accept optional `lex_form`**

Modify `token/token.mbt:165-167`:

```moonbit
pub fn Token::new(
  kind : TokenKind,
  loc : Loc,
  raw : String,
  lex_form? : LexForm = LexNormal,
) -> Token {
  { kind, loc, raw, lex_form }
}
```

- [ ] **Step 4: Update `Token::eof`**

Modify `token/token.mbt:170-172`:

```moonbit
pub fn Token::eof(loc : Loc) -> Token {
  { kind: EOF, loc, raw: "", lex_form: LexNormal }
}
```

- [ ] **Step 5: Run `moon check`**

Run: `moon check`
Expected: PASS. If any record-pattern construction (`{ kind, loc, raw }` literal) fails, add `lex_form: LexNormal` there. Search: `grep -rn '{ kind:' --include="*.mbt"` and `grep -rn '{ kind,' --include="*.mbt"` in `lexer/` to find direct record constructions.

- [ ] **Step 6: Run existing tests**

Run: `moon test`
Expected: all PASS.

- [ ] **Step 7: Run `moon info` and `moon fmt`**

Run: `moon info && moon fmt`
Expected: `.mbti` updated to reflect new public surface; `git diff token/pkg.generated.mbti` shows `LexForm` and the new struct field.

- [ ] **Step 8: Commit**

```bash
git add token/
git commit -m "$(cat <<'EOF'
token: add LexForm enum and Token.lex_form field

Additive — existing Token::new callers compile unchanged via default
value. Field will be populated by the lexer in subsequent commits and
consumed by the strict-mode validator.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Tag string escape lexer arms

**Files:**
- Modify: `lexer/lexer.mbt:830-980`
- Test: `lexer/lexer_test.mbt`

Lexer detects legacy-octal escape sequences; emits `String_` token with `lex_form = StringLegacyOctalEscape`.

- [ ] **Step 1: Write failing lexer tests**

Append to `lexer/lexer_test.mbt`:

```moonbit
///|
test "legacy octal escape: bare digit tags token" {
  let toks = @lexer.tokenize("\"\\1\"")
  inspect(toks[0].lex_form, content="StringLegacyOctalEscape")
}

///|
test "legacy octal escape: \\7 tags" {
  let toks = @lexer.tokenize("\"\\7\"")
  inspect(toks[0].lex_form, content="StringLegacyOctalEscape")
}

///|
test "non-octal decimal escape: \\8 tags" {
  let toks = @lexer.tokenize("\"\\8\"")
  inspect(toks[0].lex_form, content="StringLegacyOctalEscape")
}

///|
test "non-octal decimal escape: \\9 tags" {
  let toks = @lexer.tokenize("\"\\9\"")
  inspect(toks[0].lex_form, content="StringLegacyOctalEscape")
}

///|
test "bare \\0 (no following digit) does NOT tag" {
  let toks = @lexer.tokenize("\"\\0\"")
  inspect(toks[0].lex_form, content="LexNormal")
}

///|
test "bare \\0 followed by digit DOES tag" {
  let toks = @lexer.tokenize("\"\\08\"")
  inspect(toks[0].lex_form, content="StringLegacyOctalEscape")
}

///|
test "plain string is LexNormal" {
  let toks = @lexer.tokenize("\"hello\"")
  inspect(toks[0].lex_form, content="LexNormal")
}

///|
test "string with \\n escape is LexNormal" {
  let toks = @lexer.tokenize("\"a\\nb\"")
  inspect(toks[0].lex_form, content="LexNormal")
}
```

- [ ] **Step 2: Run tests, expect FAIL**

Run: `moon test --package lexer`
Expected: all 8 new tests FAIL (lex_form is currently always LexNormal because the lexer doesn't tag).

- [ ] **Step 3: Add a local `has_legacy_octal_escape` flag in the string lexing loop**

Locate the string-lex block at `lexer/lexer.mbt:884` (`if c == '"' || c == '\'' {`). Just before the buffer is created (after `let buf = StringBuilder::new()`), add:

```moonbit
let mut has_legacy_octal_escape = false
```

- [ ] **Step 4: Tag in the `'0'..'7'` arm conditionally**

In the existing match arm at `lexer.mbt:902` (`'0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' =>`), modify the body to set the flag. The current bare-`\0`-NUL exception is at line 308 (the comment `// \0 is NUL only when NOT followed by a decimal digit (ES spec)`); refer to that logic.

Inside that match arm, after computing `let next_is_octal = ...`, add:

```moonbit
// Tag this string token with legacy-octal-escape provenance.
// \0 followed by a non-decimal-digit is the spec-allowed exception (NUL).
// All other cases (\\1..\\7 always; \\0 followed by 0-9) are legacy.
if esc == '0' {
  let next_is_decimal_digit = offset + 1 < len &&
    char_at(offset + 1) >= '0' &&
    char_at(offset + 1) <= '9'
  if next_is_decimal_digit {
    has_legacy_octal_escape = true
  }
} else {
  // \\1..\\7 always tag
  has_legacy_octal_escape = true
}
```

Place this block AT THE TOP of the arm body, before the existing `let d1 = ...` line.

- [ ] **Step 5: Add explicit `'8' | '9'` arm BEFORE the wildcard `_ =>`**

Locate the wildcard match arm at `lexer.mbt:979` (`_ =>` for the unknown-escape case). Insert new arms BEFORE it:

```moonbit
'8' | '9' => {
  // NonOctalDecimalEscapeSequence (Annex B). In non-strict, the backslash
  // is dropped and the digit is preserved. In strict, this is a SyntaxError
  // (handled by the strict-mode validator via the lex_form tag).
  has_legacy_octal_escape = true
  buf.write_char(esc)
}
```

- [ ] **Step 6: Pass `has_legacy_octal_escape` when emitting the token**

Locate the token-push site for strings (around `lexer.mbt:875` where it picks `kind`). After the loop ends and the token kind is determined, modify the token construction to pass `lex_form`:

Find the existing pattern (search for `tokens.push({ kind` near the string-end logic). Update to:

```moonbit
let lex_form : @token.LexForm = if has_legacy_octal_escape {
  StringLegacyOctalEscape
} else {
  LexNormal
}
tokens.push({ kind, loc, raw, lex_form })
```

If the pattern uses `Token::new`, pass `lex_form~` parameter instead.

- [ ] **Step 7: Run tests**

Run: `moon test --package lexer`
Expected: all 8 string-escape tests PASS.

- [ ] **Step 8: Run `moon check && moon test` (full suite)**

Run: `moon check && moon test`
Expected: full PASS — no regressions.

- [ ] **Step 9: Commit**

```bash
git add lexer/lexer.mbt lexer/lexer_test.mbt
git commit -m "$(cat <<'EOF'
lexer: tag legacy octal/non-octal-decimal string escapes

- \\1-\\7 always tag with StringLegacyOctalEscape
- \\0 tags only when followed by a decimal digit (NUL exception)
- \\8/\\9 explicit arm tags and emits the digit literally (Annex B)

The tag rides on Token.lex_form and will be consumed by the strict-mode
validator. Behavior in non-strict code is unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Tag numeric legacy-octal-int and non-octal-decimal-int lexer arms

**Files:**
- Modify: `lexer/lexer.mbt:580-690`
- Test: `lexer/lexer_test.mbt`

- [ ] **Step 1: Write failing tests**

Append to `lexer/lexer_test.mbt`:

```moonbit
///|
test "numeric 0777 tags as NumberLegacyOctalInt" {
  let toks = @lexer.tokenize("0777")
  inspect(toks[0].lex_form, content="NumberLegacyOctalInt")
}

///|
test "numeric 08 tags as NumberNonOctalDecimalInt" {
  let toks = @lexer.tokenize("08")
  inspect(toks[0].lex_form, content="NumberNonOctalDecimalInt")
}

///|
test "numeric 09 tags as NumberNonOctalDecimalInt" {
  let toks = @lexer.tokenize("09")
  inspect(toks[0].lex_form, content="NumberNonOctalDecimalInt")
}

///|
test "numeric 0o777 (modern octal) is LexNormal" {
  let toks = @lexer.tokenize("0o777")
  inspect(toks[0].lex_form, content="LexNormal")
}

///|
test "plain numeric 100 is LexNormal" {
  let toks = @lexer.tokenize("100")
  inspect(toks[0].lex_form, content="LexNormal")
}

///|
test "numeric 0 is LexNormal" {
  let toks = @lexer.tokenize("0")
  inspect(toks[0].lex_form, content="LexNormal")
}
```

- [ ] **Step 2: Run, expect FAIL**

Run: `moon test --package lexer`
Expected: 6 new tests FAIL.

- [ ] **Step 3: Tag legacy-octal-int branch**

Locate `lexer.mbt:664` (the `if is_legacy_octal {` block). Find the `tokens.push({ kind: Number(value), loc, raw })` inside that block (around line 684) and modify to:

```moonbit
tokens.push({ kind: Number(value), loc, raw, lex_form: NumberLegacyOctalInt })
```

- [ ] **Step 4: Track non-octal-decimal-int with a flag**

At `lexer.mbt:649`, before `let mut is_legacy_octal = true`, add:

```moonbit
let mut is_non_octal_decimal_int = false
```

At `lexer.mbt:657-658` (the "Contains 8 or 9, not octal - treat as decimal" branch), modify to:

```moonbit
} else if pch == '8' || pch == '9' {
  // Contains 8 or 9, not octal - treat as decimal (Annex B NonOctalDecimalIntegerLiteral)
  is_legacy_octal = false
  is_non_octal_decimal_int = true
  break
}
```

- [ ] **Step 5: Tag at the decimal token-push site**

The decimal scanner runs at `lexer.mbt:689+` ("Decimal number with optional numeric separators") for both regular decimals and the fallthrough from the non-octal-decimal case. Find the token-push at the end of that block (search for `tokens.push({ kind: Number` after line 689). Modify to:

```moonbit
let lex_form : @token.LexForm = if is_non_octal_decimal_int {
  NumberNonOctalDecimalInt
} else {
  LexNormal
}
tokens.push({ kind: Number(value), loc, raw, lex_form })
```

Note: `is_non_octal_decimal_int` is only set inside the `c == '0' && offset + 1 < len` block at line 586, so for plain decimals (e.g. `100`) it stays `false`. Verify scope by checking that the variable is declared OUTSIDE the leading-zero block (Step 4 says place it inside the leading-zero block — actually that's a bug, fix: declare outside).

- [ ] **Step 6: Move declaration to enclosing scope**

The variable `is_non_octal_decimal_int` must be visible at the decimal-token-push site, which is OUTSIDE the leading-zero block. Move the `let mut is_non_octal_decimal_int = false` declaration to BEFORE the `if c == '0' && offset + 1 < len` block at line 586.

- [ ] **Step 7: Run tests**

Run: `moon test --package lexer`
Expected: all 6 numeric tests PASS.

- [ ] **Step 8: Run full check + tests**

Run: `moon check && moon test`
Expected: full PASS.

- [ ] **Step 9: Commit**

```bash
git add lexer/lexer.mbt lexer/lexer_test.mbt
git commit -m "$(cat <<'EOF'
lexer: tag legacy-octal and non-octal-decimal numeric literals

- 0777 tags as NumberLegacyOctalInt
- 08, 09 tags as NumberNonOctalDecimalInt
- 0oNNN, 0xNN, 0bNN, plain decimals are LexNormal

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Extend `StringLit` AST node with `lex_form`

**Files:**
- Modify: `ast/ast.mbt:103`
- Modify: `parser/expr.mbt` (multiple sites)
- Modify: `interpreter/runtime/*.mbt` (every match on StringLit — find via grep)
- Test: `parser/parser_test.mbt`

This is a coordinated type change that breaks compilation everywhere `StringLit(_, _, _)` is matched until updated. Plan to do it in one task.

- [ ] **Step 1: Grep for every existing StringLit usage**

Run: `grep -rn 'StringLit(' --include="*.mbt" | grep -v '_build\|target' > /tmp/stringlit-sites.txt`
Inspect: `wc -l /tmp/stringlit-sites.txt` — expect ~50-80 sites. Read top 20 to understand patterns.

- [ ] **Step 2: Modify the AST type**

Change `ast/ast.mbt:103`:

```moonbit
StringLit(String, Bool, @token.LexForm, @token.Loc) // value, has_escape, lex_form, loc
```

- [ ] **Step 3: Run `moon check` to enumerate breakage**

Run: `moon check 2>&1 | tee /tmp/stringlit-errors.txt`
Expected: dozens of errors at `StringLit(...)` constructions and `StringLit(...)` patterns. Each is a 1-line fix.

- [ ] **Step 4: Update primary-expression parser (`expr.mbt:690-695`)**

Modify:

```moonbit
String_(s) => {
  self.pos += 1
  let has_escape = tok.raw.length() != s.length() + 2
  StringLit(s, has_escape, tok.lex_form, tok.loc)
}
```

- [ ] **Step 5: Update object-generator-method key (`expr.mbt:953-957`)**

`expr.mbt:953` (Ident shorthand → key string): pass `LexNormal`. `expr.mbt:955-957` (String_ key): propagate `tok.lex_form`. Modify the `String_(s)` arm to:

```moonbit
String_(s) => {
  let tok2 = self.advance()
  (StringLit(s, false, tok2.lex_form, tok2.loc), s, false)
}
```

And update the `Ident(name)` arm to:

```moonbit
Ident(name) => {
  let kloc = self.advance().loc
  (StringLit(name, false, LexNormal, kloc), name, false)
}
```

For the `Number(n)` arm at `expr.mbt:959-967`: capture the token first to read its `lex_form`:

```moonbit
Number(n) => {
  let tok2 = self.advance()
  let kloc = tok2.loc
  let i = n.to_int()
  let name = if i.to_double() == n {
    i.to_string()
  } else {
    n.to_string()
  }
  (StringLit(name, false, tok2.lex_form, kloc), name, false)
}
```

- [ ] **Step 6: Update object-literal property-key parser (`expr.mbt:1212-1228`)**

Modify each match arm to capture the token and propagate `lex_form`:

```moonbit
let (key_expr, key_name, computed, is_ident_key) : (
  @ast.Expr,
  String,
  Bool,
  Bool,
) = match self.peek_kind() {
  Ident(name) => {
    let kloc = self.advance().loc
    (StringLit(name, false, @token.LexForm::LexNormal, kloc), name, false, true)
  }
  String_(s) => {
    let tok2 = self.advance()
    (StringLit(s, false, tok2.lex_form, tok2.loc), s, false, false)
  }
  Number(n) => {
    let tok2 = self.advance()
    let kloc = tok2.loc
    let i = n.to_int()
    let name = if i.to_double() == n {
      i.to_string()
    } else {
      n.to_string()
    }
    (StringLit(name, false, tok2.lex_form, kloc), name, false, false)
  }
  LBracket => {
    let _ = self.advance()
    let expr = self.parse_assignment()
    let _ = self.expect(RBracket)
    (expr, "", true, false)
  }
  // ... other arms unchanged
}
```

- [ ] **Step 7: Update class-member-key parser (`expr.mbt:2013-2025`)**

Apply the analogous transformation:

```moonbit
let (key_expr, computed) : (@ast.Expr, Bool) = match self.peek_kind() {
  Ident(name) => {
    let kloc = self.advance().loc
    (StringLit(name, false, @token.LexForm::LexNormal, kloc), false)
  }
  String_(s) => {
    let tok2 = self.advance()
    (StringLit(s, false, tok2.lex_form, tok2.loc), false)
  }
  Number(n) => {
    let tok2 = self.advance()
    let kloc = tok2.loc
    let i = n.to_int()
    let name = if i.to_double() == n { i.to_string() } else { n.to_string() }
    (StringLit(name, false, tok2.lex_form, kloc), false)
  }
  LBracket => {
    let _ = self.advance()
    let expr = self.parse_assignment()
    let _ = self.expect(RBracket)
    (expr, true)
  }
  // ... other arms unchanged
}
```

- [ ] **Step 8: Update template-literal StringLit construction (`expr.mbt:789`)**

The comment says template literals never count as directives. Pass `LexNormal`:

```moonbit
StringLit(s, true, @token.LexForm::LexNormal, tok.loc)
```

- [ ] **Step 9: Update remaining StringLit construction sites**

For every site found in Step 1's output, add `LexNormal` (or propagate `tok.lex_form` for the rare site that should). Use this rule:

- Sites that take a `String_` token → propagate `tok.lex_form`
- Sites that take an `Ident` token → `LexNormal`
- Sites that synthesize a key string (e.g. `expr.mbt:1289` shorthand) → `LexNormal`

- [ ] **Step 10: Update every match site**

For every `StringLit(s, has_escape, loc)` pattern, change to `StringLit(s, has_escape, _, loc)` if not using lex_form, or `StringLit(s, has_escape, lex_form, loc)` if using.

Search again: `grep -rn 'StringLit(' --include="*.mbt" | grep -v '_build\|target'` and update remaining match patterns.

- [ ] **Step 11: Update `has_use_strict` in `interpreter.mbt:235`**

Modify:

```moonbit
ExprStmt(StringLit(s, has_escape, _, _), _) =>
  if s == "use strict" && !has_escape {
    return true
  }
```

- [ ] **Step 12: Run `moon check` until clean**

Run: `moon check`
Expected: PASS. Iterate Step 9-10 until no errors remain.

- [ ] **Step 13: Add propagation tests**

Append to `parser/parser_test.mbt`:

```moonbit
///|
test "parser propagates lex_form to StringLit" {
  let toks = @lexer.tokenize("\"\\1\"")
  let mut p = @parser.Parser::new(toks)
  let expr = p.parse_assignment()
  match expr {
    StringLit(_, _, lex_form, _) =>
      inspect(lex_form, content="StringLegacyOctalEscape")
    _ => fail("expected StringLit")
  }
}

///|
test "parser propagates lex_form for object property key" {
  let src = "({ \"\\1\": 0 })"
  let toks = @lexer.tokenize(src)
  let mut p = @parser.Parser::new(toks)
  let expr = p.parse_assignment()
  // Expect ObjectLit with one property whose key is StringLit tagged
  match expr {
    Grouping(ObjectLit(props, _), _) =>
      match props[0].key {
        StringLit(_, _, lex_form, _) =>
          inspect(lex_form, content="StringLegacyOctalEscape")
        _ => fail("expected StringLit key")
      }
    _ => fail("expected grouped ObjectLit")
  }
}
```

- [ ] **Step 14: Run tests**

Run: `moon test`
Expected: all PASS.

- [ ] **Step 15: Run `moon info && moon fmt`, check `.mbti`**

Run: `moon info && moon fmt && git diff ast/pkg.generated.mbti parser/pkg.generated.mbti`
Verify: AST signature changed to include LexForm.

- [ ] **Step 16: Commit**

```bash
git add ast/ parser/ interpreter/
git commit -m "$(cat <<'EOF'
ast,parser: propagate lex_form to StringLit AST nodes

StringLit now carries (value, has_escape, lex_form, loc). Parser
propagates from the source token at every literal-position sink:
primary expression, object/class/object-generator method keys for both
string and numeric (number-to-string normalized) keys.

Synthetic StringLit constructions (identifier-derived keys, template
literals, shorthand bindings) pass LexNormal.

Validator integration in subsequent commit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Extend `NumberLit` AST node with `lex_form`

**Files:**
- Modify: `ast/ast.mbt:102`
- Modify: `parser/expr.mbt:686-689`
- Modify: every NumberLit match site
- Test: `parser/parser_test.mbt`

Same shape as Task 4, smaller blast radius (NumberLit is matched in fewer places than StringLit).

- [ ] **Step 1: Grep for usages**

Run: `grep -rn 'NumberLit(' --include="*.mbt" | grep -v '_build\|target' > /tmp/numlit-sites.txt`

- [ ] **Step 2: Modify AST**

Change `ast/ast.mbt:102`:

```moonbit
NumberLit(Double, @token.LexForm, @token.Loc)
```

- [ ] **Step 3: Update primary-expression parser (`expr.mbt:686-689`)**

```moonbit
Number(n) => {
  self.pos += 1
  NumberLit(n, tok.lex_form, tok.loc)
}
```

- [ ] **Step 4: Update every match site**

Run `moon check`, fix each `NumberLit(n, loc)` → `NumberLit(n, _, loc)` (or `NumberLit(n, lex_form, loc)` where used).

- [ ] **Step 5: Add propagation test**

Append to `parser/parser_test.mbt`:

```moonbit
///|
test "parser propagates lex_form to NumberLit" {
  let toks = @lexer.tokenize("0777")
  let mut p = @parser.Parser::new(toks)
  let expr = p.parse_assignment()
  match expr {
    NumberLit(_, lex_form, _) =>
      inspect(lex_form, content="NumberLegacyOctalInt")
    _ => fail("expected NumberLit")
  }
}

///|
test "parser propagates lex_form to numeric property key" {
  let src = "({ 08: 1 })"
  let toks = @lexer.tokenize(src)
  let mut p = @parser.Parser::new(toks)
  let expr = p.parse_assignment()
  // Numeric prop key normalizes to StringLit but carries Number's lex_form.
  match expr {
    Grouping(ObjectLit(props, _), _) =>
      match props[0].key {
        StringLit(_, _, lex_form, _) =>
          inspect(lex_form, content="NumberNonOctalDecimalInt")
        _ => fail("expected StringLit key")
      }
    _ => fail("expected grouped ObjectLit")
  }
}
```

- [ ] **Step 6: Run tests, format, commit**

```bash
moon check && moon test && moon info && moon fmt
git add ast/ parser/ interpreter/
git commit -m "$(cat <<'EOF'
ast,parser: propagate lex_form to NumberLit AST nodes

NumberLit now carries (value, lex_form, loc). Parser propagates from
the source token at primary-expression and at numeric-key-as-StringLit
normalization sites in object literals and class members.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Add `key_lex_form` to `PropPat` for destructuring keys

**Files:**
- Modify: `ast/ast.mbt:178-183`
- Modify: `parser/stmt.mbt:867` and `parser/expr.mbt:1763` (`expr_to_pattern`)
- Modify: every PropPat construction or match site

- [ ] **Step 1: Modify PropPat struct**

Change `ast/ast.mbt:178-183`:

```moonbit
pub(all) struct PropPat {
  key : String
  key_lex_form : @token.LexForm  // NEW
  value : Pattern
  default_val : Expr?
  computed_key : Expr?
} derive(Debug, Eq)
```

- [ ] **Step 2: Run `moon check` to enumerate construction sites**

Run: `moon check 2>&1 | tee /tmp/proppat-errors.txt`

- [ ] **Step 3: Update parser sites**

For each `{ key: ..., value: ..., ... }` PropPat construction, add `key_lex_form: @token.LexNormal` (or propagate from the source token where available).

Specifically at `parser/stmt.mbt:867` (object-pattern parser): when the key comes from a `String_` or `Number` token, capture the token and propagate `tok.lex_form`. When the key comes from an Ident, pass `LexNormal`.

At `parser/expr.mbt:1763+` (`expr_to_pattern` converting an Expr into a Pattern for assignment-destructuring): if the source Expr is a `StringLit(_, _, lex_form, _)`, propagate that `lex_form` into the resulting PropPat.

- [ ] **Step 4: Update every match site on PropPat**

For each `prop.key` access — usage stays unchanged. For each pattern matching like `{ key, value, default_val, computed_key }`, MoonBit record patterns ignore unmentioned fields by default, so existing matches don't need changes UNLESS they're exhaustive `{ key, value, default_val, computed_key }` literals — those need `key_lex_form: _` added.

- [ ] **Step 5: Add test**

Append to `parser/parser_test.mbt`:

```moonbit
///|
test "object-pattern key carries lex_form" {
  let src = "let { \"\\1\": x } = o;"
  let toks = @lexer.tokenize(src)
  let mut p = @parser.Parser::new(toks)
  let stmt = p.parse_stmt()
  match stmt {
    DestructureDecl(_, ObjectPat(props, _), _, _) =>
      inspect(props[0].key_lex_form, content="StringLegacyOctalEscape")
    _ => fail("expected DestructureDecl with ObjectPat")
  }
}
```

- [ ] **Step 6: Run, format, commit**

```bash
moon check && moon test && moon info && moon fmt
git add ast/ parser/ interpreter/
git commit -m "$(cat <<'EOF'
ast,parser: add key_lex_form to PropPat for destructuring provenance

Object-destructuring property keys (let { "\\1": x } = o) lose key
provenance when collapsed to a plain String. New field preserves the
source token's lex_form for the strict-mode validator.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Add `source_lex_form` to import/export AST nodes

**Files:**
- Modify: `ast/ast.mbt:264-287`
- Modify: `parser/stmt.mbt` import/export source-string sites (lines 1119, 1158, 1268, 1287)
- Modify: every match site on `ImportDecl`, `ExportAllDecl`, `ExportNamedDecl`

- [ ] **Step 1: Modify AST**

Change `ast/ast.mbt:264-287`:

```moonbit
ImportDecl(
  String?,
  Array[ImportSpecifier],
  String?,
  String,
  @token.LexForm,  // NEW: source_lex_form
  @token.Loc
)
ExportNamedDecl(
  Stmt?,
  Array[ExportSpecifier],
  String?,
  @token.LexForm,  // NEW: source_lex_form (LexNormal if no source)
  @token.Loc
)
ExportAllDecl(
  String?,
  String,
  @token.LexForm,  // NEW: source_lex_form
  @token.Loc
)
```

- [ ] **Step 2: Update parser sites**

In `parser/stmt.mbt`:

- Line 1119-1125 (side-effect import): capture the token to read `lex_form`:

```moonbit
if self.peek_kind() is String_(_) {
  let tok = self.advance()
  let source = match tok.kind {
    String_(s) => s
    _ => abort("unreachable")
  }
  self.eat_semicolon()
  return ImportDecl(None, [], None, source, tok.lex_form, tok2.loc)
}
```

(Replace `tok2` with the existing `tok = self.expect(Import)` if that's still in scope, else thread an explicit loc.)

- Line 1158-1169 (`import ... from 'source'`): capture source-token lex_form, pass to `ImportDecl`.
- Line 1194: update `ImportDecl(default_import, specifiers, namespace_import, source, source_lex_form, tok.loc)`.
- Line 1268-1282 (`export * from 'source'`): same pattern. Update `ExportAllDecl(ns_alias, source, source_lex_form, tok.loc)`.
- Line 1287-1305 (`export { ... } from 'source'`): same. Update `ExportNamedDecl(None, specs, source, source_lex_form, tok.loc)`. For non-re-export branch (`source = None`), pass `LexNormal`.

For other `ExportNamedDecl` constructions (where `decl` is `Some(...)`), search for them and pass `LexNormal` since there's no source.

- [ ] **Step 3: Update match sites**

Run `moon check`, fix every `ImportDecl(...)`/`ExportAllDecl(...)`/`ExportNamedDecl(...)` pattern by adding `_` for the new field.

- [ ] **Step 4: Run check + tests**

Run: `moon check && moon test`
Expected: PASS (no behavior change yet — validator integration is next task).

- [ ] **Step 5: Format, commit**

```bash
moon info && moon fmt
git add ast/ parser/ interpreter/
git commit -m "$(cat <<'EOF'
ast,parser: add source_lex_form to import/export decls

Module specifier strings carry source-token provenance to the strict
validator. Modules are always strict, so any tagged source is a
SyntaxError when validated.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Add `validate_strict_lex_form` helper and StringLit/NumberLit validator cases

**Files:**
- Modify: `interpreter/runtime/hoisting.mbt:538-700` (`validate_block_early_errors_expr`)
- Test: `interpreter/interpreter_test.mbt`

- [ ] **Step 1: Write failing integration tests**

Append to `interpreter/interpreter_test.mbt`:

```moonbit
///|
test "strict legacy octal: \\1 in string literal" {
  let src = #|"use strict"; "\1";
  let result = run_throws(src)
  inspect(result, content="SyntaxError: Octal escape sequences are not allowed in strict mode")
}

///|
test "strict legacy octal: 0777 numeric literal" {
  let src = #|"use strict"; 0777;
  let result = run_throws(src)
  inspect(result, content="SyntaxError: Octal literals are not allowed in strict mode")
}

///|
test "strict legacy octal: 08 numeric literal" {
  let src = #|"use strict"; 08;
  let result = run_throws(src)
  inspect(result, content="SyntaxError: Decimals with leading zeros are not allowed in strict mode")
}

///|
test "non-strict legacy octal: \\1 is allowed" {
  let src = #|"\1"
  let result = run(src)
  inspect(result.to_string(), content="\u{0001}")
}

///|
test "non-strict legacy octal: 0777 evaluates to 511" {
  let src = #|0777
  let result = run(src)
  inspect(result.to_string(), content="511")
}

///|
test "bare \\0 NUL is allowed in strict" {
  let src = #|"use strict"; "\0".charCodeAt(0)
  let result = run(src)
  inspect(result.to_string(), content="0")
}

///|
test "strict legacy octal: \\1 nested in dead branch still errors" {
  let src = #|"use strict"; if (false) { "\1"; }
  let result = run_throws(src)
  inspect(result, content="SyntaxError: Octal escape sequences are not allowed in strict mode")
}

///|
test "strict legacy octal: never-called function still errors" {
  let src =
    #|"use strict";
    #|function f() { "\1"; }
  let result = run_throws(src)
  inspect(result, content="SyntaxError: Octal escape sequences are not allowed in strict mode")
}
```

If `run_throws` helper doesn't exist, search `interpreter_test.mbt` for the existing pattern (likely `try { run(src) } catch { e => e.to_string() }`).

- [ ] **Step 2: Run tests, expect FAIL**

Run: `moon test --package interpreter`
Expected: 5 of 8 FAIL (the 3 non-strict + bare-NUL tests should already PASS; the 5 strict-mode tests should FAIL because validator doesn't check lex_form yet).

- [ ] **Step 3: Add `validate_strict_lex_form` helper**

Insert at the top of `interpreter/runtime/hoisting.mbt` (above `validate_block_early_errors_expr`):

```moonbit
///|
fn validate_strict_lex_form(
  form : @token.LexForm,
  loc : @token.Loc,
  strict_context : Bool,
) -> Unit raise Error {
  if !strict_context {
    return
  }
  match form {
    LexNormal => ()
    StringLegacyOctalEscape =>
      raise @errors.SyntaxError(
        message="Octal escape sequences are not allowed in strict mode at line \{loc.line}, col \{loc.col}",
      )
    NumberLegacyOctalInt =>
      raise @errors.SyntaxError(
        message="Octal literals are not allowed in strict mode at line \{loc.line}, col \{loc.col}",
      )
    NumberNonOctalDecimalInt =>
      raise @errors.SyntaxError(
        message="Decimals with leading zeros are not allowed in strict mode at line \{loc.line}, col \{loc.col}",
      )
  }
}
```

- [ ] **Step 4: Add StringLit and NumberLit cases to `validate_block_early_errors_expr`**

In `hoisting.mbt:542` (the `match expr {` block in `validate_block_early_errors_expr`), add cases:

```moonbit
StringLit(_, _, lex_form, loc) =>
  validate_strict_lex_form(lex_form, loc, strict_context)
NumberLit(_, lex_form, loc) =>
  validate_strict_lex_form(lex_form, loc, strict_context)
```

Place these near the top of the match (after `Ident` at line 543, before `FuncExpr` at line 544).

- [ ] **Step 5: Run tests**

Run: `moon test --package interpreter`
Expected: all 8 PASS.

- [ ] **Step 6: Run full check + tests**

Run: `moon check && moon test`
Expected: full PASS. If any pre-existing tests fail, investigate immediately — likely a test asserted lax behavior that the new strict check now rejects. Document any such regression in the commit message.

- [ ] **Step 7: Commit**

```bash
git add interpreter/runtime/hoisting.mbt interpreter/interpreter_test.mbt
git commit -m "$(cat <<'EOF'
interpreter: reject legacy octal forms in strict-mode code

Extends validate_block_early_errors_expr with leaf cases for StringLit
and NumberLit; raises SyntaxError when strict_context=true and the
node carries a non-LexNormal lex_form.

Covers primary-expression literals plus property keys / class member
keys (already visited by the existing walker via prop.key /
ClassMember.value).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Visit `ClassMember.key` and `Field.key` (currently unvisited)

**Files:**
- Modify: `interpreter/runtime/hoisting.mbt:621-637` (the ClassExpr case)
- Test: `interpreter/interpreter_test.mbt`

The existing walker visits `m.value` (method body) but NOT `m.key` (the method name expression). Class bodies are always strict, so the key must be validated against strict.

- [ ] **Step 1: Write failing tests**

Append to `interpreter/interpreter_test.mbt`:

```moonbit
///|
test "class method with legacy octal escape key" {
  let src =
    #|class C { "\1"() {} }
  let result = run_throws(src)
  inspect(result, content="SyntaxError: Octal escape sequences are not allowed in strict mode")
}

///|
test "class method with legacy octal numeric key" {
  let src =
    #|class C { 0777() {} }
  let result = run_throws(src)
  inspect(result, content="SyntaxError: Octal literals are not allowed in strict mode")
}

///|
test "class field with legacy octal numeric key" {
  let src =
    #|class C { 08 = 1; }
  let result = run_throws(src)
  inspect(result, content="SyntaxError: Decimals with leading zeros are not allowed in strict mode")
}
```

- [ ] **Step 2: Run, expect FAIL**

Run: `moon test --package interpreter -- "class.*legacy"`
Expected: 3 FAIL.

- [ ] **Step 3: Update ClassExpr case in `validate_block_early_errors_expr`**

At `hoisting.mbt:621-637`, modify the match arm:

```moonbit
ClassExpr(_, _, members, _) =>
  for mbr in members {
    match mbr {
      @ast.ClassMember::Method(m) => {
        // Visit the method key (always strict in class body)
        validate_block_early_errors_expr(m.key, true)
        // Visit the method body
        validate_block_early_errors_expr(m.value, true)
      }
      @ast.ClassMember::Field(f) => {
        // Visit the field key (always strict)
        validate_block_early_errors_expr(f.key, true)
        match f.initializer {
          Some(expr) => validate_block_early_errors_expr(expr, true)
          None => ()
        }
      }
    }
  }
```

Note: the existing `if f.computed` gate is removed because non-computed keys are also exprs (StringLit) that need visiting. Computed keys still get walked since `validate_block_early_errors_expr` recurses into their inner exprs.

- [ ] **Step 4: Repeat for ClassDecl in `validate_block_early_errors_stmt`**

Search `hoisting.mbt` for the `ClassDecl(...)` case (likely 1000+) and apply the same change.

- [ ] **Step 5: Run tests**

Run: `moon test`
Expected: full PASS.

- [ ] **Step 6: Commit**

```bash
git add interpreter/runtime/hoisting.mbt interpreter/interpreter_test.mbt
git commit -m "$(cat <<'EOF'
interpreter: visit class method/field keys in early-error walker

The existing walker visited Method.value and Field.computed/initializer
but not Method.key or non-computed Field.key. Class keys can carry
legacy octal lex_form (\"\\1\"() {}, 0777() {}, 08 = 1) and class
bodies are always strict — must be visited.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Visit `PropPat.key_lex_form` in pattern walker

**Files:**
- Modify: `interpreter/runtime/hoisting.mbt:517-528` (`validate_pattern_early_errors`)
- Test: `interpreter/interpreter_test.mbt`

- [ ] **Step 1: Write failing tests**

```moonbit
///|
test "destructuring pattern key with legacy octal escape" {
  let src =
    #|"use strict"; let { "\1": x } = {};
  let result = run_throws(src)
  inspect(result, content="SyntaxError: Octal escape sequences are not allowed in strict mode")
}

///|
test "destructuring pattern key with non-octal-decimal" {
  let src =
    #|"use strict"; let { 08: x } = {};
  let result = run_throws(src)
  inspect(result, content="SyntaxError: Decimals with leading zeros are not allowed in strict mode")
}
```

- [ ] **Step 2: Run, expect FAIL**

Run: `moon test --package interpreter -- "destructuring.*legacy"`
Expected: 2 FAIL.

- [ ] **Step 3: Update `validate_pattern_early_errors` ObjectPat case**

At `hoisting.mbt:517-533`, modify the `ObjectPat(props, rest)` arm:

```moonbit
ObjectPat(props, rest) => {
  for prop in props {
    // NEW: validate the key's lex_form (only meaningful in strict_context)
    // Note: PropPat.key is a String, so we need a synthetic loc — use the
    // pattern's own location if available, or default. For now, use Loc::default()
    // since PropPat doesn't currently carry its own loc.
    validate_strict_lex_form(prop.key_lex_form, @token.Loc::default(), strict_context)
    match prop.computed_key {
      Some(expr) => validate_block_early_errors_expr(expr, strict_context)
      None => ()
    }
    validate_pattern_early_errors(prop.value, strict_context, binding)
    match prop.default_val {
      Some(expr) => validate_block_early_errors_expr(expr, strict_context)
      None => ()
    }
  }
  match rest {
    Some(p) => validate_pattern_early_errors(p, strict_context, binding)
    None => ()
  }
}
```

If a precise loc is wanted, track loc in PropPat as a follow-up; for now `Loc::default()` is acceptable since the strict-mode error messages already include line/col placeholder text.

- [ ] **Step 4: Run tests**

Run: `moon test`
Expected: full PASS.

- [ ] **Step 5: Commit**

```bash
git add interpreter/runtime/hoisting.mbt interpreter/interpreter_test.mbt
git commit -m "$(cat <<'EOF'
interpreter: validate destructuring pattern key lex_form

PropPat keys (let { \"\\1\": x } = o) now checked in
validate_pattern_early_errors. Previously the walker only checked
computed_key and default_val.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Validate import/export source strings

**Files:**
- Modify: `interpreter/runtime/hoisting.mbt` (`validate_block_early_errors_stmt` ~ line 1000)
- Test: `interpreter/interpreter_test.mbt`

This task is plumbing-only (the validator code path) — the user-visible test arrives in Task 12 when the module-loader entry point invokes the walker with `strict_context=true`. Skip the test step here and verify Task 12's tests cover the integration.

- [ ] **Step 1: Update `validate_block_early_errors_stmt` for import/export**

Search `hoisting.mbt` for the existing `ExportNamedDecl(Some(decl), ...)` and `ExportDefaultDecl(...)` cases (~ line 1000). Add new cases:

```moonbit
ImportDecl(_, _, _, _, source_lex_form, loc) =>
  validate_strict_lex_form(source_lex_form, loc, strict_context)
ExportAllDecl(_, _, source_lex_form, loc) =>
  validate_strict_lex_form(source_lex_form, loc, strict_context)
ExportNamedDecl(decl_opt, _, _, source_lex_form, loc) => {
  validate_strict_lex_form(source_lex_form, loc, strict_context)
  match decl_opt {
    Some(decl) => validate_block_early_errors_stmt(decl, strict_context)
    None => ()
  }
}
```

- [ ] **Step 2: Run check + existing tests**

Run: `moon check && moon test`
Expected: PASS — no behavior change at script-entry (modules always strict but the script-entry walker is invoked with script's strict context, which may not be true). The actual error firing will require Task 12's module-loader entry passing `strict_context=true`.

- [ ] **Step 3: Commit**

```bash
git add interpreter/runtime/hoisting.mbt
git commit -m "$(cat <<'EOF'
interpreter: validate import/export source lex_form

Adds ImportDecl/ExportAllDecl/ExportNamedDecl cases to
validate_block_early_errors_stmt. Module-loader entry point (next
commit) will pass strict_context=true so module-source legacy octals
become SyntaxErrors.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Add module-loader entry point

**Files:**
- Modify: `interpreter/runtime/modules.mbt` (around line 303)
- Test: `interpreter/interpreter_test.mbt`

- [ ] **Step 1: Read existing module-loader code**

Run: `grep -n 'fn.*module\|always strict\|run_module' /home/antisatori/ghq/github.com/dowdiness/js_engine/interpreter/runtime/modules.mbt | head -20`

Identify the function that takes the parsed module AST and runs it. The point where strict-context is established for a module is where we add the validator call.

- [ ] **Step 2: Write failing tests**

Module-execution tests likely use a helper. Search test file for existing module tests:

```bash
grep -n 'test.*module' /home/antisatori/ghq/github.com/dowdiness/js_engine/interpreter/interpreter_test.mbt | head -5
```

Add test using existing module-test helper:

```moonbit
///|
test "module: import with legacy octal source string is SyntaxError" {
  let src = #|import x from "\1";
  let result = run_module_throws(src)
  inspect(result, content="SyntaxError: Octal escape sequences are not allowed in strict mode")
}

///|
test "module: \\1 in module body is SyntaxError" {
  // Modules are always strict
  let src = #|"\1";
  let result = run_module_throws(src)
  inspect(result, content="SyntaxError: Octal escape sequences are not allowed in strict mode")
}
```

If `run_module_throws` doesn't exist, write it inline using the existing module-runner pattern.

- [ ] **Step 3: Run, expect FAIL**

Run: `moon test --package interpreter -- "module:.*legacy"`
Expected: 2 FAIL.

- [ ] **Step 4: Add validator call in module loader**

In the function identified in Step 1 (likely `run_module_body` or similar around modules.mbt:303), add right after the AST parse and before any execution:

```moonbit
// Modules are always strict (ES262 §16.2.1.6). Validate static early errors.
self.validate_block_early_errors(stmts, true)
```

Match the style of the existing call at `interpreter.mbt:517` and `call.mbt:387`.

- [ ] **Step 5: Run tests**

Run: `moon test`
Expected: full PASS.

- [ ] **Step 6: Commit**

```bash
git add interpreter/runtime/modules.mbt interpreter/interpreter_test.mbt
git commit -m "$(cat <<'EOF'
interpreter: validate module bodies for strict-mode early errors

Modules are always strict per ES262 §16.2.1.6. The existing
validate_block_early_errors walker is now invoked at module-loader
entry with strict_context=true, catching legacy octal forms in module
bodies and import/export source strings.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Add Function/Generator/Async constructor entry points

**Files:**
- Modify: `interpreter/stdlib/builtins_function.mbt:358`
- Modify: `interpreter/runtime/generator.mbt:260`
- Modify: `interpreter/runtime/async.mbt:660`
- Test: `interpreter/interpreter_test.mbt`

- [ ] **Step 1: Write failing tests**

```moonbit
///|
test "new Function with strict directive and legacy octal" {
  let src = #|new Function('"use strict"; "\\1"');
  let result = run_throws(src)
  inspect(result, content="SyntaxError: Octal escape sequences are not allowed in strict mode")
}

///|
test "new GeneratorFunction with strict directive and legacy octal" {
  let src =
    #|let GF = (function*(){}).constructor;
    #|new GF('"use strict"; yield "\\1";');
  let result = run_throws(src)
  inspect(result, content="SyntaxError: Octal escape sequences are not allowed in strict mode")
}

///|
test "new AsyncFunction with strict directive and legacy octal" {
  let src =
    #|let AF = (async function(){}).constructor;
    #|new AF('"use strict"; "\\1"');
  let result = run_throws(src)
  inspect(result, content="SyntaxError: Octal escape sequences are not allowed in strict mode")
}
```

- [ ] **Step 2: Run, expect FAIL**

Run: `moon test --package interpreter -- "new.*Function.*legacy"`
Expected: 3 FAIL.

- [ ] **Step 3: Patch `builtins_function.mbt:358`**

Read the surrounding code (lines 350-400). Locate where the parsed body becomes available and where `strict: has_use_strict(body)` is set. Just before the function value is constructed, add:

```moonbit
// Validate static early errors against the function's strict context.
let body_strict = @runtime.has_use_strict(body)
self.validate_block_early_errors(body, body_strict)
```

(If `self` is not in scope, use the interpreter reference from the calling context.)

- [ ] **Step 4: Patch `generator.mbt:260`**

Read lines 250-280 to see the GeneratorFunction-constructor body where `strict: has_use_strict(body)` is set. Apply the same pattern as Step 3:

```moonbit
// Validate static early errors against the function's strict context.
let body_strict = has_use_strict(body)
self.validate_block_early_errors(body, body_strict)
```

Place the call immediately BEFORE the function value is constructed.

- [ ] **Step 5: Patch `async.mbt:660`**

Read lines 650-680 to see the AsyncFunction-constructor body. Apply the same pattern:

```moonbit
// Validate static early errors against the function's strict context.
let body_strict = has_use_strict(body)
self.validate_block_early_errors(body, body_strict)
```

Place the call immediately BEFORE the function value is constructed.

- [ ] **Step 6: Run tests**

Run: `moon test`
Expected: full PASS.

- [ ] **Step 7: Commit**

```bash
git add interpreter/stdlib/builtins_function.mbt interpreter/runtime/generator.mbt interpreter/runtime/async.mbt interpreter/interpreter_test.mbt
git commit -m "$(cat <<'EOF'
interpreter: validate Function/Generator/Async constructor bodies

new Function('"use strict"; "\\1"') previously accepted the legacy
octal silently because the constructor path bypassed the
validate_block_early_errors walker. This commit invokes the validator
at all three Function-family constructor entry points.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: test262 diff and ROADMAP update

**Files:**
- Modify: none (verification + reporting only)

- [ ] **Step 1: Run full test262 locally if available, otherwise rely on CI**

Run: `make test262-report > /tmp/test262-postchange-$(git rev-parse --short HEAD).txt`
Compare against the baseline captured in Task 0:

```bash
diff /tmp/test262-baseline-*.txt /tmp/test262-postchange-*.txt | head -100
```

Expected: increases in `language/literals/string/legacy-non-octal-escape-*`, `language/literals/numeric/legacy-octal-*`, `language/literals/numeric/non-octal-decimal-*` strict cohorts.

- [ ] **Step 2: Identify any regressions**

For any test that flipped from passing to failing, classify:
- True regression (a test that should still pass) → fix before PR
- Expected outcome change (a test that mistakenly passed because we accepted what we should have rejected) → document in commit/PR description

- [ ] **Step 3: Capture per-mode P/E and P/D rates**

Per memory note `feedback_test262_reporting_conventions.md`, report BOTH per-mode (strict + non-strict) and BOTH denominators (Passed/Executed AND Passed/Discovered).

Pull from latest CI run after pushing the branch:

```bash
git push -u origin <branch>
gh run list --workflow=test262.yml --branch=<branch> --limit=1 --json databaseId
# Wait for completion
make test262-report  # uses gh API to fetch artifacts
```

- [ ] **Step 4: Update PR description with figures**

Use this template:

```
## test262 impact

**Pre-merge baseline** (run <baseline-run-id>, SHA <baseline-sha>):
- Strict: NN.N% P/E, MM.M% P/D
- Non-strict: NN.N% P/E, MM.M% P/D

**Post-merge** (run <postmerge-run-id>, SHA <postmerge-sha>):
- Strict: NN.N% P/E (+X.Xpp), MM.M% P/D (+X.Xpp)
- Non-strict: NN.N% P/E (+X.Xpp), MM.M% P/D (+X.Xpp)

**Cohorts moved:**
- language/literals/string/legacy-non-octal-escape-sequence-*: +N
- language/literals/numeric/legacy-octal*: +N
- language/literals/numeric/non-octal-decimal*: +N

**Regressions:** none / [list]
```

- [ ] **Step 5: Commit any documentation updates**

If `docs/ROADMAP.md` or `docs/supported-features.md` mention strict-mode early errors as missing, update them.

```bash
git add docs/
git commit -m "$(cat <<'EOF'
docs: reflect strict-mode legacy octal early errors

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: File deferred-followup issues**

Open two GitHub issues (or add entries to `docs/agent-todo.md` if that's the project's convention):

1. **Template literal raw/cooked split + strict legacy octal**: covers `` `\1` `` (untagged), `` tag`\1` `` (tagged with cooked=undefined), and the existing `eval_expr.mbt:600` `raw == cooked` bug. Reference the design spec.
2. **Leading-zero fractional/exponent forms**: `01.2`, `01e2` need spec re-read of ES262 §12.8.3 + Annex B §B.1.1 to determine whether they're DecimalLiteral, NonOctalDecimalIntegerLiteral, LegacyOctalIntegerLiteral, or SyntaxError-in-all-modes.

```bash
# Use gh issue create or note in docs/agent-todo.md
gh issue create --title "Template literal raw/cooked split + strict legacy octal" --body "..."
gh issue create --title "Strict-mode handling of leading-zero numeric forms with fraction/exponent (01.2, 01e2)" --body "..."
```

---

## Self-review checklist (run before opening PR)

- [ ] All 8 AST literal-position sinks propagate `lex_form`: primary StringLit, primary NumberLit, ObjectLit prop key (string + numeric), ClassMember key (string + numeric), object generator method key, ObjectPat key, import/export source strings.
- [ ] Validator visits all 8 sites: primary expr (Task 8), property keys (Task 8 — visited via existing walker's prop.key), class keys (Task 9), pattern keys (Task 10), import/export sources (Task 11).
- [ ] Validator entry points: script (existing), eval (existing), module (Task 12), Function/Generator/Async constructors (Task 13).
- [ ] `\0` rule: bare `\0` not followed by digit is allowed in strict (NUL); `\0` followed by digit is tagged.
- [ ] `\1`-`\7` always tagged regardless of context.
- [ ] `\8`/`\9` tagged via new explicit arm before the wildcard.
- [ ] `0o777` (modern octal) is LexNormal.
- [ ] Plain decimals (no leading zero) are LexNormal.
- [ ] Annex B compatibility preserved in non-strict (`08`/`09` evaluate to `8`/`9`; `0777` evaluates to `511`; `\1` evaluates to ``).
- [ ] test262 baseline captured BEFORE any code changes (Task 0).
- [ ] CHANGELOG entry / PR description has per-mode P/E and P/D figures.
- [ ] Two follow-up issues filed (templates, leading-zero fraction/exponent).
