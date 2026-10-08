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

/** 一段的標記：字串＝不需要來源的種類；陣列＝事實＋來源 ID＋原文。只寫「事實」＝沒附來源。 */
type Label = string | [kind: "事實", source: string, quote: string];

function check(
  id: string,
  labels: Label[],
  issues: string[] = [],
): ReviewLineCheck {
  return {
    id,
    segments: labels.map((l) =>
      typeof l === "string"
        ? { kind: l }
        : { kind: l[0], source: l[1], quote: l[2] }
    ),
    issues,
  };
}

type Group = {
  caseId: string;
  candidates: Candidate[];
  review: ReviewOutput;
  /** 照規則該剔除的（Eric 列的錯句）。 */
  rejected: string[];
};

/** 每組都放 Eric 列的句子，再補 nt4 照規則可留的句子，湊得出 5 句來測選擇。 */
const GROUPS: Group[] = [
  {
    caseId: "E3",
    candidates: [
      { id: "e1", text: "跟妳講個事，我剛剛說的五分鐘，又變半小時了 😂" },
      { id: "e2", text: "我剛說五分鐘，朋友直接笑我，說妳那句早就被證實了" },
      { id: "e3", text: "如果照我的五分鐘理論遲到，妳會等還是直接走" },
      { id: "e4", text: "如果真的去北海道 妳會想先滑雪還是先吃" },
      { id: "e5", text: "路跑的人應該沒有這種時間感吧" },
      { id: "e6", text: "如果去北海道看雪，我應該會拖到雪都融了吧" },
      { id: "e7", text: "最近在想老歌到底是誰定義的，五月天算老歌了嗎" },
    ],
    review: {
      checks: [
        check("e1", ["招呼語氣", "事實", "事實"], ["編造事件"]),
        check("e2", ["事實", "事實", "事實"], ["編造事件"]),
        check("e3", [["事實", "M1", "我的五分鐘"], "問題"]),
        check("e4", [["事實", "P6", "想去北海道"], "問題"]),
        check("e5", ["看法"]),
        check("e6", ["一般話題", "看法"]),
        check("e7", ["看法", "問題"]),
      ],
      selected: ["e3", "e4", "e5", "e6", "e7"],
      recommended: "e4",
    },
    rejected: ["e1", "e2"],
  },
  {
    caseId: "B4",
    candidates: [
      { id: "b1", text: "這幾天早晚好涼，我今天又穿太少了" },
      {
        id: "b2",
        text: "週一我一定要靠一杯冰美式才醒得過來，妳週一有固定撐場的東西嗎",
      },
      { id: "b3", text: "欸問妳，宵夜吃鹹的還是甜的比較治癒" },
      { id: "b4", text: "如果一天只能選一餐吃到飽，妳選哪一餐" },
      { id: "b5", text: "搭電梯遇到鄰居都裝滑手機嗎" },
      { id: "b6", text: "我覺得外帶比內用好吃，不知道為什麼" },
      { id: "b7", text: "週一總要靠點什麼撐過去，妳的是什麼？" },
    ],
    review: {
      checks: [
        check("b1", ["一般話題", "事實"], ["編造事件"]),
        check("b2", ["事實", "問題"], ["編造事件"]),
        check("b3", ["招呼語氣", "問題"]),
        check("b4", ["一般話題", "問題"]),
        check("b5", ["問題"]),
        check("b6", ["看法", "看法"]),
        check("b7", ["一般話題", "問題"]),
      ],
      selected: ["b3", "b4", "b5", "b6", "b7"],
      recommended: "b7",
    },
    rejected: ["b1", "b2"],
  },
  {
    caseId: "J1",
    candidates: [
      {
        id: "j1",
        text:
          "我今天又點了怪口味的飲料，被妳說中了，這次是我自己都有點後悔的那種",
      },
      {
        id: "j2",
        text: "我要幫怪口味翻案，點飲料有時候就是想賭一把。妳通常點哪杯？",
      },
      { id: "j3", text: "我覺得怪口味才是真愛 妳反對嗎" },
      { id: "j4", text: "妳敢喝我選的飲料嗎 挑戰一下" },
      { id: "j5", text: "老歌跟新歌 妳投票哪邊比較耐聽" },
      { id: "j6", text: "如果去北海道 我一定找最怪的霜淇淋口味" },
    ],
    review: {
      checks: [
        check("j1", ["事實", "事實", "事實"], ["編造事件"]),
        // J1.1 ★：表態（隱含常點怪口味，M1 支持）＋看法＋問題。
        check("j2", [["事實", "M1", "點最怪的口味"], "看法", "問題"]),
        check("j3", ["看法", "問題"]),
        check("j4", ["問題", "招呼語氣"]),
        check("j5", ["一般話題", "問題"]),
        check("j6", ["一般話題", "看法"]),
      ],
      selected: ["j2", "j3", "j4", "j5", "j6"],
      recommended: "j2",
    },
    rejected: ["j1"],
  },
  {
    caseId: "C2",
    candidates: [
      { id: "k1", text: "走錯分店還硬走到櫃台才發現，我當場演得很鎮定" },
      { id: "k2", text: "信心滿滿走進店裡 結果走錯分店😂" },
      { id: "k3", text: "走錯分店讓我想到，妳路跑該不會也迷路過吧" },
      { id: "k4", text: "最近在想，心情不好的時候妳都聽什麼老歌啊" },
      { id: "k5", text: "原來我的方向感比我想的還爛" },
      { id: "k6", text: "走錯分店這種事，妳應該不會發生吧" },
    ],
    review: {
      checks: [
        // 原文只到「才發現走錯分店」：櫃台、裝鎮定是加的。
        check("k1", [["事實", "M1", "才發現走錯分店"], "事實"], ["加細節"]),
        check("k2", [["事實", "M1", "信心滿滿走進店裡"], [
          "事實",
          "M1",
          "走錯分店",
        ]]),
        check("k3", [["事實", "M1", "走錯分店"], "問題"]),
        check("k4", ["看法", "問題"]),
        check("k5", ["看法"]),
        check("k6", [["事實", "M1", "走錯分店"], "問題"]),
      ],
      selected: ["k2", "k3", "k4", "k5", "k6"],
      recommended: "k2",
    },
    rejected: ["k1"],
  },
];

function group(caseId: string): Group {
  const found = GROUPS.find((g) => g.caseId === caseId);
  if (!found) throw new Error(caseId);
  return found;
}

/** 換掉一組審稿裡某句的標記，其他照舊。 */
function withCheck(g: Group, replacement: ReviewLineCheck): ReviewOutput {
  return {
    ...g.review,
    checks: g.review.checks.map((c) =>
      c.id === replacement.id ? replacement : c
    ),
  };
}

async function verdict(g: Group, review: ReviewOutput, id: string) {
  const result = checkReview({
    sources: await sourcesFor(g.caseId),
    candidates: g.candidates,
    review,
  });
  const line = result.lines.find((l) => l.id === id);
  if (!line) throw new Error(id);
  return line;
}

Deno.test("來源包：原文照抄、缺的保持缺、節奏分數和規則行不當來源", async () => {
  const e3 = await sourcesFor("E3");
  const m1 = e3.find((s) => s.id === "M1");
  assertEquals(m1?.text, "她說我的五分鐘都是半小時");
  assertEquals(m1?.label, "你們之間的梗");
  assert(e3.some((s) => s.text === "興趣：路跑"));
  assert(e3.some((s) => s.text === "過往備註：她說過想去北海道看雪"));
  assert(
    !e3.some((s) =>
      s.text.includes("只可使用以上明確紀錄") || s.text.includes("最近互動投入")
    ),
  );
  assertEquals(
    e3.find((s) => s.id === "T1")?.text,
    "2026 年 10 月 5 日（週一）",
  );
  // 基本模式沒有作戰板、關於我和素材：只有局面和今天，不放佔位。
  assertEquals((await sourcesFor("B4")).map((s) => s.id), ["S1", "T1"]);
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
      candidates: g.candidates,
      review: g.review,
    });
    assertEquals(
      result.lines.filter((l) => !l.passed).map((l) => l.id),
      g.rejected,
      g.caseId,
    );
    assert(result.selectionOk, `${g.caseId} ${result.selectionReasons}`);
  }
  const j2 = await verdict(group("J1"), group("J1").review, "j2");
  assertEquals([j2.passed, j2.reasons], [true, []]);
  const k1 = await verdict(group("C2"), group("C2").review, "k1");
  assertEquals(k1.reasons, ["fact_without_source:2", "issue:加細節"]);
});

Deno.test("審稿標錯時程式照樣擋：沒附原文、原文不在來源、來源不存在、漏標、沒審", async () => {
  const b4 = group("B4");
  // 審稿說沒問題，但「我今天又穿太少了」標成事實卻沒附原文。
  assertEquals(
    (await verdict(b4, withCheck(b4, check("b1", ["一般話題", "事實"])), "b1"))
      .reasons,
    ["fact_without_source:2"],
  );
  // 附了原文，但基本模式沒有「關於我」可以引用。
  assertEquals(
    (await verdict(
      b4,
      withCheck(b4, check("b2", [["事實", "U1", "冰美式"], "問題"])),
      "b2",
    )).reasons,
    ["unknown_source:1"],
  );

  const e3 = group("E3");
  // 編一段素材裡沒有的「原文」來背書。
  assertEquals(
    (await verdict(
      e3,
      withCheck(
        e3,
        check("e2", ["事實", ["事實", "M1", "朋友直接笑我"], "事實"]),
      ),
      "e2",
    )).reasons,
    [
      "fact_without_source:1",
      "quote_not_in_source:2",
      "fact_without_source:3",
    ],
  );

  const j1 = group("J1");
  // 三段只標了兩段。
  assertEquals(
    (await verdict(j1, withCheck(j1, check("j1", ["看法", "看法"])), "j1"))
      .reasons,
    ["segment_count_mismatch"],
  );
  // 不在清單裡的種類和問題代碼也算沒通過。
  assertEquals(
    (await verdict(
      j1,
      withCheck(j1, check("j3", ["其他", "問題"], ["不好"])),
      "j3",
    )).reasons,
    ["unknown_kind:1", "unknown_issue:不好"],
  );

  const c2 = group("C2");
  const noCheck = {
    ...c2.review,
    checks: c2.review.checks.filter((c) => c.id !== "k1"),
  };
  assertEquals((await verdict(c2, noCheck, "k1")).reasons, ["no_check"]);
});

Deno.test("選擇核對：選到被剔除的、不滿 5 句、重複、選了不存在的、★ 不在其中，整筆失敗、程式不換句", async () => {
  const e3 = group("E3");
  const sources = await sourcesFor("E3");
  const run = (selected: string[], recommended = selected[0]) =>
    checkReview({
      sources,
      candidates: e3.candidates,
      review: { ...e3.review, selected, recommended },
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
      candidates: g.candidates,
      review: g.review,
    });
    const text = new Map(g.candidates.map((c) => [c.id, c.text]));
    assertEquals(
      result.delivered?.map((d) => d.text),
      g.review.selected.map((id) => text.get(id)),
    );
    assertEquals(
      result.delivered?.filter((d) => d.recommended).map((d) => d.id),
      [g.review.recommended],
    );
  }
});

Deno.test("程式擋不住的兩種錯（要靠付費的審稿回測量）", async () => {
  const j1 = group("J1");
  // 1. 審稿把「我今天又點了怪口味的飲料」標成看法：沒有事實要核對，程式放行。
  const asOpinion = await verdict(
    j1,
    withCheck(j1, check("j1", ["看法", "看法", "看法"])),
    "j1",
  );
  assertEquals(asOpinion.passed, true);
  // 2. 拿「每次」的習慣當「今天」的證據：原文逐字存在，程式核對不出撐不起這句。
  const habitAsEvent = await verdict(
    j1,
    withCheck(
      j1,
      check("j1", [["事實", "M1", "每次點飲料都點最怪的口味"], "看法", "看法"]),
    ),
    "j1",
  );
  assertEquals(habitAsEvent.passed, true);
});

Deno.test("審稿前過濾：亂碼、控制字元、一句兩問", () => {
  assertEquals(preReviewProblems("討論�"), ["garbled"]);
  assertEquals(preReviewProblems("好\u0007"), ["garbled"]);
  assertEquals(preReviewProblems("妳喜歡貓嗎？還是狗？"), ["multi_question"]);
  for (const g of GROUPS) {
    for (const c of g.candidates) assertEquals(preReviewProblems(c.text), []);
  }
  // 兩則訊息之間的換行不算控制字元。
  assertEquals(preReviewProblems("剛到\n妳呢？"), []);
});
