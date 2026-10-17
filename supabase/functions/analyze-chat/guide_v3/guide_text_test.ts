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
import { readSystemPrompt, writeSystemPrompt } from "./prompts.ts";
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

Deno.test("說明書 A 段：v3.4 六節逐字鎖住，各節以自己的標題開頭", async () => {
  assertEquals(GUIDE_V3_VERSION, "v3.4");
  for (const id of GUIDE_V3_SECTION_IDS) {
    assert(GUIDE_V3_SECTIONS[id].startsWith(`### ${id} `), id);
  }
  const joined = GUIDE_V3_SECTION_IDS.map((id) => GUIDE_V3_SECTIONS[id]).join(
    "\n\n",
  );
  assertEquals(joined.length, 5268);
  assertEquals(
    await sha256Hex(joined),
    "7680c722ff6c0636e3fa9d46fdf735adfe7c16c3fd01ddda5c6da0b09b2d4cac",
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
    "dd700780953c8be3e0838ea171439e42c98f8b6e0b9f784d2349eda273f445ca",
  );
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

Deno.test("真說明書組成的提示詞：讀局面帶 47 條觸發、不帶寫法；寫卡帶安全規則與外洩指令", () => {
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
  assert(write.includes(SAFETY_RULES.trim()));
  assert(write.includes(PROMPT_LEAK_DEFENSE_DIRECTIVE.trim()));
});
