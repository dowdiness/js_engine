export const PROTOCOL_VERSION = 1 as const;
export const MAX_SOURCE_LENGTH = 100_000;

export type WorkerRequest = {
  protocolVersion: typeof PROTOCOL_VERSION;
  requestId: string;
  operation: "run";
  source: string;
};

export type WirePosition = {
  line: number;
  column: number;
  offset: number;
};

export type WireLocation = {
  start: WirePosition;
  end: WirePosition | null;
};

export type WireDiagnostic = {
  failureKind: string;
  message: string;
  operation: string;
  phase: string;
  sourceId: string | null;
  location: WireLocation | null;
  engineIntegrity: string;
  retainedEffects: string;
  pendingJobs: string;
};

export type CompletedResponse = {
  protocolVersion: typeof PROTOCOL_VERSION;
  requestId: string;
  kind: "completed";
  output: string[];
  result: string;
};

export type FailedResponse = {
  protocolVersion: typeof PROTOCOL_VERSION;
  requestId: string;
  kind: "failed";
  output: string[];
  partialOutputAvailable: boolean;
  diagnostic: WireDiagnostic;
};

export type TerminatedResponse = {
  protocolVersion: typeof PROTOCOL_VERSION;
  requestId: string;
  kind: "terminated";
  reason: "stopped" | "timeout";
};

export type WorkerResponse =
  | CompletedResponse
  | FailedResponse
  | TerminatedResponse;

export type BridgeCompletedPayload = {
  protocolVersion: typeof PROTOCOL_VERSION;
  kind: "completed";
  output: string[];
  result: string;
};

export type BridgeFailedPayload = {
  protocolVersion: typeof PROTOCOL_VERSION;
  kind: "failed";
  output: string[];
  partialOutputAvailable: boolean;
  diagnostic: WireDiagnostic;
};

export type BridgePayload = BridgeCompletedPayload | BridgeFailedPayload;

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
export function isWorkerRequest(value: unknown): value is WorkerRequest {
  return (
    isRecord(value) &&
    value.protocolVersion === PROTOCOL_VERSION &&
    typeof value.requestId === "string" &&
    value.requestId.length > 0 &&
    value.operation === "run" &&
    typeof value.source === "string" &&
    value.source.length <= MAX_SOURCE_LENGTH
  );
}
