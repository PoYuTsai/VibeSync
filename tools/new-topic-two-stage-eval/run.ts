// 新話題兩段式成對評測：舊版（只送狀況）vs 兩段式（局面＋素材）。local-only、付費。
//
// 直接 import production 的 prompt 與純函式，不經 Edge／DB／串流／修格式；只有模型呼叫是真的。
// 預設 dry-run：印出每次呼叫的完整 prompt 與保守費用估算；不讀金鑰、不連網、不跑 git。
// 真跑必須同時帶 --run --confirm-paid --max-calls=<上限> --budget-usd=<上限>，且 Eric 說「跑」之後才能下。
// --arms=two_stage|legacy|both（預設 both）可以只跑一臂；兩段式臂套用 production 的紅燈收尾保證。
// 指令與輸出說明見 README.md。

import catalog from "./cases.json" with { type: "json" };
import { parseJsonObjectFromText } from "../../supabase/functions/analyze-chat/json_text.ts";
import {
  hasAnalyzeChatPromptLeak,
  hasNewTopicTwoStagePromptLeak,
} from "../../supabase/functions/analyze-chat/prompt_leak.ts";
import {
  allowsNewTopicSharedFrame,
  type NewTopicGroundingPolicy,
  type NewTopicModelTopic,
  type NewTopicSituation,
  normalizeNewTopicModelPayload,
  sanitizeNewTopicRequest,
} from "../../supabase/functions/analyze-chat/new_topic_payload.ts";
import {
  buildNewTopicUserPrompt,
  NEW_TOPIC_GENERATION_DEADLINE_MS,
  NEW_TOPIC_MAX_TOKENS,
  NEW_TOPIC_PROMPT,
} from "../../supabase/functions/analyze-chat/new_topic_prompt.ts";
import {
  auditNewTopicTwoStageTopics,
  buildNewTopicTwoStageUserPrompt,
  enforceNewTopicRedClose,
  isNewTopicRedClose,
  NEW_TOPIC_TWO_STAGE_PROMPT,
  NEW_TOPIC_TWO_STAGE_PROMPT_VERSION,
  type NewTopicTopicContext,
  type NewTopicTwoStageAudit,
} from "../../supabase/functions/analyze-chat/new_topic_two_stage.ts";
import {
  estimateCostUsd,
  SONNET_5_PRICING,
} from "../../supabase/functions/_shared/model_pricing.ts";

export type Arm = "legacy" | "two_stage";
export const ARMS: readonly Arm[] = ["legacy", "two_stage"];
export const MODEL = "claude-sonnet-5"; // 同 new_topic_handler.ts 的 newTopicModel
// 本機字數估算對中文會少算 10–20%，所以 input 一律用「字數 × 1.5」保守估。
export const CJK_TOKENS_PER_CHAR = 1.5;
export const TYPICAL_OUTPUT_TOKENS = 1200;
const API_TIMEOUT_MS = 60_000; // 同 handler 非串流路徑；超過 production 45 秒期限的另計

export type EvalCase = {
  id: string;
  source: string;
  label: string;
  partner: string | null;
  situation: NewTopicSituation;
  topicContext: Partial<Record<string, string>>;
};
export const CASES = catalog.cases as EvalCase[];
export const PARTNERS = catalog.partners as Record<string, string>;

// ---------------------------------------------------------------------------
// 參數
// ---------------------------------------------------------------------------

export type Options = {
  tag: string;
  repeat: number;
  seed: number;
  only: string[] | null;
  arms: readonly Arm[];
  run: boolean;
  maxCalls: number | null;
  budgetUsd: number | null;
};

const VALUE_FLAGS = [
  "tag",
  "repeat",
  "seed",
  "only",
  "arms",
  "max-calls",
  "budget-usd",
];
const BOOL_FLAGS = ["run", "confirm-paid"];

export function parseOptions(args: string[]): Options {
  const values = new Map<string, string | true>();
  for (const arg of args) {
    const m = /^--([a-z-]+)(?:=(.+))?$/.exec(arg);
    const key = m?.[1] ?? "";
    const known = m !== null &&
      (m[2] === undefined
        ? BOOL_FLAGS.includes(key)
        : VALUE_FLAGS.includes(key));
    if (!known || values.has(key)) {
      throw new Error(`未知、重複或格式錯誤的參數：${arg}`);
    }
    values.set(key, m[2] ?? true);
  }
  const str = (key: string) => {
    const value = values.get(key);
    return typeof value === "string" ? value : null;
  };
  const int = (key: string, fallback: number, max: number) => {
    const raw = str(key);
    if (raw === null) return fallback;
    const value = Number(raw);
    if (!/^\d+$/.test(raw) || value < 1 || value > max) {
      throw new Error(`--${key} 要是 1–${max} 的整數`);
    }
    return value;
  };

  const tag = str("tag") ?? "dry-run";
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/.test(tag)) {
    throw new Error("--tag 只能用英數、-、_");
  }
  const only = str("only")?.split(",") ?? null;
  if (
    only &&
    (new Set(only).size !== only.length ||
      only.some((id) => !CASES.some((c) => c.id === id)))
  ) {
    throw new Error("--only 有重複或不存在的案例 ID");
  }
  const armsRaw = str("arms") ?? "both";
  const arms = armsRaw === "both"
    ? ARMS
    : ARMS.filter((arm) => arm === armsRaw);
  if (arms.length === 0) {
    throw new Error("--arms 只能是 two_stage、legacy 或 both");
  }
  const budgetRaw = str("budget-usd");
  const budgetUsd = budgetRaw === null ? null : Number(budgetRaw);
  if (budgetUsd !== null && !(Number.isFinite(budgetUsd) && budgetUsd > 0)) {
    throw new Error("--budget-usd 要是正數");
  }
  const maxCalls = values.has("max-calls") ? int("max-calls", 0, 1000) : null;
  const run = values.has("run");
  if (
    run &&
    (!values.has("confirm-paid") || maxCalls === null || budgetUsd === null)
  ) {
    throw new Error(
      "真跑必須同時帶 --run --confirm-paid --max-calls=<上限> --budget-usd=<上限>（Eric 授權後）",
    );
  }
  return {
    tag,
    repeat: int("repeat", 1, 5),
    seed: int("seed", 20261001, 0xffffffff),
    only,
    arms,
    run,
    maxCalls,
    budgetUsd,
  };
}

// ---------------------------------------------------------------------------
// 呼叫計畫：每案例 × 每次重複 × 選定的臂，prompt 全由 production 函式產生
// ---------------------------------------------------------------------------

export type PlannedCall = {
  key: string;
  caseId: string;
  attempt: number;
  arm: Arm;
  requestId: string;
  situation: NewTopicSituation;
  /** 用戶真實的回答（兩臂共用）；legacy 看不到，但稽核用同一份對照。 */
  topicContext: NewTopicTopicContext;
  grounding: NewTopicGroundingPolicy;
  system: string;
  user: string;
};

export async function sha256(text: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** 固定 requestId：同案例同次重複的兩臂拿到同一個本輪內容素材（角度），可重現。 */
async function requestIdFor(caseId: string, attempt: number): Promise<string> {
  const h = await sha256(`new-topic-two-stage-eval:${caseId}:${attempt}`);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${
    h.slice(16, 20)
  }-${h.slice(20, 32)}`;
}

export async function buildPlan(
  cases: EvalCase[],
  repeat: number,
  arms: readonly Arm[] = ARMS,
): Promise<PlannedCall[]> {
  const plan: PlannedCall[] = [];
  for (const c of cases) {
    const partnerSummary = c.partner === null ? null : PARTNERS[c.partner];
    if (partnerSummary === undefined) {
      throw new Error(`案例 ${c.id} 的 partner 不存在`);
    }
    for (let attempt = 1; attempt <= repeat; attempt++) {
      const requestId = await requestIdFor(c.id, attempt);
      // 走 production 的請求驗證：案例組合不合法（例如冷掉了卻帶燈號）直接拒絕。
      const body = { requestId, partnerSummary, situation: c.situation };
      const full = sanitizeNewTopicRequest({
        ...body,
        topicContext: c.topicContext,
      });
      const legacy = sanitizeNewTopicRequest(body);
      if (!full.ok || !legacy.ok || full.request.topicContext === null) {
        throw new Error(
          `案例 ${c.id} 不是合法請求：${
            full.ok
              ? (legacy.ok ? "topicContext 空白" : legacy.reason)
              : full.reason
          }`,
        );
      }
      const topicContext = full.request.topicContext;
      for (const arm of arms) {
        const req = arm === "legacy" ? legacy.request : full.request;
        const shared = {
          partnerSummary: req.partnerSummary,
          effectiveStyleContext: req.effectiveStyleContext,
          situation: req.situation,
          requestId: req.requestId,
        };
        plan.push({
          key: `${c.id}.${attempt}.${arm}`,
          caseId: c.id,
          attempt,
          arm,
          requestId,
          situation: c.situation,
          topicContext,
          // 逐欄同 handler 的 newTopicGroundingPolicy：legacy 的 topicContext 是 null，所以也沒有素材豁免。
          grounding: {
            allowSharedFrame: allowsNewTopicSharedFrame({
              partnerSummary: req.partnerSummary,
              situation: req.situation,
              topicContext: req.topicContext,
            }),
            userMaterialText: req.topicContext?.materialText ?? null,
          },
          system: arm === "legacy"
            ? NEW_TOPIC_PROMPT
            : NEW_TOPIC_TWO_STAGE_PROMPT,
          user: arm === "legacy"
            ? buildNewTopicUserPrompt(shared)
            : buildNewTopicTwoStageUserPrompt({ ...shared, topicContext }),
        });
      }
    }
  }
  return plan;
}

// ---------------------------------------------------------------------------
// 費用估算
// ---------------------------------------------------------------------------

export function estimateInputTokens(
  call: Pick<PlannedCall, "system" | "user">,
): number {
  return Math.ceil(
    (call.system.length + call.user.length) * CJK_TOKENS_PER_CHAR,
  );
}

export function usd(inputTokens: number, outputTokens: number): number {
  return estimateCostUsd({
    inputTokens,
    outputTokens,
    cacheReadInputTokens: 0,
    cacheCreationInputTokens: 0,
  }, SONNET_5_PRICING);
}

export function estimatePlan(plan: PlannedCall[]) {
  const inputTokens = plan.reduce(
    (n, call) => n + estimateInputTokens(call),
    0,
  );
  return {
    calls: plan.length,
    inputTokens,
    typicalOutputTokens: plan.length * TYPICAL_OUTPUT_TOKENS,
    worstOutputTokens: plan.length * NEW_TOPIC_MAX_TOKENS,
    typicalUsd: usd(inputTokens, plan.length * TYPICAL_OUTPUT_TOKENS),
    worstUsd: usd(inputTokens, plan.length * NEW_TOPIC_MAX_TOKENS),
  };
}

// ---------------------------------------------------------------------------
// 結果整理（同 handler：parse → normalize＋grounding → 外洩檢查 → 紅燈收尾保證；不做修格式）
// ---------------------------------------------------------------------------

export type Inspection = {
  deliverable: boolean;
  promptLeak: boolean;
  normalizeReason: string | null;
  topics: NewTopicModelTopic[] | null;
  /** 用戶實際看到的推薦（兩段式臂已套紅燈收尾保證，同 production）。 */
  recommendationIndex: number | null;
  recommendationReason: string | null;
  /** 模型自己推的那題（套保證之前）。 */
  modelRecommendationIndex: number | null;
  /** 伺服器把推薦改成第一題（只有兩段式臂會發生）。 */
  redCloseOverridden: boolean;
  audit: NewTopicTwoStageAudit | null;
};

export function inspectOutput(call: PlannedCall, raw: string): Inspection {
  // 與 handler 同組：進階臂多查進階 sentinel（依臂判斷，兩臂都帶 topicContext 供稽核）。
  const promptLeak = call.arm === "legacy"
    ? hasAnalyzeChatPromptLeak(raw)
    : hasNewTopicTwoStagePromptLeak(raw);
  const normalized = normalizeNewTopicModelPayload(
    parseJsonObjectFromText(raw),
    call.grounding,
  );
  if (!normalized.ok) {
    return {
      deliverable: false,
      promptLeak,
      normalizeReason: normalized.reason,
      topics: null,
      recommendationIndex: null,
      recommendationReason: null,
      modelRecommendationIndex: null,
      redCloseOverridden: false,
      audit: null,
    };
  }
  // 同 handler：只有進階路徑（兩段式臂）套紅燈收尾保證；legacy 照模型。
  const enforced = call.arm === "two_stage"
    ? enforceNewTopicRedClose(normalized, {
      situation: call.situation,
      topicContext: call.topicContext,
    })
    : { normalized, overridden: false };
  const served = enforced.normalized;
  return {
    deliverable: !promptLeak,
    promptLeak,
    normalizeReason: null,
    topics: served.topics,
    recommendationIndex: served.recommendationIndex,
    recommendationReason: served.recommendationReason,
    modelRecommendationIndex: normalized.recommendationIndex,
    redCloseOverridden: enforced.overridden,
    // 兩臂都用用戶真實的回答稽核；只有 two_stage 算過關，legacy 是對照基準。
    audit: auditNewTopicTwoStageTopics({
      topics: served.topics,
      recommendationIndex: served.recommendationIndex,
      topicContext: call.topicContext,
      situation: call.situation,
    }),
  };
}

export type EvalRecord = Omit<PlannedCall, "system"> & {
  status: string;
  inspection: Inspection | null;
  raw?: string;
  stopReason?: string | null;
  usage?: { inputTokens: number; outputTokens: number } | null;
  costUsd?: number;
  costKnown?: boolean;
  elapsedMs?: number;
  error?: string;
};

// 同 new_topic_two_stage.ts 的 APOLOGY_PATTERN（未 export），改成 g 旗標數次數。
const APOLOGY_WORDS = /抱歉|不好意思|對不起|sorry/gi;

/** 一則 openingLine（可能分兩則傳）裡出現幾次道歉。 */
export function apologyCount(openingLine: string): number {
  return openingLine.match(APOLOGY_WORDS)?.length ?? 0;
}

/** 提案 §10 能機械判定的幾條；句數只算可交付的輸出，素材比率的分母連失敗一起算。 */
export function proposalChecks(records: EvalRecord[]) {
  const result = {} as Record<Arm, ReturnType<typeof armChecks>>;
  for (const arm of ARMS) {
    result[arm] = armChecks(records.filter((r) => r.arm === arm));
  }
  return result;
}

function armChecks(rows: EvalRecord[]) {
  const ok = rows.flatMap((r) =>
    r.inspection?.deliverable && r.inspection.audit
      ? [{ r, a: r.inspection.audit }]
      : []
  );
  const sum = (xs: typeof ok, f: (x: typeof ok[number]) => number) =>
    xs.reduce((n, x) => n + f(x), 0);
  // 分母＝這一臂所有有素材的呼叫；沒跑到、API 失敗、格式壞、外洩都算沒用到。
  const total = rows.filter((r) => r.topicContext.materialText !== null).length;
  const deliverableWithMaterial = ok.filter((x) =>
    x.a.materialUsedInRecommended !== null
  );
  const hit =
    deliverableWithMaterial.filter((x) => x.a.materialUsedInRecommended).length;
  const red = ok.filter((x) => x.a.redCloseApplied);
  return {
    outputs: rows.length,
    modelReturned: rows.filter((r) => r.inspection !== null).length,
    deliverable: ok.length,
    materialInRecommended: {
      hit,
      total,
      /** null＝分母 0、未評估（不是過關）。 */
      pass: total === 0 ? null : hit / total >= 0.9,
      /** 只看可交付輸出的條件比率；僅供參考，不判過關。 */
      deliverableOnly: { hit, total: deliverableWithMaterial.length },
    },
    sheNoReplyGapLines: sum(
      ok.filter((x) => x.r.topicContext.coldStop === "she_no_reply"),
      (x) => x.a.gapMentionLines,
    ),
    // 五題是五個備選，不是一起傳；規則是「同一題（可能兩則）裡道歉不超過一次」。
    iNoReplyTopicsOverOneApology: sum(
      ok.filter((x) => x.r.topicContext.coldStop === "i_no_reply"),
      (x) =>
        x.r.inspection!.topics!.filter((t) => apologyCount(t.openingLine) > 1)
          .length,
    ),
    redInviteLines: sum(
      ok.filter((x) => x.r.topicContext.engagement === "red"),
      (x) => x.a.inviteLines,
    ),
    coldInviteLines: sum(
      ok.filter((x) => x.r.situation === "went_cold"),
      (x) => x.a.inviteLines,
    ),
    bannedOpenerLines: sum(ok, (x) => x.a.bannedOpenerLines),
    // 紅燈收尾（還在聊／想更靠近＋她常只回哈哈、嗯）：只看可交付的輸出。
    redClose: {
      calls: rows.filter((r) => isNewTopicRedClose(r.situation, r.topicContext))
        .length,
      deliverable: red.length,
      modelPickedFirst:
        red.filter((x) => x.r.inspection!.modelRecommendationIndex === 0)
          .length,
      closeCueInFirst: sum(red, (x) => x.a.redCloseCueInFirst ?? 0),
      overridden: red.filter((x) => x.r.inspection!.redCloseOverridden).length,
    },
  };
}

// ---------------------------------------------------------------------------
// 盲測（給 Bruce）：每組兩版依 seed 打亂成甲／乙，只露五句＋推薦星號；解盲表另存
// ---------------------------------------------------------------------------

/** mulberry32：同 seed 同順序。 */
function seededRandom(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = Math.imul(s ^ (s >>> 15), s | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function blindAB(
  records: EvalRecord[],
  cases: EvalCase[],
  seed: number,
) {
  const rand = seededRandom(seed);
  const reveal: Record<string, { 甲: Arm; 乙: Arm }> = {};
  const unpaired: string[] = [];
  const lines = [
    "# 新話題盲測（每組兩版、順序已依 seed 打亂；評完再看 reveal-map.json）",
    "",
    "每組請填：甲、乙各有幾句你願意直接傳出去（0–5）；十句裡你最想傳的是哪一句（例：乙3）。",
    "★＝該版推薦的那一句；⏎＝分成兩則傳。",
    "",
  ];
  for (const c of cases) {
    const attempts = [
      ...new Set(
        records.filter((r) => r.caseId === c.id).map((r) => r.attempt),
      ),
    ].sort((a, b) => a - b);
    for (const attempt of attempts) {
      const code = `${c.id}#${attempt}`;
      const pair = ARMS.map((arm) =>
        records.find((r) =>
          r.caseId === c.id && r.attempt === attempt && r.arm === arm
        )
      );
      if (pair.some((r) => !r || r.inspection === null)) {
        unpaired.push(code);
        continue;
      }
      const order = rand() < 0.5 ? pair : [pair[1], pair[0]];
      reveal[code] = { 甲: order[0]!.arm, 乙: order[1]!.arm };
      lines.push(
        `## ${code}`,
        "",
        "對象資料：",
        "```",
        c.partner === null ? "（沒有對象資料）" : PARTNERS[c.partner],
        "```",
      );
      lines.push(`用戶的回答：${c.label}`);
      if (c.topicContext.materialText) {
        lines.push(`用戶寫的那句：「${c.topicContext.materialText}」`);
      }
      lines.push("");
      for (const [i, name] of (["甲", "乙"] as const).entries()) {
        const ins = order[i]!.inspection!;
        lines.push(`### ${name}`);
        if (!ins.deliverable || !ins.topics) {
          lines.push("（這一版沒有產出可用的五題）");
        } else {ins.topics.forEach((t, n) =>
            lines.push(
              `${n + 1}. ${t.openingLine.replace(/\n/g, " ⏎ ")}${
                n === ins.recommendationIndex ? " ★" : ""
              }`,
            )
          );}
        lines.push("");
      }
      lines.push("- 願意直接傳：甲＿句／乙＿句；最想傳：＿", "");
    }
  }
  return { markdown: lines.join("\n"), reveal, unpaired };
}

// ---------------------------------------------------------------------------
// 執行
// ---------------------------------------------------------------------------

function baseRecord(call: PlannedCall): Omit<PlannedCall, "system"> {
  const { system: _system, ...rest } = call;
  return rest;
}

async function git(args: string[]): Promise<string> {
  const result = await new Deno.Command("git", {
    args,
    cwd: new URL("../../", import.meta.url),
    stdout: "piped",
    stderr: "piped",
  }).output();
  if (!result.success) {
    throw new Error(`git ${args[0]} 失敗（exit ${result.code}）`);
  }
  return new TextDecoder().decode(result.stdout).trim();
}

async function main(args: string[]): Promise<void> {
  const opts = parseOptions(args);
  const selected = CASES.filter((c) => !opts.only || opts.only.includes(c.id));
  const plan = await buildPlan(selected, opts.repeat, opts.arms);
  const estimate = estimatePlan(plan);
  const out = new URL(`./out/${opts.tag}/`, import.meta.url);
  // 不覆寫任何既有證據（dry-run 或付費）。
  try {
    await Deno.stat(out);
    throw new Error(`輸出目錄已存在，請換 --tag：${out.pathname}`);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }

  let engineeringHead: string | null = null;
  let apiKey = "";
  if (opts.run) {
    engineeringHead = await git(["rev-parse", "HEAD"]);
    if (
      (await git(["status", "--porcelain", "--untracked-files=no"])).length > 0
    ) {
      throw new Error(
        "真跑前要先 commit：追蹤檔有未提交修改，結果無法對應工程版本",
      );
    }
    apiKey =
      (await Deno.readTextFile(`${Deno.env.get("HOME")}/.config/anthropic/key`))
        .trim();
    if (!apiKey) throw new Error("金鑰檔是空的");
  }

  await Deno.mkdir(out, { recursive: true });
  const write = (name: string, value: unknown) =>
    Deno.writeTextFile(
      new URL(name, out),
      typeof value === "string" ? value : JSON.stringify(value, null, 2) + "\n",
    );
  const manifest = {
    status: opts.run ? "RUNNING" : "DRY_RUN_NO_MODEL",
    startedAt: new Date().toISOString(),
    engineeringHead,
    model: MODEL,
    maxTokens: NEW_TOPIC_MAX_TOKENS,
    thinking: "disabled（同 production 對 Sonnet 5 的契約）",
    promptCache: "none",
    repairCalls: 0,
    twoStagePromptVersion: NEW_TOPIC_TWO_STAGE_PROMPT_VERSION,
    sha256: {
      legacySystemPrompt: await sha256(NEW_TOPIC_PROMPT),
      twoStageSystemPrompt: await sha256(NEW_TOPIC_TWO_STAGE_PROMPT),
      cases: await sha256(JSON.stringify(catalog)),
    },
    pricing: SONNET_5_PRICING,
    estimate: {
      ...estimate,
      method:
        `input＝字數×${CJK_TOKENS_PER_CHAR}；output 一般 ${TYPICAL_OUTPUT_TOKENS}／最壞 ${NEW_TOPIC_MAX_TOKENS}（max_tokens 全滿）`,
    },
    options: opts,
  };
  await write("manifest.json", manifest);

  if (!opts.run) {
    console.log(
      `=== 系統提示詞 legacy：NEW_TOPIC_PROMPT（${NEW_TOPIC_PROMPT.length} 字）===\n${NEW_TOPIC_PROMPT}\n`,
    );
    console.log(
      `=== 系統提示詞 two_stage：NEW_TOPIC_TWO_STAGE_PROMPT（${NEW_TOPIC_TWO_STAGE_PROMPT.length} 字）===\n${NEW_TOPIC_TWO_STAGE_PROMPT}\n`,
    );
    for (const call of plan) {
      console.log(
        `=== ${call.key}（requestId ${call.requestId}；估 input ${
          estimateInputTokens(call)
        } tokens）===\n${call.user}\n`,
      );
    }
    await write(
      "prompts.json",
      plan.map((call) => ({
        ...baseRecord(call),
        systemPrompt: call.arm === "legacy"
          ? "NEW_TOPIC_PROMPT"
          : "NEW_TOPIC_TWO_STAGE_PROMPT",
        estInputTokens: estimateInputTokens(call),
      })),
    );
    const caps = opts.budgetUsd === null
      ? ""
      : `；--budget-usd=${opts.budgetUsd} ${
        estimate.worstUsd <= opts.budgetUsd ? "涵蓋" : "不足以涵蓋"
      }最壞情況`;
    console.log(`=== 估算（dry-run，實際模型呼叫 0）===`);
    console.log(
      `案例 ${selected.length} × 重複 ${opts.repeat} × ${opts.arms.length} 臂（${
        opts.arms.join("、")
      }）= ${estimate.calls} 次呼叫${caps}`,
    );
    console.log(
      `預估 input ${estimate.inputTokens} tokens；output 一般 ${estimate.typicalOutputTokens}／最壞 ${estimate.worstOutputTokens}`,
    );
    console.log(
      `預估費用 一般 $${estimate.typicalUsd.toFixed(2)}／最壞 $${
        estimate.worstUsd.toFixed(2)
      }（${MODEL}：$${SONNET_5_PRICING.inputPerMTok}/M in、$${SONNET_5_PRICING.outputPerMTok}/M out）`,
    );
    console.log(JSON.stringify({
      status: "DRY_RUN_NO_MODEL",
      cases: selected.length,
      repeat: opts.repeat,
      arms: opts.arms,
      calls: estimate.calls,
      typicalUsd: Number(estimate.typicalUsd.toFixed(4)),
      worstUsd: Number(estimate.worstUsd.toFixed(4)),
      modelCallsMade: 0,
      output: out.pathname,
    }));
    return;
  }

  const records: EvalRecord[] = [];
  let calls = 0, spentUsd = 0, stopped = false;
  const log = (value: unknown) =>
    Deno.writeTextFile(
      new URL("requests.jsonl", out),
      JSON.stringify(value) + "\n",
      { append: true },
    );
  for (const call of plan) {
    const base = baseRecord(call);
    // 每次送出前用最壞情況（字數×1.5＋max_tokens 全滿）預檢；超過上限就整批停，不再送新呼叫。
    const reservation = usd(estimateInputTokens(call), NEW_TOPIC_MAX_TOKENS);
    if (
      stopped || calls >= opts.maxCalls! ||
      spentUsd + reservation > opts.budgetUsd!
    ) {
      stopped = true;
      records.push({
        ...base,
        status: "NOT_RUN_CAP_OR_STOP",
        inspection: null,
      });
      continue;
    }
    calls++;
    await log({
      key: call.key,
      call: calls,
      reservationUsd: reservation,
      state: "SENDING",
    });
    const started = Date.now();
    let record: EvalRecord;
    try {
      const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model: MODEL,
          max_tokens: NEW_TOPIC_MAX_TOKENS,
          thinking: { type: "disabled" },
          system: call.system,
          messages: [{ role: "user", content: call.user }],
        }),
        signal: AbortSignal.timeout(API_TIMEOUT_MS),
      });
      const data = await response.json().catch(() => null);
      if (!response.ok || data === null) {
        throw new Error(
          `HTTP ${response.status} ${data?.error?.type ?? ""}`.trim(),
        );
      }
      const raw = Array.isArray(data.content)
        ? data.content.filter((b: { type?: string }) => b.type === "text").map((
          b: { text?: string },
        ) => b.text ?? "").join("")
        : "";
      const u = data.usage;
      const usage =
        Number.isInteger(u?.input_tokens) && Number.isInteger(u?.output_tokens)
          ? {
            inputTokens: u.input_tokens as number,
            outputTokens: u.output_tokens as number,
          }
          : null;
      // usage 缺漏＝成本未知：以最壞情況計入並停止，不當免費。
      if (!usage) stopped = true;
      const costUsd = usage
        ? usd(usage.inputTokens, usage.outputTokens)
        : reservation;
      spentUsd += costUsd;
      record = {
        ...base,
        status: "MODEL_RETURNED",
        stopReason: data.stop_reason ?? null,
        usage,
        costUsd,
        costKnown: usage !== null,
        elapsedMs: Date.now() - started,
        raw,
        inspection: inspectOutput(call, raw),
      };
    } catch (error) {
      spentUsd += reservation;
      stopped = true;
      record = {
        ...base,
        status: "API_FAILED_COST_UNKNOWN",
        error: String(error).slice(0, 300),
        costUsd: reservation,
        costKnown: false,
        elapsedMs: Date.now() - started,
        inspection: null,
      };
    }
    records.push(record);
    await log({
      key: call.key,
      call: calls,
      state: record.status,
      costUsd: record.costUsd,
    });
    await write("records.json", records);
  }

  const checks = proposalChecks(records);
  const blind = blindAB(records, selected, opts.seed);
  await write("records.json", records);
  await write("blind_ab.md", blind.markdown);
  await write("reveal-map.json", blind.reveal);
  const t = checks.two_stage, l = checks.legacy;
  const mark = (
    pass: boolean | null,
  ) => (pass === null ? "未評估" : pass ? "✓" : "✗");
  const overDeadline =
    records.filter((r) => (r.elapsedMs ?? 0) > NEW_TOPIC_GENERATION_DEADLINE_MS)
      .length;
  const status = stopped
    ? "STOPPED_BY_CAP_OR_FAILURE"
    : "FINISHED_QUALITY_UNREVIEWED";
  const summary = [
    `# 新話題兩段式成對評測 · ${opts.tag} · ${MODEL}`,
    "",
    `工程 HEAD ${engineeringHead}；兩段式 prompt ${NEW_TOPIC_TWO_STAGE_PROMPT_VERSION}；案例 ${selected.length} × 重複 ${opts.repeat} × ${opts.arms.length} 臂（${
      opts.arms.join("、")
    }）。`,
    ...(opts.arms.length < ARMS.length
      ? [`本次只跑 ${opts.arms.join("、")}：沒跑的那一欄是 0/0，不是結果。`]
      : []),
    `實際呼叫 ${calls}／規劃 ${plan.length}；計入費用 $${
      spentUsd.toFixed(3)
    }（上限 $${opts.budgetUsd}；含成本未知的最壞情況）；提前停止：${
      stopped ? "是" : "否"
    }；超過 production 45 秒期限 ${overDeadline} 次。`,
    "",
    "## 提案 §10 機械檢查（two_stage 判過關；legacy 只當對照）",
    "",
    "| 檢查 | two_stage | legacy（對照） |",
    "|---|---|---|",
    `| 可交付／模型有回 | ${t.deliverable}/${t.modelReturned} | ${l.deliverable}/${l.modelReturned} |`,
    `| 推薦題用到素材 ≥90%（分母＝有素材的全部呼叫，失敗算沒用到） | ${
      mark(t.materialInRecommended.pass)
    } ${t.materialInRecommended.hit}/${t.materialInRecommended.total} | ${l.materialInRecommended.hit}/${l.materialInRecommended.total} |`,
    `| 　只看可交付的條件比率（參考，不判過關） | ${t.materialInRecommended.deliverableOnly.hit}/${t.materialInRecommended.deliverableOnly.total} | ${l.materialInRecommended.deliverableOnly.hit}/${l.materialInRecommended.deliverableOnly.total} |`,
    `| 她沒回我：提空窗 0 句 | ${
      mark(t.sheNoReplyGapLines === 0)
    } ${t.sheNoReplyGapLines} | ${l.sheNoReplyGapLines} |`,
    `| 我沒回她：同一題道歉超過一次的題數 0 | ${
      mark(t.iNoReplyTopicsOverOneApology === 0)
    } ${t.iNoReplyTopicsOverOneApology} | ${l.iNoReplyTopicsOverOneApology} |`,
    `| 紅燈：第一則邀約 0 句 | ${
      mark(t.redInviteLines === 0)
    } ${t.redInviteLines} | ${l.redInviteLines} |`,
    `| 冷掉了：第一則邀約 0 句 | ${
      mark(t.coldInviteLines === 0)
    } ${t.coldInviteLines} | ${l.coldInviteLines} |`,
    `| 在嗎／最近好嗎類 0 句 | ${
      mark(t.bannedOpenerLines === 0)
    } ${t.bannedOpenerLines} | ${l.bannedOpenerLines} |`,
    "",
    "## 紅燈收尾（還在聊／想更靠近＋她常只回哈哈、嗯；規格 §9.4）",
    "",
    "| 檢查 | two_stage | legacy（對照，不套伺服器保證） |",
    "|---|---|---|",
    `| 可交付／紅燈呼叫 | ${t.redClose.deliverable}/${t.redClose.calls} | ${l.redClose.deliverable}/${l.redClose.calls} |`,
    `| 模型自己推第一題 | ${t.redClose.modelPickedFirst}/${t.redClose.deliverable} | ${l.redClose.modelPickedFirst}/${l.redClose.deliverable} |`,
    `| 第一題有收尾字眼（先去忙、晚點、下次…） | ${t.redClose.closeCueInFirst}/${t.redClose.deliverable} | ${l.redClose.closeCueInFirst}/${l.redClose.deliverable} |`,
    `| 伺服器改推第一題 | ${t.redClose.overridden}/${t.redClose.deliverable} | — |`,
    "",
    "這些是字面規則計數（同 production 只記錄不擋的稽核），不是語意正確率；不捏造事實、不加曖昧、願意直接傳要靠 blind_ab.md 人工盲測。",
    opts.arms.length < ARMS.length
      ? "只跑一臂，沒有盲測。"
      : blind.unpaired.length
      ? `未成對、沒進盲測：${blind.unpaired.join("、")}`
      : "所有組都已成對進盲測。",
    "",
  ].join("\n");
  await write("summary.md", summary);
  await write("manifest.json", {
    ...manifest,
    status,
    finishedAt: new Date().toISOString(),
    modelCallsMade: calls,
    spentUsd,
    checks,
  });
  console.log(summary);
  console.log(
    JSON.stringify({
      status,
      modelCallsMade: calls,
      spentUsd: Number(spentUsd.toFixed(4)),
      stopped,
      output: out.pathname,
    }),
  );
}

if (import.meta.main) await main(Deno.args);
