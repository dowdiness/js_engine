const assert = require('node:assert/strict');
const test = require('node:test');
const { createProbe, instrument, validateTestOutput } = require('./diago_route_profile.cjs');

const ok = value => ({ $tag: 1, _0: value });
const plan = {
  schema_version: 1,
  summary: { functions: 2, bytecode: 1, tree: 1, lowering_unsupported: 0, activation_unsupported: 1 },
  functions: [
    { path: [], name: null, executor: 'tree', reason_phase: 'activation', reason: 'binary operation' },
    { path: [0], name: 'child', executor: 'bytecode', reason_phase: null, reason: null },
  ],
};

function prepared() {
  const child = { name: 'child', source_identity: {}, selection: { $tag: 0 }, body: [], children: [] };
  return { root: { name: undefined, source_identity: {}, selection: { $tag: 1 }, body: [], children: [child] } };
}

test('static functions and started activations stay separate across later calls', () => {
  const probe = createProbe(() => ok(JSON.stringify(plan)));
  const program = prepared();
  const prepare = probe.wrapPrepare(() => ok(program));
  const evaluate = probe.wrapEval(() => { prepare([]); return ok(undefined); });
  const start = probe.wrapStart(() => ok(undefined));
  const complete = probe.wrapComplete(() => ok(undefined));
  probe.wrapTest(() => {
    evaluate({}, 'function child() {}');
    probe.wrapPhase(() => {
      for (let i = 0; i < 2; i++) {
        const activation = { prepared: { source_identity: program.root.children[0].source_identity } };
        start(activation, 0);
        complete(activation, 0);
      }
    }, 'call_json')();
  })([], 'fixture.mbt', 0);
  const report = probe.finish();
  assert.equal(report.sources[0].plan.summary.functions, 2);
  assert.equal(report.executions.length, 1);
  assert.equal(report.executions[0].starts, 2);
  assert.equal(report.executions[0].normal, 2);
  assert.equal(report.executions[0].phase, 'call_json');
  assert.deepEqual(report.executions[0].path, [0]);
});

test('duplicate starts and missing source identities reject evidence', () => {
  const probe = createProbe(() => ok(JSON.stringify(plan)));
  assert.throws(() => probe.wrapStart(() => ok(undefined))({ prepared: { source_identity: {} } }, 0), /identity/);
  assert.throws(() => instrument('function unrelated() {}', '/tmp/report.json'), /symbol/);
  const program = prepared();
  const prepare = probe.wrapPrepare(() => ok(program));
  const evaluate = probe.wrapEval(() => { prepare([]); return ok(undefined); });
  probe.wrapTest(() => {
    evaluate({}, 'function child() {}');
    const activation = { prepared: { source_identity: program.root.children[0].source_identity } };
    const start = probe.wrapStart(() => ok(undefined));
    const complete = probe.wrapComplete(() => ok(undefined));
    start(activation, 0);
    assert.throws(() => start(activation, 0), /duplicate/);
    complete(activation, 1);
    assert.throws(() => complete(activation, 1), /without/);
    assert.throws(() => start(activation, 0), /duplicate/);
  })([], 'fixture.mbt', 0);
  assert.equal(probe.finish().executions[0].abrupt, 1);
});

test('same static paths in different sources never merge', () => {
  const probe = createProbe(() => ok(JSON.stringify(plan)));
  probe.wrapTest(() => {
    for (const source of ['first', 'second']) {
      const program = prepared();
      const prepare = probe.wrapPrepare(() => ok(program));
      probe.wrapEval(() => { prepare([]); return ok(undefined); })({}, source);
      const activation = { prepared: { source_identity: program.root.source_identity } };
      probe.wrapPlainTree(() => {
        probe.wrapStart(() => ok(undefined))(activation, 1);
        probe.wrapComplete(() => ok(undefined))(activation, 0);
      })({}, [], program.root);
    }
  })([], 'fixture.mbt', 0);
  const report = probe.finish();
  assert.equal(report.executions.length, 2);
  assert.equal(report.plain_tree_entries.length, 2);
  assert.notEqual(report.executions[0].source, report.executions[1].source);
  report.sources[0].plan.functions[0].name = 'mutated output';
  assert.equal(probe.finish().sources[0].plan.functions[0].name, null);
});

test('tree body entries match complete AST identity, not a shared first statement', () => {
  const probe = createProbe(() => ok(JSON.stringify(plan)));
  const program = prepared();
  const first = {};
  program.root.body = [{}];
  program.root.children[0].body = [first, {}];
  const prepare = probe.wrapPrepare(() => ok(program));
  probe.wrapTest(() => {
    probe.wrapEval(() => { prepare([]); return ok(undefined); })({}, 'body identity');
    const enter = probe.wrapTreeBody(() => ok(undefined));
    enter({}, {}, program.root.children[0].body.slice());
    enter({}, {}, [first]);
    enter({}, {}, [first, {}]);
  })([], 'fixture.mbt', 0);
  const report = probe.finish();
  assert.equal(report.tree_body_entries.length, 1);
  assert.equal(report.tree_body_entries[0].entries, 1);
  assert.equal(report.tree_body_entries[0].selected_executor, 'bytecode');
});

test('empty, duplicate, skipped and failed test outputs cannot become success', () => {
  assert.throws(() => validateTestOutput(''), /six/);
  const rows = Array.from({ length: 6 }, (_, index) => ({ type: 'result', file: index < 5 ? 'diago_readiness_test.mbt' : 'sketch_readiness_test.mbt', index: index < 5 ? index : 0, message: '' }));
  const output = rows.map(row => JSON.stringify(row)).join('\n');
  assert.equal(validateTestOutput(output).length, 6);
  assert.throws(() => validateTestOutput(output.replace('"message":""', '"message":"failure"')), /failed/);
  assert.throws(() => validateTestOutput(Array(6).fill(JSON.stringify(rows[0])).join('\n')), /six/);
});

test('an eval that bypasses candidate preparation cannot produce candidate evidence', () => {
  const probe = createProbe(() => ok(JSON.stringify(plan)));
  probe.wrapTest(() => {
    assert.throws(() => probe.wrapEval(() => ok(undefined))({}, 'bypass'), /candidate preparation/);
  })([], 'fixture.mbt', 0);
  const malformed = structuredClone(plan);
  malformed.summary.bytecode = 2;
  const invalid = createProbe(() => ok(JSON.stringify(malformed)));
  invalid.wrapTest(() => {
    assert.throws(() => invalid.wrapEval(() => ok(undefined))({}, 'bad summary'), assert.AssertionError);
  })([], 'fixture.mbt', 0);
});
