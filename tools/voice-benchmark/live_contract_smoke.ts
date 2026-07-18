// Portable production analyze-stream contract smoke.
// Uses the quota-waived test account and prints metadata only (never secrets
// or conversation/model text).

type Env = Record<string, string>;

function parseEnv(text: string): Env {
  const values: Env = {};
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim().replace(/^export\s+/, "");
    if (!line || line.startsWith("#")) continue;
    const separator = line.indexOf("=");
    if (separator <= 0) continue;
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    values[key] = value;
  }
  return values;
}

async function loadEnv(): Promise<Env> {
  const repoRoot = new URL("../../", import.meta.url);
  const local = parseEnv(
    await Deno.readTextFile(new URL(".env.local", repoRoot)),
  );
  const testAccount = parseEnv(
    await Deno.readTextFile(
      new URL("tools/ocr-golden/.env.golden", repoRoot),
    ),
  );
  return { ...local, ...testAccount };
}

function required(env: Env, key: string): string {
  const value = env[key]?.trim();
  if (!value) throw new Error(`Missing required ${key}`);
  return value;
}

const casePath = Deno.args[0] ?? "cases/case3_ashley_probe.json";
const expectedStyleCount = Number(Deno.args[1] ?? "5");
if (!Number.isInteger(expectedStyleCount) || expectedStyleCount <= 0) {
  throw new Error("Expected style count must be a positive integer.");
}

const env = await loadEnv();
const baseUrl = env.SUPABASE_URL?.trim() ||
  "https://fcmwrmwdoqiqdnbisdpg.supabase.co";
const anonKey = required(env, "SUPABASE_ANON_KEY");
const authResponse = await fetch(
  `${baseUrl}/auth/v1/token?grant_type=password`,
  {
    method: "POST",
    headers: {
      apikey: anonKey,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      email: required(env, "TEST_EMAIL"),
      password: required(env, "TEST_PASSWORD"),
    }),
  },
);
if (!authResponse.ok) {
  throw new Error(
    `Test-account authentication failed (${authResponse.status})`,
  );
}
const auth = await authResponse.json() as { access_token?: string };
if (!auth.access_token) throw new Error("Authentication returned no token.");

const scriptDirectory = new URL("./", import.meta.url);
const payload = JSON.parse(
  await Deno.readTextFile(new URL(casePath, scriptDirectory)),
) as { messages?: unknown[] };
const response = await fetch(`${baseUrl}/functions/v1/analyze-chat`, {
  method: "POST",
  headers: {
    Authorization: `Bearer ${auth.access_token}`,
    apikey: anonKey,
    "content-type": "application/json",
  },
  body: JSON.stringify(payload),
  signal: AbortSignal.timeout(180_000),
});
if (!response.ok || !response.body) {
  throw new Error(`Analyze stream request failed (${response.status})`);
}

const eventCounts: Record<string, number> = {};
const styles = new Set<string>();
const errors: Array<{ code: unknown; recoverable: unknown }> = [];
let doneEvent: Record<string, unknown> | null = null;
let buffer = "";

function acceptLine(line: string): void {
  if (!line.trim()) return;
  const event = JSON.parse(line) as Record<string, unknown>;
  const type = typeof event.type === "string" ? event.type : "unknown";
  eventCounts[type] = (eventCounts[type] ?? 0) + 1;
  if (type === "analysis.reply_option") {
    const style = event.style ?? event.replyStyle;
    if (typeof style === "string" && style) styles.add(style);
  } else if (type === "analysis.error") {
    errors.push({ code: event.code, recoverable: event.recoverable });
  } else if (type === "analysis.done") {
    doneEvent = event;
  }
}

const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
while (true) {
  const chunk = await reader.read();
  if (chunk.value) buffer += chunk.value;
  const lines = buffer.split("\n");
  buffer = lines.pop() ?? "";
  for (const line of lines) acceptLine(line);
  if (chunk.done) break;
}
acceptLine(buffer);

const done = doneEvent as Record<string, unknown> | null;
const finalResult = (done?.finalResult ?? done?.result) as
  | Record<string, unknown>
  | undefined;
const replyOptions = finalResult?.replyOptions as
  | Record<string, unknown>
  | undefined;
const usage = finalResult?.usage as Record<string, unknown> | undefined;
const telemetry = finalResult?.telemetry as Record<string, unknown> | undefined;
const summary = {
  httpStatus: response.status,
  inputMessages: payload.messages?.length ?? 0,
  eventCounts,
  styles: [...styles].sort(),
  errors,
  hasDone: done !== null,
  finalReplyOptionCount: replyOptions ? Object.keys(replyOptions).length : 0,
  model: usage?.model ?? null,
  tier: usage?.tierUsed ?? null,
  isTestAccount: usage?.isTestAccount ?? null,
  chargedMessages: usage?.messagesUsed ?? null,
  timeoutMs: telemetry?.timeoutMs ?? null,
};
console.log(JSON.stringify(summary, null, 2));

if (
  errors.length > 0 ||
  done === null ||
  styles.size !== expectedStyleCount ||
  summary.finalReplyOptionCount < expectedStyleCount ||
  usage?.isTestAccount !== true ||
  usage?.messagesUsed !== 0
) {
  throw new Error("Production analyze stream contract smoke failed.");
}
