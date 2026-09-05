#!/usr/bin/env node
'use strict';

// Measurement shell for the unoptimized MoonBit JS test artifact. Never patch
// production sources or the checked-in fixture; reject changed generated seams.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const sha256 = text => crypto.createHash('sha256').update(text).digest('hex');
function unwrap(result) {
  assert.equal(result?.$tag, 1, 'profiling operation did not return Ok');
  return result._0;
}

function validatePlan(plan) {
  assert.equal(plan.schema_version, 1);
  assert.equal(plan.functions.length, plan.summary.functions);
  const keys = new Set();
  const totals = { bytecode: 0, tree: 0, lowering_unsupported: 0, activation_unsupported: 0 };
  for (const row of plan.functions) {
    assert(row.path.every(index => Number.isSafeInteger(index) && index >= 0));
    const key = JSON.stringify(row.path);
    assert(!keys.has(key), 'duplicate static function path');
    keys.add(key);
    assert(['bytecode', 'tree'].includes(row.executor));
    totals[row.executor]++;
    if (row.executor === 'tree') {
      assert(['lowering', 'activation'].includes(row.reason_phase));
      assert.equal(typeof row.reason, 'string');
      totals[`${row.reason_phase}_unsupported`]++;
    } else {
      assert.equal(row.reason_phase, null);
      assert.equal(row.reason, null);
    }
  }
  for (const [key, value] of Object.entries(totals)) assert.equal(plan.summary[key], value);
  assert(keys.has('[]'), 'missing script root');
  return plan;
}

function createProbe(routePlan) {
  const sources = new Map();
  const identities = new WeakMap();
  const bodies = new WeakMap();
  const treeBodies = new Map();
  const active = new WeakMap();
  const completed = new WeakSet();
  const executions = new Map();
  const plainTree = new Map();
  const cases = [];
  let currentCase;
  let phase = 'outside';
  let evaluating;
  let activeCount = 0;
  let preparedPrograms = 0;

  function rowFor(identity, executor) {
    const metadata = identities.get(identity);
    assert(metadata, 'unmapped source identity');
    assert.equal(executor, metadata.selected_executor, 'recorded executor disagrees with static selection');
    assert(currentCase, 'route started outside a test case');
    const key = JSON.stringify([currentCase.id, phase, metadata.source, metadata.path]);
    if (!executions.has(key)) executions.set(key, {
      case: currentCase.id, phase, source: metadata.source,
      path: metadata.path, executor, starts: 0, normal: 0, abrupt: 0,
    });
    const row = executions.get(key);
    assert.equal(row.executor, executor);
    return row;
  }

  const probe = {
    wrapTest(original) {
      return function (...args) {
        assert(!currentCase, 'nested test case');
        currentCase = { id: `${args[1]}:${args[2]}`, evals: 0 };
        cases.push(currentCase);
        try { return original(...args); }
        finally {
          assert.equal(activeCount, 0, 'unfinished recorded activations');
          currentCase = undefined;
        }
      };
    },
    wrapPhase(original, nextPhase) {
      return function (...args) {
        const previous = phase;
        phase = nextPhase;
        try { return original(...args); }
        finally { phase = previous; }
      };
    },
    wrapEval(original) {
      return probe.wrapPhase(function (engine, source) {
        assert(currentCase, 'eval outside a test case');
        const digest = sha256(source);
        if (!sources.has(digest)) {
          const plan = validatePlan(JSON.parse(unwrap(routePlan(source))));
          const labels = currentCase.id.startsWith('diago_readiness_test.mbt:')
            ? ['latex_polyfills_prelude', 'latex_polyfills_source', 'latex_polyfills_epilogue', 'latex_bundle_prelude', 'latex_mathjax_source', 'latex_setup_source', 'latex_readiness_harness']
            : currentCase.id.startsWith('sketch_readiness_test.mbt:')
              ? ['sketch_runtime_source', 'sketch_setup_source', 'sketch_readiness_harness'] : [];
          sources.set(digest, { sha256: digest, label: labels[currentCase.evals] ?? digest, bytes: Buffer.byteLength(source), plan });
        }
        const previous = evaluating;
        evaluating = sources.get(digest);
        currentCase.evals++;
        const before = preparedPrograms;
        try {
          const result = original(engine, source);
          assert.equal(preparedPrograms, before + 1, 'expected one candidate preparation per Engine.eval');
          return result;
        }
        finally { evaluating = previous; }
      }, 'eval');
    },
    wrapPrepare(original) {
      return function (...args) {
        const result = original(...args);
        if (!evaluating) return result; // The separate pure static projection.
        const program = unwrap(result);
        preparedPrograms++;
        const records = new Map(evaluating.plan.functions.map(row => [JSON.stringify(row.path), row]));
        let visited = 0;
        function visit(candidate, indexes) {
          assert(Array.isArray(candidate.body) && Array.isArray(candidate.children), 'changed candidate body/children representation');
          const row = records.get(JSON.stringify(indexes));
          assert(row, 'runtime preparation has no matching static path');
          assert.equal(candidate.selection.$tag, row.executor === 'bytecode' ? 0 : 1);
          assert.equal(candidate.name ?? null, row.name);
          const metadata = { source: evaluating.sha256, path: indexes, selected_executor: row.executor };
          identities.set(candidate.source_identity, metadata);
          if (candidate.body.length > 0) {
            const first = candidate.body[0];
            const existing = bodies.get(first) ?? [];
            existing.push({ ...metadata, body: candidate.body.slice() });
            bodies.set(first, existing);
          }
          const loc = candidate.materialization_site;
          if (loc !== undefined) {
            assert(Number.isSafeInteger(loc.line) && Number.isSafeInteger(loc.col) && Number.isSafeInteger(loc.offset));
            row.materialization_site = { line: loc.line, col: loc.col, offset: loc.offset };
          }
          const loweringLoc = row.reason_phase === 'lowering' ? candidate.selection._0?._0?.loc : undefined;
          if (row.reason_phase === 'lowering') assert(loweringLoc, 'missing lowering source location');
          if (loweringLoc !== undefined) {
            assert(Number.isSafeInteger(loweringLoc.line) && Number.isSafeInteger(loweringLoc.col) && Number.isSafeInteger(loweringLoc.offset));
            row.lowering_site = { line: loweringLoc.line, col: loweringLoc.col, offset: loweringLoc.offset };
          }
          visited++;
          candidate.children.forEach((child, index) => visit(child, [...indexes, index]));
        }
        visit(program.root, []);
        assert.equal(visited, records.size);
        return result;
      };
    },
    wrapStart(original) {
      return function (activation, executor) {
        const result = original(activation, executor);
        unwrap(result);
        assert([0, 1].includes(executor), 'unknown executor encoding');
        assert(!active.has(activation) && !completed.has(activation), 'duplicate activation start');
        const row = rowFor(activation.prepared.source_identity, executor === 0 ? 'bytecode' : 'tree');
        row.starts++;
        active.set(activation, row);
        activeCount++;
        return result;
      };
    },
    wrapComplete(original) {
      return function (activation, completion) {
        const result = original(activation, completion);
        unwrap(result);
        assert([0, 1].includes(completion), 'unknown completion encoding');
        const row = active.get(activation);
        assert(row, 'completion without a recorded start');
        row[completion === 0 ? 'normal' : 'abrupt']++;
        active.delete(activation);
        completed.add(activation);
        activeCount--;
        return result;
      };
    },
    wrapPlainTree(original) {
      return function (...args) {
        const metadata = identities.get(args[2].source_identity);
        assert(metadata && currentCase, 'plain tree entry without source identity');
        const key = JSON.stringify([currentCase.id, metadata.source]);
        if (!plainTree.has(key)) plainTree.set(key, { case: currentCase.id, source: metadata.source, entries: 0 });
        plainTree.get(key).entries++;
        return original(...args);
      };
    },
    wrapTreeBody(original) {
      return function (...args) {
        const body = args[2];
        const candidates = body.length > 0 ? (bodies.get(body[0]) ?? []) : [];
        const matches = candidates.filter(candidate => candidate.body.length === body.length && candidate.body.every((stmt, index) => stmt === body[index]));
        assert(matches.length <= 1, 'ambiguous tree body identity');
        if (matches.length === 1) {
          assert(currentCase, 'tree body outside a test case');
          const metadata = matches[0];
          const key = JSON.stringify([currentCase.id, phase, metadata.source, metadata.path]);
          if (!treeBodies.has(key)) treeBodies.set(key, {
            case: currentCase.id, phase, source: metadata.source, path: metadata.path,
            selected_executor: metadata.selected_executor, entries: 0,
          });
          treeBodies.get(key).entries++;
        }
        return original(...args);
      };
    },
    finish() {
      assert.equal(activeCount, 0, 'unfinished recorded activations');
      for (const row of executions.values()) assert.equal(row.starts, row.normal + row.abrupt);
      // Only JSON measurement values leave this shell; no engine objects escape.
      return JSON.parse(JSON.stringify({ schema_version: 1, target: 'js', profile: 'debug',
        cases, sources: [...sources.values()], executions: [...executions.values()],
        plain_tree_entries: [...plainTree.values()],
        tree_body_entries: [...treeBodies.values()],
      }));
    },
  };
  return probe;
}

function instrument(source, output) {
  function symbol(suffix) {
    const matches = [...source.matchAll(/^function (\w+)\(/gm)].map(match => match[1]).filter(name => name.endsWith(suffix));
    assert.equal(matches.length, 1, `expected one generated symbol ending in ${suffix}`);
    return matches[0];
  }
  const bridge = symbol('diago__route__plan');
  const wrappers = [
    [symbol('Engine4eval'), 'wrapEval'],
    [symbol('prepare__candidate__program'), 'wrapPrepare'],
    [symbol('candidate__route__start'), 'wrapStart'],
    [symbol('candidate__route__complete'), 'wrapComplete'],
    [symbol('run__candidate__plain__tree__program'), 'wrapPlainTree'],
    [symbol('Interpreter11exec__stmts'), 'wrapTreeBody'],
    [symbol('moonbit__test__driver__internal__do__execute'), 'wrapTest'],
  ];
  const phases = [
    [symbol('Engine10call__json'), 'call_json'],
    [symbol('Engine26run__microtask__checkpoint'), 'microtask_checkpoint'],
    [symbol('Engine22run__timer__checkpoint'), 'timer_checkpoint'],
  ];
  const marker = '(() => {\n  const test_params = ';
  assert.equal(source.split(marker).length, 2, 'expected one test driver bootstrap');
  const setup = [
    `const __diagoProbe = require(${JSON.stringify(__filename)}).createProbe(${bridge});`,
    ...wrappers.map(([name, wrapper]) => `${name} = __diagoProbe.${wrapper}(${name});`),
    ...phases.map(([name, label]) => `${name} = __diagoProbe.wrapPhase(${name}, ${JSON.stringify(label)});`),
  ].join('\n');
  return source.replace(marker, `${setup}\n${marker}`) +
    `\nrequire('node:fs').writeFileSync(${JSON.stringify(output)}, JSON.stringify(__diagoProbe.finish(), null, 2) + '\\n');\n`;
}

function validateTestOutput(stdout) {
  const rows = stdout.split('\n').filter(line => line.startsWith('{')).map(line => JSON.parse(line)).filter(row => row.type === 'result');
  const expected = new Set(['diago_readiness_test.mbt:0', 'diago_readiness_test.mbt:1', 'diago_readiness_test.mbt:2', 'diago_readiness_test.mbt:3', 'diago_readiness_test.mbt:4', 'sketch_readiness_test.mbt:0']);
  assert.equal(rows.length, 6, 'expected six test results');
  for (const row of rows) {
    assert(expected.delete(`${row.file}:${row.index}`), 'expected six distinct readiness tests');
    assert.equal(row.message, '', `readiness test failed: ${row.message}`);
  }
  assert.equal(expected.size, 0, 'expected six readiness tests');
  return rows;
}

function main() {
  assert.equal(process.argv.length, 3, 'usage: node scripts/diago_route_profile.cjs OUTPUT.json');
  const root = path.resolve(__dirname, '..');
  const output = path.resolve(process.argv[2]);
  assert(!fs.existsSync(output) && !fs.existsSync(`${output}.log`), 'refusing to replace existing evidence');
  function command(executable, args, options = {}) {
    const result = spawnSync(executable, args, { cwd: root, encoding: 'utf8', timeout: 900000, maxBuffer: 16 * 1024 * 1024, ...options });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    return result.stdout;
  }
  const cwd = path.join(root, 'integration/diago_readiness');
  command('moon', ['check', '--target', 'js', '--deny-warn', 'profile'], { cwd });
  command('moon', ['test', '--target', 'js', '--build-only', 'profile'], { cwd });
  const artifact = path.join(root, 'integration/_build/js/debug/test/dowdiness/js_engine_diago_readiness/profile/profile.blackbox_test.js');
  const generated = fs.readFileSync(artifact, 'utf8');
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'diago-route-profile-'));
  try {
    const raw = path.join(temporary, 'raw.json');
    const executable = path.join(temporary, 'profile.cjs');
    fs.writeFileSync(executable, instrument(generated, raw));
    const args = { file_and_index: [['diago_readiness_test.mbt', [{ start: 0, end: 5 }]], ['sketch_readiness_test.mbt', [{ start: 0, end: 1 }]]] };
    const stdout = command(process.execPath, [executable, JSON.stringify(args)]);
    const tests = validateTestOutput(stdout);
    const report = JSON.parse(fs.readFileSync(raw, 'utf8'));
    report.tests = tests;
    assert.equal(report.cases.length, 6);
    assert.equal(report.cases.reduce((sum, entry) => sum + entry.evals, 0), 38);
    report.metadata = {
      engine_head: command('git', ['rev-parse', 'HEAD']).trim(),
      moon: command('moon', ['version']).trim(), node: process.version,
      generated_sha256: sha256(generated),
      profiler_sha256: sha256(fs.readFileSync(__filename)),
      bridge_sha256: sha256(fs.readFileSync(path.join(cwd, 'profile/route_plan_test.mbt'))),
    };
    fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
    fs.writeFileSync(`${output}.log`, stdout, { flag: 'wx' });
    process.stdout.write(`Recorded ${report.sources.length} sources and ${report.executions.length} route rows in ${output}\n`);
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}

module.exports = { createProbe, instrument, validateTestOutput };
if (require.main === module) main();
