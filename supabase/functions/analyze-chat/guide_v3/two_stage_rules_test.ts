// 兩段式實驗（開關 ANALYZE_GUIDE_V3_TWO_STAGE，Eric 2026-10-19）的排卡：帶張力張數、開心分享的
// 共鳴卡、每張卡接哪幾句。沒給四欄（開關沒開）時一律跟今天一樣。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { planTurn } from "./plan.ts";
import type { ReadTags, TwoStageTags, WorthyLine } from "./read_tags.ts";
import {
  arrangeCards,
  assignLines,
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

Deno.test("兩段式沒開：卡片規格沒有 lines、note 欄位（trace 跟今天一字不差）", () => {
  for (
    const t of [
      tags(),
      tags({ worthyBallCount: 2 }),
      tags({ light: "yellow" }),
      tags({ herMoodBad: true }),
    ]
  ) {
    for (const card of arrangeCards(send, "種子", t)) {
      assertEquals("lines" in card, false);
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

Deno.test("分句：情感先、一般的話其次、照片與貼圖最後；句子比卡少時從最重要的那句再輪", () => {
  const herLatest = ["[照片：一盤咖哩飯]", "我自己煮的！", "好想你喔"];
  const worthy = [w(2, "其他"), w(3, "情感"), w(1, "照片或貼圖")];
  assertEquals(assignLines(4, worthy, herLatest), [[3], [2], [1], [3]]);
  assertEquals(assignLines(3, worthy, herLatest), [[3], [2], [1]]);
  assertEquals(assignLines(1, [w(1, "其他")], ["哈"]), [[1]]);
});

Deno.test("分句：句子比卡多時從第一張開始各多接一句（每張最多兩句），超過兩倍張數的不排", () => {
  const herLatest = ["a", "b", "c", "d", "e"];
  const worthy = herLatest.map((_, i) => w(i + 1, "其他"));
  assertEquals(assignLines(3, worthy, herLatest), [[1, 4], [2, 5], [3]]);
  assertEquals(assignLines(2, worthy, herLatest), [[1, 3], [2, 4]]);
  assertEquals(assignLines(1, worthy, herLatest), [[1, 2]]);
});

Deno.test("分句：編號超出她最新這一輪、重複的略過；沒有值得接的句子就每張都不指定", () => {
  const herLatest = ["a", "b"];
  assertEquals(
    assignLines(
      2,
      [w(0, "其他"), w(3, "情感"), w(2, "其他"), w(2, "情感")],
      herLatest,
    ),
    [[2], [2]],
  );
  assertEquals(assignLines(3, [], herLatest), [[], [], []]);
  assertEquals(assignLines(2, [w(1, "其他")], []), [[], []]);
  assertEquals(assignLines(0, [w(1, "其他")], herLatest), []);
});

Deno.test("分句：方括號的照片貼圖標記、整則只有表情符號，就算讀局面標成情感也排在最後", () => {
  assert(isMediaLine("[貼圖：愛心]"));
  assert(isMediaLine("［照片］"));
  assert(isMediaLine("【圖片】海邊"));
  assert(isMediaLine(" 😋 "));
  assert(isMediaLine("❤️❤️"));
  assert(!isMediaLine("好想你😋"));
  assert(!isMediaLine("哈哈"));
  const herLatest = ["[貼圖：愛心]", "今天好累", "😋", "我升職了"];
  assertEquals(
    assignLines(
      4,
      [w(1, "情感"), w(2, "情感"), w(3, "情感"), w(4, "其他")],
      herLatest,
    ),
    [[2], [4], [1], [3]],
  );
});

Deno.test("分句：任何張數與句數，每張 1–2 句、合起來涵蓋全部（兩倍張數以內），最重要的那句在第一張", () => {
  for (let cards = 1; cards <= 5; cards++) {
    for (let k = 1; k <= 8; k++) {
      const herLatest = Array.from({ length: k }, (_, i) => `第${i + 1}則`);
      const worthy = herLatest.map((_, i) =>
        w(i + 1, i % 3 === 0 ? "情感" : "其他")
      );
      const out = assignLines(cards, worthy, herLatest);
      assertEquals(out.length, cards);
      assert(out.every((ls) => ls.length >= 1 && ls.length <= 2));
      const covered = new Set(out.flat());
      assertEquals(covered.size, Math.min(k, cards * 2), `${cards}/${k}`);
      assertEquals(out[0][0], 1);
    }
  }
});

Deno.test("兩段式排卡：每張規格帶要接的句子，第一張接最重要的那句", () => {
  const turns = toTurns([
    { isFromMe: true, content: "晚餐吃什麼" },
    { isFromMe: false, content: "[照片：一盤咖哩飯]" },
    { isFromMe: false, content: "我自己煮的！" },
    { isFromMe: false, content: "好想你喔" },
  ]);
  const plan = planTurn(
    turns,
    tags({ worthyBallCount: 3 }),
    undefined,
    undefined,
    extras({
      herHappyShare: true,
      herAffection: true,
      worthyLines: [w(2, "其他"), w(3, "情感"), w(1, "照片或貼圖")],
    }),
  );
  assertEquals(plan.decision, "send");
  assertEquals(plan.specs.map((s) => s.lines), [[3], [2], [1], [3], [2]]);
  assertEquals(tasks(plan.specs), ["接住", "共鳴", "接住", "接住", "接住"]);
  // 收尾也照分。
  const close = planTurn(
    turns,
    tags({ declinedOrBoundary: true }),
    undefined,
    undefined,
    extras({ worthyLines: [w(2, "其他"), w(3, "情感"), w(1, "照片或貼圖")] }),
  );
  assertEquals(close.decision, "close");
  assertEquals(close.specs.map((s) => s.lines), [[3, 2]]);
});
