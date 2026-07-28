import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  MAX_REFINE_INSTRUCTION_LENGTH,
  validateRefineInstruction,
} from "./refine_instruction.ts";

const draft = "今天天氣不錯，要不要一起去走走？";

Deno.test("refine 驗證：沒有帶欄位就不是微調請求", () => {
  for (const rawRefineInstruction of [undefined, null]) {
    assertEquals(
      validateRefineInstruction({ rawRefineInstruction, userDraft: draft }),
      { kind: "absent" },
    );
  }
});

Deno.test("refine 驗證：合法指令回傳 trim 過的字串", () => {
  assertEquals(
    validateRefineInstruction({
      rawRefineInstruction: "  短一點  ",
      userDraft: draft,
    }),
    { kind: "ok", instruction: "短一點" },
  );
});

Deno.test("refine 驗證：型別不是字串一律 400", () => {
  for (const rawRefineInstruction of [42, true, {}, [], { text: "短一點" }]) {
    const result = validateRefineInstruction({
      rawRefineInstruction,
      userDraft: draft,
    });
    assert(result.kind === "error");
    assertEquals(result.error, "Invalid refineInstruction");
    assertEquals(result.code, "INVALID_REFINE_INSTRUCTION");
  }
});

Deno.test("refine 驗證：宣告了微調卻給空字串必須 400，不得默默降級成潤飾", () => {
  for (const rawRefineInstruction of ["", "   ", "\n\t "]) {
    const result = validateRefineInstruction({
      rawRefineInstruction,
      userDraft: draft,
    });
    assert(
      result.kind === "error",
      `空白指令 ${JSON.stringify(rawRefineInstruction)} 不得被視為一般潤飾`,
    );
    assertEquals(result.code, "INVALID_REFINE_INSTRUCTION");
  }
});

Deno.test("refine 驗證：超過 80 字 400，邊界值 80 放行", () => {
  const exactly80 = "調".repeat(MAX_REFINE_INSTRUCTION_LENGTH);
  assertEquals(
    validateRefineInstruction({
      rawRefineInstruction: exactly80,
      userDraft: draft,
    }),
    { kind: "ok", instruction: exactly80 },
  );

  const tooLong = "調".repeat(MAX_REFINE_INSTRUCTION_LENGTH + 1);
  const result = validateRefineInstruction({
    rawRefineInstruction: tooLong,
    userDraft: draft,
  });
  assert(result.kind === "error");
  assertEquals(result.code, "REFINE_INSTRUCTION_TOO_LONG");

  // 長度以 trim 後計算：前後空白不該把使用者擋在門外。
  assertEquals(
    validateRefineInstruction({
      rawRefineInstruction: `   ${exactly80}   `,
      userDraft: draft,
    }),
    { kind: "ok", instruction: exactly80 },
  );
});

Deno.test("refine 驗證：沒有草稿就沒有東西可以調", () => {
  for (const userDraft of [undefined, "", "   "]) {
    const result = validateRefineInstruction({
      rawRefineInstruction: "短一點",
      userDraft,
    });
    assert(result.kind === "error", `userDraft=${JSON.stringify(userDraft)}`);
    assertEquals(result.code, "REFINE_INSTRUCTION_WITHOUT_DRAFT");
  }
});

Deno.test("refine 驗證：上限就是 80", () => {
  assertEquals(MAX_REFINE_INSTRUCTION_LENGTH, 80);
});
