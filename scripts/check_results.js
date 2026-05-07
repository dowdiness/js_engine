const d = require('./test262-results.json');
const statuses = Object.create(null);
for (const r of d.results) {
  const s = r.status;
  if (statuses[s] === undefined) statuses[s] = 0;
  statuses[s]++;
}
console.log(statuses);
const relevant = d.results.filter(r => r.status === 'pass' || r.status === 'fail');
console.log('Non-skipped:', relevant.length);
console.log('Pass:', statuses.pass, '/', relevant.length, '(' + (statuses.pass/relevant.length*100).toFixed(1) + '%)');
console.log('Fail:', statuses.fail);
console.log('Improvement from 75.1%:', ((statuses.pass/relevant.length - 0.751) * 100).toFixed(1) + ' pp');
console.log('New tests passing:', statuses.pass - 20727);
