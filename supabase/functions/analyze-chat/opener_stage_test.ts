// opener_stage.ts：兩段式合約層純函式測試（附件 F12、F20、§10.3 選項白名單）。
import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildOpenerAnalysisSnapshot,
  computeOpenerGenerationInputHash,
  graphemeLength,
  OPENER_FREE_TEXT_MAX_GRAPHEMES,
  parseOpenerAnalyzeRequest,
  parseOpenerGenerateRequest,
  validateContributionAgainstSnapshot,
} from "./opener_stage.ts";

const UUID = "0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f01";
const PROFILE = { bio: "有養一隻狗 假日會去河堤", interests: "咖啡、旅遊" };

function analysisWithQuestion(overrides: Record<string, unknown> = {}) {
  return buildOpenerAnalysisSnapshot({
    parsed: {
      profileDigest: "自介：有養一隻狗；興趣咖啡、旅遊",
      approach: { mode: "anchor_hooks", summary: "可以從她的狗開，但先確認你想聊哪個", avoid: ["不用證明自己符合條件", "第二點", "第三點不該出現"] },
      cues: [
        { id: "cue_1", label: "養狗", source: "profile_text", evidence: { field: "bio", quote: "有養一隻狗" } },
        { id: "cue_2", label: "咖啡", source: "profile_text", evidence: { field: "interests", quote: "不存在的引文" } },
        { id: "cue_3", label: "假照片線索", source: "image", evidence: { imageIndex: 1 } },
        { id: "cue_4", label: "第四個遞補", source: "profile_text" },
        { id: "cue_5", label: "第五個超過上限", source: "profile_text" },
      ],
      question: {
        affects: "sender_fact",
        text: "你跟養狗這件事比較接近哪種？",
        options: [
          { id: "option_1", label: "我自己有養", meaning: "assert_sender_fact", cueId: "cue_1", statement: "我有養狗" },
          { id: "option_2", label: "沒養，但有興趣", meaning: "curious_without_experience", cueId: "cue_1" },
          { id: "option_3", label: "其實想聊別的", meaning: "change_direction" },
          { id: "option_4", label: "亂來", meaning: "make_up_fact", cueId: "cue_1" },
          { id: "option_5", label: "她的狗", meaning: "assert_sender_fact", cueId: "cue_1", statement: "她很愛狗" },
        ],
      },
      ...overrides,
    },
    rawProfileInfo: PROFILE,
    imageCount: 0,
    initialNoteProvided: false,
  });
}

Deno.test("F20：grapheme 計數與 300 字邊界，emoji／組合字算一個字", () => {
  assertEquals(graphemeLength("你好"), 2);
  assertEquals(graphemeLength("👨‍👩‍👧‍👦"), 1);
  assertEquals(graphemeLength("é"), 1);
  const exact = "字".repeat(OPENER_FREE_TEXT_MAX_GRAPHEMES);
  const over = "🐶".repeat(OPENER_FREE_TEXT_MAX_GRAPHEMES + 1);
  const ok = parseOpenerGenerateRequest({
    rawFlowVersion: 1, rawSessionId: UUID, rawAnalysisRevision: 1, rawGenerationId: UUID,
    rawContribution: { state: "answered", freeText: exact },
  });
  assert(ok.ok && ok.request.contribution.freeText === exact, "剛好 300 字放行且原文不被截斷");
  const rejected = parseOpenerGenerateRequest({
    rawFlowVersion: 1, rawSessionId: UUID, rawAnalysisRevision: 1, rawGenerationId: UUID,
    rawContribution: { state: "answered", freeText: over },
  });
  assert(!rejected.ok && rejected.code === "OPENER_CONTRIBUTION_INVALID");
  assert(!rejected.ok && rejected.message.includes("301"), "錯誤訊息回報實際字數、不靜默截斷");
});

Deno.test("第二段請求：略過不得夾帶答案、標已回答必須有內容、選項要有題目", () => {
  const base = { rawFlowVersion: 1, rawSessionId: UUID, rawAnalysisRevision: 1, rawGenerationId: UUID };
  const skippedWithText = parseOpenerGenerateRequest({ ...base, rawContribution: { state: "skipped", freeText: "我有養狗" } });
  assert(!skippedWithText.ok && skippedWithText.code === "OPENER_CONTRIBUTION_INVALID");
  const answeredEmpty = parseOpenerGenerateRequest({ ...base, rawContribution: { state: "answered" } });
  assert(!answeredEmpty.ok);
  const optionNoQuestion = parseOpenerGenerateRequest({ ...base, rawContribution: { state: "answered", selectedOptionId: "option_1" } });
  assert(!optionNoQuestion.ok);
  const skipped = parseOpenerGenerateRequest({ ...base, rawContribution: { state: "skipped" } });
  assert(skipped.ok && skipped.request.contribution.freeText === null);
  const noAnswer = parseOpenerGenerateRequest({ ...base, rawContribution: { state: "no_answer", freeText: "   " } });
  assert(noAnswer.ok && noAnswer.request.contribution.state === "no_answer");
  const badVersion = parseOpenerGenerateRequest({ ...base, rawFlowVersion: 2, rawContribution: { state: "skipped" } });
  assert(!badVersion.ok && badVersion.code === "OPENER_FLOW_VERSION_INVALID");
});

Deno.test("第一段請求：flow version、analysisRequestId、初稿長度", () => {
  const ok = parseOpenerAnalyzeRequest({ rawFlowVersion: 1, rawAnalysisRequestId: UUID.toUpperCase(), rawInitialUserNote: " 想問她那家店在哪 ", contractVersion: 2 });
  assert(ok.ok && ok.request.analysisRequestId === UUID && ok.request.initialUserNote === "想問她那家店在哪");
  const badId = parseOpenerAnalyzeRequest({ rawFlowVersion: 1, rawAnalysisRequestId: "nope", rawInitialUserNote: null, contractVersion: 2 });
  assert(!badId.ok && badId.code === "OPENER_ANALYSIS_REQUEST_ID_INVALID");
  const longNote = parseOpenerAnalyzeRequest({ rawFlowVersion: 1, rawAnalysisRequestId: UUID, rawInitialUserNote: "字".repeat(301), contractVersion: 2 });
  assert(!longNote.ok && longNote.code === "OPENER_CONTRIBUTION_INVALID");
});

Deno.test("快照清洗：引文逐字核對、線索上限三個、圖片來源無圖時丟掉、avoid 最多兩點", () => {
  const snapshot = analysisWithQuestion();
  assert(snapshot);
  // 無圖時 image 來源被丟掉，第四個遞補成 cue_3，第五個超過三個上限。
  assertEquals(snapshot.cues.map((c) => [c.id, c.label]), [["cue_1", "養狗"], ["cue_2", "咖啡"], ["cue_3", "第四個遞補"]]);
  assertEquals(snapshot.cues[0].evidence, { field: "bio", quote: "有養一隻狗" });
  assertEquals(snapshot.cues[2].evidence, undefined, "沒有原文證據就不填假引文");
  // 引文對不上：留欄位、丟引文，不偽造。
  assertEquals(snapshot.cues[1].evidence, { field: "interests" });
  assertEquals(snapshot.approach.avoid.length, 2);
  assertEquals(snapshot.approach.mode, "anchor_hooks");
  assertEquals(snapshot.profileText, PROFILE);
  assertEquals(snapshot.initialNoteProvided, false);
});

Deno.test("題目清洗：meaning 白名單、assert_sender_fact 的 statement 必須是第一人稱且不談她、選項重新編號", () => {
  const snapshot = analysisWithQuestion();
  assert(snapshot?.question);
  const question = snapshot.question;
  assertEquals(question.id, "question_1");
  assertEquals(question.affects, "sender_fact");
  assertEquals(question.options.map((o) => [o.id, o.meaning]), [
    ["option_1", "assert_sender_fact"],
    ["option_2", "curious_without_experience"],
    ["option_3", "change_direction"],
  ]);
  assertEquals(question.options[0].statement, "我有養狗");
  assertEquals(question.options[0].cueId, "cue_1");
  assertEquals(question.options[2].cueId, undefined);
});

Deno.test("題目清洗：需要線索的選項指向被丟掉的線索→選項消失；不足兩個選項→零題", () => {
  const snapshot = analysisWithQuestion({
    cues: [{ id: "cue_9", label: "養狗", source: "profile_text" }],
    question: {
      affects: "material",
      text: "想聊哪個？",
      options: [
        { label: "狗", meaning: "pick_cue", cueId: "cue_9" },
        { label: "咖啡", meaning: "pick_cue", cueId: "cue_missing" },
      ],
    },
  });
  assert(snapshot);
  assertEquals(snapshot.cues.map((c) => c.id), ["cue_1"]);
  assertEquals(snapshot.question, null, "只剩一個合法選項就不問");

  const byPosition = analysisWithQuestion({
    cues: [
      { label: "養狗", source: "profile_text" },
      { label: "咖啡", source: "profile_text" },
    ],
    question: {
      affects: "material",
      text: "想聊哪個？",
      options: [
        { label: "狗", meaning: "pick_cue", cueId: "cue_1" },
        { label: "咖啡", meaning: "pick_cue", cueId: "cue_2" },
      ],
    },
  });
  assert(byPosition?.question);
  assertEquals(byPosition.question.options.map((o) => o.cueId), ["cue_1", "cue_2"]);
});

Deno.test("快照清洗：沒有任何線索時 anchor_hooks 降為 low_info；缺 summary 整份無效", () => {
  const noCues = analysisWithQuestion({ cues: [], question: null });
  assertEquals(noCues?.approach.mode, "low_info");
  const noSummary = analysisWithQuestion({ approach: { mode: "anchor_hooks" } });
  assertEquals(noSummary, null);
});

Deno.test("F12：題目／選項必須屬於本局；題目為 null 時不得帶選項", () => {
  const snapshot = analysisWithQuestion()!;
  const good = validateContributionAgainstSnapshot({ state: "answered", questionId: "question_1", selectedOptionId: "option_2", freeText: null }, snapshot);
  assert(good.ok && good.option?.meaning === "curious_without_experience");
  const foreignOption = validateContributionAgainstSnapshot({ state: "answered", questionId: "question_1", selectedOptionId: "option_9", freeText: null }, snapshot);
  assert(!foreignOption.ok);
  const foreignQuestion = validateContributionAgainstSnapshot({ state: "answered", questionId: "question_2", selectedOptionId: "option_1", freeText: null }, snapshot);
  assert(!foreignQuestion.ok);
  const noQuestion = analysisWithQuestion({ question: null })!;
  const optionWithoutQuestion = validateContributionAgainstSnapshot({ state: "answered", questionId: "question_1", selectedOptionId: "option_1", freeText: null }, noQuestion);
  assert(!optionWithoutQuestion.ok);
  const textOnly = validateContributionAgainstSnapshot({ state: "answered", questionId: null, selectedOptionId: null, freeText: "想聊咖啡" }, noQuestion);
  assert(textOnly.ok && textOnly.option === null);
});

Deno.test("生成輸入指紋：回答一定入 hash（改答案＝不同操作），同輸入決定性", async () => {
  const base = { sessionId: UUID, analysisRevision: 1, promptVersion: "v1", contractVersion: 2 };
  const a = await computeOpenerGenerationInputHash({ ...base, contribution: { state: "answered", questionId: "q", selectedOptionId: "o1", freeText: "我有養狗" } });
  const same = await computeOpenerGenerationInputHash({ ...base, contribution: { state: "answered", questionId: "q", selectedOptionId: "o1", freeText: "我有養狗" } });
  const edited = await computeOpenerGenerationInputHash({ ...base, contribution: { state: "answered", questionId: "q", selectedOptionId: "o1", freeText: "改聊咖啡" } });
  const skipped = await computeOpenerGenerationInputHash({ ...base, contribution: { state: "skipped", questionId: null, selectedOptionId: null, freeText: null } });
  assertEquals(a, same);
  assert(a !== edited && a !== skipped && edited !== skipped);
  assert(/^[0-9a-f]{64}$/.test(a));
});
