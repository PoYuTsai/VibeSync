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
