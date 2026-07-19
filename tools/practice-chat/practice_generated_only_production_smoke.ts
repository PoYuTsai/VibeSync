// Live production smoke: writes test-account practice sessions and calls AI providers.
// Read README.md before running.
type JsonRecord = Record<string, unknown>;

const QUALITY_SCHEMA_VERSION = "semantic-quality-v2";

function parseDotEnv(text: string): Record<string, string> {
  const values: Record<string, string> = {};
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const separator = line.indexOf("=");
    if (separator <= 0) continue;
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if (
      value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'")))
    ) {
      value = value.slice(1, -1);
    }
    values[key] = value;
  }
  return values;
}

function requireString(
  value: unknown,
  label: string,
): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`missing_${label}`);
  }
  return value.trim();
}

function asRecord(value: unknown, label: string): JsonRecord {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`invalid_${label}`);
  }
  return value as JsonRecord;
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const localEnv = parseDotEnv(
  await Deno.readTextFile(new URL("../../.env.local", import.meta.url)),
);
const goldenEnv = parseDotEnv(
  await Deno.readTextFile(
    new URL("../../tools/ocr-golden/.env.golden", import.meta.url),
  ),
);
const supabaseUrl = requireString(localEnv.SUPABASE_URL, "supabase_url");
const anonKey = requireString(localEnv.SUPABASE_ANON_KEY, "anon_key");
const email = requireString(goldenEnv.TEST_EMAIL, "test_email");
const password = requireString(goldenEnv.TEST_PASSWORD, "test_password");

const authResponse = await fetch(
  `${supabaseUrl}/auth/v1/token?grant_type=password`,
  {
    method: "POST",
    headers: {
      apikey: anonKey,
      "content-type": "application/json",
    },
    body: JSON.stringify({ email, password }),
  },
);
const authJson = asRecord(await authResponse.json(), "auth_response");
assert(authResponse.ok, `auth_failed_${authResponse.status}`);
const accessToken = requireString(authJson.access_token, "access_token");

interface ApiResult {
  status: number;
  body: JsonRecord;
}

async function practiceApi(body: JsonRecord): Promise<ApiResult> {
  const response = await fetch(
    `${supabaseUrl}/functions/v1/practice-chat`,
    {
      method: "POST",
      headers: {
        apikey: anonKey,
        authorization: `Bearer ${accessToken}`,
        "content-type": "application/json; charset=utf-8",
      },
      body: JSON.stringify(body),
    },
  );
  const text = await response.text();
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error(
      `non_json_response_${response.status}_${text.slice(0, 80)}`,
    );
  }
  return { status: response.status, body: asRecord(parsed, "api_response") };
}

const srProfiles = new Set([
  "practice_girl_004",
  "practice_girl_006",
  "practice_girl_007",
  "practice_girl_008",
  "practice_girl_009",
  "practice_girl_028",
  "practice_girl_032",
  "practice_girl_033",
  "practice_girl_036",
  "practice_girl_038",
  "practice_girl_051",
  "practice_girl_052",
  "practice_girl_055",
  "practice_girl_063",
  "practice_girl_065",
  "practice_girl_079",
  "practice_girl_080",
  "practice_girl_082",
  "practice_girl_085",
  "practice_girl_087",
]);

async function unlockSrProfile(): Promise<
  { profileId: string; draws: number }
> {
  let currentProfileId: string | undefined;
  for (let draw = 1; draw <= 40; draw++) {
    const result = await practiceApi({
      mode: "draw_profile",
      requestId: `generated-smoke-draw-${crypto.randomUUID()}`,
      catalogSize: 100,
      ...(currentProfileId ? { currentProfileId } : {}),
    });
    assert(result.status === 200, `draw_failed_${result.status}`);
    const profile = asRecord(result.body.profile, "draw_profile");
    currentProfileId = requireString(profile.profileId, "draw_profile_id");
    if (srProfiles.has(currentProfileId)) {
      return { profileId: currentProfileId, draws: draw };
    }
  }
  throw new Error("no_sr_profile_after_40_draws");
}

function generatedOnly(body: JsonRecord, surface: string): void {
  assert(body.generationSource === "model", `${surface}_not_model`);
  assert(body.fallbackUsed === false, `${surface}_fallback_used`);
  assert(
    typeof body.failoverUsed === "boolean",
    `${surface}_failover_marker_missing`,
  );
  assert(
    body.qualitySchemaVersion === QUALITY_SCHEMA_VERSION,
    `${surface}_quality_schema_mismatch`,
  );
  assert(body.costDeducted === 0, `${surface}_test_account_charged`);
}

function stableSnapshot(body: JsonRecord, key: string): string {
  return JSON.stringify(body[key]);
}

function nonEmptyStringArray(value: unknown, label: string): void {
  assert(Array.isArray(value) && value.length > 0, `invalid_${label}`);
  for (const item of value) requireString(item, label);
}

async function retryGenerated(
  label: string,
  payload: JsonRecord,
  attempts = 3,
): Promise<ApiResult> {
  let last: ApiResult | undefined;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    last = await practiceApi(payload);
    if (last.status === 200) return last;
    console.log(JSON.stringify({
      step: label,
      attempt,
      status: last.status,
      error: last.body.error ?? "unknown",
      retryable: last.body.retryable ?? false,
    }));
    assert(
      last.status === 503 || last.status === 425,
      `${label}_unexpected_status_${last.status}`,
    );
    await new Promise((resolve) => setTimeout(resolve, 1200));
  }
  throw new Error(
    `${label}_exhausted_${last?.status}_${String(last?.body.error)}`,
  );
}

interface ModeSmokeResult {
  mode: "beginner" | "game";
  profileId: string;
  prefetchStatus: number;
  prefetchError: unknown;
  hintProvider: unknown;
  hintModel: unknown;
  hintFailoverUsed: unknown;
  hintUsedCount: unknown;
  hintReplayStable: boolean;
  replies: unknown;
  coaching: unknown;
  debriefProvider: unknown;
  debriefModel: unknown;
  debriefFailoverUsed: unknown;
  debriefReplayStable: boolean;
  hintContinuityGuardPassed: boolean;
  card: unknown;
}

interface StandardDebriefSmokeResult {
  mode: "standard";
  sessionId: string;
  requestId: string;
  provider: string;
  model: string;
  failoverUsed: boolean;
  replayStable: boolean;
  card: JsonRecord;
}

async function runStandardDebrief(): Promise<StandardDebriefSmokeResult> {
  const suffix = crypto.randomUUID();
  const sessionId = `generated-smoke-standard-${suffix}`;
  const requestId = `generated-smoke-debrief-${suffix}`;
  const profileId = "practice_girl_001";
  const userTurn: JsonRecord = {
    role: "user",
    text: "今天忙到剛下班，妳下班後通常怎麼放空？",
  };
  const chat = await practiceApi({
    mode: "chat",
    practiceMode: "standard",
    sessionId,
    profileId,
    roundIndex: 1,
    turns: [userTurn],
  });
  assert(
    chat.status === 200,
    `standard_chat_failed_${chat.status}_${
      String(chat.body.error ?? "unknown")
    }`,
  );
  assert(chat.body.costDeducted === 0, "standard_chat_test_account_charged");
  const aiReply = requireString(chat.body.reply, "standard_ai_reply");
  const debriefPayload: JsonRecord = {
    mode: "debrief",
    practiceMode: "standard",
    sessionId,
    profileId,
    requestId,
    acceptedQualitySchemaVersion: QUALITY_SCHEMA_VERSION,
    roundIndex: 1,
    turns: [userTurn, { role: "ai", text: aiReply }],
  };
  console.log(JSON.stringify({
    step: "standard_debrief_context",
    sessionId,
    requestId,
    aiReply,
  }));

  // This root-fix gate is intentionally single-attempt: an initial 503 must
  // stay visible instead of being hidden by a later successful retry.
  const debrief = await practiceApi(debriefPayload);
  assert(
    debrief.status === 200,
    `standard_debrief_failed_${debrief.status}_${
      String(debrief.body.error ?? "unknown")
    }`,
  );
  generatedOnly(debrief.body, "standard_debrief");
  const provider = requireString(debrief.body.provider, "standard_provider");
  const model = requireString(debrief.body.model, "standard_model");
  const generatedAt = requireString(
    debrief.body.generatedAt,
    "standard_generated_at",
  );
  assert(
    typeof debrief.body.failoverUsed === "boolean",
    "standard_failover_marker_missing",
  );
  const failoverUsed = debrief.body.failoverUsed;
  const card = asRecord(debrief.body.card, "standard_debrief_card");
  for (
    const field of [
      "summary",
      "suggestedLine",
      "vibe",
      "dateChanceReason",
      "nextInviteMove",
    ]
  ) {
    requireString(card[field], `standard_debrief_${field}`);
  }
  nonEmptyStringArray(card.strengths, "standard_debrief_strengths");
  nonEmptyStringArray(card.watchouts, "standard_debrief_watchouts");
  assert(
    card.dateChance === "low" || card.dateChance === "medium" ||
      card.dateChance === "high",
    "standard_debrief_date_chance",
  );
  assert(card.gameBreakdown === null, "standard_debrief_game_breakdown");
  assert(
    !("hintAssessment" in card),
    "standard_debrief_hint_assessment_leaked",
  );

  const replay = await practiceApi(debriefPayload);
  assert(
    replay.status === 200,
    `standard_debrief_replay_failed_${replay.status}`,
  );
  generatedOnly(replay.body, "standard_debrief_replay");
  const replayStable = stableSnapshot(debrief.body, "card") ===
      stableSnapshot(replay.body, "card") &&
    replay.body.provider === provider && replay.body.model === model &&
    replay.body.failoverUsed === failoverUsed &&
    replay.body.generatedAt === generatedAt;
  assert(replayStable, "standard_debrief_replay_changed");

  return {
    mode: "standard",
    sessionId,
    requestId,
    provider,
    model,
    failoverUsed,
    replayStable,
    card,
  };
}

async function runMode(
  mode: "beginner" | "game",
  profileId: string,
): Promise<ModeSmokeResult> {
  const suffix = crypto.randomUUID();
  const sessionId = `generated-smoke-${mode}-${suffix}`;
  const hintRequestId = `generated-smoke-hint-${suffix}`;
  const debriefRequestId = `generated-smoke-debrief-${suffix}`;
  const opening = mode === "game"
    ? "剛看到妳喜歡咖啡，我今天路過一家聞起來超香的店。"
    : "早安，我昨晚追劇追到兩點，現在腦袋還沒開機 😂";
  const firstTurns: JsonRecord[] = [{ role: "user", text: opening }];
  const chat = await practiceApi({
    mode: "chat",
    practiceMode: mode,
    sessionId,
    profileId,
    roundIndex: 1,
    turns: firstTurns,
    ...(mode === "game" ? { temperatureScore: 30, familiarityScore: 0 } : {}),
  });
  assert(
    chat.status === 200,
    `${mode}_chat_failed_${chat.status}_${
      String(chat.body.error ?? "unknown")
    }`,
  );
  assert(chat.body.costDeducted === 0, `${mode}_chat_test_account_charged`);
  const firstAiReply = requireString(chat.body.reply, `${mode}_first_ai_reply`);
  console.log(JSON.stringify({
    step: "mode_context",
    mode,
    sessionId,
    hintRequestId,
    firstAiReply,
  }));
  const hintTurns: JsonRecord[] = [
    ...firstTurns,
    { role: "ai", text: firstAiReply },
  ];
  const baseHintPayload: JsonRecord = {
    mode: "hint",
    practiceMode: mode,
    sessionId,
    profileId,
    requestId: hintRequestId,
    acceptedQualitySchemaVersion: QUALITY_SCHEMA_VERSION,
    expectedAiCount: 1,
    roundIndex: 1,
    turns: hintTurns,
  };

  const prefetch = await practiceApi({ ...baseHintPayload, prefetch: true });
  assert(
    prefetch.status === 200 || prefetch.status === 503 ||
      prefetch.status === 425,
    `${mode}_prefetch_unexpected_${prefetch.status}`,
  );
  if (prefetch.status === 200) {
    assert(prefetch.body.prefetched === true, `${mode}_prefetch_bad_ack`);
  } else {
    assert(prefetch.body.retryable === true, `${mode}_prefetch_not_retryable`);
  }

  const hint = await retryGenerated(
    `${mode}_hint`,
    { ...baseHintPayload, prefetch: false },
  );
  generatedOnly(hint.body, `${mode}_hint`);
  const replies = hint.body.replies;
  assert(Array.isArray(replies) && replies.length === 2, `${mode}_hint_shape`);
  const selected = asRecord(replies[1], `${mode}_steady_hint`);
  const selectedType = requireString(selected.type, `${mode}_hint_type`);
  const selectedText = requireString(selected.text, `${mode}_hint_text`);
  const selectedDecision = asRecord(
    selected.decision,
    `${mode}_hint_decision`,
  );

  const hintReplay = await practiceApi({ ...baseHintPayload, prefetch: false });
  assert(hintReplay.status === 200, `${mode}_hint_replay_failed`);
  generatedOnly(hintReplay.body, `${mode}_hint_replay`);
  const hintReplayStable = stableSnapshot(hint.body, "replies") ===
      stableSnapshot(hintReplay.body, "replies") &&
    hint.body.coaching === hintReplay.body.coaching &&
    hint.body.hintUsedCount === hintReplay.body.hintUsedCount;
  assert(hintReplayStable, `${mode}_hint_replay_changed`);

  const appliedTurns: JsonRecord[] = [
    ...hintTurns,
    { role: "user", text: selectedText },
  ];
  const appliedChat = await practiceApi({
    mode: "chat",
    practiceMode: mode,
    sessionId,
    profileId,
    roundIndex: 1,
    turns: appliedTurns,
    appliedHintType: selectedType,
    appliedHintText: selectedText,
  });
  assert(
    appliedChat.status === 200,
    `${mode}_applied_chat_failed_${appliedChat.status}`,
  );
  assert(
    appliedChat.body.costDeducted === 0,
    `${mode}_applied_chat_test_account_charged`,
  );
  const secondAiReply = requireString(
    appliedChat.body.reply,
    `${mode}_second_ai_reply`,
  );
  const debriefTurns: JsonRecord[] = [
    ...appliedTurns,
    { role: "ai", text: secondAiReply },
  ];
  const debriefPayload: JsonRecord = {
    mode: "debrief",
    practiceMode: mode,
    sessionId,
    profileId,
    requestId: debriefRequestId,
    acceptedQualitySchemaVersion: QUALITY_SCHEMA_VERSION,
    roundIndex: 1,
    turns: debriefTurns,
    appliedHintTurns: [{
      turnIndex: 2,
      type: selectedType,
      originalHintText: selectedText,
      sentText: selectedText,
      exact: true,
      hintRequestId,
      decision: selectedDecision,
    }],
  };
  console.log(JSON.stringify({
    step: "debrief_context",
    mode,
    selectedHint: selectedText,
    selectedDecision,
    secondAiReply,
  }));
  const debrief = await retryGenerated(
    `${mode}_debrief`,
    debriefPayload,
  );
  generatedOnly(debrief.body, `${mode}_debrief`);
  const card = asRecord(debrief.body.card, `${mode}_debrief_card`);
  requireString(card.summary, `${mode}_debrief_summary`);
  requireString(card.suggestedLine, `${mode}_debrief_suggested_line`);

  // hintAssessment is intentionally hidden after the server validates it.
  // Reaching a generated card with an applied Hint lineage proves the server
  // accepted preserved/revised plus exact post-Hint evidence semantics.
  const hintContinuityGuardPassed = true;
  if (mode === "game") {
    const breakdown = asRecord(card.gameBreakdown, "game_breakdown");
    for (
      const field of [
        "phaseReached",
        "missedVariable",
        "failureState",
        "nextFirstLine",
        "inviteDirection",
      ]
    ) {
      requireString(breakdown[field], `game_breakdown_${field}`);
    }
  }

  const debriefReplay = await practiceApi(debriefPayload);
  assert(debriefReplay.status === 200, `${mode}_debrief_replay_failed`);
  generatedOnly(debriefReplay.body, `${mode}_debrief_replay`);
  const debriefReplayStable = stableSnapshot(debrief.body, "card") ===
    stableSnapshot(debriefReplay.body, "card");
  assert(debriefReplayStable, `${mode}_debrief_replay_changed`);

  return {
    mode,
    profileId,
    prefetchStatus: prefetch.status,
    prefetchError: prefetch.body.error ?? null,
    hintProvider: hint.body.provider,
    hintModel: hint.body.model,
    hintFailoverUsed: hint.body.failoverUsed,
    hintUsedCount: hint.body.hintUsedCount,
    hintReplayStable,
    replies: hint.body.replies,
    coaching: hint.body.coaching,
    debriefProvider: debrief.body.provider,
    debriefModel: debrief.body.model,
    debriefFailoverUsed: debrief.body.failoverUsed,
    debriefReplayStable,
    hintContinuityGuardPassed,
    card,
  };
}

if (Deno.args[0] === "--standard-debrief") {
  const standard = await runStandardDebrief();
  console.log(JSON.stringify({ step: "standard_debrief_smoke", ...standard }));
  console.log(JSON.stringify({
    step: "production_smoke",
    status: "PASS",
    modes: [standard.mode],
  }));
  Deno.exit(0);
}

const existingSr = Deno.args[0];
const requestedMode = Deno.args[1] ?? "both";
assert(
  existingSr === undefined || srProfiles.has(existingSr),
  "invalid_existing_sr_argument",
);
assert(
  requestedMode === "both" || requestedMode === "beginner" ||
    requestedMode === "game",
  "invalid_mode_argument",
);
const unlocked = existingSr
  ? { profileId: existingSr, draws: 0 }
  : await unlockSrProfile();
console.log(JSON.stringify({
  step: "game_unlock",
  status: "ok",
  profileId: unlocked.profileId,
  draws: unlocked.draws,
}));
const results: ModeSmokeResult[] = [];
if (requestedMode !== "game") {
  const beginner = await runMode("beginner", "practice_girl_001");
  results.push(beginner);
  console.log(JSON.stringify({ step: "mode_smoke", ...beginner }));
}
if (requestedMode !== "beginner") {
  const game = await runMode("game", unlocked.profileId);
  results.push(game);
  console.log(JSON.stringify({ step: "mode_smoke", ...game }));
}
console.log(JSON.stringify({
  step: "production_smoke",
  status: "PASS",
  modes: results.map((result) => result.mode),
}));
