import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  countCoachClarifications,
  mustClarifyFirstRound,
  shouldForceCoachAnswerAfterClarifications,
  textCarriesCaseEvidence,
} from "./clarification_policy.ts";

Deno.test("textCarriesCaseEvidence 只認結構訊號：說話者標記／動詞後引文／三段引文", () => {
  assertEquals(textCarriesCaseEvidence("對方回得很短，我該怎麼判斷？"), false);
  assertEquals(
    textCarriesCaseEvidence("不知道怎麼開啟話題，給我一點方向？"),
    false,
  );
  assertEquals(
    textCarriesCaseEvidence("她已讀不回我好焦慮，我要再傳嗎？"),
    false,
  );
  // Codex R2 第二輪反例：引號只是選項、字數灌水，都不算原話。
  assertEquals(
    textCarriesCaseEvidence("她對我是「有好感」還是「沒興趣」？"),
    false,
  );
  assertEquals(
    textCarriesCaseEvidence("請判斷她喜不喜歡我，".repeat(6)),
    false,
  );
  // 純描述沒有原話：不算，先釐清一次請他貼。
  assertEquals(
    textCarriesCaseEvidence(
      "認識一個月，十次有八次是我開頭，但她每次回得都蠻長，也會問我問題，我們聊工作聊旅行，週末也會互傳限動，只是她從來不先開口。",
    ),
    false,
  );
  // 說話者標記。
  assertEquals(
    textCarriesCaseEvidence(
      "她最近這樣回——我：這週末有要去哪玩嗎？她：沒欸 在家。",
    ),
    true,
  );
  // 動詞後引文（含冒號、單字引文）。
  assertEquals(
    textCarriesCaseEvidence(
      "她昨天回我「沒欸 在家」，我推薦影集她說「好啊 哪部」，算有興趣嗎？",
    ),
    true,
  );
  assertEquals(
    textCarriesCaseEvidence("她剛剛回我「今天開會開到快死」。"),
    true,
  );
  assertEquals(
    textCarriesCaseEvidence("她說：「今天很累，先睡了。」我該怎麼回？"),
    true,
  );
  assertEquals(
    textCarriesCaseEvidence("她的回覆只有「嗯」和「好」，我該怎麼判斷？"),
    true,
  );
  assertEquals(textCarriesCaseEvidence("我傳「今天好累喔」她已讀沒回"), true);
  // 三段以上引文（純貼原話）。
  assertEquals(
    textCarriesCaseEvidence(
      "「這週末要去哪」「沒欸 在家」「那我推薦影集」「好啊 哪部」",
    ),
    true,
  );
  assertEquals(textCarriesCaseEvidence(null), false);
});

Deno.test("mustClarifyFirstRound 使用者已貼原話就不再逼貼（Codex R2 P2）", () => {
  const base = {
    forceAnswer: false,
    scope: { type: "global" },
    recentMessages: [],
  };
  // 首問就貼原話。
  assertEquals(
    mustClarifyFirstRound({
      ...base,
      userQuestion:
        "她回我「沒欸 在家」，我說推薦影集她回「好啊 哪部」，這樣算有興趣嗎？",
      activeSessionTurns: [],
    }),
    false,
  );
  // 釐清後貼了原話、拿到答案、繼續深挖：證據在上一張答案之前，不該再問。
  assertEquals(
    mustClarifyFirstRound({
      ...base,
      userQuestion: "那我要怎麼回她比較好？",
      activeSessionTurns: [
        {
          role: "user",
          kind: "question",
          content: "對方回得很短，我該怎麼判斷？",
        },
        { role: "coach", kind: "clarification", content: "貼三句原話給我？" },
        {
          role: "user",
          kind: "supplement",
          content:
            "我：這週末去哪玩？她：沒欸 在家。我：推薦你影集。她：好啊 哪部？",
        },
        {
          role: "coach",
          kind: "answer",
          content: "她有接話還反問，不是冷淡。",
        },
      ],
    }),
    false,
  );
  // 上一題純問句＋答案（沒原話），新題也沒原話：照樣先釐清。
  assertEquals(
    mustClarifyFirstRound({
      ...base,
      userQuestion: "怎麼把聊天推進到約出來？",
      activeSessionTurns: [
        { role: "user", kind: "question", content: "不知道怎麼開啟話題？" },
        { role: "coach", kind: "answer", content: "先釐清局面。" },
      ],
    }),
    true,
  );
});

Deno.test("coach clarification policy allows at most three no-charge clarifications", () => {
  const twoClarifications = [
    { role: "user", kind: "question" },
    { role: "coach", kind: "clarification" },
    { role: "user", kind: "supplement" },
    { role: "coach", kind: "clarification" },
  ];
  const threeClarifications = [
    ...twoClarifications,
    { role: "user", kind: "supplement" },
    { role: "coach", kind: "clarification" },
  ];

  assertEquals(countCoachClarifications(twoClarifications), 2);
  assertEquals(
    shouldForceCoachAnswerAfterClarifications({
      activeSessionTurns: twoClarifications,
    }),
    false,
  );

  assertEquals(countCoachClarifications(threeClarifications), 3);
  assertEquals(
    shouldForceCoachAnswerAfterClarifications({
      activeSessionTurns: threeClarifications,
    }),
    true,
  );
});

Deno.test("coach clarification policy treats explicit forceAnswer as formal answer", () => {
  assertEquals(
    shouldForceCoachAnswerAfterClarifications({
      forceAnswer: true,
      activeSessionTurns: [],
    }),
    true,
  );
});

Deno.test("mustClarifyFirstRound looks at the current thread, not seeded memory (2026-09-07)", () => {
  const base = {
    forceAnswer: false,
    scope: { type: "global" },
    recentMessages: [],
  };
  // client 把上一題的問答種回 turns（24h resume／跨天摘要）：不算本題脈絡。
  assertEquals(
    mustClarifyFirstRound({
      ...base,
      activeSessionTurns: [
        { role: "user", kind: "question" },
        { role: "coach", kind: "answer" },
      ],
    }),
    true,
  );
  // 上一題釐清過、已給答案，這一題重新開始：仍要先釐清。
  assertEquals(
    mustClarifyFirstRound({
      ...base,
      activeSessionTurns: [
        { role: "user", kind: "question" },
        { role: "coach", kind: "clarification" },
        { role: "user", kind: "supplement" },
        { role: "coach", kind: "answer" },
      ],
    }),
    true,
  );
  // 本題已釐清過（在最後一張答案之後）：交回模型判斷。
  assertEquals(
    mustClarifyFirstRound({
      ...base,
      activeSessionTurns: [
        { role: "user", kind: "question" },
        { role: "coach", kind: "answer" },
        { role: "user", kind: "question" },
        { role: "coach", kind: "clarification" },
      ],
    }),
    false,
  );
  // partner 同一套。
  assertEquals(
    mustClarifyFirstRound({
      ...base,
      scope: { type: "partner" },
      activeSessionTurns: [
        { role: "user", kind: "question" },
        { role: "coach", kind: "answer" },
      ],
    }),
    true,
  );
});

Deno.test("mustClarifyFirstRound gates only contextless global first rounds", () => {
  const gated = {
    forceAnswer: false,
    scope: { type: "global" },
    activeSessionTurns: [],
    recentMessages: [],
  };
  assertEquals(mustClarifyFirstRound(gated), true);
  // 逃生門：直接看正式建議。
  assertEquals(mustClarifyFirstRound({ ...gated, forceAnswer: true }), false);
  // 已有本輪脈絡。
  assertEquals(
    mustClarifyFirstRound({
      ...gated,
      activeSessionTurns: [{ role: "coach", kind: "clarification" }],
    }),
    false,
  );
  // 已有對話訊息。
  assertEquals(
    mustClarifyFirstRound({ ...gated, recentMessages: [{}] }),
    false,
  );
  // conversation scope 不受閘門影響。
  assertEquals(
    mustClarifyFirstRound({
      ...gated,
      scope: { type: "conversation" },
    }),
    false,
  );
  assertEquals(mustClarifyFirstRound({ ...gated, scope: null }), false);
});

Deno.test("mustClarifyFirstRound gates evidence-less partner first rounds (Batch A)", () => {
  const gated = {
    forceAnswer: false,
    scope: { type: "partner" },
    activeSessionTurns: [],
    recentMessages: [],
    conversationSummary: null,
    analysisSnapshot: null,
  };
  assertEquals(mustClarifyFirstRound(gated), true);
  // 逃生門與各種「已有個案證據」都放行。
  assertEquals(mustClarifyFirstRound({ ...gated, forceAnswer: true }), false);
  assertEquals(
    mustClarifyFirstRound({ ...gated, recentMessages: [{}] }),
    false,
  );
  assertEquals(
    mustClarifyFirstRound({
      ...gated,
      activeSessionTurns: [{ role: "coach", kind: "clarification" }],
    }),
    false,
  );
  assertEquals(
    mustClarifyFirstRound({ ...gated, conversationSummary: "上次聊到爬山" }),
    false,
  );
  assertEquals(
    mustClarifyFirstRound({ ...gated, analysisSnapshot: { stage: "曖昧" } }),
    false,
  );
});
