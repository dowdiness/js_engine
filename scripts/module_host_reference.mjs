// THROWAWAY independent ESM oracle for the static-link experiment.
// Invoked by module_host_prototype.cjs with --experimental-vm-modules.
// This reference process creates a Node context; the MoonBit validator does not.
import { readFileSync } from 'node:fs';
import { SourceTextModule, createContext } from 'node:vm';
const input = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const output = [];
const calls = [];
const context = createContext({ console: { log: (...args) => output.push(args.join(' ')) } });
const modules = new Map();
function load(key) {
  if (modules.has(key)) return modules.get(key);
  if (!Object.hasOwn(input.sources, key)) throw new Error(`missing source: ${key}`);
  const module = new SourceTextModule(input.sources[key], { context, identifier: key });
  modules.set(key, module);
  return module;
}
let phase = 'link';
let result;
try {
  const entry = load(input.entry);
  await entry.link(request => load(Object.hasOwn(input.aliases, request) ? input.aliases[request] : request));
  if (input.prepare_only) {
    result = { status: 'linked', output };
  } else {
    phase = 'evaluate';
    await entry.evaluate();
    phase = 'call';
    if (input.call) {
      for (let i = 0; i < input.calls; i++) calls.push(String(entry.namespace[input.call]()));
    }
    result = { status: 'ok', output, calls };
  }
} catch (error) {
  result = { status: 'error', phase, error: error.name, message: error.message, output, calls };
}
console.log(JSON.stringify({ engine: process.version, ...result }));
