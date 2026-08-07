#!/usr/bin/env node

import { createHash } from "node:crypto";
import { mkdirSync, realpathSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const DIAGO_COMMIT = "bd03f8a9ccb396e809c858adf874fe290e3a98e8";
const FIXTURES = {
  latex: {
    sourcePath: "latex/latex_assets.mbt",
    outputName: "latex_assets.mbt",
    bytes: 1903173,
    sha256: "d1778271a6f978e3287a1b88a2890b309100c85c5bf5212a757e028c52aea739",
    bindings: [
      "latex_polyfills_source",
      "latex_mathjax_source",
      "latex_setup_source",
    ],
  },
  sketch: {
    sourcePath: "renderer_svg/sketch_assets.mbt",
    outputName: "sketch_assets.mbt",
    bytes: 108794,
    sha256: "ab4a10fe828940c03060d3f51f6ecdcaa84e17a8f99a95bbd3f5fdcdc52c2450",
    bindings: [
      "sketch_runtime_source",
      "sketch_setup_source",
      "sketch_streaks_pattern_template",
    ],
  },
};

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = realpathSync(resolve(scriptDir, ".."));
const outputDir = join(repositoryRoot, "integration/diago_readiness");

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function exposeFixtureBindings(source, fixture) {
  let exposed = source;
  for (const binding of fixture.bindings) {
    const declaration = `\nlet ${binding}`;
    const replacement = `\npub let ${binding}`;
    if (!exposed.includes(declaration)) {
      throw new Error(`missing expected fixture binding: ${binding}`);
    }
    exposed = exposed.replace(declaration, replacement);
  }
  return exposed;
}

async function generate(name) {
  const fixture = FIXTURES[name];
  const sourceUrl =
    `https://raw.githubusercontent.com/moonbit-community/diago/${DIAGO_COMMIT}/${fixture.sourcePath}`;
  const response = await fetch(sourceUrl);
  if (!response.ok) {
    throw new Error(`failed to fetch ${sourceUrl}: HTTP ${response.status}`);
  }
  const bytes = Buffer.from(await response.arrayBuffer());
  const actualHash = sha256(bytes);
  if (bytes.length !== fixture.bytes) {
    throw new Error(
      `unexpected ${name} fixture size: ${bytes.length} (expected ${fixture.bytes})`,
    );
  }
  if (actualHash !== fixture.sha256) {
    throw new Error(
      `unexpected ${name} fixture SHA-256: ${actualHash} (expected ${fixture.sha256})`,
    );
  }
  mkdirSync(outputDir, { recursive: true });
  const outputPath = join(outputDir, fixture.outputName);
  const source = exposeFixtureBindings(bytes.toString("utf8"), fixture);
  writeFileSync(outputPath, source);
  process.stdout.write(
    `wrote ${outputPath}\nbytes=${bytes.length}\nsha256=${actualHash}\n`,
  );
}

const selection = process.argv[2] ?? "all";
if (selection !== "all" && !Object.hasOwn(FIXTURES, selection)) {
  throw new Error("usage: generate_diago_readiness_fixture.mjs [latex|sketch|all]");
}
const names = selection === "all" ? Object.keys(FIXTURES) : [selection];
for (const name of names) {
  await generate(name);
}
