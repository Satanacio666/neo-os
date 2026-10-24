import { encodePng } from "@/lib/neo-os/png";
import { getNeoVnc, type NeoFrame } from "@/lib/neo-os/vnc";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * Slow compatibility path: full-frame PNG over Server-Sent Events.
 *
 * The NeoOS regression gate (scripts/golden-boot.sh) consumes this endpoint and
 * expects each `data:` line to be JSON with base64 `png`, `width` and `height`.
 * The interactive console uses the binary stream at /api/neo-os/frames instead.
 * Frames are throttled so a forgotten tab cannot burn CPU re-encoding PNGs.
 */
const MIN_INTERVAL_MS = 100;

export async function GET() {
  const vnc = getNeoVnc();
  const encoder = new TextEncoder();

  let listener: ((frame: NeoFrame) => void) | null = null;
  let heartbeat: ReturnType<typeof setInterval> | null = null;

  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      let closed = false;
      let lastSent = 0;

      const send = (frame: NeoFrame) => {
        if (closed || frame.width === 0 || frame.height === 0) return;
        const now = Date.now();
        if (now - lastSent < MIN_INTERVAL_MS) return;
        lastSent = now;
        try {
          const png = encodePng(frame.rgba, frame.width, frame.height, 3);
          const payload = JSON.stringify({
            seq: frame.seq,
            width: frame.width,
            height: frame.height,
            png: png.toString("base64"),
          });
          controller.enqueue(encoder.encode(`data: ${payload}\n\n`));
        } catch {
          // ignore malformed frame
        }
      };

      controller.enqueue(encoder.encode("retry: 1000\n\n"));
      if (vnc.isReady) send(vnc.getFrame());

      listener = (frame: NeoFrame) => send(frame);
      vnc.on("frame", listener);

      heartbeat = setInterval(() => {
        if (closed) return;
        try {
          controller.enqueue(encoder.encode(": ping\n\n"));
        } catch {
          closed = true;
        }
      }, 15000);
    },
    cancel() {
      if (listener) vnc.off("frame", listener);
      if (heartbeat) clearInterval(heartbeat);
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    },
  });
}
