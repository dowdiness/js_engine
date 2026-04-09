# js_engine — JavaScript interpreter in MoonBit

@~/.claude/moonbit-base.md

## Project Structure

Single module: `dowdiness/js_engine`

| Package | Purpose |
|---------|---------|
| `./` | Root facade |
| `ast/` | AST node types |
| `lexer/` | Tokenizer |
| `token/` | Token types |
| `parser/` | Parser |
| `interpreter/` | Tree-walk interpreter |
| `errors/` | Error types |
| `cmd/main/` | CLI entry point |

## Commands

```bash
moon check && moon test   # Lint + test
moon info && moon fmt     # Before committing
```

## Documentation

- `ROADMAP.md` — test262 pass rate, failure breakdown, next phase targets, architecture decisions
- `docs/PHASE_HISTORY.md` — Archived implementation notes for completed phases
- `README.md` — Project overview, usage, package structure

## Key Facts

**Tasks:** See `agent-todo.md` for small AI-friendly tasks
