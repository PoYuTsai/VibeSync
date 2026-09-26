// 結構刀黑箱：22 題 × 臂 × 重複，走真的 handler（claim／生成／投影／settle）。
//   A   ＝ OPENER_PLAN_WRITE=true、五風格寫手
//   B   ＝ OPENER_PLAN_WRITE=true、請求帶 openerCardSet=2（新版 App：一句推薦＋四句備選）
//   OLD ＝ 旗標關（f80b59bd 舊路徑，同一份程式碼逐位元組）
//
// 用法（在 repo 根目錄）：
//   deno run -A tools/opener-plan-write-eval/blackbox.ts --arm=B [--repeats=3] [--cases=F1,H01] [--tier=paid|free]
//        [--cap-usd=2.0] [--out=tools/opener-plan-write-eval/out/<runId>] [--live]
// 沒有 --live＝dry run：假模型、不連網、零費用，檢查管線與請求大小。
// --live 會讀 ~/.config/anthropic/key 真的付費呼叫 claude-sonnet-5：只在 Eric 說「跑」之後使用。

import {
  handleOpenerAnalyzeRequest,
  handleOpenerGenerateRequest,
  type OpenerFlowHandlerDeps,
  type OpenerFlowModelRequest,
} from "../../supabase/functions/analyze-chat/opener_flow_handler.ts";
import { OPENER_ANALYZE_PROMPT } from "../../supabase/functions/analyze-chat/opener_flow_prompt.ts";
import { OPENER_PLAN_PROMPT } from "../../supabase/functions/analyze-chat/opener_plan.ts";
import {
  analysisJsonFor,
  type CapturedCall,
  createDatabase,
  type EvalCase,
  EVAL_DIR,
  installFetchCapture,
  loadCases,
  parseArgs,
  readApiKey,
  supabaseFor,
  USER_ID,
  uuidFor,
} from "./lib.ts";

type Arm = "A" | "B" | "OLD";
const args = parseArgs(Deno.args);
const arm = String(args.arm ?? "A") as Arm;
// 旗標開時只有新版 App（openerCardSet=2＝B）走結構刀；A 已不會走到結構刀，量的其實是舊路徑（2026-09-26）。
if (!["B", "OLD"].includes(arm)) throw new Error("--arm must be B or OLD (A no longer reaches plan-write)");
const repeats = Number(args.repeats ?? 3);
/** --repeat=N 只跑第 N 次（多個程序並行，各自有上限與資料庫）。 */
const onlyRepeat = args.repeat === undefined ? null : Number(args.repeat);
const tier = String(args.tier ?? "paid");
const live = args.live === true;
const capUsd = Number(args["cap-usd"] ?? 2.0);
/** 單次生成的最壞預留（三次 Sonnet 5 呼叫）：預留不足就不送。 */
const RESERVE_USD = 0.08;
const runId = String(args.out ?? `${EVAL_DIR}out/${live ? "live" : "dry"}-${arm}-${tier}`);
const allCases = await loadCases();
const wanted = typeof args.cases === "string" ? new Set(String(args.cases).split(",")) : null;
const cases = allCases.filter((c) => !wanted || wanted.has(c.id));
await Deno.mkdir(runId, { recursive: true });

const env: Record<string, string> = arm === "OLD"
  ? { OPENER_PLAN_WRITE: "false" }
  : { OPENER_PLAN_WRITE: "true" };
const apiKey = live ? await readApiKey() : "dry-run-key";
const db = await createDatabase();
const supabase = supabaseFor(db);

function quota() {
  const sub = { monthly_messages_used: 0, daily_messages_used: 0, tier };
  return {
    sub,
    monthlyLimit: 100000,
    dailyLimit: 100000,
    effectiveTier: tier === "paid" ? "essential" : "free",
    allowedFeatures: tier === "paid" ? ["extend", "resonate", "tease", "humor", "coldRead"] : ["extend", "humor", "tease"],
  };
}

function baseDeps(body: Record<string, unknown>): OpenerFlowHandlerDeps {
  return {
    supabase,
    userId: USER_ID,
    requestBody: body,
    responseMode: "legacy",
    requestStartedAtMs: Date.now(),
    accountIsTest: true,
    claudeApiKey: apiKey,
    refreshTierFromRevenueCat: () => Promise.resolve("not_paid" as const),
    quota,
    env: (name) => env[name],
  };
}

/** dry run 的假模型：記錄請求、回可解析的最小輸出（不代表品質）。 */
function dryModel(c: EvalCase, sink: CapturedCall[]) {
  return (req: OpenerFlowModelRequest) => {
    const user = typeof req.messages[0]?.content === "string" ? req.messages[0].content : JSON.stringify(req.messages[0]?.content);
    const freeText = c.contribution.freeText;
    let body: unknown;
    if (req.system === OPENER_PLAN_PROMPT) {
      body = { spans: freeText ? [{ quote: freeText, role: "topic" }] : [], anchorCueIds: ["cue_1"], herStated: [], questionTarget: null, nominatedStyle: "extend" };
    } else if (arm === "OLD") {
      body = {
        materialReading: freeText ? [{ materialId: "material_1", subject: "unknown", kind: "raw_sentence", certainty: "stated", quote: freeText, usage: [{ quote: freeText, action: "use" }] }] : [],
        openers: { extend: `${freeText ?? "妳"}？`, resonate: "b", tease: "c", humor: "d", coldRead: "e" },
        rankedPicks: ["extend"],
        materialUse: { references: [], displayNotes: {} },
      };
    } else {
      body = { openers: { extend: "妳最近在忙什麼？", resonate: "b", tease: "c", humor: "d", coldRead: "e" }, cardReasons: {}, pioneerPlan: {} };
    }
    const rawText = JSON.stringify(body);
    sink.push({ model: "dry", maxTokens: req.maxTokens, thinking: null, temperature: null, system: req.system, user, status: 200, rawText, stopReason: "end_turn", usage: null, costUsd: 0, elapsedMs: 0 });
    return Promise.resolve({ rawText, model: "dry", inputTokens: 0, outputTokens: 0 });
  };
}

let spent = 0;
let index = 0;
const summary: Array<Record<string, unknown>> = [];
for (let repeat = 1; repeat <= repeats; repeat++) {
  if (onlyRepeat !== null && repeat !== onlyRepeat) continue;
  for (const c of cases) {
    index += 1;
    const key = `${arm}.${tier}.${c.id}.${repeat}`;
    if (live && spent + RESERVE_USD > capUsd) {
      summary.push({ key, status: "NOT_SENT_BUDGET" });
      continue;
    }
    const analysisRequestId = uuidFor("0f0f0f0f", index);
    const generationId = uuidFor("1e1e1e1e", index);
    const analyzeBody = {
      mode: "opener_analyze",
      openerFlowVersion: 1,
      openerContractVersion: 2,
      analysisRequestId,
      profileInfo: c.profileInfo,
      ...(c.initialUserNote ? { initialUserNote: c.initialUserNote } : {}),
    };
    // 第一段固定快照：不呼叫模型。
    const analyzeDeps = { ...baseDeps(analyzeBody), invokeModel: (req: OpenerFlowModelRequest) => {
      if (req.system !== OPENER_ANALYZE_PROMPT) throw new Error("unexpected analyze call");
      return Promise.resolve({ rawText: JSON.stringify(analysisJsonFor(c.profileInfo.bio ?? "", c.snapshot)), model: "fixture" });
    } };
    const analyzed = await handleOpenerAnalyzeRequest(analyzeDeps);
    const analysis = await analyzed.json() as Record<string, unknown>;
    if (analyzed.status !== 200) throw new Error(`${key}: fixture analyze failed ${analyzed.status} ${JSON.stringify(analysis)}`);

    const generateBody = {
      mode: "opener_generate",
      openerFlowVersion: 1,
      openerContractVersion: 2,
      sessionId: analysis.sessionId,
      analysisRevision: analysis.analysisRevision ?? 1,
      generationId,
      userContribution: { questionId: null, selectedOptionId: null, ...c.contribution },
      ...(arm === "B" ? { openerCardSet: 2 } : {}),
    };
    const calls: CapturedCall[] = [];
    const started = Date.now();
    let status = 0;
    let body: unknown = null;
    if (live) {
      const restore = installFetchCapture(calls);
      try {
        const res = await handleOpenerGenerateRequest(baseDeps(generateBody));
        status = res.status;
        body = await res.json();
      } finally {
        restore();
      }
    } else {
      const res = await handleOpenerGenerateRequest({ ...baseDeps(generateBody), invokeModel: dryModel(c, calls) });
      status = res.status;
      body = await res.json();
    }
    const cost = calls.reduce((sum, call) => sum + (call.costUsd ?? 0), 0);
    spent += cost;
    const row = { key, caseId: c.id, arm, tier, repeat, status, elapsedMs: Date.now() - started, costUsd: cost, calls: calls.length };
    summary.push(row);
    await Deno.writeTextFile(`${runId}/${key}.json`, JSON.stringify({ ...row, case: c, body, calls }, null, 1));
    console.log(JSON.stringify({ ...row, spentUsd: Number(spent.toFixed(6)) }));
  }
}
await Deno.writeTextFile(`${runId}/summary${onlyRepeat ? `.r${onlyRepeat}` : ""}.json`, JSON.stringify({ arm, tier, live, repeats, capUsd, spentUsd: spent, rows: summary }, null, 1));
await db.close();
console.log(`done ${arm}/${tier}: ${summary.length} rows, spent US$${spent.toFixed(4)} → ${runId}`);
