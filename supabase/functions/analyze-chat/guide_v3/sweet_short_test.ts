// 甜話短回（開關 ANALYZE_GUIDE_V3_SWEET_SHORT，Eric 2026-10-22「照預設」）的純函式：怎麼認她這一輪有沒有很短的甜話（只看讀局面
// 的標記與字數，不限本來先回的那則；她問了他什麼就不算）、認到之後怎麼排卡（只有一張回那句、其他卡回她別的話、沒有別的話就少
// 出幾張），以及規格多的那一段與它的外洩哨兵（只比卡片）。沒開或沒認到時一律跟今天一樣。對話全部新寫。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  explainUserPrompt,
  TENSION_STYLE_EXPLAIN_SENTINELS,
  vetExplanation,
} from "./explain.ts";
import { finalizeCard } from "./finalize.ts";
import { planTurn } from "./plan.ts";
import type { ReadTags, TwoStageTags, WorthyLine } from "./read_tags.ts";
import {
  arrangeSweetShort,
  type CardSpec,
  herLineChars,
  SWEET_SHORT_CARD_COUNT,
  SWEET_SHORT_MAX_CHARS,
  sweetShortLine,
} from "./rules.ts";
import { NO_SAFETY_HITS } from "./safety.ts";
import { latestHerMessages, toTurns, type Turn } from "./turns.ts";
import {
  cardSpecLineTwoStage,
  SHORT_PRAISE_WRITER_SENTINELS,
  SWEET_SHORT_CARD_PART,
  SWEET_SHORT_WRITER_SENTINELS,
  TENSION_STYLE_WRITER_SENTINELS,
  TWO_STAGE_WRITER_SENTINELS,
  writeUserPromptTwoStage,
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
    readForUser: "你們在交往，她跟你撒嬌。",
    waitFor: "",
    ...over,
  };
}

function extras(over: Partial<TwoStageTags> = {}): TwoStageTags {
  return {
    establishedCouple: true,
    herAffection: true,
    herHappyShare: false,
    worthyLines: [],
    ...over,
  };
}

const w = (
  line: number,
  kind: WorthyLine["kind"],
  label = "x",
): WorthyLine => ({
  line,
  label,
  kind,
});

/// 他傳過兩則（排卡第一張是推進（種子）），她最新這一輪是 latest。
function chat(latest: readonly string[]): Turn[] {
  return toTurns([
    { isFromMe: true, content: "今天還好嗎" },
    { isFromMe: false, content: "還行 剛下班" },
    { isFromMe: true, content: "晚點打給你" },
    ...latest.map((content) => ({ isFromMe: false, content })),
  ]);
}

/// 她撒嬌一句很短的甜話、再說腿很緊（Bruce 2026-10-22 試的形狀，句子全新）。
const SWEET_LEGS = chat(["想你了🥺", "今天站了一整天 小腿好緊"]);
const SWEET_LEGS_LINES = [w(1, "情感", "想他"), w(2, "其他", "小腿緊")];
/// 她只傳那句甜話。
const SWEET_ONLY = chat(["想你了🥺"]);
const SWEET_ONLY_LINES = [w(1, "情感", "想他")];

const ON = { sweetShort: true } as const;
const plan = (
  turns: readonly Turn[],
  two: TwoStageTags,
  t: ReadTags = tags(),
  options: { sweetShort?: boolean } = ON,
) => planTurn(turns, t, NO_SAFETY_HITS, undefined, two, options);
const marked = (specs: readonly CardSpec[]) =>
  specs.flatMap((s, i) => s.sweetShort ? [i] : []);
/// 每張卡規格裡指到她哪幾則（main、extra）。
const linesOf = (spec: CardSpec) =>
  [
    spec.answer?.main.line,
    spec.answer?.extra?.line,
  ].filter((x): x is number => x !== undefined);
const specLines = (specs: readonly CardSpec[], turns: readonly Turn[]) =>
  specs.map((s, i) => cardSpecLineTwoStage(s, i + 1, latestHerMessages(turns)));

// ── 認甜話短句 ─────────────────────────────────────────────────────────────

Deno.test("認甜話：她撒嬌、有一則標成情感而且很短，就回那則；herAffection false 就不算", () => {
  const her = ["想你了🥺", "今天站了一整天 小腿好緊"];
  assertEquals(
    sweetShortLine(extras({ worthyLines: SWEET_LEGS_LINES }), her),
    { line: 1, with: [] },
  );
  assertEquals(
    sweetShortLine(
      extras({ herAffection: false, worthyLines: SWEET_LEGS_LINES }),
      her,
    ),
    null,
  );
  // 已經在交往不是條件：還在曖昧、她撒嬌也算。
  assertEquals(
    sweetShortLine(
      extras({ establishedCouple: false, worthyLines: SWEET_LEGS_LINES }),
      her,
    ),
    { line: 1, with: [] },
  );
});

Deno.test("認甜話：那則標成其他（不是情感）就不算", () => {
  assertEquals(
    sweetShortLine(extras({ worthyLines: [w(1, "其他")] }), ["想你了"]),
    null,
  );
});

Deno.test("認甜話：字數照 SWEET_SHORT_MAX_CHARS（6）——6 個字算、7 個字不算；標點、空白、表情不算字", () => {
  assertEquals(SWEET_SHORT_MAX_CHARS, 6);
  const one = (text: string) =>
    sweetShortLine(extras({ worthyLines: [w(1, "情感")] }), [text]);
  assertEquals(herLineChars("好想好想你喔"), 6);
  assertEquals(one("好想好想你喔"), { line: 1, with: [] });
  assertEquals(herLineChars("好想好想你喔喔"), 7);
  assertEquals(one("好想好想你喔喔"), null);
  assertEquals(herLineChars("好想 好想你喔！！～🥺❤️"), 6);
  assertEquals(one("好想 好想你喔！！～🥺❤️"), { line: 1, with: [] });
});

Deno.test("認甜話：問他優先——本來先回的那則是問他（她同一輪也問了他），就算有很短的甜話也不算，照今天每張卡都先回她問的那句", () => {
  for (
    const [lines, her] of [
      [[w(1, "情感"), w(2, "問他")], ["想你了", "你今天幾點下班"]],
      [[w(1, "問他"), w(2, "情感")], ["你今天幾點下班", "想你了"]],
      [
        [w(1, "情感"), w(2, "問他"), w(3, "情感")],
        ["抱抱", "你今天幾點下班", "今天站了一整天 小腿好緊"],
      ],
    ] as const
  ) {
    assertEquals(sweetShortLine(extras({ worthyLines: lines }), her), null);
  }
});

Deno.test("認甜話：引用回覆的前綴不算她這一則的字（被引用的那句再長也不算）；她自己那段長就不算", () => {
  const one = (text: string) =>
    sweetShortLine(extras({ worthyLines: [w(1, "情感")] }), [text]);
  const longQuote = "（引用：「明天幾點的高鐵 要不要我去車站送你」）想你";
  assertEquals(herLineChars(longQuote), 2);
  assertEquals(one(longQuote), { line: 1, with: [] });
  assertEquals(one("（引用：「好」）今天站了一整天腿好緊"), null);
});

Deno.test("認甜話：只有表情的那則不當對象——整輪只有表情就不算；表情併進旁邊那句甜話，一起回", () => {
  assertEquals(
    sweetShortLine(extras({ worthyLines: [w(1, "情感")] }), ["❤️❤️"]),
    null,
  );
  assertEquals(
    sweetShortLine(
      extras({ worthyLines: [w(1, "照片或貼圖"), w(2, "情感")] }),
      ["🥰", "想你"],
    ),
    { line: 2, with: [1] },
  );
});

Deno.test("認甜話：Bruce 那次的形狀（A2）——她先撒嬌、後說腿很緊，兩則都標情感時本來每張卡先回腿那則、甜話只當順帶，現在也算，回前面那句甜話", () => {
  assertEquals(
    sweetShortLine(
      extras({ worthyLines: [w(1, "情感"), w(2, "情感")] }),
      ["想你了", "今天站了一整天 小腿好緊"],
    ),
    { line: 1, with: [] },
  );
});

Deno.test("認甜話：只有一則很長的情感句（她說腿很緊）不算；很長的情感句配一則標成其他的也不算", () => {
  assertEquals(
    sweetShortLine(extras({ worthyLines: [w(1, "情感")] }), [
      "今天站了一整天 小腿好緊",
    ]),
    null,
  );
  assertEquals(
    sweetShortLine(
      extras({ worthyLines: [w(1, "其他"), w(2, "情感")] }),
      ["想你", "今天站了一整天 小腿好緊"],
    ),
    null,
  );
});

Deno.test("認甜話：兩句很短的甜話時回 assignAnswers 排第一的那句（同一級取她後傳的）", () => {
  assertEquals(
    sweetShortLine(
      extras({ worthyLines: [w(1, "情感"), w(2, "情感"), w(3, "其他")] }),
      ["想你了", "抱抱", "今天站了一整天 小腿好緊"],
    ),
    { line: 2, with: [] },
  );
});

// ── 排卡 ─────────────────────────────────────────────────────────────────

Deno.test("排卡：第一張是推進（種子）時，甜話給第一張不是推進、也不是收的卡，只有那張回、不帶順帶；其他卡改回她別的話，規格完全不出現那句", () => {
  const two = extras({ worthyLines: SWEET_LEGS_LINES });
  const on = plan(SWEET_LEGS, two);
  const off = plan(SWEET_LEGS, two, tags(), {});
  assertEquals(on.specs.map((s) => s.task), [
    "推進",
    "接住",
    "接住",
    "接住",
    "接住",
  ]);
  assertEquals(on.specs.length, off.specs.length);
  assertEquals(marked(on.specs), [1]);
  assertEquals(on.specs[1].answer, { main: { line: 1, with: [] } });
  for (const [i, spec] of on.specs.entries()) {
    if (i === 1) continue;
    assertEquals(spec.answer, { main: { line: 2, with: [] } }, String(i));
    assertEquals(linesOf(spec).includes(1), false);
  }
  // 沒開時每張都回那句甜話、順帶腿很緊。
  for (const spec of off.specs) {
    assertEquals(spec.answer, {
      main: { line: 1, with: [] },
      extra: { line: 2, with: [] },
    });
  }
  const lines = specLines(on.specs, SWEET_LEGS);
  assert(
    lines[1].includes(
      `這張接：她的「想你了」｜${SWEET_SHORT_CARD_PART}｜他的事怎麼寫：`,
    ),
    lines[1],
  );
  for (const [i, line] of lines.entries()) {
    if (i === 1) continue;
    assertEquals(line.includes("想你了"), false, line);
    assertEquals(line.includes(SWEET_SHORT_CARD_PART), false, line);
    assert(line.includes("這張接：她的「今天站了一整天 小腿好緊」"), line);
  }
  // 任務、做法、口吻、問句都跟沒開一樣；換切入點照「回同一則」重算：第 4 張前面同規格的只有回甜話那張，不用換。
  const shape = (s: CardSpec) => [s.task, s.method, s.voice, s.questionBudget];
  assertEquals(on.specs.map(shape), off.specs.map(shape));
  assertEquals(off.specs.map((s) => s.angle), [0, 0, 0, 1, 1]);
  assertEquals(on.specs.map((s) => s.angle), [0, 0, 0, 0, 1]);
  // 計畫的其他欄位不變。
  assertEquals({ ...on, specs: off.specs }, off);
});

Deno.test("排卡：A2 形狀（甜話在前、很長的情感句在後）——沒開時每張先回腿、甜話當順帶；開了第 2 張回甜話，其他卡回腿、不帶順帶", () => {
  const two = extras({ worthyLines: [w(1, "情感"), w(2, "情感")] });
  const off = plan(SWEET_LEGS, two, tags(), {});
  const on = plan(SWEET_LEGS, two);
  for (const spec of off.specs) {
    assertEquals(spec.answer, {
      main: { line: 2, with: [] },
      extra: { line: 1, with: [] },
    });
  }
  assertEquals(on.specs.length, off.specs.length);
  assertEquals(marked(on.specs), [1]);
  assertEquals(on.specs[1].answer, { main: { line: 1, with: [] } });
  for (const [i, spec] of on.specs.entries()) {
    if (i === 1) continue;
    assertEquals(spec.answer, { main: { line: 2, with: [] } }, String(i));
  }
  const lines = specLines(on.specs, SWEET_LEGS);
  assert(
    lines[1].includes(`這張接：她的「想你了」｜${SWEET_SHORT_CARD_PART}｜`),
  );
  for (const [i, line] of lines.entries()) {
    if (i !== 1) assertEquals(line.includes("想你了"), false, line);
  }
});

Deno.test("排卡：兩句很短的甜話＋一句別的話——回排第一的那句甜話（她後傳的），其他卡回別的話，兩句甜話都不出現在其他卡（main、順帶都不是）", () => {
  const turns = chat(["想你了", "抱抱🥺", "今天站了一整天 小腿好緊"]);
  const on = plan(
    turns,
    extras({ worthyLines: [w(1, "情感"), w(2, "情感"), w(3, "其他")] }),
  );
  assertEquals(on.specs.length, 5);
  assertEquals(marked(on.specs), [1]);
  assertEquals(on.specs[1].answer, { main: { line: 2, with: [] } });
  for (const [i, spec] of on.specs.entries()) {
    if (i === 1) continue;
    assertEquals(spec.answer, { main: { line: 3, with: [] } }, String(i));
  }
  const lines = specLines(on.specs, turns);
  assert(lines[1].includes(`這張接：她的「抱抱」｜${SWEET_SHORT_CARD_PART}｜`));
  for (const line of lines) {
    assertEquals(line.includes("想你了"), false, line);
  }
  // 她只傳兩句很短的甜話：少出幾張，每張都回排第一的那句，另一句不出現在規格。
  const only = chat(["想你了", "抱抱🥺"]);
  const sweetOnly = plan(
    only,
    extras({ worthyLines: [w(1, "情感"), w(2, "情感")] }),
  );
  assertEquals(sweetOnly.specs.length, 3);
  assertEquals(marked(sweetOnly.specs), [0, 1, 2]);
  for (const spec of sweetOnly.specs) {
    assertEquals(spec.answer, { main: { line: 2, with: [] } });
  }
  for (const line of specLines(sweetOnly.specs, only)) {
    assertEquals(line.includes("想你了"), false, line);
  }
});

Deno.test("排卡：她開心分享時換上的那張共鳴留給她分享的事，甜話給下一張接住", () => {
  const on = plan(
    chat(["今天面試上了！！", "想你😚"]),
    extras({
      herHappyShare: true,
      worthyLines: [w(1, "其他", "面試上了"), w(2, "情感", "想他")],
    }),
  );
  assertEquals(on.specs.map((s) => s.task), [
    "推進",
    "共鳴",
    "接住",
    "接住",
    "接住",
  ]);
  assertEquals(on.specs[1].note, "happy_share");
  assertEquals(on.specs[1].answer?.main.line, 1);
  assertEquals(marked(on.specs), [2]);
});

Deno.test("排卡：併進那句甜話的照片、貼圖跟著那張走，其他卡也不出現", () => {
  const turns = chat([
    "[貼圖：小熊比愛心]",
    "想你了",
    "今天站了一整天 小腿好緊",
  ]);
  const on = plan(
    turns,
    extras({
      worthyLines: [w(1, "照片或貼圖"), w(2, "情感"), w(3, "其他")],
    }),
  );
  const at = marked(on.specs);
  assertEquals(at, [1]);
  assertEquals(on.specs[1].answer, { main: { line: 2, with: [1] } });
  const lines = specLines(on.specs, turns);
  assert(lines[1].includes("這張接：她的「想你了」（連同第 1 則）｜"));
  for (const [i, spec] of on.specs.entries()) {
    if (i === 1) continue;
    assertEquals(spec.answer, { main: { line: 3, with: [] } });
    assertEquals(lines[i].includes("第 1 則"), false);
  }
});

Deno.test("排卡：她還有兩句別的話時，其他卡照原本的先後回第一順位那句（同一級取後面的）、順帶輪流分剩下的", () => {
  const on = plan(
    chat(["明天要早起開會", "想你了", "今天站了一整天 小腿好緊"]),
    extras({
      worthyLines: [w(1, "其他"), w(2, "情感"), w(3, "其他")],
    }),
  );
  assertEquals(marked(on.specs), [1]);
  for (const [i, spec] of on.specs.entries()) {
    if (i === 1) continue;
    assertEquals(spec.answer, {
      main: { line: 3, with: [] },
      extra: { line: 1, with: [] },
    });
  }
});

Deno.test("排卡：她沒有別的有字的句子，就少出幾張（4、5 張都改成 3），每張都回那句、都帶短回指示、不換切入點、口吻照他預設交錯", () => {
  assertEquals(SWEET_SHORT_CARD_COUNT, 3);
  for (const worthyBallCount of [1, 2]) {
    const two = extras({ worthyLines: SWEET_ONLY_LINES });
    const t = tags({ worthyBallCount });
    const off = plan(SWEET_ONLY, two, t, {});
    const on = plan(SWEET_ONLY, two, t);
    assertEquals(off.specs.length, worthyBallCount === 1 ? 4 : 5);
    assertEquals(on.specs.length, 3);
    assertEquals(on.specs.map((s) => s.task), ["推進", "接住", "接住"]);
    assertEquals(on.specs.map((s) => s.voice), ["照他", "預設", "照他"]);
    assertEquals(marked(on.specs), [0, 1, 2]);
    for (const spec of on.specs) {
      assertEquals(spec.answer, { main: { line: 1, with: [] } });
      assertEquals(spec.angle, 0);
    }
    // 前 3 張的任務、做法、口吻照沒開時的前 3 張。
    const shape = (s: CardSpec) => [s.task, s.method, s.voice];
    assertEquals(on.specs.map(shape), off.specs.slice(0, 3).map(shape));
    for (const line of specLines(on.specs, SWEET_ONLY)) {
      assert(
        line.includes(`這張接：她的「想你了」｜${SWEET_SHORT_CARD_PART}｜`),
        line,
      );
      assertEquals(line.includes("切入點要跟前面同規格的卡不同"), false);
    }
  }
});

Deno.test("排卡：他沒有傳過訊息（口吻全是預設）時少出幾張的那幾張規格一樣，也不要求換切入點", () => {
  const on = plan(
    SWEET_ONLY,
    extras({ worthyLines: SWEET_ONLY_LINES }),
    tags({ hasHisVoiceSample: false }),
  );
  assertEquals(on.specs.length, 3);
  assertEquals(on.specs.map((s) => s.voice), ["預設", "預設", "預設"]);
  assertEquals(on.specs.map((s) => s.angle), [0, 0, 0]);
});

Deno.test("排卡：原本就 3 張（黃燈）——有別的話時第二張回甜話；只有甜話時張數不動、每張都回那句", () => {
  const t = tags({ light: "yellow" });
  const legs = plan(SWEET_LEGS, extras({ worthyLines: SWEET_LEGS_LINES }), t);
  assertEquals(legs.specs.map((s) => s.task), ["推進", "接住", "接住"]);
  assertEquals(marked(legs.specs), [1]);
  assertEquals(legs.specs[2].answer?.main.line, 2);
  const only = plan(SWEET_ONLY, extras({ worthyLines: SWEET_ONLY_LINES }), t);
  assertEquals(only.specs.length, 3);
  assertEquals(marked(only.specs), [0, 1, 2]);
});

Deno.test("排卡：紅燈（接住、接住、收）——甜話給第一張；只有甜話時連收那張都回那句、都帶短回指示", () => {
  const t = tags({ light: "red" });
  const legs = plan(SWEET_LEGS, extras({ worthyLines: SWEET_LEGS_LINES }), t);
  assertEquals(legs.specs.map((s) => s.task), ["接住", "接住", "收"]);
  assertEquals(marked(legs.specs), [0]);
  assertEquals(legs.specs.slice(1).map((s) => s.answer?.main.line), [2, 2]);
  const only = plan(SWEET_ONLY, extras({ worthyLines: SWEET_ONLY_LINES }), t);
  assertEquals(only.specs.map((s) => s.task), ["接住", "接住", "收"]);
  assertEquals(marked(only.specs), [0, 1, 2]);
});

Deno.test("排卡：她情緒差（全部共鳴）、最後撒嬌一句很短的——第一張回那句，其他共鳴回她難過的事", () => {
  const on = plan(
    chat(["今天被主管罵到想哭", "抱抱"]),
    extras({ worthyLines: [w(1, "情感", "被罵"), w(2, "情感", "要抱抱")] }),
    tags({ herMoodBad: true }),
  );
  assertEquals(on.specs.map((s) => s.task), ["共鳴", "共鳴", "共鳴"]);
  assertEquals(marked(on.specs), [0]);
  assertEquals(on.specs.slice(1).map((s) => s.answer?.main.line), [1, 1]);
});

Deno.test("排卡：婉拒收尾、詐騙換地方的固定排法不動；自傷、未成年、封鎖、明確拒絕、他是最後一則都跟沒開一模一樣", () => {
  const two = extras({ worthyLines: SWEET_LEGS_LINES });
  const same: [string, ReadTags, readonly Turn[]][] = [
    ["婉拒", tags({ declinedOrBoundary: true }), SWEET_LEGS],
    ["詐騙換地方", tags({ matchedEntries: ["B47"] }), SWEET_LEGS],
    ["自傷", tags({ selfHarmSignal: true }), SWEET_LEGS],
    ["未成年", tags({ minorSignal: true }), SWEET_LEGS],
    ["封鎖", tags({ blocked: true }), SWEET_LEGS],
    ["明確拒絕", tags({ explicitRejection: true }), SWEET_LEGS],
    [
      "他是最後一則",
      tags(),
      toTurns([
        { isFromMe: false, content: "想你了" },
        { isFromMe: true, content: "我也是" },
      ]),
    ],
  ];
  for (const [name, t, turns] of same) {
    assertEquals(plan(turns, two, t), plan(turns, two, t, {}), name);
  }
  assertEquals(
    plan(SWEET_LEGS, two, tags({ declinedOrBoundary: true })).specs.length,
    1,
  );
  assertEquals(
    plan(SWEET_LEGS, two, tags({ matchedEntries: ["B47"] })).specs.map((s) =>
      s.task
    ),
    ["推進", "收", "推進"],
  );
});

Deno.test("排卡：沒認到甜話（她沒撒嬌、那則不短、不是情感、她問他）時跟沒開一模一樣；沒開時規格沒有 sweetShort", () => {
  const cases: [string, TwoStageTags, readonly Turn[]][] = [
    [
      "她沒撒嬌",
      extras({ herAffection: false, worthyLines: SWEET_LEGS_LINES }),
      SWEET_LEGS,
    ],
    [
      "那則 7 個字",
      extras({ worthyLines: SWEET_LEGS_LINES }),
      chat(["好想好想你喔喔", "今天站了一整天 小腿好緊"]),
    ],
    [
      "標成其他",
      extras({ worthyLines: [w(1, "其他"), w(2, "其他")] }),
      SWEET_LEGS,
    ],
    [
      "她問他",
      extras({ worthyLines: [w(1, "情感"), w(2, "問他")] }),
      chat(["想你了", "你今天幾點下班"]),
    ],
  ];
  for (const [name, two, turns] of cases) {
    assertEquals(plan(turns, two), plan(turns, two, tags(), {}), name);
  }
  const off = plan(
    SWEET_LEGS,
    extras({ worthyLines: SWEET_LEGS_LINES }),
    tags(),
    {},
  );
  assertEquals(marked(off.specs), []);
  assertEquals(off.specs.some((s) => "sweetShort" in s), false);
});

Deno.test("排卡：卡都是推進或收時甜話給第一張；只剩開心分享那張共鳴可以放時才放那張", () => {
  const spec = (task: CardSpec["task"], note?: "happy_share"): CardSpec => ({
    task,
    method: "只用反應",
    voice: "預設",
    questionBudget: 1,
    push: task === "推進" ? "種子" : null,
    angle: 0,
    answer: { main: { line: 1, with: [] }, extra: { line: 2, with: [] } },
    ...(note ? { note } : {}),
  });
  const two = extras({ worthyLines: SWEET_LEGS_LINES });
  const her = ["想你了", "今天站了一整天 小腿好緊"];
  assertEquals(
    marked(
      arrangeSweetShort([spec("推進"), spec("收"), spec("推進")], two, her),
    ),
    [0],
  );
  assertEquals(
    marked(
      arrangeSweetShort(
        [spec("推進"), spec("共鳴", "happy_share"), spec("收")],
        two,
        her,
      ),
    ),
    [1],
  );
});

// ── 規格的字與哨兵 ───────────────────────────────────────────────────────────

Deno.test("規格：寫卡與說明看到同一段短回指示——有別的話時只有一張，少出幾張時每張都有；說明的卡片標頭跟寫卡回同一則", () => {
  for (
    const [turns, lines, count] of [
      [SWEET_LEGS, SWEET_LEGS_LINES, 1],
      [SWEET_ONLY, SWEET_ONLY_LINES, 3],
    ] as const
  ) {
    const p = plan(turns, extras({ worthyLines: lines }));
    const write = writeUserPromptTwoStage({
      turns,
      tags: tags(),
      entries: [],
      cards: p.specs,
      praise: p.praise,
    });
    assertEquals(write.split(SWEET_SHORT_CARD_PART).length - 1, count);
    const explain = explainUserPrompt({
      tags: tags(),
      herLatest: latestHerMessages(turns),
      entries: [],
      cards: p.specs.map((spec, i) => ({
        slot: i + 1,
        spec,
        messages: ["嗯"],
      })),
      praise: p.praise,
    });
    assertEquals(explain.split(SWEET_SHORT_CARD_PART).length - 1, count);
    // 說明裡每張卡的「這張接」跟寫卡規格的一樣。
    const quotes = (text: string) =>
      [...text.matchAll(/這張接：她的「([^」]*)」/gu)].map((m) => m[1]);
    assertEquals(quotes(explain), quotes(write));
  }
});

Deno.test("短回指示：照 Eric 核准的「短短回她一句就好」，不放例句、不替她下標籤；哨兵都照抄自這一段、而且夠長", () => {
  assertEquals(SWEET_SHORT_CARD_PART, "短短回她一句就好");
  assertEquals(/[「」]/.test(SWEET_SHORT_CARD_PART), false);
  for (const label of ["撒嬌", "甜話", "示愛"]) {
    assertEquals(SWEET_SHORT_CARD_PART.includes(label), false, label);
  }
  assert(SWEET_SHORT_WRITER_SENTINELS.length > 0);
  for (const s of SWEET_SHORT_WRITER_SENTINELS) {
    assert(SWEET_SHORT_CARD_PART.includes(s), s);
    // 共用比對不比 8 字以下的哨兵。
    assert([...s.replace(/\s+/g, "")].length >= 8, s);
  }
});

Deno.test("哨兵：正常回甜話、回她別的話的卡都不會被擋；照抄短回指示（夾空白也一樣）就拿掉那張", () => {
  const sentinels = [
    ...TWO_STAGE_WRITER_SENTINELS,
    ...SWEET_SHORT_WRITER_SENTINELS,
  ];
  const card = (messages: string[]) =>
    finalizeCard(
      { card: 1, messages, hasInventedDetail: false, expectedReaction: "" },
      { voice: "預設" },
      "想你了\n今天站了一整天 小腿好緊",
      sentinels,
    );
  for (
    const messages of [
      ["我也想你"],
      ["你的"],
      ["想你啊 晚點打給你"],
      ["抱一個", "今天辛苦了"],
      ["小腿還好嗎 早點泡個腳"],
      ["回家先躺一下 我晚點打給你"],
    ]
  ) {
    assertEquals(card(messages).ok, true, messages.join("／"));
  }
  for (const leak of ["短短回她一句就好", "短短 回她一句 就好"]) {
    const out = card([leak]);
    assertEquals(out.ok, false, leak);
    assertEquals(!out.ok && out.reason, "prompt_leak");
  }
});

Deno.test("哨兵：說明不比短回指示——說明寫到這張「短短回她一句就好」是自然的白話，照送（正式流程給說明的哨兵裡沒有這一句）", () => {
  // 開關都開時正式流程給說明多比的哨兵（stream_flow.ts explainCards）：帶張力改寫法、短版稱讚的；甜話短回的不在裡面。
  const explainExtra = [
    ...TENSION_STYLE_EXPLAIN_SENTINELS,
    ...TENSION_STYLE_WRITER_SENTINELS,
    ...SHORT_PRAISE_WRITER_SENTINELS,
  ];
  for (const s of SWEET_SHORT_WRITER_SENTINELS) {
    assertEquals(explainExtra.includes(s), false, s);
  }
  for (
    const text of [
      "她撒嬌說想你，這張短短回她一句就好，讓她知道你也在想她。",
      "她撒嬌說想你，你也短短回一句，讓她知道你也在想她。",
      "先關心她站了一整天的腿，讓她感覺被照顧。",
    ]
  ) {
    assertEquals(vetExplanation(text, explainExtra).ok, true, text);
  }
});
