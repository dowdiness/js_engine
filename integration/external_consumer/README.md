# External-consumer acceptance fixture

This standalone MoonBit module exercises the stable root `dowdiness/js_engine`
facade from outside the library module. The parent [`moon.work`](../moon.work)
resolves the fixture's versioned dependency to the repository checkout under
review, so pull-request CI tests candidate source rather than the published
Mooncakes package.

From this directory, run:

```bash
moon check --target native .
moon test --target native .
```

The adoption workflow repeats these commands for `native`, `js`, `wasm`, and
`wasm-gc`. The repository architecture-boundary audit permits this fixture to
import only the root facade; direct imports of interpreter, runtime, parser,
AST, or compiler packages fail the audit.

This checkout-under-review fixture is separate from the release checklist's
smoke test of the package installed from Mooncakes.
