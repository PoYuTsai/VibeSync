// conversation-agency-v1 Phase 4.0 自測：分人強弱資料表 ＋ 四個 consumer。
//
// 契約：mapping 完整（100 位都解析得到、20 位代表角色逐位人工定值、14 個 preset
// 都有一筆）、四個欄位各自有分佈（不全部擠在中性值）、位移過的門檻永遠合法，
// 以及每個 consumer 在門檻兩側各一個正例／反例。旗標 off／shadow 不吃 profile
// 的證明在 `agency_flag_off_equivalence_test.ts`（逐位元組）與本檔最後一支
// （planner 的 `initiative` 只在 `agency.enabled` 時套用）。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  AGENCY_BY_PRESET,
  AGENCY_BY_PROFILE_ID,
  agencyProfileFor,
  NEUTRAL_AGENCY_PROFILE,
} from "./agency_profile.ts";
import {
  AGENCY_THRESHOLDS,
  agencyPolicyFor,
  agencyThresholdsFor,
  type ConversationAgencyProfile,
  detectAgencyEvidence,
} from "./conversation_agency.ts";
import {
  classifySituation,
  computeAgencyDecision,
  detectTurnSignals,
  planTurnResponse,
  type PolicyEvidence,
  policyStanceFor,
} from "./turn_response_plan.ts";
import { PRESET_IDS, STYLE_BY_PROFILE_ID } from "./reply_style.ts";
import type { PracticeTurn } from "./validate.ts";
import type { AgencyMode } from "./conversation_agency.ts";

const u = (text: string): PracticeTurn => ({ role: "user", text });
const a = (text: string): PracticeTurn => ({ role: "ai", text });
const PROFILE_IDS = Object.keys(STYLE_BY_PROFILE_ID);
const LEVELS = [
  "initiative",
  "topicPersistence",
  "ambiguityTolerance",
  "skepticism",
] as const;
const level = (p: ConversationAgencyProfile, k: typeof LEVELS[number]) => p[k];
const profileWith = (
  over: Partial<ConversationAgencyProfile>,
): ConversationAgencyProfile => ({ ...NEUTRAL_AGENCY_PROFILE, ...over });

const evidence = (over: Partial<PolicyEvidence> = {}): PolicyEvidence => ({
  practiceMode: "standard",
  difficulty: "normal",
  partnerMood: null,
  inviteStage: null,
  gameRepairPriority: false,
  gameRealityFlagCount: 0,
  gameInviteDirection: null,
  gameGreasy: false,
  hasMemorySummary: false,
  priorDecline: false,
  userOverEscalated: false,
  recentActs: [],
  ...over,
});

// ── mapping 完整性與分佈 ────────────────────────────────────────────────

Deno.test("100 位角色都解析得到四個 0–4 的整數", () => {
  assertEquals(PROFILE_IDS.length, 100);
  for (const id of PROFILE_IDS) {
    const p = agencyProfileFor(id);
    for (const key of LEVELS) {
      const v = level(p, key);
      assert(
        Number.isInteger(v) && v >= 0 && v <= 4,
        `${id}.${key}=${v} 不在 0–4`,
      );
    }
  }
});

Deno.test("前 20 位代表角色逐位人工定值；14 個 preset 都有 preset 級預設", () => {
  const overrides = Object.keys(AGENCY_BY_PROFILE_ID);
  assertEquals(overrides.length, 20);
  for (const id of overrides) {
    assert(id in STYLE_BY_PROFILE_ID, `${id} 不在 STYLE_BY_PROFILE_ID`);
    assertEquals(agencyProfileFor(id), AGENCY_BY_PROFILE_ID[id]);
  }
  assertEquals(Object.keys(AGENCY_BY_PRESET).length, PRESET_IDS.length);
  for (const presetId of PRESET_IDS) {
    assert(presetId in AGENCY_BY_PRESET, `${presetId} 沒有 agency 預設`);
  }
});

Deno.test("其餘 80 位走 preset 預設；查不到的 id 回中性值", () => {
  const fallbacks = PROFILE_IDS.filter((id) => !(id in AGENCY_BY_PROFILE_ID));
  assertEquals(fallbacks.length, 80);
  for (const id of fallbacks) {
    assertEquals(
      agencyProfileFor(id),
      AGENCY_BY_PRESET[
        STYLE_BY_PROFILE_ID[id].presetId as keyof typeof AGENCY_BY_PRESET
      ],
    );
  }
  assertEquals(agencyProfileFor("practice_girl_999"), NEUTRAL_AGENCY_PROFILE);
  assertEquals(agencyProfileFor(""), NEUTRAL_AGENCY_PROFILE);
});

Deno.test("四個欄位在 14 個 preset 裡各自涵蓋 0–1／2／3–4 三個區段", () => {
  const presets = Object.values(AGENCY_BY_PRESET);
  for (const key of LEVELS) {
    const vs = presets.map((p) => level(p, key));
    assert(vs.some((v) => v <= 1), `${key} 沒有 0–1 的 preset`);
    assert(vs.some((v) => v === 2), `${key} 沒有 2 的 preset`);
    assert(vs.some((v) => v >= 3), `${key} 沒有 3–4 的 preset`);
  }
});

Deno.test("20 位代表角色也不是全部貼在中性值（每個欄位都有兩側）", () => {
  const picks = Object.values(AGENCY_BY_PROFILE_ID);
  for (const key of LEVELS) {
    const vs = picks.map((p) => level(p, key));
    assert(vs.some((v) => v <= 1), `${key} 沒有低值角色`);
    assert(vs.some((v) => v >= 3), `${key} 沒有高值角色`);
  }
});

// ── 位移過的門檻仍然合法（3 難度 × 2 isGame × 100 位）──────────────────

Deno.test("3 難度 × 2 isGame × 100 位：holdAt ∈ [1,3]、firstFragmentActs 非空、一般／挑戰的欠債輪沒有無條件接住", () => {
  let cases = 0;
  for (const difficulty of ["easy", "normal", "challenge"] as const) {
    for (const isGame of [false, true]) {
      for (const id of PROFILE_IDS) {
        const t = agencyThresholdsFor(difficulty, isGame, agencyProfileFor(id));
        const where = `${difficulty}/${isGame}/${id}`;
        assert(t.holdAt >= 1 && t.holdAt <= 3, `${where} holdAt=${t.holdAt}`);
        assert(t.firstFragmentActs.length > 0, `${where} firstFragmentActs 空`);
        if (difficulty !== "easy" || isGame) {
          assert(
            !t.debtAnswerActs.includes("acknowledge"),
            `${where} 欠債輪出現無條件 acknowledge`,
          );
        }
        assert(t.debtAnswerActs.length > 0, `${where} debtAnswerActs 空`);
        cases++;
      }
    }
  }
  assertEquals(cases, 600);
});

Deno.test("省略 profile＝逐字沿用難度表（off 路徑不受本 Phase 影響）", () => {
  for (const difficulty of ["easy", "normal", "challenge"] as const) {
    assertEquals(
      agencyThresholdsFor(difficulty, false),
      AGENCY_THRESHOLDS[difficulty],
    );
    assertEquals(
      agencyThresholdsFor(difficulty, false, null),
      AGENCY_THRESHOLDS[difficulty],
    );
    assertEquals(
      agencyThresholdsFor(difficulty, true, null),
      AGENCY_THRESHOLDS.challenge,
    );
  }
});

// ── consumer 1：ambiguityTolerance → firstFragmentActs ──────────────────

const BARE_FRAGMENT = [u("阿布達比")];

Deno.test("consumer ambiguityTolerance：≤1 的角色第一個裸片段變 forced ask_intent；≥2 沿用難度表的 bounded", () => {
  for (const tol of [0, 1] as const) {
    const d = agencyPolicyFor(
      detectAgencyEvidence(BARE_FRAGMENT),
      agencyThresholdsFor(
        "normal",
        false,
        profileWith({ ambiguityTolerance: tol }),
      ),
    );
    assertEquals(d.situation, "ambiguous_fragment");
    assertEquals(d.policyMode, "forced");
    assertEquals(d.forcedAct, "ask_intent");
    assertEquals(d.allowedActs, ["ask_intent"]);
  }
  for (const tol of [2, 3, 4] as const) {
    const d = agencyPolicyFor(
      detectAgencyEvidence(BARE_FRAGMENT),
      agencyThresholdsFor(
        "normal",
        false,
        profileWith({ ambiguityTolerance: tol }),
      ),
    );
    assertEquals(d.policyMode, "bounded");
    assertEquals(d.allowedActs, ["acknowledge", "ask_intent"]);
  }
});

Deno.test("consumer ambiguityTolerance：不動有效短答的免疫（她剛問完、他答了、沒有欠債）", () => {
  const d = agencyPolicyFor(
    detectAgencyEvidence([a("你喜歡哪種動物"), u("貓")]),
    agencyThresholdsFor(
      "normal",
      false,
      profileWith({ ambiguityTolerance: 0 }),
    ),
  );
  assertEquals(d.situation, null);
  assertEquals(d.allowedActs, []);
});

// ── consumer 2：skepticism → holdAt ─────────────────────────────────────

Deno.test("consumer skepticism：≥3 早一步、≤1 晚一步、2 沿用；上下界 1–3，forceEndLoopBeforeChallenge 仍由難度決定", () => {
  const at = (
    skepticism: 0 | 1 | 2 | 3 | 4,
    difficulty: "easy" | "normal" | "challenge",
  ) => agencyThresholdsFor(difficulty, false, profileWith({ skepticism }));
  // normal base=2
  assertEquals(at(3, "normal").holdAt, 1);
  assertEquals(at(4, "normal").holdAt, 1);
  assertEquals(at(2, "normal").holdAt, 2);
  assertEquals(at(1, "normal").holdAt, 3);
  assertEquals(at(0, "normal").holdAt, 3);
  // easy base=3：低懷疑不會超過上界 3
  assertEquals(at(0, "easy").holdAt, 3);
  assertEquals(at(4, "easy").holdAt, 2);
  // challenge base=1：高懷疑不會低於下界 1
  assertEquals(at(4, "challenge").holdAt, 1);
  assertEquals(at(0, "challenge").holdAt, 2);
  // 收尾方式仍然只由難度決定
  assertEquals(at(4, "normal").forceEndLoopBeforeChallenge, false);
  assertEquals(at(0, "challenge").forceEndLoopBeforeChallenge, true);
});

Deno.test("consumer skepticism：高懷疑的人在同一段逐字稿提早 hold，低懷疑的人還在 bounded", () => {
  // 她問過一次，他連丟兩個不相干的詞 → 欠債 2。
  const turns = [u("東東"), a("東東是誰？"), u("阿布達比"), u("釜山")];
  const ev = detectAgencyEvidence(turns);
  const high = agencyPolicyFor(
    ev,
    agencyThresholdsFor("normal", false, profileWith({ skepticism: 4 })),
  );
  const low = agencyPolicyFor(
    ev,
    agencyThresholdsFor("normal", false, profileWith({ skepticism: 0 })),
  );
  assertEquals(high.policyMode, "forced");
  assertEquals(high.forcedAct, "hold_position");
  assertEquals(low.policyMode, "bounded");
});

// ── consumer 3：topicPersistence → debtAnswerActs ───────────────────────

const FRAGMENT_DEBT = [u("東東"), a("東東是誰"), u("阿布達比")];

Deno.test("consumer topicPersistence：≥3 的欠債輪多一個 return_to_topic 並換成 persist 的 set id；≤2 沿用", () => {
  for (const persistence of [3, 4] as const) {
    const d = agencyPolicyFor(
      detectAgencyEvidence(FRAGMENT_DEBT),
      agencyThresholdsFor(
        "normal",
        false,
        profileWith({ topicPersistence: persistence, skepticism: 2 }),
      ),
    );
    assertEquals(d.policyMode, "bounded");
    assertEquals(d.allowedActs, [
      "accept_if_answered",
      "challenge_relevance",
      "return_to_topic",
    ]);
    assertEquals(d.allowedActSetId, "answer_or_challenge_persist_v1");
    const easy = agencyPolicyFor(
      detectAgencyEvidence(FRAGMENT_DEBT),
      agencyThresholdsFor(
        "easy",
        false,
        profileWith({ topicPersistence: persistence, skepticism: 2 }),
      ),
    );
    assertEquals(easy.allowedActSetId, "answer_or_challenge_persist_easy_v1");
  }
  for (const persistence of [0, 1, 2] as const) {
    const d = agencyPolicyFor(
      detectAgencyEvidence(FRAGMENT_DEBT),
      agencyThresholdsFor(
        "normal",
        false,
        profileWith({ topicPersistence: persistence, skepticism: 2 }),
      ),
    );
    assertEquals(d.allowedActs, ["accept_if_answered", "challenge_relevance"]);
    assertEquals(d.allowedActSetId, "answer_or_challenge_v1");
  }
});

// ── consumer 4：initiative → planTurnResponse.optionalAct ───────────────

const NEUTRAL_TURNS = [
  u("嗨嗨 終於有空跟妳聊"),
  a("嗨 我也剛忙完"),
  u("今天超熱的 我剛下班"),
];
const SEED_KEYS = Array.from({ length: 20 }, (_, i) => `p40|seed${i}`);
const agencyFor = (
  turns: PracticeTurn[],
  ev: PolicyEvidence,
  mode: AgencyMode,
) => {
  const signals = detectTurnSignals(turns);
  return computeAgencyDecision({
    turns,
    situation: classifySituation(signals, policyStanceFor(signals, ev)),
    agencyMode: mode,
    difficulty: ev.difficulty,
  });
};
const disclosureCount = (
  initiative: 0 | 1 | 2 | 3 | 4,
  mode: AgencyMode,
  turns: PracticeTurn[] = NEUTRAL_TURNS,
) => {
  const ev = evidence();
  const style = STYLE_BY_PROFILE_ID["practice_girl_001"];
  return SEED_KEYS.filter((seedKey) =>
    planTurnResponse({
      turns,
      style,
      evidence: ev,
      seedKey,
      agency: agencyFor(turns, ev, mode),
      agencyProfile: mode === "on" ? profileWith({ initiative }) : null,
    }).optionalAct === "self_disclose"
  ).length;
};

Deno.test("consumer initiative：≥3 在停滯的 neutral 輪有機率自己開題，機率隨等級升高；≤2 一次都不會", () => {
  const four = disclosureCount(4, "on");
  const three = disclosureCount(3, "on");
  assert(four > 0 && four < SEED_KEYS.length, `initiative 4 命中 ${four}/20`);
  assert(three > 0 && three < four, `initiative 3=${three}、4=${four}`);
  assertEquals(disclosureCount(2, "on"), 0);
  assertEquals(disclosureCount(1, "on"), 0);
  assertEquals(disclosureCount(0, "on"), 0);
});

Deno.test("consumer initiative：agency off／shadow／沒帶 profile 時 plan 逐字不變", () => {
  const ev = evidence();
  const style = STYLE_BY_PROFILE_ID["practice_girl_001"];
  const highInitiative = profileWith({ initiative: 4 });
  for (const seedKey of SEED_KEYS) {
    const baseline = planTurnResponse({
      turns: NEUTRAL_TURNS,
      style,
      evidence: ev,
      seedKey,
      agency: agencyFor(NEUTRAL_TURNS, ev, "on"),
    });
    for (const mode of ["off", "shadow"] as const) {
      assertEquals(
        planTurnResponse({
          turns: NEUTRAL_TURNS,
          style,
          evidence: ev,
          seedKey,
          agency: agencyFor(NEUTRAL_TURNS, ev, mode),
          agencyProfile: highInitiative,
        }),
        planTurnResponse({
          turns: NEUTRAL_TURNS,
          style,
          evidence: ev,
          seedKey,
          agency: agencyFor(NEUTRAL_TURNS, ev, mode),
        }),
        `${mode}/${seedKey}`,
      );
    }
    // agency on 但沒帶 profile：與接線前逐字相同。
    assertEquals(
      planTurnResponse({
        turns: NEUTRAL_TURNS,
        style,
        evidence: ev,
        seedKey,
        agency: agencyFor(NEUTRAL_TURNS, ev, "on"),
        agencyProfile: null,
      }),
      baseline,
      seedKey,
    );
  }
});

Deno.test("consumer initiative：不搶玩家在問她的輪次、第一個回合、她在防備的輪次", () => {
  const guarded = evidence({ partnerMood: "guarded" });
  const style = STYLE_BY_PROFILE_ID["practice_girl_001"];
  const heAsks = [u("嗨嗨"), a("嗨"), u("妳那張照片是在哪拍的？")];
  const firstTurn = [u("嗨嗨")];
  for (const turns of [heAsks, firstTurn]) {
    assertEquals(disclosureCount(4, "on", turns), 0, turns.at(-1)!.text);
  }
  for (const seedKey of SEED_KEYS) {
    assertEquals(
      planTurnResponse({
        turns: NEUTRAL_TURNS,
        style,
        evidence: guarded,
        seedKey,
        agency: agencyFor(NEUTRAL_TURNS, guarded, "on"),
        agencyProfile: profileWith({ initiative: 4 }),
      }).optionalAct,
      planTurnResponse({
        turns: NEUTRAL_TURNS,
        style,
        evidence: guarded,
        seedKey,
        agency: agencyFor(NEUTRAL_TURNS, guarded, "on"),
      }).optionalAct,
      `cautious/${seedKey}`,
    );
  }
});
