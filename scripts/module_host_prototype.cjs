#!/usr/bin/env node
// THROWAWAY design experiment. No production API or conformance claim.
// Run: node scripts/module_host_prototype.cjs [--all | --scenario NAME]
// Node/npm and MoonBit required. First transformed scenario acquires pinned
// esbuild via npm exec; this is tooling acquisition, not module network loading.
const { spawnSync } = require('node:child_process');
const { mkdtempSync, writeFileSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const path = require('node:path');
const { SourceMap } = require('node:module');
const { createInterface } = require('node:readline/promises');
const root = path.resolve(__dirname, '..');
const esbuildVersion = '0.25.9';

function command(executable, args, options = {}) {
  const result = spawnSync(executable, args, {
    cwd: root, encoding: 'utf8', timeout: 180000, maxBuffer: 8 * 1024 * 1024,
    ...options,
  });
  if (result.error || result.status !== 0) {
    throw new Error(`${executable} failed: ${result.error || result.stderr || result.stdout}`);
  }
  return result.stdout;
}

function transpile(source, loader, sourcefile) {
  const code = command('npm', [
    'exec', '--yes', `--package=esbuild@${esbuildVersion}`, '--', 'esbuild',
    `--loader=${loader}`, '--format=esm', '--target=es2020',
    '--jsx=automatic', '--jsx-import-source=probe', `--sourcefile=${sourcefile}`,
    '--sourcemap=inline',
  ], { input: source });
  const match = code.match(/sourceMappingURL=data:application\/json;base64,([^\s]+)/);
  if (!match) throw new Error('esbuild did not provide the requested source map');
  return { code, map: JSON.parse(Buffer.from(match[1], 'base64').toString()) };
}

const jsxSource = `import type { Missing } from "types-not-provided";
const answer: number = 42;
const node = <answer value={answer} />;
console.log(node);
export function main(): number { return node; }
`;
const diagnosticSource = `const label: string = "mapped failure";
export function main(): never {
  throw new Error(label);
}
`;
const scenarios = {
  plain: {
    question: 'Can prepared code outlive its source host and isolate module state across sessions?',
    sources: {
      main: 'import { next } from "counter"; export function main(){ return next(); }',
      counter: 'console.log("counter evaluated"); let n=0; export function next(){ return ++n; }',
      unreachable: 'this is not valid JavaScript !!!',
    },
    output: ['counter evaluated'], calls: ['1', '2'],
  },
  'transformed-js': {
    question: 'Does switching the same JavaScript input from identity to esbuild preserve the host contract?',
    transform: ['import { next } from "counter"; export function main(){ return next(); }', 'js', 'original.js'],
    sources: {
      counter: 'console.log("counter evaluated"); let n=0; export function next(){ return ++n; }',
      unreachable: 'this is not valid JavaScript !!!',
    },
    output: ['counter evaluated'], calls: ['1', '2'],
  },
  aliases: {
    question: 'Do two host aliases resolve to one module instance and one shared live binding?',
    aliases: { alias: 'counter' },
    sources: {
      main: 'import { next } from "counter"; import { next as other } from "alias"; console.log(next === other); export function main(){ return next()+other(); }',
      counter: 'console.log("counter evaluated"); let n=0; export function next(){ return ++n; }',
    },
    output: ['counter evaluated', 'true'], calls: ['3', '7'],
  },
  cycle: {
    question: 'Can a cyclic graph be collected before instantiation, without reading TDZ bindings?',
    sources: {
      main: 'import { read } from "b"; export const value=40; export function main(){ return read(); }',
      b: 'import { value } from "main"; export function read(){ return value+2; }',
    },
    output: [], calls: ['42', '42'],
  },
  'cycle-tdz': {
    question: 'Does an actual early read across a cycle fail during evaluation?',
    sources: {
      main: 'import { b } from "b"; export const a=b;',
      b: 'import { a } from "main"; export const b=a;',
    },
    errorPhase: 'evaluate', message: /ReferenceError|initializ|TDZ/i,
  },
  'missing-source': {
    question: 'Does preparation reject an unresolved reachable source before a Session exists?',
    sources: { main: 'import "missing";' },
    preparationError: 'load',
  },
  'parse-error': {
    question: 'Does preparation retain an identity and source span for invalid generated JavaScript?',
    sources: { main: 'export const value = ;' },
    preparationError: 'parse',
    gap: 'Parser rejects the input and retains identity, but this syntax-error path returns no structured source span.',
  },
  'missing-export': {
    question: 'Is parse plus graph collection enough to promise statically valid Program construction?',
    sources: { main: 'import { missing } from "dep"; console.log(missing);', dep: 'export const present=1;' },
    errorPhase: 'instantiate', message: /missing|export/i,
    gap: 'Preparation succeeds, but missing export is rejected only during realm-dependent instantiation.',
  },
  reexports: {
    question: 'Are named and star reexports included in reachable dependency discovery?',
    aliases: { alias: 'dep' },
    sources: {
      main: 'import { value } from "barrel"; export function main(){return value;}',
      barrel: 'export { value } from "alias"; export * from "dep";',
      dep: 'export const value=42;',
    },
    output: [], calls: ['42', '42'],
  },
  transformed: {
    question: 'Can a real TSX transform erase a type-only dependency and introduce an executable helper import?',
    transform: [jsxSource, 'tsx', 'original.tsx'],
    sources: { 'probe/jsx-runtime': 'export function jsx(tag, props){ return props.value; }' },
    output: ['42'], calls: ['42', '42'],
  },
  'mapped-error': {
    question: 'Can a real source map locate a runtime failure with the current graph execution result?',
    transform: [diagnosticSource, 'ts', 'original.ts'], sources: {},
    errorPhase: 'call', message: /JsException/,
    gap: 'A real source map exists, but this direct graph/call path exposes only a raw JsException; generated-location observation and diagnostic projection are not connected.',
  },
  'live-entrypoint': {
    question: 'Does looking up an entrypoint in materialized exports observe a changed live binding?',
    sources: { main: 'export let main = function(){ main=0; return 1; };' },
    output: [], calls: ['1', '1'],
    gap: 'The materialized export snapshot keeps the old function: second call should re-read the live binding and reject 0.',
  },
};

function verify(name, scenario, report) {
  const requireFact = (condition, detail) => {
    if (!condition) throw new Error(`${name}: unexpected observation: ${detail}\n${JSON.stringify(report, null, 2)}`);
  };
  if (scenario.preparationError) {
    requireFact(report.preparation === 'error', 'expected preparation failure');
    requireFact(report.diagnostic.phase === scenario.preparationError, 'wrong preparation phase');
    if (scenario.preparationError === 'parse') requireFact(report.diagnostic.location === null, 'parse-span gap changed; reassess the finding');
    return;
  }
  requireFact(report.preparation === 'ok', 'preparation did not complete');
  requireFact(report.host_sources_after_release === 0, 'source host not released');
  requireFact(report.host_calls_during_sessions === 0, 'execution accessed host');
  requireFact(report.sessions.length === 2, 'both sessions required');
  for (const session of report.sessions) {
    if (scenario.errorPhase) {
      requireFact(session.status === 'error' && session.phase === scenario.errorPhase, 'wrong execution failure phase');
      requireFact(scenario.message.test(session.message), 'wrong error category');
    } else {
      requireFact(session.status === 'ok', 'execution failed');
      requireFact(JSON.stringify(session.calls) === JSON.stringify(scenario.calls), 'wrong call values');
      requireFact(JSON.stringify(session.output) === JSON.stringify(scenario.output), 'wrong evaluation effects');
    }
  }
  if (!scenario.errorPhase) {
    const resumed = report.resumed_first;
    const expected = name === 'plain' || name === 'transformed-js' ? '3' : name === 'aliases' ? '11' : scenario.calls[0];
    requireFact(resumed.status === 'ok' && JSON.stringify(resumed.calls) === JSON.stringify([expected]), 'first Session changed after second Session ran');
  }
  const loads = report.host_events.filter(e => e.operation === 'load').map(e => e.key);
  requireFact(new Set(loads).size === loads.length, 'duplicate source load');
  requireFact(!loads.includes('unreachable') && !loads.includes('types-not-provided'), 'unreachable/type-only input loaded');
  if (name === 'transformed') requireFact(loads.includes('probe/jsx-runtime'), 'generated helper not discovered');
}

function run(name) {
  const scenario = scenarios[name];
  if (!scenario) throw new Error(`Unknown scenario: ${name}`);
  const scratch = mkdtempSync(path.join(tmpdir(), 'module-host-prototype-'));
  try {
    const sources = { ...scenario.sources };
    let transform;
    if (scenario.transform) {
      transform = transpile(...scenario.transform);
      sources.main = transform.code;
    }
    const input = path.join(scratch, 'input.json');
    writeFileSync(input, JSON.stringify({ entry: 'main', sources, aliases: scenario.aliases || {}, call: scenario.preparationError || scenario.errorPhase === 'instantiate' || scenario.errorPhase === 'evaluate' ? '' : 'main', calls: 2 }));
    const report = JSON.parse(command('moon', ['run', '--target', 'native', 'cmd/module_host_prototype', '--', input]));
    verify(name, scenario, report);
    const result = { scenario: name, question: scenario.question, verdict: scenario.gap ? 'design-gap-observed' : 'supported-for-this-fixture', finding: scenario.gap || null, report };
    if (name === 'live-entrypoint') {
      const reference = command(process.execPath, ['--input-type=module', '-e',
        'const m=await import("data:text/javascript,"+encodeURIComponent(' + JSON.stringify(scenario.sources.main) + ')); const first=m.main(); let second; try {m.main(); second="returned";} catch(e){second=e.name;} console.log(JSON.stringify({first, second, binding:typeof m.main}));']);
      result.reference = { engine: process.version, ...JSON.parse(reference) };
      if (result.reference.first !== 1 || result.reference.second !== 'TypeError') throw new Error('live binding reference observation changed');
    }
    if (transform) {
      result.transform = { tool: `esbuild@${esbuildVersion}`, generated_code: transform.code, source_map: transform.map };
      if (name === 'mapped-error') {
        // Independent map witness, NOT an engine-reported error location.
        const lines = transform.code.split('\n');
        const line = lines.findIndex(text => text.includes('throw new Error'));
        if (line < 0) throw new Error('transformed throw statement not found');
        const column = lines[line].indexOf('throw');
        result.transform.map_witness = {
          origin: 'manually selected generated throw token, not runtime diagnostic',
          generated: { line: line + 1, column: column + 1 },
          original: new SourceMap(transform.map).findEntry(line, column),
        };
      }
    }
    return result;
  } finally { rmSync(scratch, { recursive: true, force: true }); }
}

async function main() {
  const args = process.argv.slice(2);
  if (args[0] === '--all' && args.length === 1) {
    for (const name of Object.keys(scenarios)) console.log(JSON.stringify(run(name)));
    return;
  }
  if (args[0] === '--scenario' && args.length === 2) {
    console.log(JSON.stringify(run(args[1]), null, 2));
    return;
  }
  if (args.length) throw new Error('Usage: node scripts/module_host_prototype.cjs [--all | --scenario NAME]');
  const terminal = createInterface({ input: process.stdin, output: process.stdout });
  const names = Object.keys(scenarios);
  let state = 'No scenario run. Each action prepares once, releases Host, then starts two independent Sessions.';
  try {
    while (true) {
      console.clear();
      console.log('\x1b[1mModule Host Contract — THROWAWAY\x1b[0m');
      console.log(state);
      console.log(names.map((name, index) => `[${index + 1}] ${name}`).join('  ') + '  [q] quit');
      const action = (await terminal.question('> ')).trim();
      if (action === 'q') break;
      const name = names[Number(action) - 1];
      if (!name) { state = 'Choose a listed scenario.'; continue; }
      const result = run(name);
      const report = result.report;
      state = [
        `Scenario: ${name}`, result.question,
        `Verdict: ${result.verdict}`, `Finding: ${result.finding || 'none for this fixture'}`,
        `Preparation: ${report.preparation}; parse calls: ${report.parse_calls}`,
        `Modules: ${JSON.stringify(report.modules || [])}`,
        `Host after release: ${report.host_sources_after_release ?? 'not reached'}; later calls: ${report.host_calls_during_sessions ?? 'not reached'}`,
        `Host events: ${JSON.stringify(report.host_events)}`,
        ...((report.sessions || []).map((session, index) => `Session ${index + 1}: ${JSON.stringify(session)}`)),
        `Resume first: ${JSON.stringify(report.resumed_first || null)}`,
        `Preparation diagnostic: ${JSON.stringify(report.diagnostic || null)}`,
        'Full evidence: rerun with --scenario ' + name,
      ].join('\n');
    }
  } finally { terminal.close(); }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
