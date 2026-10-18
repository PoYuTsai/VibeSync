// 對象記憶：提示詞只帶對話、schema 照結構化輸出的限制，以及模型輸出過 v2 出處檢查。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { PROMPT_LEAK_DEFENSE_DIRECTIVE } from "../../_shared/prompt_leak_guard.ts";
import { GUIDE_V3_SECTIONS } from "./guide_text.ts";
import {
  MEMORY_KINDS,
  MEMORY_SCHEMA,
  memorySystemPrompt,
  memoryUserPrompt,
  partnerMemoryFrom,
} from "./memory.ts";
import { readSystemPrompt } from "./prompts.ts";
import { guideMessagesFrom } from "./stream_flow.ts";
import { toTurns, transcriptByTurn } from "./turns.ts";

const me = (content: string) => ({ isFromMe: true, content });
const her = (content: string, quotedReplyPreview?: string) => ({
  isFromMe: false,
  content,
  ...(quotedReplyPreview ? { quotedReplyPreview } : {}),
});
const item = (value: string, ...evidence: string[]) => ({ value, evidence });
const output = (
  over: Partial<Record<(typeof MEMORY_KINDS)[number], unknown>> = {},
) => JSON.stringify({ interests: [], traits: [], notes: [], ...over });

Deno.test("提示詞：三類規則與逐字出處、外洩指令；不帶讀局面的說明書", () => {
  const system = memorySystemPrompt();
  for (const kind of MEMORY_KINDS) assert(system.includes(`- ${kind}：`), kind);
  assert(system.includes("evidence 逐字複製她自己傳的訊息"));
  assert(system.includes("「（引用：…）」裡的內容"));
  assert(system.includes(PROMPT_LEAK_DEFENSE_DIRECTIVE.trim()));
  assert(!system.includes(GUIDE_V3_SECTIONS.A3));
  assert(!system.includes(GUIDE_V3_SECTIONS.A4));
  // 讀局面的提示詞一字不動（付費黑箱驗過），也沒有混進記憶的規則。
  assert(!readSystemPrompt().includes("targetProfile"));
  assert(!readSystemPrompt().includes("對象記憶"));
});

Deno.test("使用者訊息只有對話稿（跟讀局面同一份分輪，含引用前綴），沒有背景", () => {
  const turns = toTurns(guideMessagesFrom([
    me("週末都在幹嘛"),
    her("我每個週末都會去爬山", "週末都在幹嘛"),
  ]));
  const user = memoryUserPrompt(turns);
  assertEquals(user, `## 對話\n${transcriptByTurn(turns)}`);
  assert(user.includes("（引用：「週末都在幹嘛」）我每個週末都會去爬山"));
  for (const label of ["## 對象背景", "## 作戰板標籤", "## 更早的對話摘要"]) {
    assert(!user.includes(label), label);
  }
});

Deno.test("schema：三類都必填、每項 value＋evidence，沒有結構化輸出不支援的限制", () => {
  assertEquals(MEMORY_SCHEMA.required, [...MEMORY_KINDS]);
  assertEquals(MEMORY_SCHEMA.additionalProperties, false);
  const props = MEMORY_SCHEMA.properties as Record<
    string,
    { items: Record<string, unknown> }
  >;
  assertEquals(Object.keys(props), [...MEMORY_KINDS]);
  for (const kind of MEMORY_KINDS) {
    const items = props[kind].items;
    assertEquals(items.required, ["value", "evidence"]);
    assertEquals(items.additionalProperties, false);
  }
  const unsupported = [
    "maxItems",
    "minItems",
    "minLength",
    "maxLength",
    "minimum",
    "maximum",
    "pattern",
  ];
  const text = JSON.stringify(MEMORY_SCHEMA);
  for (const key of unsupported) assert(!text.includes(`"${key}"`), key);
});

Deno.test("她自己的原句撐得住：留下，形狀同 v2（provenanceVersion 1、出處是她的原文）", () => {
  const messages = [me("週末都在幹嘛"), her("我每個週末都會去爬山")];
  const memory = partnerMemoryFrom(
    output({ interests: [item("爬山", "我每個週末都會去爬山")] }),
    messages,
  );
  assertEquals(memory.ok, true);
  assertEquals(memory.targetProfile, {
    provenanceVersion: 1,
    interests: ["爬山"],
    traits: [],
    notes: [],
    evidence: {
      interests: [{ value: "爬山", sourceMessages: ["我每個週末都會去爬山"] }],
      traits: [],
      notes: [],
    },
  });
  assertEquals(memory.kept, { interests: 1, traits: 0, notes: 0 });
  assertEquals(memory.dropped, { interests: 0, traits: 0, notes: 0 });
});

Deno.test("他說的、只在背景出現的、貼圖：都擋下；全擋就不帶 targetProfile", () => {
  const messages = [
    me("我每個週末都會去爬山"),
    her("[貼圖]"),
    her("哈哈好喔"),
  ];
  const memory = partnerMemoryFrom(
    output({
      interests: [
        item("爬山", "我每個週末都會去爬山"),
        item("潛水", "- 興趣：潛水"),
      ],
      notes: [item("傳了貼圖", "[貼圖]")],
    }),
    messages,
  );
  assertEquals(memory.ok, true);
  assertEquals("targetProfile" in memory, false);
  assertEquals(memory.kept, { interests: 0, traits: 0, notes: 0 });
  assertEquals(memory.dropped, { interests: 2, traits: 0, notes: 1 });
});

Deno.test("出處對的是原始訊息，不是對話稿：引用前綴裡他的話不算她說的", () => {
  // 她引用他「我每週都會去游泳」回了一句；對話稿上這句會出現在她那一輪的前綴裡。
  const quotedHis = partnerMemoryFrom(
    output({ interests: [item("游泳", "我每週都會去游泳")] }),
    [me("我每週都會去游泳"), her("哈哈真的假的", "我每週都會去游泳")],
  );
  assertEquals("targetProfile" in quotedHis, false);
  // 她自己的話帶著引用前綴被整句抄下來：還是對得到她的原文，存的出處不含前綴。
  const prefixed = partnerMemoryFrom(
    output({
      interests: [item("游泳", "（引用：「你平常運動嗎」）我每週都會去游泳")],
    }),
    [me("你平常運動嗎"), her("我每週都會去游泳", "你平常運動嗎")],
  );
  const evidence = (prefixed.targetProfile?.evidence as Record<
    string,
    { sourceMessages: string[] }[]
  >).interests;
  assertEquals(evidence[0].sourceMessages, ["我每週都會去游泳"]);
});

Deno.test("她說不喜歡的：不是興趣，寫成 notes 可以留", () => {
  const memory = partnerMemoryFrom(
    output({
      interests: [item("爬山", "我不喜歡爬山")],
      notes: [item("不喜歡爬山", "我不喜歡爬山")],
    }),
    [her("我不喜歡爬山")],
  );
  assertEquals(memory.targetProfile?.interests, []);
  assertEquals(memory.targetProfile?.notes, ["不喜歡爬山"]);
  assertEquals(memory.kept, { interests: 0, traits: 0, notes: 1 });
  assertEquals(memory.dropped, { interests: 1, traits: 0, notes: 0 });
});

Deno.test("空陣列：成功但不帶；壞 JSON、不是物件：ok=false", () => {
  const empty = partnerMemoryFrom(output(), [her("我每個週末都會去爬山")]);
  assertEquals(empty.ok, true);
  assertEquals("targetProfile" in empty, false);
  for (const bad of ["不是 JSON", "[]", '"字串"', "null", ""]) {
    const memory = partnerMemoryFrom(bad, [her("我每個週末都會去爬山")]);
    assertEquals(memory.ok, false, bad);
    assertEquals("targetProfile" in memory, false, bad);
  }
});

Deno.test("每類只看前 5 個候選：多的算 dropped", () => {
  const lines = [
    "喜歡爬山",
    "喜歡潛水",
    "喜歡跑步",
    "喜歡攝影",
    "喜歡烘焙",
    "喜歡露營",
  ];
  const memory = partnerMemoryFrom(
    output({
      interests: lines.map((l) => item(l.slice(2), `我${l}`)),
    }),
    lines.map((l) => her(`我${l}`)),
  );
  assertEquals(memory.kept.interests, 5);
  assertEquals(memory.dropped.interests, 1);
});

// ── 主審第 1 輪 P2：她問他的事、或講他的事，不是她自己的事實 ──

Deno.test("她問他的嗜好（問句）：擋下", () => {
  const memory = partnerMemoryFrom(
    output({ interests: [item("爬山", "你每週都會去爬山嗎")] }),
    [me("我週末都在戶外"), her("你每週都會去爬山嗎")],
  );
  assertEquals("targetProfile" in memory, false);
  assertEquals(memory.dropped, { interests: 1, traits: 0, notes: 0 });
});

Deno.test("她自己講的「我每週都會去爬山」：照樣留下", () => {
  const memory = partnerMemoryFrom(
    output({ interests: [item("爬山", "我每週都會去爬山")] }),
    [her("我每週都會去爬山")],
  );
  assertEquals(memory.targetProfile?.interests, ["爬山"]);
});

Deno.test("原句有問句也有她的陳述：留下，出處只記陳述那一句", () => {
  const memory = partnerMemoryFrom(
    output({
      interests: [item("爬山", "你每週都會去爬山嗎", "我每週都會去爬山")],
    }),
    [her("你每週都會去爬山嗎"), her("我每週都會去爬山")],
  );
  assertEquals(memory.targetProfile?.interests, ["爬山"]);
  const evidence = (memory.targetProfile?.evidence as Record<
    string,
    { sourceMessages: string[] }[]
  >).interests;
  assertEquals(evidence[0].sourceMessages, ["我每週都會去爬山"]);
});

Deno.test("她的問句剪掉一截再抄：出處不認她的問句，一樣擋下", () => {
  const memory = partnerMemoryFrom(
    output({ interests: [item("爬山", "每週都會去爬山")] }),
    [her("你每週都會去爬山嗎")],
  );
  assertEquals("targetProfile" in memory, false);
});

Deno.test("問句（？、?、嗎／呢／吧後面接標點或表情）或「你」開頭講他的事：都不記", () => {
  const lines: [string, (typeof MEMORY_KINDS)[number], string][] = [
    ["你週末通常在家嗎？", "notes", "週末通常在家"],
    ["你養了一隻貓叫 Mochi 喔", "notes", "養了一隻貓叫 Mochi"],
    ["你最近在學攝影吧～", "interests", "攝影"],
    ["爬山你每週都會去?", "interests", "爬山"],
    ["那你平常都在練吉他呢", "interests", "吉他"],
    ["每天都會跑步的人是你吧😆", "interests", "跑步"],
  ];
  for (const [line, kind, value] of lines) {
    const memory = partnerMemoryFrom(
      output({ [kind]: [item(value, line)] }),
      [her(line)],
    );
    assertEquals("targetProfile" in memory, false, line);
  }
});
