// 兩段式 opener 的 source-scan 守門（同 opener_stream_branch_test.ts 慣例）：
// dispatch 存在、generic 月日 gate 排除、串流分支 transport-only、旗標閘門。
import { assert, assertFalse } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { classifyAnalyzeChatRequest } from "./request_shape.ts";

const indexSource = await Deno.readTextFile(new URL("./analyze_chat_handler.ts", import.meta.url));
const handlerSource = await Deno.readTextFile(new URL("./opener_flow_handler.ts", import.meta.url));

Deno.test("index：opener_analyze／opener_generate 分類與 dispatch 存在，且不被 generic 月日 gate 接管", () => {
  for (const mode of ["opener_analyze", "opener_generate"]) {
    const resolution = classifyAnalyzeChatRequest({ mode, userDraft: "草稿", images: [{}] });
    assert(resolution.ok && resolution.shape.kind === mode, `${mode} 帶草稿／圖片仍分類為自己`);
  }
  assert(indexSource.includes('const isOpenerFlowMode = requestShape.kind === "opener_analyze" ||'));
  assert(indexSource.includes("if (isOpenerFlowMode) {"));
  const gates = indexSource.split("!isOpenerFlowMode &&").length - 1;
  assert(gates >= 2, "月與日兩個 generic gate 都必須排除兩段式");
  assert(
    indexSource.indexOf("if (isOpenerFlowMode) {") < indexSource.indexOf("if (isOpenerMode) {"),
    "兩段式 dispatch 在舊單段 opener branch 之前",
  );
});

Deno.test("handler：串流被 OPENER_STREAM_ENABLED 閘住、只包模型呼叫與 complete；settle 不在 stream 包裝本體", () => {
  assert(handlerSource.includes('env("OPENER_STREAM_ENABLED") === "true"'));
  const start = handlerSource.indexOf("function streamOrRun(");
  const end = handlerSource.indexOf("// ═══", start);
  const wrapper = handlerSource.slice(start, end);
  assertFalse(wrapper.includes("settleOpenerGeneration"), "串流包裝本體不得自帶結算");
  assertFalse(wrapper.includes("settleOpenerAnalysis"));
  assert(wrapper.includes("emitJsonResponseAsStreamOutcome"));
  assert(wrapper.includes(`${"$"}{input.prefix}.started`));
});

Deno.test("handler：新局旗標與 DB 能力標記只擋第一段；第二段沒有 OPENER_TWO_STAGE_ENABLED 閘門", () => {
  const analyzeStart = handlerSource.indexOf("export async function handleOpenerAnalyzeRequest");
  const generateStart = handlerSource.indexOf("export async function handleOpenerGenerateRequest");
  const analyze = handlerSource.slice(analyzeStart, generateStart);
  const generate = handlerSource.slice(generateStart);
  assert(analyze.includes('env("OPENER_TWO_STAGE_ENABLED") === "false"'));
  assert(analyze.includes("readOpenerFlowDbContractVersion"));
  assertFalse(generate.includes("OPENER_TWO_STAGE_ENABLED"), "停用新局不得擋既有局取回或完成");
  // 第二段：模型前必有 claim（次數／併發／重播在模型前）、限流在 claim 後、settle 在投影後。
  const claimAt = generate.indexOf("await claimOpenerGeneration(claimArgs)");
  const rateAt = generate.indexOf('scope: "opener"');
  const modelAt = generate.indexOf("system: OPENER_GENERATE_PROMPT");
  const projectAt = generate.indexOf("projectOpenerGenerateResult(");
  const settleAt = generate.indexOf("await settleAndRespond(projected");
  assert(claimAt >= 0 && claimAt < rateAt && rateAt < modelAt && modelAt < projectAt && projectAt < settleAt);
  // 結構刀路徑同樣在 claim／限流之後才呼叫模型、產出結果後才結算；結算 RPC 全檔只有一處（新舊路徑共用）。
  const planWriteAt = generate.indexOf("await runOpenerPlanWrite(");
  const planSettleAt = generate.indexOf("await settleAndRespond(outcome.result");
  assert(rateAt < planWriteAt && planWriteAt < planSettleAt);
  assert(generate.split("await settleOpenerGeneration(").length === 2);
  // 扣費只發生在 settle RPC（SQL 內），handler 沒有任何直接 increment_usage 呼叫。
  assertFalse(handlerSource.includes("increment_usage"));
  assertFalse(handlerSource.includes("chargeOpenerQuota"));
});
