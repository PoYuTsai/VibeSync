// policy_breakdown.ts 的純函式自測（零網路、零模型）。
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { readOnlyStatsOf } from "./policy_breakdown.ts";

const turn = (over: Record<string, unknown> = {}) => ({
  role: "user" as const,
  userText: "曼谷",
  reply: "你怎麼一直丟地名",
  probe: null,
  ...over,
});
const session = (turns: unknown[], over: Record<string, unknown> = {}) =>
  ({
    profileId: "practice_girl_004",
    scenarioId: "A25",
    repeat: 1,
    difficulty: "normal",
    mode: "game",
    turns,
    ...over,
    // deno-lint-ignore no-explicit-any
  }) as any;

Deno.test("Phase 4.5e：readOnlyStatsOf 把「決策頻率」與「真實已讀率」分開算", () => {
  const s = readOnlyStatsOf({
    results: [
      session([
        // 腳本前文與 ai turn 都不進分母。
        { role: "ai", userText: "", reply: "在幹嘛", probe: null },
        turn({ scripted: true, forcedAct: "read_only" }),
        turn({ forcedAct: "challenge_relevance" }),
        // 走了短路：決策 ＋ 真實已讀都算。
        turn({
          forcedAct: "read_only",
          reply: "（已讀）",
          readOnlyReply: true,
        }),
        turn({
          forcedAct: "read_only",
          reply: "（已讀）",
          readOnlyReply: true,
        }),
        // 4.5e 之前的舊 artifact：決策是 read_only 但回覆是模型生成的內容。
        turn({ forcedAct: "read_only", reply: "你到底想說什麼啦" }),
      ]),
      // 失敗場次整場不算。
      session([turn({ forcedAct: "read_only", readOnlyReply: true })], {
        error: "boom",
      }),
    ],
  });
  assertEquals(s.rounds, 4);
  assertEquals(s.decisions, 3);
  assertEquals(s.replies, 2);
  assertEquals(s.decisionRate, 0.75);
  assertEquals(s.readOnlyReplyRate, 0.5);
});

Deno.test("Phase 4.5e：沒有任何回合時兩個比例都是 null，不除以零", () => {
  const s = readOnlyStatsOf({ results: [] });
  assertEquals(s.rounds, 0);
  assertEquals(s.decisionRate, null);
  assertEquals(s.readOnlyReplyRate, null);
});
