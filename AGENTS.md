# js_engine — JavaScript interpreter in MoonBit

@~/.claude/moonbit-base.md

## Commands

```bash
moon check && moon test   # Lint + test
moon info && moon fmt     # Before committing
```

## Package Map

The SessionStart hook runs `scripts/package-overview.sh` which provides a live package map at the start of every session. Use `moon ide outline <path>` to explore any package's public API. Read `moon.mod.json` for module dependencies.

## ES Spec Discipline

When implementing or debugging JavaScript built-in methods:

1. **Verify against the spec, not against sibling methods.** Methods that look structurally similar (e.g., `forEach` vs `find`) often have deliberately different semantics. Never assume one method's behavior applies to another.
2. **Read the spec algorithm for the specific method** before claiming it's buggy or before implementing a fix. The test262 `info` field quotes the exact spec steps — use it.
3. **Do not copy-paste implementations between methods.** Start from the spec algorithm for each. ES5 methods (forEach, map, filter) and ES6+ methods (find, findIndex, includes) differ on hole handling, return values, and species usage by design.

## Documentation

Browse `docs/` for architecture, decisions, development guides, and performance snapshots. Key rules:

- Architecture docs = principles only, never reference specific types/fields/lines
- Code is the source of truth — if a doc and the code disagree, the doc is wrong
- `ROADMAP.md` — test262 pass rate, failure breakdown, next phase targets
- `agent-todo.md` — small AI-friendly tasks
