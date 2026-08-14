import * as Sentry from "npm:@sentry/deno@10.68.0";

type EdgeHandler = (request: Request) => Response | Promise<Response>;
type MonitoredEdgeHandler = (request: Request) => Promise<Response>;

export interface SafeEdgeFailure {
  readonly functionName: string;
  readonly kind: "http_5xx" | "unhandled_exception";
  readonly status?: number;
  readonly errorType: string;
  readonly stack?: string;
}

export type EdgeFailureReporter = (failure: SafeEdgeFailure) => Promise<void>;

interface MutableSentryFrame extends Record<string, unknown> {
  filename?: string;
  function?: string;
  module?: string;
  package?: string;
  lineno?: number;
  colno?: number;
  in_app?: boolean;
  platform?: string;
  image_addr?: string;
  symbol_addr?: string;
  instruction_addr?: string;
  raw_function?: string;
  symbol?: string;
}

interface MutableSentryException extends Record<string, unknown> {
  type?: string;
  value?: string;
  mechanism?: Record<string, unknown>;
  stacktrace?: { frames?: MutableSentryFrame[] };
}

export interface MutableSentryEvent extends Record<string, unknown> {
  tags?: Record<string, string>;
  fingerprint?: string[];
  exception?: { values?: MutableSentryException[] };
}

const dsn = Deno.env.get("SENTRY_DSN")?.trim() ?? "";
const isConfigured = dsn.length > 0;
const deploymentId = sanitizeRelease(Deno.env.get("DENO_DEPLOYMENT_ID"));
const edgeEnvironment = deploymentId ? "Production" : "Development";

if (isConfigured) {
  Sentry.init({
    dsn,
    defaultIntegrations: false,
    sendDefaultPii: false,
    maxBreadcrumbs: 0,
    tracesSampleRate: 0,
    environment: edgeEnvironment,
    ...(deploymentId ? { release: deploymentId } : {}),
    beforeSend(event) {
      return sanitizeOperationalEvent(
        event as unknown as MutableSentryEvent,
      ) as unknown as typeof event;
    },
  });
}

/// Wraps an Edge handler without reading or copying its request.
///
/// Normal responses are untouched. Returned 5xx responses and thrown failures
/// emit only a fixed function name, status, error type, and sanitized frames.
export function withOperationalErrorMonitoring(
  functionName: string,
  handler: EdgeHandler,
  reporter: EdgeFailureReporter = reportToSentry,
): MonitoredEdgeHandler {
  const safeFunctionName = sanitizeFunctionName(functionName);

  return async (request: Request): Promise<Response> => {
    try {
      const response = await handler(request);
      if (response.status >= 500) {
        await reportSafely(reporter, {
          functionName: safeFunctionName,
          kind: "http_5xx",
          status: response.status,
          errorType: "EdgeHttpError",
        });
      }
      return response;
    } catch (error) {
      await reportSafely(
        reporter,
        buildSafeExceptionFailure(safeFunctionName, error),
      );
      throw error;
    }
  };
}

export function sanitizeOperationalEvent(
  event: MutableSentryEvent,
): MutableSentryEvent {
  const safe: MutableSentryEvent = {};
  for (
    const key of [
      "event_id",
      "timestamp",
      "platform",
      "release",
      "dist",
      "environment",
      "level",
      "sdk",
      "debug_meta",
      "type",
    ]
  ) {
    if (event[key] !== undefined) safe[key] = event[key];
  }

  const tags = event.tags;
  if (tags) {
    const safeTags: Record<string, string> = {};
    for (
      const key of [
        "runtime",
        "edge_function",
        "failure_kind",
        "http_status",
        "edge_region",
      ]
    ) {
      const value = tags[key];
      if (value !== undefined) safeTags[key] = sanitizeTag(value);
    }
    if (Object.keys(safeTags).length > 0) safe.tags = safeTags;
  }

  const fingerprint = event.fingerprint
    ?.map((value) => sanitizeIdentifier(value))
    .filter((value): value is string => value !== undefined)
    .slice(0, 5);
  if (fingerprint?.length) safe.fingerprint = fingerprint;

  const values = event.exception?.values;
  if (values?.length) {
    safe.exception = {
      values: values.map(sanitizeException),
    };
  }

  return safe;
}

function sanitizeException(
  exception: MutableSentryException,
): MutableSentryException {
  const type = sanitizeIdentifier(exception.type, "UnhandledError");
  const mechanism = exception.mechanism;
  const safeMechanism = mechanism
    ? {
      type: sanitizeIdentifier(mechanism.type, "generic"),
      ...(typeof mechanism.handled === "boolean"
        ? { handled: mechanism.handled }
        : {}),
      ...(typeof mechanism.synthetic === "boolean"
        ? { synthetic: mechanism.synthetic }
        : {}),
    }
    : undefined;

  const frames = exception.stacktrace?.frames;
  return {
    type,
    value: type,
    ...(safeMechanism ? { mechanism: safeMechanism } : {}),
    ...(frames?.length
      ? { stacktrace: { frames: frames.map(sanitizeFrame) } }
      : {}),
  };
}

function sanitizeFrame(frame: MutableSentryFrame): MutableSentryFrame {
  return compact({
    filename: sanitizeFileName(frame.filename),
    function: sanitizeIdentifier(frame.function),
    module: sanitizeFileName(frame.module),
    package: sanitizeFileName(frame.package),
    lineno: safeInteger(frame.lineno),
    colno: safeInteger(frame.colno),
    in_app: typeof frame.in_app === "boolean" ? frame.in_app : undefined,
    platform: sanitizeIdentifier(frame.platform),
    image_addr: sanitizeAddress(frame.image_addr),
    symbol_addr: sanitizeAddress(frame.symbol_addr),
    instruction_addr: sanitizeAddress(frame.instruction_addr),
    raw_function: sanitizeIdentifier(frame.raw_function),
    symbol: sanitizeIdentifier(frame.symbol),
  });
}

function buildSafeExceptionFailure(
  functionName: string,
  error: unknown,
): SafeEdgeFailure {
  const errorType = classifyErrorType(error);
  const stack = error instanceof Error
    ? sanitizeErrorStack(error.stack)
    : undefined;
  return {
    functionName,
    kind: "unhandled_exception",
    errorType,
    ...(stack ? { stack } : {}),
  };
}

function classifyErrorType(error: unknown): string {
  // Error.name is mutable and can contain user-supplied text. Keep this list
  // closed so the monitoring payload cannot inherit a custom name or value.
  if (error instanceof TypeError) return "TypeError";
  if (error instanceof RangeError) return "RangeError";
  if (error instanceof ReferenceError) return "ReferenceError";
  if (error instanceof SyntaxError) return "SyntaxError";
  if (error instanceof URIError) return "URIError";
  if (error instanceof EvalError) return "EvalError";
  if (error instanceof AggregateError) return "AggregateError";
  if (error instanceof Error) return "Error";

  switch (typeof error) {
    case "string":
      return "ThrownString";
    case "number":
      return "ThrownNumber";
    case "boolean":
      return "ThrownBoolean";
    case "bigint":
      return "ThrownBigInt";
    case "symbol":
      return "ThrownSymbol";
    case "function":
      return "ThrownFunction";
    case "object":
      return error === null ? "ThrownNull" : "ThrownObject";
    case "undefined":
      return "ThrownUndefined";
  }
}

function sanitizeErrorStack(stack: string | undefined): string | undefined {
  if (!stack) return undefined;
  const frames = stack
    .split("\n")
    .slice(1)
    .map(sanitizeStackLine)
    .filter((line): line is string => line !== undefined)
    .slice(0, 50);
  return frames.length > 0 ? frames.join("\n") : undefined;
}

function sanitizeStackLine(line: string): string | undefined {
  const match = line.trim().match(
    /^at\s+(?:(?<fn>[A-Za-z0-9_.$<>:+-]+)\s+\()?((?<path>(?:file|https?):\/\/\/?.+|[^()\s]+)):(?<line>\d+):(?<col>\d+)\)?$/,
  );
  if (!match?.groups) return undefined;
  const fn = sanitizeIdentifier(match.groups.fn);
  const file = sanitizeFileName(match.groups.path);
  const lineNumber = Number(match.groups.line);
  const columnNumber = Number(match.groups.col);
  if (
    !file || !Number.isSafeInteger(lineNumber) ||
    !Number.isSafeInteger(columnNumber)
  ) {
    return undefined;
  }
  return `at ${fn ? `${fn} ` : ""}(${file}:${lineNumber}:${columnNumber})`;
}

async function reportSafely(
  reporter: EdgeFailureReporter,
  failure: SafeEdgeFailure,
): Promise<void> {
  try {
    await reporter(failure);
  } catch {
    // Never leak the reporter error or alter the endpoint response contract.
    console.error("[operational-monitor] telemetry_delivery_failed");
  }
}

async function reportToSentry(failure: SafeEdgeFailure): Promise<void> {
  if (!isConfigured) return;

  const error = new Error(failure.errorType);
  error.name = failure.errorType;
  if (failure.stack) error.stack = `${failure.errorType}\n${failure.stack}`;

  Sentry.withScope((scope) => {
    scope.setTag("runtime", "supabase-edge");
    scope.setTag("edge_function", failure.functionName);
    scope.setTag("failure_kind", failure.kind);
    const region = sanitizeIdentifier(Deno.env.get("SB_REGION"));
    if (region) scope.setTag("edge_region", region);
    if (failure.status !== undefined) {
      scope.setTag("http_status", String(failure.status));
    }
    scope.setFingerprint([
      "edge",
      failure.functionName,
      failure.kind,
      String(failure.status ?? "thrown"),
      failure.errorType,
    ]);
    Sentry.captureException(error);
  });
  await Sentry.flush(1500);
}

function sanitizeFunctionName(value: string): string {
  const trimmed = value.trim();
  return /^[a-z0-9-]{1,64}$/.test(trimmed) ? trimmed : "unknown";
}

function sanitizeTag(value: string): string {
  return value.replace(/[^A-Za-z0-9_.:+-]/g, "_").slice(0, 120);
}

function sanitizeRelease(value: string | undefined): string | undefined {
  if (!value) return undefined;
  const safe = value.trim().replace(/[^A-Za-z0-9_.+-]/g, "_");
  return safe.length > 0 ? safe.slice(0, 200) : undefined;
}

function sanitizeIdentifier(
  value: unknown,
  fallback?: string,
): string | undefined {
  if (typeof value !== "string" || value.trim().length === 0) return fallback;
  const safe = value.trim().replace(/[^A-Za-z0-9_.$<>:+-]/g, "_");
  return safe.length > 0 ? safe.slice(0, 120) : fallback;
}

function sanitizeAddress(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return /^(0x)?[0-9a-fA-F]+$/.test(trimmed) ? trimmed : undefined;
}

function sanitizeFileName(value: unknown): string | undefined {
  if (typeof value !== "string" || value.trim().length === 0) return undefined;
  const normalized = value.trim().replaceAll("\\", "/").split(/[?#]/)[0];
  const functionsIndex = normalized.lastIndexOf("/supabase/functions/");
  const libIndex = normalized.lastIndexOf("/lib/");
  const candidate = functionsIndex >= 0
    ? normalized.slice(functionsIndex + 1)
    : libIndex >= 0
    ? normalized.slice(libIndex + 1)
    : normalized.split("/").at(-1);
  return sanitizeIdentifier(candidate);
}

function safeInteger(value: unknown): number | undefined {
  return typeof value === "number" && Number.isSafeInteger(value)
    ? value
    : undefined;
}

function compact<T extends Record<string, unknown>>(value: T): T {
  return Object.fromEntries(
    Object.entries(value).filter(([, entry]) => entry !== undefined),
  ) as T;
}
