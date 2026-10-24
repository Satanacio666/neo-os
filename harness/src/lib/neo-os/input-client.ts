"use client";

export interface KeyInput {
  type: "key";
  down: boolean;
  keysym: number;
}

export interface PointerInput {
  type: "pointer";
  buttons: number;
  x: number;
  y: number;
}

export type ClientInputEvent = KeyInput | PointerInput;

let queue: ClientInputEvent[] = [];
let scheduled = false;
let lastRttMs = 0;

async function flush(): Promise<void> {
  if (queue.length === 0) return;
  const batch = queue;
  queue = [];
  const t0 = performance.now();
  try {
    await fetch("/api/neo-os/input", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(batch),
      keepalive: true,
    });
    lastRttMs = performance.now() - t0;
  } catch {
    // Transient failure; the next event retries.
  }
}

function schedule(): void {
  if (scheduled) return;
  scheduled = true;
  const cb = () => {
    scheduled = false;
    void flush();
  };
  if (typeof requestAnimationFrame === "function") requestAnimationFrame(cb);
  else setTimeout(cb, 16);
}

/**
 * Queue an input event. Events are flushed once per animation frame, and
 * consecutive pointer moves with the same button state are coalesced so a fast
 * mouse cannot flood the guest with HTTP requests.
 */
export function sendInput(event: ClientInputEvent): void {
  const last = queue[queue.length - 1];
  if (
    event.type === "pointer" &&
    last &&
    last.type === "pointer" &&
    last.buttons === event.buttons
  ) {
    queue[queue.length - 1] = event;
  } else {
    queue.push(event);
  }
  schedule();
}

/** Most recent input round-trip time in milliseconds (0 until measured). */
export function getInputRttMs(): number {
  return lastRttMs;
}
