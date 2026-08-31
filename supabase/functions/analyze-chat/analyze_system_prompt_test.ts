import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { SYSTEM_PROMPT } from "./analyze_prompt/system_prompt.ts";

// Batch C 抽出共享模組前的 main@b330e105 基線。這裡鎖最終組合 bytes，
// 讓相容 re-export 或 section 順序漂移直接在 CI 顯現。
Deno.test("Analyze system prompt stays byte-identical after shared extraction", async () => {
  const bytes = new TextEncoder().encode(SYSTEM_PROMPT);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const sha256 = [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");

  assertEquals(SYSTEM_PROMPT.length, 34_496);
  assertEquals(bytes.length, 80_466);
  assertEquals(
    sha256,
    "ba63b43d6cf47e2c63051a8a41f458aabf13b631d0ea862f14081bdcf82b8738",
  );
});
