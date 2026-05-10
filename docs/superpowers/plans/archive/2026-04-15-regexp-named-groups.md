# RegExp Named Groups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement ES2018 named capture groups (`(?<name>...)`) so test262 `regexp-named-groups` tests pass.

**Architecture:** Extend the existing `Group` AST variant with an optional name field. Thread group name metadata from parser through matcher to match result construction. Named backreferences (`\k<name>`) use deferred resolution (post-parse pass). Replacement and callback paths gain `$<name>` and groups argument support.

**Tech Stack:** MoonBit, test262 test runner (`python3 test262-runner.py`)

**Spec:** `docs/superpowers/specs/2026-04-15-regexp-named-groups-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `interpreter/builtins_regex.mbt` | Modify | AST, parser, matcher, match array, replacement |
| `interpreter/builtins.mbt` | Modify | `[Symbol.replace]` callback groups argument |
| `interpreter/builtins_string.mbt` | Modify | `String.prototype.replace` callback groups argument |
| `test262-runner.py` | Modify | Remove `regexp-named-groups` from `SKIP_FEATURES` |
| `test262-analyze.py` | Modify | Remove `regexp-named-groups` from skip list |

---

### Task 1: AST & Data Structure Changes

**Files:**
- Modify: `interpreter/builtins_regex.mbt:10-22` (RegexNode enum)
- Modify: `interpreter/builtins_regex.mbt:32-37` (RegexParser struct)
- Modify: `interpreter/builtins_regex.mbt:40-41` (RegexParser::new)
- Modify: `interpreter/builtins_regex.mbt:462-466` (RegexMatch struct)

- [ ] **Step 1: Add optional name to Group variant and add NamedBackreference variant**

In `RegexNode`, change:
```moonbit
Group(Array[RegexNode], Int) // children, group_index
```
to:
```moonbit
Group(Array[RegexNode], Int, String?) // children, group_index, name
NamedBackreference(String) // group name (resolved post-parse)
```

- [ ] **Step 2: Add unicode flag and group_names to RegexParser**

Change `RegexParser` struct:
```moonbit
priv struct RegexParser {
  pattern : Array[Char]
  mut pos : Int
  mut group_count : Int
  unicode : Bool
  group_names : Map[String, Int]
}
```

Update `RegexParser::new` to accept a `unicode` parameter:
```moonbit
fn RegexParser::new(pattern : String, unicode~ : Bool = false) -> RegexParser {
  { pattern: pattern.to_array(), pos: 0, group_count: 0, unicode, group_names: {} }
}
```

- [ ] **Step 3: Add group_names to RegexMatch**

Change `RegexMatch` struct:
```moonbit
struct RegexMatch {
  start : Int
  end_ : Int
  captures : Array[String?]
  group_names : Array[(String, Int)] // (name, group_index) in source order
}
```

- [ ] **Step 4: Fix all existing Group pattern matches**

Every `match` on `RegexNode` that mentions `Group(children, idx)` must become `Group(children, idx, _)`. Update these locations:

- `regex_exec_inner` at line ~632: `Group(children, group_idx)` → `Group(children, group_idx, _)`
- `count_groups` at line ~840: `Group(children, group_idx)` → `Group(children, group_idx, _)`

Add a match arm for `NamedBackreference(_)` in both `regex_exec_inner` and `count_groups`:
- In `count_groups`: `| NamedBackreference(_) => 0`
- In `regex_exec_inner`: `NamedBackreference(_) => None` (should never be reached after resolution, but needed for exhaustiveness)

- [ ] **Step 5: Fix all RegexMatch construction sites**

Every place that constructs a `RegexMatch` literal `{ start: ..., end_: ..., captures: ... }` must add `group_names: []`. Search for `RegexMatch` construction in:
- `regex_match_at` (~line 917)
- `regex_search` (~line 942, 949)
- `regex_search_all` (~line 972)

Change each to include `group_names: []` (will be populated in Task 4).

- [ ] **Step 6: Fix existing Group construction in parse_group**

In `parse_group()`, change the two `Group(...)` returns:
- Non-capturing group (line ~309): `Group(children, 0)` → `Group(children, 0, None)`
- Capturing group (line ~348): `Group(children, group_idx)` → `Group(children, group_idx, None)`

- [ ] **Step 7: Run moon check**

Run: `moon check`
Expected: No errors. All existing code compiles with the new fields.

- [ ] **Step 8: Run moon test**

Run: `moon test`
Expected: All existing tests pass (no behavioral change yet).

- [ ] **Step 9: Commit**

```bash
git add interpreter/builtins_regex.mbt
git commit -m "refactor: extend regex AST for named groups (no behavior change)"
```

---

### Task 2: Parser — Named Group Syntax `(?<name>...)`

**Files:**
- Modify: `interpreter/builtins_regex.mbt:292-349` (parse_group)

- [ ] **Step 1: Add named group parsing in parse_group**

In `parse_group()`, after the `if next == ':'` block and before the `else if next == '='` block (around line 298), add a new branch. The full updated `parse_group` logic after `if self.pos < self.pattern.length() && self.pattern[self.pos] == '?'`:

```moonbit
if self.pos + 1 < self.pattern.length() {
  let next = self.pattern[self.pos + 1]
  if next == ':' {
    // Non-capturing group (?:...) — existing code unchanged
    self.pos += 2
    let inner = self.parse_alternation()
    if self.pos < self.pattern.length() && self.pattern[self.pos] == ')' {
      self.pos += 1
    }
    let children = match inner {
      Sequence(nodes) => nodes
      _ => [inner]
    }
    return Group(children, 0, None)
  } else if next == '<' {
    // Check for named group (?<name>...) vs lookbehind (?<=...) / (?<!...)
    if self.pos + 2 < self.pattern.length() {
      let after_lt = self.pattern[self.pos + 2]
      if after_lt == '=' || after_lt == '!' {
        // Lookbehind — not supported, fall through to error or treat as syntax error
        raise @errors.SyntaxError(
          message="Invalid regex: lookbehind assertions are not supported",
        )
      }
    }
    // Named capturing group (?<name>...)
    self.pos += 2 // skip '?<'
    // Parse group name: RegExpIdentifierName
    let name_buf = StringBuilder::new()
    // First char: ID_Start or $ or _
    if self.pos >= self.pattern.length() {
      raise @errors.SyntaxError(
        message="Invalid regex: unterminated group name",
      )
    }
    let first = self.pattern[self.pos]
    if first == '_' || first == '$' || first.is_alphabetic() {
      name_buf.write_char(first)
      self.pos += 1
    } else {
      raise @errors.SyntaxError(
        message="Invalid regex: invalid group name",
      )
    }
    // Subsequent chars: ID_Continue or $ or ZWNJ/ZWJ
    while self.pos < self.pattern.length() && self.pattern[self.pos] != '>' {
      let ch = self.pattern[self.pos]
      if ch == '_' || ch == '$' || ch.is_alphanumeric() ||
        ch.to_int() == 0x200C || ch.to_int() == 0x200D {
        name_buf.write_char(ch)
        self.pos += 1
      } else {
        raise @errors.SyntaxError(
          message="Invalid regex: invalid group name",
        )
      }
    }
    if self.pos >= self.pattern.length() || self.pattern[self.pos] != '>' {
      raise @errors.SyntaxError(
        message="Invalid regex: unterminated group name",
      )
    }
    self.pos += 1 // skip '>'
    let name = name_buf.to_string()
    // Duplicate check
    if self.group_names.contains(name) {
      raise @errors.SyntaxError(
        message="Invalid regex: duplicate group name",
      )
    }
    self.group_count += 1
    let group_idx = self.group_count
    self.group_names[name] = group_idx
    let inner = self.parse_alternation()
    if self.pos < self.pattern.length() && self.pattern[self.pos] == ')' {
      self.pos += 1
    }
    let children = match inner {
      Sequence(nodes) => nodes
      _ => [inner]
    }
    return Group(children, group_idx, Some(name))
  } else if next == '=' {
    // ... existing lookahead code
```

- [ ] **Step 2: Run moon check**

Run: `moon check`
Expected: No errors.

- [ ] **Step 3: Run moon test**

Run: `moon test`
Expected: All existing tests pass. Named groups now parse without error.

- [ ] **Step 4: Commit**

```bash
git add interpreter/builtins_regex.mbt
git commit -m "feat: parse named capture groups (?<name>...)"
```

---

### Task 3: Parser — Named Backreferences `\k<name>`

**Files:**
- Modify: `interpreter/builtins_regex.mbt:129-197` (parse_escape)
- Modify: `interpreter/builtins_regex.mbt:44-48` (parse method — add resolution pass)

- [ ] **Step 1: Add \k<name> parsing in parse_escape**

In `parse_escape()`, in the `match ch` block, add a case for `'k'` before the backreference digits case (before line ~190):

```moonbit
'k' => {
  // Named backreference \k<name>
  if self.pos < self.pattern.length() && self.pattern[self.pos] == '<' {
    self.pos += 1 // skip '<'
    let name_buf = StringBuilder::new()
    while self.pos < self.pattern.length() && self.pattern[self.pos] != '>' {
      name_buf.write_char(self.pattern[self.pos])
      self.pos += 1
    }
    if self.pos >= self.pattern.length() {
      raise @errors.SyntaxError(
        message="Invalid regex: unterminated named backreference",
      )
    }
    self.pos += 1 // skip '>'
    NamedBackreference(name_buf.to_string())
  } else if self.unicode {
    // In unicode mode, \k without < is an error
    raise @errors.SyntaxError(
      message="Invalid regex: invalid escape \\k",
    )
  } else {
    // Annex B: \k without < is identity escape in non-unicode mode
    Literal('k')
  }
}
```

- [ ] **Step 2: Add post-parse resolution of NamedBackreference nodes**

Add a new function `resolve_named_backreferences` that walks the AST and replaces `NamedBackreference(name)` with `Backreference(index)`:

```moonbit
fn resolve_named_backreferences(
  node : RegexNode,
  group_names : Map[String, Int],
) -> RegexNode raise Error {
  match node {
    NamedBackreference(name) =>
      match group_names.get(name) {
        Some(idx) => Backreference(idx)
        None =>
          raise @errors.SyntaxError(
            message="Invalid regex: undefined named backreference \\k<" + name + ">",
          )
      }
    Group(children, idx, name) => {
      let resolved = children.map(fn(child) {
        resolve_named_backreferences(child, group_names) catch {
          e => raise e
        }
      })
      Group(resolved, idx, name)
    }
    Sequence(nodes) => {
      let resolved = nodes.map(fn(child) {
        resolve_named_backreferences(child, group_names) catch {
          e => raise e
        }
      })
      Sequence(resolved)
    }
    Alternation(left, right) => {
      let l = left.map(fn(child) {
        resolve_named_backreferences(child, group_names) catch {
          e => raise e
        }
      })
      let r = right.map(fn(child) {
        resolve_named_backreferences(child, group_names) catch {
          e => raise e
        }
      })
      Alternation(l, r)
    }
    Quantified(inner, min, max, greedy) => {
      let resolved = resolve_named_backreferences(inner, group_names) catch {
        e => raise e
      }
      Quantified(resolved, min, max, greedy)
    }
    Lookahead(children, positive) => {
      let resolved = children.map(fn(child) {
        resolve_named_backreferences(child, group_names) catch {
          e => raise e
        }
      })
      Lookahead(resolved, positive)
    }
    // Leaf nodes: no transformation needed
    Literal(_) | Dot | CharClass(_, _) | Anchor(_) | WordBoundary(_)
    | Backreference(_) => node
  }
}
```

- [ ] **Step 3: Update RegexParser::parse to call resolution**

Change `RegexParser::parse`:

```moonbit
fn RegexParser::parse(self : RegexParser) -> RegexNode raise Error {
  let result = self.parse_alternation()
  if !self.group_names.is_empty() {
    resolve_named_backreferences(result, self.group_names)
  } else {
    result
  }
}
```

- [ ] **Step 4: Run moon check**

Run: `moon check`
Expected: No errors.

- [ ] **Step 5: Run moon test**

Run: `moon test`
Expected: All existing tests pass.

- [ ] **Step 6: Commit**

```bash
git add interpreter/builtins_regex.mbt
git commit -m "feat: parse named backreferences \\k<name> with deferred resolution"
```

---

### Task 4: Thread Group Names Through Match Functions

**Files:**
- Modify: `interpreter/builtins_regex.mbt:905-988` (regex_match_at, regex_search, regex_search_all)

The public match functions currently parse the pattern inside each call. Refactor to parse once and extract the group name map.

- [ ] **Step 1: Create a helper to parse and extract metadata**

Add a helper struct and function:

```moonbit
priv struct ParsedRegex {
  node : RegexNode
  num_groups : Int
  group_names : Array[(String, Int)] // (name, group_index) in source order
}

fn parse_regex(pattern : String, unicode~ : Bool = false) -> ParsedRegex raise Error {
  let parser = RegexParser::new(pattern, unicode~)
  let node = parser.parse()
  let num_groups = count_groups(node)
  // Convert Map to Array in source order (sorted by group_index)
  let names : Array[(String, Int)] = []
  for name, idx in parser.group_names {
    names.push((name, idx))
  }
  // Sort by group_index to ensure source order
  names.sort_by(fn(a, b) { a.1.compare(b.1) })
  { node, num_groups, group_names: names }
}
```

- [ ] **Step 2: Update regex_match_at to use parse_regex**

```moonbit
pub fn regex_match_at(
  pattern : String,
  flags : String,
  input : String,
  start_pos : Int,
) -> RegexMatch? raise Error {
  let parsed = parse_regex(pattern, unicode=flags.contains("u"))
  let input_chars = input.to_array()
  let rflags = make_regex_flags(flags)
  let captures : Array[String?] = Array::make(parsed.num_groups, None)
  match regex_exec(parsed.node, input_chars, start_pos, captures, rflags) {
    Some(end_pos) =>
      Some({ start: start_pos, end_: end_pos, captures, group_names: parsed.group_names })
    None => None
  }
}
```

- [ ] **Step 3: Update regex_search to use parse_regex**

```moonbit
pub fn regex_search(
  pattern : String,
  flags : String,
  input : String,
  start_pos? : Int = 0,
) -> RegexMatch? raise Error {
  let parsed = parse_regex(pattern, unicode=flags.contains("u"))
  let input_chars = input.to_array()
  let rflags = make_regex_flags(flags)
  let is_sticky = flags.contains("y")
  if is_sticky {
    if start_pos > input_chars.length() {
      return None
    }
    let captures : Array[String?] = Array::make(parsed.num_groups, None)
    match regex_exec(parsed.node, input_chars, start_pos, captures, rflags) {
      Some(end_pos) =>
        return Some({ start: start_pos, end_: end_pos, captures, group_names: parsed.group_names })
      None => return None
    }
  }
  for i = start_pos; i <= input_chars.length(); i = i + 1 {
    let captures : Array[String?] = Array::make(parsed.num_groups, None)
    match regex_exec(parsed.node, input_chars, i, captures, rflags) {
      Some(end_pos) =>
        return Some({ start: i, end_: end_pos, captures, group_names: parsed.group_names })
      None => continue
    }
  }
  None
}
```

- [ ] **Step 4: Update regex_search_all to use parse_regex**

```moonbit
pub fn regex_search_all(
  pattern : String,
  flags : String,
  input : String,
) -> Array[RegexMatch] raise Error {
  let parsed = parse_regex(pattern, unicode=flags.contains("u"))
  let input_chars = input.to_array()
  let rflags = make_regex_flags(flags)
  let results : Array[RegexMatch] = []
  let mut i = 0
  while i <= input_chars.length() {
    let captures : Array[String?] = Array::make(parsed.num_groups, None)
    match regex_exec(parsed.node, input_chars, i, captures, rflags) {
      Some(end_pos) => {
        results.push({ start: i, end_: end_pos, captures, group_names: parsed.group_names })
        if end_pos == i {
          i += 1
        } else {
          i = end_pos
        }
      }
      None => {
        if rflags.sticky {
          break
        }
        i += 1
      }
    }
  }
  results
}
```

- [ ] **Step 5: Run moon check**

Run: `moon check`
Expected: No errors.

- [ ] **Step 6: Run moon test**

Run: `moon test`
Expected: All existing tests pass.

- [ ] **Step 7: Commit**

```bash
git add interpreter/builtins_regex.mbt
git commit -m "refactor: thread group name metadata through regex match functions"
```

---

### Task 5: Populate `.groups` Object on Match Arrays

**Files:**
- Modify: `interpreter/builtins_regex.mbt:991-1015` (make_regex_match_array)

- [ ] **Step 1: Update make_regex_match_array to build groups object**

```moonbit
pub fn make_regex_match_array(m : RegexMatch, input : String) -> Value {
  let input_chars = input.to_array()
  let elements : Array[Value] = []
  // First element: full match
  let buf = StringBuilder::new()
  for i = m.start; i < m.end_; i = i + 1 {
    buf.write_char(input_chars[i])
  }
  elements.push(String_(buf.to_string()))
  // Capture groups
  for cap in m.captures {
    match cap {
      Some(s) => elements.push(String_(s))
      None => elements.push(Undefined)
    }
  }
  let arr_data : ArrayData = { elements, }
  // Set named properties on the result
  set_array_named_prop(arr_data, "index", Number(m.start.to_double()))
  set_array_named_prop(arr_data, "input", String_(input))
  // Build groups object
  let groups_val = if m.group_names.length() > 0 {
    // Create null-prototype object
    let props : Map[String, Value] = {}
    let descs : Map[String, PropertyDescriptor] = {}
    for pair in m.group_names {
      let (name, idx) = pair
      let val = if idx - 1 < m.captures.length() {
        match m.captures[idx - 1] {
          Some(s) => String_(s)
          None => Undefined
        }
      } else {
        Undefined
      }
      props[name] = val
      descs[name] = {
        writable: Some(true),
        enumerable: Some(true),
        configurable: Some(true),
        value: None,
        get: None,
        set_: None,
      }
    }
    Object({
      properties: props,
      descriptors: descs,
      prototype: Null,
      extensible: true,
      class_name: "Object",
      call: None,
      construct: None,
      private_elements: None,
      iterator_next: None,
    })
  } else {
    Undefined
  }
  set_array_named_prop(arr_data, "groups", groups_val)
  Array(arr_data)
}
```

Note: Check `ObjectData` struct fields to ensure the literal above matches. The key point is `prototype: Null` for null-prototype object. Use the same construction pattern as other object creation in the codebase — grep for `ObjectData` or `Object({` to find the canonical pattern.

- [ ] **Step 2: Update make_regexp_object to pass unicode flag to parser**

In `make_regexp_object` (~line 1060), the validation parse currently uses:
```moonbit
let _parsed = RegexParser::new(pattern).parse()
```

Change to:
```moonbit
let _parsed = RegexParser::new(pattern, unicode=flags.contains("u")).parse()
```

This ensures named group validation (duplicate names, `\k` semantics) works correctly during RegExp construction.

- [ ] **Step 3: Run moon check**

Run: `moon check`
Expected: No errors. Verify `ObjectData` field names match what the codebase uses.

- [ ] **Step 4: Run moon test**

Run: `moon test`
Expected: All existing tests pass.

- [ ] **Step 5: Commit**

```bash
git add interpreter/builtins_regex.mbt
git commit -m "feat: populate .groups object on regex match arrays"
```

---

### Task 6: Replacement String `$<name>` Support

**Files:**
- Modify: `interpreter/builtins_regex.mbt:1336-1403` (process_replacement)

- [ ] **Step 1: Add has_named_groups parameter and $<name> handling**

Update `process_replacement` signature to accept group name metadata:

```moonbit
fn process_replacement(
  replacement : String,
  input_chars : Array[Char],
  m : RegexMatch,
) -> String {
```

The signature stays the same since `m` already contains `group_names`. Add `$<name>` handling inside the `if repl_chars[i] == '$'` block, after the `$1-$9` case and before the `$$` case:

```moonbit
} else if next == '<' {
  // $<name> - named group substitution
  if m.group_names.length() == 0 {
    // No named groups: $< is literal
    buf.write_char('$')
    buf.write_char('<')
    i += 2
    continue
  }
  // Parse name until '>'
  let name_buf = StringBuilder::new()
  let mut j = i + 2
  while j < repl_chars.length() && repl_chars[j] != '>' {
    name_buf.write_char(repl_chars[j])
    j += 1
  }
  if j >= repl_chars.length() {
    // No closing '>' — treat $< as literal
    buf.write_char('$')
    buf.write_char('<')
    i += 2
    continue
  }
  // Found '>' — look up name
  let name = name_buf.to_string()
  let mut found = false
  for pair in m.group_names {
    let (gname, gidx) = pair
    if gname == name {
      if gidx - 1 < m.captures.length() {
        match m.captures[gidx - 1] {
          Some(s) => buf.write_string(s)
          None => () // unmatched: empty string
        }
      }
      found = true
      break
    }
  }
  // If name not found, substitute empty string (per spec)
  let _ = found
  i = j + 1 // skip past '>'
  continue
```

Insert this block after the `next >= '1' && next <= '9'` case (around line 1393) and before the `next == '$'` case.

- [ ] **Step 2: Run moon check**

Run: `moon check`
Expected: No errors.

- [ ] **Step 3: Run moon test**

Run: `moon test`
Expected: All existing tests pass.

- [ ] **Step 4: Commit**

```bash
git add interpreter/builtins_regex.mbt
git commit -m "feat: support \$<name> in regex replacement strings"
```

---

### Task 7: Callback Replace — Groups Argument

**Files:**
- Modify: `interpreter/builtins.mbt:1392-1407` ([Symbol.replace])
- Modify: `interpreter/builtins_string.mbt:684-698` (String.prototype.replace with regex)

Currently both paths stringify the replacement value before calling `string_replace_regex`. Function callback support for regex replace is not yet implemented — both `[Symbol.replace]` and `String.prototype.replace` call `.to_string()` on the replacement. Full callback support is out of scope for this PR; however, we should wire up the groups argument plumbing so when callback support is added later, groups will work.

- [ ] **Step 1: Check if function callback replace already works for regex**

Run the following test manually to verify current behavior:

```bash
echo 'var result = "abc".replace(/(?<letter>.)/, function(match, p1, offset, str, groups) { return groups.letter; }); print(result);' > /tmp/test_replace_cb.js
```

If the engine stringifies the function (producing `"function..."` as replacement), then callback support is missing and this task becomes a no-op for now — skip to Step 3.

- [ ] **Step 2: If callback replace works, add groups argument**

In `[Symbol.replace]` (builtins.mbt ~1397) and `String.prototype.replace` (builtins_string.mbt ~693), when the second argument is callable:

1. Perform the regex match
2. Build callback arguments: `[match_str, ...captures, offset, input_str]`
3. If `match.group_names.length() > 0`, build null-prototype groups object and append it
4. Call the function with these arguments

This step's implementation depends on how the existing callback infrastructure works. If callback replace for regex is not yet implemented, document it as a follow-up and skip.

- [ ] **Step 3: Commit (if changes were made)**

```bash
git add interpreter/builtins.mbt interpreter/builtins_string.mbt
git commit -m "feat: wire groups argument for regex callback replace"
```

---

### Task 8: Enable test262 Feature Flag & Validate

**Files:**
- Modify: `test262-runner.py:83`
- Modify: `test262-analyze.py:125`

- [ ] **Step 1: Remove regexp-named-groups from SKIP_FEATURES in test262-runner.py**

In `test262-runner.py` line 83, remove `"regexp-named-groups"` from the skip list.

- [ ] **Step 2: Remove regexp-named-groups from skip list in test262-analyze.py**

In `test262-analyze.py` line 125, remove `"regexp-named-groups"` from the skip list.

- [ ] **Step 3: Run the named-groups tests specifically**

```bash
python3 test262-runner.py --test-dir test262/test/built-ins/RegExp/named-groups/ 2>&1 | tail -20
```

Review which tests pass and which fail. Expected: core tests pass (non-unicode-match, groups-object basics, string-replace). Some tests may fail due to missing features (lookbehind, duplicate names ES2024, match indices).

- [ ] **Step 4: Run the language literal named-groups tests**

```bash
python3 test262-runner.py --test-dir test262/test/language/literals/regexp/named-groups/ 2>&1 | tail -20
```

- [ ] **Step 5: Run full test suite to check for regressions**

```bash
python3 test262-runner.py 2>&1 | tail -5
```

Expected: Pass rate should increase. No regressions in previously passing tests.

- [ ] **Step 6: Commit**

```bash
git add test262-runner.py test262-analyze.py
git commit -m "test: enable regexp-named-groups in test262 runner"
```

---

### Task 9: Fix Failures & Final Cleanup

- [ ] **Step 1: Analyze test failures from Task 8**

For each failing test, read the test file to understand what it expects. Categorize failures as:
- **Fixable:** Bug in our implementation (fix it)
- **Out of scope:** Requires lookbehind, duplicate names (ES2024), match indices, or other unimplemented features (document as known limitation)

- [ ] **Step 2: Fix any implementation bugs found**

Apply fixes based on the analysis. Run `moon check && moon test` after each fix.

- [ ] **Step 3: Run moon info && moon fmt**

```bash
moon info && moon fmt
```

- [ ] **Step 4: Check .mbti interface changes**

```bash
git diff *.mbti
```

Review: `RegexMatch` struct gained `group_names` field. `make_regex_match_array` signature unchanged. Verify no unexpected API changes.

- [ ] **Step 5: Final test run**

```bash
python3 test262-runner.py 2>&1 | tail -5
```

- [ ] **Step 6: Commit all remaining changes**

```bash
git add -A
git commit -m "fix: address test262 named-groups test failures"
```
