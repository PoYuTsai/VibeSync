import {
  dirname,
  fromFileUrl,
  isAbsolute,
  join,
  resolve,
} from "https://deno.land/std@0.224.0/path/mod.ts";
import {
  aggregateBenchmark,
  type BenchmarkRun,
  validateAssistResult,
  validateReadyResult,
} from "./score.ts";

type SpeakerOverride = "none" | "left_is_me" | "right_is_me";
type Voice =
  | "steady"
  | "direct"
  | "humorous"
  | "gentle"
  | "playful"
  | null;

export type BenchmarkCase = {
  id: string;
  suite: string;
  imageFile: string;
  repetitions: number;
  speakerOverride: SpeakerOverride;
  voice: {
    primary: Voice;
    secondary: Voice;
  };
  forbiddenSubstrings?: string[];
  quoteLeakNeedles?: string[];
  quotedPreviewInstances?: number;
  expectedStatuses?: string[];
};

export type BenchmarkArgs = {
  endpoint: string;
  manifests: string[];
  outDir: string;
};

type BuildRequestInput = {
  requestId: string;
  imageBytes: Uint8Array;
  mediaType: "image/jpeg" | "image/png" | "image/webp";
  speakerOverride: SpeakerOverride;
  voice: {
    primary: Voice;
    secondary: Voice;
  };
};

const CASE_KEYS = new Set([
  "id",
  "suite",
  "imageFile",
  "repetitions",
  "speakerOverride",
  "voice",
  "forbiddenSubstrings",
  "quoteLeakNeedles",
  "quotedPreviewInstances",
  "expectedStatuses",
]);
const SPEAKER_OVERRIDES = new Set(["none", "left_is_me", "right_is_me"]);
const VOICES = new Set([
  "steady",
  "direct",
  "humorous",
  "gentle",
  "playful",
  null,
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function bytesToBase64(bytes: Uint8Array): string {
  const chunkSize = 0x8000;
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(
      ...bytes.subarray(offset, Math.min(offset + chunkSize, bytes.length)),
    );
  }
  return btoa(binary);
}

export function buildAssistRequest(input: BuildRequestInput) {
  return {
    contractVersion: "keyboard-assist-v1" as const,
    requestId: input.requestId,
    image: {
      mediaType: input.mediaType,
      data: bytesToBase64(input.imageBytes),
    },
    speakerOverride: input.speakerOverride,
    voice: {
      primary: input.voice.primary,
      secondary: input.voice.secondary,
    },
  };
}

export function mimeTypeForPath(
  path: string,
): "image/jpeg" | "image/png" | "image/webp" {
  const lower = path.toLocaleLowerCase();
  if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
  if (lower.endsWith(".png")) return "image/png";
  if (lower.endsWith(".webp")) return "image/webp";
  throw new Error(`unsupported benchmark image extension: ${path}`);
}

export function validateCaseDefinition(value: unknown): string[] {
  if (!isRecord(value)) return ["case_must_be_object"];
  const issues: string[] = [];
  for (const key of Object.keys(value)) {
    if (!CASE_KEYS.has(key)) issues.push(`additional_property:${key}`);
  }
  if (typeof value.id !== "string" || value.id.trim() === "") {
    issues.push("id_required");
  }
  if (typeof value.suite !== "string" || value.suite.trim() === "") {
    issues.push("suite_required");
  }
  if (typeof value.imageFile !== "string" || value.imageFile.trim() === "") {
    issues.push("image_file_required");
  }
  if (
    !Number.isInteger(value.repetitions) ||
    Number(value.repetitions) < 1 ||
    Number(value.repetitions) > 10
  ) {
    issues.push("invalid_repetitions");
  }
  if (!SPEAKER_OVERRIDES.has(String(value.speakerOverride))) {
    issues.push("invalid_speaker_override");
  }
  if (!isRecord(value.voice)) {
    issues.push("invalid_voice");
  } else {
    const voiceKeys = Object.keys(value.voice).toSorted();
    if (
      JSON.stringify(voiceKeys) !== JSON.stringify(["primary", "secondary"])
    ) {
      issues.push("invalid_voice_keys");
    }
    if (!VOICES.has(value.voice.primary as Voice)) {
      issues.push("invalid_primary_voice");
    }
    if (!VOICES.has(value.voice.secondary as Voice)) {
      issues.push("invalid_secondary_voice");
    }
    if (
      value.voice.primary === null && value.voice.secondary !== null
    ) {
      issues.push("secondary_requires_primary");
    }
    if (
      value.voice.primary !== null &&
      value.voice.primary === value.voice.secondary
    ) {
      issues.push("duplicate_voice");
    }
  }
  return issues.toSorted();
}

export function parseBenchmarkArgs(args: string[]): BenchmarkArgs {
  let endpoint: string | undefined;
  const manifests: string[] = [];
  let outDir = "results";

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--token") {
      throw new Error(
        "token must be supplied through KEYBOARD_ASSIST_TOKEN, never CLI history",
      );
    }
    if (arg === "--endpoint") {
      endpoint = args[++index];
    } else if (arg === "--manifest") {
      manifests.push(args[++index]);
    } else if (arg === "--out") {
      outDir = args[++index];
    } else {
      throw new Error(`unknown argument: ${arg}`);
    }
  }

  if (!endpoint) {
    throw new Error("--endpoint is required; no production default is allowed");
  }
  const parsedEndpoint = new URL(endpoint);
  if (!["http:", "https:"].includes(parsedEndpoint.protocol)) {
    throw new Error("endpoint must use http or https");
  }
  if (manifests.length === 0) {
    manifests.push("cases/synthetic.json", "cases/adversarial.json");
  }
  return { endpoint, manifests, outDir };
}

function resolveFromManifest(manifestPath: string, imageFile: string): string {
  if (isAbsolute(imageFile)) return imageFile;
  return resolve(dirname(manifestPath), imageFile);
}

async function loadCases(manifestPath: string): Promise<BenchmarkCase[]> {
  const decoded: unknown = JSON.parse(await Deno.readTextFile(manifestPath));
  if (!Array.isArray(decoded)) {
    throw new Error(`${manifestPath}: manifest root must be an array`);
  }
  const cases: BenchmarkCase[] = [];
  for (const [index, item] of decoded.entries()) {
    const issues = validateCaseDefinition(item);
    if (issues.length > 0) {
      throw new Error(
        `${manifestPath}[${index}] invalid: ${issues.join(", ")}`,
      );
    }
    cases.push(item as BenchmarkCase);
  }
  return cases;
}

function visibleResponseText(response: unknown): string {
  if (!isRecord(response)) return "";
  const values: unknown[] = [response.cue];
  if (Array.isArray(response.options)) {
    for (const option of response.options) {
      if (isRecord(option)) values.push(option.text, option.why, option.effect);
    }
  }
  return values.filter((value): value is string => typeof value === "string")
    .join("\n")
    .normalize("NFKC");
}

async function runOne(
  endpoint: string,
  token: string,
  anonKey: string | undefined,
  benchmarkCase: BenchmarkCase,
  manifestPath: string,
  repetition: number,
): Promise<BenchmarkRun & Record<string, unknown>> {
  const imagePath = resolveFromManifest(manifestPath, benchmarkCase.imageFile);
  const imageBytes = await Deno.readFile(imagePath);
  const requestId = crypto.randomUUID();
  const request = buildAssistRequest({
    requestId,
    imageBytes,
    mediaType: mimeTypeForPath(imagePath),
    speakerOverride: benchmarkCase.speakerOverride,
    voice: benchmarkCase.voice,
  });
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 45_000);
  const startedAt = performance.now();
  let httpStatus = 0;
  let response: unknown = null;
  let transportError: string | null = null;

  try {
    const headers: Record<string, string> = {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    };
    if (anonKey) headers.apikey = anonKey;
    const result = await fetch(endpoint, {
      method: "POST",
      headers,
      body: JSON.stringify(request),
      signal: controller.signal,
    });
    httpStatus = result.status;
    const text = await result.text();
    try {
      response = text === "" ? null : JSON.parse(text);
    } catch {
      response = { nonJsonBody: text.slice(0, 500) };
    }
  } catch (error) {
    transportError = error instanceof Error ? error.name : "transport_error";
  } finally {
    clearTimeout(timeout);
  }

  const durationMs = Math.round(performance.now() - startedAt);
  const status = isRecord(response) && typeof response.status === "string"
    ? response.status
    : transportError === "AbortError"
    ? "timeout"
    : "error";
  const automatedIssues = status === "ready"
    ? validateReadyResult(response, {
      forbiddenSubstrings: benchmarkCase.forbiddenSubstrings,
    })
    : status === "needs_speaker_confirmation"
    ? validateAssistResult(response)
    : [];
  if (
    benchmarkCase.expectedStatuses &&
    !benchmarkCase.expectedStatuses.includes(status)
  ) {
    automatedIssues.push("unexpected_status");
  }
  const visibleText = visibleResponseText(response);
  const quoteLeakNeedles = benchmarkCase.quoteLeakNeedles ?? [];
  const quotedPreviewLeaks =
    quoteLeakNeedles.filter((needle) =>
      needle.trim() !== "" && visibleText.includes(needle.normalize("NFKC"))
    ).length;

  return {
    caseId: benchmarkCase.id,
    runId: `${benchmarkCase.id}-${repetition + 1}`,
    durationMs,
    status,
    automatedIssues,
    quotedPreviewLeaks,
    quotedPreviewInstances: benchmarkCase.quotedPreviewInstances ?? 0,
    httpStatus,
    requestId,
    transportError,
    response,
  };
}

async function main() {
  const args = parseBenchmarkArgs(Deno.args);
  const token = Deno.env.get("KEYBOARD_ASSIST_TOKEN");
  if (!token) {
    throw new Error("KEYBOARD_ASSIST_TOKEN is required");
  }
  const anonKey = Deno.env.get("KEYBOARD_ASSIST_ANON_KEY");
  const scriptDir = dirname(fromFileUrl(import.meta.url));
  const records: Array<BenchmarkRun & Record<string, unknown>> = [];

  for (const manifestArg of args.manifests) {
    const manifestPath = isAbsolute(manifestArg)
      ? manifestArg
      : join(scriptDir, manifestArg);
    const cases = await loadCases(manifestPath);
    for (const benchmarkCase of cases) {
      for (
        let repetition = 0;
        repetition < benchmarkCase.repetitions;
        repetition += 1
      ) {
        records.push(
          await runOne(
            args.endpoint,
            token,
            anonKey,
            benchmarkCase,
            manifestPath,
            repetition,
          ),
        );
      }
    }
  }

  const artifact = {
    generatedAt: new Date().toISOString(),
    endpointOrigin: new URL(args.endpoint).origin,
    note:
      "Local benchmark artifact. It contains model replies but never image bytes or auth headers.",
    summary: aggregateBenchmark(records),
    runs: records,
  };
  const outDir = isAbsolute(args.outDir)
    ? args.outDir
    : join(scriptDir, args.outDir);
  await Deno.mkdir(outDir, { recursive: true });
  const timestamp = new Date().toISOString().replaceAll(":", "-");
  const outPath = join(outDir, `${timestamp}.json`);
  await Deno.writeTextFile(outPath, JSON.stringify(artifact, null, 2));
  console.log(JSON.stringify({ outPath, summary: artifact.summary }, null, 2));
}

if (import.meta.main) {
  await main();
}
