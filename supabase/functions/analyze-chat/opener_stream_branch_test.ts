// opener / new_topic 串流分支的 source-scan 守門（index.ts import 即起
// server，無法行為測試；同 stream_branch_test.ts 慣例）。
//
// 守的核心語義（2026-08-18 拍板）：串流是 transport-only——
// 扣費／settle 只存在於共用的 complete*Request 內，stream 分支本體
// 不得出現任何扣費呼叫；flag off 時 stream 靜默降級 legacy。
import {
  assert,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

async function readIndexSource(): Promise<string> {
  return await Deno.readTextFile(new URL("./index.ts", import.meta.url));
}

function sliceBetween(source: string, startNeedle: string, endNeedle: string) {
  const start = source.indexOf(startNeedle);
  assert(start >= 0, `找不到起點：${startNeedle}`);
  const end = source.indexOf(endNeedle, start);
  assert(end > start, `找不到終點：${endNeedle}`);
  return source.slice(start, end);
}

Deno.test("opener stream：flag 閘門＋fall back to legacy 存在", async () => {
  const source = await readIndexSource();
  assert(
    source.includes(
      'const openerStreamRequested = responseMode === "stream" &&\n' +
        '        Deno.env.get("OPENER_STREAM_ENABLED") === "true";',
    ),
    "opener stream 必須被 OPENER_STREAM_ENABLED flag 閘住",
  );
  assert(
    source.includes('logInfo("opener_stream_fell_back_to_legacy"'),
    "flag off 的 stream 請求必須留 fallback telemetry（不 400）",
  );
});

Deno.test("opener stream 分支本體不含扣費；扣費只在 completeOpenerRequest 內", async () => {
  const source = await readIndexSource();
  const streamBranch = sliceBetween(
    source,
    "if (openerStreamRequested) {",
    "let apiResult: FallbackResult;",
  );
  assertFalse(
    streamBranch.includes("chargeOpenerQuota"),
    "stream 分支不得自帶扣費——必須經 completeOpenerRequest 共用管線",
  );
  assert(
    streamBranch.includes("await completeOpenerRequest("),
    "stream 分支必須走 completeOpenerRequest",
  );
  assert(
    streamBranch.includes("emitJsonResponseAsStreamOutcome"),
    "終局必須用共用 outcome 轉換（done/error 事件）",
  );
  // 共用管線內恰好一處扣費呼叫。
  const chargeCalls =
    source.match(/const chargeOutcome = await chargeOpenerQuota\(\{/g) ?? [];
  assert(chargeCalls.length === 1, "chargeOpenerQuota 呼叫必須恰好一處");
});

Deno.test("new_topic stream：quick/full 照舊 400、stream 放行且被 flag 閘住", async () => {
  const source = await readIndexSource();
  assert(
    source.includes(
      'if (responseMode !== "legacy" && responseMode !== "stream") {',
    ),
    "new_topic 只放行 legacy 與 stream；quick/full 仍 400",
  );
  assert(
    source.includes(
      'const newTopicStreamRequested = responseMode === "stream" &&\n' +
        '        Deno.env.get("OPENER_STREAM_ENABLED") === "true";',
    ),
    "new_topic stream 必須被同一個 OPENER_STREAM_ENABLED flag 閘住",
  );
  assert(
    source.includes('logInfo("new_topic_stream_fell_back_to_legacy"'),
    "flag off 的 stream 請求必須留 fallback telemetry",
  );
});

Deno.test("new_topic stream 分支本體不含 settle；錯誤路徑必 release claim", async () => {
  const source = await readIndexSource();
  const streamBranch = sliceBetween(
    source,
    "if (newTopicStreamRequested) {",
    "let newTopicApiResult: FallbackResult;",
  );
  assertFalse(
    streamBranch.includes("settleNewTopicRequest"),
    "stream 分支不得自帶 settle——必須經 completeNewTopicRequest 共用管線",
  );
  assert(
    streamBranch.includes("await completeNewTopicRequest("),
    "stream 分支必須走 completeNewTopicRequest",
  );
  assert(
    streamBranch.includes("rejectNewTopicDeadline(") &&
      streamBranch.includes('"primary_or_fallback"'),
    "deadline 必須沿用 owner-bound release 的既有 helper",
  );
  assert(
    streamBranch.includes("releaseNewTopicCurrentClaim()"),
    "provider 失敗必須 release claim（與 legacy catch 同語義）",
  );
});

Deno.test("stream 分支：complete*Request 在 provider catch 之外（R2 round-2 修正）", async () => {
  const source = await readIndexSource();
  for (
    const [startNeedle, endNeedle, completeCall] of [
      [
        "if (openerStreamRequested) {",
        "let apiResult: FallbackResult;",
        "await completeOpenerRequest(",
      ],
      [
        "if (newTopicStreamRequested) {",
        "let newTopicApiResult: FallbackResult;",
        "await completeNewTopicRequest(",
      ],
    ]
  ) {
    const branch = sliceBetween(source, startNeedle, endNeedle);
    const catchIdx = branch.indexOf("catch (streamError)");
    const completeIdx = branch.indexOf(completeCall);
    assert(catchIdx >= 0, "stream 分支必須有 provider catch");
    assert(completeIdx >= 0, "stream 分支必須呼叫 complete*Request");
    assert(
      completeIdx > catchIdx,
      "complete*Request 必須在 provider catch 之外（之後）——settle/扣費後的" +
        "非預期例外不得被誤映成 provider 錯誤或誤 release claim",
    );
    assert(
      branch.includes("remainingBudgetMs <= 0"),
      "provider 呼叫前必須有 deadline 預算先擋（不得帶 1 秒地板硬跑）",
    );
  }
});

Deno.test("stream 分支不外流生成內容：done 之前只有 started/progress 事件", async () => {
  const source = await readIndexSource();
  for (
    const [startNeedle, endNeedle] of [
      ["if (openerStreamRequested) {", "let apiResult: FallbackResult;"],
      [
        "if (newTopicStreamRequested) {",
        "let newTopicApiResult: FallbackResult;",
      ],
    ]
  ) {
    const branch = sliceBetween(source, startNeedle, endNeedle);
    // emit 呼叫只允許固定事件常數與共用 outcome 轉換；不得把 fullText /
    // parsed 內容塞進 progress 事件。
    assertFalse(
      branch.includes("fullText.slice") || branch.includes("fullText.substring"),
      "progress 事件不得帶模型輸出片段（扣費前不外流內容）",
    );
  }
});
