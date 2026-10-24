import { encodeFrame, encodeHello } from "@/lib/neo-os/frame-encode";
import { getNeoVnc, type NeoFrame, type NeoRect } from "@/lib/neo-os/vnc";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Accumulated dirty rects beyond this collapse into a full-frame update. */
const MAX_ACCUM_RECTS = 256;
const KEEPALIVE_MS = 15000;

/**
 * Low-latency binary framebuffer stream.
 *
 * Unlike the SSE/PNG endpoint (kept for the regression gate), this sends raw
 * RGBA dirty rectangles with no base64 and no PNG round-trip. A ReadableStream
 * with a one-chunk queue provides backpressure: when the viewer is behind we
 * accumulate dirty regions server-side and coalesce to a full frame instead of
 * growing an unbounded buffer.
 */
export async function GET() {
  const vnc = getNeoVnc();

  let listener: ((frame: NeoFrame) => void) | null = null;
  let heartbeat: ReturnType<typeof setInterval> | null = null;
  let flushFn: (() => void) | null = null;

  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      let closed = false;
      let accumRects: NeoRect[] = [];
      let accumArea = 0;
      let accumFull = false;

      const canSend = () => controller.desiredSize === null || controller.desiredSize > 0;

      const flush = () => {
        if (closed || !canSend()) return;
        if (!accumFull && accumRects.length === 0) return;
        const size = vnc.size;
        if (size.width === 0 || size.height === 0) return;
        const frame = vnc.getFrame();
        try {
          const rects = accumFull ? [] : accumRects;
          controller.enqueue(
            encodeFrame(frame.rgba, frame.width, frame.height, frame.seq, Date.now(), rects),
          );
          accumRects = [];
          accumArea = 0;
          accumFull = false;
        } catch {
          closed = true;
        }
      };
      flushFn = flush;

      const onFrame = (frame: NeoFrame) => {
        if (closed) return;
        if (frame.full) {
          accumFull = true;
          accumRects = [];
          accumArea = 0;
        } else {
          for (const r of frame.rects) {
            accumRects.push(r);
            accumArea += r.w * r.h;
          }
          if (
            accumRects.length > MAX_ACCUM_RECTS ||
            (frame.width > 0 && accumArea > frame.width * frame.height * 0.7)
          ) {
            accumFull = true;
            accumRects = [];
            accumArea = 0;
          }
        }
        flush();
      };

      try {
        controller.enqueue(encodeHello(vnc.size.width, vnc.size.height));
        // Seed an initial full repaint for clients that connect to an idle guest.
        if (vnc.isReady && vnc.size.width > 0 && vnc.size.height > 0) accumFull = true;
      } catch {
        closed = true;
      }

      listener = onFrame;
      vnc.on("frame", listener);

      heartbeat = setInterval(() => {
        if (closed || !canSend()) return;
        try {
          controller.enqueue(encodeHello(vnc.size.width, vnc.size.height));
        } catch {
          closed = true;
        }
      }, KEEPALIVE_MS);
    },
    pull() {
      flushFn?.();
    },
    cancel() {
      if (listener) vnc.off("frame", listener);
      if (heartbeat) clearInterval(heartbeat);
      flushFn = null;
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "application/octet-stream",
      "Cache-Control": "no-store, no-transform",
      "X-Accel-Buffering": "no",
      Connection: "keep-alive",
    },
  });
}
