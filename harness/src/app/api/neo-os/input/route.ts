import { getNeoVnc, type NeoVncClient } from "@/lib/neo-os/vnc";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

interface KeyInput {
  type: "key";
  down: boolean;
  keysym: number;
}

interface PointerInput {
  type: "pointer";
  buttons: number;
  x: number;
  y: number;
}

type InputEvent = KeyInput | PointerInput;

const MAX_BATCH = 64;

function isInputEvent(value: unknown): value is InputEvent {
  if (typeof value !== "object" || value === null) return false;
  const v = value as Record<string, unknown>;
  if (v.type === "key") return typeof v.down === "boolean" && typeof v.keysym === "number";
  if (v.type === "pointer") {
    return typeof v.buttons === "number" && typeof v.x === "number" && typeof v.y === "number";
  }
  return false;
}

function applyEvent(vnc: NeoVncClient, event: InputEvent): void {
  if (event.type === "key") {
    vnc.sendKey(Boolean(event.down), Number(event.keysym) || 0);
  } else {
    vnc.sendPointer(Number(event.buttons) || 0, Number(event.x) || 0, Number(event.y) || 0);
  }
}

/** Accepts a single input event or a batch (`InputEvent[]`) to reduce requests. */
export async function POST(req: Request) {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return Response.json({ error: "invalid json" }, { status: 400 });
  }

  const events = Array.isArray(body) ? body.slice(0, MAX_BATCH) : [body];
  if (events.length === 0 || !events.every(isInputEvent)) {
    return Response.json({ error: "unknown event" }, { status: 400 });
  }

  const vnc = getNeoVnc();
  if (!vnc.isReady) {
    return Response.json({ error: "vnc not connected" }, { status: 503 });
  }

  for (const event of events) applyEvent(vnc, event);
  return Response.json({ ok: true, applied: events.length });
}
