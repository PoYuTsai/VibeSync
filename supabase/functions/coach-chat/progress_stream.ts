import type {
  CoachChatProgressUpdate,
  GenerationResult,
} from "./generation.ts";

export const COACH_PROGRESS_MEDIA_TYPE = "application/x-ndjson";

export function wantsCoachProgressStream(request: Request): boolean {
  return request.headers.get("accept")?.toLowerCase().includes(
    COACH_PROGRESS_MEDIA_TYPE,
  ) ?? false;
}

type CoachChatProgressRunner = (
  onProgress: (update: CoachChatProgressUpdate) => void,
) => Promise<GenerationResult>;

/**
 * Progress-only transport for Coach 1:1.
 *
 * Only system-authored lifecycle stages are emitted before the terminal frame.
 * Model tokens and unvalidated card fields never cross this boundary.
 */
export function coachProgressStreamResponse(
  run: CoachChatProgressRunner,
  headers: HeadersInit = {},
): Response {
  const encoder = new TextEncoder();
  let closed = false;

  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      const emit = (event: unknown) => {
        if (closed) return;
        controller.enqueue(encoder.encode(`${JSON.stringify(event)}\n`));
      };
      const close = () => {
        if (closed) return;
        closed = true;
        controller.close();
      };

      Promise.resolve(
        run((update) => {
          emit({ type: "coach.progress", ...update });
        }),
      ).then((result) => {
        if (result.status === 200) {
          emit({ type: "coach.done", result: result.body });
        } else {
          emit({
            type: "coach.error",
            status: result.status,
            error: result.body,
          });
        }
        close();
      }).catch(() => {
        // Do not expose internal exception details over the progress channel.
        emit({
          type: "coach.error",
          status: 500,
          error: { error: "unexpected_error" },
        });
        close();
      });
    },
    cancel() {
      closed = true;
    },
  });

  return new Response(stream, {
    status: 200,
    headers: {
      "Content-Type": `${COACH_PROGRESS_MEDIA_TYPE}; charset=utf-8`,
      "Cache-Control": "no-cache, no-transform",
      "X-Accel-Buffering": "no",
      ...headers,
    },
  });
}
