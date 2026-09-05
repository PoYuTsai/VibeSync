// 統計物件 → markdown。純函式，不打網路、不讀檔。

import { MISSING_FIELDS, PLAN_MONTHLY_TWD, type Stats } from "./aggregate.ts";

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
    }；無單價未估的呼叫 ${stats.unpricedCalls} 次（DeepSeek 生成沒有可信的 token 牌價常數）。`,
  );
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
