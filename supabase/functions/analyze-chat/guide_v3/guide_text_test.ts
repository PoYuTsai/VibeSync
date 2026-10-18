// 說明書原文的鎖：A 段六節與 B 段 47 條要跟 Bruce 定稿的版本逐字相同。
// 改字要連這裡的 sha256 一起改，避免悄悄變成別的版本。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { GUIDE_V3_ENTRIES } from "./entries.ts";
import {
  GUIDE_V3_SECTION_IDS,
  GUIDE_V3_SECTIONS,
  GUIDE_V3_VERSION,
} from "./guide_text.ts";
import {
  readSystemPrompt,
  WRITE_SAFETY_FLOOR,
  writeSystemPrompt,
} from "./prompts.ts";
import { SAFETY_RULES } from "../guardrails.ts";
import { PROMPT_LEAK_DEFENSE_DIRECTIVE } from "../../_shared/prompt_leak_guard.ts";

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.test("說明書 A 段：v3.6 六節逐字鎖住，各節以自己的標題開頭", async () => {
  assertEquals(GUIDE_V3_VERSION, "v3.6");
  for (const id of GUIDE_V3_SECTION_IDS) {
    assert(GUIDE_V3_SECTIONS[id].startsWith(`### ${id} `), id);
  }
  const joined = GUIDE_V3_SECTION_IDS.map((id) => GUIDE_V3_SECTIONS[id]).join(
    "\n\n",
  );
  assertEquals(joined.length, 5272);
  assertEquals(
    await sha256Hex(joined),
    "e4ef742392d5ccd50b2b786b0145bfca5ba6a34b6018eb0d04d48a5ff5486c49",
  );
});

Deno.test("說明書 B 段：B01–B47 連號、全部啟用、觸發與寫法逐字鎖住", async () => {
  assertEquals(
    GUIDE_V3_ENTRIES.map((e) => e.id),
    Array.from(
      { length: 47 },
      (_, i) => `B${String(i + 1).padStart(2, "0")}`,
    ),
  );
  assert(GUIDE_V3_ENTRIES.every((e) => e.enabled));
  assert(GUIDE_V3_ENTRIES.every((e) => e.trigger !== "" && e.writing !== ""));
  const canonical = GUIDE_V3_ENTRIES.map((e) =>
    [e.id, e.trigger, e.writing, String(e.enabled)].join("\t")
  ).join("\n");
  assertEquals(
    await sha256Hex(canonical),
    "23074f4da1b8537308bab96ac1defef90f4bbb315056660045c361200d488bd1",
  );
});

Deno.test("v3.5：A 段不出現「加分」（Bruce 10/17：A 每次都送給模型）", () => {
  for (const id of GUIDE_V3_SECTION_IDS) {
    assert(!GUIDE_V3_SECTIONS[id].includes("加分"), id);
  }
  assert(
    GUIDE_V3_SECTIONS.A4.includes(
      "同一句話，在她熱的時候說能升溫，在她冷的時候說不恰當。",
    ),
  );
});

Deno.test("v3.5：B47 要他已經提議換地方、她還是不肯；只指定店家不算", () => {
  const b47 = GUIDE_V3_ENTRIES.find((e) => e.id === "B47")!;
  assert(b47.trigger.includes("他已經提議換地方，她還是不肯"));
  assert(b47.trigger.includes("她只是指定店家、他還沒提換地方，不算"));
  // 讀局面看得到整句觸發（含「不算」的但書），才分得出只是指定店家。
  assert(readSystemPrompt().includes(`- B47：${b47.trigger}`));
});

Deno.test("v3.6：B44 照 Bruce（10/17、10/18）：不再寫「不順著她說加分」，只寫正面做法並附他的例句", () => {
  const b44 = GUIDE_V3_ENTRIES.find((e) => e.id === "B44")!;
  assert(!b44.writing.includes("加分"));
  assert(!b44.writing.includes("順著"));
  assert(
    b44.writing.includes(
      "直接說欣賞她哪一點，例如「有啊，願意踩雷這點我很欣賞」",
    ),
  );
  // 結構照舊：觸發不動；具體欣賞、不打分數、不說她缺什麼、不出下一題都留著。
  assertEquals(
    b44.trigger,
    "她討他的看法（「那我有加分嗎」「你覺得我是怎樣的人」）",
  );
  for (
    const kept of [
      "給一個具體、有根據的欣賞",
      "不打分數",
      "不說她還缺什麼",
      "不出下一題",
    ]
  ) {
    assert(b44.writing.includes(kept), kept);
  }
});

Deno.test("只放送進模型的部分：A 段裡沒有 B、C、D 段的內容", () => {
  for (const id of GUIDE_V3_SECTION_IDS) {
    const text = GUIDE_V3_SECTIONS[id];
    for (
      const marker of ["## B｜", "## C｜", "## D｜", "參考答案", "標準答案"]
    ) {
      assert(!text.includes(marker), `${id} 含 ${marker}`);
    }
  }
});

Deno.test("寫卡的安全底線：v3 自己的三條（未成年、拒絕後施壓、騷擾跟蹤威脅），不帶 v2 舊段落", () => {
  const write = writeSystemPrompt();
  assert(write.includes(WRITE_SAFETY_FLOOR));
  // v2 的舊段落還在講熱度（說明書 C6：舊段落不能跟新的並存）。
  assert(!write.includes(SAFETY_RULES.trim()));
  assert(!write.includes("熱度"));
  assertEquals(WRITE_SAFETY_FLOOR.split("\n").length, 4);
  for (
    const word of ["18 歲", "國中、高中", "明確拒絕", "騷擾", "跟蹤", "威脅"]
  ) {
    assert(WRITE_SAFETY_FLOOR.includes(word), word);
  }
});

Deno.test("真說明書組成的提示詞：讀局面帶 47 條觸發、不帶寫法；寫卡帶安全底線與外洩指令", () => {
  const read = readSystemPrompt();
  for (const e of GUIDE_V3_ENTRIES) {
    assert(read.includes(`- ${e.id}：${e.trigger}`), e.id);
    assert(!read.includes(e.writing), `${e.id} 的寫法不該進讀局面`);
  }
  assert(read.includes(GUIDE_V3_SECTIONS.A4));
  assert(!read.includes(GUIDE_V3_SECTIONS.A5));
  // 讀局面的 readForUser、waitFor 直接給用戶看，也帶外洩指令。
  assert(read.includes(PROMPT_LEAK_DEFENSE_DIRECTIVE.trim()));
  const write = writeSystemPrompt();
  for (const id of ["A1", "A2", "A3", "A5", "A6"] as const) {
    assert(write.includes(GUIDE_V3_SECTIONS[id]), id);
  }
  assert(!write.includes(GUIDE_V3_SECTIONS.A4));
  assert(write.includes(WRITE_SAFETY_FLOOR));
  assert(write.includes(PROMPT_LEAK_DEFENSE_DIRECTIVE.trim()));
});
