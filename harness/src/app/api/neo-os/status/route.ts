import { stat } from "node:fs/promises";
import { getNeoVnc } from "@/lib/neo-os/vnc";
import { readVmStatus } from "@/lib/neo-os/vm-control";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const SERIAL_LOG = process.env.NEO_SERIAL_LOG ?? "/tmp/neo-os-serial.log";

/**
 * Fast status probe. Unlike the previous version it only blocks briefly for a
 * cold VNC handshake instead of a fixed 2 s, so polling it is cheap.
 */
export async function GET() {
  const vnc = getNeoVnc();
  for (let i = 0; i < 5 && !vnc.isReady; i++) {
    await new Promise((r) => setTimeout(r, 80));
  }

  const { width, height } = vnc.size;

  let serialSize = 0;
  try {
    serialSize = (await stat(SERIAL_LOG)).size;
  } catch {
    serialSize = 0;
  }

  const vm = await readVmStatus();

  return Response.json({
    connected: vnc.isReady,
    width,
    height,
    vnc: { host: process.env.NEO_VNC_HOST ?? "127.0.0.1", port: Number(process.env.NEO_VNC_PORT ?? 5900) },
    serial: { log: SERIAL_LOG, size: serialSize },
    vm: { running: vm.running, pid: vm.pid, root: vm.root, scriptPresent: vm.scriptPresent },
    now: Date.now(),
  });
}
