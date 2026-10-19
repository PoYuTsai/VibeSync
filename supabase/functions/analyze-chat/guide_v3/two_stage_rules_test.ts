// 兩段式實驗（開關 ANALYZE_GUIDE_V3_TWO_STAGE，Eric 2026-10-19）的排卡：帶張力張數、開心分享的
// 共鳴卡、每張卡回她哪一則（第 2 輪：每張都先回她最想聽的那則，Bruce 10/19 盲選理由）。沒給四欄
//（開關沒開）時一律跟今天一樣。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { planTurn } from "./plan.ts";
import type { ReadTags, TwoStageTags, WorthyLine } from "./read_tags.ts";
import {
  type AnswerLine,
  arrangeCards,
  assignAnswers,
  type CardAnswer,
  type CardSpec,
  isMediaLine,
  type Task,
} from "./rules.ts";
import { toTurns } from "./turns.ts";

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

const w = (
  line: number,
  kind: WorthyLine["kind"],
  label = "x",
): WorthyLine => ({
  line,
  label,
  kind,
});
const tasks = (cards: readonly CardSpec[]): Task[] => cards.map((c) => c.task);
const tension = (cards: readonly CardSpec[]) =>
  cards.filter((c) => c.task === "帶張力").length;
const send = { kind: "send" } as const;

Deno.test("兩段式：綠燈帶張力最多一張（今天 4 張以上排兩張）；黃燈、紅燈照舊不排", () => {
  for (const worthyBallCount of [1, 2]) {
    const t = tags({ worthyBallCount });
    const today = arrangeCards(send, null, t);
    const two = arrangeCards(send, null, t, extras());
    assertEquals(today.length, two.length);
    assertEquals(tension(today), 2, `今天 ${today.length} 張`);
    assertEquals(tension(two), 1, `兩段式 ${two.length} 張`);
    // 少掉的那張換成接住，第一張不動。
    assertEquals(two[0].task, today[0].task);
  }
  assertEquals(tasks(arrangeCards(send, null, tags(), extras())), [
    "接住",
    "帶張力",
    "接住",
    "接住",
  ]);
  for (const light of ["yellow", "red"] as const) {
    assertEquals(
      tension(arrangeCards(send, null, tags({ light }), extras())),
      0,
      light,
    );
  }
});

Deno.test("兩段式：已經在交往、或她這一輪撒嬌示愛，帶張力一張都不排（大笑收尾那張也改成接住）", () => {
  for (
    const ex of [
      extras({ establishedCouple: true }),
      extras({ herAffection: true }),
    ]
  ) {
    for (const worthyBallCount of [1, 2]) {
      const cards = arrangeCards(send, null, tags({ worthyBallCount }), ex);
      assertEquals(tension(cards), 0, JSON.stringify(ex));
      assert(cards.length >= 4);
    }
    const laugh = arrangeCards(send, null, tags({ herMove: "大笑收尾" }), ex);
    assertEquals(laugh[0].task, "收");
    assertEquals(tension(laugh), 0);
  }
  // 只開兩段式、沒有這兩種情況：大笑收尾照舊留一張帶張力。
  const laugh = arrangeCards(
    send,
    null,
    tags({ herMove: "大笑收尾" }),
    extras(),
  );
  assertEquals(tension(laugh), 1);
});

Deno.test("兩段式：原本的蓋過規則照舊（B43–B46 不排帶張力、B47 三張固定、她直接問他第一張接住、B34 不推進）", () => {
  const ex = extras({ herHappyShare: true });
  assertEquals(
    tension(
      arrangeCards(send, null, tags({ matchedEntries: ["B44"] }), ex),
    ),
    0,
  );
  const b47 = arrangeCards(
    send,
    "換地方",
    tags({ matchedEntries: ["B47"] }),
    ex,
  );
  assertEquals(tasks(b47), ["推進", "收", "推進"]);
  assert(b47.every((c) => c.note === undefined));
  const asks = arrangeCards(
    send,
    "具體邀約",
    tags({ herMove: "問他的事", hisStatedFacts: ["週末常爬山"] }),
    extras(),
  );
  assertEquals(asks[0].task, "接住");
  assertEquals(asks[1].task, "推進");
  const turns = toTurns([
    { isFromMe: true, content: "a" },
    { isFromMe: false, content: "b" },
    { isFromMe: true, content: "c" },
    { isFromMe: false, content: "我想慢一點" },
  ]);
  const slow = planTurn(
    turns,
    tags({ matchedEntries: ["B34"] }),
    undefined,
    undefined,
    extras(),
  );
  assertEquals(slow.push, null);
  assertEquals(slow.decision, "send");
});

Deno.test("兩段式：她分享開心的事，第二張換成共鳴（標 happy_share），第一張照原本的順序", () => {
  const ex = extras({ herHappyShare: true });
  const plain = arrangeCards(send, null, tags(), ex);
  assertEquals(tasks(plain), ["接住", "共鳴", "帶張力", "接住"]);
  assertEquals(plain.map((c) => c.note), [
    undefined,
    "happy_share",
    undefined,
    undefined,
  ]);
  // 有推進時第一張仍是推進。
  const seeded = arrangeCards(send, "種子", tags(), ex);
  assertEquals(tasks(seeded), ["推進", "共鳴", "帶張力", "接住"]);
  // 黃燈：接住換一張。
  assertEquals(tasks(arrangeCards(send, null, tags({ light: "yellow" }), ex)), [
    "接住",
    "共鳴",
    "接住",
  ]);
  // 交往中又開心分享：沒有帶張力，仍然第二張共鳴。
  assertEquals(
    tasks(
      arrangeCards(
        send,
        null,
        tags(),
        extras({ herHappyShare: true, establishedCouple: true }),
      ),
    ),
    ["接住", "共鳴", "接住", "接住"],
  );
});

Deno.test("兩段式：她情緒差、已經有共鳴（喝醉深夜）、只有一張收尾時，不另換共鳴卡", () => {
  const ex = extras({ herHappyShare: true });
  const sad = arrangeCards(send, null, tags({ herMoodBad: true }), ex);
  assert(sad.every((c) => c.task === "共鳴" && c.note === undefined));
  const late = arrangeCards(send, null, tags({ drunkOrLateNight: true }), ex);
  assertEquals(
    tasks(late),
    tasks(arrangeCards(send, null, tags({ drunkOrLateNight: true }))),
  );
  assert(late.every((c) => c.note === undefined));
  const close = arrangeCards({ kind: "close", reason: "x" }, null, tags(), ex);
  assertEquals(tasks(close), ["收"]);
});

Deno.test("兩段式沒開：卡片規格沒有 answer、note 欄位（trace 跟今天一字不差）", () => {
  for (
    const t of [
      tags(),
      tags({ worthyBallCount: 2 }),
      tags({ light: "yellow" }),
      tags({ herMoodBad: true }),
    ]
  ) {
    for (const card of arrangeCards(send, "種子", t)) {
      assertEquals("answer" in card, false);
      assertEquals("note" in card, false);
    }
  }
  const turns = toTurns([
    { isFromMe: true, content: "晚餐吃什麼" },
    { isFromMe: false, content: "咖哩" },
  ]);
  for (const spec of planTurn(turns, tags()).specs) {
    assertEquals(Object.keys(spec).sort(), [
      "angle",
      "method",
      "push",
      "questionBudget",
      "task",
      "voice",
    ]);
  }
});

/// 一則要回的句子：編號，加上併進來的照片、貼圖那幾則。
const at = (line: number, ...withLines: number[]): AnswerLine => ({
  line,
  with: withLines,
});
const mains = (out: readonly (CardAnswer | null)[]) => out.map((a) => a?.main);
const extrasOf = (out: readonly (CardAnswer | null)[]) =>
  out.map((a) => a?.extra?.line);

Deno.test("第 2 輪分句：每張卡都先回她最想聽的那則（問他 → 情感 → 其他，同一級取她最後傳的）", () => {
  const herLatest = [
    "今天好累",
    "主管又罵人",
    "你覺得我要不要換工作",
    "好想你",
  ];
  // 問他最先，她後面還有一句情感也一樣。
  assertEquals(
    mains(
      assignAnswers(
        3,
        [w(1, "情感"), w(2, "其他"), w(3, "問他"), w(4, "情感")],
        herLatest,
      ),
    ),
    [at(3), at(3), at(3)],
  );
  // 沒有問他：情感裡取她最後傳的那則。
  assertEquals(
    mains(
      assignAnswers(2, [w(1, "情感"), w(2, "其他"), w(4, "情感")], herLatest),
    ),
    [at(4), at(4)],
  );
  // 都是其他：取最後傳的。
  assertEquals(
    mains(assignAnswers(1, [w(1, "其他"), w(2, "其他")], herLatest)),
    [at(2)],
  );
});

Deno.test("第 2 輪分句：每張最多再順帶一則，其餘照同樣的先後（同一級照她傳的順序）輪流分；比卡多的不排", () => {
  const herLatest = ["a", "b", "c", "d", "e", "f"];
  const worthy = [
    w(1, "其他"),
    w(2, "情感"),
    w(3, "其他"),
    w(4, "問他"),
    w(5, "情感"),
    w(6, "其他"),
  ];
  const five = assignAnswers(5, worthy, herLatest);
  assertEquals(mains(five), Array(5).fill(at(4)));
  assertEquals(extrasOf(five), [2, 5, 1, 3, 6]);
  // 順帶的句子比卡多：最不重要的不排。
  assertEquals(extrasOf(assignAnswers(3, worthy, herLatest)), [2, 5, 1]);
  // 卡比順帶的句子多：從最重要的那句再輪。
  assertEquals(
    extrasOf(
      assignAnswers(5, [w(1, "其他"), w(2, "問他"), w(3, "情感")], [
        "a",
        "b",
        "c",
      ]),
    ),
    [3, 1, 3, 1, 3],
  );
  // 只有一則值得接：每張只回那則，不順帶。
  assertEquals(assignAnswers(2, [w(2, "其他")], herLatest), [
    { main: at(2) },
    { main: at(2) },
  ]);
});

Deno.test("第 2 輪分句：照片、貼圖、只有表情的那則不單獨當對象，併進最近一則有字的（一樣近時併進後面那則）", () => {
  // 部門聚餐的形狀：合照夾在兩句中間、貼圖夾在兩句中間，最後她問是不是最好看。
  const herLatest = [
    "今天部門聚餐 主管請客🥳",
    "[兩張照片：合照、火鍋特寫]",
    "大家都點爆 肉盤疊到快倒了",
    "[貼圖：兔子抱著愛心，寫著想你]",
    "晚點回去再給你看我偷錄的影片",
    "欸 你覺得我今天是不是最好看的那個😏",
  ];
  const worthy = [
    w(1, "情感"),
    w(2, "照片或貼圖"),
    w(3, "其他"),
    w(4, "情感"),
    w(5, "其他"),
    w(6, "問他"),
  ];
  const out = assignAnswers(5, worthy, herLatest);
  assertEquals(mains(out), Array(5).fill(at(6)));
  assertEquals(out.map((a) => a?.extra), [
    at(1),
    at(3, 2),
    at(5, 4),
    at(1),
    at(3, 2),
  ]);
  // 旁邊那則沒列成值得接：併進最近一則有列的；只剩她問的那句時就併進那句。
  assertEquals(
    assignAnswers(
      2,
      [w(2, "照片或貼圖"), w(4, "照片或貼圖"), w(6, "問他")],
      herLatest,
    ),
    [{ main: at(6, 2, 4) }, { main: at(6, 2, 4) }],
  );
  // 照片在最前面：併進後面那則。
  assertEquals(
    assignAnswers(1, [w(1, "照片或貼圖"), w(2, "其他"), w(3, "情感")], [
      "[照片：一盤咖哩飯]",
      "我自己煮的！",
      "好想你喔",
    ]),
    [{ main: at(3), extra: at(2, 1) }],
  );
});

Deno.test("第 2 輪分句：只有照片、貼圖或表情就不指定；讀局面把它們標成情感或問他也一樣；有字的那則標成照片照字算", () => {
  assertEquals(
    assignAnswers(
      2,
      [w(1, "情感"), w(2, "問他"), w(3, "照片或貼圖")],
      ["「[貼圖：最愛你了]」", "😂😂", "[照片：夕陽]"],
    ),
    [null, null],
  );
  // 有字的那則被標成照片或貼圖：當成其他，同一級取最後傳的。
  assertEquals(
    assignAnswers(1, [w(1, "照片或貼圖"), w(2, "其他")], [
      "你看這張",
      "好看嗎",
    ]),
    [{ main: at(2), extra: at(1) }],
  );
});

Deno.test("第 2 輪分句：編號不在她最新這一輪、重複的略過；沒有值得接的、或 0 張", () => {
  const herLatest = ["a", "b"];
  assertEquals(
    assignAnswers(
      2,
      [w(0, "問他"), w(3, "問他"), w(2, "其他"), w(2, "問他")],
      herLatest,
    ),
    [{ main: at(2) }, { main: at(2) }],
  );
  assertEquals(assignAnswers(3, [], herLatest), [null, null, null]);
  assertEquals(assignAnswers(2, [w(1, "其他")], []), [null, null]);
  assertEquals(assignAnswers(0, [w(1, "其他")], herLatest), []);
});

Deno.test("照片、貼圖、表情的認法：方括號開頭（外面可以包「」）、整則只有表情與標點", () => {
  assert(isMediaLine("[貼圖：愛心]"));
  assert(isMediaLine("［照片］"));
  assert(isMediaLine("【圖片】海邊"));
  // 10/19 正式環境的案例：標記外面包一層「」。
  assert(isMediaLine("「[貼圖：最愛你了，狗狗比愛心]」"));
  assert(isMediaLine(" 😋 "));
  assert(isMediaLine("❤️❤️"));
  assert(isMediaLine("😂～"));
  assert(isMediaLine("❤️‍🔥…"));
  assert(!isMediaLine("好想你😋"));
  assert(!isMediaLine("讚讚❤️‍🔥…"));
  assert(!isMediaLine("哈哈"));
  assert(!isMediaLine("～"));
  assert(!isMediaLine(""));
});

Deno.test("第 2 輪分句：任何張數與句數，每張都回同一則有字的；順帶的不是它、也不是照片；順帶的句子不比卡多時全部有卡接", () => {
  for (let cards = 1; cards <= 5; cards++) {
    for (let k = 1; k <= 8; k++) {
      // 第 2、5、8 則是照片，其他有字；最後一則有字的是問他。
      const media = (i: number) => i % 3 === 1;
      const herLatest = Array.from(
        { length: k },
        (_, i) => media(i) ? `[照片：第${i + 1}張]` : `第${i + 1}則`,
      );
      const textLines = herLatest.flatMap((_, i) => media(i) ? [] : [i + 1]);
      const lastText = textLines.at(-1)!;
      const worthy = herLatest.map((_, i) =>
        w(
          i + 1,
          media(i)
            ? "照片或貼圖"
            : i + 1 === lastText
            ? "問他"
            : i % 2 === 0
            ? "情感"
            : "其他",
        )
      );
      const out = assignAnswers(cards, worthy, herLatest);
      const label = `${cards}/${k}`;
      assertEquals(out.length, cards, label);
      assert(out.every((a) => a?.main.line === lastText), label);
      for (const a of out) {
        if (!a?.extra) continue;
        assert(a.extra.line !== lastText, label);
        assert(!media(a.extra.line - 1), label);
      }
      if (textLines.length - 1 <= cards) {
        const used = new Set(
          out.flatMap((a) => [a!.main, ...(a!.extra ? [a!.extra] : [])]),
        );
        const covered = new Set(
          [...used].flatMap((x) => [x.line, ...x.with]),
        );
        assertEquals(covered.size, k, label);
      }
    }
  }
});

Deno.test("第 2 輪排卡：每張規格都帶 answer（回她最想聽的那則，可以順帶一則），開心分享的共鳴照舊在第二張；收尾也照分", () => {
  const turns = toTurns([
    { isFromMe: true, content: "晚餐吃什麼" },
    { isFromMe: false, content: "[照片：一盤咖哩飯]" },
    { isFromMe: false, content: "我自己煮的！" },
    { isFromMe: false, content: "好想你喔" },
  ]);
  const worthyLines = [w(2, "其他"), w(3, "情感"), w(1, "照片或貼圖")];
  const plan = planTurn(
    turns,
    tags({ worthyBallCount: 3 }),
    undefined,
    undefined,
    extras({ herHappyShare: true, herAffection: true, worthyLines }),
  );
  assertEquals(plan.decision, "send");
  assertEquals(tasks(plan.specs), ["接住", "共鳴", "接住", "接住", "接住"]);
  assertEquals(
    plan.specs.map((s) => s.answer),
    Array(5).fill({ main: at(3), extra: at(2, 1) }),
  );
  const close = planTurn(
    turns,
    tags({ declinedOrBoundary: true }),
    undefined,
    undefined,
    extras({ worthyLines }),
  );
  assertEquals(close.decision, "close");
  assertEquals(close.specs.map((s) => s.answer), [{
    main: at(3),
    extra: at(2, 1),
  }]);
  // 只有照片值得接：規格不加 answer。
  const photoOnly = planTurn(
    turns,
    tags(),
    undefined,
    undefined,
    extras({ worthyLines: [w(1, "照片或貼圖")] }),
  );
  assert(photoOnly.specs.length > 0);
  assert(photoOnly.specs.every((s) => !("answer" in s)));
});
