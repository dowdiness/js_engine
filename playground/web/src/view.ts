import { acceptCompletion } from "@codemirror/autocomplete";
import { indentWithTab } from "@codemirror/commands";
import {
  javascript,
  javascriptLanguage,
} from "@codemirror/lang-javascript";
import {
  HighlightStyle,
  syntaxHighlighting,
  syntaxTree,
} from "@codemirror/language";
import { EditorState } from "@codemirror/state";
import { lintGutter, setDiagnostics } from "@codemirror/lint";
import { basicSetup, EditorView } from "codemirror";
import { tags } from "@lezer/highlight";
import { hoverTooltip, keymap } from "@codemirror/view";
import {
  engineCompletionSource,
  findEngineApiEntryByLabel,
} from "./engine-api";
import type { DiagnosticSelection } from "./playground-contracts";
import {
  MAX_SOURCE_LENGTH,
  type FailedResponse,
  type TerminatedResponse,
  type WireDiagnostic,
} from "./protocol";

const editorSyntax = syntaxHighlighting(
  HighlightStyle.define([
    { tag: tags.comment, color: "var(--editor-syntax-comment)", fontStyle: "italic" },
    { tag: tags.keyword, color: "var(--editor-syntax-keyword)" },
    { tag: tags.operator, color: "var(--editor-syntax-operator)" },
    { tag: tags.string, color: "var(--editor-syntax-string)" },
    { tag: tags.number, color: "var(--editor-syntax-number)" },
    { tag: tags.bool, color: "var(--editor-syntax-boolean)" },
    { tag: tags.null, color: "var(--editor-syntax-null)" },
    { tag: tags.regexp, color: "var(--editor-syntax-regexp)" },
    { tag: tags.function(tags.variableName), color: "var(--editor-syntax-function)" },
    { tag: tags.definition(tags.variableName), color: "var(--editor-syntax-definition)" },
    { tag: tags.propertyName, color: "var(--editor-syntax-property)" },
    { tag: tags.typeName, color: "var(--editor-syntax-type)" },
    { tag: tags.punctuation, color: "var(--editor-syntax-punctuation)" },
    { tag: tags.bracket, color: "var(--editor-syntax-bracket)" },
    { tag: tags.invalid, color: "var(--editor-syntax-invalid)" },
  ]),
);

const editorCompletionTheme = EditorView.theme(
  {
    ".cm-tooltip-autocomplete": {
      maxWidth: "min(32rem, calc(100vw - 2rem))",
      border: "1px solid var(--line-strong)",
      borderRadius: "0.55rem",
      backgroundColor: "var(--panel-raised)",
      color: "var(--text)",
      fontFamily:
        '"SFMono-Regular", "Cascadia Code", "JetBrains Mono", "Roboto Mono", "Liberation Mono", monospace',
      fontSize: "0.9rem",
      overflow: "hidden",
    },
    ".cm-tooltip-autocomplete ul": {
      maxHeight: "16rem",
      padding: "0.3rem",
    },
    ".cm-tooltip-autocomplete li": {
      minHeight: "2rem",
      padding: "0.38rem 0.55rem",
      borderRadius: "0.35rem",
    },
    ".cm-tooltip-autocomplete ul li[aria-selected]": {
      backgroundColor: "var(--accent)",
      color: "var(--ink)",
    },
    ".cm-tooltip-autocomplete .cm-completionDetail": {
      color: "var(--muted)",
      fontSize: "0.78rem",
    },
    ".cm-tooltip-autocomplete ul li[aria-selected] .cm-completionDetail": {
      color: "var(--ink)",
      opacity: "0.72",
    },
    ".cm-tooltip-autocomplete .cm-completionMatchedText": {
      color: "var(--editor-syntax-number)",
      fontWeight: "700",
    },
    ".cm-tooltip-hover": {
      maxWidth: "min(32rem, calc(100vw - 2rem))",
      padding: "0.7rem 0.8rem",
      border: "1px solid var(--line-strong)",
      borderRadius: "0.55rem",
      backgroundColor: "var(--panel-raised)",
      color: "var(--text)",
      fontFamily:
        '"SFMono-Regular", "Cascadia Code", "JetBrains Mono", "Roboto Mono", "Liberation Mono", monospace',
      fontSize: "0.82rem",
    },
    ".engine-api-tooltip": {
      display: "grid",
      gap: "0.35rem",
      lineHeight: "1.45",
    },
    ".engine-api-tooltip-title": {
      color: "var(--accent)",
      fontWeight: "700",
    },
    ".engine-api-tooltip-detail": {
      color: "var(--muted)",
    },
    ".engine-api-tooltip-documentation": {
      maxWidth: "42ch",
      color: "var(--text)",
      whiteSpace: "normal",
    },
    ".cm-lintRange-error": {
      backgroundColor: "rgb(255 173 158 / 10%)",
      textDecoration: "underline wavy var(--danger) 2px",
      textUnderlineOffset: "0.18em",
    },
    ".cm-lintPoint-error": {
      borderLeft: "2px solid var(--danger)",
    },
    ".cm-lint-marker-error": {
      color: "var(--danger)",
    },
    ".cm-diagnostic-error": {
      borderInlineStart: "2px solid var(--danger)",
    },
  },
  { dark: true },
);

const editorHost = requiredElement(
  document.querySelector<HTMLDivElement>("#editor"),
  "editor",
);
const cursorPosition = requiredElement(
  document.querySelector<HTMLElement>("#cursor-position"),
  "cursor position",
);
const sourceLength = requiredElement(
  document.querySelector<HTMLElement>("#source-length"),
  "source length",
);
const engineHover = hoverTooltip((view, pos, side) => {
  const target = hoverTarget(view, pos, side);
  if (!target) return null;
  const entry = findEngineApiEntryByLabel(target.path, target.label);
  if (!entry) return null;
  return {
    pos: target.from,
    end: target.to,
    above: true,
    create() {
      const dom = document.createElement("div");
      dom.className = "engine-api-tooltip";
      const title = document.createElement("strong");
      title.className = "engine-api-tooltip-title";
      title.textContent =
        target.path.length > 0
          ? `${target.path.join(".")}.${target.label}`
          : target.label;
      const detail = document.createElement("span");
      detail.className = "engine-api-tooltip-detail";
      detail.textContent = entry.detail ?? "";
      const documentation = document.createElement("span");
      documentation.className = "engine-api-tooltip-documentation";
      documentation.textContent = entry.documentation;
      dom.append(title, detail, documentation);
      return { dom };
    },
  };
});
const editorView = new EditorView({
  parent: editorHost,
  extensions: [
    basicSetup,
    javascript(),
    javascriptLanguage.data.of({ autocomplete: engineCompletionSource }),
    lintGutter({ hoverTime: 250 }),
    engineHover,
    keymap.of([
      { key: "Tab", run: acceptCompletion },
      indentWithTab,
    ]),
    editorCompletionTheme,
    editorSyntax,
    EditorView.contentAttributes.of({
      "aria-labelledby": "editor-heading",
      spellcheck: "false",
    }),
    EditorState.transactionExtender.of(transaction =>
      transaction.docChanged ? setDiagnostics(transaction.startState, []) : null,
    ),
    EditorView.updateListener.of(update => {
      if (update.docChanged || update.selectionSet) {
        renderEditorStatus(update.view);
      }
    }),
  ],
});
renderEditorStatus(editorView);
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

function renderEditorStatus(view: EditorView): void {
  const cursor = view.state.selection.main.head;
  const line = view.state.doc.lineAt(cursor);
  cursorPosition.textContent = `Ln ${line.number}, Col ${cursor - line.from + 1}`;
  sourceLength.textContent = `${view.state.doc.length.toLocaleString("en-US")} / ${MAX_SOURCE_LENGTH.toLocaleString("en-US")} UTF-16`;
}

function clearEditorDiagnostics(): void {
  editorView.dispatch(setDiagnostics(editorView.state, []));
}

function setEditorDiagnostic(
  diagnostic: WireDiagnostic,
  selection: DiagnosticSelection,
): void {
  const documentLength = editorView.state.doc.length;
  const from = Math.min(Math.max(selection.from, 0), documentLength);
  const selectedTo = Math.min(Math.max(selection.to, from), documentLength);
  const to =
    selectedTo > from ? selectedTo : Math.min(documentLength, from + 1);
  editorView.dispatch(
    setDiagnostics(editorView.state, [
      {
        from,
        to,
        severity: "error",
        source: diagnostic.phase,
        message: formatDiagnostic(diagnostic),
      },
    ]),
  );
}

type HoverTarget = {
  from: number;
  to: number;
  path: readonly string[];
  label: string;
};

function hoverTarget(
  view: EditorView,
  pos: number,
  side: number,
): HoverTarget | null {
  if (!isCodePosition(view, pos)) return null;
  const line = view.state.doc.lineAt(pos);
  const offset = Math.min(Math.max(pos - line.from, 0), line.text.length);
  let from = offset;
  let to = offset;
  while (from > 0 && isIdentifierCharacter(line.text[from - 1])) from -= 1;
  while (to < line.text.length && isIdentifierCharacter(line.text[to])) {
    to += 1;
  }
  if (from === to) return null;
  if ((from === offset && side < 0) || (to === offset && side > 0)) {
    return null;
  }
  const label = line.text.slice(from, to);
  const prefix = line.text.slice(0, from);
  const member = /(?:^|[^A-Za-z0-9_$])([A-Za-z_$][\w$]*)\s*\.\s*$/.exec(
    prefix,
  );
  return {
    from: line.from + from,
    to: line.from + to,
    path: member ? [member[1]] : [],
    label,
  };
}

function isCodePosition(view: EditorView, pos: number): boolean {
  const syntaxNode = syntaxTree(view.state).resolveInner(pos, -1);
  let node: typeof syntaxNode | null = syntaxNode;
  while (node) {
    if (
      node.name === "LineComment" ||
      node.name === "BlockComment" ||
      node.name === "String" ||
      node.name === "TemplateString" ||
      node.name === "RegExp"
    ) {
      return false;
    }
    node = node.parent;
  }
  return true;
}

function isIdentifierCharacter(character: string | undefined): boolean {
  return character !== undefined && /[\w$]/.test(character);
}

export function readSource(): string {
  return editorView.state.doc.toString();
}

export function writeSource(source: string): void {
  if (readSource() === source) return;
  editorView.dispatch({
    changes: {
      from: 0,
      to: editorView.state.doc.length,
      insert: source,
    },
  });
}

export function focusEditor(): void {
  editorView.focus();
}

export function selectDiagnostic(selection: DiagnosticSelection): void {
  editorView.focus();
  editorView.dispatch({
    selection: {
      anchor: selection.from,
      head: selection.to,
    },
  });
}

export function renderRunning(): void {
  clearEditorDiagnostics();
  setStatus("Running", "running");
  renderText(consoleOutput, "");
  renderText(resultOutput, "");
  renderText(diagnosticsOutput, "");
}

export function renderCompleted(output: string[], result: string): void {
  clearEditorDiagnostics();
  setStatus("Complete", "complete");
  renderText(consoleOutput, output.join("\n"));
  renderText(resultOutput, result);
  renderText(diagnosticsOutput, "");
}

export function renderFailed(
  response: FailedResponse,
  selection?: DiagnosticSelection,
): void {
  setStatus("Failed", "failed");
  renderText(consoleOutput, response.output.join("\n"));
  renderText(resultOutput, "");
  renderText(diagnosticsOutput, formatDiagnostic(response.diagnostic));
  if (selection) {
    setEditorDiagnostic(response.diagnostic, selection);
    selectDiagnostic(selection);
  } else {
    clearEditorDiagnostics();
  }
}

export function renderTerminated(response: TerminatedResponse): void {
  clearEditorDiagnostics();
  setStatus(
    response.reason === "timeout" ? "Execution terminated" : "Stopped",
    "terminated",
  );
  renderText(consoleOutput, "");
  renderText(resultOutput, "");
  renderText(
    diagnosticsOutput,
    response.reason === "timeout"
      ? "The worker exceeded the 3 second wall-clock limit and was replaced."
      : "The running worker was discarded.",
  );
}

export function clearOutput(): void {
  clearEditorDiagnostics();
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
