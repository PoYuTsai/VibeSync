import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildStagePriorSection,
  buildStreamSystemPrompt,
  LATEST_ANALYSIS_FRAGMENT_MARKER,
  markLatestAnalysisFragment,
  normalizeStagePrior,
} from "./stream_prompt.ts";

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
  // inventory is step 0; decision follows as soon as the next move is known.
  assert(prompt.includes("as soon as the next move is known"));
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
  assert(prompt.includes("`stretchLevel`"));
  assert(prompt.includes("within"));
  assert(prompt.includes("`stretch`"));
  assert(prompt.includes("too large a jump"));
  // Keep the transport contract bounded; runtime prompt-size coverage is tested
  // against the legacy prompt in analyze_prompt_v2_test.ts.
  assert(prompt.length < 6800);
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
// Stream contract observables: segmented reply options, thin recommendation,
// exact style coverage, and no content-like few-shot payloads.
// ---------------------------------------------------------------------------

Deno.test("v2: reply_option spec makes segments first-class, no flat message", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes("`segments`"));
  assert(prompt.includes("`sourceIndex`"));
  assert(prompt.includes("`sourceMessage`"));
  assert(prompt.includes("independent conversational moves"));
  assert(prompt.includes("Fold `併` context into its related `接`"));
  assert(prompt.includes("never create a segment for `併` or `略`"));
  assert(prompt.includes("Use stated/established facts only; never invent"));
  assert(prompt.includes("exact same sourceIndex/sourceMessage set, order, and count"));
  // D4：模型不寫 flat message，server join 合成。
  assert(prompt.includes("Do not write a flat `message` field"));
  // Legacy content-like examples and the old three-segment cap must stay out.
  assertEquals(
    prompt.includes("finalResult.finalRecommendation.replySegments"),
    false,
  );
  assertEquals(prompt.includes("(max 3)"), false);
  // Segment cap is observable without inventing a minimum.
  assert(prompt.includes("at most 5"));
  assert(prompt.includes("There is no minimum of 3"));
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
  assert(prompt.includes("Do not repeat reply text here"));
});

Deno.test("v2: thin recommendation is explicitly required without a few-shot", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes("`analysis.recommendation` once, thin"));
  assert(prompt.includes("This event is REQUIRED"));
  assert(prompt.includes("`expectedReaction`"));
  assertEquals(prompt.includes('{"type":"analysis.recommendation"'), false);
});

Deno.test("v2: stream contract carries no content-like reply examples", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assertEquals(prompt.includes('{"type":"analysis.reply_option"'), false);
  assertEquals(prompt.includes('{"type":"analysis.recommendation"'), false);
  assertEquals(prompt.includes("完整範例"), false);
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
  assert(prompt.includes("before choosing a style"));
  assert(prompt.includes("Latest Analysis Fragment"));
});

Deno.test("inventory: stream prompt names the 接/併/略 event fields", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes("analysis.inventory` first"));
  assert(prompt.includes("`disposition`"));
  assert(prompt.includes("(`接`/`併`/`略`)"));
  assert(prompt.includes("Each item needs 1-based `sourceIndex`"));
  assertEquals(prompt.includes('{"type":"analysis.inventory"'), false);
});

// ---------------------------------------------------------------------------
// Exact source coverage and fail-soft semantics.
// ---------------------------------------------------------------------------

Deno.test("coverage contract: no minimum floor or retry language", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes("Runtime coverage validation is fail-soft and log-only"));
  assert(prompt.includes("exact source coverage is the quality signal"));
  assert(prompt.includes("There is no minimum of 3"));
  assertEquals(prompt.includes("Server-enforced floor"), false);
  assertEquals(prompt.includes("rejects and forces a retry"), false);
});

Deno.test("coverage contract: source disposition remains explicit", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes("Group by independent conversational move"));
  assert(prompt.includes("`併` enriches a related `接`"));
  assert(prompt.includes("`略` needs no reply"));
  assert(prompt.includes("Never use earlier messages, conversationSummary, or partnerSummary as a ball/sourceMessage"));
});

Deno.test("coverage contract: every style uses the same authored source coverage", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes("exact same sourceIndex/sourceMessage set, order, and count"));
  assert(prompt.includes("the set must not change with style"));
  assert(prompt.includes("selected style first"));
  assert(prompt.includes("Do not emit reply styles outside this request list."));
});

Deno.test("coverage contract: short options are valid when they match independent moves", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  assert(prompt.includes("usually 1–3 and at most 5"));
  assert(prompt.includes("There is no minimum of 3"));
  assert(prompt.includes("Never split one move into filler segments"));
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

Deno.test("metrics, coach hint, and report sections name their payload contracts", () => {
  const prompt = buildStreamSystemPrompt("BASE");
  const metricsStart = prompt.indexOf("`analysis.metrics`");
  const coachStart = prompt.indexOf("`analysis.coach_hint`");
  const reportStart = prompt.indexOf("`analysis.report_section`");
  const doneStart = prompt.indexOf("`analysis.done`");
  assert(metricsStart >= 0 && coachStart > metricsStart);
  assert(coachStart >= 0 && reportStart > coachStart);
  assert(reportStart >= 0 && doneStart > reportStart);

  const metrics = prompt.slice(metricsStart, coachStart);
  assert(metrics.includes("enthusiasm"));
  assert(metrics.includes("score"));
  assert(metrics.includes("level"));
  assert(metrics.includes("dimensions"));
  for (const key of [
    "heat",
    "engagement",
    "topicDepth",
    "replyWillingness",
    "emotionalConnection",
    "gameStage",
    "current",
    "suggestion",
    "status",
    "nextStep",
  ]) {
    assert(metrics.includes(key), `metrics missing ${key}`);
  }

  const coach = prompt.slice(coachStart, reportStart);
  for (const key of [
    "coachActionHint",
    "catchablePoint",
    "read",
    "microMove",
    "avoid",
    "actionType",
    "confidence",
  ]) {
    assert(coach.includes(key), `coach hint missing ${key}`);
  }

  const report = prompt.slice(reportStart, doneStart);
  for (const key of [
    "section",
    "payload",
    "psychology",
    "strategy",
    "reminder",
    "targetProfile",
    "healthCheck",
    "issues",
    "suggestions",
    "empty arrays",
  ]) {
    assert(report.includes(key), `report section missing ${key}`);
  }

  const done = prompt.slice(doneStart);
  for (const key of [
    "finalResult",
    "scenarioDetected",
    "warnings",
    "legacy-compatible",
  ]) {
    assert(done.includes(key), `done payload missing ${key}`);
  }
});

Deno.test("stage prior section: legal stage renders weak-prior block, junk renders nothing", () => {
  // 跨次連續性 seam：上次有效階段是弱先驗，隨片段送入；非法值絕不偽造。
  const section = buildStagePriorSection("qualification");
  assert(section.includes("## Stage Continuity"));
  assert(section.includes("qualification"));
  assert(section.includes("Weak prior only"));

  assertEquals(buildStagePriorSection(undefined), "");
  assertEquals(buildStagePriorSection(null), "");
  assertEquals(buildStagePriorSection(""), "");
  assertEquals(buildStagePriorSection("vibing hard"), "");
  assertEquals(buildStagePriorSection("Opening"), "");
  assertEquals(buildStagePriorSection(42), "");
  assertEquals(normalizeStagePrior(" qualification "), "qualification");
  assertEquals(normalizeStagePrior("Opening"), null);
});

Deno.test("latest fragment marker is inserted at the exact message boundary", () => {
  const marked = markLatestAnalysisFragment(
    ["Her: old", "Me: reply", "Her: new 1", "Her: new 2"],
    2,
  ).split("\n");

  assertEquals(marked[2], LATEST_ANALYSIS_FRAGMENT_MARKER);
  assertEquals(marked.slice(3), ["Her: new 1", "Her: new 2"]);
  assertEquals(markLatestAnalysisFragment([], 0), "");
});

Deno.test("system prompt carries the weak-prior rule and the partner-context boundary", () => {
  const prompt = buildStreamSystemPrompt("BASE");

  // 弱先驗：模糊證據保留、強證據可跳／可回退，不是下限。
  assert(prompt.includes("Stage Continuity"));
  assert(prompt.includes("weak prior"));
  // 關於她 chips（Partner Context）邊界：可調節奏／話題／可行性，
  // 不可直接改分、改 stage、不是她本輪原話、不替低投入找藉口。
  assert(prompt.includes("Partner Context only tunes advice"));
  assert(prompt.includes("never changes score/stage"));
  assert(prompt.includes("excuses low investment"));
  // 投入度只看最新片段中她的可觀察投入；舊內容與上次分數不直接進分。
  assert(prompt.includes("messages after Latest Analysis Fragment"));
  assert(prompt.includes("history/previous score only disambiguate"));
  assert(prompt.includes("never add points"));
  assert(
    prompt.includes(
      "Never use earlier messages, conversationSummary, or partnerSummary as a ball/sourceMessage",
    ),
  );
});

Deno.test("metrics step carries the five-stage criteria and the opening guard", () => {
  // 對象卡互動階段閉環：五階段判準與 opening 正面證據 guard 必須存在於
  // stream prompt（Edge 分類契約 seam）。
  const prompt = buildStreamSystemPrompt("BASE");

  // opening 需要正面證據；缺值、短訊息、普通問候不得判成 opening。
  assert(prompt.includes("`opening` only for true first contact"));
  assert(prompt.includes("explicit reconnect after material silence/conflict"));
  assert(prompt.includes("not missing data, a greeting, or one short reply"));
  // close 必須有本次可落地的邀約／安排證據，不由伴侶標籤或用戶目標觸發。
  assert(
    prompt.includes(
      "`close` needs current reciprocal invite/scheduling, never a partner label/goal",
    ),
  );
  // narrative 不是中間預設值。
  assert(prompt.includes("`narrative` is never a default"));
  // 前次 stage／歷史是連續性證據，但本次訊息是主要證據。
  assert(prompt.includes("current evidence beats Stage Continuity"));
  // 混合證據有唯一優先順序；Topic Depth 的循序漸進只約束回覆升級，
  // 不得被誤讀成 stage 不可跳轉或回退。
  assert(
    prompt.includes(
      "close scheduling > qualification fit/boundary > narrative story/emotion > premise mutual romantic/playful tension > opening",
    ),
  );
  assert(prompt.includes("Stage may skip/retreat"));
  assert(prompt.includes("Topic Depth limits reply escalation, not stage"));
});
