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

Deno.test("done merge coerces string gameStage/psychology into client-parseable records", async () => {
  // 2026-06-13 dogfood P0：Haiku（free tier）常把 finalResult 的 gameStage/
  // psychology 寫成字串，Sonnet 偶發。client AnalysisResult.fromJson 對這些
  // key 是硬 cast Map，字串會 throw INVALID_STREAM_RESULT——形狀守門必須在
  // server 端 merge 時擋下，不能原樣 clobber assembler 的物件預設值。
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
    nextStepBody: "Keep the pace she set.",
  }));
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
      gameStage: "premise",
      psychology: "She is testing availability, answer light.",
      topicDepth: "facts",
      enthusiasm: 72,
    },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;

  const gameStage = finalResult.gameStage as Record<string, unknown>;
  assertEquals(typeof finalResult.gameStage, "object");
  assertEquals(gameStage.current, "premise");
  assertEquals(gameStage.nextStep, "Keep the pace she set.");

  const psychology = finalResult.psychology as Record<string, unknown>;
  assertEquals(typeof finalResult.psychology, "object");
  assertEquals(
    psychology.subtext,
    "She is testing availability, answer light.",
  );

  const topicDepth = finalResult.topicDepth as Record<string, unknown>;
  assertEquals(typeof finalResult.topicDepth, "object");
  assertEquals(topicDepth.current, "facts");

  const enthusiasm = finalResult.enthusiasm as Record<string, unknown>;
  assertEquals(typeof finalResult.enthusiasm, "object");
  assertEquals(enthusiasm.score, 72);
});

Deno.test("done merge drops non-record values for record-only client keys", async () => {
  // replies/replyOptions/finalRecommendation/usage/targetProfile 在 client
  // 也是硬 cast Map——模型亂寫字串時保留 assembler 既有值，不得 clobber。
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
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      replies: "humor: I will slow down before I get a ticket.",
      replyOptions: "see replies",
      finalRecommendation: "use humor",
      usage: "n/a",
      targetProfile: "unknown",
    },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;

  assertEquals(typeof finalResult.replies, "object");
  const replies = finalResult.replies as Record<string, unknown>;
  assertEquals(replies.humor, "I will slow down before I get a ticket.");
  assertEquals(typeof finalResult.replyOptions, "object");
  assertEquals(typeof finalResult.finalRecommendation, "object");
  const finalRecommendation = finalResult.finalRecommendation as Record<
    string,
    unknown
  >;
  assertEquals(finalRecommendation.pick, "humor");
  assert(!("usage" in finalResult) || typeof finalResult.usage === "object");
  assert(
    !("targetProfile" in finalResult) ||
      typeof finalResult.targetProfile === "object",
  );
});

Deno.test("report_section string payload for client-shaped sections coerces instead of clobbering", async () => {
  // 2026-06-13 queue 補強（Codex adversarial high 1）：absorbReportSection
  // 原樣寫 result[section]，section=gameStage/psychology 等且 payload 為
  // 字串可繞過 done merge 守門——同一個 result 物件的另一條寫入路徑，
  // 必須走同一套 coerce。
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
    type: "analysis.report_section",
    section: "gameStage",
    payload: "premise",
  }));
  reframer.pushText(line({
    type: "analysis.report_section",
    section: "psychology",
    payload: "She is testing availability.",
  }));
  reframer.pushText(line({
    type: "analysis.report_section",
    section: "warnings",
    payload: "別連發訊息",
  }));
  reframer.pushText(line({
    type: "analysis.report_section",
    section: "enthusiasm",
    payload: 90.4,
  }));
  reframer.pushText(line({ type: "analysis.done", finalResult: {} }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;

  assertEquals(typeof finalResult.gameStage, "object");
  assertEquals(
    (finalResult.gameStage as Record<string, unknown>).current,
    "premise",
  );
  assertEquals(typeof finalResult.psychology, "object");
  assertEquals(
    (finalResult.psychology as Record<string, unknown>).subtext,
    "She is testing availability.",
  );
  assertEquals(finalResult.warnings, ["別連發訊息"]);
  assertEquals(typeof finalResult.enthusiasm, "object");
  assertEquals(
    (finalResult.enthusiasm as Record<string, unknown>).score,
    90,
  );
});

Deno.test("done merge guards warnings as array-only", async () => {
  // 2026-06-13 queue 補強（Codex adversarial high 2）：client 是
  // List<String>.from(json['warnings'])，字串/物件 clobber 都會 throw。
  // 字串語意映射成單元素陣列，物件丟棄保留既有值。
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
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: { warnings: "請放慢節奏" },
  }));
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: { warnings: { note: "should be dropped" } },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;

  assertEquals(finalResult.warnings, ["請放慢節奏"]);
});

Deno.test("metrics float enthusiasm score is rounded for client int cast", async () => {
  // 2026-06-13 queue 補強（Codex adversarial medium 3）：client
  // enthusiasm['score'] as int? 收到 72.5 會 throw——server 端所有
  // enthusiasm 寫入路徑一律取整。
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
  reframer.pushText(line({
    type: "analysis.metrics",
    heat: 72.5,
  }));
  reframer.pushText(line({ type: "analysis.done", finalResult: {} }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  assertEquals(
    (finalResult.enthusiasm as Record<string, unknown>).score,
    73,
  );
});

Deno.test("done merge rounds float score inside enthusiasm record", async () => {
  // record 形狀正確但 score 為 float 一樣炸 client——record 路徑也要取整。
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
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: { enthusiasm: { score: 88.6, trend: "rising" } },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const enthusiasm = finalResult.enthusiasm as Record<string, unknown>;
  assertEquals(enthusiasm.score, 89);
  assertEquals(enthusiasm.trend, "rising");
});

Deno.test("done merge drops non-record psychology.shitTest instead of passing it to client", async () => {
  // 2026-06-13 queue 補強（Codex adversarial medium 4）：client 是
  // json['shitTest'] as Map<String, dynamic>?，巢狀字串硬 cast 必炸。
  // 語意不可靠（字串可能說「沒有測試」），丟 key 讓 client 走預設值。
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
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      psychology: {
        subtext: "She is keeping it light.",
        shitTest: "她在測試你",
      },
    },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const psychology = finalResult.psychology as Record<string, unknown>;
  assertEquals(psychology.subtext, "She is keeping it light.");
  assertEquals("shitTest" in psychology, false);
});

Deno.test("done merge keeps record-shaped psychology.shitTest intact", async () => {
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
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      psychology: {
        subtext: "She is testing.",
        shitTest: { detected: true, type: "tease", suggestion: "回得輕鬆" },
      },
    },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const psychology = finalResult.psychology as Record<string, unknown>;
  const shitTest = psychology.shitTest as Record<string, unknown>;
  assertEquals(shitTest.detected, true);
  assertEquals(shitTest.suggestion, "回得輕鬆");
});

Deno.test("string-array guards filter non-string elements and coerce nested healthCheck lists", async () => {
  // client 是 List<String>.from——元素混入數字/物件一樣 throw；
  // healthCheck.issues/suggestions 是同一家族的巢狀版。
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
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      warnings: ["別連發訊息", 42, { text: "junk" }],
      healthCheck: {
        issues: "回覆間隔越來越長",
        suggestions: ["放慢節奏", 7],
        score: 60,
      },
    },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  assertEquals(finalResult.warnings, ["別連發訊息"]);
  const healthCheck = finalResult.healthCheck as Record<string, unknown>;
  assertEquals(healthCheck.issues, ["回覆間隔越來越長"]);
  assertEquals(healthCheck.suggestions, ["放慢節奏"]);
  assertEquals(healthCheck.score, 60);
});

Deno.test("done merge guards string-only strategy and reminder from clobbering", async () => {
  // Codex 雙審 r2 B1（high）：strategy 不在任何守門清單，done finalResult
  // 帶 object 會原樣 clobber——client json['strategy'] as String? 必 throw。
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
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      strategy: { plan: "slow burn" },
      reminder: 42,
    },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  assertEquals(finalResult.strategy, "");
  assertEquals(finalResult.reminder, "");
});

Deno.test("done merge conforms client-casted fields inside psychology and gameStage records", async () => {
  // Codex 雙審 r2 A1＋自查：record 形狀正確但欄位型別錯——
  // qualificationSignal as bool?、subtext as String?、nextStep as String?、
  // shitTest.suggestion as String? 全是硬 cast。錯型丟欄位走 client 預設。
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
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      psychology: {
        subtext: "She is keeping it light.",
        qualificationSignal: "yes",
        shitTest: { detected: true, type: "tease", suggestion: 123 },
      },
      gameStage: { current: "premise", nextStep: 5 },
    },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const psychology = finalResult.psychology as Record<string, unknown>;
  assertEquals(psychology.subtext, "She is keeping it light.");
  assertEquals("qualificationSignal" in psychology, false);
  const shitTest = psychology.shitTest as Record<string, unknown>;
  assertEquals(shitTest.detected, true);
  assertEquals(shitTest.type, "tease");
  assertEquals("suggestion" in shitTest, false);
  const gameStage = finalResult.gameStage as Record<string, unknown>;
  assertEquals(gameStage.current, "premise");
  // 2026-07-02 gameStage 改 merge 語意（decision 的 nextStep 不得被 done 蓋掉）
  // 後，錯型 nextStep: 5 一樣被 conform 丟棄，但 assembler 種子 "" 會留著
  // ——client `as String? ?? ''` 等價，重點仍是數字 5 不得存活。
  assertEquals(gameStage.nextStep, "");
});

Deno.test("done merge conforms healthCheck bool and num fields", async () => {
  // Codex 雙審 r2 A2：hasNeedySignals/hasInterviewStyle as bool?、
  // speakingRatio as num?——字串會炸 client。
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
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      healthCheck: {
        issues: ["回覆間隔越來越長"],
        hasNeedySignals: "false",
        hasInterviewStyle: true,
        speakingRatio: "0.4",
      },
    },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const healthCheck = finalResult.healthCheck as Record<string, unknown>;
  assertEquals(healthCheck.issues, ["回覆間隔越來越長"]);
  assertEquals("hasNeedySignals" in healthCheck, false);
  assertEquals(healthCheck.hasInterviewStyle, true);
  assertEquals("speakingRatio" in healthCheck, false);
});

Deno.test("done merge rounds numeric-string enthusiasm score and drops junk score", async () => {
  // Codex 雙審 r2 B2：numberField 只收 typeof number，record 內
  // score: "72.6" 會原樣放行——client as int? 必 throw。數字字串可
  // 語意映射（parse＋round），垃圾值丟 key 走 client 預設 50。
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
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: { enthusiasm: { score: "72.6" } },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  assertEquals(
    (finalResult.enthusiasm as Record<string, unknown>).score,
    73,
  );
});

Deno.test("coach_hint event and done merge conform coachActionHint string fields", async () => {
  // Codex 雙審 r2 B3：absorb 的 coach_hint 直寫 result，done merge 也沒守
  // ——client text(key) = json[key] as String?，數字必 throw。
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
  reframer.pushText(line({
    type: "analysis.coach_hint",
    coachActionHint: {
      catchablePoint: 123,
      read: "She gave you an opening.",
      confidence: 0.8,
    },
  }));
  reframer.pushText(line({ type: "analysis.done", finalResult: {} }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const hint = finalResult.coachActionHint as Record<string, unknown>;
  assertEquals("catchablePoint" in hint, false);
  assertEquals(hint.read, "She gave you an opening.");
  assertEquals("confidence" in hint, false);
});

Deno.test("done merge conforms finalRecommendation strings and replies string map", async () => {
  // Codex 雙審 r2 B4＋自查 replies：pick/content/reason/psychology 全
  // as String?；legacy client replies 是 Map<String, String>.from，
  // 非字串 value 必 throw。
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  // recommendation 不帶 segments：finalRecommendation 不會被標 authoritative，
  // done merge 對該 key 仍生效，守門測得到。
  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "humor",
    message: "I will slow down before I get a ticket.",
    reason: "Softens the pressure.",
    quotedContext: "too fast",
  }));
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      finalRecommendation: { pick: 1, content: "use humor" },
      replies: { humor: 123, tease: "你這樣我要收費了喔" },
    },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const recommendation = finalResult.finalRecommendation as Record<
    string,
    unknown
  >;
  assertEquals("pick" in recommendation, false);
  assertEquals(recommendation.content, "use humor");
  const replies = finalResult.replies as Record<string, unknown>;
  assertEquals("humor" in replies, false);
  assertEquals(replies.tease, "你這樣我要收費了喔");
});

Deno.test("done merge conforms optimizedMessage and myMessageAnalysis fields", async () => {
  // Codex 雙審 r3 A1+A2：optimizedMessage original/optimized/reason 全
  // as String?；myMessageAnalysis sentMessage as String?、ifCold/ifWarm
  // as Map?、backupTopics/warnings 是 .cast<String>()。
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
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      optimizedMessage: { original: "嗨", optimized: 123 },
      myMessageAnalysis: {
        sentMessage: 5,
        ifColdResponse: "she ghosts",
        ifWarmResponse: { prediction: "she laughs", suggestion: 9 },
        backupTopics: "旅行",
      },
    },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const optimized = finalResult.optimizedMessage as Record<string, unknown>;
  assertEquals(optimized.original, "嗨");
  assertEquals("optimized" in optimized, false);
  const myMessage = finalResult.myMessageAnalysis as Record<string, unknown>;
  assertEquals("sentMessage" in myMessage, false);
  assertEquals("ifColdResponse" in myMessage, false);
  const warm = myMessage.ifWarmResponse as Record<string, unknown>;
  assertEquals(warm.prediction, "she laughs");
  assertEquals("suggestion" in warm, false);
  assertEquals(myMessage.backupTopics, ["旅行"]);
});

Deno.test("done merge conforms recognizedConversation including message list", async () => {
  // Codex 雙審 r3 A3：messageCount/uncertainSideCount as int?、messages
  // as List 且每則 m as Map<String, dynamic>——非物件元素必 throw。
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
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      recognizedConversation: {
        messageCount: "12",
        summary: "輕鬆閒聊",
        messages: [
          { content: "嗨", isFromMe: "yes", side: "left" },
          "junk entry",
        ],
      },
    },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const conversation = finalResult.recognizedConversation as Record<
    string,
    unknown
  >;
  assertEquals(conversation.messageCount, 12);
  assertEquals(conversation.summary, "輕鬆閒聊");
  const messages = conversation.messages as Record<string, unknown>[];
  assertEquals(messages.length, 1);
  assertEquals(messages[0].content, "嗨");
  assertEquals(messages[0].side, "left");
  assertEquals("isFromMe" in messages[0], false);
});

Deno.test("done merge conforms dimensions numbers and dogfoodComparison recommendations", async () => {
  // Codex 雙審 r3 B2+B3：client _parseDimensions 五鍵 as num?；
  // dogfoodComparison 內層走 FinalRecommendation.fromJson as String?。
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
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      dimensions: { heat: "72", engagement: 60 },
      dogfoodComparison: {
        tierUsed: "essential",
        rawFullRecommendation: { pick: 1, content: "use humor" },
      },
    },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const dimensions = finalResult.dimensions as Record<string, unknown>;
  assertEquals("heat" in dimensions, false);
  assertEquals(dimensions.engagement, 60);
  const dogfood = finalResult.dogfoodComparison as Record<string, unknown>;
  assertEquals(dogfood.tierUsed, "essential");
  const raw = dogfood.rawFullRecommendation as Record<string, unknown>;
  assertEquals("pick" in raw, false);
  assertEquals(raw.content, "use humor");
});

Deno.test("metrics dimensions are conformed before reaching result", async () => {
  // dimensions 也從 analysis.metrics 直寫——同一守門。
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
  reframer.pushText(line({
    type: "analysis.metrics",
    dimensions: { replyWillingness: "80", topicDepth: 55 },
  }));
  reframer.pushText(line({ type: "analysis.done", finalResult: {} }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const dimensions = finalResult.dimensions as Record<string, unknown>;
  assertEquals("replyWillingness" in dimensions, false);
  assertEquals(dimensions.topicDepth, 55);
});

Deno.test("reply segments are conformed at intake before entering replyOptions and finalRecommendation", async () => {
  // Codex 雙審 r3 B1（high）：ReplySegment.fromJson 對 label/
  // sourceMessage/reply/reason 全 as String?——模型 segments 帶錯型
  // 會經 replyOptions[].messages 與 finalRecommendation.replySegments
  // 炸 client。replySegmentsFrom 是單一咽喉點，入口 conform。
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
    replySegments: [
      { reply: "我先放慢", label: 1, sourceMessage: "太快了", reason: "降壓" },
    ],
  }));
  reframer.pushText(line({ type: "analysis.done", finalResult: {} }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const recommendation = finalResult.finalRecommendation as Record<
    string,
    unknown
  >;
  const segments = recommendation.replySegments as Record<string, unknown>[];
  assertEquals(segments.length, 1);
  assertEquals(segments[0].reply, "我先放慢");
  assertEquals(segments[0].sourceMessage, "太快了");
  assertEquals("label" in segments[0], false);
  const replyOptions = finalResult.replyOptions as Record<string, unknown>;
  const humor = replyOptions.humor as Record<string, unknown>;
  const messages = humor.messages as Record<string, unknown>[];
  assertEquals("label" in messages[0], false);
  assertEquals(messages[0].reply, "我先放慢");
});

Deno.test("done merge conforms replyOptions values and their segment lists", async () => {
  // done finalResult 的 replyOptions 是動態風格 key——每個 value record
  // 過 sourceMessage/reason string 守門＋messages/messageGroup/
  // replySegments 段落 conform（client fallback 路徑 sourceMessage
  // as String? 硬 cast）。
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
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      replyOptions: {
        tease: {
          sourceMessage: 9,
          reason: "輕推",
          messages: [{ reply: "你這樣我要收費了喔", label: 2 }],
        },
      },
    },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const replyOptions = finalResult.replyOptions as Record<string, unknown>;
  const tease = replyOptions.tease as Record<string, unknown>;
  assertEquals("sourceMessage" in tease, false);
  assertEquals(tease.reason, "輕推");
  const messages = tease.messages as Record<string, unknown>[];
  assertEquals(messages[0].reply, "你這樣我要收費了喔");
  assertEquals("label" in messages[0], false);
});

Deno.test("done merge drops non-string enthusiasm level", async () => {
  // Codex 雙審 r4：stream client 有 enthusiasm?['level'] as String?
  // （analysis_models.dart:911）——數字 level 必 throw。
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
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: { enthusiasm: { score: 70, level: 3 } },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const enthusiasm = finalResult.enthusiasm as Record<string, unknown>;
  assertEquals(enthusiasm.score, 70);
  assertEquals("level" in enthusiasm, false);
});

// ---------------------------------------------------------------------------
// 球數案修法二：盤點逼進輸出契約（軟版）— reframer 容忍 analysis.inventory
//
// inventory 在 decision（扣費錨）之前最先到貨。reframer 必須：純放行轉發給
// client（rides pre-charge buffer，charge 後 flush）、絕不當扣費錨、絕不碰丟段
// 路徑、絕不污染 finalResult、絕不阻斷 decision/done。守上輪紅線：完全不動
// segments / sanitize。
// ---------------------------------------------------------------------------

Deno.test("inventory: leading inventory is forwarded after charge, never blocks the stream", async () => {
  const timeline: string[] = [];
  let chargeCalls = 0;
  const reframer = createStreamReframer({
    emit(event) {
      timeline.push(`emit:${event.type}`);
    },
    onRecommendation() {
      chargeCalls += 1;
      timeline.push("charge");
      return { charged: true };
    },
  });

  // step 0：盤點先到（在 decision 之前），列全球各標 接/併/略。
  reframer.pushText(line({
    type: "analysis.inventory",
    balls: [
      { sourceIndex: 1, sourceMessage: "剛來吃晚餐", disposition: "接", reason: "生活分享可延伸" },
      { sourceIndex: 2, sourceMessage: "[Photo]", disposition: "略", reason: "無文字訊息點" },
    ],
  }));
  reframer.pushText(line({
    type: "analysis.decision",
    selectedStyle: "coldRead",
    nextStepBody: "接住晚餐球順勢延伸。",
    doThis: "問她吃了什麼。",
  }));
  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "coldRead",
    message: "吃晚餐配那張照片的氣氛，看起來今天心情不錯齁",
    reason: "接住晚餐球＋讀她的心情。",
    quotedContext: "剛來吃晚餐",
  }));

  await reframer.flush();

  // 不阻斷：charge 一次、inventory 在 charge 後 flush（decision 之前）、done 收尾、零 error。
  assertEquals(chargeCalls, 1);
  assertEquals(timeline, [
    "charge",
    "emit:analysis.inventory",
    "emit:analysis.decision",
    "emit:analysis.recommendation",
    "emit:analysis.done",
  ]);
});

Deno.test("inventory: never charges, never pollutes finalResult, never touches segments", async () => {
  const events: StreamOutputEvent[] = [];
  let chargeCalls = 0;
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
    type: "analysis.inventory",
    balls: [
      { sourceIndex: 1, sourceMessage: "剛來吃晚餐", disposition: "接", reason: "可延伸" },
      { sourceIndex: 2, sourceMessage: "等等去夜市", disposition: "併", reason: "同片段合併" },
      { sourceIndex: 3, sourceMessage: "[Photo]", disposition: "略", reason: "無文字點" },
    ],
  }));
  reframer.pushText(line({
    type: "analysis.decision",
    selectedStyle: "extend",
    nextStepBody: "接晚餐＋夜市兩球。",
    doThis: "順勢延伸。",
  }));
  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "extend",
    message: "吃了什麼好料？夜市幫我吃份地瓜球",
    reason: "接住兩球。",
    quotedContext: "剛來吃晚餐",
  }));
  reframer.pushText(line({ type: "analysis.done" }));

  await reframer.flush();

  // inventory 不是扣費錨：charge 只因 decision 觸發一次。
  assertEquals(chargeCalls, 1);
  assertEquals(events.some((e) => e.type === "analysis.error"), false);

  const done = events.find((e) => e.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;

  // 不污染 finalResult：盤點不外溢成頂層欄位。
  assertEquals("balls" in finalResult, false);
  assertEquals("inventory" in finalResult, false);

  // 不碰丟段路徑：盤點的球（帶 sourceMessage、無 reply）絕不變成 replySegments。
  const finalRecommendation = finalResult.finalRecommendation as Record<
    string,
    unknown
  >;
  assertEquals("balls" in finalRecommendation, false);
  assertEquals("disposition" in finalRecommendation, false);
  const segments = finalRecommendation.replySegments;
  if (Array.isArray(segments)) {
    for (const seg of segments) {
      assertEquals("disposition" in (seg as Record<string, unknown>), false);
    }
  }
});

// ── 球數案硬版：inventory disposition gate（INV-H1..H6 / failure matrix） ──

function inventoryLine(balls: Array<[number, string, string]>): string {
  return line({
    type: "analysis.inventory",
    balls: balls.map(([sourceIndex, disposition, sourceMessage]) => ({
      sourceIndex,
      sourceMessage,
      disposition,
      reason: "r",
    })),
  });
}

function replyOptionLine(
  style: string,
  segIdx: number[],
): string {
  return line({
    type: "analysis.reply_option",
    style,
    reason: "接住球",
    segments: segIdx.map((i) => ({
      sourceIndex: i,
      sourceMessage: `m${i}`,
      reply: `r${i}`,
      reason: "x",
    })),
  });
}

function thinRecommendationLine(style: string): string {
  return line({
    type: "analysis.recommendation",
    selectedStyle: style,
    reason: "接住才有互動感",
    expectedReaction: "她大概會繼續聊",
  });
}

function decisionLine(style: string): string {
  return line({
    type: "analysis.decision",
    selectedStyle: style,
    nextStepBody: "順著她的生活分享接住再延伸。",
    doThis: "接住晚餐與夜市兩顆球。",
    avoidThis: "不要只回一句敷衍。",
  });
}

const FOUR_CATCHABLE: Array<[number, string, string]> = [
  [1, "略", "只喜歡江果先"],
  [2, "併", "在比賽"],
  [3, "接", "剛來吃晚餐"],
  [4, "接", "晚餐照"],
  [5, "接", "到家了"],
  [6, "接", "視訊"],
];

Deno.test("fail-soft: selected style below floor is NOT blocked (logged, passes through)", async () => {
  // 2026-06-13 dogfood：硬擋會讓真實分析失敗（「請重新分析」）。閘改 fail-soft：
  // 選中風格不達下限時不擋、照出，避免 block 用戶；接球率靠 prompt 提升。
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

  reframer.pushText(inventoryLine(FOUR_CATCHABLE));
  reframer.pushText(decisionLine("coldRead"));
  reframer.pushText(thinRecommendationLine("coldRead"));
  reframer.pushText(replyOptionLine("coldRead", [5, 6])); // selected, only 2 segs
  reframer.pushText(replyOptionLine("extend", [3, 4, 5]));
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: { recommendation: { selectedStyle: "coldRead" } },
  }));

  await reframer.flush();

  assertEquals(chargeCalls, 1);
  // 不再 block：沒有 INCOMPLETE error、done 正常出、選中風格照出。
  assert(!events.some((e) => e.type === "analysis.error"));
  assert(events.some((e) => e.type === "analysis.done"));
  assert(events.some(
    (e) => e.type === "analysis.reply_option" &&
      (e as Record<string, unknown>).style === "coldRead",
  ));
});

Deno.test("hard gate: selected style meets floor (4接,3段 皆接) → PASS, done emitted", async () => {
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(inventoryLine(FOUR_CATCHABLE));
  reframer.pushText(decisionLine("coldRead"));
  reframer.pushText(thinRecommendationLine("coldRead"));
  reframer.pushText(replyOptionLine("coldRead", [4, 5, 6]));
  reframer.pushText(replyOptionLine("extend", [3, 4, 5]));

  await reframer.flush();

  assert(!events.some((e) => e.type === "analysis.error"));
  assert(events.some((e) => e.type === "analysis.done"));
  assert(events.some(
    (e) => e.type === "analysis.reply_option" &&
      (e as Record<string, unknown>).style === "coldRead",
  ));
});

Deno.test("hard gate: absent inventory → soft fallback, 2段選中風格不被誤殺", async () => {
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  // 不送 inventory 事件
  reframer.pushText(decisionLine("coldRead"));
  reframer.pushText(thinRecommendationLine("coldRead"));
  reframer.pushText(replyOptionLine("coldRead", [5, 6])); // 2 段
  reframer.pushText(replyOptionLine("extend", [3, 4, 5]));

  await reframer.flush();

  assert(!events.some((e) => e.type === "analysis.error"));
  assert(events.some((e) => e.type === "analysis.done"));
});

Deno.test("hard gate: per-style isolation — non-selected below floor does not block", async () => {
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(inventoryLine(FOUR_CATCHABLE));
  reframer.pushText(decisionLine("coldRead"));
  reframer.pushText(thinRecommendationLine("coldRead"));
  reframer.pushText(replyOptionLine("coldRead", [4, 5, 6])); // selected ok
  reframer.pushText(replyOptionLine("extend", [3])); // non-selected, 1 seg, must not block

  await reframer.flush();

  assert(!events.some((e) => e.type === "analysis.error"));
  assert(events.some((e) => e.type === "analysis.done"));
});

Deno.test("fail-soft: selected style segment sourced from 略 ball is NOT blocked", async () => {
  // fail-soft：即使選中風格取了略球段，也不擋（不 block 用戶）；只記錄。
  const events: StreamOutputEvent[] = [];
  const reframer = createStreamReframer({
    emit(event) {
      events.push(event);
    },
    onRecommendation() {
      return { charged: true };
    },
  });

  reframer.pushText(inventoryLine(FOUR_CATCHABLE)); // idx1 = 略
  reframer.pushText(decisionLine("coldRead"));
  reframer.pushText(thinRecommendationLine("coldRead"));
  reframer.pushText(replyOptionLine("coldRead", [1, 4, 5])); // idx1 是略球
  reframer.pushText(replyOptionLine("extend", [3, 4, 5]));
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: { recommendation: { selectedStyle: "coldRead" } },
  }));

  await reframer.flush();

  assert(!events.some((e) => e.type === "analysis.error"));
  assert(events.some((e) => e.type === "analysis.done"));
  assert(events.some(
    (e) => e.type === "analysis.reply_option" &&
      (e as Record<string, unknown>).style === "coldRead",
  ));
});

Deno.test("metrics gameStage record flows into finalResult and keeps decision nextStep", async () => {
  // 2026-07-02 dogfood：stream 協議 v2 後沒有任何 required 事件承載 gameStage，
  // assembler 種子預設 opening 永遠外流 → UI 對話進度永遠卡在破冰。修法＝
  // analysis.metrics 加掛 gameStage，reframer 吸收並保留 decision 填的 nextStep。
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
    nextStepBody: "Confirm the dinner plan she floated.",
  }));
  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "resonate",
    message: "Bring me the curry one.",
    reason: "She is pushing to meet.",
    quotedContext: "want me to bring dinner?",
  }));
  reframer.pushText(line({
    type: "analysis.metrics",
    heat: 90,
    gameStage: { current: "close", status: "canAdvance" },
  }));
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {},
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const gameStage = finalResult.gameStage as Record<string, unknown>;
  assertEquals(gameStage.current, "close");
  assertEquals(gameStage.status, "canAdvance");
  assertEquals(gameStage.nextStep, "Confirm the dinner plan she floated.");
});

Deno.test("gameStage synonyms and casing normalize to client enum values", async () => {
  // client GameStage.fromString / GameStageStatus.fromString 是大小寫敏感精確比對，
  // 不認得就靜默 fallback opening/normal——server 必須把中文標籤與大寫變體
  // 正規化成 client enum 名，否則模型輸出白給。
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
    selectedStyle: "extend",
    message: "So which stall are we hitting first?",
    reason: "Ride her momentum.",
    quotedContext: "night market later",
  }));
  reframer.pushText(line({
    type: "analysis.metrics",
    heat: 76,
    gameStage: { current: "升溫階段", status: "正常進行" },
  }));
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {},
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const gameStage = finalResult.gameStage as Record<string, unknown>;
  assertEquals(gameStage.current, "premise");
  assertEquals(gameStage.status, "normal");
});

Deno.test("done gameStage composite labels normalize when metrics gave no stage", async () => {
  // metrics 沒帶 stage 時 done 是唯一來源，複合寫法（"Qualification (評估)"）
  // 仍要能經包含比對映射到 client enum。
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
    selectedStyle: "coldRead",
    message: "You strike me as the type who yells at the screen.",
    reason: "Playful guess invites correction.",
    quotedContext: "watched the race",
  }));
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      gameStage: { current: "Qualification (評估)", status: "可以推進" },
    },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const gameStage = finalResult.gameStage as Record<string, unknown>;
  assertEquals(gameStage.current, "qualification");
  assertEquals(gameStage.status, "canAdvance");
});

Deno.test("metrics gameStage is authoritative over stale done gameStage", async () => {
  // Codex 雙審 P2：base prompt 的 legacy JSON schema 範例仍含 gameStage，
  // 模型可能在 compact finalResult 照抄殘骸（opening/premise）。metrics 是
  // 我們指定的權威通道——done/report_section 只能補欄位，不得覆蓋
  // current/status。
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
    nextStepBody: "Lock the dinner plan.",
  }));
  reframer.pushText(line({
    type: "analysis.recommendation",
    selectedStyle: "resonate",
    message: "Curry, and I am picking it up myself.",
    reason: "She is pushing to meet.",
    quotedContext: "want me to bring dinner?",
  }));
  reframer.pushText(line({
    type: "analysis.metrics",
    heat: 90,
    gameStage: { current: "close", status: "canAdvance" },
  }));
  reframer.pushText(line({
    type: "analysis.report_section",
    section: "gameStage",
    payload: "破冰",
  }));
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      gameStage: { current: "opening", status: "normal" },
    },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const gameStage = finalResult.gameStage as Record<string, unknown>;
  assertEquals(gameStage.current, "close");
  assertEquals(gameStage.status, "canAdvance");
  assertEquals(gameStage.nextStep, "Lock the dinner plan.");
});

Deno.test("ambiguous multi-stage strings refuse to map and keep defaults", async () => {
  // Codex 雙審 P3：包含比對首中即回會把否定/複合句誤映（「已非破冰，進入升溫」
  // 命中破冰→opening）。命中超過一個 canonical＝歧義＝拒絕映射、保留既有值。
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
    selectedStyle: "extend",
    message: "Which stall first?",
    reason: "Ride her momentum.",
    quotedContext: "night market later",
  }));
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: {
      gameStage: {
        // 命中 premise(升溫)＋qualification(評估) 兩個 canonical；
        // 首中即回會誤映 premise，歧義拒絕則守 opening 預設。
        current: "升溫之後，接近評估",
        // 命中 stuckFriend(偏向朋友)＋canAdvance(可以推進)；
        // 首中即回誤映 stuckFriend，歧義拒絕守 normal。
        status: "可以推進但偏向朋友",
      },
    },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const gameStage = finalResult.gameStage as Record<string, unknown>;
  assertEquals(gameStage.current, "opening");
  assertEquals(gameStage.status, "normal");
});

Deno.test("unmappable gameStage values keep assembler defaults instead of clobbering", async () => {
  // 值域守門：模型寫出無法映射的 stage 值時，保留 assembler 既有值
  //（client 端 fallback 也是 opening/normal，寧可 server 端就守住，
  //  不讓垃圾字串流出去）。
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
    message: "My biggest workout today was the fridge run.",
    reason: "Self-deprecation keeps it light.",
    quotedContext: "watched the race all day",
  }));
  reframer.pushText(line({
    type: "analysis.metrics",
    heat: 55,
    gameStage: { current: "vibing hard", status: 42 },
  }));
  reframer.pushText(line({
    type: "analysis.done",
    finalResult: { gameStage: "感覺不錯" },
  }));

  await reframer.flush();

  const done = events.find((event) => event.type === "analysis.done");
  assert(done, "expected analysis.done");
  const finalResult = done.finalResult as Record<string, unknown>;
  const gameStage = finalResult.gameStage as Record<string, unknown>;
  assertEquals(typeof finalResult.gameStage, "object");
  assertEquals(gameStage.current, "opening");
  assertEquals(gameStage.status, "normal");
});
