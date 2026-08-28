"use strict";

(() => {
  const separator = execArgv.indexOf("--");

  globalThis.arguments = separator === -1 ? [] : execArgv.slice(separator + 1);
  globalThis.load = (file) => std.loadScript(file);
  globalThis.readFile = (file) => std.loadFile(file);
  globalThis.runString = () => {
    throw new Error(
      "QuickJS-ng qjs does not expose isolated globals required by JetStream",
    );
  };
  globalThis.printErr ??= (...values) => {
    std.err.puts(`${values.join(" ")}\n`);
  };
  globalThis.performance ??= {};
  globalThis.performance.now ??= () => os.now();
})();
