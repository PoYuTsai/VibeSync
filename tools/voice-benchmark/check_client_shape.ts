// client 形狀檢查：對 baselines/<name>.ndjson 驗 analysis.done.finalResult
// （＋每個 analysis.reply_option 走 REPLY_OPTION 表）有沒有會讓 client fromJson
// 硬 cast throw 的欄位。有 violation 退非零。免費層（forceModel=haiku）最易吐
// 壞型，列入必測錨後用這支當斷言。
//
// 用法： deno run --allow-read check_client_shape.ts <path1.ndjson> [path2 ...]

import {
  type ClientShapeViolation,
  findClientShapeViolations,
  findRecordShapeViolations,
} from "../../supabase/functions/analyze-chat/client_shape_validator.ts";
import { REPLY_OPTION_FIELD_SHAPES } from "../../supabase/functions/analyze-chat/reframer.ts";

function label(path: string): string {
  const parts = path.split("/");
  return parts[parts.length - 1] || path;
}

if (Deno.args.length === 0) {
  console.error(
    "usage: deno run --allow-read check_client_shape.ts <file.ndjson> [more...]",
  );
  Deno.exit(2);
}

let totalViolations = 0;

for (const path of Deno.args) {
  const name = label(path);
  let text: string;
  try {
    text = await Deno.readTextFile(path);
  } catch (error) {
    console.log(`[${name}] READ ERROR — ${(error as Error).message}`);
    totalViolations++;
    continue;
  }

  const lines = text.split("\n").map((l) => l.trim()).filter(Boolean);
  const violations: ClientShapeViolation[] = [];
  let sawDone = false;

  lines.forEach((line, index) => {
    let event: unknown;
    try {
      event = JSON.parse(line);
    } catch {
      console.log(`[${name}:${index + 1}] JSON parse error — 略過該行`);
      return;
    }
    if (typeof event !== "object" || event === null) return;
    const record = event as Record<string, unknown>;

    if (record.type === "analysis.done") {
      sawDone = true;
      violations.push(...findClientShapeViolations(record.finalResult));
    } else if (record.type === "analysis.reply_option") {
      const style = typeof record.style === "string" ? record.style : "?";
      violations.push(
        ...findRecordShapeViolations(
          record,
          REPLY_OPTION_FIELD_SHAPES,
          `reply_option[${style}]`,
        ),
      );
    }
  });

  totalViolations += violations.length;

  if (violations.length === 0) {
    const note = sawDone ? "" : " (⚠️ 無 analysis.done 事件)";
    console.log(`[${name}] PASS${note}`);
  } else {
    console.log(`[${name}] FAIL — ${violations.length} violation(s)`);
    for (const v of violations) {
      console.log(`    ${v.path}: expected ${v.expected}, got ${v.actual}`);
    }
  }
}

Deno.exit(totalViolations > 0 ? 1 : 0);
