// opener_stream.ts 純函式測試。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  createStreamStageTracker,
  emitJsonResponseAsStreamOutcome,
  NEW_TOPIC_STREAM_STAGES,
  OPENER_STREAM_STAGES,
} from "./opener_stream.ts";

function collectTracker(stages: typeof OPENER_STREAM_STAGES) {
  const events: Record<string, unknown>[] = [];
  const tracker = createStreamStageTracker({
    stages,
    eventType: "opener.progress",
    emit: (event) => events.push(event),
  });
  return { tracker, events };
}

Deno.test("tracker：opener 各 stage 首見各發一次，重掃不重發", () => {
  const { tracker, events } = collectTracker(OPENER_STREAM_STAGES);
  tracker.push('{"profileAnalysis":{"style":"x"},');
  tracker.push('"openers":{"extend":"a","resonate":"b",');
  tracker.push('"tease":"c","humor":"d","coldRead":"e"},');
  // stretchLevels 重複五個風格 key：不得再發。
  tracker.push('"stretchLevels":{"extend":"within","resonate":"within",');
  tracker.push('"tease":"stretch","humor":"within","coldRead":"far"},');
  tracker.push('"pioneerPlan":{},"recommendation":{"pick":"extend"},');
  tracker.push('"formulaOpeners":[]}');

  const labels = events.map((e) => e["label"]);
  assertEquals(labels, [
    "解讀對方資料",
    "開始寫五種風格開場白",
    "開場白 1/5：延展",
    "開場白 2/5：共鳴",
    "開場白 3/5：調情",
    "開場白 4/5：幽默",
    "開場白 5/5：冷讀",
    "準備先鋒備案",
    "挑選最適推薦",
    "寫公式開場",
  ]);
  assert(events.every((e) => e["type"] === "opener.progress"));
});

Deno.test("tracker：marker 被 chunk 切半仍偵測得到", () => {
  const { tracker, events } = collectTracker(OPENER_STREAM_STAGES);
  tracker.push('{"profileAna');
  assertEquals(events.length, 0);
  tracker.push('lysis":{}');
  assertEquals(events.map((e) => e["label"]), ["解讀對方資料"]);
});

Deno.test("tracker：new_topic 的 direction 計數到 5 為止", () => {
  const events: Record<string, unknown>[] = [];
  const tracker = createStreamStageTracker({
    stages: NEW_TOPIC_STREAM_STAGES,
    eventType: "new_topic.progress",
    emit: (event) => events.push(event),
  });
  tracker.push('{"topics":[');
  for (let i = 0; i < 6; i++) {
    tracker.push('{"direction":"d","openingLine":"o"},');
  }
  tracker.push('],"recommendation":{"index":0},"formulaTopics":[]}');

  const topicLabels = events
    .map((e) => e["label"] as string)
    .filter((label) => label.startsWith("新話題"));
  assertEquals(topicLabels, [
    "新話題 1/5",
    "新話題 2/5",
    "新話題 3/5",
    "新話題 4/5",
    "新話題 5/5",
  ]);
  const phases = events.map((e) => e["phase"]);
  assert(phases.includes("topic_1") && phases.includes("topic_5"));
});

Deno.test("outcome：200 → done 事件帶整包 result", async () => {
  const events: Record<string, unknown>[] = [];
  await emitJsonResponseAsStreamOutcome(
    new Response(JSON.stringify({ openers: { extend: "hi" }, usage: {} }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    }),
    (event) => events.push(event),
    "opener",
  );
  assertEquals(events.length, 1);
  assertEquals(events[0]["type"], "opener.done");
  const result = events[0]["result"] as Record<string, unknown>;
  assertEquals((result["openers"] as Record<string, unknown>)["extend"], "hi");
});

Deno.test("outcome：非 200 → error 事件攤平 body 並帶 status；type 不被 body 蓋掉", async () => {
  const events: Record<string, unknown>[] = [];
  await emitJsonResponseAsStreamOutcome(
    new Response(
      JSON.stringify({
        error: "額度不足",
        message: "本月額度不足",
        monthlyRemaining: 0,
        type: "evil-override",
      }),
      { status: 429 },
    ),
    (event) => events.push(event),
    "opener",
  );
  assertEquals(events.length, 1);
  assertEquals(events[0]["type"], "opener.error");
  assertEquals(events[0]["status"], 429);
  assertEquals(events[0]["error"], "額度不足");
  assertEquals(events[0]["monthlyRemaining"], 0);
});

Deno.test("outcome：body 解析失敗不炸，仍發 error 事件", async () => {
  const events: Record<string, unknown>[] = [];
  await emitJsonResponseAsStreamOutcome(
    new Response("not-json", { status: 502 }),
    (event) => events.push(event),
    "new_topic",
  );
  assertEquals(events.length, 1);
  assertEquals(events[0]["type"], "new_topic.error");
  assertEquals(events[0]["status"], 502);
});

Deno.test("tracker：opener 五種風格 phase 各自獨立（client 骨架卡契約）", () => {
  const events: Record<string, unknown>[] = [];
  const tracker = createStreamStageTracker({
    stages: OPENER_STREAM_STAGES,
    eventType: "opener.progress",
    emit: (event) => events.push(event),
  });
  tracker.push(
    '{"openers":{"extend":"a","resonate":"b","tease":"c","humor":"d","coldRead":"e"}}',
  );
  const phases = events.map((e) => e["phase"]);
  for (
    const phase of [
      "style_extend",
      "style_resonate",
      "style_tease",
      "style_humor",
      "style_coldRead",
    ]
  ) {
    assert(phases.includes(phase), `缺 ${phase}`);
  }
});
