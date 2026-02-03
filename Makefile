.PHONY: build test test262 test262-quick test262-analyze test262-download clean

# Build the JS engine
build:
	moon build

# Run MoonBit unit tests
test:
	moon test

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

# Run the full Test262 conformance suite (optimized with harness caching and parallel execution)
test262: build test262-download
	python3 test262-runner.py \
		--engine "moon run cmd/main --" \
		--test262 ./test262 \
		--output test262-results.json

# Run a quick subset of Test262 (language/expressions and language/statements only)
test262-quick: build test262-download
	python3 test262-runner.py \
		--engine "moon run cmd/main --" \
		--test262 ./test262 \
		--filter "language/literals" \
		--timeout 10 \
		--output test262-results.json \
		--verbose

# Run Test262 for a specific category (e.g., make test262-filter FILTER=language/expressions)
test262-filter: build test262-download
	python3 test262-runner.py \
		--engine "moon run cmd/main --" \
		--test262 ./test262 \
		--filter "$(FILTER)" \
		--timeout 10 \
		--output test262-results.json \
		--verbose

# Static analysis of Test262 coverage (no engine build required)
test262-analyze: test262-download
	python3 test262-analyze.py \
		--test262 ./test262 \
		--output test262-analysis.json

# Clean build artifacts
clean:
	moon clean
	rm -f test262-results.json test262-analysis.json
