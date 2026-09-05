// 統計物件 → markdown。純函式，不打網路、不讀檔。

import {
  type LogStats,
  MISSING_FIELDS,
  PLAN_MONTHLY_TWD,
  type Stats,
} from "./aggregate.ts";

const usd = (value: number) => `$${value.toFixed(4)}`;
const twd = (value: number) =>
  `NT$${Math.round(value).toLocaleString("en-US")}`;
const pct = (value: number | null) =>
  value === null ? "—" : `${(value * 100).toFixed(1)}%`;

function ratio(part: number, whole: number): number | null {
  return whole > 0 ? part / whole : null;
}

export function renderReport(stats: Stats): string {
  const lines: string[] = [];
  const { range } = stats;

  lines.push(`# 練習室週報 ${range.from} ～ ${range.to}`);
  lines.push("");
  lines.push(
    "時間窗以 UTC 計，`" + range.from + " 00:00` 起（含）至 `" +
      range.to + " 00:00` 止（不含）。",
  );
  lines.push("");
  lines.push("資料來源：`practice_chat_sessions`（場次帳本）與 `ai_logs`");
  lines.push("（提示／檢討生成列）。聊天回合的 telemetry 不進 DB，見文末。");
  lines.push("");

  lines.push("## 場次");
  lines.push("");
  lines.push("| practiceMode | 場次 |");
  lines.push("| --- | ---: |");
  for (const [mode, count] of Object.entries(stats.sessions.byMode)) {
    lines.push(`| ${mode} | ${count} |`);
  }
  lines.push(`| **合計** | **${stats.sessions.total}** |`);
  lines.push("");
  lines.push(
    `已結算（扣費或測試帳號豁免）場次：${stats.sessions.charged}／${stats.sessions.total}（${
      pct(ratio(stats.sessions.charged, stats.sessions.total))
    }）。`,
  );
  lines.push(
    `提示次數合計 ${stats.hintTotal}、檢討張數合計 ${stats.debriefTotal}。`,
  );
  lines.push("");

  lines.push("## 回合分佈");
  lines.push("");
  lines.push("| AI 回合數 | 場次 |");
  lines.push("| ---: | ---: |");
  for (const bucket of stats.turnHistogram) {
    lines.push(`| ${bucket.turns} | ${bucket.sessions} |`);
  }
  lines.push("");
  lines.push(
    `0 回合（開了場沒成功生成）：${stats.zeroTurnSessions}；超過上限 20：${stats.turnOverflowSessions}。`,
  );
  lines.push("");

  lines.push("## 提示／檢討生成與成本估算");
  lines.push("");
  lines.push(
    "| mode | practiceMode | model | status | fallback | 呼叫數 | 估算成本 |",
  );
  lines.push("| --- | --- | --- | --- | ---: | ---: | ---: |");
  for (const row of stats.generation) {
    lines.push(
      `| ${row.mode} | ${row.practiceMode} | ${row.model} | ${row.status} | ${
        row.fallbackUsed ? "是" : "否"
      } | ${row.calls} | ${row.costUsd === null ? "未估" : usd(row.costUsd)} |`,
    );
  }
  lines.push(
    `| **合計** | | | | | ${stats.generationTotalCalls} | **${
      usd(stats.totalCostUsd)
    }** |`,
  );
  lines.push("");
  lines.push(
    `fallback 呼叫比率 ${
      pct(ratio(stats.generationFallbackCalls, stats.generationTotalCalls))
    }。`,
  );
  if (stats.unpricedCalls > 0) {
    lines.push(
      "其中 " + stats.unpricedCalls +
        " 次呼叫的 model 沒有登記單價（`pricing.ts` 要補），金額欄印「未估」。",
    );
  }
  lines.push(
    `每場提示＋檢討成本：${
      stats.costPerSessionUsd === null
        ? "—（本週沒有場次）"
        : usd(stats.costPerSessionUsd)
    }。`,
  );
  lines.push("");
  lines.push(
    "成本是**估算**：`ai_logs.input_tokens`／`output_tokens` 在寫入端固定是 0，",
  );
  lines.push(
    "所以用「呼叫次數 × 計畫 §2 D14 的單次 token 側寫 × `pricing.ts` 牌價」推。",
  );
  lines.push("");

  lines.push("## 損益");
  lines.push("");
  if (stats.economics === null) {
    lines.push(
      "未提供付費人數（RevenueCat 不在 Supabase）。要算損益請加",
    );
    lines.push("`--payers-starter=N --payers-essential=N`。");
  } else {
    const eco = stats.economics;
    lines.push(
      `Starter ${eco.payers.starter} 人 × ${
        twd(PLAN_MONTHLY_TWD.starter)
      }、Essential ${eco.payers.essential} 人 × ${
        twd(PLAN_MONTHLY_TWD.essential)
      }＝月營收 ${twd(eco.monthlyRevenueTwd)}。`,
    );
    lines.push("");
    lines.push("| 項目 | 金額 |");
    lines.push("| --- | ---: |");
    lines.push(`| 本週提示＋檢討成本 | ${twd(eco.weeklyCostTwd)} |`);
    lines.push(`| 外推月成本（×52/12） | ${twd(eco.monthlyCostTwd)} |`);
    lines.push(`| 月營收 | ${twd(eco.monthlyRevenueTwd)} |`);
    lines.push(`| 成本佔營收 | ${pct(eco.costShareOfRevenue)} |`);
    lines.push("");
    lines.push(
      "付費人數是手填的；成本只含提示與檢討，聊天回合成本不在 DB（見下）。",
    );
  }
  lines.push("");

  if (stats.logs) {
    lines.push(...renderLogs(stats.logs));
    return lines.join("\n");
  }

  lines.push("## 欄位不存在");
  lines.push("");
  lines.push(
    "以下是 Phase 5 計畫 WP1 點名、但 production 沒有寫進任何資料表的欄位。",
  );
  lines.push("要讓它們進週報，得先改 `practice-chat` 的寫入端。");
  lines.push("");
  lines.push("| 欄位 | 為什麼沒有 |");
  lines.push("| --- | --- |");
  for (const field of MISSING_FIELDS) {
    lines.push(`| ${field.field} | ${field.reason} |`);
  }
  lines.push("");

  return lines.join("\n");
}

/**
 * 聊天回合那七個欄位只在 `practice_chat_succeeded` 這個 console 事件裡，
 * 來源是 Edge Function logs。Supabase 的 function logs 保留期通常只有 7 天，
 * 超出保留期會回 0 筆而不是報錯，所以涵蓋範圍是這一段最重要的一行。
 */
function renderLogs(logs: LogStats): string[] {
  const lines: string[] = [];
  lines.push("## 聊天回合（Edge Function logs）");
  lines.push("");
  lines.push(
    `涵蓋範圍：${logs.earliest ?? "—"} ～ ${
      logs.latest ?? "—"
    }，端點回了 ${logs.rowsReturned} 列，`,
  );
  lines.push(
    `其中 ${logs.turns} 列是 \`practice_chat_succeeded\`（跳過：其他事件 ${logs.skippedOtherEvent} 列、無法解析 ${logs.skippedUnparsable} 列）。`,
  );
  if (logs.missingDays.length > 0) {
    lines.push("");
    lines.push(
      `**未取得 ${logs.missingDays.length} 天**（限流退避三次後仍失敗）：${
        logs.missingDays.join("、")
      }。這幾天的輪數不在上面任何一格分母裡。`,
    );
  }
  lines.push("");
  lines.push(
    "**保留期**：Supabase function logs 通常只留 7 天，時間窗超出保留期會回 0 筆",
  );
  lines.push(
    "而不會報錯。上面的涵蓋範圍如果比 `--from`／`--to` 窄，就是被保留期切掉了——",
  );
  lines.push("週報要每 7 天內跑一次。");
  lines.push("");
  lines.push("| 指標 | 分子／分母 | 比率 |");
  lines.push("| --- | ---: | ---: |");
  lines.push(
    `| agency 介入率 | ${logs.agencyApplied}／${logs.agencyTurns} | ${
      pct(logs.agencyAppliedRate)
    } |`,
  );
  lines.push(
    `| \`chatModelFallback\` | ${logs.chatModelFallbackTurns}／${logs.chatModelTurns} | ${
      pct(logs.chatModelFallbackRate)
    } |`,
  );
  lines.push(
    `| \`checkOutStructuralFail\` | ${logs.checkOutStructuralFail}／${logs.agencyTurns} | ${
      pct(logs.checkOutStructuralFailRate)
    } |`,
  );
  lines.push(
    `| \`checkOutRewriteInjected\` × fail | ${logs.checkOutRewriteAndFail}／${logs.checkOutRewriteInjected} | ${
      pct(logs.checkOutRewriteFailRate)
    } |`,
  );
  lines.push(
    `| \`readOnlyReply\` | ${logs.readOnlyReply}／${logs.agencyTurns} | ${
      pct(logs.readOnlyReplyRate)
    } |`,
  );
  lines.push("");
  lines.push(
    "分母刻意不是全部輪數：旗標關著時 `conversationAgency`／`chatModel` 整組 key",
  );
  lines.push("不存在，所以分母是「這一輪真的帶了那個 key」的輪數。");
  lines.push("");
  lines.push("### `chatModel` 分佈");
  lines.push("");
  lines.push("| chatModel | 輪數（最終採用） | 呼叫次數（含守門重試） |");
  lines.push("| --- | ---: | ---: |");
  for (const [model, turns] of Object.entries(logs.chatModelDistribution)) {
    const calls = model === "haiku"
      ? String(logs.chatModelCalls.haiku)
      : model === "deepseek"
      ? String(logs.chatModelCalls.deepseek)
      : "—";
    lines.push(`| ${model} | ${turns} | ${calls} |`);
  }
  lines.push("");
  lines.push("### 聊天成本");
  lines.push("");
  lines.push(
    `Haiku usage 累加：input ${logs.chatModelUsage.inputTokens}、cache read ${logs.chatModelUsage.cacheReadInputTokens}、cache write ${logs.chatModelUsage.cacheCreationInputTokens}、output ${logs.chatModelUsage.outputTokens} tokens。`,
  );
  lines.push(
    `DeepSeek ${logs.chatModelCalls.deepseek} 次 × 每次觀測單價。合計 **${
      usd(logs.chatCostUsd)
    }**（本段是真 usage，不是側寫估算）。`,
  );
  lines.push("");
  return lines;
}
