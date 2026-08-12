import type {
  FailedResponse,
  TerminatedResponse,
  WireDiagnostic,
} from "./protocol";

const editor = requiredElement(
  document.querySelector<HTMLTextAreaElement>("#editor"),
  "editor",
);
const consoleOutput = requiredElement(
  document.querySelector<HTMLElement>("#console"),
  "console",
);
const resultOutput = requiredElement(
  document.querySelector<HTMLElement>("#result"),
  "result",
);
const diagnosticsOutput = requiredElement(
  document.querySelector<HTMLElement>("#diagnostics"),
  "diagnostics",
);
const status = requiredElement(
  document.querySelector<HTMLElement>("#status"),
  "status",
);

function requiredElement<T extends Element>(element: T | null, name: string): T {
  if (!element) throw new Error(`Playground markup is missing ${name}`);
  return element;
}

export function readSource(): string {
  return editor.value;
}

export function writeSource(source: string): void {
  editor.value = source;
}

export function focusEditor(): void {
  editor.focus();
}

export function selectDiagnostic(location: FailedResponse["diagnostic"]["location"]): void {
  if (!location) return;
  editor.focus();
  editor.setSelectionRange(location.start.offset, location.end?.offset ?? location.start.offset);
}

export function renderRunning(): void {
  setStatus("Running", "running");
  renderText(consoleOutput, "");
  renderText(resultOutput, "");
  renderText(diagnosticsOutput, "");
}

export function renderCompleted(output: string[], result: string): void {
  setStatus("Complete", "complete");
  renderText(consoleOutput, output.join("\n"));
  renderText(resultOutput, result);
  renderText(diagnosticsOutput, "");
}

export function renderFailed(
  response: FailedResponse,
  selectLocation = true,
): void {
  setStatus("Failed", "failed");
  renderText(consoleOutput, response.output.join("\n"));
  renderText(resultOutput, "");
  renderText(diagnosticsOutput, formatDiagnostic(response.diagnostic));
  if (selectLocation) selectDiagnostic(response.diagnostic.location);
}

export function renderTerminated(response: TerminatedResponse): void {
  setStatus(
    response.reason === "timeout" ? "Execution terminated" : "Stopped",
    "terminated",
  );
  renderText(consoleOutput, "");
  renderText(resultOutput, "");
  renderText(
    diagnosticsOutput,
    response.reason === "timeout"
      ? "The worker exceeded the 2 second wall-clock limit and was replaced."
      : "The running worker was discarded.",
  );
}

export function clearOutput(): void {
  setStatus("Ready", "idle");
  renderText(consoleOutput, "");
  renderText(resultOutput, "");
  renderText(diagnosticsOutput, "");
}

function setStatus(label: string, state: string): void {
  status.textContent = label;
  status.dataset.state = state;
}

function renderText(target: HTMLElement, value: string): void {
  target.textContent = value;
}

function formatDiagnostic(diagnostic: WireDiagnostic): string {
  const location = diagnostic.location
    ? `\nline ${diagnostic.location.start.line}, column ${diagnostic.location.start.column}`
    : "";
  return `${diagnostic.failureKind}: ${diagnostic.message}${location}`;
}
