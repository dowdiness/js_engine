# External-consumer acceptance fixture

This standalone MoonBit module exercises the stable root `dowdiness/js_engine`
facade from outside the library module. The parent [`moon.work`](../moon.work)
resolves the fixture's versioned dependency to the repository checkout under
review, so pull-request CI tests candidate source rather than the published
Mooncakes package.

From the repository root, run:

```bash
make external-consumer-test TARGET=native
```

The adoption workflow repeats this repository command for `native`, `js`,
`wasm`, and `wasm-gc`. The repository architecture-boundary audit permits this
fixture to import only the root facade; direct imports of interpreter, runtime,
parser, AST, or compiler packages fail the audit.

The user-facing [`example/rule_engine`](../../example/rule_engine/) remains the
runnable example. This module is an independent black-box acceptance test of
the stable contract, so it deliberately does not share implementation code with
that example.

This checkout-under-review fixture is separate from the release checklist's
smoke test of the package installed from Mooncakes.
