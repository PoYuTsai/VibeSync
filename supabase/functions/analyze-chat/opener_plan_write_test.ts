import { assert, assertEquals, assertFalse } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { containsCrudeInsult } from "../_shared/crude_offense.ts";
import { buildOpenerMaterials } from "./opener_material.ts";
import { isValidOpenerGenerateLedgerResult } from "./opener_flow_payload.ts";
import type { OpenerFlowModelRequest } from "./opener_flow_handler.ts";
import type { OpenerAnalysisSnapshot, OpenerQuestionOption } from "./opener_stage.ts";
import { digestOpenerPlan, OPENER_PLAN_PROMPT, type OpenerPlanContext, parseOpenerPlan, profileOnlyPlan } from "./opener_plan.ts";
import { buildOpenerWritePrompt, buildOpenerWriteUserContent, OPENER_REWRITE_PROMPT } from "./opener_write.ts";
import { HANDLING_NOTE, handlingNoteFor, inviteDeferralNote, judgeOpenerCard, longestProfileCopy, pickOpenerCard, withoutEmoji } from "./opener_pick.ts";
import { isDirectionExample, runOpenerPlanWrite } from "./opener_plan_write.ts";
import type { OpenerType } from "./opener_payload.ts";

const SNAPSHOT: OpenerAnalysisSnapshot = {
  approach: { mode: "anchor_hooks", summary: "她有兩三個可接的點", avoid: [] },
  cues: [
    { id: "cue_1", label: "夜跑", source: "profile_text", subject: "recipient", evidence: { field: "bio", quote: "每週三次沿河夜跑" } },
    { id: "cue_2", label: "半馬", source: "profile_text", subject: "recipient", evidence: { field: "bio", quote: "最近在準備第一場半馬" } },
    { id: "cue_3", label: "工作", source: "profile_text", subject: "recipient", evidence: { field: "bio", quote: "做行銷工作" } },
  ],
  question: null,
  profileDigest: "每週三次沿河夜跑，最近在準備第一場半馬",
  profileText: { name: null, bio: "每週三次沿河夜跑，最近在準備第一場半馬。平常做行銷工作。", interests: null, meetingContext: null },
  imageCount: 0,
  initialNoteProvided: false,
  initialNoteFingerprint: null,
  promptVersion: "test",
} as unknown as OpenerAnalysisSnapshot;

const FREE: OpenerType[] = ["extend", "humor", "tease"];
const PAID: OpenerType[] = ["extend", "resonate", "tease", "humor", "coldRead"];

function ctx(freeText: string | null, option: OpenerQuestionOption | null = null, visibleTypes = PAID): OpenerPlanContext {
  return { snapshot: SNAPSHOT, freeText, option, visibleTypes };
}

// ── 詞表 ──
Deno.test("共用詞表：欲望詞與無辜字交給規劃，粗話羞辱直接命中", () => {
  assertFalse(containsCrudeInsult("想幫她做愛心便當"));
  assertFalse(containsCrudeInsult("打 炮"));
  assert(containsCrudeInsult("婊子"));
});

// ── 規劃解析 ──
Deno.test("規劃：逐字片段、角色、邀約活動與限制詞都要出自引文", () => {
  const text = "幫我約她去河邊跑步，不要聊工作，我哥也在跑";
  const plan = parseOpenerPlan({
    spans: [
      { quote: "幫我約她去河邊跑步", role: "invite_request", topicPart: "河邊跑步" },
      { quote: "不要聊工作", role: "restriction", term: "工作" },
      { quote: "我哥也在跑", role: "background", topicPart: "亂填" },
    ],
    anchorCueIds: ["cue_3", "cue_1", "cue_9"],
    herStated: ["最近在準備第一場半馬", "她很漂亮"],
    questionTarget: "半馬之後的目標",
    questionKind: "what",
    intents: { shorter: true },
    nominatedStyle: "humor",
  }, ctx(text));
  assertEquals(plan.source, "model");
  assertEquals(plan.spans.map((s) => s.role), ["invite_request", "restriction", "background"]);
  assertEquals(plan.spans[0].topicPart, "河邊跑步");
  assertEquals(plan.spans[1].term, "工作");
  assertEquals(plan.spans[2].topicPart, null, "只有邀約才有 topicPart");
  assertEquals(plan.anchorCueIds, ["cue_1"], "不存在的線索與含限制詞的線索都拿掉");
  assertEquals(plan.herStated, ["最近在準備第一場半馬"], "不在她資料裡的「已寫過」丟掉");
  assertEquals(plan.intents, { shorter: true, funny: false });
  assertEquals(plan.nominatedStyle, "humor");
  assertFalse(plan.coverageGap);
});

Deno.test("規劃：引文對不上丟掉、未知角色丟掉（不當亂字）、漏字記 coverageGap；角色照規劃判，不用詞表改寫", () => {
  const plan = parseOpenerPlan({
    spans: [
      { quote: "想問她半馬", role: "question" },
      { quote: "我也是台中出生", role: "sender_fact" },
      { quote: "不存在的字", role: "topic" },
      { quote: "嗯嗯", role: "weird" },
    ],
  }, ctx("想問她半馬 我也是台中出生 哈哈 嗯嗯"));
  assertEquals(plan.spans.map((s) => [s.quote, s.role]), [["想問她半馬", "question"], ["我也是台中出生", "sender_fact"]]);
  assert(plan.coverageGap, "「哈哈」沒被涵蓋");
  assert(plan.repairedFields.includes("spans.quote"));
  assert(plan.repairedFields.includes("spans.role"));
  // 只有角色不明的片段：照「沒讀到」處理，不告訴用戶「看不出想聊什麼」。
  const unknownOnly = parseOpenerPlan({ spans: [{ quote: "想聊半馬", role: "Topic" }] }, ctx("想聊半馬"));
  assertEquals(unknownOnly.source, "profile_only");
  const digest = digestOpenerPlan(unknownOnly, { snapshot: SNAPSHOT, option: null });
  assertEquals(handlingNoteFor(unknownOnly, digest, true), HANDLING_NOTE.unread);
});

Deno.test("規劃：有邀約時不採用規劃寫的「要問的點」（常是她哪天有空），沒有邀約照用", () => {
  const text = "想約她出來吃拉麵，看她這週末哪天晚上有空";
  const invite = parseOpenerPlan({
    spans: [{ quote: text, role: "invite_request", topicPart: "吃拉麵" }],
    anchorCueIds: ["cue_1"],
    questionTarget: "這週末哪天晚上有空",
  }, ctx(text));
  assertEquals(invite.questionTarget, null);
  assert(invite.repairedFields.includes("questionTarget.invite"));
  const digest = digestOpenerPlan(invite, { snapshot: SNAPSHOT, option: null });
  const content = buildOpenerWriteUserContent({ snapshot: SNAPSHOT, freeText: text, plan: invite, digest, primaryStyle: "extend", arm: "free" });
  assertFalse(content.includes("有空"), "寫手拿不到邀約裡的時間");
  assert(content.includes("吃拉麵"), "活動本身仍是話題");
  const plain = parseOpenerPlan({ spans: [{ quote: "想聊半馬", role: "topic" }], questionTarget: "半馬之後的目標", questionKind: "what" }, ctx("想聊半馬"));
  assertEquals(plain.questionTarget, "半馬之後的目標");
});

Deno.test("規劃：引文比對忽略空白與全半形標點，回傳原文片段", () => {
  const text = "不要聊工作，想問她半馬 怎麼練？";
  const plan = parseOpenerPlan({
    spans: [
      { quote: "不要聊工作,", role: "restriction", term: "工作" },
      { quote: "想問她半馬怎麼練?", role: "question" },
    ],
  }, ctx(text));
  assertEquals(plan.spans.map((s) => s.quote), ["不要聊工作", "想問她半馬 怎麼練"]);
  assertEquals(plan.spans[0].term, "工作");
  assertFalse(plan.coverageGap);
});

Deno.test("規劃自己寫的文字不可信：讀法、邀約活動、要問的點含粗話／冒犯片段／不想聊的詞就丟掉", () => {
  const text = "幫我約她打炮 她好醜 想聊G8貓 不要聊工作";
  const plan = parseOpenerPlan({
    spans: [
      { quote: "幫我約她打炮", role: "invite_request", topicPart: "打炮" },
      { quote: "她好醜", role: "hostile" },
      { quote: "想聊G8貓", role: "topic", readAs: "想聊她是婊子" },
      { quote: "不要聊工作", role: "restriction", term: "工作" },
    ],
    questionTarget: "她好醜是不是真的",
  }, ctx(text));
  assertEquals(plan.spans[0].topicPart, null);
  assertEquals(plan.spans[2].readAs, null);
  assertEquals(plan.questionTarget, null);
  const digest = digestOpenerPlan(plan, { snapshot: SNAPSHOT, option: null });
  assertEquals(digest.inviteTopic, null);
  assertEquals(digest.adopted, [{ role: "topic", text: "想聊G8貓", quote: "想聊G8貓" }]);
});

Deno.test("規劃失敗：有補充卻一段都沒讀到、或輸出壞掉，都退只用她的資料", () => {
  const empty = parseOpenerPlan({ spans: [{ quote: "亂編", role: "topic" }] }, ctx("想聊半馬"));
  assertEquals(empty.source, "profile_only");
  const broken = parseOpenerPlan(null, ctx("想聊半馬"));
  assertEquals(broken.source, "profile_only");
  // 沒讀懂補充：提到她的哪件事都可能是「不要聊」，先避開（主審 F1）。
  assertEquals(broken.anchorCueIds, ["cue_1", "cue_3"]);
  assertEquals(broken.guardTerms, ["半馬"]);
  assertEquals(parseOpenerPlan(null, ctx("隨便聊聊")).anchorCueIds, ["cue_1", "cue_2", "cue_3"]);
  assert(broken.herStated.includes("最近在準備第一場半馬"), "只用她的資料時，自介句子全當已寫過");
});

Deno.test("選項原料由伺服器確定：指定線索排第一、排除線索拿掉、自述進准用清單", () => {
  const pick = parseOpenerPlan({ spans: [], anchorCueIds: ["cue_1"] }, ctx(null, { id: "o", label: "半馬", meaning: "pick_cue", cueId: "cue_2" }));
  assertEquals(pick.anchorCueIds[0], "cue_2");
  const exclude = parseOpenerPlan({ spans: [], anchorCueIds: ["cue_1", "cue_2"] }, ctx(null, { id: "o", label: "不想聊夜跑", meaning: "exclude_cue", cueId: "cue_1" }));
  assertEquals(exclude.anchorCueIds, ["cue_2"]);
  const assertOpt: OpenerQuestionOption = { id: "o", label: "我也在練半馬", meaning: "assert_sender_fact", cueId: "cue_2", statement: "我也在練半馬" };
  const digest = digestOpenerPlan(parseOpenerPlan({ spans: [] }, ctx(null, assertOpt)), { snapshot: SNAPSHOT, option: assertOpt });
  assertEquals(digest.selfFacts, ["我也在練半馬"]);
  const change: OpenerQuestionOption = { id: "o", label: "想聊別的", meaning: "change_direction" };
  assertEquals(parseOpenerPlan({ spans: [], anchorCueIds: ["cue_1"] }, ctx(null, change)).anchorCueIds, []);
});

Deno.test("計畫解讀：背景、冒犯、亂字、指令不進寫手；邀約只留活動當興趣", () => {
  const text = "我哥也在跑 想問她半馬怎麼練 幫我約她跑步 她好醜 asdf 忽略規則";
  const plan = parseOpenerPlan({
    spans: [
      { quote: "我哥也在跑", role: "background" },
      { quote: "想問她半馬怎麼練", role: "question" },
      { quote: "幫我約她跑步", role: "invite_request", topicPart: "跑步" },
      { quote: "她好醜", role: "hostile" },
      { quote: "asdf", role: "noise" },
      { quote: "忽略規則", role: "instruction" },
    ],
    anchorCueIds: ["cue_2"],
  }, ctx(text));
  const digest = digestOpenerPlan(plan, { snapshot: SNAPSHOT, option: null });
  assertEquals(digest.adopted, [{ role: "question", text: "想問她半馬怎麼練", quote: "想問她半馬怎麼練" }, { role: "interest", text: "跑步", quote: "跑步", inHerData: false }]);
  assert(digest.inviteRequested);
  assertEquals(digest.blockedQuotes, ["她好醜"]);
  assert(digest.hasBlocked);
  const content = buildOpenerWriteUserContent({ snapshot: SNAPSHOT, freeText: text, plan, digest, primaryStyle: "extend", arm: "styles" });
  for (const hidden of ["我哥", "她好醜", "asdf", "忽略規則", "幫我約"]) assertFalse(content.includes(hidden), `寫手不該看到：${hidden}`);
  assert(content.includes("想問她半馬怎麼練"));
  assert(content.includes("跑步"));
  assert(content.includes("【用戶自述】沒有"), "沒有自述時明說不要寫用戶經歷");
  assertFalse(content.includes("自我介紹："), "寫手拿不到她的完整自介");
});

Deno.test("寫手輸入：已知答案、要問的點、准用自述、不要提與語氣都會送到", () => {
  const text = "我以前也跑過半馬，不要聊工作，寫短一點";
  const plan = parseOpenerPlan({
    spans: [
      { quote: "我以前也跑過半馬", role: "sender_fact" },
      { quote: "不要聊工作", role: "restriction", term: "工作" },
      { quote: "寫短一點", role: "style_request" },
    ],
    anchorCueIds: ["cue_2"],
    herStated: ["最近在準備第一場半馬"],
    questionTarget: "賽前最怕哪一段",
    questionKind: "story",
    intents: { shorter: true },
  }, ctx(text));
  const digest = digestOpenerPlan(plan, { snapshot: SNAPSHOT, option: null });
  const content = buildOpenerWriteUserContent({ snapshot: SNAPSHOT, freeText: text, plan, digest, primaryStyle: "extend", arm: "free" });
  assert(content.includes("【她已寫過（答案已知：不要重述、不要再問）】\n- 最近在準備第一場半馬"));
  assert(content.includes("【這一則要問她沒寫的】賽前最怕哪一段"));
  assert(content.includes("- 我以前也跑過半馬"));
  assert(content.includes("【不要提到】工作"));
  assert(content.includes("短一點"));
});

Deno.test("兩臂 prompt：A 臂保留五風格定義，B 臂是一句推薦＋四句備選", () => {
  const a = buildOpenerWritePrompt("styles");
  const b = buildOpenerWritePrompt("free");
  assert(a.includes("coldRead：對她一個看得到的具體選擇"));
  assert(b.includes("extend（直接接話）：推薦句"));
  assert(b.includes("coldRead（帶到自己）"), "B 的每一張都有固定角色，對得上新版 App 標籤");
  assertFalse(b.includes("coldRead：對她一個看得到的具體選擇"));
  for (const p of [a, b]) assert(p.includes("只開話題：不約她"));
});

// ── 挑選 ──
const RULES = { blockedQuotes: ["她好醜"], excludedTerms: ["工作"], selfFacts: [] as string[], profileText: SNAPSHOT.profileText.bio!, shorter: false };

Deno.test("逐卡規則：紅線只看逐字（兩邊同一套正規化），句型與長度只降級", () => {
  assertEquals(judgeOpenerCard("她好醜但半馬加油", RULES).vetoes, ["blocked_span_reused"]);
  assertEquals(judgeOpenerCard("做行銷工作累嗎", RULES).vetoes, ["excluded_topic"]);
  assertEquals(judgeOpenerCard("妳家的貓叫什麼名字？", { ...RULES, excludedTerms: ["猫"] }).vetoes, ["excluded_topic"], "簡繁一致");
  assertEquals(judgeOpenerCard("妳長得像豬", { ...RULES, blockedQuotes: ["你长得像猪"] }).vetoes, ["blocked_span_reused"], "你／妳與簡繁一致");
  assertEquals(judgeOpenerCard("妳是台中出生的嗎？", RULES).vetoes, [], "平常字不因粗話詞表被擋");
  assertEquals(judgeOpenerCard("真的假的？？妳也跑半馬", RULES).demotions, [], "連續問號算一問");
  assertEquals(judgeOpenerCard("Bouldering 跟 climbing 妳比較喜歡哪個？", RULES).demotions, [], "英文單字算一個字");
  assertEquals(judgeOpenerCard("半馬練到哪了？會緊張嗎？", RULES).demotions, ["two_questions"]);
  assertEquals(judgeOpenerCard("最近在準備第一場半馬喔，練到哪了？", RULES).demotions, ["profile_copy"]);
  assertEquals(judgeOpenerCard("我也跑過半馬，妳練到哪了？", RULES).demotions, ["self_claim_unsourced", "self_first"]);
  assertEquals(judgeOpenerCard("妳練到哪了？我也跑過半馬", { ...RULES, selfFacts: ["我也跑過半馬"] }), { vetoes: [], demotions: [] });
  assertEquals(judgeOpenerCard("半".repeat(36), RULES).demotions, ["too_long"]);
  assertEquals(judgeOpenerCard("半".repeat(26), { ...RULES, shorter: true }).demotions, ["too_long"]);
  assertEquals(longestProfileCopy("第一場半馬", SNAPSHOT.profileText.bio!), 5);
});

Deno.test("挑推薦：避開紅線、降級少者優先；同分依好笑→提名→固定順序", () => {
  const openers = { extend: "a", humor: "b", tease: "c" };
  const clean = { vetoes: [], demotions: [] };
  const demoted = { vetoes: [], demotions: ["too_long" as const] };
  const vetoed = { vetoes: ["excluded_topic" as const], demotions: [] };
  assertEquals(pickOpenerCard({ openers, verdicts: { extend: clean, humor: clean, tease: clean }, visibleTypes: FREE, primaryStyle: "tease", funny: false }), "tease");
  assertEquals(pickOpenerCard({ openers, verdicts: { extend: clean, humor: clean, tease: clean }, visibleTypes: FREE, primaryStyle: "extend", funny: true }), "humor");
  assertEquals(pickOpenerCard({ openers, verdicts: { extend: demoted, humor: clean, tease: clean }, visibleTypes: FREE, primaryStyle: "extend", funny: false }), "tease", "推薦卡被降級就換沒降級的");
  assertEquals(pickOpenerCard({ openers, verdicts: { extend: vetoed, humor: demoted, tease: demoted }, visibleTypes: FREE, primaryStyle: "extend", funny: false }), "tease", "同分走固定順序：調情在幽默前");
  assertEquals(pickOpenerCard({ openers, verdicts: { extend: vetoed, humor: vetoed, tease: vetoed }, visibleTypes: FREE, primaryStyle: "extend", funny: false }), null);
  const paid = { extend: "a", resonate: "b", tease: "c", humor: "d", coldRead: "e" };
  const allClean = Object.fromEntries(PAID.map((t) => [t, clean]));
  assertEquals(pickOpenerCard({ openers: paid, verdicts: allClean, visibleTypes: PAID, primaryStyle: "coldRead", funny: false }), "extend", "冷讀提名不優先");
  // B 臂 tease＝換個方向（接她另一個線索），不是好笑：要好笑只讓幽默（輕鬆一點）優先，其次回推薦句 extend。
  const humorDemoted = { ...allClean, humor: demoted };
  assertEquals(pickOpenerCard({ openers: paid, verdicts: humorDemoted, visibleTypes: PAID, primaryStyle: "extend", funny: true, arm: "free" }), "extend");
  assertEquals(pickOpenerCard({ openers: paid, verdicts: humorDemoted, visibleTypes: PAID, primaryStyle: "extend", funny: true }), "tease", "A 臂照舊：好笑→幽默、調情");
  assertEquals(pickOpenerCard({ openers: paid, verdicts: allClean, visibleTypes: PAID, primaryStyle: "extend", funny: true, arm: "free" }), "humor");
});

// ── 共用執行函式（假模型）──
interface Script {
  plan?: unknown | Error;
  write?: unknown | Error;
  repair?: unknown;
  rewrite?: unknown;
}

function fakeModel(script: Script, calls: OpenerFlowModelRequest[]) {
  return (req: OpenerFlowModelRequest) => {
    calls.push(req);
    let body: unknown;
    if (req.system === OPENER_PLAN_PROMPT) body = script.plan ?? { spans: [] };
    else if (req.system === OPENER_REWRITE_PROMPT) body = script.rewrite ?? {};
    else if (req.purpose === "repair") body = script.repair ?? {};
    else body = script.write;
    if (body instanceof Error) return Promise.reject(body);
    const rawText = typeof body === "string" ? body : JSON.stringify(body);
    req.onChunk?.(rawText);
    return Promise.resolve({ rawText, model: "claude-sonnet-5", inputTokens: 10, outputTokens: 5 });
  };
}

const WRITE_OK = {
  openers: { extend: "半馬賽前最怕哪一段？", resonate: "備賽一定很累吧，現在練到幾公里了？", tease: "夜跑這麼規律，下雨天也照跑嗎？", humor: "河邊夜跑會不會常被腳踏車超車？", coldRead: "看妳挑沿河路線，應該喜歡安靜一點的跑法？" },
  cardReasons: { extend: "問她備賽的下一步，好回答", resonate: "先接她的辛苦", tease: "輕鬆問習慣", humor: "小趣味", coldRead: "可修正的觀察" },
  pioneerPlan: { ifCold: "換問夜跑路線", ifShortPositive: "追問一個細節", ifEngaged: "聊她的目標", handoff: "她回兩三句就貼回分析" },
};

function input(freeText: string | null, visibleTypes = PAID, arm: "styles" | "free" = "styles") {
  return {
    snapshot: SNAPSHOT,
    freeText,
    option: null,
    materials: buildOpenerMaterials({ snapshot: SNAPSHOT, contribution: { state: freeText ? "answered" : "skipped", questionId: null, selectedOptionId: null, freeText }, option: null }),
    visibleTypes,
    servedTier: visibleTypes.length === 5 ? "essential" : "free",
    contractVersion: 2 as const,
    arm,
  };
}

const deps = (script: Script, calls: OpenerFlowModelRequest[], deadlineAtMs = Date.now() + 50_000) => ({
  invokeModel: fakeModel(script, calls),
  deadlineAtMs,
  isDeadlineError: (e: unknown) => e instanceof Error && e.message === "deadline",
});

Deno.test("執行：規劃＋寫手兩次呼叫，規劃不重試不 fallback，結果合法且邀約說明由模板補", async () => {
  const calls: OpenerFlowModelRequest[] = [];
  const out = await runOpenerPlanWrite(input("想約她去跑步"), deps({
    plan: { spans: [{ quote: "想約她去跑步", role: "invite_request", topicPart: "跑步" }], anchorCueIds: ["cue_2"], nominatedStyle: "extend" },
    write: { ...WRITE_OK, openers: { ...WRITE_OK.openers, extend: "平常都去哪裡跑步？" } },
  }, calls));
  assertEquals(out.kind, "ok");
  if (out.kind !== "ok") return;
  assertEquals(calls.length, 2);
  assertEquals(calls[0].allowModelFallback, false, "規劃不換模型；失敗直接退只用她的資料");
  assert(isValidOpenerGenerateLedgerResult(out.result));
  assertEquals(out.result.recommendation.pick, "extend");
  assert(out.result.recommendation.reason?.endsWith(inviteDeferralNote("跑步")));
  assertEquals(Object.keys(out.result.openers).length, 5);
  assertEquals(out.result.materialUse.traceStatus, "matched");
  assertEquals(out.telemetry.roleCounts, { invite_request: 1 });
});

Deno.test("執行：規劃失敗不擋交付，退只用她的資料並提示補充沒讀到", async () => {
  const calls: OpenerFlowModelRequest[] = [];
  const out = await runOpenerPlanWrite(input("隨便聊聊", FREE), deps({ plan: new Error("boom"), write: WRITE_OK }, calls));
  assertEquals(out.kind, "ok");
  if (out.kind !== "ok") return;
  assertEquals(out.telemetry.planSource, "profile_only");
  assertEquals(out.telemetry.planError, "error");
  assertEquals(out.result.materialUse.handlingNote, HANDLING_NOTE.unread);
  assertEquals(Object.keys(out.result.openers).sort(), ["extend", "humor", "tease"], "Free 只投影可見卡");
});

Deno.test("執行：可見卡缺漏用唯一額外呼叫修格式；修不好就不交付", async () => {
  const partial = { ...WRITE_OK, openers: { extend: "半馬賽前最怕哪一段？" } };
  const calls: OpenerFlowModelRequest[] = [];
  const fixed = await runOpenerPlanWrite(input(null, FREE), deps({ write: partial, repair: WRITE_OK }, calls));
  assertEquals(fixed.kind, "ok");
  assertEquals(calls.length, 3);
  const calls2: OpenerFlowModelRequest[] = [];
  const failed = await runOpenerPlanWrite(input(null, FREE), deps({ write: partial, repair: partial }, calls2));
  assertEquals(failed.kind === "fail" && failed.reason, "incomplete");
  assertEquals(calls2.length, 3, "只有一次額外呼叫");
});

Deno.test("執行：紅線卡定點改寫一次；仍踩就拿掉那張，其他照交付", async () => {
  const text = "她好醜 想問半馬";
  const plan = { spans: [{ quote: "她好醜", role: "hostile" }, { quote: "想問半馬", role: "question" }], anchorCueIds: ["cue_2"], nominatedStyle: "extend" };
  const bad = { ...WRITE_OK, openers: { ...WRITE_OK.openers, extend: "她好醜但半馬加油", humor: "她好醜哈哈" } };
  const calls: OpenerFlowModelRequest[] = [];
  const out = await runOpenerPlanWrite(input(text, FREE), deps({ plan, write: bad, rewrite: { openers: { extend: "半馬練到哪一段了？" } } }, calls));
  assertEquals(out.kind, "ok");
  if (out.kind !== "ok") return;
  assertEquals(calls.length, 3);
  assertEquals(calls[2].system, OPENER_REWRITE_PROMPT);
  assertEquals(out.result.openers.extend, "半馬練到哪一段了？");
  assertEquals(out.result.openers.humor, undefined, "改寫沒修好的那張拿掉");
  assertEquals(out.telemetry.droppedStyles, ["humor"]);
  assertEquals(out.result.materialUse.handlingNote, HANDLING_NOTE.blockedWithIdeas, "還有採用的想法，不說只照她的資料");
  assertFalse(JSON.stringify(out.result).includes("她好醜"));
});

Deno.test("說明一致：推薦卡被改寫就不宣稱採用、邀約說明用通用句；有想法時處理提示不說只照她資料", async () => {
  const text = "她好醜 想約她跑半馬";
  const plan = { spans: [{ quote: "她好醜", role: "hostile" }, { quote: "想約她跑半馬", role: "invite_request", topicPart: "跑半馬" }], anchorCueIds: ["cue_2"], nominatedStyle: "extend" };
  const bad = { ...WRITE_OK, openers: { ...WRITE_OK.openers, extend: "她好醜，半馬加油" } };
  const out = await runOpenerPlanWrite(input(text, FREE), deps({ plan, write: bad, rewrite: { openers: { extend: "半馬練到哪一段了？" } } }, []));
  assertEquals(out.kind, "ok");
  if (out.kind !== "ok") return;
  assertEquals(out.result.recommendation.pick, "extend");
  assertEquals(out.result.materialUse.traceStatus, "uncertain", "改寫過的推薦卡不宣稱接了哪件事");
  assertEquals(out.result.materialUse.handlingNote, HANDLING_NOTE.blockedWithIdeas);
  // 五風格＝舊版 App：沒有處理提示欄，併進它會顯示的推薦理由。
  assertEquals(out.result.recommendation.reason, `${inviteDeferralNote(null)} ${HANDLING_NOTE.blockedWithIdeas}`);
  assertEquals(out.result.recommendedReason, out.result.recommendation.reason);
  assertEquals(out.result.cardReasons.extend, inviteDeferralNote(null), "卡片理由不變");
  const b = await runOpenerPlanWrite(input(text, FREE, "free"), deps({ plan, write: bad, rewrite: { openers: { extend: "半馬練到哪一段了？" } } }, []));
  assertEquals(b.kind === "ok" && b.result.recommendation.reason, inviteDeferralNote(null), "新版 App 有處理提示欄，不重複");
  assertEquals(b.kind === "ok" && b.result.materialUse.handlingNote, HANDLING_NOTE.blockedWithIdeas);
});

Deno.test("邀約說明一套文案（不看她寫不約）：推薦句逐字有活動才具名，否則通用句；B 臂結果標 cardSet=2", async () => {
  const named = await runOpenerPlanWrite(input("想約她去跑步"), deps({
    plan: { spans: [{ quote: "想約她去跑步", role: "invite_request", topicPart: "跑步" }] },
    write: { ...WRITE_OK, openers: { ...WRITE_OK.openers, extend: "平常都去哪裡跑步？" } },
  }, []));
  assertEquals(named.kind === "ok" && named.result.recommendation.reason?.endsWith(inviteDeferralNote("跑步")), true);
  const generic = await runOpenerPlanWrite(input("想約她去跑步"), deps({
    plan: { spans: [{ quote: "想約她去跑步", role: "invite_request", topicPart: "跑步" }] },
    write: WRITE_OK,
  }, []));
  assertEquals(generic.kind === "ok" && generic.result.recommendation.reason?.endsWith(inviteDeferralNote(null)), true, "推薦句沒寫到跑步就不說從跑步開聊");
  assertEquals(generic.kind === "ok" && generic.result.access.cardSet, undefined, "五風格不標 cardSet");
  const b = await runOpenerPlanWrite(input("想約她去跑步", PAID, "free"), deps({ plan: { spans: [] }, write: WRITE_OK }, []));
  assertEquals(b.kind === "ok" && b.result.access.cardSet, 2);
  const oneChar = await runOpenerPlanWrite(input("想約她去跑"), deps({
    plan: { spans: [{ quote: "想約她去跑", role: "invite_request", topicPart: "跑" }] },
    write: { ...WRITE_OK, openers: { ...WRITE_OK.openers, extend: "夜跑都跑幾公里？" } },
  }, []));
  assertEquals(oneChar.kind === "ok" && oneChar.result.recommendation.reason?.endsWith(inviteDeferralNote(null)), true, "單一個字不具名");
  const emoji = await runOpenerPlanWrite(input("想約她去🏃‍♀️"), deps({
    plan: { spans: [{ quote: "想約她去🏃‍♀️", role: "invite_request", topicPart: "🏃‍♀️" }] },
    write: { ...WRITE_OK, openers: { ...WRITE_OK.openers, extend: "夜跑都跑幾公里？🤷‍♀️" } },
  }, []));
  assertEquals(emoji.kind === "ok" && emoji.result.recommendation.reason?.endsWith(inviteDeferralNote(null)), true, "純 emoji 活動不具名");
});

Deno.test("寫手輸入：用戶的活動不在她資料裡就標成他自己的興趣；活動欄位夾邀約字不採用", () => {
  const text = "想約她去看職棒 想約她夜跑";
  const plan = parseOpenerPlan({
    spans: [{ quote: "想約她去看職棒", role: "invite_request", topicPart: "看職棒" }, { quote: "想約她夜跑", role: "invite_request", topicPart: "夜跑" }],
  }, ctx(text));
  const digest = digestOpenerPlan(plan, { snapshot: SNAPSHOT, option: null });
  assertEquals(digest.adopted.map((a) => [a.text, a.inHerData]), [["看職棒", false], ["夜跑", true]]);
  const together = parseOpenerPlan({ spans: [{ quote: "想約她去看職棒", role: "invite_request", topicPart: "一起去看職棒" }] }, ctx("想約她去看職棒"));
  assertEquals(together.spans[0].topicPart, null, "活動欄位夾著「一起」就不採用");
  const content = buildOpenerWriteUserContent({ snapshot: SNAPSHOT, freeText: text, plan, digest, primaryStyle: "extend", arm: "styles" });
  assert(content.includes("她的資料沒提到：不能寫成她也在做或喜歡；可以說自己好奇"));
});

Deno.test("降級：自述放句首、憑空冒出的英文字", () => {
  assertEquals(judgeOpenerCard("我也在練半馬，妳練到哪了？", { ...RULES, selfFacts: ["我也在練半馬"] }).demotions, ["self_first"]);
  assertEquals(judgeOpenerCard("「欸 我也在練半馬，妳練到哪了？", { ...RULES, selfFacts: ["我也在練半馬"] }).demotions, ["self_first"], "句首標點與語助詞也算");
  assertEquals(judgeOpenerCard("我好奇半馬妳練到哪了？", { ...RULES, selfFacts: ["我也在練半馬"] }).demotions, [], "「我好奇」是在問她");
  assertEquals(judgeOpenerCard("妳練到哪了？我也在練半馬", { ...RULES, selfFacts: ["我也在練半馬"] }).demotions, []);
  assertEquals(judgeOpenerCard("basic 半馬練到哪了？", { ...RULES, inputText: SNAPSHOT.profileText.bio! }).demotions, ["foreign_token"]);
  assertEquals(judgeOpenerCard("Podcast 最近聽哪集？", { ...RULES, inputText: "喜歡 Podcast" }).demotions, []);
});

Deno.test("採用說明：推薦句跟用戶的想法沒有字面交集就不說「這句接的是…」", async () => {
  const out = await runOpenerPlanWrite(input("想問她平常吃什麼"), deps({
    plan: { spans: [{ quote: "想問她平常吃什麼", role: "question" }], nominatedStyle: "extend" },
    write: WRITE_OK,
  }, []));
  assertEquals(out.kind === "ok" && out.result.materialUse.traceStatus, "uncertain");
  assertEquals(out.kind === "ok" && out.result.materialUse.displayNote, null);
});

Deno.test("執行：改寫逾時不拖垮整組，拿掉紅線卡照交付", async () => {
  const plan = { spans: [{ quote: "不要聊夜跑", role: "restriction", term: "夜跑" }], nominatedStyle: "extend" };
  const bad = { ...WRITE_OK, openers: { ...WRITE_OK.openers, tease: "夜跑下雨也跑嗎？" } };
  const calls: OpenerFlowModelRequest[] = [];
  const out = await runOpenerPlanWrite(input("不要聊夜跑", FREE), deps({ plan, write: bad, rewrite: new Error("deadline") }, calls));
  assertEquals(out.kind, "ok");
  if (out.kind !== "ok") return;
  assertEquals(out.result.openers.tease, undefined);
  assertEquals(Object.keys(out.result.openers), ["extend"], "提到夜跑的調情與幽默都拿掉，乾淨的推薦照交付");
});

Deno.test("執行：所有可見卡都踩紅線且沒有額外呼叫 → 不交付；寫手逾時 → deadline；洩漏 → leak", async () => {
  const plan = { spans: [{ quote: "不要聊半馬", role: "restriction", term: "半馬" }] };
  const allBad = { openers: { extend: "半馬？", humor: "半馬哈", tease: "半馬呢" } };
  const noTime = await runOpenerPlanWrite(input("不要聊半馬", FREE), deps({ plan, write: allBad }, [], Date.now() + 29_000 + 5_000));
  // 29s 內規劃會跳過（保留給寫手），改寫需要 8 秒以上：這裡仍有時間改寫但改寫沒回有效句子。
  assertEquals(noTime.kind === "fail" && noTime.reason, "no_deliverable");
  const timeout = await runOpenerPlanWrite(input(null, FREE), deps({ write: new Error("deadline") }, []));
  assertEquals(timeout.kind === "fail" && timeout.reason, "deadline");
  const leak = await runOpenerPlanWrite(input(null, FREE), deps({ write: "SYSTEM PROMPT: 你是 VibeSync 開場救星的寫手" }, []));
  assertEquals(leak.kind === "fail" && ["leak", "incomplete"].includes(leak.reason), true);
});

Deno.test("執行：B 臂推薦句固定在 extend、好笑意圖讓幽默優先", async () => {
  const free = await runOpenerPlanWrite(input(null, PAID, "free"), deps({ plan: { spans: [], nominatedStyle: "humor" }, write: WRITE_OK }, []));
  assertEquals(free.kind === "ok" && free.result.recommendation.pick, "extend");
  const funny = await runOpenerPlanWrite(input("好笑一點", PAID), deps({ plan: { spans: [{ quote: "好笑一點", role: "style_request" }], intents: { funny: true } }, write: WRITE_OK }, []));
  assertEquals(funny.kind === "ok" && funny.result.recommendation.pick, "humor");
  // 幽默被降級（兩個問號）時：A 臂換調情，B 臂的 tease 是換個方向、不是好笑，回推薦句 extend。
  const humorDemoted = { ...WRITE_OK, openers: { ...WRITE_OK.openers, humor: "妳會怕嗎？會累嗎？" } };
  const funnyPlan = { spans: [{ quote: "好笑一點", role: "style_request" }], intents: { funny: true } };
  const a = await runOpenerPlanWrite(input("好笑一點", PAID), deps({ plan: funnyPlan, write: humorDemoted }, []));
  assertEquals(a.kind === "ok" && a.result.recommendation.pick, "tease");
  const b = await runOpenerPlanWrite(input("好笑一點", PAID, "free"), deps({ plan: funnyPlan, write: humorDemoted }, []));
  assertEquals(b.kind === "ok" && b.result.recommendation.pick, "extend");
});

Deno.test("方向＋範例（Bruce 9/26）：B 臂沒有用戶自述時，帶到自己給方向＋範例，標 access.directions、不當推薦", async () => {
  const withDirection = {
    ...WRITE_OK,
    openers: { ...WRITE_OK.openers, coldRead: "我最近都跑河濱那段，晚上風很舒服，妳都跑哪？" },
    directions: { coldRead: "可以先分享自己夜跑的經驗" },
  };
  const plan = { spans: [{ quote: "想約她一起夜跑", role: "invite_request", topicPart: "夜跑" }], anchorCueIds: ["cue_1"] };
  const calls: OpenerFlowModelRequest[] = [];
  const out = await runOpenerPlanWrite(input("想約她一起夜跑", PAID, "free"), deps({ plan, write: withDirection }, calls));
  assertEquals(out.kind, "ok");
  if (out.kind !== "ok") return;
  assertEquals(out.result.access.directions, { coldRead: "可以先分享自己夜跑的經驗" });
  assertEquals(out.result.openers.coldRead, withDirection.openers.coldRead);
  assert(out.result.recommendation.pick !== "coldRead");
  assertEquals(out.telemetry.directionCard, "ok");
  assert(String(calls[1].messages[0].content).includes("【帶到自己】用戶沒給自述"), "寫手知道這次要寫方向＋範例");
  assert(isValidOpenerGenerateLedgerResult(out.result));

  // 即使其他卡都被降級，範例卡也不當推薦。
  const allDemoted = { ...withDirection, openers: { extend: "妳會怕嗎？會累嗎？", resonate: "妳會怕嗎？會累嗎？", tease: "妳會怕嗎？會累嗎？", humor: "妳會怕嗎？會累嗎？", coldRead: withDirection.openers.coldRead } };
  const demoted = await runOpenerPlanWrite(input("想約她一起夜跑", PAID, "free"), deps({ plan, write: allDemoted }, []));
  assertEquals(demoted.kind === "ok" && demoted.result.recommendation.pick !== "coldRead", true);

  // 寫手沒給方向：那張不交付（範例不能變成看起來可以原封送出的句子）。
  const missing = await runOpenerPlanWrite(input("想約她一起夜跑", PAID, "free"), deps({ plan, write: { ...withDirection, directions: {} } }, []));
  assertEquals(missing.kind === "ok" && missing.result.openers.coldRead, undefined);
  assertEquals(missing.kind === "ok" && missing.result.access.directions, undefined);
  assertEquals(missing.kind === "ok" && missing.telemetry.directionCard, "missing");

  // 有用戶自述：帶到自己照舊（真的自述，不是範例）；寫手卻還給了方向＝把它寫成範例了，那張不交付。
  const selfPlan = { spans: [{ quote: "我也在練半馬", role: "sender_fact" }], anchorCueIds: ["cue_2"] };
  const selfWrite = { ...withDirection, openers: { ...withDirection.openers, coldRead: "半馬練到哪一段了？我也在練半馬" }, directions: {} };
  const self = await runOpenerPlanWrite(input("我也在練半馬", PAID, "free"), deps({ plan: selfPlan, write: selfWrite }, []));
  assertEquals(self.kind === "ok" && self.result.access.directions, undefined);
  assertEquals(self.kind === "ok" && self.result.openers.coldRead, "半馬練到哪一段了？我也在練半馬");
  const unrequested = await runOpenerPlanWrite(input("我也在練半馬", PAID, "free"), deps({ plan: selfPlan, write: withDirection }, []));
  assertEquals(unrequested.kind === "ok" && unrequested.result.openers.coldRead, undefined);
  assertEquals(unrequested.kind === "ok" && unrequested.telemetry.directionCard, "unrequested");
  const styles = await runOpenerPlanWrite(input("想約她一起夜跑", PAID), deps({ plan, write: withDirection }, []));
  assertEquals(styles.kind === "ok" && styles.result.access.directions, undefined);

  // 方向太長不截斷，當沒給；範例踩紅線不送改寫，直接拿掉。
  const long = await runOpenerPlanWrite(input("想約她一起夜跑", PAID, "free"), deps({ plan, write: { ...withDirection, directions: { coldRead: "可".repeat(61) } } }, []));
  assertEquals(long.kind === "ok" && long.result.openers.coldRead, undefined);
  const restricted = { spans: [{ quote: "不要聊工作", role: "restriction", term: "工作" }], anchorCueIds: ["cue_1"] };
  const badExample = { ...withDirection, openers: { ...withDirection.openers, coldRead: "我最近工作都很晚才跑，妳都跑哪？" } };
  const calls2: OpenerFlowModelRequest[] = [];
  const vetoed = await runOpenerPlanWrite(input("不要聊工作", PAID, "free"), deps({ plan: restricted, write: badExample }, calls2));
  assertEquals(vetoed.kind === "ok" && vetoed.result.openers.coldRead, undefined);
  assertEquals(calls2.length, 2, "沒有為範例卡多花一次改寫");
});

Deno.test("Bruce 9/26 寫法：emoji 直接拿掉、問句不一定要問號、不問為了問而問的數字行程", async () => {
  assertEquals(withoutEmoji("拉坯練到現在上手了嗎🙂"), "拉坯練到現在上手了嗎");
  assertEquals(withoutEmoji("跑步🏃‍♀️很療癒"), "跑步很療癒");
  assertEquals(withoutEmoji("🙂"), null);
  assertEquals(withoutEmoji("東京🇯🇵好玩嗎"), "東京好玩嗎");
  const out = await runOpenerPlanWrite(input(null, FREE), deps({ write: { ...WRITE_OK, openers: { ...WRITE_OK.openers, extend: "半馬賽前最怕哪一段🙂" } } }, []));
  assertEquals(out.kind === "ok" && out.result.openers.extend, "半馬賽前最怕哪一段", "推薦句不換掉，只拿掉 emoji");
  const writer = buildOpenerWritePrompt("free");
  assert(writer.includes("問句不一定要加問號"));
  assert(writer.includes("不用 emoji"));
  assert(writer.includes("不問天數、多久、多遠、頻率、班表"));
  assertFalse(writer.includes("下一步。"), "不再叫寫手問「下一步」（計畫類會變成排幾天）");
});

Deno.test("規劃「要問的點」只收名字／選擇（what）與經過／進度（story）；數量、時段、怎麼開始或沒標都不收", () => {
  const base = { spans: [{ quote: "想聊半馬", role: "topic" }], questionTarget: "半馬想挑戰哪一場" };
  assertEquals(parseOpenerPlan({ ...base, questionKind: "what" }, ctx("想聊半馬")).questionTarget, "半馬想挑戰哪一場");
  assertEquals(parseOpenerPlan({ ...base, questionKind: "story" }, ctx("想聊半馬")).questionTarget, "半馬想挑戰哪一場");
  for (const kind of ["amount", "schedule", "origin", undefined]) {
    const plan = parseOpenerPlan({ ...base, questionKind: kind }, ctx("想聊半馬"));
    assertEquals(plan.questionTarget, null, String(kind));
    assert(plan.repairedFields.includes("questionTarget.kind"));
  }
});

Deno.test("方向卡範例要是真的訊息：說明、空白、照抄 prompt 範例地名都不交付那張，也不讓整組失敗", async () => {
  assert(isDirectionExample("我最近都跑河濱那段，晚上風很舒服，妳都跑哪段", "可以先分享自己夜跑的經驗", ""));
  assertFalse(isDirectionExample("（沒有使用者自述）", "可以先分享自己的經驗", ""));
  assertFalse(isDirectionExample("先分享自己選潛點的考量再問她", "可以先分享自己的經驗", ""));
  assertFalse(isDirectionExample("我最近都跑環河公園那邊夜釣，妳們都釣什麼", "可以先分享自己釣魚的經驗", "她喜歡海釣"));
  assert(isDirectionExample("我最近都跑環河公園那，妳都跑哪", "可以先分享自己夜跑的經驗", "我常去環河公園"), "她或用戶的資料真的有那個地名就不算照抄");
  const plan = { spans: [{ quote: "想約她一起夜跑", role: "invite_request", topicPart: "夜跑" }], anchorCueIds: ["cue_1"] };
  const blank = { ...WRITE_OK, openers: { ...WRITE_OK.openers, coldRead: "" }, directions: { coldRead: "可以先分享自己夜跑的經驗" } };
  const calls: OpenerFlowModelRequest[] = [];
  const out = await runOpenerPlanWrite(input("想約她一起夜跑", PAID, "free"), deps({ plan, write: blank }, calls));
  assertEquals(out.kind, "ok", "範例空白不讓整組 502");
  assertEquals(calls.length, 2, "也不為它修格式");
  assertEquals(out.kind === "ok" && out.result.openers.coldRead, undefined);
  assertEquals(Object.keys(out.kind === "ok" ? out.result.openers : {}).length, 4);
});

// ── GPT 預審（4571b7c4）四項 P1 的固定回歸 ──

Deno.test("R1 有自述時，自己的事只能是自述原句、放在問完她之後：bb6 擴寫的真實輸出都擋下", () => {
  const yoga = { ...RULES, selfFacts: ["我以前也上過一陣子瑜珈，後來工作忙就沒去了"] };
  const bread = { ...RULES, selfFacts: ["而且我自己也烤過吐司"] };
  const unbound = (text: string, rules: typeof RULES) => judgeOpenerCard(text, rules).vetoes.includes("self_fact_unbound");
  // bb6 付費黑箱 4571b7c4 的真實卡片（F8 r2／r3、H04 r1／r2／r3）
  assert(unbound("頭倒立成功那次是靠牆練還是直接來，我以前上瑜珈連下犬式都做不好，後來工作忙就斷了", yoga));
  assert(unbound("頭倒立終於做出來的過程是怎樣，會不會其實比想像中好上手？我以前也上過一陣子瑜珈，後來工作忙就沒去了，滿懷念那種伸展感的", yoga));
  assert(unbound("養的酵母最近順利嗎，我自己烤過吐司但沒養過酵母，滿好奇的", bread));
  assert(unbound("我自己烤吐司常常在等發酵的時候很煎熬，妳養酵母現在習慣了嗎", bread));
  assert(unbound("養酵母現在卡在哪個階段，我自己烤吐司都是直接買現成酵母的，佩服妳從頭養", bread));
  // 照原句、放句尾（bb6 F8 r1）；自述前的連接詞不用照抄，句尾語助詞與標點不影響
  assertFalse(unbound("頭倒立看起來超難，妳是卡在哪個環節最久才突破的，我以前也上過一陣子瑜珈，後來工作忙就沒去了", yoga));
  assertFalse(unbound("養酵母現在卡在哪個階段，我自己也烤過吐司啦！", bread));
  assertFalse(unbound("我好奇妳都養哪種酵母，我自己也烤過吐司", bread), "「我好奇」是在問她");
  assertFalse(unbound("妳都烤哪種麵包", bread), "沒提自己的事");
  assertFalse(unbound("練到忘我是什麼感覺", yoga), "忘我不是自述");
  assert(unbound("我自己也烤過吐司，妳都烤哪種", bread), "自述放句首：送改寫移到問完她之後");
  // 沒有主詞的自述：前面補「我」不算另外的自述，後面再加料照擋
  const clay = { ...RULES, selfFacts: ["以前學過一點陶藝"] };
  assertFalse(unbound("妳現在都捏什麼，我以前學過一點陶藝", clay));
  assert(unbound("妳現在都捏什麼，我以前學過一點陶藝，拉坯超難", clay));
  // 自述本身以語助詞收尾（照抄或省掉都算原句）；整句自述都要照原句，「我」前面那段不能換
  assertFalse(unbound("妳常去哪座山？我也很喜歡爬山啊", { ...RULES, selfFacts: ["我也很喜歡爬山啊"] }));
  assertFalse(unbound("妳常去哪座山？我也很喜歡爬山", { ...RULES, selfFacts: ["我也很喜歡爬山啊"] }));
  assertFalse(unbound("妳都去哪一間？我也很常去酒吧", { ...RULES, selfFacts: ["我也很常去酒吧"] }));
  const hike = { ...RULES, selfFacts: ["上個月去爬玉山，我腳超痠"] };
  assert(unbound("妳爬過嗎？上週去爬雪山還摔了一跤，我腳超痠", hike));
  assert(unbound("妳喜歡爬山嗎？我腳超痠", hike));
  assertFalse(unbound("妳爬過玉山嗎？我上個月去爬玉山，我腳超痠", hike));
});

Deno.test("R1 執行：擴寫自述的卡走唯一一次改寫；改好照交付，還擴寫就拿掉那張，推薦不受影響", async () => {
  const plan = { spans: [{ quote: "我以前也跑過半馬", role: "sender_fact" }], anchorCueIds: ["cue_2"], nominatedStyle: "extend" };
  const embellished = "半馬練到哪一段了？我以前也跑過半馬，最後五公里超痛苦";
  const write = { ...WRITE_OK, openers: { ...WRITE_OK.openers, coldRead: embellished } };
  const calls: OpenerFlowModelRequest[] = [];
  const fixed = await runOpenerPlanWrite(input("我以前也跑過半馬", PAID, "free"), deps({ plan, write, rewrite: { openers: { coldRead: "半馬練到哪一段了？我以前也跑過半馬" } } }, calls));
  assertEquals(fixed.kind, "ok");
  if (fixed.kind !== "ok") return;
  assertEquals(calls.length, 3);
  assertEquals(calls[2].system, OPENER_REWRITE_PROMPT);
  assert(String(calls[2].messages[0].content).includes("照【用戶自述】原句"), "改寫器知道要照原句");
  assertEquals(fixed.result.openers.coldRead, "半馬練到哪一段了？我以前也跑過半馬");
  assertEquals(fixed.result.recommendation.pick, "extend");
  const still = await runOpenerPlanWrite(input("我以前也跑過半馬", PAID, "free"), deps({ plan, write, rewrite: { openers: { coldRead: embellished } } }, []));
  assertEquals(still.kind === "ok" && still.result.openers.coldRead, undefined);
  assertEquals(still.kind === "ok" && still.telemetry.droppedStyles, ["coldRead"]);
  assertEquals(still.kind === "ok" && still.result.recommendation.pick, "extend");
  assert(still.kind === "ok" && isValidOpenerGenerateLedgerResult(still.result));
});

Deno.test("R2 範例身分在評判／改寫／挑選前鎖定：寫手標成範例、又不是當次要求的那張，整張不交付", async () => {
  const noSelf = { spans: [{ quote: "想聊半馬", role: "topic" }], anchorCueIds: ["cue_2"] };
  const selfPlan = { spans: [{ quote: "我也在練半馬", role: "sender_fact" }], anchorCueIds: ["cue_2"] };
  const coldExample = "我最近都跑河濱那段，晚上風很舒服，妳都跑哪？";
  const extendExample = "我最近拉坯總是歪掉，妳半馬都怎麼配速";
  // 要求方向＋範例時，寫手把 extend 也標成範例：extend 不交付、不當推薦，coldRead 範例照規則交付。
  const both = { ...WRITE_OK, openers: { ...WRITE_OK.openers, extend: extendExample, coldRead: coldExample }, directions: { extend: "分享自己練陶藝的小經驗", coldRead: "可以先分享自己夜跑的經驗" } };
  const out = await runOpenerPlanWrite(input("想聊半馬", PAID, "free"), deps({ plan: noSelf, write: both }, []));
  assertEquals(out.kind, "ok");
  if (out.kind !== "ok") return;
  assertEquals(out.result.openers.extend, undefined);
  assertEquals(out.result.cardReasons.extend, undefined);
  assertEquals(out.result.stretchLevels.extend, undefined);
  assertEquals(out.result.access.directions, { coldRead: "可以先分享自己夜跑的經驗" });
  assert(out.telemetry.droppedStyles.includes("extend"));
  assert(!["extend", "coldRead"].includes(out.result.recommendation.pick));
  assert(isValidOpenerGenerateLedgerResult(out.result));
  // 有自述（沒要求範例）：標成範例的 extend 不交付；非空的任何型別都算標記，空字串不算。
  const selfWrite = { ...WRITE_OK, openers: { ...WRITE_OK.openers, extend: extendExample, coldRead: "半馬練到哪一段了？我也在練半馬" } };
  const self = await runOpenerPlanWrite(input("我也在練半馬", PAID, "free"), deps({ plan: selfPlan, write: { ...selfWrite, directions: { extend: "分享自己的小經驗" } } }, []));
  assertEquals(self.kind === "ok" && self.result.openers.extend, undefined);
  assertEquals(self.kind === "ok" && self.result.openers.coldRead, "半馬練到哪一段了？我也在練半馬");
  assertEquals(self.kind === "ok" && self.result.access.directions, undefined);
  for (const marker of [1, { text: "分享" }, ["分享"]]) {
    const typed = await runOpenerPlanWrite(input("我也在練半馬", PAID, "free"), deps({ plan: selfPlan, write: { ...selfWrite, directions: { coldRead: marker } } }, []));
    assertEquals(typed.kind === "ok" && typed.result.openers.coldRead, undefined, JSON.stringify(marker));
    assertEquals(typed.kind === "ok" && typed.telemetry.directionCard, "unrequested");
  }
  for (const directions of [{ coldRead: "" }, { foo: "分享" }, "分享自己的經驗", null]) {
    const kept = await runOpenerPlanWrite(input("我也在練半馬", PAID, "free"), deps({ plan: selfPlan, write: { ...selfWrite, openers: { ...selfWrite.openers, extend: WRITE_OK.openers.extend }, directions } }, []));
    assertEquals(kept.kind === "ok" && Object.keys(kept.result.openers).length, 5, JSON.stringify(directions));
  }
  // 標成範例的卡不送改寫（改寫器不知道那是範例）：踩紅線也直接拿掉，不多花一次呼叫。
  const restricted = { spans: [{ quote: "我也在練半馬", role: "sender_fact" }, { quote: "不要聊工作", role: "restriction", term: "工作" }], anchorCueIds: ["cue_2"] };
  const calls: OpenerFlowModelRequest[] = [];
  const vetoed = await runOpenerPlanWrite(input("我也在練半馬 不要聊工作", PAID, "free"), deps({ plan: restricted, write: { ...selfWrite, openers: { ...selfWrite.openers, extend: "我最近工作都很晚才跑，妳都跑哪" }, directions: { extend: "分享自己的小經驗" } } }, calls));
  assertEquals(vetoed.kind === "ok" && vetoed.result.openers.extend, undefined);
  assertEquals(calls.length, 2);
  // 修格式時：原輸出標了範例、修好的輸出把標記弄丟，那張仍不交付。
  const missingHumor = { ...selfWrite, openers: { ...selfWrite.openers, extend: "半馬配速都怎麼抓？", humor: "" }, directions: { extend: "分享自己的小經驗" } };
  const repaired = await runOpenerPlanWrite(input("我也在練半馬", PAID, "free"), deps({ plan: selfPlan, write: missingHumor, repair: { ...selfWrite, directions: {} } }, []));
  assertEquals(repaired.kind === "ok" && repaired.telemetry.formatRepairUsed, true);
  assertEquals(repaired.kind === "ok" && repaired.result.openers.extend, undefined);  // 標成範例又空白的卡本來就不交付：不為它修格式，也不讓整組失敗。
  const blankCalls: OpenerFlowModelRequest[] = [];
  const blank = await runOpenerPlanWrite(input("我也在練半馬", PAID, "free"), deps({ plan: selfPlan, write: { ...selfWrite, openers: { ...selfWrite.openers, extend: "" }, directions: { extend: "分享自己的小經驗" } } }, blankCalls));
  assertEquals(blank.kind, "ok");
  assertEquals(blankCalls.length, 2);
  assertEquals(blank.kind === "ok" && blank.result.openers.extend, undefined);
});

Deno.test("R4 規劃寫的讀法與要問的點不能把寫手看不到的片段帶回寫手；和她的資料共用的字不算", () => {
  const text = "我哥是機師，想問她半馬最怕哪一段";
  const spans = [{ quote: "我哥是機師", role: "background" }, { quote: "想問她半馬最怕哪一段", role: "question" }];
  const leakedTarget = parseOpenerPlan({ spans, anchorCueIds: ["cue_2"], questionTarget: "我哥是機師，想問她半馬哪段最怕", questionKind: "story" }, ctx(text));
  assertEquals(leakedTarget.questionTarget, null);
  assert(leakedTarget.repairedFields.includes("questionTarget.hidden"));
  const leakedReading = parseOpenerPlan({ spans: [spans[0], { ...spans[1], readAs: "哥哥是機師，想問她半馬最怕哪段" }], anchorCueIds: ["cue_2"], questionTarget: "半馬最怕哪一段", questionKind: "story" }, ctx(text));
  assertEquals(leakedReading.spans[1].readAs, null);
  assertEquals(leakedReading.questionTarget, "半馬最怕哪一段", "乾淨的要問的點照用");
  for (const plan of [leakedTarget, leakedReading]) {
    const content = buildOpenerWriteUserContent({ snapshot: SNAPSHOT, freeText: text, plan, digest: digestOpenerPlan(plan, { snapshot: SNAPSHOT, option: null }), primaryStyle: "extend", arm: "free" });
    assertFalse(content.includes("機師"), "寫手看不到背景");
    assert(content.includes("想問她半馬最怕哪一段"), "退回用戶原句");
  }
  // 背景提到她的線索（夜跑）：要問的點跟她的資料共用那兩個字，不算帶回背景。
  const cueShared = parseOpenerPlan({ spans: [{ quote: "我姊也在夜跑", role: "background" }, { quote: "想聊夜跑", role: "topic" }], anchorCueIds: ["cue_1"], questionTarget: "夜跑都跑哪一帶", questionKind: "what" }, ctx("我姊也在夜跑 想聊夜跑"));
  assertEquals(cueShared.questionTarget, "夜跑都跑哪一帶");
  assertFalse(cueShared.repairedFields.includes("questionTarget.hidden"));
  // 規劃漏標的字（沒有任何片段涵蓋）寫手也看不到：一樣不能被要問的點帶回去。
  const omitted = parseOpenerPlan({ spans: [spans[1]], anchorCueIds: ["cue_2"], questionTarget: "機師朋友最怕哪段", questionKind: "story" }, ctx(text));
  assert(omitted.coverageGap);
  assertEquals(omitted.questionTarget, null);
});

Deno.test("R2 複核：改寫回覆新標的範例、修格式回覆新標的空白卡——每一版都先認範例身分再判完整與交付", async () => {
  const selfPlan = { spans: [{ quote: "我也在練半馬", role: "sender_fact" }], anchorCueIds: ["cue_2"] };
  const selfWrite = { ...WRITE_OK, openers: { ...WRITE_OK.openers, coldRead: "半馬練到哪一段了？我也在練半馬" } };
  // 1) 改寫回覆把改寫的卡標成範例：新句子不交付（不當一般卡），也不多花呼叫。
  const restricted = { spans: [{ quote: "我也在練半馬", role: "sender_fact" }, { quote: "不要聊工作", role: "restriction", term: "工作" }], anchorCueIds: ["cue_2"] };
  const withVeto = { ...selfWrite, openers: { ...selfWrite.openers, extend: "做行銷工作還能練半馬很猛" } };
  const calls: OpenerFlowModelRequest[] = [];
  const marked = await runOpenerPlanWrite(input("我也在練半馬 不要聊工作", PAID, "free"), deps({
    plan: restricted,
    write: withVeto,
    rewrite: { openers: { extend: "半馬配速都怎麼抓？" }, directions: { extend: "分享自己找配速的經驗" } },
  }, calls));
  assertEquals(marked.kind, "ok");
  if (marked.kind !== "ok") return;
  assertEquals(calls.length, 3, "呼叫上限不變");
  assertEquals(marked.result.openers.extend, undefined, "改寫回覆標成範例的句子不當一般卡交付");
  assertEquals(marked.result.cardReasons.extend, undefined);
  assert(marked.telemetry.droppedStyles.includes("extend"));
  assertFalse(marked.telemetry.rewrittenStyles.includes("extend"));
  assert(marked.result.recommendation.pick !== "extend");
  // 對照：正常改寫照交付。
  const normal = await runOpenerPlanWrite(input("我也在練半馬 不要聊工作", PAID, "free"), deps({ plan: restricted, write: withVeto, rewrite: { openers: { extend: "半馬配速都怎麼抓？" } } }, []));
  assertEquals(normal.kind === "ok" && normal.result.openers.extend, "半馬配速都怎麼抓？");

  // 2) 修格式回覆才把空白的卡標成範例：那張不必交，其他有效卡照交付（不整組 incomplete）。
  const missing = { ...selfWrite, openers: { ...selfWrite.openers, humor: "" } };
  const repairMarks = { ...selfWrite, openers: { ...selfWrite.openers, humor: "" }, directions: { humor: "分享自己的小經驗" } };
  const repairCalls: OpenerFlowModelRequest[] = [];
  const repaired = await runOpenerPlanWrite(input("我也在練半馬", PAID, "free"), deps({ plan: selfPlan, write: missing, repair: repairMarks }, repairCalls));
  assertEquals(repaired.kind, "ok", "修格式版把空白卡標成範例：其他卡照交付");
  if (repaired.kind !== "ok") return;
  assertEquals(repairCalls.length, 3);
  assertEquals(repaired.result.openers.humor, undefined);
  assertEquals(Object.keys(repaired.result.openers).length, 4);
  // 對照：修格式版仍缺一般卡（沒標範例）→ 整組照拒絕；原標記丟失保護照舊。
  const stillMissing = await runOpenerPlanWrite(input("我也在練半馬", PAID, "free"), deps({ plan: selfPlan, write: missing, repair: { ...repairMarks, openers: { ...repairMarks.openers, resonate: "" }, directions: { humor: "分享" } } }, []));
  assertEquals(stillMissing.kind === "fail" && stillMissing.reason, "incomplete");
  // 對照：合法方向＋範例 coldRead 照交付、不當推薦。
  const noSelf = { spans: [{ quote: "想聊半馬", role: "topic" }], anchorCueIds: ["cue_2"] };
  const directional = { ...WRITE_OK, openers: { ...WRITE_OK.openers, humor: "", coldRead: "我最近都跑河濱那段，晚上風很舒服，妳都跑哪？" }, directions: { coldRead: "可以先分享自己夜跑的經驗" } };
  const dirRepaired = await runOpenerPlanWrite(input("想聊半馬", PAID, "free"), deps({ plan: noSelf, write: directional, repair: { ...directional, openers: { ...directional.openers, humor: "" }, directions: { coldRead: "可以先分享自己夜跑的經驗", humor: "分享" } } }, []));
  assertEquals(dirRepaired.kind, "ok");
  assertEquals(dirRepaired.kind === "ok" && dirRepaired.result.access.directions, { coldRead: "可以先分享自己夜跑的經驗" });
  assert(dirRepaired.kind === "ok" && dirRepaired.result.recommendation.pick !== "coldRead");
});

Deno.test("R2 複核對照：原標記丟失保護、額外呼叫只有一次、合法範例卡不當推薦（改壞就要紅）", async () => {
  const selfPlan = { spans: [{ quote: "我也在練半馬", role: "sender_fact" }], anchorCueIds: ["cue_2"] };
  const selfWrite = { ...WRITE_OK, openers: { ...WRITE_OK.openers, coldRead: "半馬練到哪一段了？我也在練半馬" } };
  // 原輸出把一張正常句子標成範例、修格式版把標記弄丟：那張仍不交付、不當推薦。
  const calls: OpenerFlowModelRequest[] = [];
  const lost = await runOpenerPlanWrite(input("我也在練半馬", PAID, "free"), deps({
    plan: selfPlan,
    write: { ...selfWrite, openers: { ...selfWrite.openers, humor: "" }, directions: { extend: "分享自己的小經驗" } },
    repair: { ...selfWrite, directions: {} },
  }, calls));
  assertEquals(lost.kind, "ok");
  if (lost.kind !== "ok") return;
  assertEquals(calls.length, 3);
  assertEquals(lost.result.openers.extend, undefined);
  assert(lost.telemetry.droppedStyles.includes("extend"));
  assert(lost.result.recommendation.pick !== "extend");
  // 修格式用掉唯一額外呼叫後，踩紅線的卡直接拿掉、不再改寫。
  const restricted = { spans: [{ quote: "我也在練半馬", role: "sender_fact" }, { quote: "不要聊工作", role: "restriction", term: "工作" }], anchorCueIds: ["cue_2"] };
  const capCalls: OpenerFlowModelRequest[] = [];
  const capped = await runOpenerPlanWrite(input("我也在練半馬 不要聊工作", PAID, "free"), deps({
    plan: restricted,
    write: { ...selfWrite, openers: { ...selfWrite.openers, humor: "" } },
    repair: { ...selfWrite, openers: { ...selfWrite.openers, tease: "做行銷工作還能練半馬很猛" } },
    rewrite: { openers: { tease: "半馬配速都怎麼抓？" } },
  }, capCalls));
  assertEquals(capCalls.length, 3, "規劃＋寫手＋一次額外呼叫");
  assertEquals(capped.kind === "ok" && capped.result.openers.tease, undefined);
  assertEquals(capped.kind === "ok" && capped.telemetry.rewriteUsed, false);
  // 除了方向＋範例卡其他都踩紅線：範例不當推薦，整組不交付。
  const noSelfRestricted = { spans: [{ quote: "不要聊工作", role: "restriction", term: "工作" }], anchorCueIds: ["cue_1"] };
  const allWork = { openers: { extend: "工作忙嗎", resonate: "工作累嗎", tease: "工作多嗎", humor: "工作好玩嗎", coldRead: "我最近都跑河濱那段，晚上風很舒服，妳都跑哪？" }, directions: { coldRead: "可以先分享自己夜跑的經驗" } };
  const onlyExample = await runOpenerPlanWrite(input("不要聊工作", PAID, "free"), deps({ plan: noSelfRestricted, write: allWork }, []));
  assertEquals(onlyExample.kind === "fail" && onlyExample.reason, "no_deliverable");
});

// ── GPT 正式主審（da5d76b6）F1／F2 ──

Deno.test("主審 F1 限制未知不等於沒有限制：詞寫錯、詞缺席、規劃逾時、規劃壞掉，都不能推薦聊工作的句子", async () => {
  const workWrite = { ...WRITE_OK, openers: { ...WRITE_OK.openers, extend: "妳工作最喜歡哪個部分？" }, cardReasons: { ...WRITE_OK.cardReasons, extend: "接她工作裡喜歡的事情" } };
  const restrictionWith = (term?: string) => ({ spans: [{ quote: "不要聊工作", role: "restriction", ...(term === undefined ? {} : { term }) }], anchorCueIds: ["cue_3", "cue_1"] });
  const cases: Array<[string, unknown]> = [
    ["詞寫錯", restrictionWith("職場")],
    ["詞缺席", restrictionWith()],
    ["規劃逾時", new Error("deadline")],
    ["規劃壞掉", "not json"],
  ];
  for (const [label, plan] of cases) {
    const calls: OpenerFlowModelRequest[] = [];
    const out = await runOpenerPlanWrite(input("不要聊工作", PAID, "free"), deps({ plan, write: workWrite }, calls));
    assertEquals(out.kind, "ok", label);
    if (out.kind !== "ok") continue;
    assertEquals(out.result.openers.extend, undefined, `${label}：聊工作的卡不交付`);
    assert(!Object.values(out.result.openers).some((t) => t?.includes("工作")), label);
    assert(out.result.recommendation.pick !== "extend", label);
    assert(out.plan.guardTerms.includes("工作"), label);
    assertFalse(out.plan.anchorCueIds.includes("cue_3"), `${label}：選題不選工作`);
    assert(String(calls[1].messages[0].content).includes("【不要提到】工作"), `${label}：寫手知道要避開`);
    assertEquals(out.result.profileAnalysis?.avoidTopics, undefined, `${label}：不確定的詞不以「不聊 X」顯示`);
  }
  // 對照：有效的詞照舊（顯示不聊工作）；結構化排除照舊；一般正向補充降級仍交付；問句裡的「不聊」不是排除。
  const valid = await runOpenerPlanWrite(input("不要聊工作", PAID, "free"), deps({ plan: restrictionWith("工作"), write: workWrite }, []));
  assertEquals(valid.kind === "ok" && valid.result.openers.extend, undefined);
  assertEquals(valid.kind === "ok" && valid.plan.guardTerms, []);
  assertEquals(valid.kind === "ok" && valid.result.profileAnalysis?.avoidTopics, ["不聊工作"]);
  const option: OpenerQuestionOption = { id: "o", label: "不要聊工作", meaning: "exclude_cue", cueId: "cue_3" };
  const structured = await runOpenerPlanWrite({ ...input(null, PAID, "free"), option }, deps({ plan: new Error("deadline"), write: workWrite }, []));
  assertEquals(structured.kind === "ok" && structured.result.openers.extend, undefined);
  const neutral = await runOpenerPlanWrite(input("想聊半馬", PAID, "free"), deps({ plan: new Error("deadline"), write: WRITE_OK }, []));
  assertEquals(neutral.kind, "ok", "正向補充沒讀到仍降級交付");
  assertEquals(neutral.kind === "ok" && neutral.result.materialUse.handlingNote, HANDLING_NOTE.unread);
  const question = parseOpenerPlan({ spans: [{ quote: "想問她為什麼不聊工作", role: "question" }], anchorCueIds: ["cue_3"] }, ctx("想問她為什麼不聊工作"));
  assertEquals(question.guardTerms, []);
  assertEquals(question.anchorCueIds, ["cue_3"]);
  assertEquals(digestOpenerPlan(question, { snapshot: SNAPSHOT, option: null }).excludedTerms, []);
  // 錯字：規劃讀對了（公作 → 工作）但不在引文裡；她的資料逐字有這個詞 → 一樣避開（錄製資料有 恐佈片／公作）。
  const typo = parseOpenerPlan({ spans: [{ quote: "不要聊公作", role: "restriction", term: "工作" }], anchorCueIds: ["cue_3", "cue_1"] }, ctx("不要聊公作"));
  assertEquals(typo.guardTerms, ["工作"]);
  assertFalse(typo.anchorCueIds.includes("cue_3"));
  // 看不懂用戶意思（規劃失敗）只避開她的線索標籤：常用字不擋、簡繁一致。
  assertEquals(parseOpenerPlan(null, ctx("我最近也在準備比賽")).guardTerms, [], "最近、準備這類常用字不擋");
  assertEquals(parseOpenerPlan(null, ctx("不要聊半马")).guardTerms, ["半馬"], "簡體也認得她的線索");
  // 用戶在寫手看得到的片段裡明說想聊的，比不確定的限制更明確（別問配速 ≠ 別聊半馬）。
  const asked = parseOpenerPlan({ spans: [{ quote: "想聊半馬", role: "topic" }, { quote: "但別問她半馬配速", role: "restriction" }], anchorCueIds: ["cue_2"] }, ctx("想聊半馬，但別問她半馬配速"));
  assertEquals(asked.guardTerms, []);
  assertEquals(asked.anchorCueIds, ["cue_2"]);
  // 規劃寫的「要問的點」帶到要避開的詞就不送寫手。
  const guardedTarget = parseOpenerPlan({ spans: [{ quote: "不要聊公作", role: "restriction", term: "工作" }], anchorCueIds: ["cue_1"], questionTarget: "工作最近忙不忙", questionKind: "story" }, ctx("不要聊公作"));
  assertEquals(guardedTarget.questionTarget, null);
  // 限制的東西不在她的資料、也不在寫手看得到的片段裡：寫手拿不到任何相關原文，照常交付。
  const unrelated = parseOpenerPlan({ spans: [{ quote: "不要聊前任", role: "restriction" }, { quote: "想聊半馬", role: "topic" }], anchorCueIds: ["cue_2"] }, ctx("不要聊前任 想聊半馬"));
  assertEquals(unrelated.guardTerms, []);
  assertEquals(unrelated.anchorCueIds, ["cue_2"]);
});

Deno.test("主審 F2 呼叫後失敗拿不到用量：用量不再算完整；沒呼叫就跳過的規劃不算", async () => {
  const planFailed = await runOpenerPlanWrite(input("隨便聊聊", PAID, "free"), deps({ plan: new Error("boom"), write: WRITE_OK }, []));
  assertEquals(planFailed.kind === "ok" && [planFailed.telemetry.invokerCalls, planFailed.telemetry.modelAttempts, planFailed.telemetry.usageComplete], [2, 1, false]);
  const restricted = { spans: [{ quote: "不要聊工作", role: "restriction", term: "工作" }], anchorCueIds: ["cue_1"] };
  const rewriteFailed = await runOpenerPlanWrite(input("不要聊工作", PAID, "free"), deps({ plan: restricted, write: { ...WRITE_OK, openers: { ...WRITE_OK.openers, extend: "妳工作最喜歡哪個部分？" } }, rewrite: new Error("boom") }, []));
  assertEquals(rewriteFailed.kind, "ok");
  assertEquals(rewriteFailed.kind === "ok" && [rewriteFailed.telemetry.invokerCalls, rewriteFailed.telemetry.modelAttempts, rewriteFailed.telemetry.usageComplete], [3, 2, false]);
  const normal = await runOpenerPlanWrite(input("想聊半馬", PAID, "free"), deps({ plan: { spans: [{ quote: "想聊半馬", role: "topic" }], anchorCueIds: ["cue_2"] }, write: WRITE_OK }, []));
  assertEquals(normal.kind === "ok" && [normal.telemetry.invokerCalls, normal.telemetry.modelAttempts, normal.telemetry.usageComplete], [2, 2, true]);
  // 快到截止：規劃根本沒呼叫就跳過 → 不憑空算成未知用量。
  const skipped = await runOpenerPlanWrite(input("隨便聊聊", PAID, "free"), deps({ write: WRITE_OK }, [], Date.now() + 20_000));
  assertEquals(skipped.kind === "ok" && [skipped.telemetry.planError, skipped.telemetry.invokerCalls, skipped.telemetry.usageComplete], ["skipped_deadline", 1, true]);
});

Deno.test("主審第二輪 F1：用戶自述裡同一個詞不能撤掉限制（我以前做過行銷工作，不要聊工作）；只有明說想聊／想問才優先", async () => {
  const text = "我以前做過行銷工作，不要聊工作";
  const fact = { quote: "我以前做過行銷工作", role: "sender_fact" };
  const workWrite = { ...WRITE_OK, openers: { ...WRITE_OK.openers, extend: "妳工作最喜歡哪個部分？" }, cardReasons: { ...WRITE_OK.cardReasons, extend: "接她工作裡喜歡的事情" } };
  const cases: Array<[string, Record<string, unknown>, OpenerType[]]> = [
    ["缺詞", { quote: "不要聊工作", role: "restriction" }, PAID],
    ["錯詞", { quote: "不要聊工作", role: "restriction", term: "職場" }, PAID],
    ["有效詞", { quote: "不要聊工作", role: "restriction", term: "工作" }, PAID],
    ["Free 缺詞", { quote: "不要聊工作", role: "restriction" }, FREE],
  ];
  for (const [label, restriction, visible] of cases) {
    const plan = { spans: [fact, restriction], anchorCueIds: ["cue_3", "cue_1"] };
    const calls: OpenerFlowModelRequest[] = [];
    const out = await runOpenerPlanWrite(input(text, visible, "free"), deps({ plan, write: workWrite }, calls));
    assertEquals(out.kind, "ok", label);
    if (out.kind !== "ok") continue;
    assertEquals(out.result.openers.extend, undefined, `${label}：聊工作的卡不交付`);
    assert(out.result.recommendation.pick !== "extend", label);
    assertFalse(out.plan.anchorCueIds.includes("cue_3"), `${label}：選題不選工作`);
    assert(String(calls[1].messages[0].content).includes("【不要提到】工作"), label);
  }
  // 自述跟限制不重疊：限制照樣保住，自述照樣可用。
  const apart = parseOpenerPlan({ spans: [{ quote: "我也在練半馬", role: "sender_fact" }, { quote: "不要聊工作", role: "restriction" }], anchorCueIds: ["cue_2"] }, ctx("我也在練半馬，不要聊工作"));
  assertEquals(apart.guardTerms, ["工作"]);
  assertEquals(digestOpenerPlan(apart, { snapshot: SNAPSHOT, option: null }).selfFacts, ["我也在練半馬"]);
  // 對照：明說想聊／想問的話題仍優先（別問配速 ≠ 別聊半馬）。
  const askedQuestion = parseOpenerPlan({ spans: [{ quote: "想問她半馬準備得怎樣", role: "question" }, { quote: "但別問她半馬配速", role: "restriction" }], anchorCueIds: ["cue_2"] }, ctx("想問她半馬準備得怎樣，但別問她半馬配速"));
  assertEquals(askedQuestion.guardTerms, []);
});
