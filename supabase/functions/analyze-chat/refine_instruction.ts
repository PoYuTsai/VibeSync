export const MAX_REFINE_INSTRUCTION_LENGTH = 80;

export type RefineInstructionValidation =
  | { kind: "absent" }
  | { kind: "ok"; instruction: string }
  | { kind: "error"; error: string; code: string; message: string };

/// 回覆微調的入口守門。全部在打模型與扣額度之前跑完，任何一種失敗都是 0 扣費。
///
/// 只要 `refineInstruction` 這個鍵存在（不論值是什麼），就代表 client 明確宣告
/// 「這是一次微調」。宣告了卻給空字串必須擋下來，**不得默默降級成一般潤飾**：
/// 靠 payload 形狀推導身分、推導失敗就悄悄換一種行為，正是付費牆那個洞的成因。
export function validateRefineInstruction({
  rawRefineInstruction,
  userDraft,
}: {
  rawRefineInstruction: unknown;
  userDraft: string | undefined;
}): RefineInstructionValidation {
  if (rawRefineInstruction === undefined || rawRefineInstruction === null) {
    return { kind: "absent" };
  }

  if (typeof rawRefineInstruction !== "string") {
    return {
      kind: "error",
      error: "Invalid refineInstruction",
      code: "INVALID_REFINE_INSTRUCTION",
      message: "微調指令格式有誤，請重新送出。本次不會扣額度。",
    };
  }

  const instruction = rawRefineInstruction.trim();
  if (instruction.length === 0) {
    return {
      kind: "error",
      error: "Invalid refineInstruction",
      code: "INVALID_REFINE_INSTRUCTION",
      message: "請先告訴我要往哪個方向調。本次不會扣額度。",
    };
  }

  if (instruction.length > MAX_REFINE_INSTRUCTION_LENGTH) {
    return {
      kind: "error",
      error:
        `refineInstruction too long (max ${MAX_REFINE_INSTRUCTION_LENGTH} chars)`,
      code: "REFINE_INSTRUCTION_TOO_LONG",
      message:
        `微調指令請控制在 ${MAX_REFINE_INSTRUCTION_LENGTH} 字以內。本次不會扣額度。`,
    };
  }

  if (!userDraft || userDraft.trim().length === 0) {
    return {
      kind: "error",
      error: "refineInstruction requires userDraft",
      code: "REFINE_INSTRUCTION_WITHOUT_DRAFT",
      message: "找不到要微調的原句，請重新選一則回覆。本次不會扣額度。",
    };
  }

  return { kind: "ok", instruction };
}
