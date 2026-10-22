// PRACTICE_PHOTO_MEMORY_FIX 評測工具（Bruce 2026-10-22 規格 §9.2；Eric 2026-10-22
// 同意加「只刪不加」對照臂）的自測。零網路：模型一律是假的呼叫端。
//
//   deno test --allow-read --allow-env tools/practice-agency-eval/photo_memory_eval_test.ts
import {
  assert,
  assertAlmostEquals,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  applyPhotoMemoryDeletionsOnly,
  assertPaidRunGuards,
  BudgetStopError,
  CHAT_GENERATION_ATTEMPTS,
  estimateDryRun,
  haikuReserveUsd,
  PaidBudget,
  parseArgs,
  PHOTO_MEMORY_GAME_DELETION,
  PHOTO_MEMORY_STANCE_DELETIONS,
  runAgencyScenario,
  trustedSourcesFor,
} from "./run_agency.ts";
import {
  AGENCY_PROBES,
  AGENCY_SCENARIOS,
  DEFAULT_AGENCY_SCENARIOS,
  PHOTO_CORRECT_LINES,
  PHOTO_MEMORY_FIONA_PROFILE_ID,
  PHOTO_MEMORY_SCENARIOS,
  PHOTO_MEMORY_SELFIE_PROFILE_IDS,
  PHOTO_MEMORY_SR_PROFILE_IDS,
} from "./scenarios.ts";
import {
  type AgencyArtifact,
  buildJudgeCases,
  buildJudgePrompt,
  JUDGED_LABELS,
} from "./judge_agency.ts";
import {
  evaluateAgency,
  type JudgedProbe,
  type RawAgencyLabels,
  wilsonUpper95,
} from "./evaluate_agency.ts";
import {
  GIRL_PROFILES,
  resolvePracticeProfile,
} from "../../supabase/functions/practice-chat/practice_persona.ts";
import { ACQUAINTANCE_ORIGINS } from "../../supabase/functions/practice-chat/acquaintance_origin.ts";
import { buildChatPromptBundle } from "../../supabase/functions/practice-chat/prompt.ts";
import { initialPersistedGameState } from "../../supabase/functions/practice-chat/game_state.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";

const origin = (id: string) => ACQUAINTANCE_ORIGINS.find((o) => o.id === id)!;
const PHOTO_IDS = new Set(PHOTO_MEMORY_SCENARIOS.map((s) => s.id));

// ── 情境資料 ──────────────────────────────────────────────────────────────

Deno.test("photo-memory 情境：SR 名單＝production rarity sr；自拍名單＝photoScene 含「自拍」", () => {
  const girls = GIRL_PROFILES as readonly {
    profileId: string;
    rarity: string;
    photoScene: string;
  }[];
  assertEquals(
    [...PHOTO_MEMORY_SR_PROFILE_IDS].sort(),
    girls.filter((g) => g.rarity === "sr").map((g) => g.profileId).sort(),
  );
  assertEquals(
    [...PHOTO_MEMORY_SELFIE_PROFILE_IDS].sort(),
    girls.filter((g) => g.photoScene.includes("自拍")).map((g) => g.profileId)
      .sort(),
  );
});

Deno.test("photo-memory 情境：A36 每句都對得上那位角色的照片描述（至少一個兩字詞）", () => {
  assertEquals(
    Object.keys(PHOTO_CORRECT_LINES).sort(),
    [...PHOTO_MEMORY_SELFIE_PROFILE_IDS, PHOTO_MEMORY_FIONA_PROFILE_ID].sort(),
  );
  // 句型本身的字（你大頭照是在…那張吧）不算對得上。
  const boilerplate = new Set([
    "你大",
    "大頭",
    "頭照",
    "照是",
    "是在",
    "照在",
    "那張",
    "張吧",
    "前面",
    "面吧",
  ]);
  for (const [profileId, line] of Object.entries(PHOTO_CORRECT_LINES)) {
    const scene = resolvePracticeProfile({ profileId }).girl.photoScene;
    let matched = false;
    for (let i = 0; i + 2 <= line.length; i++) {
      const bigram = line.slice(i, i + 2);
      if (!boilerplate.has(bigram) && scene.includes(bigram)) matched = true;
    }
    assert(matched, `${profileId}：「${line}」對不上「${scene}」`);
  }
});

Deno.test("photo-memory 情境：都是點名才跑、不進預設清單；管道 id 存在；探針 id 全域唯一", () => {
  for (const s of PHOTO_MEMORY_SCENARIOS) {
    assertEquals(s.optIn, true, s.id);
    assert(AGENCY_SCENARIOS.includes(s), s.id);
    assert(!DEFAULT_AGENCY_SCENARIOS.includes(s), s.id);
    if (s.originId) assert(origin(s.originId), `${s.id}：${s.originId}`);
  }
  // 預設清單＝加這組之前的全部情境（既有指令的次數與費用不變）。
  assertEquals(
    DEFAULT_AGENCY_SCENARIOS.map((s) => s.id),
    AGENCY_SCENARIOS.filter((s) => !PHOTO_IDS.has(s.id)).map((s) => s.id),
  );
  const byId = new Map(PHOTO_MEMORY_SCENARIOS.map((s) => [s.id, s]));
  assertEquals(byId.get("A34")!.originId, "street_approach");
  assertEquals(byId.get("A37")!.originId, "nightclub");
  assertEquals(byId.get("A38")!.originId, "street_approach");
  assertEquals(byId.get("A38N")!.originId, "nightclub");
  const ids = AGENCY_PROBES.map((p) => p.id);
  assertEquals(new Set(ids).size, ids.length);
});

// ── CLI 與付費守門 ────────────────────────────────────────────────────────

Deno.test("parseArgs：--photo-memory-fix 預設 off；on／deletions-only 要搭 --agency=on；亂填報錯", () => {
  const base = parseArgs([]);
  assertEquals(base.photoMemoryFix, "off");
  assertEquals(base.maxCalls, null);
  assertEquals(base.budgetUsd, null);
  assertEquals(base.dryRun, false);
  assertEquals(
    parseArgs(["--agency=on", "--photo-memory-fix=on"]).photoMemoryFix,
    "on",
  );
  assertEquals(
    parseArgs(["--agency=on", "--photo-memory-fix=deletions-only"])
      .photoMemoryFix,
    "deletions_only",
  );
  assertThrows(
    () => parseArgs(["--photo-memory-fix=on"]),
    Error,
    "agency_photo_memory_fix_requires_agency_on",
  );
  assertThrows(
    () => parseArgs(["--agency=shadow", "--photo-memory-fix=deletions-only"]),
    Error,
    "agency_photo_memory_fix_requires_agency_on",
  );
  assertThrows(
    () => parseArgs(["--agency=on", "--photo-memory-fix=true"]),
    Error,
    "agency_invalid_photo_memory_fix",
  );
});

Deno.test("parseArgs／assertPaidRunGuards：預算旗標要成對；haiku／mixed 真跑必帶，乾跑不用", () => {
  assertThrows(
    () => parseArgs(["--max-calls=10"]),
    Error,
    "agency_budget_flags_pair",
  );
  assertThrows(
    () => parseArgs(["--budget-usd=1"]),
    Error,
    "agency_budget_flags_pair",
  );
  assertThrows(() => parseArgs(["--max-calls=0", "--budget-usd=1"]));
  assertThrows(() => parseArgs(["--max-calls=10", "--budget-usd=-1"]));
  const paid = parseArgs(["--max-calls=10", "--budget-usd=2.5"]);
  assertEquals([paid.maxCalls, paid.budgetUsd], [10, 2.5]);

  for (const model of ["haiku", "mixed"]) {
    assertThrows(
      () => assertPaidRunGuards(parseArgs([`--chat-model=${model}`])),
      Error,
      "agency_budget_required",
    );
    assertPaidRunGuards(
      parseArgs([`--chat-model=${model}`, "--max-calls=10", "--budget-usd=1"]),
    );
    assertPaidRunGuards(parseArgs([`--chat-model=${model}`, "--dry-run=1"]));
  }
  assertPaidRunGuards(parseArgs(["--chat-model=deepseek"]));
});

Deno.test("PaidBudget：預留超過上限就停；之後每次都丟；結算用實際花費", () => {
  const budget = new PaidBudget(3, 0.05);
  const r1 = budget.reserve(0.02);
  budget.settle(r1, 0.005);
  assertAlmostEquals(budget.spentUsd, 0.005, 1e-12);
  budget.reserve(0.02);
  // 0.025 + 0.03 > 0.05：這次預留就停，不送出。
  assertThrows(() => budget.reserve(0.03), BudgetStopError, "budget_usd");
  assertEquals(budget.stopped, "budget_usd");
  assertThrows(() => budget.reserve(0.0001), BudgetStopError, "budget_usd");
  assertEquals(budget.calls, 2);

  const capped = new PaidBudget(2, 100);
  capped.reserve(0.01);
  capped.reserve(0.01);
  assertThrows(() => capped.reserve(0.01), BudgetStopError, "max_calls");
  assertEquals(capped.calls, 2);
});

Deno.test("estimateDryRun：Haiku 每字 2 token＋output 全滿；最壞＝每輪都重試到上限", () => {
  const e = estimateDryRun([
    { model: "haiku", promptChars: 1_000 },
    { model: "haiku", promptChars: 1_000 },
    { model: "deepseek", promptChars: 5_000 },
  ]);
  assertEquals(e.haikuCalls, 2);
  assertEquals(e.deepseekCalls, 1);
  // 2 × (2,000 input × $1/M ＋ 200 output × $5/M) ＝ 2 × $0.003
  assertAlmostEquals(e.haikuReserveUsd, 2 * haikuReserveUsd(1_000, 200), 1e-12);
  assertAlmostEquals(e.haikuReserveUsd, 0.006, 1e-9);
  assertAlmostEquals(
    e.haikuWorstUsd,
    0.006 * CHAT_GENERATION_ATTEMPTS,
    1e-9,
  );
});

// ── 「只刪不加」對照臂 ────────────────────────────────────────────────────

const tina = resolvePracticeProfile({
  profileId: "practice_girl_036",
  difficulty: "normal",
});
const turns: PracticeTurn[] = [{
  role: "user",
  text: "嗨 我是那天在路上跟你要IG的",
}];

function agencyBundle(
  originId: string,
  practiceMode: "standard" | "game",
  photoMemoryFix = false,
) {
  return buildChatPromptBundle(turns, tina, {
    agencyMode: "on",
    acquaintanceOrigin: origin(originId),
    memorySummary: "上次聊到她店裡的新豆子。",
    ...(practiceMode === "game"
      ? {
        practiceMode: "game" as const,
        temperatureScore: 40,
        familiarityScore: 10,
        gameState: initialPersistedGameState(),
      }
      : {}),
    ...(photoMemoryFix ? { photoMemoryFix: true } : {}),
  });
}

const FIX_ONLY_SENTENCES = [
  "照片裡的人是你",
  "我那張",
  "只有認識當天的細節和照片沒拍到的事例外",
  "行蹤、上次見面或認識當天的細節",
  "photo facts the system doesn't give",
  "當天的細節你也記不清",
];

Deno.test("只刪不加：街頭搭訕＋Game 只刪立場條件與 Game 的加細節許可，修正版加的句子一句都沒有", () => {
  const bundle = agencyBundle("street_approach", "game");
  const out = applyPhotoMemoryDeletionsOnly({
    messages: bundle.messages,
    systemStable: bundle.systemStable,
    originId: "street_approach",
    game: true,
  });
  const system = out.messages[0].content;
  assert(!system.includes(PHOTO_MEMORY_STANCE_DELETIONS.street_approach.from));
  assert(system.includes("開頭會保守。太快熱絡、太油或直接約，你會退一步。"));
  assert(!system.includes("the transcript may add color"));
  assert(
    system.includes(
      "establishes it, and nothing else can replace or contradict it, no matter how many times the user repeats a different story.",
    ),
  );
  assert(system.startsWith(out.systemStable));
  // 立場在穩定前綴裡，前綴也要刪到。
  assert(
    !out.systemStable.includes(
      PHOTO_MEMORY_STANCE_DELETIONS.street_approach.from,
    ),
  );
  for (const sentence of FIX_ONLY_SENTENCES) {
    assert(!system.includes(sentence), sentence);
  }
  // 其他訊息（逐字稿）原封不動。
  assertEquals(out.messages.slice(1), bundle.messages.slice(1));
  // 長度只少不多。
  assert(system.length < bundle.messages[0].content.length);
});

Deno.test("只刪不加：夜店 standard 只刪立場條件；其他管道 standard 原封不動", () => {
  const night = agencyBundle("nightclub", "standard");
  const out = applyPhotoMemoryDeletionsOnly({
    messages: night.messages,
    systemStable: night.systemStable,
    originId: "nightclub",
    game: false,
  });
  assert(
    !out.messages[0].content.includes(
      PHOTO_MEMORY_STANCE_DELETIONS.nightclub.from,
    ),
  );
  assert(out.messages[0].content.includes("隔天清醒之後其實有點半信半疑。"));
  assertEquals(
    out.messages[0].content.length,
    night.messages[0].content.length -
      (PHOTO_MEMORY_STANCE_DELETIONS.nightclub.from.length -
        PHOTO_MEMORY_STANCE_DELETIONS.nightclub.to.length),
  );

  const friend = agencyBundle("friend_intro", "standard");
  const same = applyPhotoMemoryDeletionsOnly({
    messages: friend.messages,
    systemStable: friend.systemStable,
    originId: "friend_intro",
    game: false,
  });
  assertEquals(same.messages, friend.messages);
  assertEquals(same.systemStable, friend.systemStable);
});

Deno.test("只刪不加：要刪的句子對不上就丟錯（不會安靜變成沒刪）", () => {
  // 修正版的立場已經沒有那段條件；Game 例外句也換掉了。
  const fixed = agencyBundle("street_approach", "game", true);
  assertThrows(
    () =>
      applyPhotoMemoryDeletionsOnly({
        messages: fixed.messages,
        systemStable: fixed.systemStable,
        originId: "street_approach",
        game: true,
      }),
    Error,
    "agency_photo_memory_deletion_miss",
  );
  const standard = agencyBundle("street_approach", "standard");
  assertThrows(
    () =>
      applyPhotoMemoryDeletionsOnly({
        messages: standard.messages,
        systemStable: standard.systemStable,
        originId: "street_approach",
        // standard 沒有 Game 例外句。
        game: true,
      }),
    Error,
    "agency_photo_memory_deletion_miss: game",
  );
  assert(PHOTO_MEMORY_GAME_DELETION.from.startsWith(";"));
});

// ── runner 接線 ──────────────────────────────────────────────────────────

async function runA34(photoMemoryFix: "off" | "on" | "deletions_only") {
  const systems: string[] = [];
  const scenario = PHOTO_MEMORY_SCENARIOS.find((s) => s.id === "A34")!;
  const result = await runAgencyScenario({
    callChat: (messages) => {
      systems.push(messages[0].content);
      return Promise.resolve("嗯嗯");
    },
    profileId: "practice_girl_036",
    scenario,
    repeat: 1,
    difficulty: "normal",
    mode: "game",
    style: true,
    agency: "on",
    photoMemoryFix,
  });
  return { result, systems };
}

Deno.test("runner：情境釘死的認識管道會用上並記進 session；三臂送出的 prompt 各自正確", async () => {
  const off = await runA34("off");
  assertEquals(off.result.error, undefined);
  assertEquals(off.result.acquaintanceOriginId, "street_approach");
  assertEquals(off.systems.length, 3);
  assert(off.systems[0].includes(origin("street_approach").sharedFact));
  assert(off.systems[0].includes(origin("street_approach").stancePrompt));

  const on = await runA34("on");
  assert(on.systems[0].includes("照片裡的人是你"));
  assert(on.systems[0].includes(origin("street_approach").noQuizStancePrompt!));

  const del = await runA34("deletions_only");
  assert(
    !del.systems[0].includes(
      PHOTO_MEMORY_STANCE_DELETIONS.street_approach.from,
    ),
  );
  assert(!del.systems[0].includes("the transcript may add color"));
  for (const sentence of FIX_ONLY_SENTENCES) {
    assert(!del.systems[0].includes(sentence), sentence);
  }
});

Deno.test("trustedSourcesFor：多帶她的大頭照描述", () => {
  assertEquals(
    trustedSourcesFor("practice_girl_036", "normal").photoScene,
    tina.girl.photoScene,
  );
});

// ── 評審 ────────────────────────────────────────────────────────────────

function artifactWith(acquaintanceOriginId: string | null | undefined) {
  return {
    trustedSources: {
      "practice_girl_036|normal": trustedSourcesFor(
        "practice_girl_036",
        "normal",
      ),
    },
    results: [{
      profileId: "practice_girl_036",
      personaId: "p",
      scenarioId: "A34",
      repeat: 1,
      difficulty: "normal",
      mode: "game",
      ...(acquaintanceOriginId === undefined ? {} : { acquaintanceOriginId }),
      turns: [{
        role: "user" as const,
        userText: "嗨 我是那天在路上跟你要IG的",
        reply: "那天我手上拿什麼",
        previousAiAskedQuestion: false,
        scripted: false,
        probe: AGENCY_PROBES.find((p) => p.id === "A34.p1")!,
      }],
    }],
  } as unknown as AgencyArtifact;
}

Deno.test("評審：看得到大頭照（照片裡的人是她）與這一場的認識管道；舊 artifact 寫沒有記錄", () => {
  const [c] = buildJudgeCases(artifactWith("street_approach"));
  assertEquals(c.acquaintanceOrigin?.label, origin("street_approach").label);
  const prompt = buildJudgePrompt(c);
  assert(prompt.includes("她的大頭照（照片裡的人是她，男生看得到）："));
  assert(prompt.includes("晚上在便利商店門口拍的自拍"));
  assert(prompt.includes(origin("street_approach").sharedFact));
  assert(prompt.includes("認識當天的其他細節系統沒有給"));
  for (
    const label of [
      "meeting_day_quiz",
      "fabricated_meeting_detail",
      "photo_subject_flip",
      "photo_fact_ack",
    ]
  ) {
    assert(prompt.includes(`- ${label}：`), label);
  }

  const [old] = buildJudgeCases(artifactWith(undefined));
  assertEquals(old.acquaintanceOrigin, null);
  assert(buildJudgePrompt(old).includes("她和男生怎麼認識的：（沒有記錄）"));
  assertThrows(
    () => buildJudgeCases(artifactWith("no_such_origin")),
    Error,
    "agency_judge_unknown_origin",
  );
});

// ── 指標 ────────────────────────────────────────────────────────────────

const NONE = Object.fromEntries(
  JUDGED_LABELS.map((l) => [l, false]),
) as RawAgencyLabels;

function judged(probeId: string, ...labels: string[]): JudgedProbe {
  const spec = AGENCY_PROBES.find((p) => p.id === probeId)!;
  return {
    probeId,
    scenarioId: spec.scenarioId,
    profileId: "practice_girl_036",
    difficulty: "normal",
    mode: "game",
    repeat: 1,
    kinds: spec.kinds,
    labels: {
      ...NONE,
      ...Object.fromEntries(labels.map((l) => [l, true])),
    } as RawAgencyLabels,
  };
}

Deno.test("指標：考題率、主詞錯置率、自編當天細節率、照片講對承認率的分母各自正確", () => {
  const m = evaluateAgency([
    judged("A34.p1", "meeting_day_quiz", "photo_subject_flip"),
    judged("A34.p2"),
    judged("A38.p1", "fabricated_meeting_detail"),
    judged("A35.p1", "photo_subject_flip"),
    judged("A35.p2"),
    judged("A36-036.p1", "photo_fact_ack"),
    judged("A36-023.p1"),
    // 不在這組分母裡的探針即使有標也不算。
    judged("A01.p1", "meeting_day_quiz", "photo_fact_ack"),
  ]);
  // 考題：A34.p1、A34.p2（meeting_recall）＋A38.p1（meeting_detail_challenge）。
  assertEquals([m.meetingDayQuizRate.hits, m.meetingDayQuizRate.n], [1, 3]);
  // 主詞：A35.p1、A35.p2（photo_*）＋A34.p1、A34.p2（meeting_recall）。
  assertEquals([m.photoSubjectFlipRate.hits, m.photoSubjectFlipRate.n], [2, 4]);
  // 自編當天細節：上面兩組的聯集（五個探針）。
  assertEquals(
    [m.fabricatedMeetingDetailRate.hits, m.fabricatedMeetingDetailRate.n],
    [1, 5],
  );
  assertEquals([m.photoFactAckRate.hits, m.photoFactAckRate.n], [1, 2]);
});

Deno.test("wilsonUpper95：樣本少時的保守上界；n＝0 回 null", () => {
  assertEquals(wilsonUpper95(0, 0), null);
  assertAlmostEquals(wilsonUpper95(0, 20)!, 0.1611, 1e-3);
  assertAlmostEquals(wilsonUpper95(1, 100)!, 0.0545, 1e-3);
  assertAlmostEquals(wilsonUpper95(10, 10)!, 1, 1e-12);
});
