// Phase 4.5c：口語化質疑的**分類器召回率量測工具**（只寫工具，本輪不跑付費步驟）。
//
// 為什麼要有這支：Phase 4.5b 的標準模式階梯**完全依賴**分類器回報的
// `aiChallengedThisTurn`（她這一則有沒有在問「你剛剛那句是什麼意思」）。但那個
// 欄位對**無標記中文反問**（「蛤？」「你在講什麼」「？」「什麼意思」「你是在
// 亂說還是怎樣」）的召回率**從來沒有量過**——真人講話不會加「請問你的意思
// 是」，模型判準寫的是語意條件，兩者之間有多大落差是個空白。
//
// 作法（兩段，第二段才花錢）：
//   1. 用一組**可審閱的口語質疑候選正則**，從既有 run artifact 裡挑出她的回覆。
//      這組正則**不是真值**，只是候選集：`--dry-run` 會把每一條正則、命中數與
//      逐則命中內容印出來，要人工複核之後才決定要不要花錢重放。
//   2. 對每一則候選，用 production 的分類器重放一次（`--mode=standard` 走
//      `buildStandardAgencyClassifierMessages`，`--mode=assisted` 走
//      `buildTurnClassifierMessages`），輸出 `aiChallengedThisTurn=true` 的比例
//      ＝**召回率代理**（分母是候選集，不是真值集，所以是代理不是召回率本身）。
//
// 估價在最開頭印出來（`pricing.ts` 的觀測單價），跑之前就看得到會花多少。
//
// 用法：
//   # 只列候選、不打模型、不需要 API key
//   deno run --allow-read tools/practice-agency-eval/classifier_recall.ts \
//     tools/practice-agency-eval/out/2026-09-05-p45b-standard{A,B}-*.json --dry-run
//
//   # 真的重放（**會花錢，要 Eric 明確授權**）
//   deno run --allow-env --allow-read --allow-write --allow-net=api.deepseek.com \
//     tools/practice-agency-eval/classifier_recall.ts <artifact.json...> \
//     [--mode=standard|assisted] [--concurrency=8] [--out=<file>]

import { callDeepSeek } from "../../supabase/functions/practice-chat/deepseek.ts";
import { resolvePracticeProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";
import {
  buildStandardAgencyClassifierMessages,
  buildTurnClassifierMessages,
  parseStandardAgencyClassification,
  parseTurnClassification,
} from "../../supabase/functions/practice-chat/temperature.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";
import { buildBakeoffContextFixture } from "../practice-difficulty-bakeoff/bakeoff.ts";
import { readDeepSeekKey } from "./run_agency.ts";
import { DEEPSEEK_CLASSIFIER_USD_PER_CALL } from "./pricing.ts";

const CLASSIFIER_MAX_TOKENS = 450;
const CLASSIFIER_TEMPERATURE = 0.2;
const MODEL_TIMEOUT_MS = 30_000;
/** 逐輪分類器要的兩個分數，跟 run_agency.ts 的 beginner 常數同值。 */
const HEAT_SCORE = 40;
const FAMILIARITY_SCORE = 10;

/**
 * 口語質疑的**候選正則**（不是真值判準）。
 *
 * 每一條都刻意寫得窄而可讀，配一句「為什麼它可能是質疑」。這組東西的唯一用途
 * 是把幾百則回覆縮成一批人看得完的候選；命中不代表她真的在質疑（「什麼意思都
 * 可以」這種句子會誤中），沒命中也不代表她沒質疑（「你這句跟剛剛那件事有關
 * 嗎」就抓不到）。所以：
 *   - `--dry-run` 一定把整組正則與逐則命中印出來供人工複核；
 *   - 報告裡的數字只能寫成「候選集內 `aiChallengedThisTurn=true` 的比例」，
 *     **不可以**寫成「分類器的召回率是 X%」。
 *
 * 踩坑筆記「繁中正則分類器沒有詞邊界會連環誤判」：中文沒有詞邊界，所以這裡
 * 全部改用「整則很短」或「句尾語氣」這類**結構條件**來收斂，不做裸關鍵字。
 */
export interface ChallengeCandidate {
  readonly id: string;
  readonly pattern: RegExp;
  /** 給人工複核看的一句話：這條在抓什麼、可能誤中什麼。 */
  readonly note: string;
}

export const CHALLENGE_CANDIDATES: readonly ChallengeCandidate[] = [
  {
    id: "bare_question_mark",
    pattern: /^[\s？?]*[？?]+[\s？?]*$/u,
    note:
      "整則只有問號（「？」「??」）——最短的質疑形態；不會誤中含內容的句子。",
  },
  {
    id: "short_interjection",
    pattern: /^(蛤|哈|嗄|啊|欸|誒|欵|嗯|哦|喔|痾|呃)[\s？?！!…。.]*$/u,
    note:
      "整則只有一個語氣詞（蛤／欸／嗯…），可帶標點——真人表達「聽不懂」的主要形態；可能誤中單純的附和「嗯。」。",
  },
  {
    id: "interjection_then_question",
    pattern: /^(蛤|哈|嗄|啊|欸|誒|欵|痾|呃)[\s？?！!，,]/u,
    note:
      "語氣詞開頭再接一句（「蛤？你問這個幹嘛」）——4.4 逐字裡最常見的形態。",
  },
  {
    id: "what_meaning",
    pattern: /(什麼意思|甚麼意思|啥意思|三小|殺小|蝦密)/u,
    note: "直接問語意；「三小／殺小」是台語口語同義形態。",
  },
  {
    id: "what_are_you_saying",
    pattern: /(在(講|說)什麼|在(講|說)啥|講三小|說三小)/u,
    note: "「你在講什麼」家族；可能誤中「我不知道要在講什麼好」這種自述。",
  },
  {
    id: "cannot_follow",
    pattern: /(聽不懂|看不懂|不懂你|沒聽懂|不太懂)/u,
    note: "直說跟不上；可能誤中「我不太懂這個領域」這種自陳能力。",
  },
  {
    id: "suspect_nonsense",
    pattern: /(亂(說|講|扯|回)|唬爛|瞎掰|你在(唬|扯)|還是怎樣|還是幹嘛)/u,
    note: "「你是在亂說還是怎樣」家族——帶懷疑的質疑，不只是問語意。",
  },
  {
    id: "why_suddenly",
    pattern:
      /((怎麼|幹嘛|為什麼|為何).{0,4}(突然|忽然)|突然.{0,4}(講|說|問|丟))/u,
    note: "指出他跳題（「你幹嘛突然講這個」）；不含猜測時就是純質疑。",
  },
  {
    id: "relevance_challenge",
    pattern:
      /(跟.{0,8}(有|有沒有).{0,4}關|有關係嗎|關這什麼事|干.{0,3}什麼事)/u,
    note: "直接問關聯（「這跟剛剛在聊的有關嗎」）。",
  },
  {
    id: "not_answered_yet",
    pattern: /(還沒回答|沒回答我|答非所問|你沒有回答|回答我的問題)/u,
    note: "指出他沒回答；judge 這一側算 clarify_or_challenge。",
  },
  {
    id: "who_what_is_that",
    pattern: /^(那|這)?(是)?(誰|什麼|啥)[\s？?]*$/u,
    note: "整則只有「誰？」「什麼？」這種裸疑問詞。",
  },
];

/** 這一則回覆命中了哪幾條候選正則（回 id 陣列，空陣列＝不是候選）。 */
export function candidateHitsFor(reply: string): string[] {
  const text = reply.trim();
  if (!text) return [];
  return CHALLENGE_CANDIDATES.filter((c) => c.pattern.test(text)).map((c) =>
    c.id
  );
}

// ── artifact → 候選 job ───────────────────────────────────────────────────
interface ArtifactTurn {
  readonly role: "user" | "ai";
  readonly userText: string;
  readonly reply: string;
  readonly scripted?: boolean;
  readonly probe?: { readonly id: string } | null;
}
interface ArtifactSession {
  readonly profileId: string;
  readonly difficulty: string;
  readonly scenarioId: string;
  readonly repeat: number;
  readonly turns: readonly ArtifactTurn[];
  readonly error?: string;
}
export interface RecallJob {
  readonly artifact: string;
  readonly profileId: string;
  readonly difficulty: string;
  readonly scenarioId: string;
  readonly repeat: number;
  readonly probeId: string;
  /** 玩家前一句（表格用）。 */
  readonly userText: string;
  /** 她這一則（＝候選）。 */
  readonly reply: string;
  readonly hits: readonly string[];
  /** 重建到玩家這句為止的逐字稿（分類器的呼叫慣例，跟 handler 一致）。 */
  readonly turns: readonly PracticeTurn[];
}

/**
 * 純函式：把一份 artifact 展開成候選 job。只看**模型真的生成過**的輪次
 * （`role === "user"` 且非 `scripted`）；腳本前文不是她生成的，不能拿來量。
 */
export function buildRecallJobs(
  artifactName: string,
  sessions: readonly ArtifactSession[],
): RecallJob[] {
  const jobs: RecallJob[] = [];
  for (const s of sessions) {
    if (s.error) continue;
    const turns: PracticeTurn[] = [];
    for (const t of s.turns) {
      if (t.role === "ai") {
        turns.push({ role: "ai", text: t.reply });
        continue;
      }
      const hits = t.scripted ? [] : candidateHitsFor(t.reply);
      if (hits.length > 0) {
        jobs.push({
          artifact: artifactName,
          profileId: s.profileId,
          difficulty: s.difficulty,
          scenarioId: s.scenarioId,
          repeat: s.repeat,
          probeId: t.probe?.id ?? "-",
          userText: t.userText,
          reply: t.reply,
          hits,
          turns: [...turns, { role: "user", text: t.userText }],
        });
      }
      turns.push({ role: "user", text: t.userText });
      turns.push({ role: "ai", text: t.reply });
    }
  }
  return jobs;
}

/** 這一批候選重放要花多少（觀測單價，見 pricing.ts）。 */
export function estimateRecallRunUsd(candidates: number): number {
  return candidates * DEEPSEEK_CLASSIFIER_USD_PER_CALL;
}

export interface RecallRow extends RecallJob {
  readonly aiChallengedThisTurn: boolean | null;
  /**
   * 這一筆的 `aiChallengedThisTurn` 是 parser repair 出來的（模型漏答／吐非
   * 布林），不是模型真的判 false——召回率代理的分母要扣掉這些筆
   * （跟 `classifier_replay.ts` 的 `sharedPastClaimRepaired` 同一條線）。
   */
  readonly repaired: boolean;
  readonly error: string | null;
}

export interface RecallSummary {
  readonly candidates: number;
  /** 模型真的吐了布林值的筆數（分母）。 */
  readonly explicit: number;
  readonly challenged: number;
  /** `challenged / explicit`；`explicit === 0` 時是 `null`，不除以零。 */
  readonly recallProxy: number | null;
  readonly repaired: number;
  readonly errors: number;
  /** 逐條候選正則各自的命中數與 `aiChallengedThisTurn=true` 數。 */
  readonly byCandidate: Record<string, { n: number; challenged: number }>;
}

/** 純函式：把逐則結果彙總（測試直接餵假 row，不打模型）。 */
export function summarizeRecall(rows: readonly RecallRow[]): RecallSummary {
  const byCandidate: Record<string, { n: number; challenged: number }> = {};
  let explicit = 0, challenged = 0, repaired = 0, errors = 0;
  for (const r of rows) {
    if (r.error !== null) errors++;
    if (r.repaired) repaired++;
    const counts = r.error === null && !r.repaired;
    if (counts && r.aiChallengedThisTurn !== null) {
      explicit++;
      if (r.aiChallengedThisTurn) challenged++;
    }
    for (const id of r.hits) {
      byCandidate[id] ??= { n: 0, challenged: 0 };
      byCandidate[id].n++;
      if (counts && r.aiChallengedThisTurn === true) {
        byCandidate[id].challenged++;
      }
    }
  }
  return {
    candidates: rows.length,
    explicit,
    challenged,
    recallProxy: explicit === 0 ? null : challenged / explicit,
    repaired,
    errors,
    byCandidate,
  };
}

function flag(name: string, fallback: string): string {
  return Deno.args.find((a) => a.startsWith(`--${name}=`))?.slice(
    name.length + 3,
  ) ?? fallback;
}

async function main(): Promise<void> {
  const paths = Deno.args.filter((a) => !a.startsWith("--"));
  if (paths.length === 0) {
    console.error(
      "用法：classifier_recall.ts <artifact.json...> [--dry-run] [--mode=standard|assisted] [--concurrency=8] [--out=…]",
    );
    Deno.exit(2);
  }
  const dryRun = Deno.args.includes("--dry-run");
  const mode = flag("mode", "standard");
  if (mode !== "standard" && mode !== "assisted") {
    throw new Error(`classifier_recall_invalid_mode: ${mode}`);
  }
  const concurrency = Number.parseInt(flag("concurrency", "8"), 10);

  const jobs: RecallJob[] = [];
  let totalGenerated = 0;
  for (const path of paths) {
    const artifact = JSON.parse(await Deno.readTextFile(path));
    const sessions = artifact.results as ArtifactSession[];
    for (const s of sessions) {
      if (s.error) continue;
      totalGenerated += s.turns.filter((t) =>
        t.role === "user" && !t.scripted
      ).length;
    }
    jobs.push(...buildRecallJobs(path, sessions));
  }

  // 估價一定印在最開頭：跑之前就看得到會花多少。
  const usd = estimateRecallRunUsd(jobs.length);
  console.log(
    `# 候選 ${jobs.length} 則／生成輪 ${totalGenerated} 則（${
      (jobs.length / Math.max(totalGenerated, 1) * 100).toFixed(1)
    }%）｜mode=${mode}｜重放估價 $${
      usd.toFixed(4)
    }（$${DEEPSEEK_CLASSIFIER_USD_PER_CALL}／次觀測單價，見 pricing.ts）`,
  );
  console.log(
    "# 下面這組正則是**候選集，不是真值**：命中不代表她真的在質疑，沒命中也不代表沒質疑。要人工複核。",
  );
  console.log("\n候選正則 | 命中則數 | 說明");
  const hitCount = new Map<string, number>();
  for (const j of jobs) {
    for (const id of j.hits) hitCount.set(id, (hitCount.get(id) ?? 0) + 1);
  }
  for (const c of CHALLENGE_CANDIDATES) {
    console.log(
      `${c.id}｜${c.pattern.source} | ${hitCount.get(c.id) ?? 0} | ${c.note}`,
    );
  }

  if (dryRun) {
    console.log(
      "\n（--dry-run：不打模型）逐則候選：情境 | 探針 | 玩家 | 她 | 命中",
    );
    for (const j of jobs) {
      console.log(
        `${j.scenarioId}/${j.profileId}#${j.repeat} | ${j.probeId} | ${
          j.userText.replace(/\n/g, " ")
        } | ${j.reply.replace(/\n/g, " ")} | ${j.hits.join(",")}`,
      );
    }
    return;
  }

  const apiKey = await readDeepSeekKey();
  const rows: RecallRow[] = [];
  let next = 0;
  const worker = async () => {
    while (next < jobs.length) {
      const job = jobs[next++];
      const profile = resolvePracticeProfile({
        profileId: job.profileId,
        difficulty: job.difficulty as "easy" | "normal" | "challenge",
      });
      const fixture = buildBakeoffContextFixture(profile);
      try {
        const messages = mode === "standard"
          ? buildStandardAgencyClassifierMessages({
            turns: [...job.turns],
            profile,
            assistantReply: job.reply,
            memorySummary: fixture.memorySummary,
            herRecentMoments: fixture.herRecentMoments,
          })
          : buildTurnClassifierMessages({
            turns: [...job.turns],
            profile,
            heatScore: HEAT_SCORE,
            familiarityScore: FAMILIARITY_SCORE,
            assistantReply: job.reply,
            agencyEnabled: true,
            memorySummary: fixture.memorySummary,
            herRecentMoments: fixture.herRecentMoments,
          });
        const raw = await callDeepSeek({
          apiKey,
          messages,
          maxTokens: CLASSIFIER_MAX_TOKENS,
          temperature: CLASSIFIER_TEMPERATURE,
          jsonMode: true,
          timeoutMs: MODEL_TIMEOUT_MS,
        });
        const parsed = mode === "standard"
          ? parseStandardAgencyClassification(raw)
          : parseTurnClassification(raw, { requireCoherence: true });
        rows.push({
          ...job,
          aiChallengedThisTurn: parsed.aiChallengedThisTurn ?? null,
          repaired: parsed.repairedFields?.includes("aiChallengedThisTurn") ??
            false,
          error: null,
        });
      } catch (e) {
        rows.push({
          ...job,
          aiChallengedThisTurn: null,
          repaired: false,
          error: e instanceof Error ? e.message : String(e),
        });
      }
    }
  };
  await Promise.all(Array.from({ length: concurrency }, worker));

  const summary = summarizeRecall(rows);
  console.log(
    `\n候選 ${summary.candidates}｜有效判定 ${summary.explicit}（repair ${summary.repaired}、失敗 ${summary.errors} 已扣除）｜` +
      `aiChallengedThisTurn=true ${summary.challenged}｜**召回率代理** ${
        summary.recallProxy === null
          ? "n/a"
          : `${(summary.recallProxy * 100).toFixed(1)}%`
      }`,
  );
  console.log("\n候選正則 | 命中 | 判 true | 比例");
  for (const c of CHALLENGE_CANDIDATES) {
    const g = summary.byCandidate[c.id];
    if (!g) continue;
    console.log(
      `${c.id} | ${g.n} | ${g.challenged} | ${
        (g.challenged / g.n * 100).toFixed(1)
      }%`,
    );
  }
  console.log("\n逐則對照：情境 | 探針 | 玩家 | 她 | 命中 | 判定");
  for (const r of rows) {
    console.log(
      `${r.scenarioId}/${r.profileId}#${r.repeat} | ${r.probeId} | ${
        r.userText.replace(/\n/g, " ")
      } | ${r.reply.replace(/\n/g, " ")} | ${r.hits.join(",")} | ${
        r.error ?? (r.repaired ? "repaired" : String(r.aiChallengedThisTurn))
      }`,
    );
  }
  const outPath = flag("out", "");
  if (outPath) {
    await Deno.writeTextFile(
      outPath,
      JSON.stringify({ mode, summary, rows }, null, 2) + "\n",
    );
    console.error(`[classifier-recall] 寫入 ${outPath}`);
  }
}

if (import.meta.main) await main();
