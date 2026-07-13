.PHONY: build test bench-focus bench-focus-mbt subprocess-helpers-mbt-test architecture-audit architecture-boundary-audit architecture-boundary-audit-mbt architecture-boundary-audit-mbt-test architecture-state-audit architecture-state-audit-mbt architecture-state-audit-mbt-test test262 test262-metadata-test test262-metadata-mbt-test test262-metadata-tools-mbt-test test262-utils-test test262-utils-mbt-test test262-utils-corpus-mbt test262-runner-test test262-runner-mbt-test test262-runner-mbt test262-quick test262-filter test262-analyze test262-analyze-mbt test262-validate-skips test262-validate-skips-mbt test262-classify-by-edition-mbt classify-by-edition-mbt test262-download test262-report test262-report-test test262-report-mbt test262-skip-report test262-feature-gap test262-feature-gap-test validate-docs-skip-policy validate-docs-skip-policy-test unicode-tables unicode-tables-mbt clean

TEST262_COMMIT ?= main

# Build the JS engine
build:
	moon build

# Run MoonBit unit tests
test:
	moon test

# Ensure the native core bundle exists (required for `moon build --target native`).
# Runs `moon bundle` on the installed core library, which links individual .core
# files into bundle/core.core. Idempotent — fast skips when already up to date.
# Needed after `moon clean` or a toolchain upgrade.
native-core-bundle:
	cd ~/.moon/lib/core && moon bundle --target native

# MoonBit subprocess helper tests.
subprocess-helpers-mbt-test: native-core-bundle
	moon test --target native tooling/subprocess_helpers

# MoonBit native is authoritative.
bench-focus: subprocess-helpers-mbt-test
	moon build --target native cmd/bench_focus
	./_build/native/debug/build/cmd/bench_focus/bench_focus.exe $(ARGS)

bench-focus-mbt: subprocess-helpers-mbt-test
	moon build --target native cmd/bench_focus
	@if [ -n "$(ARGS)" ]; then \
		./_build/native/debug/build/cmd/bench_focus/bench_focus.exe $(ARGS); \
	else \
		echo "built cmd/bench_focus (pass ARGS='--runs 1 ...' to run)"; \
	fi

# Runs the MoonBit architecture state audit.
architecture-state-audit: architecture-state-audit-mbt

architecture-state-audit-mbt: architecture-state-audit-mbt-test
	moon build --target native cmd/architecture_state_audit
	./_build/native/debug/build/cmd/architecture_state_audit/architecture_state_audit.exe --root .

architecture-state-audit-mbt-test:
	moon test --target native tooling/architecture_state_audit

# Runs the Stage 0 architecture guardrails.
architecture-audit: architecture-state-audit architecture-boundary-audit

# Runs the MoonBit architecture import-boundary and representation-access audit.
architecture-boundary-audit: architecture-boundary-audit-mbt

architecture-boundary-audit-mbt: architecture-boundary-audit-mbt-test
	moon build --target native cmd/architecture_boundary_audit
	./_build/native/debug/build/cmd/architecture_boundary_audit/architecture_boundary_audit.exe --root .

architecture-boundary-audit-mbt-test:
	moon test --target native tooling/architecture_boundary_audit

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

# Shared Test262 metadata tests.
test262-metadata-test: test262-metadata-mbt-test test262-metadata-tools-mbt-test

test262-metadata-mbt-test:
	moon test --target native tooling/test262_metadata

test262-metadata-tools-mbt-test:
	moon test --target native tooling/test262_metadata_tools

# Shared Test262 frontmatter utility tests.
test262-utils-test: test262-utils-mbt-test

test262-utils-mbt-test:
	moon test --target native tooling/test262_utils

test262-utils-corpus-mbt:
	moon build --target native cmd/test262_utils_corpus

# Unit tests for the MoonBit runner with a curated real-Test262 parity slice.
test262-runner-test: test262-download test262-runner-mbt-test

test262-runner-mbt-test:
	moon test --target native tooling/test262_runner

# Build/run the authoritative MoonBit async Test262 runner.
# Pass ARGS="--mode strict --count 10 ..." to run it.
test262-runner-mbt: test262-runner-mbt-test
	moon build --target native cmd/test262_runner
	@if [ -n "$(ARGS)" ]; then \
		./_build/native/debug/build/cmd/test262_runner/test262_runner.exe $(ARGS); \
	else \
		echo "built cmd/test262_runner (pass ARGS='--count 10 ...' to run)"; \
	fi

# Run the full Test262 conformance suite (MoonBit native authoritative).
test262: build test262-download
	moon build --target native cmd/test262_runner
	./_build/native/debug/build/cmd/test262_runner/test262_runner.exe \
		--engine "moon run cmd/main --" \
		--test262 ./test262 \
		--output test262-results.json

# Run a quick subset of Test262 (language/literals only).
test262-quick: build test262-download
	moon build --target native cmd/test262_runner
	./_build/native/debug/build/cmd/test262_runner/test262_runner.exe \
		--engine "moon run cmd/main --" \
		--test262 ./test262 \
		--filter "language/literals" \
		--timeout 120 \
		--output test262-results.json \
		--verbose

# Run Test262 for a specific category (e.g., make test262-filter FILTER=language/expressions).
test262-filter: build test262-download
	moon build --target native cmd/test262_runner
	./_build/native/debug/build/cmd/test262_runner/test262_runner.exe \
		--engine "moon run cmd/main --" \
		--test262 ./test262 \
		--filter "$(FILTER)" \
		--timeout 120 \
		--output test262-results.json \
		--verbose

# Runs the MoonBit static metadata analysis (no engine build required).
test262-analyze: test262-download test262-metadata-tools-mbt-test
	moon build --target native cmd/test262_analyze
	./_build/native/debug/build/cmd/test262_analyze/test262_analyze.exe \
		--test262 ./test262 \
		--output test262-analysis.json

test262-analyze-mbt: test262-download test262-metadata-tools-mbt-test
	moon build --target native cmd/test262_analyze
	./_build/native/debug/build/cmd/test262_analyze/test262_analyze.exe \
		--test262 ./test262 \
		--output test262-analysis.moonbit-shadow.json

# Check that shared skip metadata still matches the checked-out Test262 suite.
# This does not run tests or produce conformance numbers.
test262-validate-skips: test262-validate-skips-mbt

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
test262-report-test: subprocess-helpers-mbt-test

# MoonBit native is authoritative. Builds classify_by_edition for --with-editions.
test262-report: subprocess-helpers-mbt-test
	moon build --target native cmd/report_test262
	moon build --target native cmd/classify_by_edition
	./_build/native/debug/build/cmd/report_test262/report_test262.exe --with-editions $(ARGS)

test262-report-mbt: subprocess-helpers-mbt-test
	moon build --target native cmd/report_test262
	@if [ -n "$(ARGS)" ]; then \
		./_build/native/debug/build/cmd/report_test262/report_test262.exe $(ARGS); \
	else \
		echo "built cmd/report_test262 (pass ARGS='--run ...' to run; does not run the engine)"; \
	fi

# Render a human-readable Test262 skip-policy report from shared metadata.
# Output path defaults to docs/test262-skip-report.md for easy review.
test262-skip-report:
	python3 scripts/test262_skip_report.py \
		--metadata scripts/test262_skip_metadata.json \
		--output docs/test262-skip-report.md

# Compare this repo's skip metadata against an external Test262 feature config.
# Pass EXT_CONFIG=/path/to/config.ini; output goes to docs/test262-feature-gap.md.
# This is a planning signal only — it does not run tests or report pass rates.
test262-feature-gap:
	python3 scripts/test262_feature_gap.py \
		--ext-config $(EXT_CONFIG) \
		--output docs/test262-feature-gap.md

# Run Python unit tests for the feature-gap comparison script.
test262-feature-gap-test:
	python3 -m unittest scripts/test_test262_feature_gap.py -v

# Validate active intent docs against shared skip metadata (fast policy guard).
validate-docs-skip-policy: validate-docs-skip-policy-test
	python3 scripts/validate_docs_skip_policy.py

validate-docs-skip-policy-test:
	python3 -m unittest scripts/test_validate_docs_skip_policy.py -v

# Regenerate lexer/unicode_id.mbt from DerivedCoreProperties.txt.
# Pass UNICODE_VERSION=X.Y.Z to target a specific Unicode release (default: 17.0.0).
# MoonBit native is authoritative.
unicode-tables: subprocess-helpers-mbt-test
	moon build --target native cmd/generate_unicode_id_tables
	./_build/native/debug/build/cmd/generate_unicode_id_tables/generate_unicode_id_tables.exe $(if $(UNICODE_VERSION),--unicode-version $(UNICODE_VERSION))

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
