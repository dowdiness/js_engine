export type RunIdentity = {
  requestId: string;
  workerId: number;
};

export function isCurrentResponse(
  activeRun: RunIdentity | undefined,
  response: Pick<RunIdentity, "requestId">,
  responseWorkerId: number,
): boolean {
  return (
    activeRun !== undefined &&
    activeRun.requestId === response.requestId &&
    activeRun.workerId === responseWorkerId
  );
}

export function isCurrentWorker(
  activeRun: RunIdentity | undefined,
  workerId: number,
): boolean {
  return activeRun !== undefined && activeRun.workerId === workerId;
}

export function isSourceWithinLimit(
  source: string,
  maxLength: number,
): boolean {
  return source.length <= maxLength;
}

export type DiagnosticSelection = {
  from: number;
  to: number;
};

type DiagnosticLocation = {
  start: { offset: number };
  end: { offset: number } | null;
};

export function diagnosticSelection(
  sourceAtRequest: string,
  currentSource: string,
  location: DiagnosticLocation | null,
): DiagnosticSelection | undefined {
  if (sourceAtRequest !== currentSource || location === null) return undefined;
  const from = Math.min(
    Math.max(location.start.offset, 0),
    currentSource.length,
  );
  const endOffset = location.end?.offset ?? location.start.offset;
  const to = Math.max(
    from,
    Math.min(Math.max(endOffset, 0), currentSource.length),
  );
  return { from, to };
}

export type ExampleSources = Readonly<Record<string, string>>;

export type ExampleComparison = {
  missing: string[];
  unexpected: string[];
  changed: string[];
};

export function compareExampleSources(
  expected: ExampleSources,
  actual: ExampleSources,
): ExampleComparison {
  const expectedNames = Object.keys(expected).sort();
  const actualNames = Object.keys(actual).sort();
  const missing = expectedNames.filter(name => !Object.hasOwn(actual, name));
  const unexpected = actualNames.filter(name => !Object.hasOwn(expected, name));
  const changed = expectedNames.filter(
    name =>
      Object.hasOwn(actual, name) &&
      expected[name] !== actual[name],
  );
  return { missing, unexpected, changed };
}
