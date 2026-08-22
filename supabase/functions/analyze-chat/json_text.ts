// 模型輸出的 JSON 文字修復與解析工具：處理截斷、trailing comma、
// code fence 與夾雜說明文字的回覆。所有 mode handler 共用。

import { isPlainObject } from "../_shared/quota.ts";

// JSON 修復函數 - 處理 Claude 有時輸出不完整的 JSON
function repairJson(jsonString: string): string {
  let repaired = jsonString.trim();

  // 移除 trailing commas before } or ]
  repaired = repaired.replace(/,(\s*[}\]])/g, "$1");

  // 計算未閉合的括號
  let braceCount = 0;
  let bracketCount = 0;
  let inString = false;
  let escape = false;

  for (const char of repaired) {
    if (escape) {
      escape = false;
      continue;
    }
    if (char === "\\") {
      escape = true;
      continue;
    }
    if (char === '"') {
      inString = !inString;
      continue;
    }
    if (inString) continue;

    if (char === "{") braceCount++;
    if (char === "}") braceCount--;
    if (char === "[") bracketCount++;
    if (char === "]") bracketCount--;
  }

  // 補上缺少的閉合括號
  while (bracketCount > 0) {
    repaired += "]";
    bracketCount--;
  }
  while (braceCount > 0) {
    repaired += "}";
    braceCount--;
  }

  return repaired;
}

function stripJsonCodeFence(text: string): string {
  const trimmed = text.trim();
  const match = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  return match ? match[1].trim() : trimmed;
}

function extractBalancedJsonObject(text: string): string | null {
  const cleaned = stripJsonCodeFence(text);
  const start = cleaned.indexOf("{");
  if (start < 0) return null;

  let depth = 0;
  let inString = false;
  let escaped = false;

  for (let i = start; i < cleaned.length; i++) {
    const char = cleaned[i];

    if (escaped) {
      escaped = false;
      continue;
    }

    if (char === "\\") {
      escaped = true;
      continue;
    }

    if (char === '"') {
      inString = !inString;
      continue;
    }

    if (inString) continue;

    if (char === "{") {
      depth++;
    } else if (char === "}") {
      depth--;
      if (depth === 0) {
        return cleaned.slice(start, i + 1);
      }
    }
  }

  return null;
}

function parseJsonObjectFromText(text: string): Record<string, unknown> | null {
  const candidates = [
    text.trim(),
    stripJsonCodeFence(text),
    extractBalancedJsonObject(text) ?? "",
  ].filter((candidate, index, self) =>
    candidate.trim().length > 0 && self.indexOf(candidate) === index
  );

  for (const candidate of candidates) {
    const attempts = [candidate, repairJson(candidate)].filter((
      attempt,
      index,
      self,
    ) => attempt.trim().length > 0 && self.indexOf(attempt) === index);

    for (const attempt of attempts) {
      try {
        const parsed = JSON.parse(attempt);
        if (isPlainObject(parsed)) return parsed;
      } catch {
        // Try the next repair/extraction strategy.
      }
    }
  }

  return null;
}

// 主呼叫與 repair 共用同一上限：內容豐富截圖輸出可超過 1800（實測成功案例
// 1566–1597 tokens），repair 上限若低於主呼叫，截斷輸入修完仍超長＝必再截斷。

export {
  extractBalancedJsonObject,
  parseJsonObjectFromText,
  repairJson,
  stripJsonCodeFence,
};
