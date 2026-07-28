import {
  assert,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  isGroundedKeyboardAssistCompilerOutput,
  UNGATED_RELATIVE_DATE_TOKENS,
} from "./grounding.ts";
import type { NormalizedKeyboardAssistCompilerOutput } from "./normalize.ts";

function compilerWithCandidate(
  candidateText: string,
  messageText = "嗨",
): NormalizedKeyboardAssistCompilerOutput {
  return {
    conversationType: "chat",
    suggestedMySide: "right",
    sideConfidence: "high",
    confidence: "high",
    turnState: "reply_due",
    cue: "對方剛打招呼。",
    uncertainty: null,
    messages: [{ index: 0, side: "left", text: messageText }],
    candidates: [{
      strategy: "extend",
      text: candidateText,
      why: "順著對方的話接",
      effect: "保持自然",
      evidenceIndices: [0],
    }],
  };
}

Deno.test("compiler grounding rejects off-screen factual tokens", () => {
  for (
    const candidate of [
      "那就 7 月 27 日見",
      "那就下午三點見",
      "那就 14:30 見",
      "那就 8 點見",
      "那就 8 點半見",
      "一個人大概 500 元",
      "一個人大概 500 塊",
      "細節在 https://example.com/menu",
      "你可以找 @kevin_chen",
    ]
  ) {
    assertFalse(
      isGroundedKeyboardAssistCompilerOutput(
        compilerWithCandidate(candidate),
      ),
      candidate,
    );
  }
});

Deno.test("a reply may say 明天 without the screenshot saying it first", () => {
  // Suggesting a future is not asserting a fact, and every one of these words
  // was a hard refusal of the whole batch until 2026-07-28. A specific future
  // is still a fact: "下週六" carries 週六 and stays refused below.
  for (const token of UNGATED_RELATIVE_DATE_TOKENS) {
    assert(
      isGroundedKeyboardAssistCompilerOutput(
        compilerWithCandidate(`${token}再一起去`),
      ),
      token,
    );
  }
  assertFalse(
    isGroundedKeyboardAssistCompilerOutput(
      compilerWithCandidate("下週六再一起去"),
    ),
  );
});

Deno.test("compiler grounding accepts the same factual token in cited OCR", () => {
  for (
    const [message, candidate] of [
      ["明天要不要見？", "好啊，那我們明天見"],
      ["下個月要不要見？", "好啊，那我們下個月見"],
      ["下次再一起去", "好，下次再一起去"],
      ["7 月 27 日有空嗎？", "7 月 27 日可以"],
      ["可以帶 2 個朋友", "好，我也會帶 2 個朋友"],
      ["下午三點有空嗎？", "下午三點可以"],
      ["網址是 https://example.com/menu", "我看一下 https://example.com/menu"],
      ["請找 @kevin_chen", "好，我找 @kevin_chen"],
    ]
  ) {
    assert(
      isGroundedKeyboardAssistCompilerOutput(
        compilerWithCandidate(candidate, message),
      ),
      `${message} -> ${candidate}`,
    );
  }
});

Deno.test("separate visible numbers do not authorize an invented compound date", () => {
  assertFalse(
    isGroundedKeyboardAssistCompilerOutput(
      compilerWithCandidate(
        "那就 7 月 27 日見",
        "我有 7 個提案，裡面總共列了 27 個選項",
      ),
    ),
  );
});

Deno.test("a bare count is not a claim the way a price or a clock time is", () => {
  // Refusing every digit refused the whole batch whenever one line wrote
  // "那 4 道菜" instead of "那幾道菜", which is what happened on 2026-07-28.
  // Dates, clock times and money stay gated above; a count does not.
  for (
    const candidate of [
      "我可以帶 2 個朋友",
      "我可以帶２個朋友",
      "那 4 道菜看起來都不錯",
      "先訂 4 個人的位子好了",
    ]
  ) {
    assert(
      isGroundedKeyboardAssistCompilerOutput(
        compilerWithCandidate(candidate),
      ),
      candidate,
    );
  }
});

Deno.test("names, places and shared-past wording are no longer refusals", () => {
  // Gated until 2026-07-28, when the cost became clear: a batch is exactly
  // three replies, so one over-eager whitelist hit takes all three. Naming the
  // wrong restaurant is embarrassing; it does not make anyone act on a false
  // address, account, time or price, which is what the remaining classes cover.
  for (
    const candidate of [
      "我問 Kevin 看看",
      "我問王小明看看",
      "我和 Alice 聊聊",
      "上次在台北那家店很好玩",
      "要不要去海底撈火鍋店？",
      "要不要去鼎泰豐？",
      "上次那件事真的很好玩",
      "你說過你很喜歡",
      "還記得那天嗎？",
    ]
  ) {
    assert(
      isGroundedKeyboardAssistCompilerOutput(
        compilerWithCandidate(candidate),
      ),
      candidate,
    );
  }
});

Deno.test("a Thai screenshot answered in Chinese can still be grounded", () => {
  // Evidence is matched literally against the model's own transcript, so any
  // Chinese rendering of a Thai place or dish could never match. That made a
  // whole class of real screenshots impossible to serve, not merely risky.
  assert(
    isGroundedKeyboardAssistCompilerOutput(
      compilerWithCandidate(
        "那家泰式餐廳看起來不錯，改天一起去",
        "ร้านนี้อร่อยมาก แนะนำให้จองโต๊ะก่อนนะคะ",
      ),
    ),
  );
});

Deno.test("compiler grounding keeps generic natural replies usable", () => {
  for (
    const candidate of [
      "可以啊，你比較想哪一種？",
      "聽起來不錯，我再確認一下",
      "哈哈這個我可以",
      "OK 啊，那你呢？",
      "你是想約白天還是晚上？",
      "要不要去那家店看看？",
      "要不要去咖啡廳坐坐？",
      "要不要找間餐廳吃飯？",
    ]
  ) {
    assert(
      isGroundedKeyboardAssistCompilerOutput(
        compilerWithCandidate(candidate),
      ),
      candidate,
    );
  }
});

Deno.test("a fact agreed earlier in the same screenshot is still grounded", () => {
  // Real conversations spread their facts around: the newest message says
  // "Saturday works", but the date it refers to was agreed three messages
  // earlier. Citing only the message being answered must not make an ordinary
  // reply look invented.
  const value: NormalizedKeyboardAssistCompilerOutput = {
    conversationType: "chat",
    suggestedMySide: "right",
    sideConfidence: "high",
    confidence: "high",
    turnState: "reply_due",
    cue: "對方說週六可以。",
    uncertainty: null,
    messages: [
      {
        index: 0,
        side: "right",
        text: "好 等你回來 姪女 8/11 開學 8/2~8/11 找一天",
      },
      { index: 1, side: "left", text: "好的 沒問題" },
      { index: 2, side: "right", text: "8/9" },
      { index: 3, side: "left", text: "週日好像不行，週六可以" },
    ],
    candidates: [{
      strategy: "humor",
      text: "那就 8/9 週六吧",
      why: "對方說週六可以",
      effect: "把日子定下來",
      evidenceIndices: [3],
    }],
  };

  assert(isGroundedKeyboardAssistCompilerOutput(value));
});

Deno.test("citations still have to point at real messages", () => {
  const value: NormalizedKeyboardAssistCompilerOutput = {
    conversationType: "chat",
    suggestedMySide: "right",
    sideConfidence: "high",
    confidence: "high",
    turnState: "reply_due",
    cue: "對方剛打招呼。",
    uncertainty: null,
    messages: [{ index: 0, side: "left", text: "嗨" }],
    candidates: [{
      strategy: "extend",
      text: "嗨嗨",
      why: "對方剛打招呼",
      effect: "先把話接起來",
      evidenceIndices: [7],
    }],
  };

  assertFalse(isGroundedKeyboardAssistCompilerOutput(value));
});
