// 黑箱工具的純函式：挑卡規則、每次的檢查、付費閘與估價。
import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  CHIPS,
  endsWithPermissionAsk,
  endsWithQuestion,
  estimatePlan,
  type FixtureCard,
  inspect,
  parseOptions,
  planRefines,
  requestBodyFor,
  reservationUsd,
  selectCards,
  stopBeforeCall,
} from "./run.ts";

const fixtures = JSON.parse(
  await Deno.readTextFile(
    new URL(
      "../../supabase/functions/analyze-chat/testdata/guide_v3_replay_fixtures.json",
      import.meta.url,
    ),
  ),
);

function card(over: Partial<FixtureCard> = {}): FixtureCard {
  return {
    slot: 1,
    task: "push",
    method: "reaction",
    voice: "default",
    messages: ["好啊", "那就週六，我來訂位"],
    hasBlank: false,
    ...over,
  };
}

Deno.test("挑卡：20 張，推進與有空格的全收，收、共鳴、照樣寫＋標示各至少一張", () => {
  const picked = selectCards(fixtures);
  assertEquals(picked.length, 20);
  const all = fixtures.cases.flatMap((
    c: { expected: { events: FixtureCard[] } },
  ) =>
    c.expected.events.filter((e) =>
      (e as { type?: string }).type === "analysis.card"
    )
  ) as FixtureCard[];
  const pickedCards = picked.map((p) => p.card);
  assertEquals(
    pickedCards.filter((c) => c.task === "push").length,
    all.filter((c) => c.task === "push").length,
  );
  assertEquals(
    pickedCards.filter((c) => c.hasBlank).length,
    all.filter((c) => c.hasBlank).length,
  );
  for (const task of ["close", "resonate", "accept", "tension"]) {
    assert(pickedCards.some((c) => c.task === task), task);
  }
  assert(pickedCards.some((c) => c.method === "invented"));
  // 規則固定：同一份錄音每次挑一樣的卡。
  assertEquals(
    selectCards(fixtures).map((p) => `${p.caseName}#${p.card.slot}`),
    picked.map((p) => `${p.caseName}#${p.card.slot}`),
  );
});

Deno.test("計畫：每張卡四顆指令；請求帶卡片規格、多則用換行接", () => {
  const plan = planRefines(selectCards(fixtures).slice(0, 2));
  assertEquals(plan.length, 2 * CHIPS.length);
  const body = requestBodyFor(plan[0], "123e4567-e89b-42d3-a456-426614174000");
  const first = plan[0].picked.card;
  assertEquals(body.userDraft, first.messages.join("\n"));
  assertEquals(body.refineInstruction, CHIPS[0]);
  assertEquals(body.guideV3Card, {
    task: first.task,
    voice: first.voice,
    method: first.method,
  });
});

Deno.test("推進檢查：徵求同意的問句才算；結尾的語氣符號與表情不影響", () => {
  assert(endsWithPermissionAsk(["週六一起去好嗎？"]));
  assert(endsWithPermissionAsk(["好啊", "要不要週六去？😊"]));
  assert(endsWithPermissionAsk(["方便的話週六見，可以嗎?～"]));
  assert(!endsWithPermissionAsk(["週六一起去吧"]));
  assert(!endsWithPermissionAsk(["你想先在哪碰面？我配合你的時間"]));
  // 問她挑時間不是請求句。
  assert(!endsWithPermissionAsk(["週六還是週日？"]));
  assert(endsWithQuestion("週六還是週日？"));
});

Deno.test("每次檢查：則數、空格、有沒有改、預設口吻的「妳」、推進前後", () => {
  const checks = inspect(card(), ["好啊", "週六好嗎？"]);
  assertEquals(checks.countKept, true);
  assertEquals(checks.blanksKept, true);
  assertEquals(checks.changed, true);
  assertEquals(checks.defaultVoiceHasNi, false);
  assertEquals(checks.push, {
    permissionAskBefore: false,
    permissionAskAfter: true,
    questionBefore: false,
    questionAfter: true,
  });
  const blank = inspect(
    card({ task: "accept", messages: ["我是做＿＿的"], hasBlank: true }),
    ["我是做設計的，妳呢"],
  );
  assertEquals(blank.blanksKept, false);
  // 逐則比：總數一樣、但第一則被填掉、第二則多一個，也算沒留住。
  assertEquals(
    inspect(
      card({
        task: "accept",
        messages: ["我做＿＿", "住＿＿"],
        hasBlank: true,
      }),
      ["我做設計", "住＿＿，週末去＿＿"],
    ).blanksKept,
    false,
  );
  assertEquals(blank.defaultVoiceHasNi, true);
  assertEquals(blank.push, undefined);
  assertEquals(inspect(card(), ["好啊"]).countKept, false);
  assertEquals(inspect(card(), card().messages).changed, false);
});

Deno.test("付費閘：四個旗標缺一個就拒絕；dry-run 只要 tag", () => {
  assertEquals(parseOptions(["--tag=dry"]).run, false);
  assertThrows(() => parseOptions(["--tag=x", "--run"]));
  assertThrows(() =>
    parseOptions(["--tag=x", "--run", "--confirm-paid", "--max-calls=10"])
  );
  assertThrows(() => parseOptions(["--tag=x", "--max-calls=0"]));
  assertThrows(() => parseOptions(["--tag=../x"]));
  assertThrows(() => parseOptions(["--tag=x", "--model=claude-opus"]));
  const paid = parseOptions([
    "--tag=x",
    "--run",
    "--confirm-paid",
    "--max-calls=160",
    "--budget-usd=3",
  ]);
  assertEquals([paid.run, paid.maxCalls, paid.budgetUsd], [true, 160, 3]);
});

Deno.test("估價與預留：快取寫入價＋output 全滿；超過預算或次數就不送", () => {
  // 1000 字 × 1.5 = 1500 token × $2.5/M ＋ 700 × $10/M。
  assertEquals(reservationUsd(1000), (1500 * 2.5 + 700 * 10) / 1_000_000);
  assert(
    stopBeforeCall({
      stopped: false,
      calls: 0,
      maxCalls: 2,
      spentUsd: 2.99,
      reservationUsd: 0.02,
      budgetUsd: 3,
    }),
  );
  assert(
    stopBeforeCall({
      stopped: false,
      calls: 2,
      maxCalls: 2,
      spentUsd: 0,
      reservationUsd: 0.01,
      budgetUsd: 3,
    }),
  );
  assert(
    !stopBeforeCall({
      stopped: false,
      calls: 1,
      maxCalls: 2,
      spentUsd: 0.5,
      reservationUsd: 0.01,
      budgetUsd: 3,
    }),
  );
  // 同一份 system 第二次用讀快取價；上限每次微調算兩次呼叫。
  const estimate = estimatePlan(
    [{ systemChars: 1000, userChars: 1000 }, {
      systemChars: 1000,
      userChars: 1000,
    }],
    ["a", "a"],
  );
  assertEquals(estimate.maxCalls, 4);
  assertEquals(estimate.upperBoundUsd, 4 * reservationUsd(2000));
  const typicalFirst = (1500 * 2 + 1500 * 2.5 + 250 * 10) / 1_000_000;
  const typicalSecond = (1500 * 2 + 1500 * 0.2 + 250 * 10) / 1_000_000;
  assert(
    Math.abs(estimate.typicalUsd - (typicalFirst + typicalSecond)) < 1e-12,
  );
});
