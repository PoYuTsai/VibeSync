import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  createStreamReframer,
  type StreamOutputEvent,
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
    label: "pressure check",
    nextStepBody: "Slow down first.",
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
    "emit:analysis.decision",
    "charge:resonate",
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
    "analysis.progress",
    "analysis.done",
  ]);
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
    nextStepBody: "Acknowledge the pressure and slow the pace.",
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
    "analysis.progress",
    "analysis.done",
  ]);
});
