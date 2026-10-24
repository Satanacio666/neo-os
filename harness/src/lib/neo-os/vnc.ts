import { EventEmitter } from "node:events";
import net from "node:net";
import type { NeoRect } from "./frame-protocol";

const VNC_HOST = process.env.NEO_VNC_HOST ?? "127.0.0.1";
const VNC_PORT = Number(process.env.NEO_VNC_PORT ?? 5900);
/** Coalescing window for framebuffer updates. ~60 fps by default. */
const FRAME_MS = Math.max(1, Number(process.env.NEO_FRAME_MS ?? 16));
/** Above this many dirty rects we fall back to a full-frame update. */
const MAX_RECTS = 256;

const LITTLE_ENDIAN = new Uint8Array(new Uint16Array([1]).buffer)[0] === 1;

type Phase = "version" | "security" | "secresult" | "serverinit" | "messages";

export type { NeoRect };

export interface NeoFrame {
  width: number;
  height: number;
  /** Authoritative full framebuffer: RGBA, 4 bytes/pixel, top-down. */
  rgba: Buffer;
  seq: number;
  /** Rectangles changed since the previous frame (empty when `full`). */
  rects: NeoRect[];
  /** True when consumers must repaint the entire framebuffer. */
  full: boolean;
}

/**
 * Minimal RFB (VNC) client that talks to QEMU's built-in VNC server.
 *
 * It maintains the guest framebuffer, tracks dirty rectangles so downstream
 * consumers can avoid re-encoding the whole surface, and forwards
 * keyboard/pointer events back into the guest.
 */
class NeoVncClient extends EventEmitter {
  private sock: net.Socket | null = null;
  private buf: Buffer = Buffer.alloc(0);
  private phase: Phase = "version";
  private connecting = false;
  private ready = false;

  private width = 0;
  private height = 0;
  private rgba: Buffer = Buffer.alloc(0);
  private rgba32: Uint32Array = new Uint32Array(0);
  /** Aligned scratch used when a raw rect cannot be viewed as u32 directly. */
  private scratch: Buffer = Buffer.alloc(0);
  private scratch32: Uint32Array = new Uint32Array(0);

  private frameSeq = 0;
  private flushTimer: NodeJS.Timeout | null = null;
  private pendingRects: NeoRect[] = [];
  private pendingArea = 0;
  private pendingFull = false;

  private watchdog: NodeJS.Timeout | null = null;

  get isReady(): boolean {
    return this.ready;
  }

  /** Tear down the socket and listeners (used on hot-reload replacement). */
  dispose(): void {
    if (this.watchdog) {
      clearInterval(this.watchdog);
      this.watchdog = null;
    }
    this.removeAllListeners();
    this.reset();
  }

  private ensureWatchdog(): void {
    if (this.watchdog) return;
    this.watchdog = setInterval(() => {
      if (!this.sock && !this.connecting) this.ensureConnected();
    }, 3000);
    this.watchdog.unref?.();
  }

  get size(): { width: number; height: number } {
    return { width: this.width, height: this.height };
  }

  getFrame(): NeoFrame {
    return {
      width: this.width,
      height: this.height,
      rgba: this.rgba,
      seq: this.frameSeq,
      rects: [],
      full: true,
    };
  }

  ensureConnected(): void {
    this.ensureWatchdog();
    if (this.sock || this.connecting) return;
    this.connecting = true;
    const sock = net.connect({ host: VNC_HOST, port: VNC_PORT });
    sock.setNoDelay(true);
    sock.on("connect", () => {
      this.connecting = false;
    });
    sock.on("data", (data) => this.onData(data));
    sock.on("error", () => this.reset());
    sock.on("close", () => this.reset());
    this.sock = sock;
  }

  private reset(): void {
    if (this.flushTimer) {
      clearTimeout(this.flushTimer);
      this.flushTimer = null;
    }
    if (this.sock) {
      this.sock.removeAllListeners();
      this.sock.destroy();
    }
    this.sock = null;
    this.connecting = false;
    this.ready = false;
    this.phase = "version";
    this.buf = Buffer.alloc(0);
    this.pendingRects = [];
    this.pendingArea = 0;
    this.pendingFull = false;
  }

  private onData(data: Buffer): void {
    this.buf = this.buf.length ? Buffer.concat([this.buf, data]) : data;
    try {
      this.pump();
    } catch {
      this.reset();
    }
  }

  private pump(): void {
    let progressed = true;
    while (progressed) {
      progressed = false;
      switch (this.phase) {
        case "version":
          if (this.buf.length < 12) return;
          this.buf = this.buf.subarray(12);
          this.write(Buffer.from("RFB 003.008\n", "ascii"));
          this.phase = "security";
          progressed = true;
          break;
        case "security": {
          if (this.buf.length < 1) return;
          const count = this.buf[0];
          if (this.buf.length < 1 + count) return;
          const types = this.buf.subarray(1, 1 + count);
          this.buf = this.buf.subarray(1 + count);
          if (!types.includes(1)) throw new Error("VNC server does not offer None auth");
          this.write(Buffer.from([1])); // None
          this.phase = "secresult";
          progressed = true;
          break;
        }
        case "secresult": {
          if (this.buf.length < 4) return;
          const ok = this.buf.readUInt32BE(0);
          this.buf = this.buf.subarray(4);
          if (ok !== 0) throw new Error("VNC auth failed");
          this.write(Buffer.from([1])); // ClientInit: shared
          this.phase = "serverinit";
          progressed = true;
          break;
        }
        case "serverinit": {
          if (this.buf.length < 24) return;
          const w = this.buf.readUInt16BE(0);
          const h = this.buf.readUInt16BE(2);
          const nameLen = this.buf.readUInt32BE(20);
          if (this.buf.length < 24 + nameLen) return;
          this.buf = this.buf.subarray(24 + nameLen);
          this.setSize(w, h);
          this.sendSetPixelFormat();
          this.sendSetEncodings();
          this.ready = true;
          this.requestUpdate(false);
          this.phase = "messages";
          progressed = true;
          break;
        }
        case "messages": {
          progressed = this.parseMessages();
          break;
        }
      }
    }
  }

  private parseMessages(): boolean {
    if (this.buf.length < 1) return false;
    const type = this.buf[0];
    if (type === 0) {
      // FramebufferUpdate
      if (this.buf.length < 4) return false;
      const nRects = this.buf.readUInt16BE(2);
      let off = 4;
      const rects: NeoRect[] = [];
      for (let i = 0; i < nRects; i++) {
        if (this.buf.length < off + 12) return false;
        const x = this.buf.readUInt16BE(off);
        const y = this.buf.readUInt16BE(off + 2);
        const w = this.buf.readUInt16BE(off + 4);
        const h = this.buf.readUInt16BE(off + 6);
        const enc = this.buf.readInt32BE(off + 8);
        off += 12;
        if (enc === 0) {
          // Raw
          const bytes = w * h * 4;
          if (this.buf.length < off + bytes) return false;
          this.blitRaw(x, y, w, h, this.buf.subarray(off, off + bytes));
          off += bytes;
          if (w > 0 && h > 0) rects.push({ x, y, w, h });
        } else if (enc === -223) {
          // DesktopSize pseudo-encoding
          if (w > 0 && h > 0 && (w !== this.width || h !== this.height)) {
            this.setSize(w, h);
          }
        } else if (enc === -224) {
          // LastRect
          break;
        } else {
          throw new Error(`unsupported VNC encoding ${enc}`);
        }
      }
      this.buf = this.buf.subarray(off);
      this.markDirty(rects);
      this.requestUpdate(true);
      return true;
    }
    if (type === 1) {
      // SetColourMapEntries
      if (this.buf.length < 6) return false;
      const nColors = this.buf.readUInt16BE(4);
      const total = 6 + nColors * 6;
      if (this.buf.length < total) return false;
      this.buf = this.buf.subarray(total);
      return true;
    }
    if (type === 2) {
      // Bell
      this.buf = this.buf.subarray(1);
      return true;
    }
    if (type === 3) {
      // ServerCutText
      if (this.buf.length < 8) return false;
      const len = this.buf.readUInt32BE(4);
      if (this.buf.length < 8 + len) return false;
      this.buf = this.buf.subarray(8 + len);
      return true;
    }
    throw new Error(`unknown VNC message type ${type}`);
  }

  private setSize(w: number, h: number): void {
    this.width = w;
    this.height = h;
    const bytes = w * h * 4;
    this.rgba = Buffer.alloc(bytes);
    this.rgba32 = new Uint32Array(this.rgba.buffer, this.rgba.byteOffset, w * h);
    this.scratch = Buffer.alloc(bytes);
    this.scratch32 = new Uint32Array(this.scratch.buffer, this.scratch.byteOffset, w * h);
    this.pendingRects = [];
    this.pendingArea = 0;
    this.pendingFull = true;
  }

  /**
   * Copy a raw RFB rectangle into the framebuffer, swizzling the server's
   * little-endian 0xXXRRGGBB pixels into RGBA. Uses 32-bit typed-array reads
   * instead of per-byte indexing.
   */
  private blitRaw(x: number, y: number, w: number, h: number, raw: Buffer): void {
    if (w <= 0 || h <= 0 || x >= this.width || y >= this.height) return;
    const dst = this.rgba32;
    const W = this.width;
    const H = this.height;
    const count = w * h;

    let src32: Uint32Array;
    if (LITTLE_ENDIAN && raw.byteOffset % 4 === 0 && raw.length >= count * 4) {
      src32 = new Uint32Array(raw.buffer, raw.byteOffset, count);
    } else {
      raw.copy(this.scratch, 0, 0, count * 4);
      src32 = this.scratch32;
    }

    const rows = Math.min(h, H - y);
    const cols = Math.min(w, W - x);
    for (let row = 0; row < rows; row++) {
      const s = row * w;
      const d = (y + row) * W + x;
      for (let col = 0; col < cols; col++) {
        const v = src32[s + col];
        dst[d + col] = ((v >>> 16) & 0xff) | (v & 0x0000ff00) | ((v & 0xff) << 16) | 0xff000000;
      }
    }
  }

  private markDirty(rects: NeoRect[]): void {
    if (rects.length === 0) {
      if (!this.pendingFull) return;
    }
    if (this.pendingFull) {
      this.scheduleFlush();
      return;
    }
    for (const r of rects) {
      this.pendingRects.push(r);
      this.pendingArea += r.w * r.h;
    }
    if (
      this.pendingRects.length > MAX_RECTS ||
      (this.width > 0 && this.pendingArea > this.width * this.height * 0.7)
    ) {
      this.pendingRects = [];
      this.pendingArea = 0;
      this.pendingFull = true;
    }
    this.scheduleFlush();
  }

  private scheduleFlush(): void {
    if (this.flushTimer) return;
    this.flushTimer = setTimeout(() => {
      this.flushTimer = null;
      this.flush();
    }, FRAME_MS);
  }

  private flush(): void {
    if (!this.pendingFull && this.pendingRects.length === 0) return;
    if (this.width === 0 || this.height === 0) return;
    this.frameSeq += 1;
    const full = this.pendingFull || this.pendingRects.length === 0;
    const rects = full ? [] : this.pendingRects;
    this.pendingRects = [];
    this.pendingArea = 0;
    this.pendingFull = false;
    this.emit("frame", {
      width: this.width,
      height: this.height,
      rgba: this.rgba,
      seq: this.frameSeq,
      rects,
      full,
    } satisfies NeoFrame);
  }

  private write(buf: Buffer): void {
    if (this.sock) this.sock.write(buf);
  }

  private sendSetPixelFormat(): void {
    const pf = Buffer.alloc(16);
    pf[0] = 32; // bits per pixel
    pf[1] = 24; // depth
    pf[2] = 0; // little-endian
    pf[3] = 1; // true color
    pf.writeUInt16BE(255, 4); // red max
    pf.writeUInt16BE(255, 6); // green max
    pf.writeUInt16BE(255, 8); // blue max
    pf[10] = 16; // red shift
    pf[11] = 8; // green shift
    pf[12] = 0; // blue shift
    const msg = Buffer.concat([Buffer.from([0, 0, 0, 0]), pf]);
    this.write(msg);
  }

  private sendSetEncodings(): void {
    const encodings = [0, -223, -224]; // Raw, DesktopSize, LastRect
    const msg = Buffer.alloc(4 + encodings.length * 4);
    msg[0] = 2;
    msg.writeUInt16BE(encodings.length, 2);
    encodings.forEach((e, i) => msg.writeInt32BE(e, 4 + i * 4));
    this.write(msg);
  }

  private requestUpdate(incremental: boolean): void {
    if (!this.ready) return;
    const msg = Buffer.alloc(10);
    msg[0] = 3;
    msg[1] = incremental ? 1 : 0;
    msg.writeUInt16BE(0, 2);
    msg.writeUInt16BE(0, 4);
    msg.writeUInt16BE(this.width, 6);
    msg.writeUInt16BE(this.height, 8);
    this.write(msg);
  }

  sendPointer(buttonMask: number, x: number, y: number): void {
    if (!this.ready) return;
    const msg = Buffer.alloc(6);
    msg[0] = 5;
    msg[1] = buttonMask & 0xff;
    msg.writeUInt16BE(Math.max(0, Math.min(65535, x)), 2);
    msg.writeUInt16BE(Math.max(0, Math.min(65535, y)), 4);
    this.write(msg);
  }

  sendKey(down: boolean, keysym: number): void {
    if (!this.ready) return;
    const msg = Buffer.alloc(8);
    msg[0] = 4;
    msg[1] = down ? 1 : 0;
    msg.writeUInt32BE(keysym >>> 0, 4);
    this.write(msg);
  }
}

/**
 * Bump when the client's behaviour or event payload changes. The dev server
 * keeps this singleton on `globalThis` across hot reloads, so without a version
 * guard a module rewrite would keep serving the stale, old-shaped client.
 */
const CLIENT_VERSION = 2;

interface VncGlobal {
  __neoVnc?: unknown;
}

function isVersioned(value: unknown): value is { version: number; client: NeoVncClient } {
  return (
    typeof value === "object" &&
    value !== null &&
    "version" in value &&
    "client" in value
  );
}

const globalRef = globalThis as unknown as VncGlobal;

export function getNeoVnc(): NeoVncClient {
  const current = globalRef.__neoVnc;
  if (!isVersioned(current) || current.version !== CLIENT_VERSION) {
    // The previous value may be a bare client from an older module revision.
    const stale = isVersioned(current) ? current.client : (current as Partial<NeoVncClient> | undefined);
    stale?.dispose?.();
    globalRef.__neoVnc = { version: CLIENT_VERSION, client: new NeoVncClient() };
  }
  const entry = globalRef.__neoVnc as { version: number; client: NeoVncClient };
  entry.client.ensureConnected();
  return entry.client;
}

export type { NeoVncClient };
