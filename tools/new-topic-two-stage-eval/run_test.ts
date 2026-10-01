// 純函式測試：不打模型、不讀金鑰、不寫檔。
import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  apologyCount,
  ARMS,
  blindAB,
  buildPlan,
  CASES,
  estimateInputTokens,
  estimatePlan,
  type EvalCase,
  type EvalRecord,
  inspectOutput,
  parseOptions,
  proposalChecks,
  usd,
} from "./run.ts";
import {
  NEW_TOPIC_MAX_TOKENS,
  NEW_TOPIC_PROMPT,
} from "../../supabase/functions/analyze-chat/new_topic_prompt.ts";
import { NEW_TOPIC_TWO_STAGE_PROMPT } from "../../supabase/functions/analyze-chat/new_topic_two_stage.ts";

Deno.test("參數：預設 dry-run；真跑缺任何一個守門參數都拒絕", () => {
  assertEquals(parseOptions([]).run, false);
  assertEquals(parseOptions([]).repeat, 1);
  for (
    const args of [
      ["--run"],
      ["--run", "--confirm-paid", "--max-calls=24"],
      ["--run", "--confirm-paid", "--budget-usd=2"],
      ["--run", "--max-calls=24", "--budget-usd=2"],
    ]
  ) assertThrows(() => parseOptions(args));
  const live = parseOptions([
    "--run",
    "--confirm-paid",
    "--max-calls=24",
    "--budget-usd=2",
    "--tag=r1",
  ]);
  assertEquals([live.run, live.maxCalls, live.budgetUsd, live.tag], [
    true,
    24,
    2,
    "r1",
  ]);
  assertThrows(() => parseOptions(["--bogus=1"]));
  assertThrows(() => parseOptions(["--run=yes"]));
  assertThrows(() => parseOptions(["--tag=a", "--tag=b"]));
  assertThrows(() => parseOptions(["--tag=../x"]));
  assertThrows(() => parseOptions(["--only=E1,NOPE"]));
  assertThrows(() => parseOptions(["--budget-usd=-1"]));
});

Deno.test("案例：涵蓋提案三例、四種狀況、五種素材，且都過 production 請求驗證", async () => {
  for (const id of ["E1", "E2", "E3"]) assert(CASES.some((c) => c.id === id));
  assertEquals(new Set(CASES.map((c) => c.situation)).size, 4);
  assertEquals(new Set(CASES.map((c) => c.topicContext.materialKind)).size, 5);
  const plan = await buildPlan(CASES, 1); // 不合法會 throw
  assertEquals(plan.length, CASES.length * ARMS.length);
});

Deno.test("計畫：兩臂同 requestId；legacy 看不到素材，two_stage 看得到；系統提示詞就是 production 常數", async () => {
  const plan = await buildPlan(CASES, 2);
  for (const c of CASES) {
    for (const attempt of [1, 2]) {
      const [legacy, two] = ARMS.map((arm) =>
        plan.find((p) =>
          p.caseId === c.id && p.attempt === attempt && p.arm === arm
        )!
      );
      assertEquals(legacy.requestId, two.requestId);
      assert(
        legacy.system === NEW_TOPIC_PROMPT &&
          two.system === NEW_TOPIC_TWO_STAGE_PROMPT,
      );
      const text = c.topicContext.materialText;
      if (text) {
        assert(!legacy.user.includes(text), c.id);
        assert(two.user.includes(text), c.id);
      }
    }
  }
  const ids = plan.filter((p) => p.caseId === "E1").map((p) => p.requestId);
  assert(ids[0] !== ids[2], "不同次重複要換 requestId");
});

Deno.test("估算：input＝字數×1.5，最壞用 max_tokens、一般用 1200", async () => {
  assertEquals(estimateInputTokens({ system: "一二", user: "三" }), 5);
  const plan = await buildPlan(CASES.slice(0, 1), 1);
  const est = estimatePlan(plan);
  assertEquals(est.worstOutputTokens, 2 * NEW_TOPIC_MAX_TOKENS);
  assertEquals(est.typicalOutputTokens, 2 * 1200);
  assert(est.typicalUsd < est.worstUsd);
  assertEquals(usd(1_000_000, 0), 2);
  assertEquals(usd(0, 1_000_000), 10);
});

function fakeOutput(lines: string[], index = 0): string {
  return JSON.stringify({
    topics: lines.map((openingLine, i) => ({
      direction: `方向${"一二三四五"[i]}`,
      openingLine,
      whyItWorks: "她一句話就能接",
      nextMove: "先接住她的話，再加一點自己的看法",
    })),
    recommendation: { index, reason: "最好接" },
  });
}

function toRecords(
  plan: Awaited<ReturnType<typeof buildPlan>>,
  output: (key: string) => string,
): EvalRecord[] {
  return plan.map((call) => {
    const { system: _s, ...rest } = call;
    return {
      ...rest,
      status: "MODEL_RETURNED",
      inspection: inspectOutput(call, output(call.key)),
    };
  });
}

Deno.test("整理＋§10 計數：失敗不算進句數、但算進素材分母；legacy 對照照實記", async () => {
  const plan = await buildPlan(
    CASES.filter((c) => ["E1", "C1", "D2"].includes(c.id)),
    1,
  );
  const outputs: Record<string, string> = {
    // E1 是「我沒回她」：五題各道歉一次（五個備選，不是一起傳）→ 0 題違規。
    "E1.1.two_stage": fakeOutput([
      "抱歉晚回，剛路過一家浮誇的甜點店",
      "不好意思，今天的雲很像棉花糖",
      "對不起消失了一下，我發現巷口開了新書店",
      "Sorry 剛剛差點坐過站",
      "抱歉，辦公室冷氣冷到發抖",
    ]),
    // 同一題分兩則傳、各道歉一次＝同一題道歉兩次 → 1 題違規。
    "E1.1.legacy": fakeOutput([
      "不好意思最近太忙了\n抱歉現在才回",
      "在嗎",
      "今天的雲很像棉花糖",
      "我發現巷口開了新書店",
      "剛剛差點坐過站",
    ]),
    "C1.1.two_stage": fakeOutput([
      "潛水證照考到哪一關了",
      "今天的雲很像棉花糖",
      "我發現巷口開了新書店",
      "剛剛差點坐過站",
      "辦公室冷氣冷到發抖",
    ]),
    "C1.1.legacy": fakeOutput([
      "好久沒聊了",
      "今天的雲很像棉花糖",
      "我發現巷口開了新書店",
      "剛剛差點坐過站",
      "辦公室冷氣冷到發抖",
    ]),
    "D2.1.two_stage": "not json",
    "D2.1.legacy": fakeOutput([
      "下次約妳吃飯",
      "今天的雲很像棉花糖",
      "我發現巷口開了新書店",
      "剛剛差點坐過站",
      "辦公室冷氣冷到發抖",
    ]),
  };
  const checks = proposalChecks(toRecords(plan, (key) => outputs[key]));
  assertEquals(checks.two_stage.outputs, 3);
  assertEquals(checks.two_stage.deliverable, 2);
  // D2 格式壞掉算沒用到素材：2/3 不到 90%；只看可交付的條件比率另列。
  assertEquals(checks.two_stage.materialInRecommended, {
    hit: 2,
    total: 3,
    pass: false,
    deliverableOnly: { hit: 2, total: 2 },
  });
  assertEquals(checks.two_stage.sheNoReplyGapLines, 0);
  assertEquals(checks.legacy.sheNoReplyGapLines, 1);
  assertEquals(checks.two_stage.iNoReplyTopicsOverOneApology, 0);
  assertEquals(checks.legacy.iNoReplyTopicsOverOneApology, 1);
  assertEquals(checks.legacy.bannedOpenerLines, 1);
  assertEquals(checks.legacy.redInviteLines, 1);
  assertEquals(checks.legacy.materialInRecommended.hit, 0);
});

Deno.test("道歉：數同一則 openingLine 裡的次數，不分大小寫", () => {
  assertEquals(apologyCount("抱歉晚回"), 1);
  assertEquals(apologyCount("不好意思\n抱歉現在才回"), 2);
  assertEquals(apologyCount("SORRY 對不起"), 2);
  assertEquals(apologyCount("今天的雲很像棉花糖"), 0);
});

Deno.test("素材比率：分母是有素材的全部呼叫，失敗算沒用到；分母 0 是未評估不是過關", async () => {
  const material = CASES.filter((c) => c.topicContext.materialText);
  assertEquals(material.length, 10);
  const plan = await buildPlan(material, 1);
  const hitE1 = fakeOutput([
    "剛路過一家浮誇的甜點店",
    "今天的雲很像棉花糖",
    "我發現巷口開了新書店",
    "剛剛差點坐過站",
    "辦公室冷氣冷到發抖",
  ]);
  // 9 個格式失敗＋1 個命中：1/10，不是 1/1 過關。
  const oneHit = proposalChecks(
    toRecords(plan, (key) => key === "E1.1.two_stage" ? hitE1 : "not json"),
  );
  assertEquals(oneHit.two_stage.materialInRecommended, {
    hit: 1,
    total: 10,
    pass: false,
    deliverableOnly: { hit: 1, total: 1 },
  });
  // 全部失敗：0/10 不過關，不是 0/0 過關。
  const allFail = proposalChecks(toRecords(plan, () => "not json"));
  assertEquals(allFail.two_stage.materialInRecommended, {
    hit: 0,
    total: 10,
    pass: false,
    deliverableOnly: { hit: 0, total: 0 },
  });
  // 選到的案例都沒有素材：未評估。
  const none = await buildPlan(
    CASES.filter((c) => !c.topicContext.materialText),
    1,
  );
  assertEquals(
    proposalChecks(toRecords(none, () => hitE1)).two_stage.materialInRecommended
      .pass,
    null,
  );
});

Deno.test("grounding 同 handler：兩段式用戶素材裡的內部代碼字（stuck）照用不算外洩，legacy 沒有豁免", async () => {
  const stuckCase: EvalCase = {
    id: "T1",
    source: "test",
    label: "測試",
    partner: "xiaowen",
    situation: "went_cold",
    topicContext: {
      coldDuration: "weeks",
      coldStop: "she_no_reply",
      materialKind: "my_story",
      materialText: "最近專案一直 stuck 在同一關",
    },
  };
  const plan = await buildPlan([stuckCase], 1);
  const [legacy, two] = ARMS.map((arm) => plan.find((p) => p.arm === arm)!);
  assertEquals(two.grounding.userMaterialText, "最近專案一直 stuck 在同一關");
  assertEquals(legacy.grounding.userMaterialText, null);
  const raw = fakeOutput([
    "上次說的 stuck 專案終於過關了",
    "今天的雲很像棉花糖",
    "我發現巷口開了新書店",
    "剛剛差點坐過站",
    "辦公室冷氣冷到發抖",
  ]);
  assert(inspectOutput(two, raw).deliverable);
  const legacyResult = inspectOutput(legacy, raw);
  assert(!legacyResult.deliverable);
  assertEquals(legacyResult.normalizeReason, "topic_field_invalid");
});

Deno.test("盲測：同 seed 同順序、不露臂名、解盲表涵蓋每組兩臂、失敗那版照列", async () => {
  const plan = await buildPlan(CASES.slice(0, 3), 1);
  const ok = fakeOutput([
    "剛路過一家浮誇的甜點店",
    "今天的雲很像棉花糖",
    "我發現巷口開了新書店",
    "剛剛差點坐過站",
    "辦公室冷氣冷到發抖",
  ], 1);
  const records = toRecords(plan, (key) => key === plan[0].key ? "壞掉" : ok);
  const a = blindAB(records, CASES.slice(0, 3), 7);
  assertEquals(a, blindAB(records, CASES.slice(0, 3), 7));
  assertEquals(Object.keys(a.reveal), ["E1#1", "E2#1", "E3#1"]);
  for (const pair of Object.values(a.reveal)) {
    assertEquals(new Set([pair.甲, pair.乙]), new Set(ARMS));
  }
  assert(!/legacy|two_stage|兩段式|舊版/.test(a.markdown));
  assert(a.markdown.includes("（這一版沒有產出可用的五題）"));
  assert(a.markdown.includes("今天的雲很像棉花糖 ★"));
  const seeds = new Set(
    Array.from(
      { length: 8 },
      (_, s) => JSON.stringify(blindAB(records, CASES.slice(0, 3), s).reveal),
    ),
  );
  assert(seeds.size > 1, "不同 seed 要能換順序");
});

Deno.test("外洩檢查同 handler：進階 sentinel 只在兩段式臂擋（Codex R2 P2）", async () => {
  const plan = await buildPlan(CASES.slice(0, 1), 1);
  const [legacy, two] = ARMS.map((arm) => plan.find((p) => p.arm === arm)!);
  const raw = fakeOutput([
    "剛路過一家浮誇的甜點店",
    "今天的雲很像棉花糖",
    "我發現巷口開了新書店",
    "剛剛差點坐過站",
    "辦公室冷氣冷到發抖",
  ])
    .replace("她一句話就能接", "照類型決定主詞，不改主詞");
  const twoResult = inspectOutput(two, raw);
  assert(twoResult.promptLeak);
  assert(!twoResult.deliverable);
  const legacyResult = inspectOutput(legacy, raw);
  assert(!legacyResult.promptLeak);
});
