import { readFile } from "node:fs/promises";
import net from "node:net";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const SERIAL_LOG = process.env.NEO_SERIAL_LOG ?? "/tmp/neo-os-serial.log";
/** Real UART input socket created by scripts/run-viewer-vm.sh (uart-bridge.mjs). */
const UART_IN_SOCK =
  process.env.NEO_UART_IN_SOCK ?? process.env.NEO_UART_SOCK ?? "/tmp/neo-os-uart-in.sock";
const MAX_BYTES = 64 * 1024;

/**
 * Tail the serial log. Pass `?offset=<bytes>` to fetch only new output; the
 * response then carries `offset` (the byte position the text starts at) so the
 * client can append instead of re-reading the whole tail.
 */
export async function GET(req: Request) {
  const url = new URL(req.url);
  const sinceParam = url.searchParams.get("offset");

  try {
    const buf = await readFile(SERIAL_LOG);
    const size = buf.length;

    if (sinceParam !== null) {
      const since = Number.parseInt(sinceParam, 10);
      const start = Number.isFinite(since) && since >= 0 && since <= size ? since : Math.max(0, size - MAX_BYTES);
      const slice = buf.subarray(start, start + MAX_BYTES);
      return Response.json({ size, offset: start, next: start + slice.length, text: slice.toString("utf8") });
    }

    const start = Math.max(0, size - MAX_BYTES);
    const slice = buf.subarray(start, start + MAX_BYTES);
    return Response.json({ size, offset: start, next: start + slice.length, text: slice.toString("utf8") });
  } catch {
    return Response.json({ size: 0, offset: 0, next: 0, text: "" });
  }
}

export async function POST(req: Request) {
  let data = "";
  try {
    const body = (await req.json()) as { data?: string };
    data = typeof body.data === "string" ? body.data : "";
  } catch {
    return Response.json({ error: "invalid json" }, { status: 400 });
  }
  if (!data) return Response.json({ error: "empty" }, { status: 400 });
  if (data.length > 8192) return Response.json({ error: "payload too large" }, { status: 413 });

  const ok = await new Promise<boolean>((resolve) => {
    const sock = net.connect(UART_IN_SOCK);
    let settled = false;
    const done = (value: boolean) => {
      if (settled) return;
      settled = true;
      sock.destroy();
      resolve(value);
    };
    sock.on("connect", () => {
      sock.write(data, () => done(true));
    });
    sock.on("error", () => done(false));
    setTimeout(() => done(false), 2000);
  });

  return Response.json({ ok });
}
