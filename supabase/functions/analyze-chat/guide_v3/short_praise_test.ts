// 短版稱讚（開關 ANALYZE_GUIDE_V3_SHORT_PRAISE，Bruce 2026-10-20「可以」）的純函式：程式照 runId 抽、只在
// 本來就挑輕輕誇時換、只放一張卡（第一張回她那則的接住，其次共鳴，推進、收不放）、規格與說明同一段。
// 沒抽到（或開關沒開）時一律跟今天一樣。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { explainUserPrompt } from "./explain.ts";
import { planTurn } from "./plan.ts";
import type { ReadTags, TwoStageTags } from "./read_tags.ts";
import {
  type CardSpec,
  LIGHT_SHORT_EVERY,
  lightShortRun,
  praiseStyle,
} from "./rules.ts";
import { NO_SAFETY_HITS } from "./safety.ts";
import { toTurns } from "./turns.ts";
import {
  cardSpecLineTwoStage,
  LIGHT_SHORT_CARD_PART,
  PRAISE_TEXT,
  SHORT_PRAISE_WRITER_SENTINELS,
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
    hasHisVoiceSample: false,
    replyWillingness: "high",
    worthyBallCount: 1,
    herTurnsPerfunctory: [],
    matchedEntries: [],
    readForUser: "她願意聊。",
    waitFor: "",
    ...over,
  };
}

function extras(over: Partial<TwoStageTags> = {}): TwoStageTags {
  return {
    establishedCouple: false,
    herAffection: false,
    herHappyShare: false,
    worthyLines: [],
    ...over,
  };
}

const TURNS = toTurns([
  { isFromMe: true, content: "今天好嗎" },
  { isFromMe: false, content: "還不錯" },
  { isFromMe: true, content: "那就好" },
  { isFromMe: false, content: "你咧" },
]);
const HER = ["你咧"];
/// 她最新這一輪只有一則，標成問他：每張卡都回這一則。
const ASKED = extras({
  worthyLines: [{ line: 1, label: "問他", kind: "問他" }],
});
const SHORT = { lightShortPraise: true } as const;
const plan = (
  t: ReadTags = tags(),
  two: TwoStageTags = ASKED,
  options: { lightShortPraise?: boolean } = {},
  turns = TURNS,
) => planTurn(turns, t, NO_SAFETY_HITS, undefined, two, options);
const marked = (specs: readonly CardSpec[]) =>
  specs.flatMap((s, i) => s.shortPraise ? [i] : []);

Deno.test("短版稱讚：交往中或撒嬌照舊直接誇；還沒交往、抽到短版才換；沒抽到跟今天一樣", () => {
  assertEquals(
    praiseStyle(extras({ establishedCouple: true }), true),
    "direct",
  );
  assertEquals(praiseStyle(extras({ herAffection: true }), true), "direct");
  assertEquals(praiseStyle(extras(), true), "light_short");
  assertEquals(praiseStyle(extras(), false), "light");
  assertEquals(praiseStyle(extras()), "light");
});

Deno.test("短版稱讚：照 runId 決定，同一個 runId 永遠一樣；大約每 LIGHT_SHORT_EVERY 次一次", () => {
  const ids = Array.from({ length: 2000 }, (_, i) => `run-${i}`);
  const picks = ids.filter(lightShortRun).length;
  assertEquals(ids.filter(lightShortRun).length, picks);
  const expected = ids.length / LIGHT_SHORT_EVERY;
  assert(Math.abs(picks - expected) < expected * 0.2, String(picks));
  for (const id of ["a", "00000000-0000-4000-8000-000000000001"]) {
    assertEquals(lightShortRun(id), lightShortRun(id));
  }
});

Deno.test("短版稱讚：只放一張——第一張回她那則的接住；其他欄位跟沒抽到一樣", () => {
  const short = plan(tags(), ASKED, SHORT);
  const plain = plan();
  assertEquals(short.praise, "light_short");
  assertEquals(plain.praise, "light");
  const at = marked(short.specs);
  assertEquals(at.length, 1);
  assertEquals(short.specs[at[0]].task, "接住");
  assertEquals(
    at[0],
    short.specs.findIndex((s) => s.task === "接住" && s.answer),
  );
  assertEquals(marked(plain.specs), []);
  assertEquals<unknown>(
    short.specs.map(({ shortPraise: _, ...s }) => s),
    plain.specs,
  );
  assertEquals({ ...short, praise: "light", specs: plain.specs }, plain);
});

Deno.test("短版稱讚：沒有接住就第一張共鳴；交往中直接誇不放；沒有指定她哪一則不放", () => {
  const mood = plan(tags({ herMoodBad: true }), ASKED, SHORT);
  assertEquals(marked(mood.specs), [0]);
  assertEquals(mood.specs[0].task, "共鳴");
  const couple = plan(
    tags(),
    extras({ ...ASKED, establishedCouple: true }),
    SHORT,
  );
  assertEquals(couple.praise, "direct");
  assertEquals(marked(couple.specs), []);
  const none = plan(tags(), extras(), SHORT);
  assertEquals(marked(none.specs), []);
});

Deno.test("短版稱讚：自傷、未成年、停、先別回的計畫跟沒抽到一模一樣；詐騙換地方與婉拒收尾不放（推進、收不放）", () => {
  const same: [string, ReadTags, typeof TURNS][] = [
    ["自傷", tags({ selfHarmSignal: true }), TURNS],
    ["未成年", tags({ minorSignal: true }), TURNS],
    ["封鎖", tags({ blocked: true }), TURNS],
    ["明確拒絕", tags({ explicitRejection: true }), TURNS],
    [
      "他是最後一則",
      tags(),
      toTurns([
        { isFromMe: false, content: "你咧" },
        { isFromMe: true, content: "我也還好" },
      ]),
    ],
  ];
  for (const [name, t, turns] of same) {
    assertEquals(plan(t, ASKED, SHORT, turns), plan(t, ASKED, {}, turns), name);
  }
  const scam = plan(tags({ matchedEntries: ["B47"] }), ASKED, SHORT);
  assertEquals(scam.specs.map((s) => s.task), ["推進", "收", "推進"]);
  assertEquals(marked(scam.specs), []);
  const close = plan(tags({ declinedOrBoundary: true }), ASKED, SHORT);
  assertEquals(close.decision, "close");
  assertEquals(marked(close.specs), []);
});

Deno.test("短版稱讚：那一張的規格與說明在「這張接」後面寫短版的誇法，其他張沒有；稱讚那段跟輕輕誇一樣", () => {
  const short = plan(tags(), ASKED, SHORT);
  const at = marked(short.specs)[0];
  const lines = short.specs.map((s, i) => cardSpecLineTwoStage(s, i + 1, HER));
  lines.forEach((line, i) =>
    assertEquals(line.includes(LIGHT_SHORT_CARD_PART), i === at, line)
  );
  assert(
    lines[at].includes(`這張接：她的「你咧」｜${LIGHT_SHORT_CARD_PART}｜`),
  );
  assertEquals(PRAISE_TEXT.light_short, PRAISE_TEXT.light);
  const write = writeUserPromptTwoStage({
    turns: TURNS,
    tags: tags(),
    entries: [],
    cards: short.specs,
    praise: short.praise,
  });
  assertEquals(write.split(LIGHT_SHORT_CARD_PART).length - 1, 1);
  assert(write.includes(PRAISE_TEXT.light));
  const explain = explainUserPrompt({
    tags: tags(),
    herLatest: HER,
    entries: [],
    cards: short.specs.map((spec, i) => ({
      slot: i + 1,
      spec,
      messages: ["好啊"],
    })),
    praise: short.praise,
  });
  assertEquals(explain.split(LIGHT_SHORT_CARD_PART).length - 1, 1);
  // 沒抽到時，規格與說明都沒有這一段。
  const plain = plan();
  assertEquals(
    plain.specs.some((s, i) =>
      cardSpecLineTwoStage(s, i + 1, HER).includes(LIGHT_SHORT_CARD_PART)
    ),
    false,
  );
});

Deno.test("短版的誇法：只講形狀（很短、誇張、正面的說法），不放例句；卡片多比的哨兵都照抄自這一段、而且夠長", () => {
  assertEquals(/[「」]/.test(LIGHT_SHORT_CARD_PART), false);
  for (const word of ["很短", "誇張", "正面的說法"]) {
    assert(LIGHT_SHORT_CARD_PART.includes(word), word);
  }
  for (const s of SHORT_PRAISE_WRITER_SENTINELS) {
    assert(LIGHT_SHORT_CARD_PART.includes(s), s);
    // 共用比對不比 8 字以下的哨兵。
    assert([...s].length >= 8, s);
  }
});
