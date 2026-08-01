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

The permanent stack-safety gate runs only the focused engine and facade suites
for one explicitly supplied target/profile. `TARGET` accepts `native`, `js`,
`wasm`, or `wasm-gc`; `PROFILE` accepts `debug` or `release`:

```bash
make stack-safety-test TARGET=js PROFILE=debug
make stack-safety-test TARGET=js PROFILE=release
```

The adoption workflow runs both profiles for `native`, `js`, `wasm`, and
`wasm-gc`. Each profile uses the same checked-in JavaScript source and expected
result. The gate deliberately does not include the deferred #608 mixed-call or
success-valued 512-comma runtime workloads.

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

## Hono reference workload

`hono_acceptance_test.mbt` runs the default `hono` entry and its default
`SmartRouter` as a cross-target reference workload. The scenario performs one
`GET /hello/Ada?lang=moon`, checks route and path-parameter matching, reads the
query parameter, produces a JSON response, and observes asynchronous middleware
in `before`, `handler`, `after` order. It uses only the stable root facade:
`Engine::eval` loads the JavaScript pieces, the host explicitly runs
`Engine::run_microtask_checkpoint`, and `Engine::call_json` retrieves a saved,
plain JSON-compatible result. No Promise crosses the JSON bridge.

Before the Web shim was installed, the same bundled Hono request path stopped
at `app.request()` with `ReferenceError: Request is not defined`. The shim is
therefore test infrastructure at the documented Web boundary, not a Hono patch
or a new `js_engine` builtin.

### Pinned bundle and reproduction

The checked-in `hono_4_12_31_bundle_test.mbt` embeds exactly 65,441 bytes with
SHA-256
`124d47855cb3c634399e04819f8bdeb5da8848b17d989d9099b98bd3e2f16603`.
It is generated from the unmodified default ESM entry `package/dist/index.js`
in `hono@4.12.31` using `esbuild@0.27.7`:

```text
esbuild entry.mjs --bundle --format=iife --platform=neutral --target=esnext
```

The upstream npm tarball is
`https://registry.npmjs.org/hono/-/hono-4.12.31.tgz`, with SHA-256
`d32c7ffb9ea3f7c9268d4f942e811a4bcd11afd96ece7b3a47d7ba96b6ed0596`.
Regenerate and verify both the tarball and bundle pins from the repository root:

```bash
node scripts/generate_hono_acceptance_fixture.mjs
```

The generator uses a temporary directory, runs `npm pack hono@4.12.31
--ignore-scripts`, bundles only an entry that imports `Hono` from the default
ESM module and saves it on `globalThis`, and aborts if either byte size or hash
differs. It does not downlevel syntax, patch Hono, or inject Web polyfills.

### Test-only Web shim boundary

The complete shim surface is:

- `Headers`: construction from another shim `Headers`, an array of pairs, or an
  enumerable object; `append`, `delete`, `get`, `has`, `set`, `entries`,
  `forEach`, and iteration. Names are lowercased and values are string-coerced.
- `Request`: construction from another shim `Request` or a string-coercible URL,
  plus `method`, `headers`, and `body` initialization.
- `Response`: `body`, `status`, and `headers` initialization plus an asynchronous
  `text()` method.

Everything else is intentionally unsupported by this fixture. In particular it
does not provide request body readers, cloning, abort signals, streams,
`ReadableStream`, multipart/form-data, complete Fetch header validation or
multi-value `Set-Cookie` behavior, network or server adapters, sockets,
WebSockets, Node.js APIs, a DOM, filesystem access, or a general Web Platform.
Hono routes and middleware that depend on those facilities are outside this
acceptance claim.
