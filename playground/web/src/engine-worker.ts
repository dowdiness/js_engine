import { playground_run } from "../generated/playground_bridge.js";
import {
  MAX_SOURCE_LENGTH,
  PROTOCOL_VERSION,
  isRecord,
  isWorkerRequest,
  type BridgePayload,
  type WireDiagnostic,
  type WireLocation,
  type WirePosition,
} from "./protocol";
const workerScope = self as DedicatedWorkerGlobalScope;
const INVALID_REQUEST_ID = "invalid-request";

workerScope.onmessage = (event: MessageEvent<unknown>) => {
  const request = event.data;
  if (!isWorkerRequest(request)) {
    const sourceTooLarge =
      isRecord(request) &&
      typeof request.source === "string" &&
      request.source.length > MAX_SOURCE_LENGTH;
    const requestId =
      isRecord(request) &&
      typeof request.requestId === "string" &&
      request.requestId.length > 0
        ? request.requestId
        : INVALID_REQUEST_ID;
    workerScope.postMessage({
      protocolVersion: PROTOCOL_VERSION,
      requestId,
      kind: "failed",
      output: [],
      partialOutputAvailable: false,
      diagnostic: {
        failureKind: sourceTooLarge ? "source-too-large" : "invalid-request",
        message: sourceTooLarge
          ? `Source is limited to ${MAX_SOURCE_LENGTH} UTF-16 code units.`
          : "Worker received an invalid request.",
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

  try {
    if (
      request.protocolVersion !== PROTOCOL_VERSION ||
      request.operation !== "run"
    ) {
      throw new Error("Unsupported worker request");
    }

    const payload = parseBridgePayload(
      playground_run(request.source, `playground:${request.requestId}`),
    );
    workerScope.postMessage({
      requestId: request.requestId,
      ...payload,
    });
  } catch (error) {
    workerScope.postMessage({
      protocolVersion: PROTOCOL_VERSION,
      requestId: request.requestId,
      kind: "failed",
      output: [],
      partialOutputAvailable: false,
      diagnostic: {
        failureKind: "bridge-failure",
        message: error instanceof Error ? error.message : String(error),
        operation: "run",
        phase: "bridge",
        sourceId: `playground:${request.requestId}`,
        location: null,
        engineIntegrity: "not-applicable",
        retainedEffects: "none",
        pendingJobs: "unknown",
      },
    });
  }
};

function parseBridgePayload(raw: string): BridgePayload {
  const value: unknown = JSON.parse(raw);
  if (!isRecord(value) || value.protocolVersion !== PROTOCOL_VERSION) {
    throw new Error("Bridge returned an unsupported protocol version");
  }

  if (value.kind === "completed") {
    if (!isStringArray(value.output) || typeof value.result !== "string") {
      throw new Error("Bridge returned an invalid completed response");
    }
    return {
      protocolVersion: PROTOCOL_VERSION,
      kind: "completed",
      output: value.output,
      result: value.result,
    };
  }

  if (value.kind === "failed") {
    if (
      !isStringArray(value.output) ||
      typeof value.partialOutputAvailable !== "boolean" ||
      !isDiagnostic(value.diagnostic)
    ) {
      throw new Error("Bridge returned an invalid failed response");
    }
    return {
      protocolVersion: PROTOCOL_VERSION,
      kind: "failed",
      output: value.output,
      partialOutputAvailable: value.partialOutputAvailable,
      diagnostic: value.diagnostic,
    };
  }

  throw new Error("Bridge returned an unsupported response kind");
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string");
}

function isDiagnostic(value: unknown): value is WireDiagnostic {
  if (!isRecord(value)) return false;
  return (
    typeof value.failureKind === "string" &&
    typeof value.message === "string" &&
    typeof value.operation === "string" &&
    typeof value.phase === "string" &&
    (value.sourceId === null || typeof value.sourceId === "string") &&
    (value.location === null || isLocation(value.location)) &&
    typeof value.engineIntegrity === "string" &&
    typeof value.retainedEffects === "string" &&
    typeof value.pendingJobs === "string"
  );
}

function isLocation(value: unknown): value is WireLocation {
  if (!isRecord(value)) return false;
  return (
    isPosition(value.start) &&
    (value.end === null || isPosition(value.end))
  );
}

function isPosition(value: unknown): value is WirePosition {
  if (!isRecord(value)) return false;
  return (
    typeof value.line === "number" &&
    Number.isSafeInteger(value.line) &&
    value.line >= 0 &&
    typeof value.column === "number" &&
    Number.isSafeInteger(value.column) &&
    value.column >= 0 &&
    typeof value.offset === "number" &&
    Number.isSafeInteger(value.offset) &&
    value.offset >= 0
  );
}
