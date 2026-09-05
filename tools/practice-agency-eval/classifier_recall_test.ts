// classifier_recall.ts 的 dry-run 自測：**一次模型呼叫都不打**。
// 驗三件事——候選正則挑得到／挑不到什麼、artifact 展開成 job 的結構條件
// （腳本輪與失敗場次不算）、彙總的分母規則（repair／失敗要扣、不除以零）。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  buildRecallJobs,
  candidateHitsFor,
  CHALLENGE_CANDIDATES,
  complementHitsFor,
  estimateRecallRunUsd,
  type RecallRow,
  summarizeRecall,
} from "./classifier_recall.ts";
import { DEEPSEEK_CLASSIFIER_USD_PER_CALL } from "./pricing.ts";

Deno.test("候選正則：任務點名的五種無標記中文反問全部挑得到", () => {
  for (
    const reply of [
      "蛤？",
      "蛤",
      "你在講什麼",
      "？",
      "什麼意思",
      "你是在亂說還是怎樣",
      "嗄？你問這個幹嘛",
      "你幹嘛突然講這個",
      "這跟剛剛在聊的有關嗎",
      "你還沒回答我",
      "誰？",
      "聽不懂",
      "三小",
    ]
  ) {
    assert(candidateHitsFor(reply).length > 0, reply);
  }
});

Deno.test("候選正則：正常回覆不會被挑進候選（不然分母整個沒意義）", () => {
  for (
    const reply of [
      "好啊 那你下班後有空嗎",
      "我最近在調作息 晚上都比較早睡",
      "清邁喔 我還沒去過欸",
      "哈哈哈笑死",
      "",
      "   ",
    ]
  ) {
    assertEquals(candidateHitsFor(reply), [], reply);
  }
});

Deno.test("候選正則：每一條都有 id 與說明，id 不重複（供人工複核）", () => {
  const ids = CHALLENGE_CANDIDATES.map((c) => c.id);
  assertEquals(new Set(ids).size, ids.length);
  for (const c of CHALLENGE_CANDIDATES) {
    assert(c.note.length > 10, c.id);
    // 全域旗標會讓 RegExp.test 帶 lastIndex 狀態，逐則重用時結果會跳動。
    assert(!c.pattern.global, `${c.id} 不可帶 g 旗標`);
  }
});

Deno.test("buildRecallJobs：只收模型真的生成過的輪次，逐字稿重建到玩家那句為止", () => {
  const jobs = buildRecallJobs("fake.json", [
    {
      profileId: "practice_girl_001",
      difficulty: "easy",
      scenarioId: "A25",
      repeat: 1,
      turns: [
        // 腳本前文（ai）：不是候選，但要進逐字稿。
        { role: "ai", userText: "", reply: "在幹嘛" },
        // 腳本化的 user turn：她那則不是模型生成的，不算候選。
        { role: "user", userText: "東東", reply: "蛤？", scripted: true },
        // 真的生成的一輪，且命中候選。
        {
          role: "user",
          userText: "阿布達比",
          reply: "蛤？你在講什麼",
          probe: { id: "A25.p2" },
        },
        // 生成但沒命中候選。
        { role: "user", userText: "沒事", reply: "喔好", probe: null },
      ],
    },
    // 失敗場次整場略過。
    {
      profileId: "practice_girl_002",
      difficulty: "easy",
      scenarioId: "A25",
      repeat: 1,
      error: "boom",
      turns: [{ role: "user", userText: "x", reply: "蛤？" }],
    },
  ]);
  assertEquals(jobs.length, 1);
  const job = jobs[0];
  assertEquals(job.probeId, "A25.p2");
  assertEquals(job.userText, "阿布達比");
  assertEquals([...job.hits].sort(), [
    "interjection_then_question",
    "what_are_you_saying",
  ]);
  // 逐字稿含腳本前文與腳本輪，尾巴是玩家這一句（她這則另外走 assistantReply）。
  assertEquals(job.turns, [
    { role: "ai", text: "在幹嘛" },
    { role: "user", text: "東東" },
    { role: "ai", text: "蛤？" },
    { role: "user", text: "阿布達比" },
  ]);
});

Deno.test("estimateRecallRunUsd：候選數 × pricing.ts 的觀測單價", () => {
  assertEquals(estimateRecallRunUsd(0), 0);
  assertEquals(
    estimateRecallRunUsd(100),
    100 * DEEPSEEK_CLASSIFIER_USD_PER_CALL,
  );
});

Deno.test("summarizeRecall：repair 與失敗都扣出分母，分母 0 時是 null 不是 0", () => {
  const row = (over: Partial<RecallRow>): RecallRow => ({
    artifact: "a",
    profileId: "p",
    difficulty: "easy",
    scenarioId: "A25",
    repeat: 1,
    probeId: "A25.p1",
    userText: "阿布達比",
    reply: "蛤？",
    hits: ["short_interjection"],
    turns: [],
    aiChallengedThisTurn: null,
    repaired: false,
    error: null,
    ...over,
  });
  const s = summarizeRecall([
    row({ aiChallengedThisTurn: true }),
    row({ aiChallengedThisTurn: true }),
    row({ aiChallengedThisTurn: false }),
    // repair 出來的 false 不是模型的判斷，扣掉。
    row({ aiChallengedThisTurn: false, repaired: true }),
    // 呼叫失敗，扣掉。
    row({ error: "timeout" }),
  ]);
  assertEquals(s.candidates, 5);
  assertEquals(s.explicit, 3);
  assertEquals(s.challenged, 2);
  assertEquals(s.repaired, 1);
  assertEquals(s.errors, 1);
  assert(Math.abs((s.recallProxy ?? 0) - 2 / 3) < 1e-9);
  // 逐條正則的命中數含被扣掉的那些（那是候選集大小，不是判定分母）。
  assertEquals(s.byCandidate.short_interjection, { n: 5, challenged: 2 });
  assertEquals(summarizeRecall([]).recallProxy, null);
});

Deno.test("Phase 4.5f complementHitsFor：挑非候選的問句，候選與非問句都排除", () => {
  // 非候選的問句＝誤判率代理集。
  for (const reply of ["清邁喔 我還沒去過欸 你去過嗎", "那你下班後有空嗎？"]) {
    assertEquals(complementHitsFor(reply), ["complement"], reply);
  }
  // 已經在候選集裡的（會被 --complement 之外的那一路算），不重複收。
  for (const reply of ["蛤？", "你是在亂說還是怎樣", "？"]) {
    assertEquals(complementHitsFor(reply), [], reply);
  }
  // 沒有問號也沒有問句語尾的陳述句不收。
  for (const reply of ["我最近在調作息", "哈哈哈笑死", "", "   "]) {
    assertEquals(complementHitsFor(reply), [], reply);
  }
});

Deno.test("Phase 4.5f buildRecallJobs 吃得下 complement 取樣器（同一條展開路徑）", () => {
  const sessions = [{
    profileId: "p",
    difficulty: "normal",
    scenarioId: "s",
    repeat: 1,
    turns: [
      { role: "user" as const, userText: "清邁", reply: "蛤？" },
      { role: "user" as const, userText: "泰國那個", reply: "你去過嗎？" },
    ],
  }];
  assertEquals(
    buildRecallJobs("a", sessions, complementHitsFor).map((j) => j.reply),
    ["你去過嗎？"],
  );
  assertEquals(buildRecallJobs("a", sessions).map((j) => j.reply), ["蛤？"]);
});
