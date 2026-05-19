.PHONY: build test architecture-state-audit architecture-state-audit-test test262 test262-quick test262-analyze test262-validate-skips test262-download test262-report unicode-tables clean

# Build the JS engine
build:
	moon build

# Run MoonBit unit tests
test:
	moon test

# Guardrail for the realm-state migration track.
architecture-state-audit: architecture-state-audit-test
	python3 scripts/architecture-state-audit.py

architecture-state-audit-test:
	python3 scripts/architecture_state_audit_test.py

# Download the Test262 test suite
test262-download:
	@if [ ! -d "test262/test" ]; then \
		echo "Downloading Test262..."; \
		curl -fsSL -L "https://api.github.com/repos/tc39/test262/tarball/main" -o /tmp/test262.tar.gz; \
		mkdir -p test262; \
		tar -xzf /tmp/test262.tar.gz -C test262 --strip-components=1; \
		echo "Test262 downloaded."; \
	else \
		echo "Test262 already present."; \
	fi

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
test262-analyze: test262-download
	python3 scripts/test262-analyze.py \
		--test262 ./test262 \
		--output test262-analysis.json

# Check that shared skip metadata still matches the checked-out Test262 suite.
# This does not run tests or produce conformance numbers.
test262-validate-skips: test262-download
	python3 scripts/validate-test262-skip-metadata.py \
		--test262 ./test262

# Download the latest Test262 CI results and print a paste-ready report.
# Pass ARGS="..." to forward flags, e.g. make test262-report ARGS="--run 24730849102"
test262-report:
	python3 scripts/report-test262.py --with-editions $(ARGS)

# Regenerate lexer/unicode_id.mbt from DerivedCoreProperties.txt.
# Pass UNICODE_VERSION=X.Y.Z to target a specific Unicode release (default: 17.0.0).
unicode-tables:
	python3 scripts/generate-unicode-id-tables.py $(if $(UNICODE_VERSION),--unicode-version $(UNICODE_VERSION))

# Clean build artifacts
clean:
	moon clean
	rm -f test262-results.json test262-analysis.json
