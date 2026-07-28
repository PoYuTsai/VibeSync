import {
  assert,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  isGroundedKeyboardAssistCompilerOutput,
  isGroundedKeyboardAssistReadyResult,
} from "./grounding.ts";
import type { KeyboardAssistReadyResult } from "./contract.ts";
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
      evidenceIndices: [0],
    }],
  };
}

Deno.test("compiler grounding rejects off-screen factual tokens", () => {
  for (
    const candidate of [
      "那我們明天見",
      "那我們下個月見",
      "下次再一起去",
      "大後天有空嗎？",
      "那就 7 月 27 日見",
      "我可以帶 2 個朋友",
      "我可以帶２個朋友",
      "那就下午三點見",
      "那就 14:30 見",
      "細節在 https://example.com/menu",
      "你可以找 @kevin_chen",
      "我問 Kevin 看看",
      "我問王小明看看",
      "我跟王小明一起去",
      "我和 Alice 聊聊",
      "我約 王小明",
      "上次在台北那家店很好玩",
      "要不要去海底撈火鍋店？",
      "要不要去鼎泰豐？",
      "上次那件事真的很好玩",
      "你說過你很喜歡",
      "我們聊過這件事",
      "還記得那天嗎？",
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
      ["Kevin 也會去", "那我問 Kevin 看看"],
      ["王小明也會去", "我問王小明看看"],
      ["我會跟王小明一起去", "好，我跟王小明一起去"],
      ["我剛和 Alice 聊過", "那我和 Alice 聊聊"],
      ["我現在住台北", "台北我可以"],
      ["想吃海底撈火鍋店", "要不要去海底撈火鍋店？"],
      ["想吃鼎泰豐", "要不要去鼎泰豐？"],
      ["上次那件事很好笑", "上次那件事真的很好玩"],
      ["你說過你喜歡看展", "你說過你很喜歡"],
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

Deno.test("judge explanations cannot add off-screen factual tokens", () => {
  const compiler = compilerWithCandidate("可以啊，你想怎麼安排？");
  const ready = {
    contractVersion: "keyboard-assist-v1",
    status: "ready",
    source: {
      scope: "screenshot_only",
      messageCount: 1,
      confidence: "high",
      sideConfidence: "high",
    },
    turnState: "reply_due",
    cue: compiler.cue,
    uncertainty: null,
    options: [{
      strategy: "extend",
      text: compiler.candidates[0].text,
      why: "先自然接話",
      effect: "保持低壓",
    }],
    // Both batches are served to the user, so both are grounded the same way.
    alternates: [{
      strategy: "extend",
      text: compiler.candidates[0].text,
      why: "先確認再回",
      effect: "減少誤會",
    }],
  } satisfies KeyboardAssistReadyResult;

  assert(
    isGroundedKeyboardAssistReadyResult(
      ready,
      compiler,
      { primary: null, secondary: null },
    ),
  );
  assertFalse(
    isGroundedKeyboardAssistReadyResult(
      {
        ...ready,
        options: [{ ...ready.options[0], why: "承接上次在台北的回憶" }],
      },
      compiler,
      { primary: null, secondary: null },
    ),
  );
  assertFalse(
    isGroundedKeyboardAssistReadyResult(
      {
        ...ready,
        options: [{ ...ready.options[0], effect: "方便明天推進" }],
      },
      compiler,
      { primary: null, secondary: null },
    ),
  );
  assertFalse(
    isGroundedKeyboardAssistReadyResult(
      {
        ...ready,
        alternates: [{ ...ready.alternates[0], why: "承接上次在台北的回憶" }],
      },
      compiler,
      { primary: null, secondary: null },
    ),
    "the second batch is not a lower-standard batch",
  );
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
      { index: 0, side: "right", text: "好 等你回來 姪女 8/11 開學 8/2~8/11 找一天" },
      { index: 1, side: "left", text: "好的 沒問題" },
      { index: 2, side: "right", text: "8/9" },
      { index: 3, side: "left", text: "週日好像不行，週六可以" },
    ],
    candidates: [{
      strategy: "humor",
      text: "那就 8/9 週六吧",
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
      evidenceIndices: [7],
    }],
  };

  assertFalse(isGroundedKeyboardAssistCompilerOutput(value));
});

Deno.test("a one-batch result is checked, not crashed on", () => {
  // "換一批" is optional by contract. Spreading a missing second batch used to
  // throw, so a legitimately degraded result surfaced as a generic 503.
  const compiler = compilerWithCandidate("可以啊，你想怎麼安排？");
  const { alternates: _dropped, ...oneBatch } = {
    contractVersion: "keyboard-assist-v1",
    status: "ready",
    source: {
      scope: "screenshot_only",
      messageCount: 1,
      confidence: "high",
      sideConfidence: "high",
    },
    turnState: "reply_due",
    cue: compiler.cue,
    uncertainty: null,
    options: [{
      strategy: "extend",
      text: compiler.candidates[0].text,
      why: "先自然接話",
      effect: "保持低壓",
    }],
    alternates: [],
  } satisfies KeyboardAssistReadyResult;

  assert(
    isGroundedKeyboardAssistReadyResult(
      oneBatch as KeyboardAssistReadyResult,
      compiler,
      { primary: null, secondary: null },
    ),
  );
});
