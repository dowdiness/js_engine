# RegExp Named Groups Design

## Goal

Implement ES2018 named capture groups (`(?<name>...)`) in the MoonBit regex engine so that test262 `regexp-named-groups` tests pass.

## Scope

All changes are in `interpreter/builtins_regex.mbt`. Six touch points:

1. AST & data structures
2. Parser: `(?<name>...)` syntax
3. Parser: `\k<name>` backreferences
4. Match data: name-to-value mapping
5. Match array: `.groups` object
6. Replacement: `$<name>` and callback groups argument

**Out of scope:** Lookbehind (`(?<=...)`/`(?<!...)`), duplicate named groups (ES2024), match indices (`d` flag), Unicode identifier names in group names (ASCII identifiers only for now).

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

Used during parsing to resolve `\k<name>` backreferences to their group index.

**`RegexMatch`** — Add field:

```
group_names : Map[String, String?]  // name -> captured value (None = unmatched)
```

Populated after matching by correlating named group indices with the captures array.

### 2. Parser: Named Group Syntax

In `parse_group()`, after detecting `(?`:

1. Check if next char is `<`
2. Verify the char after `<` is NOT `=` or `!` (those are lookbehind, unsupported)
3. Parse identifier: `[a-zA-Z_$][a-zA-Z0-9_$]*` until `>`
4. If `>` not found, raise `SyntaxError("Invalid regex: unterminated group name")`
5. Increment `group_count`, record `group_names[name] = group_count`
6. Parse inner alternation, close `)`, return `Group(children, group_idx, Some(name))`

### 3. Parser: Named Backreferences

In `parse_escape()`, add case for `k`:

1. Check next char is `<`
2. Parse name until `>`
3. Look up name in `group_names` map
4. If not found, raise `SyntaxError("Invalid regex: undefined named backreference \\k<name>")`
5. Emit `Backreference(group_index)` — reuses existing backreference matching

### 4. Match Data Population

After matching succeeds in `regex_match_at()`, `regex_search()`, and `regex_search_all()`:

1. Walk the parsed AST to collect `(name, group_index)` pairs from named `Group` nodes
2. For each pair, look up `captures[group_index - 1]` to get the captured value
3. Store in `RegexMatch.group_names`

Alternatively, store the name map on the parser and thread it through — avoids re-walking the AST.

### 5. Match Array `.groups` Object

In `make_regex_match_array()`:

- If `group_names` is non-empty: create an object with `null` prototype (`Object.create(null)`), add each name as a data property with the captured value (or `Undefined` if unmatched)
- If `group_names` is empty: set `groups` to `Undefined`

Per ES spec steps 24-26 of `RegExpBuiltinExec`.

### 6. Replacement Integration

**`process_replacement()`** — Handle `$<name>`:

1. After `$`, check if next char is `<`
2. Parse name until `>`
3. Look up in match's `group_names`
4. Substitute captured value, or empty string if unmatched/missing

Requires `process_replacement` to accept `RegexMatch` (it already does) — just needs to read `group_names`.

**`string_replace_regex()`** — When calling replace callback function:

1. Build the groups object (same null-prototype object as match array)
2. Pass it as the final argument: `fn(match, p1, p2, ..., offset, string, groups)`

## Test Coverage

Primary: `test262/test/built-ins/RegExp/named-groups/` (~36 tests)
Additional: `test262/test/language/literals/regexp/named-groups/`

Key test behaviors:
- `.groups` has null prototype
- `.groups` created with `CreateDataProperty` (not `Set`)
- Unmatched named groups have value `undefined`
- `\k<name>` backreferences work
- `$<name>` in replacement strings
- Groups object passed to replace callbacks
- Mixed named and unnamed groups coexist
