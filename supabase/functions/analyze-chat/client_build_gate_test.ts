// 最低 App 版本閘門（client_build_gate.ts）：純函式的開關與判斷，以及接進
// handler 之後的位置——擋下時不查訂閱、不動額度、不呼叫模型；只擋對話分析的
// 新分析，開場救星、新話題等其他入口在閘門打開、沒帶 clientBuild 時照樣放行。

import {
  assert,
  assertEquals,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  APP_UPDATE_REQUIRED_CODE,
  APP_UPDATE_REQUIRED_MESSAGE,
  checkClientBuildGate,
  parseClientBuild,
  parseMinClientBuild,
} from "./client_build_gate.ts";
import { createAnalyzeChatHandler } from "./index.ts";

const ENV_KEY = "MIN_CLIENT_BUILD";

Deno.test("parseMinClientBuild：沒設、空白、打錯都當關閉", () => {
  for (
    const raw of [
      undefined,
      "",
      "   ",
      "abc",
      "0",
      "-5",
      "12a",
      "1.5",
      "1e3",
      "99999999999999999999",
    ]
  ) {
    assertEquals(parseMinClientBuild(raw), null, `raw=${raw}`);
  }
  assertEquals(parseMinClientBuild("340"), 340);
  assertEquals(parseMinClientBuild(" 340 "), 340);
});

Deno.test("parseClientBuild：只認正整數的 JSON number，其他都當沒送", () => {
  assertEquals(parseClientBuild(340), 340);
  for (
    const raw of [
      "340",
      0,
      -1,
      1.5,
      Number.NaN,
      Number.POSITIVE_INFINITY,
      null,
      undefined,
      true,
      {},
    ]
  ) {
    assertEquals(parseClientBuild(raw), null, `raw=${String(raw)}`);
  }
});

Deno.test("checkClientBuildGate：開關沒設或打錯時完全不看 clientBuild", () => {
  for (const env of [undefined, "", "abc", "0"]) {
    for (const clientBuild of [undefined, 1, "junk"]) {
      const result = checkClientBuildGate({
        minClientBuild: env,
        clientBuild,
        isNewChatAnalysis: true,
        streaming: true,
      });
      assertFalse(result.blocked, `env=${env} clientBuild=${clientBuild}`);
    }
  }
});

Deno.test("checkClientBuildGate：不是對話分析的新分析，一律放行", () => {
  for (const streaming of [true, false]) {
    const result = checkClientBuildGate({
      minClientBuild: "999999",
      clientBuild: undefined,
      isNewChatAnalysis: false,
      streaming,
    });
    assertFalse(result.blocked);
  }
});

Deno.test("checkClientBuildGate：build 號等於或高於門檻就放行", () => {
  for (const clientBuild of [340, 341, 100000]) {
    const result = checkClientBuildGate({
      minClientBuild: "340",
      clientBuild,
      isNewChatAnalysis: true,
      streaming: true,
    });
    assertFalse(result.blocked, `clientBuild=${clientBuild}`);
  }
});

Deno.test("checkClientBuildGate：有帶但太舊 → 426 JSON，說明不扣額度", async () => {
  // 串流與否都一樣：有帶 clientBuild 的 App 認得 426。
  for (const streaming of [true, false]) {
    const result = checkClientBuildGate({
      minClientBuild: "340",
      clientBuild: 339,
      isNewChatAnalysis: true,
      streaming,
    });
    assert(result.blocked);
    assertEquals(result.minClientBuild, 340);
    assertEquals(result.clientBuild, 339);
    assertEquals(result.response.status, 426);
    assertEquals(
      result.response.headers.get("access-control-allow-origin"),
      "*",
    );
    assertEquals(await result.response.json(), {
      error: APP_UPDATE_REQUIRED_MESSAGE,
      code: APP_UPDATE_REQUIRED_CODE,
      message: APP_UPDATE_REQUIRED_MESSAGE,
      shouldChargeQuota: false,
    });
  }
});

Deno.test("checkClientBuildGate：沒帶＋串流 → 200 NDJSON 只有一則 analysis.error", async () => {
  const result = checkClientBuildGate({
    minClientBuild: "340",
    clientBuild: undefined,
    isNewChatAnalysis: true,
    streaming: true,
  });
  assert(result.blocked);
  assertEquals(result.clientBuild, null);
  assertEquals(result.response.status, 200);
  assertEquals(
    result.response.headers.get("content-type"),
    "application/x-ndjson; charset=utf-8",
  );
  assertEquals(
    result.response.headers.get("access-control-allow-origin"),
    "*",
  );
  const lines = (await result.response.text()).split("\n").filter(Boolean);
  assertEquals(lines.length, 1);
  // 舊版只顯示含中文的 message；recoverable:false 不讓它當成可接續的 run。
  assertEquals(JSON.parse(lines[0]), {
    type: "analysis.error",
    code: APP_UPDATE_REQUIRED_CODE,
    message: APP_UPDATE_REQUIRED_MESSAGE,
    recoverable: false,
    retriesRemaining: 0,
  });
});

Deno.test("checkClientBuildGate：沒帶＋非串流 → 426；亂填的 clientBuild 當沒帶", async () => {
  const nonStream = checkClientBuildGate({
    minClientBuild: "340",
    clientBuild: undefined,
    isNewChatAnalysis: true,
    streaming: false,
  });
  assert(nonStream.blocked);
  assertEquals(nonStream.response.status, 426);
  assertEquals(
    (await nonStream.response.json()).code,
    APP_UPDATE_REQUIRED_CODE,
  );

  const junk = checkClientBuildGate({
    minClientBuild: "340",
    clientBuild: "999",
    isNewChatAnalysis: true,
    streaming: true,
  });
  assert(junk.blocked);
  assertEquals(junk.clientBuild, null);
  assertEquals(junk.response.status, 200);
  await junk.response.body?.cancel();
});

// ── 接進 handler 之後 ──────────────────────────────────────────────────

interface Calls {
  tables: string[];
  rpc: number;
  fetch: number;
}

/// 第一次查資料表（訂閱）就丟錯停下：查到＝已經通過閘門。
function fakeSupabase(calls: Calls) {
  return {
    auth: {
      getUser: (_token: string) =>
        Promise.resolve({
          data: {
            user: {
              id: "00000000-0000-4000-8000-000000000002",
              email: "user@example.com",
            },
          },
          error: null,
        }),
    },
    from: (table: string) => {
      calls.tables.push(table);
      throw new Error("client build gate test stops at the first DB read");
    },
    rpc: (_fn: string) => {
      calls.rpc += 1;
      throw new Error("client build gate test must not call RPCs");
    },
    // deno-lint-ignore no-explicit-any
  } as any;
}

async function runHandler(
  body: Record<string, unknown>,
  minClientBuild: string | undefined,
): Promise<{ response: Response; calls: Calls }> {
  const calls: Calls = { tables: [], rpc: 0, fetch: 0 };
  const handler = createAnalyzeChatHandler({
    createSupabaseClient: () => fakeSupabase(calls),
  });
  const originalFetch = globalThis.fetch;
  const originalEnv = Deno.env.get(ENV_KEY);
  globalThis.fetch = () => {
    calls.fetch += 1;
    throw new Error("client build gate test must not call any provider");
  };
  if (minClientBuild === undefined) {
    Deno.env.delete(ENV_KEY);
  } else {
    Deno.env.set(ENV_KEY, minClientBuild);
  }
  try {
    const response = await handler(
      new Request("http://localhost/analyze-chat", {
        method: "POST",
        headers: {
          Authorization: "Bearer fake-token",
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      }),
    );
    return { response, calls };
  } finally {
    globalThis.fetch = originalFetch;
    if (originalEnv === undefined) {
      Deno.env.delete(ENV_KEY);
    } else {
      Deno.env.set(ENV_KEY, originalEnv);
    }
  }
}

const MESSAGES = [{ content: "今天好累喔", isFromMe: false }];

/// 現行 App 的對話分析請求（串流、協定版本 3）。
function chatAnalysis(extra: Record<string, unknown> = {}) {
  return {
    responseMode: "stream",
    messages: MESSAGES,
    billingProtocolVersion: 3,
    analysisContractVersion: 3,
    ...extra,
  };
}

function assertPassedGate(
  result: { response: Response; calls: Calls },
  label: string,
) {
  assertEquals(result.calls.tables[0], "subscriptions", `${label}: 查訂閱`);
  assert(result.response.status !== 426, `${label}: 不是 426`);
  assertFalse(
    (result.response.headers.get("content-type") ?? "").includes("ndjson"),
    `${label}: 不是閘門的串流錯誤`,
  );
}

function assertZeroCost(calls: Calls, label: string) {
  assertEquals(calls.tables, [], `${label}: 不得查訂閱`);
  assertEquals(calls.rpc, 0, `${label}: 不得動額度`);
  assertEquals(calls.fetch, 0, `${label}: 不得呼叫模型`);
}

Deno.test("handler：閘門打開，太舊的 build → 426，沒查訂閱、沒動額度、沒呼叫模型", async () => {
  const { response, calls } = await runHandler(
    chatAnalysis({ clientBuild: 339 }),
    "340",
  );
  assertEquals(response.status, 426);
  const payload = await response.json();
  assertEquals(payload.code, APP_UPDATE_REQUIRED_CODE);
  assertEquals(payload.shouldChargeQuota, false);
  assertZeroCost(calls, "太舊");
});

Deno.test("handler：閘門打開，舊版沒帶 clientBuild → 一則串流錯誤，同樣零成本", async () => {
  const { response, calls } = await runHandler(chatAnalysis(), "340");
  assertEquals(response.status, 200);
  assertEquals(
    response.headers.get("content-type"),
    "application/x-ndjson; charset=utf-8",
  );
  const lines = (await response.text()).split("\n").filter(Boolean);
  assertEquals(lines.length, 1);
  const event = JSON.parse(lines[0]);
  assertEquals(event.type, "analysis.error");
  assertEquals(event.code, APP_UPDATE_REQUIRED_CODE);
  assertEquals(event.message, APP_UPDATE_REQUIRED_MESSAGE);
  assertZeroCost(calls, "沒帶");
});

Deno.test("handler：build 號等於、高於門檻就照常往下走", async () => {
  for (const clientBuild of [340, 341]) {
    assertPassedGate(
      await runHandler(chatAnalysis({ clientBuild }), "340"),
      `clientBuild=${clientBuild}`,
    );
  }
});

Deno.test("handler：閘門關閉（沒設、空字串、打錯）時，沒帶或亂填 clientBuild 都照常往下走", async () => {
  for (const env of [undefined, "", "abc", "0"]) {
    for (const clientBuild of [undefined, "junk", 1]) {
      assertPassedGate(
        await runHandler(chatAnalysis({ clientBuild }), env),
        `env=${env} clientBuild=${clientBuild}`,
      );
    }
  }
});

Deno.test("handler：閘門打開也不擋開場救星、兩段式開場、新話題、潤飾、微調、我說、截圖辨識、續看", async () => {
  const cases: Array<[label: string, body: Record<string, unknown>]> = [
    ["開場救星", { mode: "opener", images: ["ZmFrZQ=="] }],
    ["開場救星（串流）", {
      mode: "opener",
      responseMode: "stream",
      images: ["ZmFrZQ=="],
    }],
    ["兩段式開場：分析", { mode: "opener_analyze" }],
    ["兩段式開場：生成", { mode: "opener_generate" }],
    ["新話題", { mode: "new_topic" }],
    ["新話題（串流）", { mode: "new_topic", responseMode: "stream" }],
    ["草稿潤飾", { messages: MESSAGES, userDraft: "週末要不要去看展" }],
    ["回覆微調", {
      messages: MESSAGES,
      userDraft: "週末要不要去看展",
      refineInstruction: "再自然一點",
    }],
    ["我說", { analyzeMode: "my_message", messages: MESSAGES }],
    ["截圖辨識", { recognizeOnly: true, images: ["ZmFrZQ=="] }],
    // 已扣費的 run 接續，擋了等於拿不到付過的結果。
    ["續看", chatAnalysis({ analysisRunId: "run-already-charged" })],
    // 舊的草稿＋截圖分析形狀（現行 App 不送），不在範圍內。
    ["草稿＋截圖（舊形狀）", {
      messages: MESSAGES,
      userDraft: "週末要不要去看展",
      images: ["ZmFrZQ=="],
    }],
  ];
  for (const [label, body] of cases) {
    assertPassedGate(await runHandler(body, "999999"), label);
  }
});

Deno.test("handler：閘門在合約版本解析之後——合約版本不合法仍回原本的 400", async () => {
  const { response, calls } = await runHandler(
    chatAnalysis({ analysisContractVersion: 99 }),
    "340",
  );
  assertEquals(response.status, 400);
  assertEquals(await response.json(), {
    error: "Invalid analysisContractVersion",
  });
  assertZeroCost(calls, "合約版本不合法");
});

Deno.test("原始碼：閘門在合約版本解析之後、第一次查訂閱之前；handler 只在閘門裡讀 clientBuild", async () => {
  const source = await Deno.readTextFile(
    new URL("./analyze_chat_handler.ts", import.meta.url),
  );
  const contractParse = source.indexOf(
    "const contractParse = parseAnalysisContractVersion(",
  );
  const gateStart = source.indexOf(
    "const clientBuildGate = checkClientBuildGate(",
  );
  const gateReturn = "return clientBuildGate.response;";
  const gateEnd = source.indexOf(gateReturn) + gateReturn.length;
  const subscriptionLookup = source.indexOf("await loadSubscriptionAccess(");
  assert(contractParse > 0, "合約版本解析要在");
  assert(gateStart > contractParse, "閘門在合約版本解析之後");
  assert(gateEnd > gateStart + gateReturn.length);
  assert(subscriptionLookup > gateEnd, "閘門在第一次查訂閱之前");
  assertEquals(
    source.indexOf("const clientBuildGate = checkClientBuildGate(", gateEnd),
    -1,
    "只有一個閘門",
  );
  // clientBuild 只在閘門裡被讀：不進任何雜湊、計費或 prompt 輸入。
  for (const match of source.matchAll(/clientBuild/g)) {
    const at = match.index ?? -1;
    assert(
      at >= gateStart && at <= gateEnd,
      `clientBuild 出現在閘門以外（offset ${at}）`,
    );
  }
});
