// 不記帳不承諾（開關 ANALYZE_GUIDE_V3_NO_IOU，Bruce 2026-10-22 PR #97 盲選回覆；Eric 同日「回了 來處理吧」）的純函式：已經在交往、
// 她這一輪撒嬌示愛或喊累時不排推進（種子）（rules.ts withoutCoupleSeed、plan.ts），其他推進與固定排法照舊；讀局面開關開時多一欄
// herTired（提示詞 herAffection 下面那一行、schema、檢查）；寫卡「這一步只寫訊息」第二條換成多記帳、承諾補償說法的那一句（其他字
// 不動）；兩組外洩哨兵（讀局面那一行比判讀、寫卡那一句只比卡片）與誤擋；跟甜話短回一起開時的排法。沒開時一律跟今天一樣。對話全部
// 新寫。
import {
  assert,
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { TENSION_STYLE_EXPLAIN_SENTINELS, vetExplanation } from "./explain.ts";
import { finalizeCard, vetCoachText } from "./finalize.ts";
import { planTurn } from "./plan.ts";
import {
  HER_TIRED_FIELD,
  parseTwoStageTags,
  READ_TAGS_SCHEMA,
  READ_TAGS_SCHEMA_TWO_STAGE,
  READ_TAGS_SCHEMA_TWO_STAGE_SWEET,
  type ReadTags,
  type TwoStageTags,
  withHerTired,
  type WorthyLine,
} from "./read_tags.ts";
import { RELATION_LEAK_SENTINELS } from "./relation.ts";
import {
  arrangeCards,
  type CardSpec,
  type PushAction,
  withoutCoupleSeed,
} from "./rules.ts";
import { NO_SAFETY_HITS } from "./safety.ts";
import { latestHerMessages, toTurns, type Turn } from "./turns.ts";
import {
  cardSpecLineTwoStage,
  HER_TIRED_NOTE,
  NO_IOU_DIRECT_REPLY_LINE,
  NO_IOU_READ_LEAK_SENTINELS,
  NO_IOU_READ_SENTINELS,
  NO_IOU_WRITER_SENTINELS,
  READ_TAGS_SCHEMA_TWO_STAGE_SWEET_WITH_RELATION,
  READ_TAGS_SCHEMA_TWO_STAGE_WITH_RELATION,
  READ_TWO_STAGE_NOTES,
  readSystemPromptTwoStage,
  readSystemPromptTwoStageWithRelation,
  readTwoStageNotes,
  SHORT_PRAISE_WRITER_SENTINELS,
  SWEET_READ_LEAK_SENTINELS,
  SWEET_SHORT_CARD_PART,
  TENSION_STYLE_WRITER_SENTINELS,
  TWO_STAGE_READ_LEAK_SENTINELS,
  TWO_STAGE_WRITER_SENTINELS,
  WRITE_NATURAL_RULES,
  writeNaturalRules,
  writeSystemPromptTwoStage,
} from "./two_stage_prompts.ts";

function tags(over: Partial<ReadTags> = {}): ReadTags {
  return {
    light: "green",
    herMove: "生活",
    herMoodBad: false,
    drunkOrLateNight: false,
    inviteReadiness: "沒機會",
    cancelHasAlternative: false,
    retreating: false,
    declinedOrBoundary: false,
    explicitRejection: false,
    blocked: false,
    risk: false,
    selfHarmSignal: false,
    minorSignal: false,
    needsHisFacts: false,
    identityQuestion: false,
    hisStatedFacts: [],
    hasHisVoiceSample: true,
    replyWillingness: "high",
    worthyBallCount: 2,
    herTurnsPerfunctory: [],
    matchedEntries: [],
    readForUser: "你們在交往，她今天跑了好幾個客戶。",
    waitFor: "",
    ...over,
  };
}

const w = (
  line: number,
  kind: WorthyLine["kind"],
  label = "x",
): WorthyLine => ({ line, label, kind });

/// 讀局面的兩段式欄位（開關開時多 herTired）：預設已經在交往、她沒撒嬌也沒喊累。
function extras(over: Partial<TwoStageTags> = {}): TwoStageTags {
  return {
    establishedCouple: true,
    herAffection: false,
    herTired: false,
    herHappyShare: false,
    worthyLines: [w(1, "其他", "喊累"), w(2, "其他", "早點睡")],
    ...over,
  };
}

/// 他傳過兩則（沒開時排卡第一張是推進（種子）），她最新這一輪是 latest。
function chat(latest: readonly string[]): Turn[] {
  return toTurns([
    { isFromMe: true, content: "今天外勤跑哪" },
    { isFromMe: false, content: "跑了三個客戶" },
    { isFromMe: true, content: "這麼拚 晚點打給你" },
    ...latest.map((content) => ({ isFromMe: false, content })),
  ]);
}

/// 她開心地喊累、說要早點睡（沒撒嬌、情緒不差）。
const TIRED = chat(["腳快斷了哈哈", "今晚要早點睡"]);

const ON = { noIou: true } as const;
const plan = (
  turns: readonly Turn[],
  two: TwoStageTags | undefined,
  t: ReadTags = tags(),
  options: { noIou?: boolean; sweetShort?: boolean } = ON,
) => planTurn(turns, t, NO_SAFETY_HITS, undefined, two, options);
const tasksOf = (specs: readonly CardSpec[]) => specs.map((s) => s.task);
const specLines = (specs: readonly CardSpec[], turns: readonly Turn[]) =>
  specs.map((s, i) => cardSpecLineTwoStage(s, i + 1, latestHerMessages(turns)));
const withoutAnswer = (specs: readonly CardSpec[]) =>
  specs.map(({ answer: _answer, ...rest }) => rest);

// ── 種子規則 ───────────────────────────────────────────────────────────────

Deno.test("種子：已經在交往、她撒嬌示愛——這次不推進：push 是 null、沒有推進的卡、張數照舊，任務照沒有推進的排法；沒開照舊排種子", () => {
  const two = extras({ herAffection: true });
  const off = plan(TIRED, two, tags(), {});
  const on = plan(TIRED, two);
  assertEquals(off.push, "種子");
  assertEquals(tasksOf(off.specs), ["推進", "接住", "接住", "接住", "接住"]);
  assertEquals(off.specs[0].push, "種子");
  assertEquals(off.specs[0].questionBudget, 0);
  assertEquals(on.push, null);
  assertEquals(on.specs.length, off.specs.length);
  assertEquals(tasksOf(on.specs), ["接住", "接住", "接住", "接住", "接住"]);
  assertEquals(on.specs.every((s) => s.push === null), true);
  assertEquals(on.specs.every((s) => s.questionBudget === 1), true);
  // 跟本來就沒有推進的排法一模一樣（arrangeCards 給 push null）；回她哪一則照常指定。
  assertEquals(
    withoutAnswer(on.specs),
    arrangeCards({ kind: "send" }, null, tags(), two),
  );
  assertEquals(on.specs.every((s) => s.answer?.main.line === 2), true);
  // 規格裡沒有「推進（種子）」也沒有「不問問題」。
  for (const line of specLines(on.specs, TIRED)) {
    assertEquals(line.includes("推進"), false, line);
    assertEquals(line.includes("不問問題"), false, line);
  }
  assert(specLines(off.specs, TIRED)[0].startsWith("1. 任務：推進（種子）｜"));
  // 計畫的其他欄位（決定、判讀、條目、邀約進度、誇法）不變。
  assertEquals({ ...on, push: off.push, specs: off.specs }, off);
});

Deno.test("種子：已經在交往、她喊累（herTired）但沒撒嬌——一樣不推進；撒嬌又喊累也一樣", () => {
  for (
    const two of [
      extras({ herTired: true }),
      extras({ herAffection: true, herTired: true }),
    ]
  ) {
    const off = plan(TIRED, two, tags(), {});
    const on = plan(TIRED, two);
    assertEquals(off.push, "種子");
    assertEquals(on.push, null);
    assertEquals(on.specs.length, off.specs.length);
    assertEquals(on.specs.some((s) => s.task === "推進"), false);
    assertEquals(
      withoutAnswer(on.specs),
      arrangeCards({ kind: "send" }, null, tags(), two),
    );
  }
});

Deno.test("種子：已經在交往但她沒撒嬌也沒喊累——照舊排種子，跟沒開一模一樣", () => {
  const plain = chat(["晚餐吃了拉麵", "湯頭超濃"]);
  const two = extras();
  assertEquals(plan(plain, two), plan(plain, two, tags(), {}));
  assertEquals(plan(plain, two).push, "種子");
  assertEquals(plan(plain, two).specs[0].task, "推進");
});

Deno.test("種子：還沒交往——她撒嬌或喊累都照舊排種子，跟沒開一模一樣", () => {
  for (
    const two of [
      extras({ establishedCouple: false, herAffection: true }),
      extras({ establishedCouple: false, herTired: true }),
      extras({ establishedCouple: false, herAffection: true, herTired: true }),
    ]
  ) {
    const on = plan(TIRED, two);
    assertEquals(on, plan(TIRED, two, tags(), {}));
    assertEquals(on.push, "種子");
    assertEquals(on.specs[0].task, "推進");
  }
});

Deno.test("其他推進照舊：具體邀約（她自己提見面、含糊答應、她開窗）、說定（明確答應、取消但給了別的時間）、改天（取消沒給時間），交往中她撒嬌又喊累也跟沒開一模一樣", () => {
  const two = extras({ herAffection: true, herTired: true });
  const cases: [string, ReadTags, PushAction][] = [
    ["她自己提見面", tags({ inviteReadiness: "她自己提見面" }), "具體邀約"],
    ["含糊答應", tags({ inviteReadiness: "含糊答應" }), "具體邀約"],
    ["她開窗", tags({ herMove: "開窗" }), "具體邀約"],
    ["明確答應", tags({ inviteReadiness: "明確答應" }), "說定"],
    [
      "取消但給了別的時間",
      tags({ inviteReadiness: "她取消了", cancelHasAlternative: true }),
      "說定",
    ],
    ["取消沒給時間", tags({ inviteReadiness: "她取消了" }), "改天"],
  ];
  for (const [name, t, push] of cases) {
    const on = plan(TIRED, two, t);
    assertEquals(on, plan(TIRED, two, t, {}), name);
    assertEquals(on.push, push, name);
    assert(on.specs.some((s) => s.task === "推進" && s.push === push), name);
  }
});

Deno.test("本來就不推進的照舊：她情緒差、喝醉或深夜、在退、紅燈、標到風險，交往中她撒嬌又喊累也跟沒開一模一樣", () => {
  const two = extras({ herAffection: true, herTired: true });
  for (
    const [name, t] of [
      ["情緒差", tags({ herMoodBad: true })],
      ["喝醉或深夜", tags({ drunkOrLateNight: true })],
      ["在退", tags({ retreating: true })],
      ["紅燈", tags({ light: "red" })],
      ["風險", tags({ risk: true })],
    ] as const
  ) {
    const on = plan(TIRED, two, t);
    assertEquals(on, plan(TIRED, two, t, {}), name);
    assertEquals(on.push, null, name);
  }
});

Deno.test("黃燈：種子不用等綠燈，所以黃燈交往中她撒嬌或喊累也拿掉種子（3 張都接住）；黃燈沒撒嬌沒喊累照舊排種子", () => {
  const yellow = tags({ light: "yellow" });
  const off = plan(TIRED, extras({ herTired: true }), yellow, {});
  const on = plan(TIRED, extras({ herTired: true }), yellow);
  assertEquals(tasksOf(off.specs), ["推進", "接住", "接住"]);
  assertEquals(tasksOf(on.specs), ["接住", "接住", "接住"]);
  assertEquals(on.push, null);
  const plain = plan(TIRED, extras(), yellow);
  assertEquals(plain, plan(TIRED, extras(), yellow, {}));
  assertEquals(plain.push, "種子");
});

Deno.test("固定排法照舊：婉拒收尾、詐騙換地方（B47）、B34／B46／B33 不推進、自傷、未成年、封鎖、明確拒絕、他是最後一則都跟沒開一模一樣", () => {
  const two = extras({ herAffection: true, herTired: true });
  const same: [string, ReadTags, readonly Turn[]][] = [
    ["婉拒", tags({ declinedOrBoundary: true }), TIRED],
    ["詐騙換地方", tags({ matchedEntries: ["B47"] }), TIRED],
    ["她說太快了（B34）", tags({ matchedEntries: ["B34"] }), TIRED],
    ["對自己的投入不好意思（B46）", tags({ matchedEntries: ["B46"] }), TIRED],
    ["兩次提案都被帶過（B33）", tags({ matchedEntries: ["B33"] }), TIRED],
    ["自傷", tags({ selfHarmSignal: true }), TIRED],
    ["未成年", tags({ minorSignal: true }), TIRED],
    ["封鎖", tags({ blocked: true }), TIRED],
    ["明確拒絕", tags({ explicitRejection: true }), TIRED],
    [
      "他是最後一則",
      tags(),
      toTurns([
        { isFromMe: false, content: "腳快斷了哈哈" },
        { isFromMe: true, content: "早點睡" },
      ]),
    ],
  ];
  for (const [name, t, turns] of same) {
    assertEquals(plan(turns, two, t), plan(turns, two, t, {}), name);
  }
  assertEquals(
    plan(TIRED, two, tags({ declinedOrBoundary: true })).specs.length,
    1,
  );
  const venue = plan(TIRED, two, tags({ matchedEntries: ["B47"] }));
  assertEquals(venue.push, "換地方");
  assertEquals(tasksOf(venue.specs), ["推進", "收", "推進"]);
});

Deno.test("沒有兩段式的讀局面欄位（兩段式沒開）時，開關開著也跟今天一模一樣（還是排種子）", () => {
  const on = plan(TIRED, undefined);
  assertEquals(on, plan(TIRED, undefined, tags(), {}));
  assertEquals(on.push, "種子");
});

Deno.test("withoutCoupleSeed：只拿掉交往中她撒嬌或喊累的種子；herTired 沒給（開關沒開時讀局面沒有這欄）當沒喊累；其他推進一律原樣", () => {
  const couple = { establishedCouple: true, herAffection: false };
  assertEquals(
    withoutCoupleSeed("種子", { ...couple, herAffection: true }),
    null,
  );
  assertEquals(withoutCoupleSeed("種子", { ...couple, herTired: true }), null);
  assertEquals(withoutCoupleSeed("種子", couple), "種子");
  assertEquals(
    withoutCoupleSeed("種子", { ...couple, herTired: false }),
    "種子",
  );
  assertEquals(
    withoutCoupleSeed("種子", {
      establishedCouple: false,
      herAffection: true,
      herTired: true,
    }),
    "種子",
  );
  for (
    const push of ["具體邀約", "說定", "改天", "換地方", null] as const
  ) {
    assertEquals(
      withoutCoupleSeed(push, {
        ...couple,
        herAffection: true,
        herTired: true,
      }),
      push,
      String(push),
    );
  }
});

// ── 跟甜話短回一起開 ───────────────────────────────────────────────────────────

Deno.test("跟甜話短回一起開、她只傳一句很短的甜話（S2 的形狀）：3 張都是接住、都短短回那句；只開甜話短回時第一張是推進（種子）、也帶短回指示；只開這個 4 張都接住", () => {
  const turns = chat(["想你了🥺"]);
  const two = extras({
    herAffection: true,
    worthyLines: [w(1, "撒嬌", "想他")],
  });
  const t = tags({ worthyBallCount: 1 });
  const both = plan(turns, two, t, { sweetShort: true, noIou: true });
  assertEquals(both.push, null);
  assertEquals(tasksOf(both.specs), ["接住", "接住", "接住"]);
  assertEquals(both.specs.every((s) => s.sweetShort === true), true);
  assertEquals(both.specs.map((s) => s.voice), ["照他", "預設", "照他"]);
  for (const line of specLines(both.specs, turns)) {
    assert(
      line.includes(`這張接：她的「想你了」｜${SWEET_SHORT_CARD_PART}｜`),
      line,
    );
    assertEquals(line.includes("推進"), false, line);
  }
  const sweetOnly = plan(turns, two, t, { sweetShort: true });
  assertEquals(sweetOnly.push, "種子");
  assertEquals(tasksOf(sweetOnly.specs), ["推進", "接住", "接住"]);
  assertEquals(sweetOnly.specs.every((s) => s.sweetShort === true), true);
  const noIouOnly = plan(turns, two, t, { noIou: true });
  assertEquals(tasksOf(noIouOnly.specs), ["接住", "接住", "接住", "接住"]);
  assertEquals(noIouOnly.specs.some((s) => s.sweetShort), false);
  const neither = plan(turns, two, t, {});
  assertEquals(tasksOf(neither.specs), ["推進", "接住", "接住", "接住"]);
});

Deno.test("跟甜話短回一起開、她先撒嬌一句很短的甜話再說腳痠（S1 的形狀）：沒有推進可以跳過，第一張就是回甜話的那張，其他卡回腳痠；張數照舊", () => {
  const turns = chat(["想你了🥺", "今天跑了四家店 腳快不行了"]);
  const two = extras({
    herAffection: true,
    herTired: true,
    worthyLines: [w(1, "撒嬌", "想他"), w(2, "其他", "腳痠")],
  });
  const both = plan(turns, two, tags(), { sweetShort: true, noIou: true });
  const sweetOnly = plan(turns, two, tags(), { sweetShort: true });
  assertEquals(both.specs.length, sweetOnly.specs.length);
  assertEquals(tasksOf(both.specs), ["接住", "接住", "接住", "接住", "接住"]);
  assertEquals(
    both.specs.flatMap((s, i) => s.sweetShort ? [i] : []),
    [0],
  );
  assertEquals(both.specs[0].answer, { main: { line: 1, with: [] } });
  for (const spec of both.specs.slice(1)) {
    assertEquals(spec.answer, { main: { line: 2, with: [] } });
  }
  // 只開甜話短回：第一張推進（種子）回腳痠，第二張才回甜話。
  assertEquals(sweetOnly.specs[0].task, "推進");
  assertEquals(
    sweetOnly.specs.flatMap((s, i) => s.sweetShort ? [i] : []),
    [1],
  );
});

// ── 讀局面 ─────────────────────────────────────────────────────────────────

Deno.test("讀局面：沒開時提示詞跟今天一字不差；開時只在 herAffection 那一行下面多 herTired 那一行，拿掉就跟沒開一樣；關係訊號、甜話短回各自開不開都一樣（四種）", () => {
  assertEquals(
    HER_TIRED_NOTE,
    "- herTired：她這一輪在喊累，或說身體痠痛、不舒服，例如說好累、腳很痠、頭痛、沒睡飽。",
  );
  const affectionLine = READ_TWO_STAGE_NOTES.split("\n").find((l) =>
    l.startsWith("- herAffection：")
  )!;
  for (
    const fn of [
      readSystemPromptTwoStage,
      readSystemPromptTwoStageWithRelation,
    ]
  ) {
    for (const sweetShort of [false, true]) {
      const off = fn(undefined, undefined, undefined, { sweetShort });
      assertEquals(
        fn(undefined, undefined, undefined, { sweetShort, noIou: false }),
        off,
      );
      const on = fn(undefined, undefined, undefined, {
        sweetShort,
        noIou: true,
      });
      assert(on.includes(`${affectionLine}\n${HER_TIRED_NOTE}\n`));
      assertEquals(on.split(HER_TIRED_NOTE).length - 1, 1);
      assertEquals(on.replace(`\n${HER_TIRED_NOTE}`, ""), off);
      assertEquals(off.includes(HER_TIRED_FIELD), false);
    }
  }
  // 都沒開就是今天的原文。
  assertEquals(readTwoStageNotes(), READ_TWO_STAGE_NOTES);
  assertEquals(
    readTwoStageNotes({ noIou: true }).replace(`\n${HER_TIRED_NOTE}`, ""),
    READ_TWO_STAGE_NOTES,
  );
});

Deno.test("讀局面：schema 開時在 herAffection 後面多 herTired（布林、必填），兩段式的四種 schema 都一樣、其他欄位與順序不變；原本那幾份不動；沒有 herAffection 就丟錯", () => {
  type Schema = { required: string[]; properties: Record<string, unknown> };
  for (
    const base of [
      READ_TAGS_SCHEMA_TWO_STAGE,
      READ_TAGS_SCHEMA_TWO_STAGE_SWEET,
      READ_TAGS_SCHEMA_TWO_STAGE_WITH_RELATION,
      READ_TAGS_SCHEMA_TWO_STAGE_SWEET_WITH_RELATION,
    ]
  ) {
    const before = JSON.stringify(base);
    const s = withHerTired(base) as Schema;
    const b = base as Schema;
    assertEquals(
      s.required.indexOf(HER_TIRED_FIELD),
      b.required.indexOf("herAffection") + 1,
    );
    const keys = Object.keys(s.properties);
    assertEquals(
      keys.indexOf(HER_TIRED_FIELD),
      keys.indexOf("herAffection") + 1,
    );
    assertEquals(s.properties[HER_TIRED_FIELD], { type: "boolean" });
    // 拿掉 herTired 就跟原本那份一字不差（key 的順序也一樣）；原本那份沒被改到。
    const back = JSON.parse(JSON.stringify(s));
    back.required = back.required.filter((k: string) => k !== HER_TIRED_FIELD);
    delete back.properties[HER_TIRED_FIELD];
    assertEquals(JSON.stringify(back), before);
    assertEquals(JSON.stringify(base), before);
    assertEquals(HER_TIRED_FIELD in b.properties, false);
  }
  // 關係訊號也開：關係三欄照舊在最後。
  const rel = withHerTired(READ_TAGS_SCHEMA_TWO_STAGE_SWEET_WITH_RELATION) as {
    required: string[];
  };
  assertEquals(rel.required.slice(-8), [
    "establishedCouple",
    "herAffection",
    "herTired",
    "herHappyShare",
    "worthyLines",
    "gameStage",
    "heatScore",
    "dimensions",
  ]);
  assertThrows(() => withHerTired(READ_TAGS_SCHEMA));
});

Deno.test("讀局面：解析只有開時才收 herTired——缺了或不是 true 當 false；沒開時回的欄位裡沒有 herTired（讀局面多給也不收）；跟甜話短回一起開時撒嬌照收", () => {
  const read = {
    establishedCouple: true,
    herAffection: false,
    herHappyShare: false,
    worthyLines: [{ line: 1, label: "腳快斷了", kind: "情感" }],
  };
  assertEquals(
    parseTwoStageTags({ ...read, herTired: true }, { noIou: true })?.herTired,
    true,
  );
  assertEquals(
    parseTwoStageTags({ ...read, herTired: false }, { noIou: true })?.herTired,
    false,
  );
  assertEquals(parseTwoStageTags(read, { noIou: true })?.herTired, false);
  for (const bad of ["true", 1, null]) {
    assertEquals(
      parseTwoStageTags({ ...read, herTired: bad }, { noIou: true })?.herTired,
      false,
      String(bad),
    );
  }
  assertEquals(
    Object.keys(parseTwoStageTags({ ...read, herTired: true }, ON)!),
    [
      "establishedCouple",
      "herAffection",
      "herTired",
      "herHappyShare",
      "worthyLines",
    ],
  );
  // 沒開：沒有 herTired 這個欄位，讀局面多給也一樣（跟今天回的一模一樣）。
  const off = parseTwoStageTags({ ...read, herTired: true });
  assertEquals(off, parseTwoStageTags(read));
  assertEquals(off !== null && HER_TIRED_FIELD in off, false);
  assertEquals(
    parseTwoStageTags({ ...read, herTired: true }, { noIou: false }),
    off,
  );
  // 其他欄位壞了照舊算讀局面失敗。
  assertEquals(
    parseTwoStageTags({ ...read, herAffection: "yes", herTired: true }, ON),
    null,
  );
  // 跟甜話短回一起開：撒嬌只有甜話短回開時才收。
  const sweet = {
    ...read,
    herAffection: true,
    herTired: true,
    worthyLines: [{ line: 1, label: "想他", kind: "撒嬌" }],
  };
  assertEquals(parseTwoStageTags(sweet, { noIou: true }), null);
  assertEquals(
    parseTwoStageTags(sweet, { sweetShort: true, noIou: true })?.herTired,
    true,
  );
});

// ── 寫卡 ───────────────────────────────────────────────────────────────────

const OLD_DIRECT_LINE = WRITE_NATURAL_RULES.split("\n").find((l) =>
  l.startsWith("- 直接回她說的事。")
)!;

Deno.test("寫卡：沒開時系統提示詞跟今天一字不差；開時只換「這一步只寫訊息」第二條，換回原本那一句就跟沒開一樣（帶張力改寫法開不開都一樣）；其他條一字不動", () => {
  assertEquals(
    NO_IOU_DIRECT_REPLY_LINE,
    "- 直接回她說的事。判斷、策略、招式的名稱、對她的評價（包括評她的語氣和用字）、替自己說明心態、原則或反應的話（例如「我收到了」「我收下了」「記下了」），以及像在記帳、討人情，或說要幫她做什麼、給她什麼來補償的話（例如「幫你記一筆」「都算我的」「換我來犒賞你」），都不寫進訊息；為什麼這樣回，下一步會另外說明給用戶。",
  );
  assertEquals(
    writeSystemPromptTwoStage(),
    writeSystemPromptTwoStage(
      undefined,
      undefined,
      undefined,
      { noIou: false },
    ),
  );
  for (const tensionStyle of [false, true]) {
    const off = writeSystemPromptTwoStage(undefined, undefined, undefined, {
      tensionStyle,
    });
    const on = writeSystemPromptTwoStage(undefined, undefined, undefined, {
      tensionStyle,
      noIou: true,
    });
    assert(on.includes(NO_IOU_DIRECT_REPLY_LINE));
    assertEquals(on.includes(OLD_DIRECT_LINE), false);
    assertEquals(on.replace(NO_IOU_DIRECT_REPLY_LINE, OLD_DIRECT_LINE), off);
  }
  assertEquals(writeNaturalRules(), WRITE_NATURAL_RULES);
  const onLines = writeNaturalRules({ noIou: true }).split("\n");
  const offLines = WRITE_NATURAL_RULES.split("\n");
  assertEquals(onLines.length, offLines.length);
  offLines.forEach((line, i) => {
    assertEquals(
      onLines[i],
      line === OLD_DIRECT_LINE ? NO_IOU_DIRECT_REPLY_LINE : line,
    );
  });
  // 新的那一句保留原本那一句的每一段（只把「，以及」挪到新加的說法前面），沒有另開一條。
  for (
    const part of [
      "- 直接回她說的事。判斷、策略、招式的名稱、對她的評價（包括評她的語氣和用字）",
      "替自己說明心態、原則或反應的話（例如「我收到了」「我收下了」「記下了」）",
      "，都不寫進訊息；為什麼這樣回，下一步會另外說明給用戶。",
    ]
  ) {
    assert(OLD_DIRECT_LINE.includes(part), part);
    assert(NO_IOU_DIRECT_REPLY_LINE.includes(part), part);
  }
});

// ── 哨兵 ───────────────────────────────────────────────────────────────────

Deno.test("寫卡的外洩哨兵：都照抄自新的那一句、夠長、沒開的提示詞裡沒有；正常的卡（晚餐我來想、吃的我來處理、先休息一下…）不會被擋，照抄那一句（夾空白也一樣）就拿掉那張", () => {
  const off = writeSystemPromptTwoStage(undefined, undefined, undefined, {
    tensionStyle: true,
  });
  assert(NO_IOU_WRITER_SENTINELS.length > 0);
  for (const s of NO_IOU_WRITER_SENTINELS) {
    assert(NO_IOU_DIRECT_REPLY_LINE.includes(s), s);
    assertEquals(off.includes(s), false, s);
    // 共用比對不比 8 字以下的哨兵。
    assert([...s.replace(/\s+/g, "")].length >= 8, s);
  }
  // 正式流程開著時卡片比的哨兵（兩段式、帶張力改寫法、這個）。
  const sentinels = [
    ...TWO_STAGE_WRITER_SENTINELS,
    ...TENSION_STYLE_WRITER_SENTINELS,
    ...NO_IOU_WRITER_SENTINELS,
  ];
  const card = (messages: string[]) =>
    finalizeCard(
      { card: 1, messages, hasInventedDetail: false, expectedReaction: "" },
      { voice: "預設" },
      "腳快斷了哈哈\n今晚要早點睡",
      sentinels,
    );
  for (
    const messages of [
      ["晚餐我來想"],
      ["吃的我來處理"],
      ["先休息一下"],
      ["辛苦了 先休息一下", "吃的我來處理"],
      ["腳還好嗎 回去泡個腳早點睡"],
      ["今天也太拚了 晚點打給你"],
      ["我也想你"],
    ]
  ) {
    assertEquals(card(messages).ok, true, messages.join("／"));
  }
  for (
    const leak of [
      "像在記帳、討人情，或說要幫她做什麼",
      "像在記帳、討人情， 或說要 幫她做什麼",
      "給她什麼來補償的話",
      "給她什麼來 補償的話",
    ]
  ) {
    const out = card(["先休息一下", leak]);
    assertEquals(out.ok, false, leak);
    assertEquals(!out.ok && out.reason, "prompt_leak");
  }
});

Deno.test("寫卡那一句只比卡片：說明看不到寫卡的系統提示詞，正式流程給說明多比的哨兵裡沒有這幾句，說明寫到也照送", () => {
  // 開關都開時正式流程給說明多比的哨兵（stream_flow.ts explainCards）：帶張力改寫法、短版稱讚的；這個開關的不在裡面。
  const explainExtra = [
    ...TENSION_STYLE_EXPLAIN_SENTINELS,
    ...TENSION_STYLE_WRITER_SENTINELS,
    ...SHORT_PRAISE_WRITER_SENTINELS,
  ];
  for (const s of NO_IOU_WRITER_SENTINELS) {
    assertEquals(explainExtra.includes(s), false, s);
  }
  for (
    const text of [
      "她喊累，這張先關心她的腳，沒有說要幫她做什麼、給她什麼來補償的話，讀起來比較自然。",
      "她說腳快斷了，你先讓她休息，語氣輕鬆不刻意。",
    ]
  ) {
    assertEquals(vetExplanation(text, explainExtra).ok, true, text);
  }
});

Deno.test("讀局面的外洩哨兵：都照抄自 herTired 那一行、夠長、沒開的提示詞裡沒有；判讀照抄就不給，一般的判讀（她說好累、腳很痠）照給", () => {
  const off = readSystemPromptTwoStageWithRelation(
    undefined,
    undefined,
    undefined,
    { sweetShort: true },
  );
  const on = readSystemPromptTwoStageWithRelation(
    undefined,
    undefined,
    undefined,
    { sweetShort: true, noIou: true },
  );
  assert(NO_IOU_READ_SENTINELS.length > 0);
  for (const s of NO_IOU_READ_SENTINELS) {
    assert(HER_TIRED_NOTE.includes(s), s);
    assert(on.includes(s), s);
    assertEquals(off.includes(s), false, s);
    assert([...s.replace(/\s+/g, "")].length >= 8, s);
    assertEquals(
      vetCoachText(`她今天跑了好幾個客戶。${s}`, NO_IOU_READ_LEAK_SENTINELS).ok,
      false,
      s,
    );
  }
  // 正式流程開著時判讀比的哨兵（兩段式、關係訊號、甜話短回、這個）：一般判讀照給。
  const all = [
    ...TWO_STAGE_READ_LEAK_SENTINELS,
    ...RELATION_LEAK_SENTINELS,
    ...SWEET_READ_LEAK_SENTINELS,
    ...NO_IOU_READ_LEAK_SENTINELS,
  ];
  for (
    const judgment of [
      "你們在交往，她跑了一天外勤，說好累、腳很痠，想早點睡。",
      "她喊累也說頭痛，先關心她的身體。",
      "她今天沒睡飽、腳很痠，但心情不錯，在跟你分享一天。",
      "她在喊累，不是在生你的氣。",
    ]
  ) {
    assertEquals(vetCoachText(judgment, all).ok, true, judgment);
  }
});
