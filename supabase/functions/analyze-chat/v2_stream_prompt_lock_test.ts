// 健檢 F19：實際送出的對話分析 v2 串流提示詞上鎖（2026-10-12）。
// 原本只有 analyze_system_prompt_test（共用底座）與 baseline_contract_test（v1）
// 有雜湊鎖，真正送出的 v2 串流提示詞改了也沒有任何測試會發現。
//
// 組合定義在 v2_stream_prompt_variants.ts，組法照正式呼叫點。最常見的「付費＋
// 先收尾／資料不夠」存全文快照，改了會逐行顯示差異；其餘三種鎖長度與 SHA-256。
// 有意修改提示詞時：
//   deno run --allow-read --allow-write=supabase/functions/analyze-chat/testdata tools/ci/regen-v2-prompt-snapshot.ts
// 再把印出的新雜湊貼進下面的 LOCKS，審查時看快照檔的差異。
import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  SNAPSHOT_PATH,
  V2_PROMPT_VARIANTS,
} from "./v2_stream_prompt_variants.ts";

const LOCKS: Record<string, { length: number; sha256: string }> = {
  paid_usual_menu: {
    length: 48_047,
    sha256: "0ce6e5479e2eeddca565dcad1b4fa8d87616cf4cb320b44739a70892e43a6522",
  },
  paid_low_investment_menu: {
    length: 48_842,
    sha256: "e48de35b7405e1a32a8bc42441c1de2e0928e95e7c61d13e37c2388695bd9cba",
  },
  paid_first_exchange_menu: {
    length: 47_946,
    sha256: "595bed58deb44374c815ee74d76b0f17f9ed25508c579a67f7b0fe0ef6842209",
  },
  free_usual_menu: {
    length: 47_981,
    sha256: "788619bc063cb2d219ef5690be9b56681b000642d49f0a3c20ae74471b0508f8",
  },
};

const REGEN_HINT =
  "提示詞改了。有意修改就跑 tools/ci/regen-v2-prompt-snapshot.ts 更新快照與雜湊";

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

Deno.test("v2 串流提示詞：最常見組合與全文快照逐字相同", async () => {
  const variant = V2_PROMPT_VARIANTS.find((candidate) => candidate.snapshot);
  if (!variant) throw new Error("必須有一種組合存全文快照");
  const snapshot = await Deno.readTextFile(
    new URL(`./${SNAPSHOT_PATH}`, import.meta.url),
  );
  assertEquals(variant.render(), snapshot, REGEN_HINT);
});

Deno.test("v2 串流提示詞：四種組合的長度與 SHA-256 上鎖", async () => {
  assertEquals(
    V2_PROMPT_VARIANTS.map((variant) => variant.id).sort(),
    Object.keys(LOCKS).sort(),
    "組合清單與 LOCKS 要一一對應",
  );
  for (const variant of V2_PROMPT_VARIANTS) {
    const prompt = variant.render();
    assertEquals(
      { length: prompt.length, sha256: await sha256Hex(prompt) },
      LOCKS[variant.id],
      `${variant.id}：${REGEN_HINT}`,
    );
  }
});
