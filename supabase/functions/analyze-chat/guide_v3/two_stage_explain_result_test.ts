// 兩段式實驗的「為什麼這樣回」存進結果（主審第 1 輪 P2，Eric 2026-10-20）：續看只重播結果、不重播
// analysis.card_explain，所以通過檢查、送出的說明照卡號放進結果的 cardExplains（App 573b71ee 讀這個
// key）。即時 done、落帳結果、續看重播都要有；說明沒送出就沒有這個 key；開關沒開一字不變（見
// flag_matrix_test.ts）；上一輪脈絡不會把說明帶進下一輪的提示詞。不呼叫模型、不連網。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { stripClientHiddenFinalResult } from "../divergence_contract.ts";
import { handleStreamAnalysisResume } from "../stream_handler.ts";
import type { AnalysisStreamRun } from "../stream_run_store.ts";
import { FLAG_MATRIX_T0, runFlagMatrix } from "./flag_matrix_harness.ts";
import { GUIDE_V3_VERSION } from "./guide_text.ts";
import {
  parsePreviousRound,
  previousRoundReadSection,
  previousRoundWriteSection,
} from "./previous_round.ts";
import { guideV3ResumeSnapshot } from "./run_shape.ts";
import { handleGuideV3Stream } from "./stream_flow.ts";
import { toTurns } from "./turns.ts";
import { GUIDE_V3_CARD_EXPLAINS_KEY } from "./wire.ts";

type Rec = Record<string, unknown>;
type Outcome = { events: Rec[]; markDone: Rec };

const TWO_STAGE_COMBOS = [
  { twoStage: true, relation: false },
  { twoStage: true, relation: true },
];

async function run(combo: { twoStage: boolean; relation: boolean }) {
  return await runFlagMatrix(handleGuideV3Stream, combo) as unknown as Outcome;
}

const explainsOf = (o: Outcome) =>
  o.events.filter((e) => e.type === "analysis.card_explain").map((e) => ({
    card: e.card,
    text: e.text,
  }));
const doneOf = (o: Outcome) =>
  o.events.find((e) => e.type === "analysis.done")!;

Deno.test("兩段式開：送出的說明照卡號放進結果的 cardExplains；即時 done、落帳結果都有，跟 analysis.card_explain 一字不差", async () => {
  assertEquals(GUIDE_V3_CARD_EXPLAINS_KEY, "cardExplains");
  for (const combo of TWO_STAGE_COMBOS) {
    const outcome = await run(combo);
    const streamed = explainsOf(outcome);
    assert(streamed.length > 0, JSON.stringify(combo));
    const cards = outcome.events.filter((e) => e.type === "analysis.card");
    assertEquals(
      streamed.map((x) => x.card),
      cards.map((c) => c.slot),
    );
    const done = doneOf(outcome);
    assertEquals((done.finalResult as Rec).cardExplains, streamed);
    assertEquals((done.result as Rec).cardExplains, streamed);
    // 落帳的結果（含 trace）也有；送 App 前剝掉 trace，cardExplains 留著。
    assertEquals(outcome.markDone.cardExplains, streamed);
    assertEquals(
      (stripClientHiddenFinalResult(outcome.markDone) as Rec).cardExplains,
      streamed,
    );
    assertEquals(
      "guideV3Trace" in (stripClientHiddenFinalResult(outcome.markDone) as Rec),
      false,
    );
    // App 的格式：卡號是 1 以上的整數、說明不是空字串。
    for (const x of streamed) {
      assert(Number.isInteger(x.card) && (x.card as number) >= 1);
      assert(typeof x.text === "string" && x.text !== "");
    }
  }
});

Deno.test("兩段式開：續看重播已結案的 run，結果帶 cardExplains、不帶 trace", async () => {
  for (const combo of TWO_STAGE_COMBOS) {
    const outcome = await run(combo);
    const run_: AnalysisStreamRun = {
      id: "matrix-run",
      user_id: "matrix-user",
      conversation_hash: "matrix-hash",
      status: "done",
      selected_style: null,
      decision_kind: "send",
      card_task: "accept",
      recommendation_json: null,
      final_result_json: outcome.markDone,
      charged_at: new Date(FLAG_MATRIX_T0).toISOString(),
      last_error_code: null,
      retry_count: 0,
      request_context: { guideVersion: GUIDE_V3_VERSION },
      created_at: new Date(FLAG_MATRIX_T0).toISOString(),
      expires_at: new Date(FLAG_MATRIX_T0 + 30 * 60_000).toISOString(),
    };
    const snapshot = guideV3ResumeSnapshot(run_, FLAG_MATRIX_T0 + 86_400_000);
    const response = handleStreamAnalysisResume({
      runId: "matrix-run",
      conversationHash: "matrix-hash",
      initialRun: snapshot,
      loadRun: () => snapshot,
      pollIntervalMs: 0,
      heartbeatIntervalMs: 0,
    });
    const events = (await response.text()).split("\n").filter(Boolean).map((
      l,
    ) => JSON.parse(l) as Rec);
    const done = events.find((e) => e.type === "analysis.done")!;
    assertEquals(done.recovered, true);
    const replayed = done.finalResult as Rec;
    assertEquals(replayed.cardExplains, explainsOf(outcome));
    assertEquals("guideV3Trace" in replayed, false);
  }
});

Deno.test("上一輪脈絡：App 把整份上一輪結果（含 cardExplains 與卡）當 previousRound 送來，也只收判讀與訊息，說明的字不進下一輪的提示詞", () => {
  const explainText = "這張先回她問的那句，說明只給用戶看";
  const raw = {
    decision: "send",
    light: "green",
    judgment: "她在分享聚餐的開心。",
    messages: [{ isFromMe: false, content: "你覺得我今天好看嗎" }],
    cards: [{ slot: 1, task: "accept", messages: ["好看啊"] }],
    [GUIDE_V3_CARD_EXPLAINS_KEY]: [{ card: 1, text: explainText }],
  };
  const parsed = parsePreviousRound(raw);
  assertEquals(parsed.kind, "ok");
  if (parsed.kind !== "ok") return;
  assertEquals(Object.keys(parsed.round).sort(), [
    "decision",
    "judgment",
    "light",
    "messages",
  ]);
  assertEquals(JSON.stringify(parsed.round).includes(explainText), false);
  const prompts = [
    ...previousRoundReadSection(parsed.round),
    ...previousRoundWriteSection(parsed.round),
  ].join("\n");
  assert(prompts.length > 0);
  assertEquals(prompts.includes(explainText), false);
  assertEquals(prompts.includes("好看啊"), false);
  // 把說明塞進 previousRound 的訊息才會被當成對話：App 不這樣做（這裡只確認伺服器不另外去讀）。
  assert(toTurns(parsed.round.messages).length === 1);
});
