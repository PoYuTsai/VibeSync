// v3 流程的小零件：排卡決定、每張卡定稿、送給 App 的形狀、認 v3 run、串流切行、
// 背景段落、單張卡的禁語檢查。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import type { AnalysisStreamRun } from "../stream_run_store.ts";
import { isBlockedOutgoingCard } from "../guardrails.ts";
import { createLineSplitter, parseWrittenCardLine } from "./cards.ts";
import { finalizeCard, GUIDE_V3_SENTINELS } from "./finalize.ts";
import { HOLD_WAIT_FALLBACK, planTurn } from "./plan.ts";
import {
  backgroundSections,
  readUserPrompt,
  writeUserPrompt,
} from "./prompts.ts";
import { READ_TAGS_SCHEMA, type ReadTags } from "./read_tags.ts";
import type { CardSpec } from "./rules.ts";
import { SCAM_VENUE_WARNING } from "./rules.ts";
import {
  GUIDE_V3_STALE_AFTER_MS,
  guideV3ResumeSnapshot,
  isGuideV3Run,
  recoveredGuideV3Result,
} from "./run_shape.ts";
import { guideMessagesFrom, upstreamErrorEvent } from "./stream_flow.ts";
import { toTurns } from "./turns.ts";
import { cardView, CARE_MESSAGE, readView, TASK_CODE } from "./wire.ts";

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
  const plan = planTurn(
    herLast,
    tags({ selfHarmSignal: true, explicitRejection: true }),
  );
  assertEquals(plan.decision, "care");
  assertEquals(plan.specs, []);
  assertEquals(plan.entries, []);
  assertEquals(plan.judgment, "");
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
  // 簡體的禁語：整理前後都查。
  assertEquals(
    finalizeCard(card(["我会一直跟踪你"]), spec(), ""),
    { ok: false, reason: "unsafe" },
  );
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
