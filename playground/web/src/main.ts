import "./style.css";
import {
  MAX_SOURCE_LENGTH,
  PROTOCOL_VERSION,
  type WorkerRequest,
  type WorkerResponse,
} from "./protocol";
import { examples } from "./examples";
import {
  clearOutput,
  focusEditor,
  readSource,
  renderCompleted,
  renderFailed,
  renderRunning,
  renderTerminated,
  writeSource,
} from "./view";

const HARD_TIMEOUT_MS = 2_000;

const runButton = document.querySelector<HTMLButtonElement>("#run");
const stopButton = document.querySelector<HTMLButtonElement>("#stop");
const clearButton = document.querySelector<HTMLButtonElement>("#clear");
const examplePicker = document.querySelector<HTMLSelectElement>("#example");

if (!runButton || !stopButton || !clearButton || !examplePicker) {
  throw new Error("Playground controls are incomplete");
}
const exampleGroup = examplePicker.querySelector<HTMLOptGroupElement>(
  "optgroup",
);
if (!exampleGroup) {
  throw new Error("Playground example group is incomplete");
}

const exampleNames = Object.keys(examples).sort();
if (exampleNames.length === 0) {
  throw new Error("Playground examples are empty");
}
for (const name of exampleNames) {
  const option = document.createElement("option");
  option.value = name;
  option.textContent = exampleLabel(name);
  exampleGroup.append(option);
}
examplePicker.value = exampleNames[0];

function exampleLabel(name: string): string {
  return name
    .split("_")
    .map(part => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

let worker = spawnWorker();
let active:
  | { requestId: string; timerId: number; worker: Worker; source: string }
  | undefined;

runButton.addEventListener("click", () => run());
stopButton.addEventListener("click", () => stopActive("stopped"));
clearButton.addEventListener("click", () => {
  stopActive("stopped");
  clearOutput();
});
examplePicker.addEventListener("change", () => {
  const source = examples[examplePicker.value];
  if (source !== undefined) writeSource(source);
  focusEditor();
});

document.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
    event.preventDefault();
    run();
  }
});


function run(): void {
  stopActive("stopped");
  const source = readSource();
  if (source.length > MAX_SOURCE_LENGTH) {
    renderFailed({
      protocolVersion: PROTOCOL_VERSION,
      requestId: "source-too-large",
      kind: "failed",
      output: [],
      partialOutputAvailable: false,
      diagnostic: {
        failureKind: "source-too-large",
        message: `Source is limited to ${MAX_SOURCE_LENGTH} UTF-16 code units.`,
        operation: "run",
        phase: "request",
        sourceId: null,
        location: null,
        engineIntegrity: "not-applicable",
        retainedEffects: "none",
        pendingJobs: "unknown",
      },
    });
    return;
  }

  const requestId = crypto.randomUUID();
  const executingWorker = worker;
  const timerId = window.setTimeout(() => {
    if (!active || active.requestId !== requestId) return;
    executingWorker.terminate();
    active = undefined;
    worker = spawnWorker();
    renderTerminated({
      protocolVersion: PROTOCOL_VERSION,
      requestId,
      kind: "terminated",
      reason: "timeout",
    });
  }, HARD_TIMEOUT_MS);

  active = {
    requestId,
    timerId,
    worker: executingWorker,
    source,
  };
  renderRunning();
  const request: WorkerRequest = {
    protocolVersion: PROTOCOL_VERSION,
    requestId,
    operation: "run",
    source,
  };
  executingWorker.postMessage(request);
}

function stopActive(reason: "stopped"): void {
  if (!active) return;
  window.clearTimeout(active.timerId);
  active.worker.terminate();
  const requestId = active.requestId;
  active = undefined;
  worker = spawnWorker();
  renderTerminated({
    protocolVersion: PROTOCOL_VERSION,
    requestId,
    kind: "terminated",
    reason,
  });
}

function spawnWorker(): Worker {
  const createdWorker = new Worker(
    new URL("./engine-worker.ts", import.meta.url),
    { type: "module" },
  );

  createdWorker.addEventListener(
    "message",
    (event: MessageEvent<WorkerResponse>) => {
      const currentRun = active;
      const response = event.data;
      if (
        !currentRun ||
        currentRun.worker !== createdWorker ||
        response.requestId !== currentRun.requestId
      ) {
        return;
      }

      window.clearTimeout(currentRun.timerId);
      active = undefined;
      if (response.kind === "completed") {
        renderCompleted(response.output, response.result);
      } else if (response.kind === "failed") {
        renderFailed(response, readSource() === currentRun.source);
      } else {
        renderTerminated(response);
      }
    },
  );

  createdWorker.addEventListener("error", (event) => {
    if (!active || active.worker !== createdWorker) return;
    window.clearTimeout(active.timerId);
    const requestId = active.requestId;
    active = undefined;
    createdWorker.terminate();
    worker = spawnWorker();
    renderFailed({
      protocolVersion: PROTOCOL_VERSION,
      requestId,
      kind: "failed",
      output: [],
      partialOutputAvailable: false,
      diagnostic: {
        failureKind: "worker-failure",
        message: event.message || "The engine worker failed.",
        operation: "run",
        phase: "worker",
        sourceId: `playground:${requestId}`,
        location: null,
        engineIntegrity: "not-applicable",
        retainedEffects: "none",
        pendingJobs: "unknown",
      },
    });
  });

  return createdWorker;
}

writeSource(examples[examplePicker.value]);
