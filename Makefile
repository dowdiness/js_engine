.PHONY: build test bench-focus bench-focus-test bench-focus-mbt subprocess-helpers-mbt-test architecture-state-audit architecture-state-audit-mbt architecture-state-audit-mbt-test architecture-state-audit-test test262 test262-contract-test test262-metadata-test test262-metadata-mbt-test test262-metadata-tools-mbt-test test262-utils-test test262-utils-mbt-test test262-utils-corpus-test test262-utils-corpus-mbt test262-runner-test test262-quick test262-analyze test262-analyze-mbt test262-validate-skips test262-validate-skips-mbt test262-classify-by-edition-mbt classify-by-edition-mbt test262-compare-results test262-download test262-report test262-report-test test262-report-mbt unicode-tables unicode-tables-test unicode-tables-mbt clean

TEST262_COMMIT ?= main

# Build the JS engine
build:
	moon build

# Run MoonBit unit tests
test:
	moon test

# Shadow subprocess/network helper tests. Python scripts remain authoritative.
subprocess-helpers-mbt-test:
	moon test --target native tooling/subprocess_helpers

bench-focus-test: subprocess-helpers-mbt-test
	python3 scripts/bench_focus_test.py

bench-focus:
	python3 scripts/bench-focus.py $(ARGS)

bench-focus-mbt: subprocess-helpers-mbt-test
	moon build --target native cmd/bench_focus
	@if [ -n "$(ARGS)" ]; then \
		./_build/native/debug/build/cmd/bench_focus/bench_focus.exe $(ARGS); \
	else \
		echo "built cmd/bench_focus (pass ARGS='--runs 1 ...' to run)"; \
	fi

# Guardrail for the realm-state migration track.
# Keep Python authoritative while requiring the MoonBit shadow to build and match.
architecture-state-audit: architecture-state-audit-test architecture-state-audit-mbt
	python3 scripts/architecture-state-audit.py

architecture-state-audit-mbt: architecture-state-audit-mbt-test
	moon build --target native cmd/architecture_state_audit
	./_build/native/debug/build/cmd/architecture_state_audit/architecture_state_audit.exe --root .

architecture-state-audit-mbt-test:
	moon test --target native tooling/architecture_state_audit

architecture-state-audit-test:
	python3 scripts/architecture_state_audit_test.py

# Download the Test262 test suite
test262-download:
	@if [ ! -d "test262/test" ]; then \
		echo "Downloading Test262 ($(TEST262_COMMIT))..."; \
		curl -fsSL -L "https://api.github.com/repos/tc39/test262/tarball/$(TEST262_COMMIT)" -o /tmp/test262.tar.gz; \
		mkdir -p test262; \
		tar -xzf /tmp/test262.tar.gz -C test262 --strip-components=1; \
		echo "Test262 downloaded."; \
	else \
		echo "Test262 already present."; \
	fi

# Unit tests for Test262 artifact contracts and parity helpers.
test262-contract-test:
	python3 scripts/compare_test262_results_test.py
	python3 scripts/classify_by_edition_test.py
	python3 scripts/report_test262_test.py

# Shared Test262 metadata tests. Python remains authoritative; MoonBit shadows it.
test262-metadata-test: test262-metadata-mbt-test test262-metadata-tools-mbt-test
	python3 scripts/test262_skip_metadata_test.py
	python3 scripts/validate_test262_skip_metadata_test.py

test262-metadata-mbt-test:
	moon test --target native tooling/test262_metadata

test262-metadata-tools-mbt-test:
	moon test --target native tooling/test262_metadata_tools

# Shared Test262 frontmatter utility tests. Python remains authoritative; MoonBit shadows it.
test262-utils-test: test262-utils-mbt-test
	python3 scripts/test262_utils_test.py

test262-utils-mbt-test:
	moon test --target native tooling/test262_utils

test262-utils-corpus-mbt:
	moon build --target native cmd/test262_utils_corpus

test262-utils-corpus-test: test262-download test262-utils-corpus-mbt
	@set -e; \
	tmp="$$(mktemp)"; \
	trap 'rm -f "$$tmp"' EXIT; \
	./_build/native/debug/build/cmd/test262_utils_corpus/test262_utils_corpus.exe \
		--test262 ./test262 \
		--output "$$tmp"; \
	python3 scripts/test262_utils_corpus_test.py \
		--test262 ./test262 \
		--moonbit-output "$$tmp" \
		--yaml-mode fallback

# Unit tests for Test262 runner task selection and harness helpers.
test262-runner-test: test262-contract-test
	python3 scripts/test262_runner_task_selection_test.py
	python3 scripts/test262_runner_harness_test.py

# Compare two Test262 result artifacts under the migration parity contract.
# Pass ARGS="left.json right.json [--ignore-reason]".
test262-compare-results:
	python3 scripts/compare-test262-results.py $(ARGS)

# Run the full Test262 conformance suite
test262: build test262-download
	python3 scripts/test262-runner.py \
		--engine "moon run cmd/main --" \
		--test262 ./test262 \
		--output test262-results.json

# Run a quick subset of Test262 (language/literals only)
test262-quick: build test262-download
	python3 scripts/test262-runner.py \
		--engine "moon run cmd/main --" \
		--test262 ./test262 \
		--filter "language/literals" \
		--timeout 10 \
		--output test262-results.json \
		--verbose

# Run Test262 for a specific category (e.g., make test262-filter FILTER=language/expressions)
test262-filter: build test262-download
	python3 scripts/test262-runner.py \
		--engine "moon run cmd/main --" \
		--test262 ./test262 \
		--filter "$(FILTER)" \
		--timeout 10 \
		--output test262-results.json \
		--verbose

# Non-authoritative static metadata analysis (no engine build required).
# Use scripts/test262-runner.py / CI artifacts for conformance and skip truth.
# Shared skip metadata only prevents runner/analyzer drift.
test262-analyze: test262-download test262-analyze-mbt
	python3 scripts/test262-analyze.py \
		--test262 ./test262 \
		--output test262-analysis.json
	python3 -c 'import json, sys; from pathlib import Path; expected = json.loads(Path("test262-analysis.json").read_text()); actual = json.loads(Path("test262-analysis.moonbit-shadow.json").read_text()); keys = ("summary", "complexity", "categories", "feature_gaps"); mismatches = [key for key in keys if expected.get(key) != actual.get(key)]; sys.exit("MoonBit shadow test262-analyze mismatch in " + mismatches[0]) if mismatches else print("ok: MoonBit shadow test262-analyze summary/category output matches Python")'

test262-analyze-mbt: test262-download test262-metadata-tools-mbt-test
	moon build --target native cmd/test262_analyze
	./_build/native/debug/build/cmd/test262_analyze/test262_analyze.exe \
		--test262 ./test262 \
		--output test262-analysis.moonbit-shadow.json

# Check that shared skip metadata still matches the checked-out Test262 suite.
# This does not run tests or produce conformance numbers.
test262-validate-skips: test262-download test262-validate-skips-mbt
	python3 scripts/validate-test262-skip-metadata.py \
		--test262 ./test262

test262-validate-skips-mbt: test262-download test262-metadata-tools-mbt-test
	moon build --target native cmd/test262_validate_skips
	./_build/native/debug/build/cmd/test262_validate_skips/test262_validate_skips.exe \
		--test262 ./test262

# Build/run the MoonBit shadow edition classifier over existing result artifacts.
# Pass ARGS="[--test262-root .] result.json ..." to run it; this never runs the engine.
test262-classify-by-edition-mbt: test262-metadata-tools-mbt-test
	moon build --target native cmd/classify_by_edition
	@if [ -n "$(ARGS)" ]; then \
		./_build/native/debug/build/cmd/classify_by_edition/classify_by_edition.exe $(ARGS); \
	else \
		echo "built cmd/classify_by_edition (pass ARGS='result.json ...' to run)"; \
	fi

classify-by-edition-mbt: test262-classify-by-edition-mbt

# Download the latest Test262 CI results and print a paste-ready report.
# Pass ARGS="..." to forward flags, e.g. make test262-report ARGS="--run 24730849102"
test262-report-test: test262-contract-test subprocess-helpers-mbt-test

test262-report:
	python3 scripts/report-test262.py --with-editions $(ARGS)

test262-report-mbt: subprocess-helpers-mbt-test
	moon build --target native cmd/report_test262
	@if [ -n "$(ARGS)" ]; then \
		./_build/native/debug/build/cmd/report_test262/report_test262.exe $(ARGS); \
	else \
		echo "built cmd/report_test262 (pass ARGS='--run ...' to run; does not run the engine)"; \
	fi

# Regenerate lexer/unicode_id.mbt from DerivedCoreProperties.txt.
# Pass UNICODE_VERSION=X.Y.Z to target a specific Unicode release (default: 17.0.0).
unicode-tables-test: subprocess-helpers-mbt-test
	python3 scripts/generate_unicode_id_tables_test.py

unicode-tables:
	python3 scripts/generate-unicode-id-tables.py $(if $(UNICODE_VERSION),--unicode-version $(UNICODE_VERSION))

unicode-tables-mbt: subprocess-helpers-mbt-test
	moon build --target native cmd/generate_unicode_id_tables
	@if [ -n "$(ARGS)" ]; then \
		./_build/native/debug/build/cmd/generate_unicode_id_tables/generate_unicode_id_tables.exe $(ARGS); \
	else \
		echo "built cmd/generate_unicode_id_tables (pass ARGS='--output /tmp/unicode_id.mbt' to fetch/generate)"; \
	fi

# Clean build artifacts
clean:
	moon clean
	rm -f test262-results.json test262-analysis.json test262-analysis.moonbit-shadow.json
