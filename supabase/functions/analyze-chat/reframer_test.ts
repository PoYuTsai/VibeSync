import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  createStreamReframer,
  type StreamOutputEvent,
  type StreamRecommendationForCharge,
} from "./reframer.ts";

function line(value: Record<string, unknown>): string {
  return `${JSON.stringify(value)}\n`;
}

Deno.test("reframer emits recommendation only after charge succeeds", async () => {
  const timeline: string[] = [];
  const reframer = createStreamReframer({
    emit(event) {
      timeline.push(`emit:${event.type}`);
    },
    onRecommendation(recommendation) {
      timeline.push(`charge:${recommendation.selectedStyle}`);
      return { charged: true };
    },
  });

  reframer.pushText(line({
    type: "analysis.decision",
    selectedStyle: "resonate",
    label: "pressure check",
    nextStepBody: "Slow down first.",
    doThis: "Respect the boundary.",
    avoidThis: "Do not over-explain.",
  }));
  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "resonate",
    message: "I hear you. Let us slow down.",
    reason: "Matches the boundary.",
    quotedContext: "not too fast",
  }));

  await reframer.flush();

  assertEquals(timeline, [
    "charge:resonate",
    "emit:analysis.decision",
    "emit:analysis.recommendation",
    "emit:analysis.done",
  ]);
});

Deno.test("reframer stops stream when charge fails", async () => {
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return {
        charged: false,
        code: "STREAM_CHARGE_FAILED",
        message: "Quota update failed.",
      };
    },
  });

  reframer.pushText(line({
    type: "analysis.progress",
    label: "Claude progress should stay buffered.",
  }));
  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "extend",
    message: "Tell me more.",
    reason: "Keep it easy.",
    quotedContext: "hello",
  }));
  reframer.pushText(line({
    type: "analysis.progress",
    label: "should be ignored",
  }));

  await reframer.flush();

  assertEquals(events.map((event) => event.type), ["analysis.error"]);
  assertEquals(events[0].code, "STREAM_CHARGE_FAILED");
  assertEquals(
    events.some((event) => event.type === "analysis.progress"),
    false,
  );
});

Deno.test("reframer does not leak decision when decision charge fails", async () => {
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return {
        charged: false,
        code: "STREAM_CHARGE_FAILED",
        message: "Quota update failed.",
      };
    },
  });

  reframer.pushText(line({
    type: "analysis.decision",
    selectedStyle: "extend",
    nextStepBody: "This would be core coaching value.",
    doThis: "Send this calibrated move.",
    avoidThis: "Do not over-explain.",
  }));

  await reframer.flush();

  assertEquals(events.map((event) => event.type), ["analysis.error"]);
  assertEquals(events[0].code, "STREAM_CHARGE_FAILED");
});

Deno.test("reframer does not complete a cleanly ended decision-only stream", async () => {
  let chargeCalls = 0;
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      chargeCalls += 1;
      return { charged: true };
    },
  });

  reframer.pushText(line({
    type: "analysis.decision",
    selectedStyle: "extend",
    nextStepBody: "This is useful, but not a complete full analysis.",
    doThis: "Wait for the recommendation before completing.",
  }));

  await reframer.flush();

  assertEquals(chargeCalls, 1);
  assertEquals(events.map((event) => event.type), [
    "analysis.decision",
    "analysis.error",
  ]);
  assertEquals(events.at(-1)?.code, "STREAM_MISSING_COMPLETION_ANCHOR");
});

Deno.test("reframer never emits substantive events before charge", async () => {
  const timeline: string[] = [];
  const reframer = createStreamReframer({
    emit(event) {
      timeline.push(`emit:${event.type}`);
    },
    onRecommendation() {
      timeline.push("charge");
      return { charged: true };
    },
  });

  reframer.pushText(line({
    type: "analysis.progress",
    label: "Reading only.",
  }));
  reframer.pushText(line({
    type: "analysis.decision",
    selectedStyle: "tease",
    nextStepBody: "Buffered until charge.",
    doThis: "Send a short reply.",
  }));
  reframer.pushText(line({
    type: "analysis.reply_option",
    style: "tease",
    message: "Also buffered.",
  }));
  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "extend",
    message: "Tell me more.",
    reason: "Keep it easy.",
    quotedContext: "hello",
  }));

  await reframer.flush();

  assertEquals(timeline, [
    "charge",
    "emit:analysis.progress",
    "emit:analysis.decision",
    "emit:analysis.reply_option",
    "emit:analysis.recommendation",
    "emit:analysis.done",
  ]);
});

Deno.test("reframer charges only one official recommendation", async () => {
  let chargeCalls = 0;
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      chargeCalls += 1;
      return { charged: true };
    },
  });

  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "extend",
    message: "Tell me more about that.",
    reason: "Keeps the thread open.",
    quotedContext: "I had a long day.",
  }));
  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "tease",
    message: "Second official recommendation should not happen.",
    reason: "Duplicate anchor.",
    quotedContext: "I had a long day.",
  }));

  await reframer.flush();

  assertEquals(chargeCalls, 1);
  assertEquals(events.map((event) => event.type), [
    "analysis.recommendation",
    "analysis.error",
  ]);
  assertEquals(events.at(-1)?.code, "STREAM_DUPLICATE_RECOMMENDATION");
});

Deno.test("reframer skips duplicated resume decision after precharged decision", async () => {
  let chargeCalls = 0;
  const events: StreamOutputEvent[] = [];
  const prechargedDecision: StreamRecommendationForCharge = {
    selectedStyle: "resonate",
    message: "Acknowledge the pressure and slow the pace.",
    reason: "Respect the boundary.",
    quotedContext: "analysis.decision",
    warnings: [],
    raw: {
      type: "analysis.decision",
      selectedStyle: "resonate",
      nextStepBody: "Acknowledge the pressure and slow the pace.",
      doThis: "Respect the boundary.",
      avoidThis: "Do not push.",
    },
  };
  const reframer = createStreamReframer({
    prechargedRecommendation: prechargedDecision,
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      chargeCalls += 1;
      return { charged: true };
    },
  });

  reframer.pushText(line({
    type: "analysis.decision",
    selectedStyle: "resonate",
    nextStepBody: "Acknowledge the pressure and slow the pace.",
    doThis: "Respect the boundary.",
    avoidThis: "Do not push.",
  }));
  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "resonate",
    message: "I understand. We can go at your pace.",
    reason: "Respect the boundary.",
    quotedContext: "too fast",
  }));

  await reframer.flush();

  assertEquals(chargeCalls, 0);
  assertEquals(events.map((event) => event.type), [
    "analysis.recommendation",
    "analysis.done",
  ]);
});

Deno.test("reframer rejects malformed recommendation before charge", async () => {
  let chargeCalls = 0;
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      chargeCalls += 1;
      return { charged: true };
    },
  });

  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "extend",
    message: "",
    reason: "Empty message should fail.",
    quotedContext: "hello",
  }));

  await reframer.flush();

  assertEquals(chargeCalls, 0);
  assertEquals(events.map((event) => event.type), ["analysis.error"]);
  assertEquals(events[0].code, "STREAM_MALFORMED_RECOMMENDATION");
});

Deno.test("reframer parses a line split across chunks", async () => {
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  const payload = line({
    type: "analysis.progress",
    label: "Reading the chat.",
  });

  reframer.pushText(payload.slice(0, 18));
  assertEquals(events.length, 0);
  reframer.pushText(payload.slice(18));
  await reframer.flush();

  assertEquals(events.map((event) => event.type), [
    "analysis.error",
  ]);
  assertEquals(events.at(-1)?.code, "STREAM_MISSING_CHARGE_ANCHOR");
});

Deno.test("reframer assembles a legacy-compatible final result", async () => {
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(line({
    type: "analysis.decision",
    selectedStyle: "resonate",
    nextStepBody: "Acknowledge the pressure and slow the pace.",
    doThis: "Respect the boundary.",
  }));
  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "resonate",
    message: "I understand. We can go at your pace.",
    reason: "Respect the boundary.",
    quotedContext: "too fast",
  }));
  reframer.pushText(line({
    type: "analysis.reply_option",
    style: "tease",
    message: "Then I will slow down before I get a speeding ticket.",
    reason: "Light joke.",
  }));
  reframer.pushText(line({
    type: "analysis.metrics",
    heat: 25,
    topicDepth: {
      current: "boundary",
      suggestion: "Do not push.",
    },
  }));
  reframer.pushText(line({
    type: "analysis.report_section",
    section: "strategy",
    content: "Back off and rebuild trust.",
  }));
  reframer.pushText(line({ type: "analysis.done" }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done);
  const finalResult = done.finalResult as Record<string, unknown>;
  const replies = finalResult.replies as Record<string, unknown>;
  const finalRecommendation = finalResult.finalRecommendation as Record<
    string,
    unknown
  >;
  const gameStage = finalResult.gameStage as Record<string, unknown>;
  const enthusiasm = finalResult.enthusiasm as Record<string, unknown>;
  const topicDepth = finalResult.topicDepth as Record<string, unknown>;

  assertEquals(replies.resonate, "I understand. We can go at your pace.");
  assertEquals(
    replies.tease,
    "Then I will slow down before I get a speeding ticket.",
  );
  assertEquals(finalRecommendation.pick, "resonate");
  assertEquals(
    gameStage.nextStep,
    "Acknowledge the pressure and slow the pace.",
  );
  assertEquals(enthusiasm.score, 25);
  assertEquals(topicDepth.current, "boundary");
  assertEquals(finalResult.strategy, "Back off and rebuild trust.");
});

Deno.test("reframer emits synthetic done when model omits done event", async () => {
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "humor",
    message: "I will slow down before I get a ticket.",
    reason: "Softens the pressure.",
    quotedContext: "too fast",
  }));

  await reframer.flush();

  assertEquals(events.map((event) => event.type), [
    "analysis.recommendation",
    "analysis.done",
  ]);
});

Deno.test("reframer rejects paid completion when four reply styles are missing", async () => {
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    requiredReplyStyles: ["extend", "resonate", "tease", "humor", "coldRead"],
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "resonate",
    message: "I get why that felt off.",
    reason: "Respect the boundary.",
    quotedContext: "too fast",
  }));
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      replies: {
        resonate: "I get why that felt off.",
      },
      replyOptions: {
        resonate: {
          approach: "Respect the boundary.",
          messages: [{ reply: "I get why that felt off." }],
        },
      },
      finalRecommendation: {
        pick: "resonate",
        content: "I get why that felt off.",
      },
    },
  }));

  await reframer.flush();

  assertEquals(events.map((event) => event.type), [
    "analysis.recommendation",
    "analysis.error",
  ]);
  assertEquals(events.at(-1)?.code, "STREAM_INCOMPLETE_REPLY_OPTIONS");
  assertEquals(events.at(-1)?.missingStyles, [
    "extend",
    "tease",
    "humor",
    "coldRead",
  ]);
});

Deno.test("reframer absorbs segmented reply options without top-level message", async () => {
  // 2026-06-12 P0：#12 一球一回 prompt 下，多球對話的 reply_option 事件
  // 只帶 messages 段落陣列、無頂層 message 字串。absorb 必須回退到
  // segments，否則五風格全被丟棄 → STREAM_INCOMPLETE_REPLY_OPTIONS。
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    requiredReplyStyles: ["extend", "resonate", "tease", "humor", "coldRead"],
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "resonate",
    message: "到家啦，今天辛苦了",
    reason: "接住到家訊號",
    quotedContext: "到家 🤙🤙🤙",
  }));
  for (const style of ["resonate", "extend", "tease", "humor", "coldRead"]) {
    reframer.pushText(line({
      type: "analysis.reply_option",
      style,
      approach: `${style} approach`,
      quotedContext: "到家 🤙🤙🤙",
      messages: [
        {
          sourceIndex: 4,
          label: "接到家",
          sourceMessage: "到家 🤙🤙🤙",
          reply: `${style} 段落一`,
          reason: "接住到家",
        },
        {
          sourceIndex: 2,
          label: "接晚餐",
          sourceMessage: "茄汁牛肉飯",
          reply: `${style} 段落二`,
          reason: "順接晚餐",
        },
      ],
    }));
  }

  await reframer.flush();

  assertEquals(events.at(-1)?.type, "analysis.done");
  const finalResult = events.at(-1)?.finalResult as Record<string, unknown>;
  const replies = finalResult.replies as Record<string, unknown>;
  assertEquals(replies.tease, "tease 段落一\ntease 段落二");
  const replyOptions = finalResult.replyOptions as Record<
    string,
    { approach: string; messages: Record<string, unknown>[] }
  >;
  for (const style of ["extend", "tease", "humor", "coldRead"]) {
    assertEquals(replyOptions[style].messages.length, 2);
    assertEquals(
      replyOptions[style].messages[1].sourceMessage,
      "茄汁牛肉飯",
    );
  }
  // 官方 recommendation（resonate）後到的同風格 reply_option 段落版要能
  // 覆蓋成完整段落，但 finalRecommendation 的 pick 不變。
  const finalRecommendation = finalResult.finalRecommendation as Record<
    string,
    unknown
  >;
  assertEquals(finalRecommendation.pick, "resonate");
});

// ---------------------------------------------------------------------------
// 方案二件4 — Bind 扣卡回填（D2 瘦推薦卡 + D3 契約凍結 + D4 server join）
//
// v2 模型輸出：瘦 recommendation（無 message、帶 expectedReaction）→
// reply_option[selected]（segments 一等公民）→ 其餘風格。reframer 把瘦卡
// buffer 住，等 selected reply_option 到貨後 join 全文回填，再按今天的
// 順序轉發——App 收到的事件順序與形狀不變。
// ---------------------------------------------------------------------------

const V2_STYLES = ["extend", "resonate", "tease", "humor", "coldRead"] as const;

function v2ReplyOption(style: string): Record<string, unknown> {
  return {
    type: "analysis.reply_option",
    style,
    reason: `${style} approach`,
    segments: [
      {
        sourceIndex: 1,
        sourceMessage: "剛來吃晚餐",
        reply: `${style} 段落一`,
        reason: "接晚餐球",
      },
      {
        sourceIndex: 2,
        sourceMessage: "等等要去樂華夜市",
        reply: `${style} 段落二`,
        reason: "延伸夜市話題",
      },
    ],
  };
}

const V2_THIN_RECOMMENDATION = {
  type: "analysis.recommendation",
  selectedStyle: "extend",
  reason: "兩顆球都接住才有互動感",
  expectedReaction: "她大概會分享夜市買了什麼",
};

const V2_DECISION = {
  type: "analysis.decision",
  selectedStyle: "extend",
  nextStepBody: "接住晚餐與夜市兩顆球。",
  doThis: "兩段都回。",
  avoidThis: "不要只回一句。",
};

Deno.test("bind: thin recommendation buffers until selected reply_option backfills it", async () => {
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    requiredReplyStyles: [...V2_STYLES],
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(line(V2_DECISION));
  reframer.pushText(line(V2_THIN_RECOMMENDATION));
  for (const style of V2_STYLES) {
    reframer.pushText(line(v2ReplyOption(style)));
  }
  reframer.pushText(line({ type: "analysis.done" }));
  await reframer.flush();

  // D3 契約凍結：client 看到的順序與今天相同。
  assertEquals(events.map((event) => event.type), [
    "analysis.decision",
    "analysis.recommendation",
    "analysis.reply_option",
    "analysis.reply_option",
    "analysis.reply_option",
    "analysis.reply_option",
    "analysis.reply_option",
    "analysis.done",
  ]);

  const recommendation = events[1] as Record<string, unknown>;
  assertEquals(recommendation.selectedStyle, "extend");
  // 回填：join 後全文 + 原始段落陣列。
  assertEquals(recommendation.message, "extend 段落一\nextend 段落二");
  assertEquals((recommendation.replySegments as unknown[]).length, 2);

  // D4 相容欄位：reply_option 的 flat message 由 server join 合成。
  const selectedOption = events[2] as Record<string, unknown>;
  assertEquals(selectedOption.style, "extend");
  assertEquals(selectedOption.message, "extend 段落一\nextend 段落二");

  // 廢除雙軌：finalRecommendation 從 selected reply_option 回填。
  const finalResult = (events.at(-1) as Record<string, unknown>)
    .finalResult as Record<string, unknown>;
  const finalRecommendation = finalResult.finalRecommendation as Record<
    string,
    unknown
  >;
  assertEquals(finalRecommendation.pick, "extend");
  assertEquals(finalRecommendation.content, "extend 段落一\nextend 段落二");
  assertEquals((finalRecommendation.replySegments as unknown[]).length, 2);
});

Deno.test("bind: missing selected reply_option fails INCOMPLETE, never a silent done", async () => {
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    requiredReplyStyles: [...V2_STYLES],
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(line(V2_DECISION));
  reframer.pushText(line(V2_THIN_RECOMMENDATION));
  for (const style of V2_STYLES.filter((s) => s !== "extend")) {
    reframer.pushText(line(v2ReplyOption(style)));
  }
  // 模型雙軌殘骸：finalResult 塞滿五風格也不得讓瘦卡靜默消失。
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      replies: Object.fromEntries(V2_STYLES.map((s) => [s, `${s} 假全文`])),
      finalRecommendation: { pick: "extend", content: "extend 假全文" },
    },
  }));
  await reframer.flush();

  assertEquals(events.at(-1)?.type, "analysis.error");
  assertEquals(events.at(-1)?.code, "STREAM_INCOMPLETE_REPLY_OPTIONS");
  assert(
    (events.at(-1)?.missingStyles as string[]).includes("extend"),
  );
  assertEquals(events.some((event) => event.type === "analysis.done"), false);
  assertEquals(
    events.some((event) => event.type === "analysis.recommendation"),
    false,
  );
});

Deno.test("bind: unsafe joined reply text fails hard safety after backfill", async () => {
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    requiredReplyStyles: ["extend"],
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(line(V2_DECISION));
  reframer.pushText(line(V2_THIN_RECOMMENDATION));
  reframer.pushText(line({
    type: "analysis.reply_option",
    style: "extend",
    reason: "extend approach",
    segments: [
      {
        sourceIndex: 1,
        sourceMessage: "她說晚安",
        reply: "Follow her home and pressure her until she replies.",
        reason: "unsafe",
      },
    ],
  }));
  await reframer.flush();

  assertEquals(events.at(-1)?.type, "analysis.error");
  assertEquals(events.at(-1)?.code, "STREAM_UNSAFE_RECOMMENDATION");
  assertEquals(
    events.some((event) => event.type === "analysis.recommendation"),
    false,
  );
});

Deno.test("bind: thin recommendation charge flushes buffered reply_option through bind", async () => {
  // 模型亂序（reply_option 先於 recommendation、且無 decision）：
  // 瘦卡扣費成功後 flush pre-charge buffer，selected option 仍要綁卡。
  const timeline: string[] = [];
  const emitted: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    requiredReplyStyles: ["extend"],
    emit(event) {
      timeline.push(`emit:${event.type}`);
      emitted.push(event);
    },
    onRecommendation(recommendation) {
      timeline.push(`charge:${recommendation.selectedStyle}`);
      return { charged: true };
    },
  });

  reframer.pushText(line(v2ReplyOption("extend")));
  reframer.pushText(line(V2_THIN_RECOMMENDATION));
  reframer.pushText(line({ type: "analysis.done" }));
  await reframer.flush();

  assertEquals(timeline, [
    "charge:extend",
    "emit:analysis.recommendation",
    "emit:analysis.reply_option",
    "emit:analysis.done",
  ]);
  const recommendation = emitted[0] as Record<string, unknown>;
  assertEquals(recommendation.message, "extend 段落一\nextend 段落二");
});

Deno.test("bind: model finalResult cannot clobber the bound finalRecommendation", async () => {
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    requiredReplyStyles: ["extend"],
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(line(V2_DECISION));
  reframer.pushText(line(V2_THIN_RECOMMENDATION));
  reframer.pushText(line(v2ReplyOption("extend")));
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      strategy: "model 補充的策略",
      finalRecommendation: { pick: "extend", content: "模型亂寫的合併單句" },
    },
  }));
  await reframer.flush();

  const finalResult = (events.at(-1) as Record<string, unknown>)
    .finalResult as Record<string, unknown>;
  // 其他欄位照常 merge；finalRecommendation 以 bind 結果為權威。
  assertEquals(finalResult.strategy, "model 補充的策略");
  const finalRecommendation = finalResult.finalRecommendation as Record<
    string,
    unknown
  >;
  assertEquals(finalRecommendation.content, "extend 段落一\nextend 段落二");
  assertEquals((finalRecommendation.replySegments as unknown[]).length, 2);
});

Deno.test("bind: late thin recommendation after its reply_option still backfills", async () => {
  // prod 黑箱 r1 發現：模型可能亂序或晚出瘦卡。option 先過、瘦卡後到，
  // 也要立刻綁卡回填（rec 事件晚於 option 屬可接受的順序偏移）。
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    requiredReplyStyles: ["extend"],
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(line(V2_DECISION));
  reframer.pushText(line(v2ReplyOption("extend")));
  reframer.pushText(line(V2_THIN_RECOMMENDATION));
  reframer.pushText(line({ type: "analysis.done" }));
  await reframer.flush();

  const recommendation = events.find(
    (event) => event.type === "analysis.recommendation",
  ) as Record<string, unknown>;
  assert(recommendation);
  assertEquals(recommendation.message, "extend 段落一\nextend 段落二");
  assertEquals(events.at(-1)?.type, "analysis.done");
});

Deno.test("bind: omitted recommendation synthesized from decision + selected reply_option", async () => {
  // prod 黑箱 r1 實測：模型整條 stream 沒出 recommendation 事件（瘦卡被
  // 視為與 decision 重複而省略）。decision 已扣費、selected style 的
  // option 有完整內容 → 合成推薦卡，不準把整次分析打成錯誤。
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    requiredReplyStyles: ["extend"],
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(line(V2_DECISION));
  reframer.pushText(line(v2ReplyOption("extend")));
  reframer.pushText(line({ type: "analysis.done" }));
  await reframer.flush();

  const recommendation = events.find(
    (event) => event.type === "analysis.recommendation",
  ) as Record<string, unknown>;
  assert(recommendation);
  assertEquals(recommendation.selectedStyle, "extend");
  assertEquals(recommendation.message, "extend 段落一\nextend 段落二");
  assertEquals(events.at(-1)?.type, "analysis.done");
  const finalResult = (events.at(-1) as Record<string, unknown>)
    .finalResult as Record<string, unknown>;
  assertEquals(
    (finalResult.finalRecommendation as Record<string, unknown>).pick,
    "extend",
  );
});

Deno.test("bind: omitted recommendation without matching option still errors", async () => {
  // 合成的前提是 selected style 的 option 真的有貨；都沒有就維持既有
  // MISSING_COMPLETION_ANCHOR（不能無中生有推薦卡）。
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    requiredReplyStyles: ["extend"],
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(line(V2_DECISION));
  await reframer.flush();

  assertEquals(events.at(-1)?.type, "analysis.error");
  assertEquals(events.at(-1)?.code, "STREAM_MISSING_COMPLETION_ANCHOR");
});

Deno.test("bind: resume with thin precharged recommendation rebinds from replayed stream", async () => {
  let chargeCalls = 0;
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    prechargedRecommendation: {
      selectedStyle: "extend",
      message: "",
      reason: "兩顆球都接住才有互動感",
      quotedContext: "",
      warnings: [],
      raw: V2_THIN_RECOMMENDATION,
    },
    requiredReplyStyles: ["extend"],
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      chargeCalls += 1;
      return { charged: true };
    },
  });

  reframer.pushText(line(V2_DECISION));
  reframer.pushText(line(V2_THIN_RECOMMENDATION));
  reframer.pushText(line(v2ReplyOption("extend")));
  reframer.pushText(line({ type: "analysis.done" }));
  await reframer.flush();

  assertEquals(chargeCalls, 0);
  const recommendation = events.find(
    (event) => event.type === "analysis.recommendation",
  ) as Record<string, unknown>;
  assert(recommendation);
  assertEquals(recommendation.message, "extend 段落一\nextend 段落二");
  assertEquals(events.at(-1)?.type, "analysis.done");
});

Deno.test("bind: corrupt thin precharged card still rebinds from replayed stream", async () => {
  // 防禦路徑：存進 ledger 的瘦卡 resume 時 revalidation 失敗（理論上扣費
  // 時已驗過，僅防 ledger 損壞）——不得讓 officialRecommendationEmitted
  // 卡成 true 而靜默完成；replay 的瘦卡要能重新掛 pending 綁卡。
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    prechargedRecommendation: {
      selectedStyle: "extend",
      message: "",
      reason: "",
      quotedContext: "",
      warnings: [],
      raw: {
        type: "analysis.recommendation",
        selectedStyle: "extend",
        reason: "", // 缺 reason → revalidation 失敗
        expectedReaction: "她大概會回",
      },
    },
    requiredReplyStyles: ["extend"],
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(line(V2_DECISION));
  reframer.pushText(line(V2_THIN_RECOMMENDATION));
  reframer.pushText(line(v2ReplyOption("extend")));
  reframer.pushText(line({ type: "analysis.done" }));
  await reframer.flush();

  const recommendation = events.find(
    (event) => event.type === "analysis.recommendation",
  ) as Record<string, unknown>;
  assert(recommendation);
  assertEquals(recommendation.message, "extend 段落一\nextend 段落二");
  assertEquals(events.at(-1)?.type, "analysis.done");
});

Deno.test("reframer filters reply options outside the active tier", async () => {
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    requiredReplyStyles: ["extend"],
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "extend",
    message: "Tell me more about that.",
    reason: "Keeps the thread open.",
    quotedContext: "long day",
  }));
  reframer.pushText(line({
    type: "analysis.reply_option",
    style: "tease",
    message: "This paid style must not stream to a Free user.",
    reason: "Unauthorized style.",
  }));
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      replies: {
        extend: "Tell me more about that.",
      },
      finalRecommendation: {
        pick: "extend",
        content: "Tell me more about that.",
      },
    },
  }));

  await reframer.flush();

  assertEquals(events.map((event) => event.type), [
    "analysis.recommendation",
    "analysis.done",
  ]);
  assertEquals(
    events.some((event) => event.type === "analysis.reply_option"),
    false,
  );
});

Deno.test("reframer accepts analysis.done result alias", async () => {
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "resonate",
    message: "I get why that felt off.",
    reason: "Respect the boundary.",
    quotedContext: "too fast",
  }));
  reframer.pushText(line({
    type: "analysis.done",
    result: {
      strategy: "Back off and rebuild trust.",
      finalRecommendation: {
        pick: "resonate",
        content: "I get why that felt off.",
      },
    },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done);
  const finalResult = done.finalResult as Record<string, unknown>;

  assertEquals(finalResult.strategy, "Back off and rebuild trust.");
  assertEquals(finalResult.finalRecommendation, {
    pick: "resonate",
    content: "I get why that felt off.",
  });
});

Deno.test("reframer ignores malformed trailing text on flush", async () => {
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(line({
    type: "analysis.progress",
    label: "valid",
  }));
  reframer.pushText("{not-json");

  await reframer.flush();

  assertEquals(events.map((event) => event.type), [
    "analysis.error",
  ]);
  assertEquals(events.at(-1)?.code, "STREAM_MISSING_CHARGE_ANCHOR");
});
