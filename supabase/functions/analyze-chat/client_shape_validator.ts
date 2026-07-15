// Read-only 偵測版的 client 形狀守門：reframer.ts 的 coerce/conform 路徑在
// 出貨時把錯型欄位丟掉/取整來救 client；這個模組反過來「只看不改」，回報哪些
// 欄位若沒被守門就會讓 client fromJson 硬 cast throw。除測試基建（黑箱
// baseline、forceModel=haiku 必測錨）外，optimize_message 也在原子扣點前用它
// fail closed，避免扣了額度才發現 App 解析不了結果。
//
// 契約來源＝reframer.ts 匯出的 client 形狀表（client analysis_models.dart /
// analysis_result.dart 的 fromJson 硬 cast 的 server 端轉錄）。
//
// 鐵律：undefined 與 null 一律放行——client 欄位是 nullable cast（as Map? /
// as String? / as int?），只有「present 且非 null 且型別錯」才算 violation。
// 例外：recordArray／stringArray 的「元素」走非 nullable cast（client
// `(list).map((m) => fromJson(m as Map))`、`List<String>.from`），null/錯型
// 元素一樣 throw，所以元素層不放行 null。

import {
  ARRAY_ONLY_FINAL_RESULT_KEYS,
  CLIENT_RECORD_FIELD_SHAPES,
  type ClientFieldShape,
  REPLY_OPTION_FIELD_SHAPES,
  STRING_ONLY_FINAL_RESULT_KEYS,
} from "./reframer.ts";

export interface ClientShapeViolation {
  path: string; // 例 "enthusiasm.score"、"recognizedConversation.messages[0]"
  expected: string; // 期望形狀（client 硬 cast 的型別）
  actual: string; // 實際遇到的 JSON 型別
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function describe(value: unknown): string {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  return typeof value;
}

function collectShapeViolations(
  path: string,
  shape: ClientFieldShape,
  value: unknown,
  out: ClientShapeViolation[],
): void {
  if (typeof shape === "object") {
    if ("recordArray" in shape) {
      if (!Array.isArray(value)) {
        out.push({ path, expected: "recordArray", actual: describe(value) });
        return;
      }
      value.forEach((element, index) => {
        const elementPath = `${path}[${index}]`;
        // client `.map((m) => fromJson(m as Map))`——元素非 record 必 throw。
        if (!isRecord(element)) {
          out.push({
            path: elementPath,
            expected: "record",
            actual: describe(element),
          });
          return;
        }
        collectRecordViolations(element, shape.recordArray, elementPath, out);
      });
      return;
    }
    if (!isRecord(value)) {
      out.push({ path, expected: "record", actual: describe(value) });
      return;
    }
    collectRecordViolations(value, shape.record, path, out);
    return;
  }

  switch (shape) {
    case "string":
      if (typeof value !== "string") {
        out.push({ path, expected: "string", actual: describe(value) });
      }
      return;
    case "boolean":
      if (typeof value !== "boolean") {
        out.push({ path, expected: "boolean", actual: describe(value) });
      }
      return;
    case "int":
      // client as int?——float 與字串都 throw。
      if (!(typeof value === "number" && Number.isInteger(value))) {
        out.push({ path, expected: "int", actual: describe(value) });
      }
      return;
    case "number":
      if (!(typeof value === "number" && Number.isFinite(value))) {
        out.push({ path, expected: "number", actual: describe(value) });
      }
      return;
    case "stringArray":
      if (!Array.isArray(value)) {
        out.push({ path, expected: "stringArray", actual: describe(value) });
        return;
      }
      // client List<String>.from——混型元素 throw。
      value.forEach((element, index) => {
        if (typeof element !== "string") {
          out.push({
            path: `${path}[${index}]`,
            expected: "string",
            actual: describe(element),
          });
        }
      });
      return;
  }
}

function collectRecordViolations(
  record: Record<string, unknown>,
  shapes: Record<string, ClientFieldShape>,
  basePath: string,
  out: ClientShapeViolation[],
): void {
  for (const [field, shape] of Object.entries(shapes)) {
    if (!(field in record)) continue;
    const value = record[field];
    if (value === null || value === undefined) continue; // nullable 欄位放行
    const path = basePath ? `${basePath}.${field}` : field;
    collectShapeViolations(path, shape, value, out);
  }
}

/**
 * 對任意 record 套一張欄位形狀表查違規（reply_option 走 REPLY_OPTION 表時用）。
 * 非 record 輸入回 []（client 對非 Map 寬容或上游已過濾）。
 */
export function findRecordShapeViolations(
  record: unknown,
  shapes: Record<string, ClientFieldShape>,
  basePath = "",
): ClientShapeViolation[] {
  const out: ClientShapeViolation[] = [];
  if (!isRecord(record)) return out;
  collectRecordViolations(record, shapes, basePath, out);
  return out;
}

/**
 * 查 analysis.done 的 finalResult 整包對 client 硬 cast 契約的違規。
 * 涵蓋 record 表、array-only key（warnings）、string-only key（strategy/
 * reminder）、dynamic replies（Map<String,String>）、dynamic replyOptions
 * （每個 record value 走 REPLY_OPTION 表、非 record value 放行）。
 */
export function findClientShapeViolations(
  finalResult: unknown,
): ClientShapeViolation[] {
  const out: ClientShapeViolation[] = [];
  if (!isRecord(finalResult)) return out;

  for (const [key, value] of Object.entries(finalResult)) {
    if (value === null || value === undefined) continue; // nullable 放行

    if (ARRAY_ONLY_FINAL_RESULT_KEYS.has(key)) {
      collectShapeViolations(key, "stringArray", value, out);
      continue;
    }
    if (STRING_ONLY_FINAL_RESULT_KEYS.has(key)) {
      collectShapeViolations(key, "string", value, out);
      continue;
    }
    if (key === "replies") {
      // legacy client Map<String, String>.from——非 record 整包 throw，
      // record value 必須是字串。
      if (!isRecord(value)) {
        out.push({ path: "replies", expected: "record", actual: describe(value) });
        continue;
      }
      for (const [style, reply] of Object.entries(value)) {
        if (reply === null || reply === undefined) continue;
        if (typeof reply !== "string") {
          out.push({
            path: `replies.${style}`,
            expected: "string",
            actual: describe(reply),
          });
        }
      }
      continue;
    }
    if (key === "replyOptions") {
      if (!isRecord(value)) {
        out.push({
          path: "replyOptions",
          expected: "record",
          actual: describe(value),
        });
        continue;
      }
      for (const [style, option] of Object.entries(value)) {
        // client ReplyOption.fromJson 對非 Map value 寬容（reframer 同樣
        // `if (!isRecord(option)) continue`）。
        if (!isRecord(option)) continue;
        collectRecordViolations(
          option,
          REPLY_OPTION_FIELD_SHAPES,
          `replyOptions.${style}`,
          out,
        );
      }
      continue;
    }

    const shapes = CLIENT_RECORD_FIELD_SHAPES[key];
    if (!shapes) continue; // 表外欄位原樣放行
    collectShapeViolations(key, { record: shapes }, value, out);
  }

  return out;
}
