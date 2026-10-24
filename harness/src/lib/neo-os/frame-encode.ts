import type { NeoRect } from "./frame-protocol";
import { FRAME_HEADER_BYTES, HELLO_BYTES, MSG_FRAME, MSG_HELLO, RECT_BYTES } from "./frame-protocol";

/**
 * Node-side encoder for the binary framebuffer protocol (see ./frame-protocol).
 */

export function encodeHello(width: number, height: number): Buffer {
  const buf = Buffer.allocUnsafe(HELLO_BYTES);
  buf.writeUInt8(MSG_HELLO, 0);
  buf.writeUInt16LE(width & 0xffff, 1);
  buf.writeUInt16LE(height & 0xffff, 3);
  return buf;
}

/**
 * Encode a frame as a header + per-rect payload. `rgba` is the authoritative
 * full framebuffer (top-down RGBA, 4 bytes/pixel). Rectangles outside the
 * framebuffer are clipped defensively.
 */
export function encodeFrame(
  rgba: Buffer,
  width: number,
  height: number,
  seq: number,
  serverMs: number,
  rects: NeoRect[],
): Buffer {
  const clipped: NeoRect[] = [];
  for (const r of rects) {
    const x = Math.max(0, r.x);
    const y = Math.max(0, r.y);
    const w = Math.min(r.w, width - x);
    const h = Math.min(r.h, height - y);
    if (w > 0 && h > 0) clipped.push({ x, y, w, h });
  }
  if (clipped.length === 0) clipped.push({ x: 0, y: 0, w: width, h: height });

  let payloadBytes = 0;
  for (const r of clipped) payloadBytes += r.w * r.h * 4;

  const total = FRAME_HEADER_BYTES + clipped.length * RECT_BYTES + payloadBytes;
  const out = Buffer.allocUnsafe(total);
  out.writeUInt8(MSG_FRAME, 0);
  out.writeUInt32LE(seq >>> 0, 1);
  out.writeDoubleLE(serverMs, 5);
  out.writeUInt16LE(width & 0xffff, 13);
  out.writeUInt16LE(height & 0xffff, 15);
  out.writeUInt16LE(clipped.length, 17);

  let off = FRAME_HEADER_BYTES;
  for (const r of clipped) {
    out.writeUInt16LE(r.x, off);
    out.writeUInt16LE(r.y, off + 2);
    out.writeUInt16LE(r.w, off + 4);
    out.writeUInt16LE(r.h, off + 6);
    off += RECT_BYTES;
  }

  for (const r of clipped) {
    const rowBytes = r.w * 4;
    const stride = width * 4;
    for (let row = 0; row < r.h; row++) {
      const srcStart = (r.y + row) * stride + r.x * 4;
      rgba.copy(out, off, srcStart, srcStart + rowBytes);
      off += rowBytes;
    }
  }

  return out;
}
