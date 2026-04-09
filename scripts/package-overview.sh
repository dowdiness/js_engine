#!/bin/bash
# Generate a compact package overview using moon ide outline
# Run by SessionStart hook automatically

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

packages=$(find . \( -name "moon.pkg.json" -o -name "moon.pkg" \) \
  -not -path "./.worktrees/*" \
  -not -path "./.mooncakes/*" \
  -printf '%h\n' | sort)

echo "=== Package Overview ==="
for pkg in $packages; do
  # Count public declarations
  outline=$(moon ide outline "$pkg" --no-check 2>/dev/null || true)
  pub_count=$(echo "$outline" | grep -c "pub" || true)
  files=$(echo "$outline" | grep -c "\.mbt:" || true)
  echo "  $pkg  ($files files, $pub_count pub decls)"
done
echo "========================"
echo "Use 'moon ide outline <path>' to explore any package's public API."
