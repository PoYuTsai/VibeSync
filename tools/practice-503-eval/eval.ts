// 離線 eval harness：量化 practice-chat hint/debrief 在「主觀語意複審 reject」
// 終局出口的 503 比率，舊邏輯 vs 新邏輯（Change A/B/C）對比。
//
// 誠實聲明：這是離線 eval，不打任何模型。它以「注入 semantic verdict(issueKinds)
// ＋固定逐字稿 fixture ＋候選卡」的方式，直接驅動 handler 的降級出口決策邏輯
// （salvage 用的是與 handler 相同的真實 parseHintResult / parseDebriefCard /
// stripUnsupportedThirdPartyDetails 函式）。量測的是「到達終局 reject 出口時，
// 每條路徑會轉 503 還是改為供給」，非 prod 實測命中率。
//
// 執行：deno run --allow-read tools/practice-503-eval/eval.ts

import { parseHintResult } from "../../supabase/functions/practice-chat/hint.ts";
import { parseDebriefCard } from "../../supabase/functions/practice-chat/debrief_card.ts";
import {
  buildHintFactContext,
  stripUnsupportedThirdPartyDetails,
} from "../../supabase/functions/practice-chat/hint_fact_ledger.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";

type IssueKind =
  | "unsupported_fact"
  | "generic"
  | "strategy_mismatch"
  | "unsafe";

type Outcome = "serve" | "503";

// ---- 與 handler 相同的降級決策（faithful replica）--------------------------

function salvageHint(
  turns: PracticeTurn[],
  mode: "chat" | "game",
  candidate: { warmUp: string; steady: string; coaching: string },
): boolean {
  const factContext = buildHintFactContext({ turns });
  const cleaned = {
    warmUp: stripUnsupportedThirdPartyDetails({
      text: candidate.warmUp,
      field: "reply",
      context: factContext,
    }),
    steady: stripUnsupportedThirdPartyDetails({
      text: candidate.steady,
      field: "reply",
      context: factContext,
    }),
    coaching: stripUnsupportedThirdPartyDetails({
      text: candidate.coaching,
      field: "coaching",
      context: factContext,
    }),
  };
  try {
    parseHintResult(JSON.stringify(cleaned), {
      mode,
      turns,
      enforceGeneratedQuality: true,
      semanticAdjudicated: true,
    });
    return true;
  } catch {
    return false;
  }
}

function salvageDebrief(
  turns: PracticeTurn[],
  mode: "chat" | "game",
  card: Record<string, unknown>,
): boolean {
  try {
    parseDebriefCard(JSON.stringify(card), {
      allowGameBreakdown: mode === "game",
      requireCompleteCard: true,
      turns,
      repairPreservedHintCritique: false,
      enforceGeneratedQuality: true,
      semanticAdjudicated: true,
    });
    return true;
  } catch {
    return false;
  }
}

// 舊邏輯：終局 semantic reject 一律 503。
function oldOutcome(): Outcome {
  return "503";
}

function newHintOutcome(
  turns: PracticeTurn[],
  mode: "chat" | "game",
  candidate: { warmUp: string; steady: string; coaching: string },
  issueKinds: IssueKind[],
  isPrefetch: boolean,
): Outcome {
  if (isPrefetch) return "503";
  if (issueKinds.includes("unsafe")) return "503";
  return salvageHint(turns, mode, candidate) ? "serve" : "503";
}

function newDebriefOutcome(
  turns: PracticeTurn[],
  mode: "chat" | "game",
  card: Record<string, unknown>,
  issueKinds: IssueKind[],
): Outcome {
  if (issueKinds.includes("unsafe")) return "503";
  if (issueKinds.includes("unsupported_fact")) return "503";
  return salvageDebrief(turns, mode, card) ? "serve" : "503";
}

// ---- Fixtures --------------------------------------------------------------

interface HintCase {
  path: "newbie_hint" | "game_hint";
  batch: string;
  turns: PracticeTurn[];
  mode: "chat" | "game";
  candidate: { warmUp: string; steady: string; coaching: string };
  issueKinds: IssueKind[];
  isPrefetch?: boolean;
}

interface DebriefCase {
  path: "newbie_debrief" | "game_debrief";
  batch: string;
  turns: PracticeTurn[];
  mode: "chat" | "game";
  card: Record<string, unknown>;
  issueKinds: IssueKind[];
}

const climbTurns: PracticeTurn[] = [
  { role: "ai", text: "我這週末打算去爬象山，你假日都怎麼安排？" },
];
const dessertTurns: PracticeTurn[] = [
  {
    role: "ai",
    text: "我最近迷上做甜點，上週烤了檸檬塔，你有沒有什麼在鑽研的？",
  },
];
const coffeeGameTurns: PracticeTurn[] = [
  { role: "user", text: "妳平常喝咖啡嗎？" },
  { role: "ai", text: "會，假日常去找間安靜的店坐一下。" },
  { role: "user", text: "我沒有固定喝哪種，通常看當天心情。" },
  { role: "ai", text: "那你比較常點手沖還是拿鐵？" },
];

const groundedNewbieHint = {
  warmUp: "象山我也爬過，那段階梯真的會喘，你都挑清晨還是傍晚去？",
  steady: "聽你說要爬象山，我週末通常在家耍廢，被你這樣一講有點想動了。",
  coaching: "她主動分享週末爬象山，先接住這個具體行程再把話題延伸到她的節奏。",
};
const thirdPartyNewbieHint = {
  warmUp: "你烤檸檬塔喔，我朋友阿凱也超愛，改天想跟你討教一下配方。",
  steady: "聽你說在鑽研甜點，我對烘焙一竅不通，被你這樣一講有點想學了。",
  coaching: "她主動分享做甜點烤檸檬塔，先接住這個具體嗜好再把話題延伸。",
};
const groundedGameHint = {
  warmUp: "真的看當天心情，手沖和拿鐵都不固定。",
  steady: "我沒有固定派，妳這題要看當天狀態才答得出來。",
  coaching:
    "Game 心法：她在縮小咖啡偏好，建立熟悉階段直接回答看心情即可。速約任務：這輪不約，先延續咖啡口味。",
};
const thirdPartyGameHint = {
  warmUp: "真的看當天心情，我朋友阿凱都笑我亂喝，手沖拿鐵都不固定。",
  steady: "我沒有固定派，妳這題要看當天狀態才答得出來。",
  coaching:
    "Game 心法：她在縮小咖啡偏好，建立熟悉階段直接回答看心情即可。速約任務：這輪不約，先延續咖啡口味。",
};

const hintCases: HintCase[] = [
  // --- newbie hint ---
  {
    path: "newbie_hint",
    batch: "subjective_reject",
    turns: climbTurns,
    mode: "chat",
    candidate: groundedNewbieHint,
    issueKinds: ["strategy_mismatch"],
  },
  {
    path: "newbie_hint",
    batch: "revision_required",
    turns: climbTurns,
    mode: "chat",
    candidate: groundedNewbieHint,
    issueKinds: ["generic"],
  },
  {
    path: "newbie_hint",
    batch: "venue_named",
    turns: dessertTurns,
    mode: "chat",
    candidate: thirdPartyNewbieHint,
    issueKinds: ["generic"],
  },
  {
    path: "newbie_hint",
    batch: "safety_unsafe",
    turns: climbTurns,
    mode: "chat",
    candidate: groundedNewbieHint,
    issueKinds: ["unsafe"],
  },
  {
    path: "newbie_hint",
    batch: "prefetch_no_salvage",
    turns: climbTurns,
    mode: "chat",
    candidate: groundedNewbieHint,
    issueKinds: ["strategy_mismatch"],
    isPrefetch: true,
  },
  // --- game hint ---
  {
    path: "game_hint",
    batch: "subjective_reject",
    turns: coffeeGameTurns,
    mode: "game",
    candidate: groundedGameHint,
    issueKinds: ["strategy_mismatch"],
  },
  {
    path: "game_hint",
    batch: "revision_required",
    turns: coffeeGameTurns,
    mode: "game",
    candidate: groundedGameHint,
    issueKinds: ["generic"],
  },
  {
    path: "game_hint",
    batch: "venue_named",
    turns: coffeeGameTurns,
    mode: "game",
    candidate: thirdPartyGameHint,
    issueKinds: ["generic"],
  },
  {
    path: "game_hint",
    batch: "safety_unsafe",
    turns: coffeeGameTurns,
    mode: "game",
    candidate: groundedGameHint,
    issueKinds: ["unsafe"],
  },
];

const residenceTurns: PracticeTurn[] = [
  { role: "user", text: "妳平常住哪裡？" },
  { role: "ai", text: "我住台南，最常在中西區活動。" },
];
const groundedResidenceCard = {
  summary: "她說自己住台南、常在中西區活動，你有接住這兩個生活圈資訊。",
  strengths: ["你先問她住哪裡，讓她分享台南與中西區生活圈。"],
  watchouts: ["下一步可以問她在中西區最常做什麼，別只重複地名。"],
  suggestedLine: "原來妳常在中西區活動，休假最常去哪裡放空？",
  vibe: "中性",
  dateChance: "low",
  dateChanceReason: "她分享台南與中西區生活圈，但還沒提見面或時間。",
  nextInviteMove: "先問她在中西區最常去哪裡放空，等她回答再交換自己的生活圈。",
  hintAssessment: { verdict: "preserved", revisedEvidenceQuote: null },
};

const gameDebriefTurns: PracticeTurn[] = [
  { role: "user", text: "早安，昨天有睡飽嗎？" },
  { role: "ai", text: "我還在賴床，腦袋還沒開機。" },
];
const groundedGameDebriefCard = {
  summary: "她拿賴床狀態跟你開玩笑，你有接到這個輕鬆的梗。",
  strengths: ["你接住她賴床沒開機的狀態，沒有急著換話題。"],
  watchouts: ["下一步別只回一句玩笑，可以多留一點自己的起床畫面。"],
  suggestedLine: "賴床冠軍先慢慢醒，下午清醒了再跟我報到。",
  vibe: "暖",
  dateChance: "medium",
  dateChanceReason: "她願意拿賴床狀態和你開玩笑。",
  nextInviteMove: "先延續賴床梗，等她再投入一輪才丟短咖啡窗口。",
  hintAssessment: { verdict: "preserved", revisedEvidenceQuote: null },
  gameBreakdown: {
    phaseReached: "賴床話題的熟悉建立",
    missedVariable: "還在賴床這句沒有再多給她一個好接的球",
    failureState: "停在一句玩笑收尾，沒有延伸她的賴床狀態",
    nextFirstLine: "賴床冠軍先慢慢醒，我等你清醒了再聊",
    inviteDirection: "先延續賴床話題，再看她是否多投入才推窗口",
  },
};

const debriefCases: DebriefCase[] = [
  {
    path: "newbie_debrief",
    batch: "subjective_reject",
    turns: residenceTurns,
    mode: "chat",
    card: groundedResidenceCard,
    issueKinds: ["strategy_mismatch"],
  },
  {
    path: "newbie_debrief",
    batch: "revision_required",
    turns: residenceTurns,
    mode: "chat",
    card: groundedResidenceCard,
    issueKinds: ["generic"],
  },
  {
    path: "newbie_debrief",
    batch: "safety_unsafe",
    turns: residenceTurns,
    mode: "chat",
    card: groundedResidenceCard,
    issueKinds: ["unsafe"],
  },
  {
    path: "newbie_debrief",
    batch: "safety_unsupported_fact",
    turns: residenceTurns,
    mode: "chat",
    card: groundedResidenceCard,
    issueKinds: ["unsupported_fact"],
  },
  {
    path: "game_debrief",
    batch: "subjective_reject",
    turns: gameDebriefTurns,
    mode: "game",
    card: groundedGameDebriefCard,
    issueKinds: ["strategy_mismatch"],
  },
  {
    path: "game_debrief",
    batch: "revision_required",
    turns: gameDebriefTurns,
    mode: "game",
    card: groundedGameDebriefCard,
    issueKinds: ["generic"],
  },
  {
    path: "game_debrief",
    batch: "safety_unsafe",
    turns: gameDebriefTurns,
    mode: "game",
    card: groundedGameDebriefCard,
    issueKinds: ["unsafe"],
  },
  {
    path: "game_debrief",
    batch: "safety_unsupported_fact",
    turns: gameDebriefTurns,
    mode: "game",
    card: groundedGameDebriefCard,
    issueKinds: ["unsupported_fact"],
  },
];

// ---- Run & aggregate -------------------------------------------------------

interface Row {
  total: number;
  old503: number;
  new503: number;
  serve: number;
}
const byPath = new Map<string, Row>();
const byBatch: Array<{
  path: string;
  batch: string;
  old: Outcome;
  neu: Outcome;
}> = [];

function record(path: string, oldO: Outcome, newO: Outcome, batch: string) {
  const row = byPath.get(path) ?? { total: 0, old503: 0, new503: 0, serve: 0 };
  row.total += 1;
  if (oldO === "503") row.old503 += 1;
  if (newO === "503") row.new503 += 1;
  else row.serve += 1;
  byPath.set(path, row);
  byBatch.push({ path, batch, old: oldO, neu: newO });
}

for (const c of hintCases) {
  const oldO = oldOutcome();
  const newO = newHintOutcome(
    c.turns,
    c.mode,
    c.candidate,
    c.issueKinds,
    c.isPrefetch === true,
  );
  record(c.path, oldO, newO, c.batch);
}
for (const c of debriefCases) {
  const oldO = oldOutcome();
  const newO = newDebriefOutcome(c.turns, c.mode, c.card, c.issueKinds);
  record(c.path, oldO, newO, c.batch);
}

console.log("=== 逐案結果（注入 verdict → 出口決策）===");
for (const r of byBatch) {
  console.log(
    `${r.path.padEnd(16)} ${r.batch.padEnd(24)} old=${r.old.padEnd(5)} new=${r.neu}`,
  );
}

console.log("\n=== 各路徑 503 率：舊 → 新 ===");
console.log(
  "path".padEnd(16) + "n".padEnd(4) + "old503%".padEnd(10) + "new503%".padEnd(10) + "serve",
);
for (const [path, row] of byPath) {
  const oldPct = ((row.old503 / row.total) * 100).toFixed(0) + "%";
  const newPct = ((row.new503 / row.total) * 100).toFixed(0) + "%";
  console.log(
    path.padEnd(16) +
      String(row.total).padEnd(4) +
      oldPct.padEnd(10) +
      newPct.padEnd(10) +
      String(row.serve),
  );
}

// 安全底線自檢：所有 safety_* 批次在新邏輯下仍必須 503。
const safetyLeaks = byBatch.filter((r) =>
  r.batch.startsWith("safety_") && r.neu !== "503"
);
console.log(
  "\n=== 安全底線自檢 ===\n" +
    (safetyLeaks.length === 0
      ? "PASS：所有 unsafe / unsupported_fact 案例在新邏輯下仍 503，未供給。"
      : "FAIL：安全案例洩漏！" + JSON.stringify(safetyLeaks)),
);
if (safetyLeaks.length > 0) Deno.exit(1);
