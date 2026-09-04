// Phase 4 完整矩陣・Hint／Debrief 輸出層抽查（Anthropic，真呼叫，Eric 核准 $1 上限）。
//
// 目的：`hintAgencyCoachingFor`／`debriefAgencyLedgerFor` 算出的結構證據有沒有
// 真的讓 hint／debrief 模型說出「你還沒回答她」／引用補救輪次——這是輸出層，
// 光看 evaluate_agency.ts 的分類器標籤看不到。
//
// 作法：把主矩陣 on 臂 artifact 的每一場逐輪重放（跟 replay_plan.ts
// 同一套 buildChatPromptBundle／agencyState 重建邏輯，只是這裡不重打 chat
// 模型——chat 回覆已經在 artifact 裡，重放只是為了正確推進 agencyState），
// 在每一輪她回完話的時間點呼叫 hintAgencyCoachingFor 記錄 kind≠none 的時點，
// 在每一場結束時呼叫 debriefAgencyLedgerFor 記錄補救輪非零的場。取前 N 個候選
// （見下面 --hint / --debrief 旗標），用 production 同款 buildHintMessages／
// buildDebriefMessages（agencyCoaching／agencyLedger 帶 on 臂證據）打真正的
// Claude（CLAUDE_SONNET_MODEL），off 對照組不傳證據。輸出逐則 JSON，人工讀。
//
// 用法：
//   export CLAUDE_API_KEY=$(cat ~/.config/anthropic/key)
//   deno run --allow-env --allow-read --allow-write --allow-net=api.anthropic.com \
//     tools/practice-agency-eval/hint_debrief_spotcheck.ts \
//     tools/practice-agency-eval/out/2026-09-05-p4full-beginner-on.json \
//     tools/practice-agency-eval/out/2026-09-05-hint-debrief-spotcheck.json \
//     [--hint-answer=10] [--hint-stop=10] [--hint-off=5] [--debrief=10] [--debrief-off=5]
import { buildChatPromptBundle } from "../../supabase/functions/practice-chat/prompt.ts";
import { buildHintMessages } from "../../supabase/functions/practice-chat/hint.ts";
import { buildDebriefMessages } from "../../supabase/functions/practice-chat/prompt.ts";
import { resolvePracticeProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";
import {
  type ConversationAgencyState,
  nextConversationAgencyState,
} from "../../supabase/functions/practice-chat/conversation_agency.ts";
import {
  type AgencyCoachingContext,
  type DebriefAgencyLedger,
  debriefAgencyLedgerFor,
  type HintAgencyCoaching,
  hintAgencyCoachingFor,
} from "../../supabase/functions/practice-chat/agency_coaching.ts";
import {
  BAKEOFF_THREAD_ID,
  buildBakeoffContextFixture,
} from "../practice-difficulty-bakeoff/bakeoff.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";
import { callClaude, CLAUDE_SONNET_MODEL } from "../../supabase/functions/practice-chat/claude.ts";

const TEMPERATURE_SCORE = 40;
const FAMILIARITY_SCORE = 10;

const inPath = Deno.args[0];
const outPath = Deno.args[1];
const flag = (k: string, d: string) =>
  Deno.args.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3) ?? d;
const wantHintAnswer = Number.parseInt(flag("hint-answer", "10"), 10);
const wantHintStop = Number.parseInt(flag("hint-stop", "10"), 10);
const wantHintOff = Number.parseInt(flag("hint-off", "5"), 10);
const wantDebrief = Number.parseInt(flag("debrief", "10"), 10);
const wantDebriefOff = Number.parseInt(flag("debrief-off", "5"), 10);

if (!inPath || !outPath || inPath.startsWith("--")) {
  console.error(
    "用法：hint_debrief_spotcheck.ts <on-arm-artifact.json> <out.json> [--hint-answer=10] [--hint-stop=10] [--hint-off=5] [--debrief=10] [--debrief-off=5]",
  );
  Deno.exit(1);
}

interface HintCandidate {
  profileId: string;
  scenarioId: string;
  repeat: number;
  roundIndex: number;
  kind: HintAgencyCoaching["kind"];
  turns: PracticeTurn[];
  difficulty: "easy" | "normal" | "challenge";
}
interface DebriefCandidate {
  profileId: string;
  scenarioId: string;
  repeat: number;
  ledger: DebriefAgencyLedger;
  turns: PracticeTurn[];
  difficulty: "easy" | "normal" | "challenge";
}

const art = JSON.parse(await Deno.readTextFile(inPath));
const hintAnswer: HintCandidate[] = [];
const hintStop: HintCandidate[] = [];
const debriefHits: DebriefCandidate[] = [];

for (const s of art.results) {
  if (s.error) continue;
  const difficulty = (s.difficulty ?? "normal") as "easy" | "normal" | "challenge";
  const profile = resolvePracticeProfile({
    profileId: s.profileId,
    difficulty,
  });
  const fx = buildBakeoffContextFixture(profile);
  const chatContext = {
    sceneContext: fx.sceneContext,
    acquaintanceOrigin: fx.acquaintanceOrigin,
    memorySummary: fx.memorySummary,
    timeContext: fx.timeContext,
    herRecentMomentsBlock: fx.herRecentMomentsBlock,
  };
  const ctx: AgencyCoachingContext = {
    difficulty,
    isGame: false,
    profileId: s.profileId,
  };
  const turns: PracticeTurn[] = [];
  let agencyState: ConversationAgencyState | null = null;
  let roundIndex = 0;
  for (const t of s.turns) {
    if (t.role !== "user") {
      turns.push({ role: "ai", text: t.reply });
      continue;
    }
    roundIndex += 1;
    turns.push({ role: "user", text: t.userText });
    const bundle = buildChatPromptBundle(turns, profile, {
      replyStyle: true,
      agencyMode: "on",
      visiblePracticeThreadId: BAKEOFF_THREAD_ID,
      partnerState: null,
      styleState: null,
      agencyState,
      practiceMode: "beginner",
      temperatureScore: TEMPERATURE_SCORE,
      familiarityScore: FAMILIARITY_SCORE,
      ...chatContext,
      // deno-lint-ignore no-explicit-any
    } as any);
    const askedUser = bundle.responsePlan?.askUserFocus !== undefined;
    if (bundle.agencyDecision && (bundle.agencyDecision.applied || askedUser)) {
      agencyState = nextConversationAgencyState(
        agencyState,
        bundle.agencyDecision.decision,
        null,
        askedUser,
      );
    }
    turns.push({ role: "ai", text: t.reply });

    const hint = hintAgencyCoachingFor(turns, agencyState, ctx);
    if (hint.kind === "answer_her_question" && hintAnswer.length < wantHintAnswer) {
      hintAnswer.push({
        profileId: s.profileId,
        scenarioId: s.scenarioId,
        repeat: s.repeat,
        roundIndex,
        kind: hint.kind,
        turns: [...turns],
        difficulty,
      });
    } else if (
      hint.kind === "stop_dropping_words" && hintStop.length < wantHintStop
    ) {
      hintStop.push({
        profileId: s.profileId,
        scenarioId: s.scenarioId,
        repeat: s.repeat,
        roundIndex,
        kind: hint.kind,
        turns: [...turns],
        difficulty,
      });
    }
  }
  if (debriefHits.length < wantDebrief) {
    const ledger = debriefAgencyLedgerFor(turns, ctx);
    if (ledger.repairTurnCount > 0) {
      debriefHits.push({
        profileId: s.profileId,
        scenarioId: s.scenarioId,
        repeat: s.repeat,
        ledger,
        turns,
        difficulty,
      });
    }
  }
  if (
    hintAnswer.length >= wantHintAnswer && hintStop.length >= wantHintStop &&
    debriefHits.length >= wantDebrief
  ) break;
}

console.error(
  `候選：hint answer ${hintAnswer.length}/${wantHintAnswer}、hint stop ${hintStop.length}/${wantHintStop}、debrief ${debriefHits.length}/${wantDebrief}`,
);

const apiKeyRaw = Deno.env.get("CLAUDE_API_KEY");
if (!apiKeyRaw) {
  console.error("缺 CLAUDE_API_KEY");
  Deno.exit(1);
}
const apiKey: string = apiKeyRaw;

interface HintResultRow {
  role: string;
  scenarioId: string;
  kind: string;
  arm: "on" | "off";
  coaching: string | null;
  raw?: string;
  error?: string;
}
interface DebriefResultRow {
  role: string;
  scenarioId: string;
  repairTurns: number[];
  arm: "on" | "off";
  summary: string | null;
  watchouts: string | null;
  dateChance: string | null;
  raw?: string;
  error?: string;
}

function extractField(raw: string, key: string): string | null {
  try {
    const obj = JSON.parse(raw.slice(raw.indexOf("{"), raw.lastIndexOf("}") + 1));
    const v = obj[key];
    return typeof v === "string" ? v : v == null ? null : JSON.stringify(v);
  } catch {
    return null;
  }
}

const hintResults: HintResultRow[] = [];
const debriefResults: DebriefResultRow[] = [];
let calls = 0;

async function callHint(c: HintCandidate, arm: "on" | "off") {
  const profile = resolvePracticeProfile({
    profileId: c.profileId,
    difficulty: c.difficulty,
  });
  const messages = buildHintMessages({
    turns: c.turns,
    profile,
    practiceMode: "beginner",
    temperatureScore: TEMPERATURE_SCORE,
    familiarityScore: FAMILIARITY_SCORE,
    agencyCoaching: arm === "on" ? { kind: c.kind, unresolvedCount: 1 } : null,
  });
  calls += 1;
  try {
    const raw = await callClaude({
      apiKey,
      model: CLAUDE_SONNET_MODEL,
      messages,
      maxTokens: 650,
      temperature: 0.45,
      timeoutMs: 20000,
    });
    hintResults.push({
      role: c.profileId,
      scenarioId: c.scenarioId,
      kind: c.kind,
      arm,
      coaching: extractField(raw, "coaching"),
      raw,
    });
  } catch (error) {
    hintResults.push({
      role: c.profileId,
      scenarioId: c.scenarioId,
      kind: c.kind,
      arm,
      coaching: null,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

async function callDebrief(c: DebriefCandidate, arm: "on" | "off") {
  const profile = resolvePracticeProfile({
    profileId: c.profileId,
    difficulty: c.difficulty,
  });
  const messages = buildDebriefMessages(c.turns, profile, {
    practiceMode: "beginner",
    temperatureScore: TEMPERATURE_SCORE,
    familiarityScore: FAMILIARITY_SCORE,
    partnerState: null,
    agencyLedger: arm === "on" ? c.ledger : null,
  });
  calls += 1;
  try {
    const raw = await callClaude({
      apiKey,
      model: CLAUDE_SONNET_MODEL,
      messages,
      maxTokens: 1200,
      temperature: 0.4,
      timeoutMs: 25000,
    });
    debriefResults.push({
      role: c.profileId,
      scenarioId: c.scenarioId,
      repairTurns: [...c.ledger.repairTurns],
      arm,
      summary: extractField(raw, "summary"),
      watchouts: extractField(raw, "watchouts"),
      dateChance: extractField(raw, "dateChance"),
      raw,
    });
  } catch (error) {
    debriefResults.push({
      role: c.profileId,
      scenarioId: c.scenarioId,
      repairTurns: [...c.ledger.repairTurns],
      arm,
      summary: null,
      watchouts: null,
      dateChance: null,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

for (const c of hintAnswer) await callHint(c, "on");
for (const c of hintStop) await callHint(c, "on");
for (const c of hintAnswer.slice(0, Math.ceil(wantHintOff / 2))) {
  await callHint(c, "off");
}
for (const c of hintStop.slice(0, Math.floor(wantHintOff / 2))) {
  await callHint(c, "off");
}
for (const c of debriefHits) await callDebrief(c, "on");
for (const c of debriefHits.slice(0, wantDebriefOff)) await callDebrief(c, "off");

console.error(`Anthropic 呼叫數：${calls}`);
await Deno.writeTextFile(
  outPath,
  JSON.stringify({ hintResults, debriefResults, calls }, null, 2),
);
console.error(`寫入 ${outPath}`);
