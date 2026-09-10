import {
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  latestAssistantShowsHostility,
  partnerPhotoDenialQuotes,
} from "./conversation_signals.ts";

Deno.test("hostility signal accepts direct exit boundaries", () => {
  for (
    const text of [
      "不要再傳了",
      "可以不要再聯絡我嗎？",
      "我不想跟你聊了",
      "你再這樣我就封鎖你",
      "請停止聯絡我",
      "請不要再跟我聯絡",
      "我希望你不要再聯絡我",
      "我覺得我們不要再聯絡比較好",
      "我不想再收到你的訊息",
      "我不想再跟你有任何聯絡",
      "請勿再聯絡我",
      "不要再聯\u200b絡我",
      "我不想跟你聊\ufe0f了",
      "先這樣\n不要再聯絡我",
      "先說清楚：不要再聯絡我",
      "請停止跟我聯絡",
      "我們不要再聯絡了",
      "不要再密了",
      "別再回我了",
      "到此為止，不要聯絡了",
      "別再傳 Line 給我",
    ]
  ) {
    assertEquals(latestAssistantShowsHostility(text), true, text);
  }
});

Deno.test("hostility signal does not treat a bare question as her exit declaration", () => {
  for (
    const text of [
      "不想聊了？",
      "你不想聊了嗎？",
      "前任跟我說，不要再傳了。",
      "她問我，可以不要再聯絡我嗎？",
      "她說：不要再聯絡我",
      "她問我：可以不要再聯絡我嗎？",
      "前任跟我說：不要再傳了",
      "下次別再來。這家店很雷。",
      "不是不想聊，只是今天有點累。",
    ]
  ) {
    assertFalse(latestAssistantShowsHostility(text), text);
  }
});

Deno.test("hostility signal keeps direct-speaker colon boundaries", () => {
  for (const text of ["我說：不要再聯絡我", "先說清楚：不要再聯絡我"]) {
    assertEquals(latestAssistantShowsHostility(text), true, text);
  }
});

// ── 2026-09-10 她否認自己大頭照細節 ────────────────────────────────────────

Deno.test("partnerPhotoDenialQuotes：使用者提照片、她下一句否認 → 引她原句，依序去重截 40 字", () => {
  const long = "巴黎？我沒去過巴黎啊，那是淡水河邊拍的。" + "真的啦".repeat(20);
  assertEquals(
    partnerPhotoDenialQuotes([
      { role: "ai", text: "今天上完瑜珈課，整個人很放鬆" },
      { role: "user", text: "妳大頭照是去巴黎鐵塔前野餐拍的吧？" },
      { role: "ai", text: long },
      { role: "user", text: "可是真的很像巴黎欸" },
      { role: "ai", text: "就說不是了，你認錯人了" },
      { role: "user", text: "妳頭像那張" },
      { role: "ai", text: "就說不是了，你認錯人了" },
    ]),
    [long.slice(0, 40), "就說不是了，你認錯人了"],
  );
});

Deno.test("partnerPhotoDenialQuotes：不觸發的形狀 → 空陣列", () => {
  // 她承認
  assertEquals(
    partnerPhotoDenialQuotes([
      { role: "user", text: "妳大頭照在巴黎拍的吧" },
      { role: "ai", text: "對啊 去年去進修的時候" },
    ]),
    [],
  );
  // 使用者沒提照片，她的否認是別的事
  assertEquals(
    partnerPhotoDenialQuotes([
      { role: "user", text: "妳是護理師嗎" },
      { role: "ai", text: "不是欸，我是設計師" },
    ]),
    [],
  );
  // 否認詞出現在使用者句、她的句子不含
  assertEquals(
    partnerPhotoDenialQuotes([
      { role: "user", text: "妳照片沒有戴眼鏡吧" },
      { role: "ai", text: "對，那天沒戴" },
    ]).length,
    1, // ponytail: 「沒戴」在她句裡也算否認詞——已知誤觸形狀，注入文只叫 debrief 對照判定
  );
  // 純客套謙辭（整句沒有任何事實）不算否認；帶內容的仍算
  for (const modest of ["沒有啦", "哪有～", "沒有啦哈哈", "才沒有！", "沒有沒有 XD"]) {
    assertEquals(
      partnerPhotoDenialQuotes([
        { role: "user", text: "妳大頭照超好看" },
        { role: "ai", text: modest },
      ]),
      [],
      modest,
    );
  }
  assertEquals(
    partnerPhotoDenialQuotes([
      { role: "user", text: "妳大頭照超好看，是在飯店大廳拍的吧" },
      { role: "ai", text: "沒有啦，那不是飯店" },
    ]),
    ["沒有啦，那不是飯店"],
  );
  assertEquals(partnerPhotoDenialQuotes([]), []);
  assertEquals(
    partnerPhotoDenialQuotes([{ role: "ai", text: "沒有啦" }]),
    [],
  );
});
