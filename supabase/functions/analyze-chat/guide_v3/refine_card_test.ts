// 任務卡的「再調一下」：卡片規格驗證、任務卡規則段落、調完的字定稿（跟出卡同一套檢查，
// 再加則數與空格）。
import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { GUIDE_V3_SENTINELS } from "./finalize.ts";
import {
  finalizeRefinedCard,
  GUIDE_V3_REFINE_SENTINELS,
  type GuideV3RefineCard,
  guideV3RefineSection,
  isGuideV3RefineSafetyRejection,
  parseGuideV3RefineCard,
  splitCardMessages,
} from "./refine_card.ts";
import { METHOD_CODE, TASK_CODE, VOICE_CODE } from "./wire.ts";

const PUSH: GuideV3RefineCard = {
  task: "push",
  voice: "default",
  method: "reaction",
};

function refined(
  draft: string,
  optimized: string,
  card: Partial<GuideV3RefineCard> = {},
  sourceText = "",
) {
  return finalizeRefinedCard({
    draft,
    optimized,
    card: { ...PUSH, ...card },
    sourceText,
  });
}

Deno.test("卡片規格：沒帶是一般微調；三個欄位都要是出卡用的代碼", () => {
  assertEquals(parseGuideV3RefineCard(undefined), { kind: "absent" });
  assertEquals(parseGuideV3RefineCard(null), { kind: "absent" });
  assertEquals(
    parseGuideV3RefineCard({ task: "push", voice: "his", method: "blank" }),
    { kind: "ok", card: { task: "push", voice: "his", method: "blank" } },
  );
  // 其他欄位不看，也不帶進規格（hash 只用這三個）。
  assertEquals(
    parseGuideV3RefineCard({
      task: "close",
      voice: "default",
      method: "reaction",
      slot: 3,
    }),
    {
      kind: "ok",
      card: { task: "close", voice: "default", method: "reaction" },
    },
  );
  for (
    const bad of [
      "push",
      ["push"],
      {},
      { task: "push", voice: "default" },
      { task: "推進", voice: "default", method: "reaction" },
      { task: "push", voice: "預設", method: "reaction" },
      { task: "push", voice: "default", method: "留空格" },
      { task: "push", voice: "default", method: 1 },
      { task: "tease", voice: "default", method: "reaction" },
    ]
  ) {
    assertEquals(parseGuideV3RefineCard(bad), { kind: "error" }, String(bad));
  }
});

Deno.test("卡片規格：代碼表跟 wire.ts 同一份，出卡用的每個代碼都認得", () => {
  for (const task of Object.values(TASK_CODE)) {
    for (const voice of Object.values(VOICE_CODE)) {
      for (const method of Object.values(METHOD_CODE)) {
        const parsed = parseGuideV3RefineCard({ task, voice, method });
        assertEquals(parsed.kind, "ok", `${task}/${voice}/${method}`);
        // 每種組合都組得出規則段落（不會因為少一條對照而丟例外）。
        if (parsed.kind === "ok") assert(guideV3RefineSection(parsed.card));
      }
    }
  }
});

Deno.test("拆則：換行與字面的 \\n 都算分開，空行不算一則", () => {
  assertEquals(splitCardMessages("好啊\n週六見"), ["好啊", "週六見"]);
  assertEquals(splitCardMessages("好啊\\n週六見"), ["好啊", "週六見"]);
  assertEquals(splitCardMessages(" 好啊 \r\n\n 週六見 \n"), ["好啊", "週六見"]);
  assertEquals(splitCardMessages("  "), []);
});

Deno.test("任務卡規則：保住任務；推進不能用徵求同意收尾；帶張力兩段都留", () => {
  const push = guideV3RefineSection(PUSH);
  assertStringIncludes(push, "## 任務卡規則");
  assertStringIncludes(push, "任務是「推進」");
  assertStringIncludes(push, "最後一句不能是徵求同意的問法");
  assertStringIncludes(push, "不要為了降低壓力改成這種問法");
  assertStringIncludes(push, "優先於上面的「調整品質」");
  assertStringIncludes(push, "「不可覆蓋的規則」仍然最優先");
  assertStringIncludes(push, "不加入卡片沒有的事實");
  assertStringIncludes(push, "調完的則數跟原本一樣");
  assertStringIncludes(push, "optimized 裡一則一行");
  assertStringIncludes(push, "「＿＿」");
  assertStringIncludes(push, "每一個都原樣保留");
  assertStringIncludes(push, "「更直接」");
  assertStringIncludes(push, "「更幽默」");

  const tension = guideV3RefineSection({ ...PUSH, task: "tension" });
  assertStringIncludes(tension, "任務是「帶張力」");
  assertStringIncludes(tension, "把氣氛鬆開的那一句也要留著");
  assert(!tension.includes("徵求同意"), "推進的規則不放進別的任務");
});

Deno.test("任務卡規則：預設口吻用「你」；照他口吻維持卡片原本的稱呼", () => {
  assertStringIncludes(guideV3RefineSection(PUSH), "一律用「你」");
  const his = guideV3RefineSection({ ...PUSH, voice: "his" });
  assertStringIncludes(his, "卡片用「妳」就維持「妳」");
  assert(!his.includes("一律用「你」"));
});

Deno.test("任務卡規則：「有他」做法各有一句；同規格每次都是同一段（可快取）", () => {
  assertStringIncludes(
    guideV3RefineSection({ ...PUSH, method: "blank" }),
    "一律維持空格",
  );
  assertStringIncludes(
    guideV3RefineSection({ ...PUSH, method: "invented" }),
    "不要再多編新的細節",
  );
  assertStringIncludes(
    guideV3RefineSection({ ...PUSH, method: "his_facts" }),
    "只能用卡片裡已經有的內容",
  );
  assertEquals(guideV3RefineSection(PUSH), guideV3RefineSection({ ...PUSH }));
});

Deno.test("定稿：則數照舊、預設口吻換成「你」、簡體轉繁體", () => {
  assertEquals(refined("好啊\n週六見", "妳說的喔\n这周六见"), {
    ok: true,
    messages: ["你說的喔", "這週六見"],
  });
  // 照他口吻不動稱呼。
  assertEquals(refined("好", "妳說的喔", { voice: "his" }), {
    ok: true,
    messages: ["妳說的喔"],
  });
  // 模型把換行寫成字面的 \n：照樣拆回兩則。
  assertEquals(refined("好啊\n週六見", "好啊\\n週六下午見"), {
    ok: true,
    messages: ["好啊", "週六下午見"],
  });
});

Deno.test("定稿：「欠」組照給（Bruce 10/18 改回只記錄）；禁語、脅迫、外洩、整則英文照出卡的規則擋", () => {
  assertEquals(refined("週六見", "週六見，遲到就算你欠我一杯"), {
    ok: true,
    messages: ["週六見，遲到就算你欠我一杯"],
  });
  assertEquals(refined("好啊\n週六見", "好啊\n先欠著也行"), {
    ok: true,
    messages: ["好啊", "先欠著也行"],
  });
  assertEquals(refined("週六見", "你不來我就去死"), {
    ok: false,
    reason: "unsafe",
  });
  assertEquals(refined("週六見", "不要放棄，一直約她就對了"), {
    ok: false,
    reason: "unsafe",
  });
  assertEquals(refined("週六見", `週六見 ${GUIDE_V3_SENTINELS[0]}`), {
    ok: false,
    reason: "prompt_leak",
  });
  assertEquals(refined("週六見", "See you on Saturday"), {
    ok: false,
    reason: "language_drift",
  });
  // 對話裡出現過的英文照留。
  assertEquals(
    refined("週六見", "週六 brunch 見", {}, "她說想吃 brunch"),
    { ok: true, messages: ["週六 brunch 見"] },
  );
});

Deno.test("定稿：則數變了整次不給（兩則併一則、一則拆兩則、清完少一則）", () => {
  assertEquals(refined("好啊\n週六見", "好啊，週六見"), {
    ok: false,
    reason: "message_count_changed",
  });
  assertEquals(refined("好啊，週六見", "好啊\n週六見"), {
    ok: false,
    reason: "message_count_changed",
  });
  assertEquals(refined("好啊\n週六見", "好啊\nПривет"), {
    ok: false,
    reason: "message_count_changed",
  });
});

Deno.test("定稿：每一則的空格段數都要跟原本一樣（不能填掉、挪到別則或多編一個）", () => {
  assertEquals(refined("我是做＿＿的\n你呢", "我是做設計的\n你呢"), {
    ok: false,
    reason: "blank_changed",
  });
  // 總數一樣也不行：第一則的身分空格被填掉，第二則多一個（主審第 1 輪 P2-5）。
  assertEquals(refined("我做＿＿\n住＿＿", "我做設計\n住＿＿，週末去＿＿"), {
    ok: false,
    reason: "blank_changed",
  });
  assertEquals(
    refined("我做＿＿，住＿＿", "我做＿＿的，住在＿", { method: "blank" }),
    { ok: true, messages: ["我做＿＿的，住在＿"] },
  );
  assertEquals(refined("我做＿＿\n住＿＿", "我做＿＿啦\n住＿＿附近"), {
    ok: true,
    messages: ["我做＿＿啦", "住＿＿附近"],
  });
  assertEquals(refined("我做＿＿，住＿＿", "我做＿＿，住哪就先不說"), {
    ok: false,
    reason: "blank_changed",
  });
  assertEquals(refined("週末去走走", "週末去＿＿走走"), {
    ok: false,
    reason: "blank_changed",
  });
});

Deno.test("外洩哨兵：任務卡規則段落的每一行、每一條規則都有，至少 12 字", () => {
  assert(GUIDE_V3_REFINE_SENTINELS.length > 20);
  for (const sentinel of GUIDE_V3_REFINE_SENTINELS) {
    assert(sentinel.length >= 12, sentinel);
  }
  // 每一種規格組出來的段落，標題以外的每一行都至少中一個哨兵。
  for (const task of Object.values(TASK_CODE)) {
    for (const voice of Object.values(VOICE_CODE)) {
      for (const method of Object.values(METHOD_CODE)) {
        const lines = guideV3RefineSection({ task, voice, method })
          .split("\n").slice(1).filter((l) => l.trim());
        for (const line of lines) {
          assert(
            GUIDE_V3_REFINE_SENTINELS.some((s) => line.includes(s)),
            line,
          );
        }
      }
    }
  }
});

Deno.test("定稿：模型把任務卡規則照抄成一則就整次不給（外洩）", () => {
  const section = guideV3RefineSection(PUSH).split("\n");
  // 主審第 1 輪 P2-4 的例子：段落開頭那一行。
  assertEquals(refined("那就週六\n我來訂位", `那就週六\n${section[2]}`), {
    ok: false,
    reason: "prompt_leak",
  });
  // 規則句（推進那一條，去掉前面的項目符號）。
  assertEquals(
    refined(
      "那就週六\n我來訂位",
      "那就週六\n往前推的意思要留著：用陳述句，或當作已經說定的口氣",
    ),
    { ok: false, reason: "prompt_leak" },
  );
  // 口吻那一條，夾在一般句子裡也算。
  assertEquals(
    refined(
      "好啊",
      "好啊，稱呼對方一律用「你」，不用「妳」；語助詞和表情符號少用",
    ),
    { ok: false, reason: "prompt_leak" },
  );
  // 簡體照抄：整理後轉成繁體一樣抓得到。
  assertEquals(
    refined("好啊", "好啊，这一则是对话分析写好的任务卡。这一节优先于上面的"),
    { ok: false, reason: "prompt_leak" },
  );
});

Deno.test("外洩哨兵不誤擋：v3 錄音裡 73 張卡的字都不會中", async () => {
  const fixtures = JSON.parse(
    await Deno.readTextFile(
      new URL("../testdata/guide_v3_replay_fixtures.json", import.meta.url),
    ),
  ) as { cases: { expected: { events: Record<string, unknown>[] } }[] };
  const cards = fixtures.cases.flatMap((c) =>
    c.expected.events.filter((e) => e.type === "analysis.card")
  ) as { messages: string[] }[];
  assertEquals(cards.length, 73);
  for (const card of cards) {
    const text = card.messages.join("\n");
    assert(
      !GUIDE_V3_REFINE_SENTINELS.some((s) => text.includes(s)),
      text,
    );
  }
});

Deno.test("定稿重跑不變：已經定稿過的卡再過一次照樣通過、字也不變（重播再定稿靠這個）", async () => {
  const fixtures = JSON.parse(
    await Deno.readTextFile(
      new URL("../testdata/guide_v3_replay_fixtures.json", import.meta.url),
    ),
  ) as {
    cases: {
      messages: { content: string }[];
      expected: { events: Record<string, unknown>[] };
    }[];
  };
  let checked = 0;
  for (const c of fixtures.cases) {
    const sourceText = c.messages.map((m) => m.content).join("\n");
    for (const e of c.expected.events) {
      if (e.type !== "analysis.card") continue;
      const card = e as unknown as {
        task: string;
        voice: string;
        method: string;
        messages: string[];
      };
      const text = card.messages.join("\n");
      const parsed = parseGuideV3RefineCard(card);
      assert(parsed.kind === "ok", text);
      assertEquals(
        finalizeRefinedCard({
          draft: text,
          optimized: text,
          card: parsed.card,
          sourceText,
        }),
        { ok: true, messages: splitCardMessages(text) },
        text,
      );
      checked++;
    }
  }
  assertEquals(checked, 73);
});

Deno.test("內容問題（引導換方向）只有禁語脅迫；其他當成這次沒調好（「欠」組 10/18 起不擋）", () => {
  assert(isGuideV3RefineSafetyRejection("unsafe"));
  for (
    const reason of [
      "prompt_leak",
      "language_drift",
      "empty_after_cleanup",
      "message_count_changed",
      "blank_changed",
      null,
    ] as const
  ) {
    assert(!isGuideV3RefineSafetyRejection(reason), String(reason));
  }
});
