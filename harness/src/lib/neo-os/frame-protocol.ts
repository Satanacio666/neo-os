/**
 * Binary wire protocol for the low-latency framebuffer stream.
 *
 * This module is isomorphic: it is imported by the Node route handler (encoder
 * lives in ./frame-encode) and by the browser viewer (decoder). It must not
 * depend on any Node built-ins.
 *
 * Message framing (all integers little-endian):
 *
 *   HELLO
 *     u8  type = 0
 *     u16 width
 *     u16 height
 *
 *   FRAME
 *     u8  type = 1
 *     u32 seq
 *     f64 serverMs          (server wall-clock at encode time, for latency)
 *     u16 width
 *     u16 height
 *     u16 rectCount
 *     rectCount x { u16 x, u16 y, u16 w, u16 h }
 *     payload: for each rect in order, w*h*4 bytes of RGBA (top-down)
 *
 * The viewer reads this from a chunked HTTP body and blits each rect with
 * `putImageData` — no base64, no PNG, no full-frame re-encode on the hot path.
 */

export const MSG_HELLO = 0;
export const MSG_FRAME = 1;

export const HELLO_BYTES = 5;
export const FRAME_HEADER_BYTES = 19;
export const RECT_BYTES = 8;

export interface NeoRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface DecodedRect extends NeoRect {
  /** Byte offset of this rect's RGBA payload inside the source buffer. */
  offset: number;
}

export interface DecodedHello {
  kind: "hello";
  width: number;
  height: number;
  byteLength: number;
}

export interface DecodedFrame {
  kind: "frame";
  seq: number;
  serverMs: number;
  width: number;
  height: number;
  rects: DecodedRect[];
  /** Total number of bytes this message occupies. */
  byteLength: number;
}

export type DecodedMessage = DecodedHello | DecodedFrame;

/**
 * Try to decode a single message from `buf[start..end)`.
 *
 * Returns `null` when the buffer does not yet hold a complete message (the
 * caller should read more bytes and retry). Throws on an unknown message type,
 * which indicates stream corruption and should trigger a reconnect.
 */
export function decodeMessage(buf: Uint8Array, start: number, end: number): DecodedMessage | null {
  if (end - start < 1) return null;
  const type = buf[start];

  if (type === MSG_HELLO) {
    if (end - start < HELLO_BYTES) return null;
    const dv = new DataView(buf.buffer, buf.byteOffset + start, HELLO_BYTES);
    return {
      kind: "hello",
      width: dv.getUint16(1, true),
      height: dv.getUint16(3, true),
      byteLength: HELLO_BYTES,
    };
  }

  if (type === MSG_FRAME) {
    if (end - start < FRAME_HEADER_BYTES) return null;
    const head = new DataView(buf.buffer, buf.byteOffset + start, FRAME_HEADER_BYTES);
    const seq = head.getUint32(1, true);
    const serverMs = head.getFloat64(5, true);
    const width = head.getUint16(13, true);
    const height = head.getUint16(15, true);
    const count = head.getUint16(17, true);

    const rectsEnd = FRAME_HEADER_BYTES + count * RECT_BYTES;
    if (end - start < rectsEnd) return null;

    const rectView = new DataView(buf.buffer, buf.byteOffset + start, rectsEnd);
    const rects: DecodedRect[] = [];
    let payloadOffset = start + rectsEnd;
    let payloadBytes = 0;
    for (let i = 0; i < count; i++) {
      const o = FRAME_HEADER_BYTES + i * RECT_BYTES;
      const w = rectView.getUint16(o + 4, true);
      const h = rectView.getUint16(o + 6, true);
      rects.push({
        x: rectView.getUint16(o, true),
        y: rectView.getUint16(o + 2, true),
        w,
        h,
        offset: payloadOffset,
      });
      const bytes = w * h * 4;
      payloadOffset += bytes;
      payloadBytes += bytes;
    }

    const byteLength = rectsEnd + payloadBytes;
    if (end - start < byteLength) return null;

    return { kind: "frame", seq, serverMs, width, height, rects, byteLength };
  }

  throw new Error(`unknown frame message type ${type}`);
}
