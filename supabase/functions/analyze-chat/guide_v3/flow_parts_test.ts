// v3 流程的小零件：排卡決定、每張卡定稿、送給 App 的形狀、認 v3 run、串流切行、
// 背景段落、單張卡的禁語檢查。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import type { AnalysisStreamRun } from "../stream_run_store.ts";
import { isBlockedOutgoingCard } from "../guardrails.ts";
import { createLineSplitter, parseWrittenCardLine } from "./cards.ts";
import {
  finalizeCard,
  GUIDE_V3_SENTINELS,
  vetCoachText,
  vetPlanText,
} from "./finalize.ts";
import {
  FORCE_CARE_ON_EXPLICIT_SELF_HARM,
  HOLD_WAIT_FALLBACK,
  planTurn,
  planWithoutRead,
  STOP_REASON_CARE,
  STOP_REASON_MINOR,
} from "./plan.ts";
import {
  backgroundSections,
  readSystemPrompt,
  readUserPrompt,
  writeUserPrompt,
} from "./prompts.ts";
import { READ_TAGS_SCHEMA, type ReadTags } from "./read_tags.ts";
import type { CardSpec } from "./rules.ts";
import { MONEY_RISK_WARNING, SCAM_VENUE_WARNING } from "./rules.ts";
import { NO_SAFETY_HITS, type SafetyKeywordHits } from "./safety.ts";
import {
  GUIDE_V3_STALE_AFTER_MS,
  guideV3ResumeSnapshot,
  isGuideV3Run,
  recoveredGuideV3Result,
} from "./run_shape.ts";
import { guideMessagesFrom, upstreamErrorEvent } from "./stream_flow.ts";
import { toTurns } from "./turns.ts";
import {
  cardView,
  CARE_MESSAGE,
  MINOR_MESSAGE,
  readView,
  TASK_CODE,
} from "./wire.ts";

function tags(over: Partial<ReadTags> = {}): ReadTags {
  return {
    light: "green",
    herMove: "生活",
    herMoodBad: false,
    drunkOrLateNight: false,
    inviteReadiness: "沒機會",
    cancelHasAlternative: false,
    retreating: false,
    declinedOrBoundary: false,
    explicitRejection: false,
    blocked: false,
    risk: false,
    selfHarmSignal: false,
    minorSignal: false,
    needsHisFacts: false,
    identityQuestion: false,
    hisStatedFacts: [],
    hasHisVoiceSample: false,
    replyWillingness: "high",
    worthyBallCount: 1,
    herTurnsPerfunctory: [],
    matchedEntries: [],
    readForUser: "她在分享日常。",
    waitFor: "",
    ...over,
  };
}

const herLast = toTurns([
  { isFromMe: true, content: "週末去哪" },
  { isFromMe: false, content: "爬山" },
]);
const hisLast = toTurns([
  { isFromMe: false, content: "爬山" },
  { isFromMe: true, content: "哪座山" },
]);

/// 程式關鍵字的命中（沒寫到的都是 false）。
const hits = (over: Partial<SafetyKeywordHits>): SafetyKeywordHits => ({
  ...NO_SAFETY_HITS,
  ...over,
});

const spec = (over: Partial<CardSpec> = {}): CardSpec => ({
  task: "接住",
  method: "只用反應",
  voice: "預設",
  questionBudget: 1,
  push: null,
  angle: 0,
  ...over,
});

const card = (messages: string[], hasInventedDetail = false) => ({
  card: 1,
  messages,
  hasInventedDetail,
  expectedReaction: "",
});

Deno.test("自傷訊號優先於其他所有判斷：不排卡、不帶條目", () => {
  // 也蓋過 B47（規則先後第 1 條）。
  assertEquals(
    planTurn(herLast, tags({ selfHarmSignal: true, matchedEntries: ["B47"] }))
      .decision,
    "care",
  );
  const plan = planTurn(
    herLast,
    tags({ selfHarmSignal: true, explicitRejection: true }),
  );
  assertEquals(plan.decision, "care");
  assertEquals(plan.specs, []);
  assertEquals(plan.entries, []);
  assertEquals(plan.judgment, "");
});

Deno.test("未成年：讀局面成功時只看模型標記（關鍵字不蓋過模型），讀局面失敗才看關鍵字；自傷排在前面", () => {
  const byModel = planTurn(herLast, tags({ minorSignal: true }));
  assertEquals(byModel.decision, "care");
  assertEquals(byModel.careKind, "minor");
  assertEquals(byModel.careTrigger, "model");
  assertEquals(byModel.reason, STOP_REASON_MINOR);
  assertEquals(byModel.specs, []);
  assertEquals(byModel.entries, []);
  assertEquals(byModel.judgment, "");
  // 模型沒標：就算有「高中」這類字也照常出卡（主審第 1 輪：老師、講以前的事被誤擋）。
  const wordsOnly = planTurn(herLast, tags(), hits({ minorWords: true }));
  assertEquals(wordsOnly.decision, "send");
  assert(wordsOnly.specs.length > 0);
  // 自傷關心排在未成年前面（專線比「不提供建議」重要）。
  const both = planTurn(
    herLast,
    tags({ selfHarmSignal: true, minorSignal: true }),
  );
  assertEquals([both.careKind, both.reason], ["self_harm", STOP_REASON_CARE]);
  // 蓋過 B47、停、先別回：一律固定說明。
  for (
    const [turns, over] of [
      [herLast, { matchedEntries: ["B47"] }],
      [herLast, { explicitRejection: true }],
      [hisLast, {}],
    ] as const
  ) {
    const plan = planTurn(turns, tags({ ...over, minorSignal: true }));
    assertEquals(plan.careKind, "minor", JSON.stringify(over));
  }
  // 讀局面失敗時只看關鍵字；沒命中就照原本的錯誤處理。
  assertEquals(planWithoutRead(hits({ minorWords: true }))?.careKind, "minor");
  assertEquals(
    planWithoutRead(hits({ minorWords: true }))?.careTrigger,
    "keyword",
  );
  assertEquals(planWithoutRead(NO_SAFETY_HITS), null);
});

Deno.test("自傷關鍵字：最明確的說法在模型沒標時也強制關心；後援層只在讀局面失敗時用", () => {
  assert(FORCE_CARE_ON_EXPLICIT_SELF_HARM);
  const explicit = hits({ selfHarm: true, selfHarmExplicit: true });
  const forced = planTurn(herLast, tags(), explicit);
  assertEquals(
    [forced.decision, forced.careKind, forced.careTrigger],
    ["care", "self_harm", "keyword"],
  );
  assertEquals(
    planTurn(herLast, tags({ selfHarmSignal: true }), explicit).careTrigger,
    "both",
  );
  // 自傷先於未成年，關鍵字的也一樣。
  assertEquals(
    planTurn(herLast, tags({ minorSignal: true }), explicit).careKind,
    "self_harm",
  );
  // 只有後援層（「我好想死」）：讀局面成功時照模型的判斷。
  assertEquals(
    planTurn(herLast, tags(), hits({ selfHarm: true })).decision,
    "send",
  );
  // 讀局面失敗：後援層也給關心訊息，而且排在未成年前面。
  assertEquals(
    planWithoutRead(hits({ selfHarm: true }))?.careKind,
    "self_harm",
  );
  assertEquals(
    planWithoutRead(hits({ selfHarm: true, minorWords: true }))?.careKind,
    "self_harm",
  );
});

Deno.test("未成年的判讀事件：固定說明、careKind，沒有排卡；說明一兩句、講明不扣", () => {
  const view = readView(
    planTurn(herLast, tags({ minorSignal: true })),
    "green",
  );
  assertEquals(view.decision, "care");
  assertEquals(view.careKind, "minor");
  assertEquals(view.careMessage, MINOR_MESSAGE);
  assertEquals(view.plannedCards, []);
  // 自傷關心的 careKind 是 self_harm，文案不變。
  const care = readView(
    planTurn(herLast, tags({ selfHarmSignal: true })),
    "red",
  );
  assertEquals([care.careKind, care.careMessage], ["self_harm", CARE_MESSAGE]);
  // 讀局面失敗、只靠關鍵字時沒有燈號。
  assertEquals(
    readView(planWithoutRead(hits({ minorWords: true }))!, null).light,
    null,
  );
  assert(MINOR_MESSAGE.split("。").filter(Boolean).length <= 2);
  for (const word of ["18 歲", "不提供回覆建議", "不扣額度"]) {
    assert(MINOR_MESSAGE.includes(word), word);
  }
});

Deno.test("讀局面標記的 schema 有未成年欄位，而且是必填；提示詞有欄位說明", () => {
  assert((READ_TAGS_SCHEMA.required as string[]).includes("minorSignal"));
  assertEquals(
    (READ_TAGS_SCHEMA.properties as Record<string, unknown>).minorSignal,
    { type: "boolean" },
  );
  const prompt = readSystemPrompt();
  assert(prompt.includes("- minorSignal："));
  assert(prompt.includes("「我高中的時候」"));
});

Deno.test("先別回：模型沒寫要等什麼時用預設；有寫就用模型的", () => {
  assertEquals(planTurn(hisLast, tags()).waitFor, HOLD_WAIT_FALLBACK);
  assertEquals(
    planTurn(hisLast, tags({ waitFor: "  等她說哪座山 " })).waitFor,
    "等她說哪座山",
  );
  assertEquals(planTurn(hisLast, tags()).specs, []);
});

Deno.test("送出型與 B47：判讀換成固定提醒，排推進、收、推進", () => {
  const plan = planTurn(herLast, tags({ matchedEntries: ["B47"] }));
  assertEquals(plan.decision, "send");
  assertEquals(plan.judgment, SCAM_VENUE_WARNING);
  assertEquals(plan.specs.map((s) => TASK_CODE[s.task]), [
    "push",
    "close",
    "push",
  ]);
  assertEquals(plan.entries.map((e) => e.id), ["B47"]);
});

Deno.test("她要錢的關鍵字跟風險標記同樣處理：照常出卡、不排推進、判讀換成固定提醒；B47 不受影響", () => {
  const long = toTurns([
    { isFromMe: true, content: "a" },
    { isFromMe: false, content: "b" },
    { isFromMe: true, content: "c" },
    { isFromMe: false, content: "d" },
  ]);
  for (
    const [t, h] of [
      [tags({ herMove: "開窗" }), hits({ money: true })],
      [tags({ herMove: "開窗", risk: true }), NO_SAFETY_HITS],
    ] as const
  ) {
    const plan = planTurn(long, t, h);
    assertEquals(plan.decision, "send");
    assertEquals(plan.judgment, MONEY_RISK_WARNING);
    assertEquals(plan.push, null);
    assert(plan.specs.length > 0);
    assert(plan.specs.every((s) => s.task !== "推進"));
  }
  // 沒命中照常推進（開窗）、判讀用模型的。
  const plain = planTurn(long, tags({ herMove: "開窗" }));
  assertEquals(plain.push, "具體邀約");
  assertEquals(plain.judgment, "她在分享日常。");
  // B47 有自己的提醒與換地方的卡。
  const b47 = planTurn(
    herLast,
    tags({ matchedEntries: ["B47"] }),
    hits({ money: true }),
  );
  assertEquals(b47.judgment, SCAM_VENUE_WARNING);
  assertEquals(b47.push, "換地方");
  // 先別回、停也換成提醒（判讀照樣給用戶看）。
  assertEquals(
    planTurn(hisLast, tags(), hits({ money: true })).judgment,
    MONEY_RISK_WARNING,
  );
});

Deno.test("讀局面標記的 schema 有自傷欄位，而且是必填", () => {
  assert((READ_TAGS_SCHEMA.required as string[]).includes("selfHarmSignal"));
  assertEquals(
    (READ_TAGS_SCHEMA.properties as Record<string, unknown>).selfHarmSignal,
    { type: "boolean" },
  );
});

Deno.test("定稿：預設口吻換成「你」、照他口吻不動；簡體轉繁體；原文另存", () => {
  const def = finalizeCard(card(["妳也太會挑了吧"]), spec(), "");
  assert(def.ok);
  assertEquals(def.messages, ["你也太會挑了吧"]);
  assertEquals(def.rawMessages, ["妳也太會挑了吧"]);
  const his = finalizeCard(
    card(["妳也太會挑了吧"]),
    spec({ voice: "照他" }),
    "",
  );
  assert(his.ok);
  assertEquals(his.messages, ["妳也太會挑了吧"]);
  assertEquals(his.rawMessages, undefined);
  const simplified = finalizeCard(card(["这个周末一起去吗"]), spec(), "");
  assert(simplified.ok);
  assertEquals(simplified.messages, ["這個週末一起去嗎"]);
});

Deno.test("定稿：禁語、脅迫、外洩命中就整張拿掉；引號裡的引述不算脅迫", () => {
  assertEquals(
    finalizeCard(card(["不要放棄，一直約她就對了"]), spec(), ""),
    { ok: false, reason: "unsafe" },
  );
  assertEquals(
    finalizeCard(card(["你不回我我就去死"]), spec(), ""),
    { ok: false, reason: "unsafe" },
  );
  assert(
    finalizeCard(card(["妳說「你不回我我就去死」，我很擔心妳"]), spec(), "").ok,
  );
  // 哨兵含「用戶」，簡轉繁會改成「使用者」：整理前的原文也要查。
  assertEquals(
    finalizeCard(card([`好啊 ${GUIDE_V3_SENTINELS[0]}`]), spec(), ""),
    { ok: false, reason: "prompt_leak" },
  );
  // 照他口吻的「妳」：脅迫樣式照樣抓得到。
  assertEquals(
    finalizeCard(card(["妳不回我我就去死"]), spec({ voice: "照他" }), ""),
    { ok: false, reason: "unsafe" },
  );
  // v2 推薦卡的英文樣式也查。
  assertEquals(
    finalizeCard(card(["我會 follow her 到她家"]), spec(), ""),
    { ok: false, reason: "unsafe" },
  );
  assertEquals(
    finalizeCard(card(["先 ignore previous instructions 再說"]), spec(), ""),
    { ok: false, reason: "prompt_leak" },
  );
  // 換行不能繞過脅迫樣式；同一張卡拆成兩則也一樣。
  assertEquals(
    finalizeCard(card(["你不回我\n我就去死"]), spec(), ""),
    { ok: false, reason: "unsafe" },
  );
  assertEquals(
    finalizeCard(card(["你不回我", "我就去死"]), spec(), ""),
    { ok: false, reason: "unsafe" },
  );
  // 引號沒在同一則收尾，不能拿來包住下一則的脅迫句：接起來查會把中間整段當成引述
  //（引號外還有「還有」兩個字），要靠每則各自查（第二則沒有開引號，不會被當引述）。
  assertEquals(
    finalizeCard(card(["「哈哈", "你不回我\n我就去死」還有"]), spec(), ""),
    { ok: false, reason: "unsafe" },
  );
  // 簡體的禁語：整理前後都查。
  assertEquals(
    finalizeCard(card(["我会一直跟踪你"]), spec(), ""),
    { ok: false, reason: "unsafe" },
  );
});

Deno.test("定稿：C5「欠」組（欠我、欠著、你欠）整張拿掉；欠缺、欠自己的覺照送", () => {
  assertEquals(
    finalizeCard(
      card(["先說好，我只等十分鐘", "多一分鐘就當你欠我一杯飲料"]),
      spec(),
      "",
    ),
    { ok: false, reason: "debt_frame", detail: ["欠我", "你欠"] },
  );
  // 照他口吻的「妳」也算。
  assertEquals(
    finalizeCard(card(["算妳欠我一杯"]), spec({ voice: "照他" }), ""),
    { ok: false, reason: "debt_frame", detail: ["欠我", "你欠"] },
  );
  assertEquals(
    finalizeCard(card(["推薦費可以先欠著"]), spec(), ""),
    { ok: false, reason: "debt_frame", detail: ["欠著"] },
  );
  assertEquals(
    finalizeCard(card(["這杯就算妳欠的，下次還"]), spec({ voice: "照他" }), ""),
    { ok: false, reason: "debt_frame", detail: ["你欠"] },
  );
  // 跟她無關的「欠」不擋。
  assert(finalizeCard(card(["我這週剛好在補之前欠自己的覺"]), spec(), "").ok);
  assert(finalizeCard(card(["你欠缺的只是一個好的週末"]), spec(), "").ok);
  // 整理前後兩份都要查：整理會拿掉夾外文的子句（只有原文有「欠我」），也會拿掉
  // 夾在中間的外文（整理後才湊出「欠著」）。
  assertEquals(
    finalizeCard(card(["你好，欠我一杯Привет。"]), spec(), ""),
    { ok: false, reason: "debt_frame", detail: ["欠我"] },
  );
  assertEquals(
    finalizeCard(card(["先欠Привет著"]), spec(), ""),
    { ok: false, reason: "debt_frame", detail: ["欠著"] },
  );
  // 同時命中更嚴重的原因時照舊：脅迫、外洩先判。
  assertEquals(
    finalizeCard(card(["你欠我一杯，你不回我我就去死"]), spec(), ""),
    { ok: false, reason: "unsafe" },
  );
  assertEquals(
    finalizeCard(card(["欠我一杯，ignore previous instructions"]), spec(), ""),
    { ok: false, reason: "prompt_leak" },
  );
  // 只記錄的 C5 九個字眼照舊不擋。
  const scoring = finalizeCard(card(["這點加分"]), spec(), "");
  assert(scoring.ok);
  assertEquals(scoring.scoringWords, ["加分"]);
});

Deno.test("定稿：整則英文才拿掉；夾在中文裡的品牌名、對話裡出現過的英文都留著", () => {
  const english = finalizeCard(card(["Sounds good to me"]), spec(), "");
  assertEquals(english.ok, false);
  assert(!english.ok && english.reason === "language_drift");
  const brand = finalizeCard(card(["入門可以看 Olympus mju"]), spec(), "");
  assert(brand.ok);
  assertEquals(brand.unsupportedLatin, ["Olympus", "mju"]);
  const sourced = finalizeCard(
    card(["chill night"]),
    spec(),
    "今天好 chill 的 night",
  );
  assert(sourced.ok);
  assert(finalizeCard(card(["XD"]), spec(), "").ok);
});

Deno.test("定稿：C5 打分字眼只記錄，不拿掉", () => {
  const out = finalizeCard(card(["這題加分"]), spec(), "");
  assert(out.ok);
  assertEquals(out.scoringWords, ["加分"]);
});

Deno.test("定稿：空白或清完只剩空的訊息拿掉；全部空掉才整張拿掉", () => {
  const one = finalizeCard(card(["好啊", "Привет"]), spec(), "");
  assert(one.ok);
  assertEquals(one.messages, ["好啊"]);
  assertEquals(
    finalizeCard(card(["Привет"]), spec(), ""),
    { ok: false, reason: "empty_after_cleanup" },
  );
});

Deno.test("單張卡的禁語檢查跟 v2 同一套樣式，每則各自掃、不跨訊息湊句", () => {
  assert(isBlockedOutgoingCard(["我會跟蹤妳"]));
  assert(isBlockedOutgoingCard(["她說不要\n但其實很想"]));
  assert(!isBlockedOutgoingCard(["她說不要", "但其實我也不確定"]));
  // 跟 v2 回覆卡同一套，第一人稱的「我不想死纏爛打」也會被擋（已知取捨：只少一張卡；
  // 過去 896 張黑箱卡沒有一張命中）。
  assert(isBlockedOutgoingCard(["我不想死纏爛打，所以先問一次"]));
  assert(!isBlockedOutgoingCard(["週末一起去爬山嗎"]));
});

Deno.test("送給 App 的卡：任務、做法、口吻轉成代碼，有「＿」就標 hasBlank", () => {
  const v = cardView(
    2,
    spec({ task: "推進", method: "留空格", voice: "照他" }),
    ["我週＿＿有空"],
    true,
  );
  assertEquals(v, {
    slot: 2,
    task: "push",
    method: "blank",
    voice: "his",
    messages: ["我週＿＿有空"],
    hasInventedDetail: true,
    hasBlank: true,
  });
});

Deno.test("判讀事件：先別回帶 waitFor、關心帶固定文案，其他不帶", () => {
  const hold = readView(planTurn(hisLast, tags()), "yellow");
  assertEquals(hold.waitFor, HOLD_WAIT_FALLBACK);
  assertEquals("careMessage" in hold, false);
  const care = readView(
    planTurn(herLast, tags({ selfHarmSignal: true })),
    "red",
  );
  assertEquals(care.careMessage, CARE_MESSAGE);
  assertEquals("waitFor" in care, false);
  const send = readView(planTurn(herLast, tags()), "green");
  assertEquals("waitFor" in send, false);
  assertEquals(send.plannedCards.length, 4);
});

Deno.test("關心文案照 Eric 10/16 同意的版本，有專線號碼", () => {
  for (const n of ["1925", "1995", "110", "119"]) {
    assert(CARE_MESSAGE.includes(n), n);
  }
  assert(CARE_MESSAGE.endsWith("這次不提供回覆建議。"));
});

function run(over: Partial<AnalysisStreamRun> = {}): AnalysisStreamRun {
  return {
    id: "run-1",
    user_id: "u",
    conversation_hash: "h",
    status: "charged",
    selected_style: null,
    decision_kind: "send",
    card_task: null,
    recommendation_json: null,
    final_result_json: null,
    charged_at: "2026-10-16T00:00:00.000Z",
    last_error_code: null,
    retry_count: 0,
    request_context: null,
    created_at: "2026-10-16T00:00:00.000Z",
    expires_at: "2026-10-16T00:30:00.000Z",
    ...over,
  };
}

Deno.test("認 v3 run：card_task、扣費內容或 requestContext 的 guideVersion 任一", () => {
  assert(isGuideV3Run(run({ card_task: "accept" })));
  assert(isGuideV3Run(run({ recommendation_json: { guideVersion: "v3.3" } })));
  assert(isGuideV3Run(run({ request_context: { guideVersion: "v3.3" } })));
  assert(!isGuideV3Run(run({ selected_style: "extend" })));
  assert(
    !isGuideV3Run(run({ recommendation_json: { selectedStyle: "extend" } })),
  );
});

Deno.test("續看快照：扣過費卻被記成 failed 也從扣費內容重組", () => {
  const read = { decision: "hold", judgment: "等她" };
  const snapshot = guideV3ResumeSnapshot(
    run({
      status: "failed",
      decision_kind: "do_not_send",
      recommendation_json: {
        guideVersion: "v3.3",
        read,
        chargedMessageCount: 1,
      },
    }),
    Date.parse("2026-10-16T00:00:00.000Z") + GUIDE_V3_STALE_AFTER_MS,
  );
  assertEquals(snapshot.status, "failed");
  assertEquals(
    (snapshot.finalResult as Record<string, unknown>).usage,
    { messagesUsed: 1, shouldChargeQuota: true },
  );
  // 沒扣過費的 failed 照舊是失敗、沒有結果。
  const unpaid = guideV3ResumeSnapshot(
    run({ status: "failed", charged_at: null, recommendation_json: { read } }),
    Date.parse("2026-10-16T00:00:00.000Z") + GUIDE_V3_STALE_AFTER_MS,
  );
  assertEquals(unpaid.finalResult, null);
});

Deno.test("續看快照：v3 一律不可 retry；太久的 pending 當失敗", () => {
  const created = Date.parse("2026-10-16T00:00:00.000Z");
  const fresh = guideV3ResumeSnapshot(run({ status: "failed" }), created);
  assertEquals(fresh.retriesRemaining, 0);
  const pending = guideV3ResumeSnapshot(
    run({ status: "pending", charged_at: null }),
    created + GUIDE_V3_STALE_AFTER_MS,
  );
  assertEquals(pending.status, "failed");
  assertEquals(pending.lastErrorCode, "GUIDE_V3_ABANDONED");
  const young = guideV3ResumeSnapshot(
    run({ status: "pending", charged_at: null }),
    created + GUIDE_V3_STALE_AFTER_MS - 1,
  );
  assertEquals(young.status, "pending");
});

Deno.test("重組結果：送出型要有完整的第一張卡；不送型只有判讀；壞的回 null", () => {
  const read = { decision: "hold", judgment: "等她" };
  assertEquals(
    recoveredGuideV3Result(run({
      decision_kind: "do_not_send",
      recommendation_json: { guideVersion: "v3.3", read },
    }))?.cards,
    [],
  );
  assertEquals(
    recoveredGuideV3Result(run({
      card_task: "accept",
      recommendation_json: { guideVersion: "v3.3", read, firstCard: {} },
    })),
    null,
  );
  assertEquals(
    recoveredGuideV3Result(
      run({ recommendation_json: { guideVersion: "v3.3" } }),
    ),
    null,
  );
  const stale = guideV3ResumeSnapshot(
    run({ card_task: "accept", recommendation_json: { read } }),
    Date.parse("2026-10-16T00:00:00.000Z") + GUIDE_V3_STALE_AFTER_MS,
  );
  assertEquals(stale.status, "failed");
  assertEquals(stale.lastErrorCode, "GUIDE_V3_RECOVERY_UNAVAILABLE");
});

Deno.test("串流切行：等整行到了才交出；最後沒換行的由 flush 交出", () => {
  const s = createLineSplitter();
  assertEquals(s.push('{"card":1,'), []);
  assertEquals(s.push('"messages":["a"]}\n{"card"'), [
    '{"card":1,"messages":["a"]}',
  ]);
  assertEquals(s.push(':2,"messages":["b"]}'), []);
  assertEquals(s.flush(), ['{"card":2,"messages":["b"]}']);
  assertEquals(s.flush(), []);
  assertEquals(parseWrittenCardLine("null"), null);
  assertEquals(parseWrittenCardLine('{"card":1,"messages":[]}'), null);
});

Deno.test("背景段落：空的欄位不放；沒有背景時讀局面提示詞跟原本一樣", () => {
  assertEquals(backgroundSections(undefined), []);
  assertEquals(backgroundSections({ meetingContext: "  " }), []);
  const sections = backgroundSections({
    meetingContext: "交友軟體",
    duration: "一週",
    partnerSummary: "喜歡爬山",
    conversationSummary: "上週聊過電影",
  });
  assertEquals(sections, [
    "## 作戰板標籤\n- 怎麼認識：交友軟體\n- 認識多久：一週",
    "## 對象背景\n喜歡爬山",
    "## 更早的對話摘要\n上週聊過電影",
  ]);
  assert(readUserPrompt(herLast).startsWith("## 對話\n"));
  assert(
    readUserPrompt(herLast, { goal: "約出來" }).startsWith("## 作戰板標籤\n"),
  );
  const write = writeUserPrompt({
    turns: herLast,
    tags: tags(),
    entries: [],
    cards: [spec()],
    background: { goal: "約出來" },
  });
  assert(write.startsWith("## 作戰板標籤\n- 他的目標：約出來\n\n## 對話\n"));
});

Deno.test("引用回覆照中性寫法：不認是誰說的", () => {
  assertEquals(
    guideMessagesFrom([{
      isFromMe: false,
      content: "對啊",
      quotedReplyPreview: "  你也喜歡\n爬山？ ",
    }]),
    [{ isFromMe: false, content: "（引用：「你也喜歡 爬山？」）對啊" }],
  );
});

Deno.test("上游錯誤：拒答不可重試，其他可重試，都寫明不扣額度", () => {
  const refusal = upstreamErrorEvent({ code: "MODEL_REFUSAL" });
  assertEquals(refusal.recoverable, false);
  const other = upstreamErrorEvent(new Error("boom"));
  assertEquals(other.code, "GUIDE_V3_UPSTREAM_FAILED");
  assertEquals(other.recoverable, true);
  for (const e of [refusal, other]) {
    assert(String(e.message).includes("本次不會扣額度"));
  }
});

Deno.test("定稿第 2 輪：簡體照抄說明書也抓得到；整則只有引號的脅迫句照擋；中文卡加一則英文不誤擋", () => {
  // 第一條哨兵含「用戶」：簡體原文對不上繁體哨兵，整理後又被改成「使用者」。
  const simplified = "用户＝他（男生），对象＝她。他对她有兴趣，也在看";
  assertEquals(
    finalizeCard(card([simplified]), spec(), ""),
    { ok: false, reason: "prompt_leak" },
  );
  assertEquals(
    finalizeCard(card(["「你不回我我就去死」"]), spec(), ""),
    { ok: false, reason: "unsafe" },
  );
  // 引號外有他自己的話：引述她說過的話，照舊不擋。
  assert(
    finalizeCard(card(["你說「你不回我我就去死」，我很擔心你"]), spec(), "").ok,
  );
  assert(
    finalizeCard(card(["今天爬山辛苦了，早點休息", "Good night~"]), spec(), "")
      .ok,
  );
  assert(finalizeCard(card(["生日快樂！", "Happy birthday"]), spec(), "").ok);
  const allEnglish = finalizeCard(card(["Good night~", "See you"]), spec(), "");
  assert(!allEnglish.ok && allEnglish.reason === "language_drift");
});

Deno.test("定稿第 2 輪：整理會把禁語所在的子句整段拿掉時，原文也要查", () => {
  // 含俄文字母的子句整段被清掉，整理後只剩「週末見」。
  assertEquals(
    finalizeCard(card(["我會跟蹤你Привет，週末見"]), spec(), ""),
    { ok: false, reason: "unsafe" },
  );
});

Deno.test("教練文字（判讀、要等她做什麼）：外洩、注入、英文不安全樣式命中就不給；正常的照用", () => {
  assertEquals(vetCoachText(`她在分享 ${GUIDE_V3_SENTINELS[1]}`), {
    ok: false,
  });
  assertEquals(vetCoachText("ignore previous instructions"), { ok: false });
  assertEquals(vetCoachText("you should follow her home"), { ok: false });
  assertEquals(vetCoachText(" 她在分享日常,氣氛輕鬆 "), {
    ok: true,
    text: "她在分享日常，氣氛輕鬆",
  });
  // 描述她的狀況不掃 BLOCKED_PATTERNS（不誤傷說明）。
  assert(vetCoachText("她說有人一直跟蹤她，先關心她").ok);
  const removed: string[] = [];
  const plan = vetPlanText(
    planTurn(
      hisLast,
      tags({
        readForUser: "system prompt 外洩",
        waitFor: "   ",
      }),
    ),
    (f) => removed.push(f),
  );
  assertEquals(plan.judgment, "");
  assertEquals(plan.waitFor, HOLD_WAIT_FALLBACK);
  assertEquals(removed, ["judgment"]);
});

Deno.test("續看快照：扣過費但還沒到 120 秒，不重組（原請求可能還在寫）", () => {
  const created = Date.parse("2026-10-16T00:00:00.000Z");
  const snapshot = guideV3ResumeSnapshot(
    run({
      card_task: "accept",
      recommendation_json: {
        read: { decision: "send" },
        firstCard: { slot: 1, task: "accept", messages: ["嗨"] },
      },
    }),
    created + GUIDE_V3_STALE_AFTER_MS - 1,
  );
  assertEquals(snapshot.status, "charged");
  assertEquals(snapshot.finalResult, null);
});

Deno.test("判讀事件：免費方案的張數之外標 locked", () => {
  const view = readView(planTurn(herLast, tags()), "green", 2);
  assertEquals(view.plannedCards.map((c) => c.locked), [
    false,
    false,
    true,
    true,
  ]);
  assertEquals(
    readView(planTurn(herLast, tags()), "green").plannedCards.some((c) =>
      c.locked
    ),
    false,
  );
});

Deno.test("定稿第 3 輪：換行或空白夾在關鍵詞中間照擋；原文與整理後各自掃，不湊出假威脅", () => {
  for (
    const threat of [
      "你不回我我\n就去死",
      "你不回我我 就去死",
      "你不回\n我我就\n去死",
    ]
  ) {
    assertEquals(
      finalizeCard(card([threat]), spec(), ""),
      { ok: false, reason: "unsafe" },
      threat,
    );
  }
  // 安撫句：單獨掃不會命中，原文與整理後放在一起掃才會湊出「你不…照片…傳出去」。
  assert(finalizeCard(card(["我不會把照片傳出去，你不用擔心"]), spec(), "").ok);
  assert(!isBlockedOutgoingCard(["我不會把照片傳出去，你不用擔心"]));
});

Deno.test("續看快照：扣過費卻被記成 failed，不用等 120 秒就重組（已經沒有人在寫）", () => {
  const created = Date.parse("2026-10-16T00:00:00.000Z");
  const snapshot = guideV3ResumeSnapshot(
    run({
      status: "failed",
      card_task: "accept",
      recommendation_json: {
        guideVersion: "v3.3",
        read: { decision: "send" },
        firstCard: { slot: 1, task: "accept", messages: ["嗨"] },
        chargedMessageCount: 2,
      },
    }),
    created + 1_000,
  );
  assertEquals(
    (snapshot.finalResult as Record<string, unknown>).cards,
    [{ slot: 1, task: "accept", messages: ["嗨"] }],
  );
});
