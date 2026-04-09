# js_engine — JavaScript interpreter in MoonBit

@~/.claude/moonbit-base.md

## Commands

```bash
moon check && moon test   # Lint + test
moon info && moon fmt     # Before committing
```

## Package Map

The SessionStart hook runs `scripts/package-overview.sh` which provides a live package map at the start of every session. Use `moon ide outline <path>` to explore any package's public API. Read `moon.mod.json` for module dependencies.

## Documentation

Browse `docs/` for architecture, decisions, development guides, and performance snapshots. Key rules:

- Architecture docs = principles only, never reference specific types/fields/lines
- Code is the source of truth — if a doc and the code disagree, the doc is wrong
- `ROADMAP.md` — test262 pass rate, failure breakdown, next phase targets
- `agent-todo.md` — small AI-friendly tasks
