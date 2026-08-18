// supabase/functions/analyze-chat/opener_stream.ts
//
// Opener / new_topic NDJSON 串流的純函式層（2026-08-18 呈現精修第 2 包）。
//
// 設計邊界（拍板）：模型輸出契約不變（單一 JSON object）。串流只做兩件事——
// 1. 傳輸層改 NDJSON 逐塊接收；
// 2. 掃描累積中的原始文字，偵測頂層欄位 marker，發「誠實進度」事件。
// 生成內容在共用的解析／repair／completeness／tier 投影／扣費管線全部通過之前
// **一個字都不外流**（結果只隨 *.done 事件出去）。這保住「驗證全過才扣費、
// 失敗一律不扣」的既有計費語義：中斷者拿不到任何內容，也就沒有免扣費蹭
// 生成的空間（analysis 串流為了逐塊外流內容才需要 anchor 扣費＋run store，
// opener/new_topic v1 刻意不做）。

export interface StreamStageSpec {
  /// 在模型原始輸出中出現即代表進入該階段的子字串（含引號的 JSON key）。
  marker: string;
  phase: string;
  label: string | ((occurrence: number) => string);
  detail?: string;
  /// marker 可重複出現的次數（例如五題各有一個 "direction"）。預設 1。
  repeat?: number;
}

// 五種風格各給獨立 phase（style_<type>）：client 骨架卡靠 phase 點亮，
// label 只是顯示文字、不當 contract 用。
export const OPENER_STREAM_STAGES: StreamStageSpec[] = [
  { marker: '"profileAnalysis"', phase: "profile", label: "解讀對方資料" },
  { marker: '"openers"', phase: "openers", label: "開始寫五種風格開場白" },
  { marker: '"extend"', phase: "style_extend", label: "開場白 1/5：延展" },
  { marker: '"resonate"', phase: "style_resonate", label: "開場白 2/5：共鳴" },
  { marker: '"tease"', phase: "style_tease", label: "開場白 3/5：調情" },
  { marker: '"humor"', phase: "style_humor", label: "開場白 4/5：幽默" },
  { marker: '"coldRead"', phase: "style_coldRead", label: "開場白 5/5：冷讀" },
  { marker: '"pioneerPlan"', phase: "pioneer", label: "準備先鋒備案" },
  { marker: '"recommendation"', phase: "recommendation", label: "挑選最適推薦" },
  { marker: '"formulaOpeners"', phase: "formula", label: "寫公式開場" },
];

export const NEW_TOPIC_STREAM_STAGES: StreamStageSpec[] = [
  { marker: '"topics"', phase: "topics", label: "開始寫五個新話題" },
  {
    marker: '"direction"',
    phase: "topic",
    label: (n) => `新話題 ${n}/5`,
    repeat: 5,
  },
  { marker: '"recommendation"', phase: "recommendation", label: "挑選最適推薦" },
  { marker: '"formulaTopics"', phase: "formula", label: "寫公式新話題" },
];

export interface StreamStageTracker {
  push: (chunk: string) => void;
}

/// 掃描模型原始輸出、每個 stage 首見（或第 n 次見，repeat 用）時各發一次
/// 進度事件。marker 可能被 chunk 切半，所以掃的是完整累積 buffer。
// ponytail: 每次 push 全 buffer indexOf 掃描，O(n·chunks)；opener 輸出
// ≤ ~12KB，量級無感。真的變慢再改成記錄各 marker 掃描起點。
export function createStreamStageTracker(options: {
  stages: StreamStageSpec[];
  eventType: string;
  emit: (event: Record<string, unknown>) => void;
}): StreamStageTracker {
  let buffer = "";
  const seenCounts = new Map<StreamStageSpec, number>();

  const occurrenceIndex = (marker: string, occurrence: number): number => {
    let from = 0;
    for (let i = 0; i < occurrence; i++) {
      const idx = buffer.indexOf(marker, from);
      if (idx < 0) return -1;
      from = idx + marker.length;
    }
    return from;
  };

  return {
    push(chunk: string) {
      if (!chunk) return;
      buffer += chunk;
      for (const stage of options.stages) {
        const max = stage.repeat ?? 1;
        let count = seenCounts.get(stage) ?? 0;
        while (count < max && occurrenceIndex(stage.marker, count + 1) >= 0) {
          count += 1;
          seenCounts.set(stage, count);
          const label = typeof stage.label === "function"
            ? stage.label(count)
            : stage.label;
          options.emit({
            type: options.eventType,
            phase: max > 1 ? `${stage.phase}_${count}` : stage.phase,
            label,
            ...(stage.detail ? { detail: stage.detail } : {}),
          });
        }
      }
    },
  };
}

/// 把既有 handler 邏輯回傳的 JSON Response 轉成串流終局事件：
/// 200 → `${prefix}.done`（result＝整包 body，形狀與 legacy 回應相同）；
/// 其他 → `${prefix}.error`（status＋原 body 欄位攤平，client 可沿用
/// 既有錯誤碼對映）。body 解析失敗不炸串流，發空 body 的 error。
export async function emitJsonResponseAsStreamOutcome(
  response: Response,
  emit: (event: Record<string, unknown>) => void,
  prefix: string,
): Promise<void> {
  let body: Record<string, unknown> = {};
  try {
    const parsed = await response.json();
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      body = parsed as Record<string, unknown>;
    }
  } catch (_error) {
    // 保底：body 留空物件，client 依 status 走 generic 錯誤。
  }
  if (response.status === 200) {
    emit({ result: body, type: `${prefix}.done` });
  } else {
    emit({ ...body, type: `${prefix}.error`, status: response.status });
  }
}
