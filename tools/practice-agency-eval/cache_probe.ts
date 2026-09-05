// Phase 4.5b 刀 B 的 cache 量測腳本（Codex R1 P1-2）。
//
// **為什麼要有這一支**：刀 B 把 Haiku 的 system 拆成「穩定前綴 ＋ 當輪尾巴」，
// 前綴掛 `cache_control: ephemeral`。但 Haiku 4.5 的最小可快取長度是 2048
// tokens，而穩定前綴實測只有 2,799–3,608 code units——`prompt_test.ts` 只能用
// **字元數粗估**，沒有用真的 tokenizer 量過。唯一能證明「cache 真的命中」的
// 證據是 Anthropic 回的 `usage`。
//
// **這支腳本不會被任何測試執行**（付費呼叫要等 Eric 授權）。`cache_probe_test.ts`
// 只跑 dry-run：驗 plan 的形狀與「同一格的兩輪穩定前綴逐位元組相同」。
//
// 跑法（**需要 Eric 明確授權才能跑，會真的花錢**）：
//   export CLAUDE_API_KEY=$(cat ~/.config/anthropic/key)
//   deno run --allow-env --allow-net --allow-read \
//     tools/practice-agency-eval/cache_probe.ts
//
// 每一格對**同一場**連續打兩次 Haiku（第二輪只多一則玩家訊息與一則她的回覆，
// 穩定前綴逐位元組不變）。判讀：
//   - 第 1 輪 `cacheCreationInputTokens > 0`＝前綴長到寫得進 cache。
//   - 第 2 輪 `cacheReadInputTokens > 0`＝**真的命中**（刀 B 成立）。
//   - 兩輪 create/read 都 0＝前綴沒到 2048 tokens 門檻，刀 B 目前是死碼；
//     出口見計畫檔 Phase 4.5b「已知限制」（把記憶摘要／朋友圈也搬進前綴，
//     或整個拆法退掉）。

import { buildChatPromptBundle } from "../../supabase/functions/practice-chat/prompt.ts";
import {
  callClaude,
  CLAUDE_HAIKU_MODEL,
} from "../../supabase/functions/practice-chat/claude.ts";
import { resolvePracticeProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";
import type { PracticeTurn } from "../../supabase/functions/practice-chat/validate.ts";
import { readAnthropicKey } from "./run_agency.ts";
import { estimateCostUsd, HAIKU_4_5_PRICING } from "./pricing.ts";

const CHAT_MAX_TOKENS = 200;
const CHAT_TEMPERATURE = 0.9;
const MODEL_TIMEOUT_MS = 30000;
const PROBE_THREAD_ID = "cache-probe-thread";

/** 最短的兩輪逐字稿：第二輪只是在第一輪後面接一則她的回覆與一則玩家訊息。 */
const ROUND1: PracticeTurn[] = [{ role: "user", text: "東東" }];
const ROUND2: PracticeTurn[] = [
  ...ROUND1,
  { role: "ai", text: "東東是誰" },
  { role: "user", text: "阿布達比" },
];

export interface ProbeCell {
  readonly label: string;
  readonly practiceMode: "standard" | "beginner" | "game";
  readonly style: boolean;
  readonly profileId: string;
}

/**
 * standard／beginner／game × style on／off ＝ 6 格（Game 要 SR 角色）。
 * 每格 2 次呼叫 → 共 12 次 Haiku。
 */
export const PROBE_CELLS: readonly ProbeCell[] =
  (["standard", "beginner", "game"] as const)
    .flatMap((practiceMode) =>
      [false, true].map((style) => ({
        label: `${practiceMode}/style${style ? "on" : "off"}`,
        practiceMode,
        style,
        profileId: practiceMode === "game"
          ? "practice_girl_004"
          : "practice_girl_001",
      }))
    );

/** 一格的兩輪 bundle（純函式，dry-run 測試就是驗這個）。 */
export function probePlanFor(cell: ProbeCell) {
  const profile = resolvePracticeProfile({ profileId: cell.profileId });
  const bundleFor = (turns: PracticeTurn[]) =>
    buildChatPromptBundle(turns, profile, {
      replyStyle: cell.style,
      agencyMode: "on",
      practiceMode: cell.practiceMode,
      visiblePracticeThreadId: PROBE_THREAD_ID,
      temperatureScore: 40,
      familiarityScore: 10,
    });
  return { round1: bundleFor(ROUND1), round2: bundleFor(ROUND2) };
}

async function main(): Promise<void> {
  const apiKey = readAnthropicKey();
  // Phase 4.5c：單價唯一來源是 pricing.ts（這支之前只印 token 數，金額要另外
  // 手算，跟 README 的外推容易對不起來）。
  let totalUsd = 0;
  console.log("cell\tround\tcreate\tread\tinput\tprefixChars\tusd");
  for (const cell of PROBE_CELLS) {
    const plan = probePlanFor(cell);
    for (
      const [round, bundle] of [[1, plan.round1], [2, plan.round2]] as const
    ) {
      let usage = { create: 0, read: 0, input: 0, output: 0 };
      try {
        await callClaude({
          apiKey,
          model: CLAUDE_HAIKU_MODEL,
          messages: bundle.messages,
          maxTokens: CHAT_MAX_TOKENS,
          temperature: CHAT_TEMPERATURE,
          timeoutMs: MODEL_TIMEOUT_MS,
          systemCachePrefix: bundle.systemStable,
          onUsage: (u) => {
            usage = {
              create: u.cacheCreationInputTokens,
              read: u.cacheReadInputTokens,
              input: u.inputTokens,
              output: u.outputTokens,
            };
          },
        });
      } catch (e) {
        // 生成失敗不影響量測目的：`onUsage` 在 provider 回了 usage 時就已經響過。
        console.error(`[cache-probe] ${cell.label} r${round} 失敗：${e}`);
      }
      const usd = estimateCostUsd({
        inputTokens: usage.input,
        outputTokens: usage.output,
        cacheReadInputTokens: usage.read,
        cacheCreationInputTokens: usage.create,
      }, HAIKU_4_5_PRICING);
      totalUsd += usd;
      console.log(
        [
          cell.label,
          round,
          usage.create,
          usage.read,
          usage.input,
          bundle.systemStable.length,
          usd.toFixed(6),
        ].join("\t"),
      );
    }
  }
  console.log(
    `total\t${PROBE_CELLS.length * 2}\t\t\t\t\t${totalUsd.toFixed(6)}`,
  );
}

if (import.meta.main) await main();
