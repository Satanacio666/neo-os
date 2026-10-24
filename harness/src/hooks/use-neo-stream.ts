"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { decodeMessage, type DecodedFrame } from "@/lib/neo-os/frame-protocol";

export type StreamStatus = "connecting" | "streaming" | "reconnecting" | "error" | "idle";

export interface RenderRect {
  x: number;
  y: number;
  w: number;
  h: number;
  /** RGBA bytes for this rect. Valid only for the duration of the callback. */
  data: Uint8Array;
}

export interface RenderFrame {
  seq: number;
  serverMs: number;
  width: number;
  height: number;
  rects: RenderRect[];
}

export interface NeoTelemetry {
  fps: number;
  kbps: number;
  frameKb: number;
  frameAgeMs: number;
  seq: number;
  width: number;
  height: number;
}

const EMPTY_TELEMETRY: NeoTelemetry = {
  fps: 0,
  kbps: 0,
  frameKb: 0,
  frameAgeMs: 0,
  seq: 0,
  width: 0,
  height: 0,
};

export interface UseNeoStreamOptions {
  onFrame: (frame: RenderFrame) => void;
  enabled?: boolean;
}

export interface UseNeoStreamResult {
  status: StreamStatus;
  telemetry: NeoTelemetry;
  error: string | null;
  reconnect: () => void;
}

/**
 * Connects to the binary framebuffer stream and decodes dirty-rect frames.
 *
 * Reconnects with exponential backoff + jitter, and tracks fps / bandwidth /
 * frame-age telemetry. `onFrame` is invoked synchronously per message; the
 * rect `data` views point into the internal read buffer and must be consumed
 * (e.g. via `putImageData`) before the callback returns.
 */
export function useNeoStream({ onFrame, enabled = true }: UseNeoStreamOptions): UseNeoStreamResult {
  const [status, setStatus] = useState<StreamStatus>(enabled ? "connecting" : "idle");
  const [telemetry, setTelemetry] = useState<NeoTelemetry>(EMPTY_TELEMETRY);
  const [error, setError] = useState<string | null>(null);
  const [nonce, setNonce] = useState(0);

  const onFrameRef = useRef(onFrame);
  onFrameRef.current = onFrame;

  const statsRef = useRef({
    frames: 0,
    bytes: 0,
    lastFrameKb: 0,
    lastSeq: 0,
    lastServerMs: 0,
    width: 0,
    height: 0,
  });

  const reconnect = useCallback(() => {
    setError(null);
    setNonce((n) => n + 1);
  }, []);

  useEffect(() => {
    if (!enabled) {
      setStatus("idle");
      return;
    }

    let stopped = false;
    let attempt = 0;
    let retryTimer: ReturnType<typeof setTimeout> | null = null;
    const controller = new AbortController();

    let buf = new Uint8Array(1 << 20);
    let start = 0;
    let end = 0;

    const ensure = (extra: number) => {
      if (buf.length - end >= extra) return;
      if (start > 0) {
        buf.copyWithin(0, start, end);
        end -= start;
        start = 0;
      }
      if (buf.length - end < extra) {
        let size = buf.length;
        while (size - end < extra) size *= 2;
        const next = new Uint8Array(size);
        next.set(buf.subarray(0, end));
        buf = next;
      }
    };

    const handleFrame = (msg: DecodedFrame) => {
      const rects: RenderRect[] = msg.rects.map((r) => ({
        x: r.x,
        y: r.y,
        w: r.w,
        h: r.h,
        data: buf.subarray(r.offset, r.offset + r.w * r.h * 4),
      }));
      const s = statsRef.current;
      s.frames += 1;
      s.bytes += msg.byteLength;
      s.lastSeq = msg.seq;
      s.lastServerMs = msg.serverMs;
      s.width = msg.width;
      s.height = msg.height;
      s.lastFrameKb = msg.byteLength / 1024;
      onFrameRef.current({ seq: msg.seq, serverMs: msg.serverMs, width: msg.width, height: msg.height, rects });
    };

    const process = () => {
      for (;;) {
        if (end - start < 1) return;
        const msg = decodeMessage(buf, start, end);
        if (!msg) return;
        start += msg.byteLength;
        if (msg.kind === "frame") handleFrame(msg);
      }
    };

    const append = (chunk: Uint8Array) => {
      ensure(chunk.length);
      buf.set(chunk, end);
      end += chunk.length;
    };

    const run = async () => {
      while (!stopped) {
        try {
          setStatus(attempt === 0 ? "connecting" : "reconnecting");
          const res = await fetch("/api/neo-os/frames", {
            signal: controller.signal,
            cache: "no-store",
          });
          if (!res.ok || !res.body) throw new Error(`stream unavailable (HTTP ${res.status})`);

          attempt = 0;
          setError(null);
          setStatus("streaming");

          const reader = res.body.getReader();
          for (;;) {
            const { done, value } = await reader.read();
            if (done) break;
            if (stopped) {
              void reader.cancel();
              return;
            }
            append(value);
            process();
            if (start > (1 << 20) || start > buf.length / 2) {
              buf.copyWithin(0, start, end);
              end -= start;
              start = 0;
            }
          }
          if (stopped) return;
          throw new Error("stream ended");
        } catch (err) {
          if (stopped) return;
          if (err instanceof DOMException && err.name === "AbortError") return;
          setError(err instanceof Error ? err.message : String(err));
        }

        if (stopped) return;
        setStatus("reconnecting");
        attempt += 1;
        const delay = Math.min(10000, 500 * 2 ** Math.min(attempt, 5)) + Math.floor(Math.random() * 250);
        await new Promise<void>((resolve) => {
          retryTimer = setTimeout(resolve, delay);
        });
      }
    };

    void run();

    return () => {
      stopped = true;
      controller.abort();
      if (retryTimer) clearTimeout(retryTimer);
    };
  }, [enabled, nonce]);

  useEffect(() => {
    if (!enabled) return;
    let last = performance.now();
    const id = setInterval(() => {
      const now = performance.now();
      const dt = Math.max(0.001, (now - last) / 1000);
      last = now;
      const s = statsRef.current;
      setTelemetry({
        fps: s.frames / dt,
        kbps: s.bytes / 1024 / dt,
        frameKb: s.lastFrameKb,
        frameAgeMs: s.lastServerMs > 0 ? Math.max(0, Date.now() - s.lastServerMs) : 0,
        seq: s.lastSeq,
        width: s.width,
        height: s.height,
      });
      s.frames = 0;
      s.bytes = 0;
    }, 500);
    return () => clearInterval(id);
  }, [enabled]);

  return { status, telemetry, error, reconnect };
}
