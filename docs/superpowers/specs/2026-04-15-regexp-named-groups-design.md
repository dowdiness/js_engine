# RegExp Named Groups Design

## Goal

Implement ES2018 named capture groups (`(?<name>...)`) in the MoonBit regex engine so that test262 `regexp-named-groups` tests pass.

## Scope

Primary changes in `interpreter/builtins_regex.mbt`. Additional changes in `interpreter/builtins.mbt` and `interpreter/builtins_string.mbt` for callback replace integration. Seven touch points:

1. AST & data structures
2. Parser: `(?<name>...)` syntax with duplicate rejection
3. Parser: `\k<name>` backreferences (deferred resolution)
4. Match data: name-to-value mapping (source order)
5. Match array: `.groups` object (null prototype)
6. Replacement: `$<name>` with correct edge cases
7. Callback replace: groups argument (conditional)

**Out of scope:** Lookbehind (`(?<=...)`/`(?<!...)`), duplicate named groups (ES2024 — these are distinct from ES2018 duplicate rejection which is a SyntaxError), match indices (`d` flag). These are separately feature-gated in test262.

## Design

### 1. AST & Data Structures

**`RegexNode::Group`** — Add optional name field:

```
Group(Array[RegexNode], Int, String?)  // children, group_index, name
```

Unnamed capturing groups pass `None`. Non-capturing groups keep `group_index = 0, name = None`.

**`RegexParser`** — Add field:

```
group_names : Map[String, Int]  // name -> group_index
```

Used during parsing to:
- Detect duplicate group names (raise SyntaxError)
- Resolve `\k<name>` backreferences after full parse (see section 3)

**`RegexMatch`** — Add field:

```
group_names : Array[(String, Int)]  // (name, group_index) pairs in source order
```

Using an array of pairs (not a Map) preserves source order, which is required for `.groups` property creation order. Populated after matching by correlating named group indices with the captures array.

### 2. Parser: Named Group Syntax

In `parse_group()`, after detecting `(?`:

1. Check if next char is `<`
2. Verify the char after `<` is NOT `=` or `!` (those are lookbehind, unsupported)
3. Parse group name as `RegExpIdentifierName`: first char must satisfy `ID_Start` or be `$` or `_`; subsequent chars must satisfy `ID_Continue` or be `$` or `\u200C` (ZWNJ) or `\u200D` (ZWJ). For practical coverage, accept `[a-zA-Z_$]` as start and `[a-zA-Z0-9_$]` as continue, plus Unicode letters via `Char::is_alphabetic()` / `Char::is_alphanumeric()`
4. If `>` not found, raise `SyntaxError("Invalid regex: unterminated group name")`
5. **Duplicate check:** If `group_names` already contains the name, raise `SyntaxError("Invalid regex: duplicate group name")`
6. Increment `group_count`, record `group_names[name] = group_count`
7. Parse inner alternation, close `)`, return `Group(children, group_idx, Some(name))`

### 3. Parser: Named Backreferences (Deferred Resolution)

`\k<name>` can reference a named group defined later in the pattern (forward reference). Resolution must be deferred.

**Two-pass approach:**

1. During `parse_escape()`, when encountering `\k`:
   - If next char is `<`, parse name until `>`
   - If `>` not found, raise SyntaxError
   - Emit a new AST node: `NamedBackreference(name)` (stores the name string, not the index)
   - **Annex B fallback:** In non-`u` mode, if `\k` is NOT followed by `<`, treat as literal `k` (identity escape). In `u` mode, always require `<name>`.

2. After parsing completes, walk the AST to resolve `NamedBackreference(name)` nodes:
   - Look up `name` in `group_names`
   - If not found, raise `SyntaxError("Invalid regex: undefined named backreference")`
   - Replace with `Backreference(group_index)` — reuses existing backreference matching

This requires either a post-parse AST rewrite or storing unresolved references in a list and resolving them. The AST rewrite is cleaner.

**Alternative:** Add `NamedBackreference(String)` as a permanent AST variant and resolve at match time by looking up the name in the captures. This avoids the rewrite pass but adds a new match arm. Either approach is acceptable.

### 4. Match Data Population

Thread the parser's `group_names` map through to the match functions. After matching succeeds in `regex_match_at()`, `regex_search()`, and `regex_search_all()`:

1. Iterate `group_names` entries (collected in source order during parsing)
2. For each `(name, group_index)`, look up `captures[group_index - 1]`
3. Store as `(name, group_index)` pairs on `RegexMatch` — the actual captured value is already in `captures`

To thread the name map, the public API functions (`regex_match_at`, `regex_search`, `regex_search_all`) should parse once and pass the name metadata alongside the parsed node. Currently they parse inside each function — refactor to parse once and return both the node and the name map.

### 5. Match Array `.groups` Object

In `make_regex_match_array()`:

- If `group_names` is non-empty: create an object with `null` prototype, iterate names **in source order**, add each as a data property with the captured value (or `Undefined` if the capture is `None`)
- If `group_names` is empty: set `groups` to `Undefined`

Per ES spec steps 24-26 of `RegExpBuiltinExec`. The null-prototype object means `Object.create(null)` semantics — no `__proto__` inheritance. Properties are writable, enumerable, and configurable (CreateDataProperty semantics).

### 6. Replacement: `$<name>`

**`process_replacement()`** — Handle `$<name>` per `GetSubstitution` spec:

1. After `$`, check if next char is `<`
2. If the regex has **no named groups** (group_names is empty), treat `$<` as literal — do not consume it
3. Parse name until `>`. If `>` is not found before end of replacement string, treat `$<` as literal
4. Look up name in match's group_names:
   - If found and captured: substitute the captured value
   - If found but unmatched (capture is None): substitute empty string
   - If name not found in group_names: substitute empty string

`process_replacement()` needs an additional parameter: whether the regex has any named groups (to distinguish "no named groups" from "named groups exist but this name doesn't match").

### 7. Callback Replace: Groups Argument

Changes span `builtins_regex.mbt`, `builtins.mbt`, and `builtins_string.mbt`.

In `string_replace_regex()` (and any callback-based replace path):

1. Build the groups object only if the regex contains named groups
2. If groups object exists, append it as the **last** argument to the callback: `fn(match, p1, p2, ..., offset, string, groups)`
3. If the regex has no named groups, do **not** append the groups argument (per spec: only when `result.[[Groups]]` is not undefined)

The groups object uses the same null-prototype construction as section 5.

## Test Coverage

Primary: `test262/test/built-ins/RegExp/named-groups/` (~36 tests)
Additional: `test262/test/language/literals/regexp/named-groups/`
Annex B: `test262/test/annexB/built-ins/RegExp/named-groups/`

Key test behaviors:
- `.groups` has null prototype
- `.groups` created with `CreateDataProperty` (not `Set`)
- `.groups` properties in source order
- Unmatched named groups have value `undefined`
- Duplicate group names are SyntaxError (ES2018)
- `\k<name>` backreferences work, including forward references
- `\k` without `<` is identity escape in non-`u` mode, SyntaxError in `u` mode
- `$<name>` in replacement strings, literal when no named groups or unclosed `>`
- Groups object passed to replace callbacks only when named groups exist
- Mixed named and unnamed groups coexist
- Unicode identifier names in group names
