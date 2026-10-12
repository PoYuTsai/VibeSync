// 重新產生對話分析 v2 串流提示詞的全文快照，並印出四種組合的長度與 SHA-256。
// 只在「有意修改提示詞」時跑：
//   deno run --allow-read --allow-write=supabase/functions/analyze-chat/testdata tools/ci/regen-v2-prompt-snapshot.ts
// 跑完把印出的雜湊貼進 supabase/functions/analyze-chat/v2_stream_prompt_lock_test.ts，
// 審查時看快照檔的逐行差異。組法與正式呼叫點 analyze_stream_handler.ts 相同。
import {
  SNAPSHOT_PATH,
  V2_PROMPT_VARIANTS,
} from "../../supabase/functions/analyze-chat/v2_stream_prompt_variants.ts";

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

const snapshotUrl = new URL(
  `../../supabase/functions/analyze-chat/${SNAPSHOT_PATH}`,
  import.meta.url,
);
for (const variant of V2_PROMPT_VARIANTS) {
  const prompt = variant.render();
  if (variant.snapshot) await Deno.writeTextFile(snapshotUrl, prompt);
  console.log(
    `${variant.id}\tlength=${prompt.length}\tsha256=${await sha256Hex(prompt)}`,
  );
}
