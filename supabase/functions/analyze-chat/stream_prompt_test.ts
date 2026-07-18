import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildStreamSystemPrompt } from "./stream_prompt.ts";

Deno.test("stream prompt wraps base prompt with JSONL event contract", () => {
  const prompt = buildStreamSystemPrompt("Base full reasoning prompt.");

  assert(prompt.includes("Base full reasoning prompt."));
  assert(prompt.includes("Return JSONL only"));
  assert(prompt.includes("one complete minified JSON object per line"));
  assert(prompt.includes("analysis.progress"));
  assert(prompt.includes("analysis.decision"));
  assert(prompt.includes("analysis.recommendation"));
  assert(prompt.includes("analysis.reply_option"));
  assert(prompt.includes("analysis.metrics"));
  assert(prompt.includes("analysis.coach_hint"));
  assert(prompt.includes("analysis.report_section"));
  assert(prompt.includes("analysis.done"));
  assert(prompt.includes("Emit exactly 5 `analysis.reply_option` events"));
  assert(prompt.includes("Low-investment rule for every option"));
  assert(prompt.includes("no pressure, guilt, or bids for reassurance"));
  assert(
    prompt.includes(
      "Complete all required `analysis.reply_option` events before any metrics, report sections, or done event.",
    ),
  );
  assert(
    prompt.includes(
      "Do not spend finalResult tokens duplicating the full five-style replyOptions",
    ),
  );
  assertEquals(
    prompt.includes(
      "analysis.done.finalResult.replies and `replyOptions` must include every allowed reply style",
    ),
    false,
  );
  assert(
    prompt.indexOf("analysis.decision") <
      prompt.indexOf("analysis.recommendation"),
  );
  // 球數案修法二：inventory 是 step 0，decision 改為 step 1（不再是「first」）。
  assert(prompt.includes("as soon as you know the next move"));
  assert(prompt.includes("analysis.progress` is optional after"));
  assert(prompt.includes("status/waiting copy only"));
  assert(prompt.includes("Do not include advice"));
  assert(prompt.includes("doThis"));
  assert(prompt.includes("avoidThis"));
  for (const style of ["extend", "resonate", "tease", "humor", "coldRead"]) {
    assert(prompt.includes(style));
  }
  assert(prompt.includes("Traditional Chinese"));
  assert(prompt.includes("Taiwan) only; never Simplified"));
  // v2 few-shot、硬版 compliance floor (b)＋callback (c)＋黑箱後選中風格強化 (b2)
  // 後再放寬，仍鎖上限防 contract 無限膨脹。
  // 2026-07-02 metrics 掛 gameStage（enum 值域必須全列，UI 對話進度卡破冰案）
  // 語意分群加入 接/併 的獨立球定義與對照範例，再放寬一檔。
  assert(prompt.length < 6200);
});

Deno.test("stream prompt trims the base prompt before appending contract", () => {
  const prompt = buildStreamSystemPrompt("  Base prompt.  ");

  assertEquals(
    prompt.startsWith("Base prompt.\n\n## Streaming Output Contract"),
    true,
  );
});

Deno.test("stream prompt can restrict reply styles for the active tier", () => {
  const prompt = buildStreamSystemPrompt("Base prompt.", ["extend"]);

  assert(
    prompt.includes("Use only these style values for this request: `extend`."),
  );
  assert(prompt.includes("Emit exactly 1 `analysis.reply_option` events"));
  assert(
    prompt.includes("Do not emit reply styles outside this request list."),
  );
  assertEquals(prompt.includes("`resonate`"), false);
  assertEquals(prompt.includes("`tease`"), false);
  assertEquals(prompt.includes("`humor`"), false);
  assertEquals(prompt.includes("`coldRead`"), false);
});

// ---------------------------------------------------------------------------
// 方案二件3 stream 協議 v2 — segments[] 一等公民 + 瘦 recommendation + few-shot
//
// #12 root cause：分段規格從未進事件協議（只在 finalResult 一句話帶過，又被
// compact 指令吃掉）。v2 把 segments 直接定義在 reply_option 事件上，模型不再
// 寫 flat message（D4，server join 合成相容欄位）、recommendation 不再帶回覆
// 全文（D2 瘦推薦卡，字只寫一次在 selected reply_option）。
// ---------------------------------------------------------------------------

Deno.test("v2: reply_option spec makes segments first-class, no flat message", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes("`segments`"));
  assert(prompt.includes("`sourceIndex`"));
  assert(prompt.includes("`sourceMessage`"));
  assert(prompt.includes("one segment per independent ball marked `接`"));
  assert(prompt.includes("Fold `併` context naturally"));
  assert(prompt.includes("never create a segment just to acknowledge a `併`"));
  assert(prompt.includes("Use stated/established facts only; never invent"));
  assert(prompt.includes('"next month" is not "first day promoted"'));
  assert(prompt.includes("segment sources must be balls marked `接`"));
  assert(prompt.includes("may incorporate related `併` context"));
  // D4：模型不寫 flat message，server join 合成。
  assert(prompt.includes("Do not write a flat `message` field"));
  // 舊規格殘骸不得留下：finalResult replySegments 條款與 max 3 cap。
  assertEquals(
    prompt.includes("finalResult.finalRecommendation.replySegments"),
    false,
  );
  assertEquals(prompt.includes("(max 3)"), false);
  // D1：cap 放寬到 5。
  assert(prompt.includes("up to 5"));
});

Deno.test("v2: recommendation event is thin (selectedStyle + reason + expectedReaction)", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes("`expectedReaction`"));
  // 瘦卡：不再要求 message/quotedContext 全文欄位。
  assertEquals(
    prompt.includes(
      "fields `selectedStyle`, `message`, `reason`, and `quotedContext`",
    ),
    false,
  );
  assert(prompt.includes("Do not repeat the reply text"));
});

Deno.test("v2: thin recommendation is explicitly required with its own few-shot", () => {
  // prod 黑箱 r1：瘦卡內容少到被模型視為可省略 → 整條 stream 沒出
  // recommendation。標 REQUIRED + 給 few-shot，與 reply_option 同款待遇。
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes("analysis.recommendation` is REQUIRED"));
  assert(prompt.includes('{"type":"analysis.recommendation"'));
  assert(prompt.includes('"expectedReaction"'));
});

Deno.test("v2: prompt carries a one-line multi-ball reply_option few-shot", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes('{"type":"analysis.reply_option"'));
  assert(prompt.includes('"segments":['));
  // few-shot 必須示範多球（≥2 段），單段範例會被模型當預設形狀。
  const example = prompt.slice(
    prompt.indexOf('{"type":"analysis.reply_option"'),
  );
  assertEquals(example.split('"sourceIndex"').length >= 3, true);
});

// ---------------------------------------------------------------------------
// 球數案修法二：盤點逼進輸出契約（軟版）— stream_prompt step 0 = analysis.inventory
//
// 黑箱根因：盤點寫在 reason（決策後才填的事後辯解欄）→ 模型先選球再補理由、
// 靜默吞球。修法＝把盤點做成「最先 emit、列全 N 球」的事件，autoregressive 上
// 強迫分類在選球之前。step 0 必須排在 analysis.decision 之前。
// ---------------------------------------------------------------------------

Deno.test("inventory: stream prompt emits analysis.inventory as step 0 before the decision", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes("analysis.inventory"));
  // 順序契約：盤點事件必須排在 decision 之前（autoregressive 強迫先分類後選球）。
  assert(
    prompt.indexOf("analysis.inventory") < prompt.indexOf("analysis.decision"),
    "inventory step must precede the decision step",
  );
  // 列全 N 球、寫進 inventory 事件而非只寫進 reason（堵事後辯解後門）。
  assert(prompt.includes("before you pick a style"));
  assert(prompt.includes("not only"));
});

Deno.test("inventory: stream prompt ships a 接/併/略 example inventory line", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes('{"type":"analysis.inventory"'));
  assert(prompt.includes('"disposition"'));
  // 範例必須示範三種處置，模型才知道 略 也要顯式列出（吞球的反面）。
  const example = prompt.slice(prompt.indexOf('{"type":"analysis.inventory"'));
  const head = example.slice(0, example.indexOf("\n"));
  assert(head.includes("接"));
  assert(head.includes("併"));
  assert(head.includes("略"));
});

// ---------------------------------------------------------------------------
// 球數案硬版：compliance prompt (b) ＋ callback 分類原則 (c)
//
// (b) reframer 已加 server 硬閘（段數下限＋略球擋），但閘是 guard 非 generator：
//     不告訴模型「會被退回」它仍只寫 2 段→只是把 reply 變 INCOMPLETE error。
//     prompt 必須宣告 server 強制下限，模型才上游服從而非被退。
// (c) golden msg1「只喜歡江果先」被誤判略：partnerSummary 顯示自造梗時，缺
//     背景的個人 callback 應順著接住，不判略。略只留給真的沒文字鉤的球。
// ---------------------------------------------------------------------------

Deno.test("compliance(b): prompt declares the server-enforced segment floor and 略-ball block", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes("Server-enforced floor"));
  assert(prompt.includes("min(3, number of independent balls marked 接)"));
  assert(
    prompt.includes(
      "A `併` line enriches a related segment but does not raise the floor",
    ),
  );
  // 明說不足/取略球會被退回重來，模型才知道要上游服從。
  assert(prompt.includes("rejects and forces a retry"));
  assert(prompt.includes("from a `略` ball"));
});

Deno.test("callback(c): prompt tells model not to mark a personal callback 略 for lack of backstory", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes("inside joke"));
  assert(prompt.includes("play along"));
  assert(
    prompt.includes("never mark it `略` only because you lack the backstory"),
  );
  // (c) 屬分類原則，須落在 inventory step（decision 之前）。
  assert(
    prompt.indexOf("never mark it `略` only because you lack the backstory") <
      prompt.indexOf("analysis.decision"),
    "callback principle must live in the inventory step",
  );
  // 略 可用於不需獨立回覆的承接、重複或背景細節，但不能因缺 backstory 略掉 callback。
  assert(
    prompt.includes(
      "acknowledgement, duplicate, or detail that needs no reply",
    ),
  );
});

Deno.test("compliance(b2): selected style covers independent balls without matching the longest alternative", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  // 黑箱實證：模型把「主打/選中」風格寫最短（coldRead/tease 2 段），非選中
  // 卻到 3 段 → 閘每跑退回選中風格。專打這個系統性偏差。
  assert(prompt.includes("does not need to match the longest alternative"));
  assert(prompt.includes("precision beats padding"));
});

Deno.test("metrics step requires gameStage with client enum values and context rule", () => {
  // 2026-07-02：stream 協議 v2 沒有事件承載 gameStage → UI 永遠破冰。
  // metrics 是 required 事件，stage 掛在這裡最可靠；值域必須點名 client enum。
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes("`analysis.metrics`"));
  assert(prompt.includes("gameStage"));
  for (
    const stage of [
      "opening",
      "premise",
      "qualification",
      "narrative",
      "close",
    ]
  ) {
    assert(prompt.includes(stage), `missing stage value ${stage}`);
  }
  for (
    const status of ["normal", "stuckFriend", "canAdvance", "shouldRetreat"]
  ) {
    assert(prompt.includes(status), `missing status value ${status}`);
  }
  assert(prompt.includes("認識場景"));
});
