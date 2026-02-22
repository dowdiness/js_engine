#!/bin/bash
# Simple test262 runner for the MoonBit JS engine
# Usage: ./run_test262.sh <test_file.js>

ENGINE="/opt/node22/bin/node /home/user/js_engine/_build/js/release/build/cmd/main/main.js"
HARNESS_DIR="/home/user/js_engine/test262/harness"
TEST_FILE="$1"

if [ -z "$TEST_FILE" ]; then
    echo "Usage: $0 <test_file.js>"
    exit 1
fi

# Read test metadata
METADATA=$(sed -n '/\/\*---/,/---\*\//p' "$TEST_FILE")

# Check for flags
IS_STRICT=false
IS_NOSTRICT=false
IS_RAW=false
IS_NEGATIVE=false
NEGATIVE_TYPE=""
NEGATIVE_PHASE=""

if echo "$METADATA" | grep -q "onlyStrict"; then
    IS_STRICT=true
fi
if echo "$METADATA" | grep -q "noStrict"; then
    IS_NOSTRICT=true
fi
if echo "$METADATA" | grep -q "raw"; then
    IS_RAW=true
fi

# Check for negative test expectations
if echo "$METADATA" | grep -q "negative:"; then
    IS_NEGATIVE=true
    NEGATIVE_PHASE=$(echo "$METADATA" | grep -A2 "negative:" | grep "phase:" | sed 's/.*phase: *//')
    NEGATIVE_TYPE=$(echo "$METADATA" | grep -A3 "negative:" | grep "type:" | sed 's/.*type: *//')
fi

# Extract includes - handle both YAML list format and inline bracket format
INCLUDES_LINE=$(echo "$METADATA" | grep "^includes:")
if echo "$INCLUDES_LINE" | grep -q '\['; then
    # Inline format: includes: [foo.js, bar.js]
    INCLUDES=$(echo "$INCLUDES_LINE" | sed 's/.*\[//; s/\].*//; s/,/ /g; s/^ *//; s/ *$//')
else
    # YAML list format:
    # includes:
    #   - foo.js
    INCLUDES=$(echo "$METADATA" | grep -A100 "^includes:" | grep "^ *- " | sed 's/^ *- //')
fi

# Build combined code in a temp file
TMPFILE=$(mktemp /tmp/test262_XXXXXX.js)

# Always include sta.js and assert.js
cat "$HARNESS_DIR/sta.js" >> "$TMPFILE"
echo "" >> "$TMPFILE"
cat "$HARNESS_DIR/assert.js" >> "$TMPFILE"
echo "" >> "$TMPFILE"

# Include additional harness files
for inc in $INCLUDES; do
    if [ -f "$HARNESS_DIR/$inc" ]; then
        cat "$HARNESS_DIR/$inc" >> "$TMPFILE"
        echo "" >> "$TMPFILE"
    fi
done

# Add strict mode prefix if needed
if [ "$IS_STRICT" = true ]; then
    STRICT_TMPFILE=$(mktemp /tmp/test262_strict_XXXXXX.js)
    echo '"use strict";' > "$STRICT_TMPFILE"
    cat "$TMPFILE" >> "$STRICT_TMPFILE"
    mv "$STRICT_TMPFILE" "$TMPFILE"
fi

# Add the test code
if [ "$IS_RAW" = true ]; then
    # For raw tests, only use the test code
    cat "$TEST_FILE" > "$TMPFILE"
else
    cat "$TEST_FILE" >> "$TMPFILE"
fi

# Run the test by passing file contents as argument
OUTPUT=$($ENGINE "$(cat "$TMPFILE")" 2>&1)
EXIT_CODE=$?

rm -f "$TMPFILE"

# Evaluate result
TEST_NAME=$(basename "$TEST_FILE")

if [ "$IS_NEGATIVE" = true ]; then
    # Test expects an error
    if [ $EXIT_CODE -ne 0 ]; then
        if [ -n "$NEGATIVE_TYPE" ] && echo "$OUTPUT" | grep -q "$NEGATIVE_TYPE"; then
            echo "PASS  $TEST_NAME  (expected $NEGATIVE_TYPE, got it)"
        elif [ -n "$NEGATIVE_TYPE" ]; then
            echo "FAIL  $TEST_NAME  (expected $NEGATIVE_TYPE, got: $OUTPUT)"
        else
            echo "PASS  $TEST_NAME  (expected error, got one)"
        fi
    else
        echo "FAIL  $TEST_NAME  (expected $NEGATIVE_TYPE but no error thrown)"
    fi
else
    # Test expects success
    if [ $EXIT_CODE -eq 0 ]; then
        echo "PASS  $TEST_NAME"
    else
        echo "FAIL  $TEST_NAME  ($OUTPUT)"
    fi
fi
