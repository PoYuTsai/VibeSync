export type NdjsonEmit = (event: unknown) => void;
export type NdjsonClose = () => void;
export type NdjsonFail = (error: unknown) => void;
export type NdjsonIsClosed = () => boolean;

export type NdjsonStart = (
  emit: NdjsonEmit,
  close: NdjsonClose,
  fail: NdjsonFail,
  isClosed: NdjsonIsClosed,
) => void | Promise<void>;

export function ndjsonStreamResponse(
  start: NdjsonStart,
  headers: HeadersInit = {},
): Response {
  const encoder = new TextEncoder();
  let closed = false;

  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      const emit: NdjsonEmit = (event) => {
        if (closed) return;
        controller.enqueue(encoder.encode(`${JSON.stringify(event)}\n`));
      };

      const close: NdjsonClose = () => {
        if (closed) return;
        closed = true;
        controller.close();
      };

      const fail: NdjsonFail = (error) => {
        if (closed) return;
        closed = true;
        controller.error(error);
      };

      const isClosed: NdjsonIsClosed = () => closed;

      // start 逃出的例外常發生在 finally close() 之後，fail 會因已關閉而
      // 不動作；先留紀錄，否則伺服器端完全看不到。直接用 console.error，
      // 不引 logger.ts（它頂層載入 supabase-js），保持本檔零依賴。
      const failUnhandled = (error: unknown) => {
        console.error("[analyze-chat] ndjson_stream_unhandled", {
          error: error instanceof Error ? error.message : String(error),
        });
        fail(error);
      };

      try {
        Promise.resolve(start(emit, close, fail, isClosed)).catch(
          failUnhandled,
        );
      } catch (error) {
        failUnhandled(error);
      }
    },
    cancel() {
      closed = true;
    },
  });

  return new Response(stream, {
    status: 200,
    headers: {
      "Content-Type": "application/x-ndjson; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      "X-Accel-Buffering": "no",
      ...headers,
    },
  });
}
