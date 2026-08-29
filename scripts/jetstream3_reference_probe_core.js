"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const { assessAdmission } = require("./jetstream3_admission.js");

const DEFAULT_TIMEOUT_MS = 180_000;

function requireObject(value, name) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${name} must be an object`);
  }
}

function requireString(value, name) {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${name} must be a non-empty string`);
  }
}

function validateCommonSpec(spec) {
  requireObject(spec, "probe specification");
  if (spec.schema_version !== 1) {
    throw new Error("schema_version must be 1");
  }
  if (!Number.isInteger(spec.generation) || spec.generation <= 0) {
    throw new Error("generation must be a positive integer");
  }
  if (spec.platform !== "linux64") {
    throw new Error("platform must be linux64");
  }
  if (!/^\d+\.\d+\.\d+$/.test(spec.jsvu_version || "")) {
    throw new Error("jsvu_version must be an exact semantic version");
  }
  if (!/^[0-9a-f]{40}$/.test(spec.jetstream_commit || "")) {
    throw new Error("jetstream_commit must be a full 40-character commit SHA");
  }
  if (spec.workload !== "navier-stokes") {
    throw new Error("workload must be navier-stokes");
  }
  requireObject(spec.engine, "engine");
  for (const field of ["id", "jsvu_engine", "version", "executable"]) {
    requireString(spec.engine[field], `engine.${field}`);
  }
  if (
    spec.engine.version === "latest" ||
    !/^[0-9]+(?:[.-][0-9A-Za-z]+)*$/.test(spec.engine.version)
  ) {
    throw new Error("engine.version must be exact");
  }
  if (
    path.isAbsolute(spec.engine.executable) ||
    spec.engine.executable.split(/[\\/]/).includes("..")
  ) {
    throw new Error("engine.executable must stay inside the payload");
  }
  if (!/^[0-9a-f]{64}$/.test(spec.engine.payload_sha256 || "")) {
    throw new Error("engine.payload_sha256 must be a SHA-256 digest");
  }
  return spec;
}

function payloadEntries(root, current = "") {
  const directory = path.join(root, current);
  const names = fs.readdirSync(directory).sort();
  const entries = [];
  for (const name of names) {
    const relative = current ? path.join(current, name) : name;
    const absolute = path.join(root, relative);
    const stat = fs.lstatSync(absolute);
    const portable = relative.split(path.sep).join("/");
    if (stat.isDirectory()) {
      entries.push(...payloadEntries(root, relative));
    } else if (stat.isFile()) {
      const digest = crypto
        .createHash("sha256")
        .update(fs.readFileSync(absolute))
        .digest("hex");
      entries.push(`file\0${portable}\0${stat.mode & 0o111}\0${digest}\n`);
    } else if (stat.isSymbolicLink()) {
      entries.push(`symlink\0${portable}\0${fs.readlinkSync(absolute)}\n`);
    } else {
      throw new Error(`unsupported payload entry: ${portable}`);
    }
  }
  return entries;
}

function payloadFingerprint(root) {
  if (!fs.statSync(root).isDirectory()) {
    throw new Error("--engine-root must name a directory");
  }
  return crypto
    .createHash("sha256")
    .update(payloadEntries(root).join(""))
    .digest("hex");
}

function parseProbeArgs(argv, defaultOutput) {
  const options = { output: defaultOutput, timeoutMs: DEFAULT_TIMEOUT_MS };
  const valueOptions = new Set([
    "--engine-root",
    "--jetstream",
    "--output",
    "--spec",
    "--timeout-ms",
  ]);
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--help") {
      options.help = true;
      continue;
    }
    if (!valueOptions.has(arg)) throw new Error(`unknown option: ${arg}`);
    if (index + 1 >= argv.length) throw new Error(`${arg} requires a value`);
    const value = argv[(index += 1)];
    if (arg === "--engine-root") options.engineRoot = value;
    if (arg === "--jetstream") options.jetstream = value;
    if (arg === "--output") options.output = value;
    if (arg === "--spec") options.spec = value;
    if (arg === "--timeout-ms") options.timeoutMs = Number(value);
  }
  if (options.help) return options;
  for (const required of ["engineRoot", "jetstream", "spec"]) {
    if (!options[required]) throw new Error(`missing required option: ${required}`);
  }
  if (!Number.isInteger(options.timeoutMs) || options.timeoutMs <= 0) {
    throw new Error("--timeout-ms must be a positive integer");
  }
  for (const field of ["engineRoot", "jetstream", "output", "spec"]) {
    options[field] = path.resolve(options[field]);
  }
  return options;
}

function runProbe(name, executable, args, options, dependencies) {
  const spawn = dependencies.spawn || spawnSync;
  const now = dependencies.now || Date.now;
  const started = now();
  const result = spawn(executable, args, {
    cwd: options.jetstream,
    encoding: "utf8",
    timeout: options.timeoutMs,
  });
  return {
    name,
    command: [executable, ...args],
    duration_ms: Math.max(0, now() - started),
    error: result.error ? result.error.message : null,
    signal: result.signal || null,
    status: result.status,
    stderr: result.stderr || "",
    stdout: result.stdout || "",
  };
}

function readRevision(root) {
  const result = spawnSync("git", ["-C", root, "rev-parse", "HEAD"], {
    encoding: "utf8",
  });
  if (result.status !== 0) throw new Error("cannot read JetStream revision");
  return result.stdout.trim();
}

function readTreeState(root) {
  const result = spawnSync(
    "git",
    ["-C", root, "status", "--porcelain", "--untracked-files=all"],
    { encoding: "utf8" },
  );
  if (result.status !== 0) throw new Error("cannot inspect JetStream checkout");
  return result.stdout.trim() === "" ? "clean" : "dirty";
}

function runReferenceProbe(argv, config, dependencies = {}) {
  const options = parseProbeArgs(argv, config.defaultOutput);
  const stdout = dependencies.stdout || process.stdout;
  if (options.help) {
    stdout.write(config.usage);
    return "help";
  }

  const spec = config.validateSpec(
    JSON.parse(fs.readFileSync(options.spec, "utf8")),
  );
  if (!fs.statSync(options.jetstream).isDirectory()) {
    throw new Error("--jetstream must name a directory");
  }
  const revision = (dependencies.readRevision || readRevision)(options.jetstream);
  if (revision !== spec.jetstream_commit) {
    throw new Error(
      `JetStream revision mismatch: expected ${spec.jetstream_commit}, got ${revision}`,
    );
  }
  if ((dependencies.readTreeState || readTreeState)(options.jetstream) !== "clean") {
    throw new Error("JetStream checkout has local modifications");
  }

  const fingerprint = payloadFingerprint(options.engineRoot);
  if (fingerprint !== spec.engine.payload_sha256) {
    throw new Error(
      `payload fingerprint mismatch: expected ${spec.engine.payload_sha256}, got ${fingerprint}`,
    );
  }
  const executable = path.join(options.engineRoot, spec.engine.executable);
  if (!fs.statSync(executable).isFile()) {
    throw new Error("specified executable is not a file in the payload");
  }
  const cli = path.join(options.jetstream, "cli.js");
  if (!fs.statSync(cli).isFile()) {
    throw new Error("JetStream checkout is missing cli.js");
  }
  const invocation = config.resolveInvocation?.({
    engineRoot: options.engineRoot,
    executable,
    spec,
  }) || { executable, prefix: [] };
  if (!fs.statSync(invocation.executable).isFile()) {
    throw new Error("resolved shell executable is not a file in the payload");
  }
  const commands = config.buildCommands({ cli, options, spec });
  const discovery = runProbe(
    "test_discovery",
    invocation.executable,
    [...invocation.prefix, ...commands.discovery],
    options,
    dependencies,
  );
  const execution = runProbe(
    "workload_execution",
    invocation.executable,
    [...invocation.prefix, ...commands.execution],
    options,
    dependencies,
  );
  const probes = [discovery, execution];
  const assessment = assessAdmission({ discovery, execution }, spec.workload);
  const probeFailed = probes.some(
    (probe) => probe.error !== null || probe.signal !== null,
  );
  const compatibility = probeFailed
    ? "probe_failed"
    : assessment.result === "admitted"
      ? "compatible"
      : "incompatible";
  const now = dependencies.now || Date.now;
  const report = {
    schema_version: 1,
    generated_at: new Date(now()).toISOString(),
    candidate: {
      generation: spec.generation,
      platform: spec.platform,
      jsvu_version: spec.jsvu_version,
      jetstream_commit: spec.jetstream_commit,
    },
    engine: {
      id: spec.engine.id,
      jsvu_engine: spec.engine.jsvu_engine,
      version: spec.engine.version,
      payload_sha256: fingerprint,
      compatibility,
    },
    environment: {
      node_version: process.version,
      platform: os.platform(),
      architecture: os.arch(),
      os_release: os.release(),
    },
    scope: {
      workload: spec.workload,
      iteration_count: 2,
      worst_case_count: 1,
      prefetch: false,
      timeout_ms: options.timeoutMs,
      timings_are_diagnostic_only: true,
    },
    assessment,
    probes,
  };
  Object.assign(report.engine, config.reportEngineFields?.(spec, options) || {});
  fs.mkdirSync(path.dirname(options.output), { recursive: true });
  fs.writeFileSync(options.output, `${JSON.stringify(report, null, 2)}\n`);
  stdout.write(`${JSON.stringify({ output: options.output, compatibility })}\n`);
  return compatibility;
}

module.exports = {
  parseProbeArgs,
  payloadFingerprint,
  requireString,
  runReferenceProbe,
  validateCommonSpec,
};
