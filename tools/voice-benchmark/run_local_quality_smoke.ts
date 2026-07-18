// Local-only qualitative smoke for synthetic analyze-chat cases.
// It prints model text, so it deliberately refuses non-synthetic payloads.

type Env = Record<string, string>;
type JsonRecord = Record<string, unknown>;

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

function required(env: Env, key: string): string {
  const value = env[key]?.trim();
  if (!value) throw new Error(`Missing required ${key}`);
  return value;
}

function record(value: unknown): JsonRecord | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonRecord
    : null;
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function recommendationFromStream(events: JsonRecord[]): string {
  const recommendation = events.find((event) =>
    event.type === "analysis.recommendation"
  );
  const direct = text(recommendation?.message);
  if (direct) return direct;

  const done = events.findLast((event) => event.type === "analysis.done");
  const result = record(done?.finalResult ?? done?.result);
  const finalRecommendation = record(result?.finalRecommendation);
  return text(finalRecommendation?.content ?? finalRecommendation?.message);
}

function semanticChecks(caseName: string, reply: string): JsonRecord {
  const compact = reply.replace(/\s+/g, "");
  const lineCount = reply.split(/\r?\n/).filter((line) => line.trim()).length;
  const base = {
    length: [...reply].length,
    lineCount,
    questionCount: (reply.match(/[？?]/g) ?? []).length,
    dryGeneric: /^(哈哈|嗯嗯|了解|好喔|原來如此)[～~!！。.]?$/.test(compact),
    leaksRuleLanguage: /1\.8|字數公式|投入對等|節奏護欄/.test(reply),
    corruptedText: reply.includes("�"),
    simplifiedChinese:
      /[这还个为会发听说让换开关过么吗后边]|还是|这个|那个|这样|里面|时候|发现|觉得|已经|应该|不会|没有|问题|关系|准备|担心|紧张|学习|项目|计划|顺便|听起来|说不定/
        .test(
          reply,
        ),
  };

  if (caseName.includes("whole_turn_laugh")) {
    const groups = [
      /升|談成|慶祝/,
      /專案|逃跑|工作/,
      /海|充電|放空|週末/,
    ];
    const earlierBallGroupsHit = groups.filter((pattern) => pattern.test(reply))
      .length;
    const temporalDrift =
      /升(職|官)(當天|隔天|第一天)|已經升(職|官)|今天升(職|官)|明天升(職|官)/
        .test(reply);
    return {
      ...base,
      earlierBallGroupsHit,
      temporalDrift,
      highSkillShape: earlierBallGroupsHit >= 2 && lineCount <= 3 &&
        !temporalDrift,
    };
  }
  if (caseName.includes("multiball_ack")) {
    const groups = [
      /貓|浪浪|領養|牠/,
      /沙發|眼睛|偷看|觀察/,
      /怕|擔心|照顧|認真/,
    ];
    const earlierBallGroupsHit = groups.filter((pattern) => pattern.test(reply))
      .length;
    const inventedCareContext = /第一次(養|照顧)|新手|我家(那隻|的貓)|我也養/
      .test(
        reply,
      );
    return {
      ...base,
      earlierBallGroupsHit,
      inventedCareContext,
      highSkillShape: earlierBallGroupsHit >= 2 && lineCount <= 3 &&
        !inventedCareContext,
    };
  }
  return {
    ...base,
    lowInvestmentConcise: [...reply].length <= 45,
    pressureLanguage: /為什麼|到底|一定要|快點|給我|我不夠吸引|是不是我不夠/
      .test(
        reply,
      ),
  };
}

function assertQualitativeFloor(caseName: string, reply: string): void {
  if (!reply) throw new Error("Smoke returned no recommended reply.");
  const checks = semanticChecks(caseName, reply);
  if (
    checks.dryGeneric === true || checks.leaksRuleLanguage === true ||
    checks.corruptedText === true || checks.simplifiedChinese === true
  ) {
    throw new Error("Recommended reply failed the qualitative floor.");
  }
  if (
    (caseName.includes("whole_turn_laugh") ||
      caseName.includes("multiball_ack")) &&
    checks.highSkillShape !== true
  ) {
    throw new Error(
      `Recommended reply missed meaningful balls or became line-by-line: ${
        JSON.stringify({ reply, checks })
      }`,
    );
  }
  if (
    caseName.includes("low_investment") &&
    (checks.lowInvestmentConcise !== true || checks.pressureLanguage === true)
  ) {
    throw new Error("Low-investment reply was long or pressuring.");
  }
}

function assertStreamOptionFloor(
  caseName: string,
  options: Array<{ style: unknown; message: string }>,
): void {
  const failures = options.flatMap((option) => {
    const checks = semanticChecks(caseName, option.message);
    const failed = checks.dryGeneric === true ||
      checks.leaksRuleLanguage === true || checks.corruptedText === true ||
      checks.simplifiedChinese === true ||
      (caseName.includes("low_investment") &&
        checks.pressureLanguage === true) ||
      (caseName.includes("multiball_ack") &&
        checks.inventedCareContext === true) ||
      (caseName.includes("whole_turn_laugh") &&
        checks.temporalDrift === true);
    return failed ? [{ ...option, checks }] : [];
  });
  if (failures.length > 0) {
    throw new Error(
      `One or more alternative styles failed the qualitative floor: ${
        JSON.stringify(failures)
      }`,
    );
  }
}

const caseName = Deno.args[0] ?? "smoke_1_8x_whole_turn_laugh.json";
const mode = Deno.args[1] ?? "stream";
const runLabel = Deno.args[2] ?? "run";
if (!/^smoke_1_8x_[a-z0-9_]+\.json$/.test(caseName)) {
  throw new Error(
    "This text-printing runner accepts synthetic 1.8x cases only.",
  );
}
if (mode !== "stream" && mode !== "quick") {
  throw new Error("Mode must be stream or quick.");
}

const repoRoot = new URL("../../", import.meta.url);
const env = {
  ...parseEnv(await Deno.readTextFile(new URL(".env.local", repoRoot))),
  ...parseEnv(
    await Deno.readTextFile(
      new URL("tools/ocr-golden/.env.golden", repoRoot),
    ),
  ),
};
const productionUrl = required(env, "SUPABASE_URL");
const anonKey = required(env, "SUPABASE_ANON_KEY");
const authResponse = await fetch(
  `${productionUrl}/auth/v1/token?grant_type=password`,
  {
    method: "POST",
    headers: { apikey: anonKey, "content-type": "application/json" },
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

const caseUrl = new URL(`cases/${caseName}`, import.meta.url);
const payload = JSON.parse(await Deno.readTextFile(caseUrl)) as JsonRecord;
payload.responseMode = mode;
const endpoint = Deno.env.get("ANALYZE_SMOKE_ENDPOINT") ??
  "http://127.0.0.1:8000";
if (!/https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?\//.test(`${endpoint}/`)) {
  throw new Error("Qualitative smoke endpoint must be local.");
}

const response = await fetch(endpoint, {
  method: "POST",
  headers: {
    Authorization: `Bearer ${auth.access_token}`,
    apikey: anonKey,
    "content-type": "application/json",
  },
  body: JSON.stringify(payload),
  signal: AbortSignal.timeout(180_000),
});
const body = await response.text();
if (!response.ok) {
  throw new Error(`Analyze smoke failed (${response.status}): ${body}`);
}

if (mode === "quick") {
  const parsed = JSON.parse(body) as JsonRecord;
  const quickResult = record(parsed.quickResult);
  const usage = record(parsed.usage);
  const reply = text(quickResult?.recommendedReply);
  assertQualitativeFloor(caseName, reply);
  console.log(JSON.stringify(
    {
      case: caseName,
      mode,
      run: runLabel,
      httpStatus: response.status,
      pick: quickResult?.pick ?? null,
      recommendedReply: reply,
      shortReason: quickResult?.shortReason ?? null,
      checks: semanticChecks(caseName, reply),
      model: usage?.model ?? null,
      isTestAccount: usage?.isTestAccount ?? null,
      chargedMessages: usage?.messagesUsed ?? null,
    },
    null,
    2,
  ));
  if (usage?.isTestAccount !== true || usage?.messagesUsed !== 0) {
    throw new Error("Quick smoke did not use the quota-waived test account.");
  }
  Deno.exit(0);
}

const events = body.split(/\r?\n/).filter((line) => line.trim()).map((line) =>
  JSON.parse(line) as JsonRecord
);
const errors = events.filter((event) => event.type === "analysis.error");
const recommendation = recommendationFromStream(events);
assertQualitativeFloor(caseName, recommendation);
const options = events.filter((event) => event.type === "analysis.reply_option")
  .map((event) => ({ style: event.style, message: text(event.message) }));
assertStreamOptionFloor(caseName, options);
const done = events.findLast((event) => event.type === "analysis.done");
const result = record(done?.finalResult ?? done?.result);
const usage = record(result?.usage);
console.log(JSON.stringify(
  {
    case: caseName,
    mode,
    run: runLabel,
    httpStatus: response.status,
    selectedStyle: events.find((event) => event.type === "analysis.decision")
      ?.selectedStyle ?? null,
    recommendedReply: recommendation,
    checks: semanticChecks(caseName, recommendation),
    optionCount: options.length,
    options,
    errorCount: errors.length,
    hasDone: done !== undefined,
    model: usage?.model ?? null,
    isTestAccount: usage?.isTestAccount ?? null,
    chargedMessages: usage?.messagesUsed ?? null,
  },
  null,
  2,
));
if (
  errors.length > 0 || done === undefined || options.length !== 5 ||
  usage?.isTestAccount !== true || usage?.messagesUsed !== 0
) {
  throw new Error("Stream contract or test-account assertion failed.");
}
