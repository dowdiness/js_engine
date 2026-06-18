# Supported Features

This page is a **dated Test262 snapshot**, not a hand-maintained support claim.
For headline release text, regenerate from CI artifacts with `make test262-report`.
For active priorities, see [ROADMAP.md](ROADMAP.md).

Snapshot source: Test262 CI run
[27737766095](https://github.com/dowdiness/js_engine/actions/runs/27737766095),
workflow **Test262 Conformance**, conclusion **success**, head
`001ef3d2ed9317788f6fe35f72f1335d2463ddc8`, created 2026-06-18.

Each Test262 file is reported per mode. Do **not** sum strict and non-strict
figures; that double-counts files. Cells below use `Passed/Failed/Skipped
(Passed / Executed, Passed / Discovered)` unless otherwise noted.

## Refreshing

```bash
make test262-report
make test262-report ARGS="--format=changelog"
```

`make test262-report` includes edition tables by default. The native
`cmd/report_test262` and CI artifacts are authoritative for these numbers.

---

## Headline by mode

| Mode | Discovered | Skipped | Executed | Passed | Failed | Timeout/Err | Passed / Executed | Passed / Discovered |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| strict | 44,986 | 18,100 | 26,857 | 25,597 | 1,260 | 29 | **95.3%** | 56.9% |
| non-strict | 47,692 | 18,641 | 29,016 | 27,267 | 1,749 | 35 | **94.0%** | 57.2% |

---

## Per-edition pass rates

### strict

| Edition | Discovered | Skipped | Executed | Passed | Failed | Timeout/Err | Passed / Executed | Passed / Discovered |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Pre-ES2015 (baseline) | 13,281 | 0 | 13,265 | 12,836 | 429 | 16 | 96.8% | 96.6% |
| ES2015 | 10,300 | 154 | 10,134 | 9,718 | 416 | 12 | 95.9% | 94.3% |
| ES2016 | 100 | 11 | 89 | 88 | 1 | 0 | 98.9% | 88.0% |
| ES2017 | 736 | 344 | 392 | 349 | 43 | 0 | 89.0% | 47.4% |
| ES2018 | 4,725 | 4,326 | 399 | 379 | 20 | 0 | 95.0% | 8.0% |
| ES2019 | 128 | 0 | 128 | 104 | 24 | 0 | 81.3% | 81.3% |
| ES2020 | 1,784 | 1,537 | 247 | 237 | 10 | 0 | 96.0% | 13.3% |
| ES2021 | 468 | 128 | 340 | 303 | 37 | 0 | 89.1% | 64.7% |
| ES2022 | 5,065 | 4,352 | 713 | 708 | 5 | 0 | 99.3% | 14.0% |
| ES2023 | 254 | 38 | 216 | 211 | 5 | 0 | 97.7% | 83.1% |
| ES2024 | 1,072 | 866 | 206 | 107 | 99 | 0 | 51.9% | 10.0% |
| ES2025 | 1,148 | 779 | 369 | 295 | 74 | 0 | 79.9% | 25.7% |
| Annex B | 365 | 46 | 318 | 254 | 64 | 1 | 79.9% | 69.6% |
| Stage 3 | 5,531 | 5,519 | 12 | 6 | 6 | 0 | 50.0% | 0.1% |
| Unmapped | 29 | 0 | 29 | 2 | 27 | 0 | 6.9% | 6.9% |
| **Total** | **44,986** | **18,100** | **26,857** | **25,597** | **1,260** | **29** | **95.3%** | **56.9%** |

### non-strict

| Edition | Discovered | Skipped | Executed | Passed | Failed | Timeout/Err | Passed / Executed | Passed / Discovered |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Pre-ES2015 (baseline) | 13,917 | 0 | 13,897 | 13,292 | 605 | 20 | 95.6% | 95.5% |
| ES2015 | 10,788 | 153 | 10,623 | 10,167 | 456 | 12 | 95.7% | 94.2% |
| ES2016 | 100 | 11 | 89 | 88 | 1 | 0 | 98.9% | 88.0% |
| ES2017 | 775 | 344 | 431 | 381 | 50 | 0 | 88.4% | 49.2% |
| ES2018 | 4,781 | 4,384 | 397 | 377 | 20 | 0 | 95.0% | 7.9% |
| ES2019 | 127 | 0 | 127 | 103 | 24 | 0 | 81.1% | 81.1% |
| ES2020 | 1,984 | 1,610 | 374 | 316 | 58 | 0 | 84.5% | 15.9% |
| ES2021 | 444 | 128 | 316 | 279 | 37 | 0 | 88.3% | 62.8% |
| ES2022 | 5,361 | 4,628 | 733 | 727 | 6 | 0 | 99.2% | 13.6% |
| ES2023 | 277 | 61 | 216 | 211 | 5 | 0 | 97.7% | 76.2% |
| ES2024 | 1,077 | 870 | 207 | 108 | 99 | 0 | 52.2% | 10.0% |
| ES2025 | 1,180 | 813 | 367 | 293 | 74 | 0 | 79.8% | 24.8% |
| Annex B | 1,156 | 46 | 1,107 | 913 | 194 | 3 | 82.5% | 79.0% |
| Stage 3 | 5,696 | 5,593 | 103 | 10 | 93 | 0 | 9.7% | 0.2% |
| Unmapped | 29 | 0 | 29 | 2 | 27 | 0 | 6.9% | 6.9% |
| **Total** | **47,692** | **18,641** | **29,016** | **27,267** | **1,749** | **35** | **94.0%** | **57.2%** |

---

## Top failure categories

Top 25 categories by failure count in the worst mode for this run.

| Category | strict | non-strict |
|---|---:|---:|
| language/expressions | 5,604/214/4,568 (96.3%, 54.0%) | 5,744/320/4,712 (94.7%, 53.3%) |
| built-ins/Array | 2,723/189/117 (93.0%, 89.4%) | 2,750/187/117 (93.1%, 89.6%) |
| language/statements | 4,334/113/4,404 (97.5%, 49.0%) | 4,537/176/4,437 (96.3%, 49.6%) |
| annexB/language | 15/11/26 (57.7%, 28.8%) | 676/141/26 (82.7%, 80.2%) |
| built-ins/Object | 3,277/96/24 (97.1%, 96.4%) | 3,273/102/24 (96.9%, 96.2%) |
| built-ins/String | 1,116/91/12 (92.4%, 91.5%) | 1,119/91/12 (92.4%, 91.5%) |
| language/import | 6/0/0 (100.0%, 100.0%) | 12/86/29 (12.2%, 9.4%) |
| built-ins/Function | 312/80/29 (79.6%, 74.1%) | 340/82/50 (80.6%, 72.0%) |
| language/eval-code | 111/11/1 (91.0%, 90.2%) | 260/70/1 (78.8%, 78.5%) |
| built-ins/Uint8Array | 8/60/0 (11.8%, 11.8%) | 8/60/0 (11.8%, 11.8%) |
| built-ins/Promise | 618/53/3 (92.1%, 91.7%) | 618/53/3 (92.1%, 91.7%) |
| built-ins/RegExp | 832/50/990 (93.7%, 44.3%) | 831/50/990 (93.6%, 44.2%) |
| built-ins/JSON | 91/44/30 (67.4%, 55.2%) | 91/44/30 (67.4%, 55.2%) |
| annexB/built-ins | 191/31/19 (86.0%, 79.3%) | 189/31/19 (85.1%, 78.4%) |
| language/arguments-object | 105/1/100 (99.1%, 51.0%) | 122/30/102 (80.3%, 48.0%) |
| built-ins/Proxy | 242/20/37 (92.4%, 80.9%) | 252/20/36 (92.6%, 81.8%) |
| language/statementList | 60/20/0 (75.0%, 75.0%) | 60/20/0 (75.0%, 75.0%) |
| built-ins/Date | 564/19/11 (96.7%, 94.9%) | 564/19/11 (96.7%, 94.9%) |
| built-ins/GeneratorPrototype | 45/16/0 (73.8%, 73.8%) | 45/16/0 (73.8%, 73.8%) |
| language/literals | 364/14/142 (96.3%, 70.0%) | 358/14/142 (95.5%, 69.2%) |
| built-ins/Number | 322/13/3 (96.1%, 95.3%) | 322/13/3 (96.1%, 95.3%) |
| language/global-code | 21/12/4 (63.6%, 56.8%) | 22/12/4 (64.7%, 57.9%) |
| built-ins/AggregateError | 15/9/1 (62.5%, 60.0%) | 15/9/1 (62.5%, 60.0%) |
| built-ins/Set | 370/9/3 (97.6%, 96.9%) | 370/9/3 (97.6%, 96.9%) |
| built-ins/Reflect | 145/8/0 (94.8%, 94.8%) | 145/8/0 (94.8%, 94.8%) |

---

## Well-supported larger categories

Categories below have at least 20 executed tests in each mode and at least 95%
Passed / Executed in both modes in this run.

| Category | strict | non-strict |
|---|---:|---:|
| language/statements | 4,334/113/4,404 (97.5%, 49.0%) | 4,537/176/4,437 (96.3%, 49.6%) |
| built-ins/Object | 3,277/96/24 (97.1%, 96.4%) | 3,273/102/24 (96.9%, 96.2%) |
| built-ins/TypedArray | 775/2/653 (99.7%, 54.2%) | 775/2/653 (99.7%, 54.2%) |
| built-ins/Date | 564/19/11 (96.7%, 94.9%) | 564/19/11 (96.7%, 94.9%) |
| built-ins/Set | 370/9/3 (97.6%, 96.9%) | 370/9/3 (97.6%, 96.9%) |
| built-ins/DataView | 377/0/184 (100.0%, 67.2%) | 377/0/184 (100.0%, 67.2%) |
| language/literals | 364/14/142 (96.3%, 70.0%) | 358/14/142 (95.5%, 69.2%) |
| built-ins/TypedArrayConstructors | 359/0/361 (100.0%, 49.9%) | 360/0/362 (100.0%, 49.9%) |
| built-ins/Number | 322/13/3 (96.1%, 95.3%) | 322/13/3 (96.1%, 95.3%) |
| built-ins/Math | 315/7/5 (97.8%, 96.3%) | 315/7/5 (97.8%, 96.3%) |
| language/identifiers | 208/0/60 (100.0%, 77.6%) | 207/0/60 (100.0%, 77.5%) |
| built-ins/Map | 200/0/3 (100.0%, 98.5%) | 199/0/3 (100.0%, 98.5%) |
| language/function-code | 108/0/0 (100.0%, 100.0%) | 169/4/0 (97.7%, 97.7%) |
| built-ins/WeakMap | 134/6/1 (95.7%, 95.0%) | 133/6/1 (95.7%, 95.0%) |
| language/block-scope | 126/0/19 (100.0%, 86.9%) | 123/0/19 (100.0%, 86.6%) |
| language/types | 98/4/2 (96.1%, 94.2%) | 100/5/2 (95.2%, 93.5%) |
| language/asi | 102/0/0 (100.0%, 100.0%) | 102/0/0 (100.0%, 100.0%) |
| built-ins/NativeErrors | 86/2/6 (97.7%, 91.5%) | 86/2/6 (97.7%, 91.5%) |
| built-ins/WeakSet | 83/1/1 (98.8%, 97.6%) | 83/1/1 (98.8%, 97.6%) |
| built-ins/ArrayBuffer | 80/0/116 (100.0%, 40.8%) | 80/0/116 (100.0%, 40.8%) |

---

## Large skipped categories in this run

These counts are category-level skipped counts from the same CI artifacts. They
are not feature flags by themselves; one skipped feature may affect multiple
categories.

| Category | strict skipped | non-strict skipped |
|---|---:|---:|
| language/expressions | 4,568 | 4,712 |
| built-ins/Temporal | 4,584 | 4,584 |
| language/statements | 4,404 | 4,437 |
| built-ins/RegExp | 990 | 990 |
| built-ins/TypedArray | 653 | 653 |
| built-ins/Iterator | 505 | 505 |
| built-ins/Atomics | 376 | 376 |
| built-ins/TypedArrayConstructors | 361 | 362 |
| language/module-code | 3 | 280 |
| built-ins/DataView | 184 | 184 |
| language/literals | 142 | 142 |
| built-ins/Array | 117 | 117 |
| built-ins/ArrayBuffer | 116 | 116 |
| built-ins/AsyncDisposableStack | 104 | 104 |
| built-ins/SharedArrayBuffer | 104 | 104 |
| language/arguments-object | 100 | 102 |

## Shared skip metadata

The runner's shared skip metadata is `scripts/test262_skip_metadata.json`. At
the time of this snapshot, feature skips include:

- `Atomics`, `BigInt`, `FinalizationRegistry`, `Float16Array`, `IsHTMLDDA`,
  `RegExp.escape`, `ShadowRealm`, `SharedArrayBuffer`, `Temporal`, `WeakRef`.
- `async-iteration`, `caller`, `cross-realm`, `decorators`, `dynamic-import`,
  `explicit-resource-management`, `for-in-order`, `hashbang`,
  `immutable-arraybuffer`, `import-attributes`,
  `import.meta`, `intl-normative-optional`, `iterator-helpers`,
  `iterator-sequencing`, `joint-iteration`, `json-modules`,
  `json-parse-with-source`, `source-phase-imports`,
  `source-phase-imports-module-source`, `tail-call-optimization`,
  `top-level-await`.
- Private class features: `class-fields-private`, `class-methods-private`,
  `class-static-block`, `class-static-fields-private`,
  `class-static-methods-private`.
- RegExp features: `regexp-lookbehind`, `regexp-match-indices`,
  `regexp-modifiers`, `regexp-unicode-property-escapes`, `regexp-v-flag`.
- ArrayBuffer features: `resizable-arraybuffer` and `arraybuffer-transfer`.

The runner also skips Test262 flags `CanBlockIsFalse` and `CanBlockIsTrue`, plus
a small set of path-specific int64 array-index cases recorded in the same JSON
file.
