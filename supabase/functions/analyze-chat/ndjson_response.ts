export type NdjsonEmit = (event: unknown) => void;
export type NdjsonClose = () => void;
export type NdjsonFail = (error: unknown) => void;

export type NdjsonStart = (
  emit: NdjsonEmit,
  close: NdjsonClose,
  fail: NdjsonFail,
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

      try {
        Promise.resolve(start(emit, close, fail)).catch(fail);
      } catch (error) {
        fail(error);
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
