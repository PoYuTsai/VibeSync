// review_check.ts 的免費驗證：用 Eric 2026-10-08 列的正反例（nt5-model）當測資，
// 審稿輸出是手寫的。只證明程式核對的控制流程，不證明模型會這樣標。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { buildPlan, candRouter, CASES, DEFAULT_EVAL_NOW } from "./run.ts";
import {
  buildSourcePack,
  type Candidate,
  checkReview,
  preReviewProblems,
  type ReviewLineCheck,
  type ReviewOutput,
  type SourceItem,
  splitSegments,
} from "./review_check.ts";

const NOW_MS = Date.parse(DEFAULT_EVAL_NOW);

async function sourcesFor(caseId: string): Promise<SourceItem[]> {
  const [call] = await buildPlan(
    CASES.filter((c) => c.id === caseId),
    1,
    { cand: candRouter(NOW_MS) },
    ["cand"],
    "model",
  );
  return buildSourcePack(call.user);
}

/**
 * 一段的標記。字串＝不需要來源的種類；只寫「事實」＝事實但沒附來源；
 * 陣列＝事實的範圍、來源 ID、原文。
 */
type Label = string | [scope: string, source: string, quote: string];

type Line = { id: string; text: string; labels: Label[]; issues?: string[] };

/** 照程式切出的段，依序補上段號和原文（審稿照規則輸出時就是這樣）。 */
function checkOf(line: Line): ReviewLineCheck {
  const segments = splitSegments(line.text);
  return {
    id: line.id,
    segments: line.labels.map((l, i) => {
      const at = { index: i + 1, text: segments[i] ?? "" };
      return typeof l === "string"
        ? { ...at, kind: l }
        : { ...at, kind: "事實", scope: l[0], source: l[1], quote: l[2] };
    }),
    issues: line.issues ?? [],
  };
}

type Group = {
  caseId: string;
  lines: Line[];
  selected: string[];
  recommended: string;
  /** 照規則該剔除的（Eric 列的錯句）。 */
  rejected: string[];
};

const candidatesOf = (g: Group): Candidate[] =>
  g.lines.map(({ id, text }) => ({ id, text }));

/** 這組照規則標的審稿輸出；replacements 換掉某幾句的標記。 */
function reviewOf(
  g: Group,
  replacements: ReviewLineCheck[] = [],
): ReviewOutput {
  return {
    checks: g.lines.map((line) =>
      replacements.find((r) => r.id === line.id) ?? checkOf(line)
    ),
    selected: g.selected,
    recommended: g.recommended,
  };
}

function relabel(g: Group, id: string, labels: Label[], issues: string[] = []) {
  const line = g.lines.find((l) => l.id === id);
  if (!line) throw new Error(id);
  return checkOf({ ...line, labels, issues });
}

/** 每組都放 Eric 列的句子，再補 nt4 照規則可留的句子，湊得出 5 句來測選擇。 */
const GROUPS: Group[] = [
  {
    caseId: "E3",
    lines: [
      {
        id: "e1",
        text: "跟妳講個事，我剛剛說的五分鐘，又變半小時了 😂",
        labels: ["招呼語氣", "事實", "事實"],
        issues: ["編造事件"],
      },
      {
        id: "e2",
        text: "我剛說五分鐘，朋友直接笑我，說妳那句早就被證實了",
        labels: ["事實", "事實", "事實"],
        issues: ["編造事件"],
      },
      {
        id: "e3",
        text: "如果照我的五分鐘理論遲到，妳會等還是直接走",
        labels: [["說過", "M1", "我的五分鐘"], "問題"],
      },
      {
        id: "e4",
        text: "如果真的去北海道 妳會想先滑雪還是先吃",
        labels: [["習慣", "P6", "想去北海道"], "問題"],
      },
      { id: "e5", text: "路跑的人應該沒有這種時間感吧", labels: ["看法"] },
      {
        id: "e6",
        text: "如果去北海道看雪，我應該會拖到雪都融了吧",
        labels: ["一般話題", "看法"],
      },
      {
        id: "e7",
        text: "最近在想老歌到底是誰定義的，五月天算老歌了嗎",
        labels: ["看法", "問題"],
      },
    ],
    selected: ["e3", "e4", "e5", "e6", "e7"],
    recommended: "e4",
    rejected: ["e1", "e2"],
  },
  {
    caseId: "B4",
    lines: [
      {
        id: "b1",
        text: "這幾天早晚好涼，我今天又穿太少了",
        labels: ["事實", "事實"],
        issues: ["編造事件"],
      },
      {
        id: "b2",
        text: "週一我一定要靠一杯冰美式才醒得過來，妳週一有固定撐場的東西嗎",
        labels: ["事實", "問題"],
        issues: ["編造事件"],
      },
      {
        id: "b3",
        text: "欸問妳，宵夜吃鹹的還是甜的比較治癒",
        labels: ["招呼語氣", "問題"],
      },
      {
        id: "b4",
        text: "如果一天只能選一餐吃到飽，妳選哪一餐",
        labels: ["一般話題", "問題"],
      },
      { id: "b5", text: "搭電梯遇到鄰居都裝滑手機嗎", labels: ["問題"] },
      {
        id: "b6",
        text: "我覺得外帶比內用好吃，不知道為什麼",
        labels: ["看法", "看法"],
      },
      {
        id: "b7",
        text: "週一總要靠點什麼撐過去，妳的是什麼？",
        labels: ["一般話題", "問題"],
      },
    ],
    selected: ["b3", "b4", "b5", "b6", "b7"],
    recommended: "b7",
    rejected: ["b1", "b2"],
  },
  {
    caseId: "J1",
    lines: [
      {
        id: "j1",
        text:
          "我今天又點了怪口味的飲料，被妳說中了，這次是我自己都有點後悔的那種",
        labels: ["事實", "事實", "事實"],
        issues: ["編造事件"],
      },
      {
        // J1.1 ★：表態（隱含常點怪口味，M1 的梗撐得起這個習慣）＋看法＋問題。
        id: "j2",
        text: "我要幫怪口味翻案，點飲料有時候就是想賭一把。妳通常點哪杯？",
        labels: [["習慣", "M1", "點最怪的口味"], "看法", "問題"],
      },
      {
        id: "j3",
        text: "我覺得怪口味才是真愛 妳反對嗎",
        labels: ["看法", "問題"],
      },
      {
        id: "j4",
        text: "妳敢喝我選的飲料嗎 挑戰一下",
        labels: ["問題", "招呼語氣"],
      },
      {
        id: "j5",
        text: "老歌跟新歌 妳投票哪邊比較耐聽",
        labels: ["一般話題", "問題"],
      },
      {
        id: "j6",
        text: "如果去北海道 我一定找最怪的霜淇淋口味",
        labels: ["一般話題", "看法"],
      },
    ],
    selected: ["j2", "j3", "j4", "j5", "j6"],
    recommended: "j2",
    rejected: ["j1"],
  },
  {
    caseId: "C2",
    lines: [
      {
        // 原文只到「才發現走錯分店」：櫃台、裝鎮定是加的。
        id: "k1",
        text: "走錯分店還硬走到櫃台才發現，我當場演得很鎮定",
        labels: [["事件", "M1", "才發現走錯分店"], "事實"],
        issues: ["加細節"],
      },
      {
        id: "k2",
        text: "信心滿滿走進店裡 結果走錯分店😂",
        labels: [["事件", "M1", "信心滿滿走進店裡"], [
          "事件",
          "M1",
          "走錯分店",
        ]],
      },
      {
        id: "k3",
        text: "走錯分店讓我想到，妳路跑該不會也迷路過吧",
        labels: [["事件", "M1", "走錯分店"], "問題"],
      },
      {
        id: "k4",
        text: "最近在想，心情不好的時候妳都聽什麼老歌啊",
        labels: ["看法", "問題"],
      },
      { id: "k5", text: "原來我的方向感比我想的還爛", labels: ["看法"] },
      {
        id: "k6",
        text: "走錯分店這種事，妳應該不會發生吧",
        labels: [["事件", "M1", "走錯分店"], "問題"],
      },
    ],
    selected: ["k2", "k3", "k4", "k5", "k6"],
    recommended: "k2",
    rejected: ["k1"],
  },
];

function group(caseId: string): Group {
  const found = GROUPS.find((g) => g.caseId === caseId);
  if (!found) throw new Error(caseId);
  return found;
}

async function verdict(g: Group, review: ReviewOutput, id: string) {
  const result = checkReview({
    sources: await sourcesFor(g.caseId),
    candidates: candidatesOf(g),
    review,
  });
  const line = result.lines.find((l) => l.id === id);
  if (!line) throw new Error(id);
  return line;
}

/** 單句測：不在固定組裡的句子（例如 nt4 的錯句）。 */
async function single(caseId: string, text: string, labels: Label[]) {
  const result = checkReview({
    sources: await sourcesFor(caseId),
    candidates: [{ id: "x", text }],
    review: {
      checks: [checkOf({ id: "x", text, labels })],
      selected: [],
      recommended: "",
    },
  });
  return result.lines[0];
}

Deno.test("來源包：原文照抄、缺的保持缺、節奏分數和規則行不當來源", async () => {
  const e3 = await sourcesFor("E3");
  const m1 = e3.find((s) => s.id === "M1");
  assertEquals(
    [m1?.kind, m1?.text, m1?.label],
    ["素材", "她說我的五分鐘都是半小時", "你們之間的梗"],
  );
  assert(e3.some((s) => s.kind === "作戰板" && s.text === "興趣：路跑"));
  assert(e3.some((s) => s.text === "過往備註：她說過想去北海道看雪"));
  assert(
    !e3.some((s) =>
      s.text.includes("只可使用以上明確紀錄") || s.text.includes("最近互動投入")
    ),
  );
  assertEquals(
    e3.find((s) => s.id === "T1"),
    { id: "T1", kind: "今天", text: "2026 年 10 月 5 日（週一）" },
  );
  // 基本模式沒有作戰板、關於我和素材：只有局面和今天，不放佔位。
  assertEquals(
    (await sourcesFor("B4")).map((s) => `${s.id}:${s.kind}`),
    ["S1:局面", "T1:今天"],
  );
  assertEquals(
    (await sourcesFor("C2")).find((s) => s.id === "M1")?.label,
    "用戶最近遇到的事",
  );
});

Deno.test("切段：依標點、空白和換行；表情併回前一段", () => {
  assertEquals(splitSegments("跟妳講個事，我剛剛說的五分鐘，又變半小時了 😂"), [
    "跟妳講個事，",
    "我剛剛說的五分鐘，",
    "又變半小時了😂",
  ]);
  assertEquals(
    splitSegments("剛點了一杯芋頭配花生的飲料\n妳應該又要說我口味很怪了"),
    [
      "剛點了一杯芋頭配花生的飲料",
      "妳應該又要說我口味很怪了",
    ],
  );
});

Deno.test("Eric 列的 6 句：審稿照規則標，程式全部剔除；J1.1 ★ 保留", async () => {
  for (const g of GROUPS) {
    const result = checkReview({
      sources: await sourcesFor(g.caseId),
      candidates: candidatesOf(g),
      review: reviewOf(g),
    });
    assertEquals(
      result.lines.filter((l) => !l.passed).map((l) => l.id),
      g.rejected,
      g.caseId,
    );
    assert(result.selectionOk, `${g.caseId} ${result.selectionReasons}`);
  }
  const j2 = await verdict(group("J1"), reviewOf(group("J1")), "j2");
  assertEquals([j2.passed, j2.reasons], [true, []]);
  const k1 = await verdict(group("C2"), reviewOf(group("C2")), "k1");
  assertEquals(k1.reasons, ["fact_without_source:2", "issue:加細節"]);
});

Deno.test("審稿把事件標成看法：句子有時間詞、「我每次／我一定要」或「我家」就照樣剔除", async () => {
  const j1 = group("J1");
  // 「我今天又點了…」「這次是我自己都有點後悔…」標成看法。
  const asOpinion = await verdict(
    j1,
    reviewOf(j1, [relabel(j1, "j1", ["看法", "看法", "看法"])]),
    "j1",
  );
  assertEquals(asOpinion.reasons, [
    "claim_not_fact:1:時間",
    "claim_not_fact:3:時間",
  ]);
  // 標成問題也不行：它不是在問。
  const asQuestion = await verdict(
    j1,
    reviewOf(j1, [relabel(j1, "j1", ["問題", "看法", "招呼語氣"])]),
    "j1",
  );
  assertEquals(asQuestion.reasons, [
    "claim_not_fact:1:時間",
    "claim_not_fact:3:時間",
  ]);

  const b4 = group("B4");
  // 「週一我一定要靠一杯冰美式…」是用戶的習慣，不是看法。
  assertEquals(
    (await verdict(
      b4,
      reviewOf(b4, [relabel(b4, "b2", ["看法", "問題"])]),
      "b2",
    )).reasons,
    ["claim_not_fact:1:習慣"],
  );
  // 「這幾天早晚好涼」是天氣，不是從日期推得出的一般話題。
  assertEquals(
    (await verdict(
      b4,
      reviewOf(b4, [relabel(b4, "b1", ["一般話題", "事實"])]),
      "b1",
    )).reasons,
    ["claim_not_fact:1:時間", "fact_without_source:2"],
  );
  // nt4 B4#2 乙1：「我家樓下最近多了隻貓」也是事實。
  assertEquals(
    (await single("B4", "我家樓下最近多了隻貓，每天坐在門口巡邏", [
      "看法",
      "看法",
    ])).reasons,
    ["claim_not_fact:1:我家"],
  );
});

Deno.test("習慣撐不起今天又發生：「每次點怪口味」證明不了「今天又點了」", async () => {
  const j1 = group("J1");
  const habit = ["習慣", "M1", "每次點飲料都點最怪的口味"] as Label;
  const event = ["事件", "M1", "每次點飲料都點最怪的口味"] as Label;
  // 範圍標成習慣：時間詞要的是事件或日期，而且「今天」不在原文裡。
  assertEquals(
    (await verdict(
      j1,
      reviewOf(j1, [relabel(j1, "j1", [habit, "看法", "看法"])]),
      "j1",
    )).reasons,
    ["marker_scope:1:時間", "time_not_in_quote:1", "claim_not_fact:3:時間"],
  );
  // 範圍標成事件：梗撐不起用戶的單次事件。
  assertEquals(
    (await verdict(
      j1,
      reviewOf(j1, [relabel(j1, "j1", [event, "看法", "看法"])]),
      "j1",
    )).reasons,
    ["scope_source_mismatch:1", "time_not_in_quote:1", "claim_not_fact:3:時間"],
  );
});

Deno.test("作戰板不能冒充她說過的話", async () => {
  const e3 = group("E3");
  assertEquals(
    (await verdict(
      e3,
      reviewOf(e3, [relabel(e3, "e4", [["說過", "P6", "想去北海道"], "問題"])]),
      "e4",
    )).reasons,
    ["scope_source_mismatch:1"],
  );
});

Deno.test("合法的原文不能挪去替另一段無關的事背書", async () => {
  const c2 = group("C2");
  // 「走錯分店」逐字在素材裡，但「我當場演得很鎮定」講的不是這件事。
  assertEquals(
    (await verdict(
      c2,
      reviewOf(c2, [
        relabel(c2, "k1", [["事件", "M1", "才發現走錯分店"], [
          "事件",
          "M1",
          "走錯分店",
        ]]),
      ]),
      "k1",
    )).reasons,
    ["quote_unrelated:2"],
  );
});

Deno.test("原文沒有的時間細節、日期撐天氣，都剔除", async () => {
  // nt4 C2#1 乙1：素材沒寫「今天」，句子寫了。
  assertEquals(
    (await single("C2", "好久不見～我今天信心滿滿走進店裡才發現走錯分店哈哈", [
      "招呼語氣",
      ["事件", "M1", "信心滿滿走進店裡"],
    ])).reasons,
    ["time_not_in_quote:2"],
  );
  // 「今天」只撐得起日期，撐不起「這幾天早晚好涼」。
  const weather = await single("B4", "這幾天早晚好涼，妳那邊呢？", [
    ["狀態", "T1", "10 月"],
    "問題",
  ]);
  assertEquals(weather.reasons, [
    "quote_unrelated:1",
    "scope_source_mismatch:1",
    "marker_scope:1:時間",
    "time_not_in_quote:1",
  ]);
});

/** 自備來源測單句：測原文寫了什麼才撐得起哪種說法。 */
function withSources(sources: SourceItem[], text: string, labels: Label[]) {
  return checkReview({
    sources,
    candidates: [{ id: "x", text }],
    review: {
      checks: [checkOf({ id: "x", text, labels })],
      selected: [],
      recommended: "",
    },
  }).lines[0];
}

Deno.test("原文沒寫明的關係不能升級：看到撐不起擁有，想做撐不起做了", async () => {
  const sawCat: SourceItem = {
    id: "M1",
    kind: "素材",
    label: "用戶最近遇到的事",
    text: "在公園看到一隻貓",
  };
  // 「看到一隻貓」撐不起「我家有一隻貓」。
  assertEquals(
    withSources([sawCat], "我家有一隻貓", [["擁有", "M1", "看到一隻貓"]])
      .reasons,
    ["possession_not_in_quote:1"],
  );
  // 原文明寫「我家有」才行。
  const ownCat: SourceItem = { id: "U1", kind: "關於我", text: "我家有一隻貓" };
  assertEquals(
    withSources([ownCat], "我家有一隻貓", [["擁有", "U1", "我家有一隻貓"]])
      .reasons,
    [],
  );
  // 主詞要對上：她家的貓撐不起我家的貓，撐得起妳家的貓。
  const herCat: SourceItem = {
    id: "M1",
    kind: "素材",
    label: "之前聊過的事（她提過的）",
    text: "她說她家有一隻貓",
  };
  assertEquals(
    withSources([herCat], "我家有一隻貓", [["擁有", "M1", "她家有一隻貓"]])
      .reasons,
    ["possession_not_in_quote:1"],
  );
  assertEquals(
    withSources([herCat], "原來妳家有一隻貓", [["擁有", "M1", "她家有一隻貓"]])
      .reasons,
    [],
  );

  // D1：「她說一直想學衝浪」撐不起「她去學了」，撐得起「還想學衝浪」。
  assertEquals(
    (await single("D1", "妳後來去學衝浪了", [["狀態", "M1", "想學衝浪"]]))
      .reasons,
    ["wish_as_done:1"],
  );
  assertEquals(
    (await single("D1", "怕曬黑還想學衝浪，妳這矛盾也太可愛", [
      ["說過", "M1", "想學衝浪"],
      "看法",
    ])).reasons,
    [],
  );
});

Deno.test("時間詞的正當用法：日期、真的在問、素材本來就寫了時間", async () => {
  assertEquals(
    (await single("B4", "今天週一，妳靠什麼撐過去？", [
      ["日期", "T1", "週一"],
      "問題",
    ])).reasons,
    [],
  );
  assertEquals((await single("B4", "妳今天過得怎樣？", ["問題"])).reasons, []);
  // 素材寫了「今天」，句子照著寫就可以。
  const result = checkReview({
    sources: [{
      id: "M1",
      kind: "素材",
      label: "用戶最近遇到的事",
      text: "今天信心滿滿走進店裡，才發現走錯分店",
    }],
    candidates: [{ id: "x", text: "我今天信心滿滿走進店裡" }],
    review: {
      checks: [checkOf({
        id: "x",
        text: "我今天信心滿滿走進店裡",
        labels: [["事件", "M1", "今天信心滿滿走進店裡"]],
      })],
      selected: [],
      recommended: "",
    },
  });
  assertEquals(result.lines[0].reasons, []);
});

Deno.test("審稿標錯時程式照樣擋：沒附原文、原文不在來源、來源不存在、錯位、漏標、沒審", async () => {
  const b4 = group("B4");
  // 附了原文，但基本模式沒有「關於我」可以引用。
  assertEquals(
    (await verdict(
      b4,
      reviewOf(b4, [relabel(b4, "b2", [["習慣", "U1", "冰美式"], "問題"])]),
      "b2",
    )).reasons,
    ["unknown_source:1"],
  );

  const e3 = group("E3");
  // 編一段素材裡沒有的「原文」來背書。
  assertEquals(
    (await verdict(
      e3,
      reviewOf(e3, [
        relabel(e3, "e2", ["事實", ["事件", "M1", "朋友直接笑我"], "事實"]),
      ]),
      "e2",
    )).reasons,
    [
      "fact_without_source:1",
      "quote_not_in_source:2",
      "fact_without_source:3",
    ],
  );
  // 事實沒寫範圍、範圍不在清單裡。
  assertEquals(
    (await verdict(
      e3,
      reviewOf(e3, [{
        ...checkOf(e3.lines[2]),
        segments: [
          { ...checkOf(e3.lines[2]).segments[0], scope: undefined },
          { ...checkOf(e3.lines[2]).segments[1] },
        ],
      }]),
      "e3",
    )).reasons,
    ["fact_without_scope:1"],
  );

  const j1 = group("J1");
  // 三段只標了兩段。
  assertEquals(
    (await verdict(
      j1,
      reviewOf(j1, [relabel(j1, "j1", ["看法", "看法"])]),
      "j1",
    )).reasons,
    ["claim_not_fact:1:時間", "segment_missing:3"],
  );
  // 標記錯位：第 1 段的標記寫的是第 2 段的字。
  const j3 = checkOf(j1.lines[2]);
  assertEquals(
    (await verdict(
      j1,
      reviewOf(j1, [{
        ...j3,
        segments: [
          { ...j3.segments[0], text: j3.segments[1].text },
          { ...j3.segments[1], text: j3.segments[0].text },
        ],
      }]),
      "j3",
    )).reasons,
    ["segment_mismatch:1", "segment_mismatch:2"],
  );
  // 段號重複、超出範圍。
  assertEquals(
    (await verdict(
      j1,
      reviewOf(j1, [{
        ...j3,
        segments: [j3.segments[0], j3.segments[0], {
          ...j3.segments[1],
          index: 9,
        }],
      }]),
      "j3",
    )).reasons,
    ["segment_duplicate:1", "segment_unknown:9", "segment_missing:2"],
  );
  // 不在清單裡的種類和問題代碼也算沒通過。
  assertEquals(
    (await verdict(
      j1,
      reviewOf(j1, [relabel(j1, "j3", ["其他", "問題"], ["不好"])]),
      "j3",
    )).reasons,
    ["unknown_kind:1", "unknown_issue:不好"],
  );

  const c2 = group("C2");
  const noCheck = {
    ...reviewOf(c2),
    checks: reviewOf(c2).checks.filter((c) => c.id !== "k1"),
  };
  assertEquals((await verdict(c2, noCheck, "k1")).reasons, ["no_check"]);
});

Deno.test("選擇核對：選到被剔除的、不滿 5 句、重複、選了不存在的、★ 不在其中，整筆失敗、程式不換句", async () => {
  const e3 = group("E3");
  const sources = await sourcesFor("E3");
  const run = (selected: string[], recommended = selected[0]) =>
    checkReview({
      sources,
      candidates: candidatesOf(e3),
      review: { ...reviewOf(e3), selected, recommended },
    });

  const withRejected = run(["e1", "e3", "e4", "e5", "e6"]);
  assertEquals(withRejected.selectionReasons, ["selected_not_passed:e1"]);
  assertEquals(withRejected.delivered, null);
  assertEquals(run(["e3", "e4", "e5", "e6"]).selectionReasons, [
    "selected_count:4",
  ]);
  assertEquals(run(["e3", "e3", "e4", "e5", "e6"]).selectionReasons, [
    "selected_duplicate",
  ]);
  assertEquals(run(["e3", "e4", "e5", "e6", "e9"]).selectionReasons, [
    "selected_unknown:e9",
  ]);
  assertEquals(
    run(["e3", "e4", "e5", "e6", "e7"], "e1").selectionReasons,
    ["recommended_not_selected"],
  );
});

Deno.test("交付的句子依 ID 從候選原樣複製，★ 只標在推薦那句", async () => {
  for (const g of GROUPS) {
    const result = checkReview({
      sources: await sourcesFor(g.caseId),
      candidates: candidatesOf(g),
      review: reviewOf(g),
    });
    const text = new Map(g.lines.map((l) => [l.id, l.text]));
    assertEquals(
      result.delivered?.map((d) => d.text),
      g.selected.map((id) => text.get(id)),
    );
    assertEquals(
      result.delivered?.filter((d) => d.recommended).map((d) => d.id),
      [g.recommended],
    );
  }
});

Deno.test("審稿前過濾：亂碼、控制字元、一句兩問", () => {
  assertEquals(preReviewProblems("討論�"), ["garbled"]);
  assertEquals(preReviewProblems("好\u0007"), ["garbled"]);
  assertEquals(preReviewProblems("妳喜歡貓嗎？還是狗？"), ["multi_question"]);
  for (const g of GROUPS) {
    for (const l of g.lines) assertEquals(preReviewProblems(l.text), []);
  }
  // 兩則訊息之間的換行不算控制字元。
  assertEquals(preReviewProblems("剛到\n妳呢？"), []);
});
