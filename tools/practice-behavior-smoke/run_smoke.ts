// 練習室 NPC 行為評測（pre-release 手動跑，刻意不進 CI——需要網路與
// DEEPSEEK_API_KEY，混進 CI 會連紅；坑已登記）。
//
// 跑法（repo 根目錄）：
//   deno run --allow-read --allow-net tools/practice-behavior-smoke/run_smoke.ts
//
// 用 production 同款 CHAT_SYSTEM_PROMPT＋deepseek-v4-flash 生 NPC 回覆，
// 先過 bannedPatterns（確定性），再交 LLM 評審（temperature 0）判語意。
// 任何 FAIL → exit 1。NPC 生成溫度 0.7（貼近線上），單發有隨機性：
// FAIL 先重看回覆內容再判是回歸還是抖動。

import { CHAT_SYSTEM_PROMPT } from "../../supabase/functions/practice-chat/prompt.ts";
import { SMOKE_CASES } from "./cases.ts";

const envText = await Deno.readTextFile(
  new URL("../../supabase/.env", import.meta.url),
);
const apiKey = envText.match(/DEEPSEEK_API_KEY=("?)([^"\n]+)\1/)?.[2];
if (!apiKey) {
  console.error("DEEPSEEK_API_KEY not found in supabase/.env");
  Deno.exit(2);
}

async function callDeepSeek(opts: {
  system: string;
  user: string;
  jsonMode?: boolean;
  temperature: number;
}): Promise<string> {
  const res = await fetch("https://api.deepseek.com/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: "deepseek-v4-flash",
      messages: [
        { role: "system", content: opts.system },
        { role: "user", content: opts.user },
      ],
      max_tokens: 300,
      temperature: opts.temperature,
      stream: false,
      thinking: { type: "disabled" },
      ...(opts.jsonMode ? { response_format: { type: "json_object" } } : {}),
    }),
  });
  const json = await res.json();
  const content = json.choices?.[0]?.message?.content;
  if (typeof content !== "string" || content.length === 0) {
    throw new Error(`deepseek empty reply: ${JSON.stringify(json).slice(0, 200)}`);
  }
  return content;
}

const JUDGE_SYSTEM =
  "你是行為評測員。給你一句使用者訊息、模擬女生的回覆、與判準。" +
  '嚴格依判準判定，只輸出 JSON：{"pass":true|false,"reason":"20字內"}';

let failures = 0;
for (const c of SMOKE_CASES) {
  const reply = await callDeepSeek({
    system: CHAT_SYSTEM_PROMPT,
    user: c.userText,
    temperature: 0.7,
  });
  const flat = reply.replaceAll("\n", " ⏎ ");

  const banned = (c.bannedPatterns ?? []).find((p) => p.test(reply));
  if (banned) {
    failures++;
    console.log(`FAIL ${c.id} [banned ${banned}]\n  她回：${flat}`);
    continue;
  }

  const verdictRaw = await callDeepSeek({
    system: JUDGE_SYSTEM,
    user: `使用者訊息：${c.userText}\n她的回覆：${reply}\n判準：${c.criterion}`,
    jsonMode: true,
    temperature: 0,
  });
  let verdict: { pass?: boolean; reason?: string };
  try {
    verdict = JSON.parse(verdictRaw);
  } catch {
    failures++;
    console.log(`FAIL ${c.id} [judge unparsable] ${verdictRaw.slice(0, 100)}`);
    continue;
  }
  if (verdict.pass === true) {
    console.log(`pass ${c.id}\n  她回：${flat}`);
  } else {
    failures++;
    console.log(`FAIL ${c.id} [${verdict.reason ?? "no reason"}]\n  她回：${flat}`);
  }
}

console.log(`\n${SMOKE_CASES.length - failures}/${SMOKE_CASES.length} passed`);
Deno.exit(failures > 0 ? 1 : 0);
