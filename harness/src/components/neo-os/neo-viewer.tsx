"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  Activity,
  Gauge,
  Keyboard,
  Maximize,
  Minimize,
  MousePointer2,
  RefreshCw,
  Wifi,
  WifiOff,
} from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Kbd, KbdGroup } from "@/components/ui/kbd";
import { Spinner } from "@/components/ui/spinner";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useNeoStream, type RenderFrame } from "@/hooks/use-neo-stream";
import { getInputRttMs, sendInput } from "@/lib/neo-os/input-client";
import { toKeysym } from "@/lib/neo-os/keysym";
import { cn } from "@/lib/utils";

const KEY_GROUPS: Array<{ title: string; keys: Array<{ k: string; label: string }> }> = [
  {
    title: "Guest controls",
    keys: [
      { k: "Ctrl+Alt+Del", label: "Reboot hint to the guest" },
      { k: "Ctrl+C", label: "Interrupt the running guest program" },
      { k: "Enter", label: "Submit the serial/REPL line" },
    ],
  },
  {
    title: "Shell",
    keys: [
      { k: "↑ / ↓", label: "Command history" },
      { k: "Tab", label: "Autocomplete" },
      { k: "Esc", label: "Cancel current input" },
    ],
  },
  {
    title: "Viewer",
    keys: [
      { k: "Click", label: "Capture keyboard" },
      { k: "Esc", label: "Release keyboard" },
      { k: "Fullscreen", label: "Fill the screen with the guest" },
    ],
  },
];

function isTypingTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  const tag = target.tagName;
  return tag === "INPUT" || tag === "TEXTAREA" || target.isContentEditable;
}

export function NeoViewer() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const viewportRef = useRef<HTMLDivElement | null>(null);
  const ctxRef = useRef<CanvasRenderingContext2D | null>(null);
  const buttonsRef = useRef(0);
  const pointerRef = useRef({ x: 0, y: 0 });
  const guestRef = useRef({ w: 0, h: 0 });

  const [guest, setGuest] = useState({ w: 0, h: 0 });
  const [box, setBox] = useState({ w: 0, h: 0 });
  const [focused, setFocused] = useState(false);
  const [fit, setFit] = useState<"contain" | "actual">("contain");
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [showHelp, setShowHelp] = useState(false);
  const [rtt, setRtt] = useState(0);

  const onFrame = useCallback((frame: RenderFrame) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    if (canvas.width !== frame.width || canvas.height !== frame.height) {
      canvas.width = frame.width;
      canvas.height = frame.height;
      guestRef.current = { w: frame.width, h: frame.height };
      setGuest({ w: frame.width, h: frame.height });
      ctxRef.current = canvas.getContext("2d", { alpha: false });
    }
    const ctx = ctxRef.current ?? canvas.getContext("2d", { alpha: false });
    if (!ctx) return;
    ctxRef.current = ctx;
    for (const r of frame.rects) {
      if (r.w === 0 || r.h === 0) continue;
      const data = new Uint8ClampedArray(
        r.data.buffer as ArrayBuffer,
        r.data.byteOffset,
        r.data.length,
      );
      ctx.putImageData(new ImageData(data, r.w, r.h), r.x, r.y);
    }
  }, []);

  const { status, telemetry, error, reconnect } = useNeoStream({ onFrame });
  const streaming = status === "streaming";

  useEffect(() => {
    const el = viewportRef.current;
    if (!el) return;
    const ro = new ResizeObserver((entries) => {
      const rect = entries[0].contentRect;
      setBox({ w: rect.width, h: rect.height });
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  useEffect(() => {
    const onChange = () => setIsFullscreen(document.fullscreenElement === viewportRef.current);
    document.addEventListener("fullscreenchange", onChange);
    return () => document.removeEventListener("fullscreenchange", onChange);
  }, []);

  useEffect(() => {
    const id = setInterval(() => setRtt(getInputRttMs()), 1000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!focused || showHelp || isTypingTarget(e.target)) return;
      if (e.key === "Escape") {
        setFocused(false);
        (document.activeElement as HTMLElement | null)?.blur();
        return;
      }
      const keysym = toKeysym(e);
      if (!keysym) return;
      e.preventDefault();
      e.stopPropagation();
      sendInput({ type: "key", down: e.type === "keydown", keysym });
    };
    window.addEventListener("keydown", onKey, true);
    window.addEventListener("keyup", onKey, true);
    return () => {
      window.removeEventListener("keydown", onKey, true);
      window.removeEventListener("keyup", onKey, true);
    };
  }, [focused, showHelp]);

  const toGuest = useCallback((clientX: number, clientY: number) => {
    const canvas = canvasRef.current;
    const { w, h } = guestRef.current;
    if (!canvas || !w || !h) return { x: 0, y: 0 };
    const rect = canvas.getBoundingClientRect();
    const x = Math.round(((clientX - rect.left) / rect.width) * w);
    const y = Math.round(((clientY - rect.top) / rect.height) * h);
    return {
      x: Math.max(0, Math.min(w - 1, x)),
      y: Math.max(0, Math.min(h - 1, y)),
    };
  }, []);

  const movePointer = useCallback(
    (clientX: number, clientY: number) => {
      const p = toGuest(clientX, clientY);
      pointerRef.current = p;
      sendInput({ type: "pointer", buttons: buttonsRef.current, x: p.x, y: p.y });
    },
    [toGuest],
  );

  const onPointerDown = (e: React.PointerEvent<HTMLCanvasElement>) => {
    canvasRef.current?.focus();
    e.currentTarget.setPointerCapture(e.pointerId);
    const bit = e.button === 0 ? 1 : e.button === 1 ? 2 : 4;
    buttonsRef.current |= bit;
    movePointer(e.clientX, e.clientY);
  };

  const onPointerUp = (e: React.PointerEvent<HTMLCanvasElement>) => {
    const bit = e.button === 0 ? 1 : e.button === 1 ? 2 : 4;
    buttonsRef.current &= ~bit;
    movePointer(e.clientX, e.clientY);
    if (e.currentTarget.hasPointerCapture(e.pointerId)) {
      e.currentTarget.releasePointerCapture(e.pointerId);
    }
  };

  const onWheel = (e: React.WheelEvent<HTMLCanvasElement>) => {
    const p = toGuest(e.clientX, e.clientY);
    const button = e.deltaY < 0 ? 4 : 5;
    sendInput({ type: "pointer", buttons: buttonsRef.current | button, x: p.x, y: p.y });
    sendInput({ type: "pointer", buttons: buttonsRef.current, x: p.x, y: p.y });
  };

  const toggleFullscreen = async () => {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else await viewportRef.current?.requestFullscreen();
    } catch {
      toast.error("Fullscreen unavailable", {
        description: "The preview iframe may block fullscreen. Open the console in a new tab.",
      });
    }
  };

  const scale = guest.w && box.w ? Math.min(box.w / guest.w, box.h / guest.h) : 1;
  const displayW = fit === "contain" ? Math.max(1, Math.floor(guest.w * scale)) : guest.w;
  const displayH = fit === "contain" ? Math.max(1, Math.floor(guest.h * scale)) : guest.h;

  const statusMeta = {
    connecting: { label: "connecting", tone: "text-amber-400", dot: "bg-amber-400" },
    streaming: { label: "streaming", tone: "text-emerald-400", dot: "bg-emerald-400" },
    reconnecting: { label: "reconnecting", tone: "text-amber-400", dot: "bg-amber-400" },
    error: { label: "offline", tone: "text-destructive", dot: "bg-destructive" },
    idle: { label: "idle", tone: "text-muted-foreground", dot: "bg-muted-foreground" },
  }[status];

  return (
    <section className="flex min-h-0 flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <Badge variant="secondary" className="gap-1.5">
          <span className={cn("size-1.5 rounded-full", statusMeta.dot)} aria-hidden />
          <span className={statusMeta.tone}>{statusMeta.label}</span>
        </Badge>
        <Badge variant="outline" className="font-mono tabular-nums">
          {telemetry.width ? `${telemetry.width}×${telemetry.height}` : "—"}
        </Badge>
        <Badge variant="outline" className="gap-1 font-mono tabular-nums">
          <Gauge className="size-3" />
          {telemetry.fps.toFixed(0)} fps
        </Badge>
        <Badge variant="outline" className="gap-1 font-mono tabular-nums">
          <Activity className="size-3" />
          {telemetry.kbps >= 1024
            ? `${(telemetry.kbps / 1024).toFixed(1)} MB/s`
            : `${telemetry.kbps.toFixed(0)} KB/s`}
        </Badge>
        <Badge variant="outline" className="font-mono tabular-nums">
          {telemetry.frameKb.toFixed(1)} KB/frame
        </Badge>
        <Badge variant="outline" className="gap-1 font-mono tabular-nums">
          <MousePointer2 className="size-3" />
          {rtt > 0 ? `${rtt.toFixed(0)} ms` : "—"}
        </Badge>

        <div className="ml-auto flex items-center gap-2">
          <Button size="sm" variant="ghost" onClick={() => setFit(fit === "contain" ? "actual" : "contain")}>
            {fit === "contain" ? "Fit" : "1:1"}
          </Button>
          <Button size="sm" variant="ghost" onClick={() => setShowHelp(true)}>
            <Keyboard className="size-3.5" />
            Keys
          </Button>
          <Button size="sm" variant="ghost" onClick={() => void toggleFullscreen()}>
            {isFullscreen ? <Minimize className="size-3.5" /> : <Maximize className="size-3.5" />}
            {isFullscreen ? "Exit" : "Fullscreen"}
          </Button>
          <Button size="sm" variant="secondary" onClick={reconnect} disabled={streaming}>
            {status === "reconnecting" || status === "connecting" ? (
              <Spinner className="size-3.5" />
            ) : (
              <RefreshCw className="size-3.5" />
            )}
            Reconnect
          </Button>
        </div>
      </div>

      <div
        ref={viewportRef}
        className={cn(
          "relative flex aspect-[4/3] max-h-[72vh] w-full items-center justify-center overflow-auto rounded-lg border bg-black p-2",
          fit === "actual" && "items-start justify-start",
        )}
      >
        <canvas
          ref={canvasRef}
          tabIndex={0}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
          onPointerDown={onPointerDown}
          onPointerUp={onPointerUp}
          onPointerMove={(e) => movePointer(e.clientX, e.clientY)}
          onWheel={onWheel}
          onContextMenu={(e) => e.preventDefault()}
          aria-label="NeoOS guest framebuffer"
          className="block cursor-crosshair touch-none outline-none"
          style={{
            width: displayW,
            height: displayH,
            imageRendering: "pixelated",
            boxShadow: focused ? "0 0 0 2px var(--ring)" : undefined,
          }}
        />

        {!streaming && (
          <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center gap-2 bg-black/75 p-6 text-center">
            {status === "error" ? (
              <>
                <WifiOff className="size-6 text-destructive" />
                <p className="text-sm text-foreground">Stream unavailable</p>
                <p className="max-w-sm text-xs text-muted-foreground">
                  {error ?? "The guest framebuffer could not be reached."} Check the QEMU guest, then
                  reconnect.
                </p>
              </>
            ) : (
              <>
                <Spinner className="size-5 text-muted-foreground" />
                <p className="text-sm text-foreground">
                  {status === "reconnecting" ? "Reconnecting…" : "Waiting for the guest framebuffer…"}
                </p>
                <p className="max-w-sm text-xs text-muted-foreground">
                  Start the VM or check the serial console. The viewer reconnects automatically.
                </p>
              </>
            )}
          </div>
        )}

        {streaming && !focused && (
          <div className="pointer-events-none absolute bottom-3 left-1/2 -translate-x-1/2 rounded-full bg-black/70 px-3 py-1 text-[11px] text-foreground">
            Click the screen to capture the keyboard
          </div>
        )}
        {streaming && focused && (
          <div className="pointer-events-none absolute bottom-3 left-1/2 flex -translate-x-1/2 items-center gap-1.5 rounded-full bg-black/70 px-3 py-1 text-[11px] text-emerald-400">
            <Wifi className="size-3" /> Keyboard captured · press Esc to release
          </div>
        )}
      </div>

      <Dialog open={showHelp} onOpenChange={setShowHelp}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Keyboard shortcuts</DialogTitle>
            <DialogDescription>
              Keys are forwarded to the guest while the screen has focus. Press <Kbd>Esc</Kbd> to
              release the keyboard.
            </DialogDescription>
          </DialogHeader>
          <div className="grid gap-4 sm:grid-cols-2">
            {KEY_GROUPS.map((group) => (
              <div key={group.title} className="space-y-2">
                <h3 className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                  {group.title}
                </h3>
                <ul className="space-y-2">
                  {group.keys.map((k) => (
                    <li key={k.k} className="flex items-start justify-between gap-3 text-sm">
                      <KbdGroup>
                        <Kbd>{k.k}</Kbd>
                      </KbdGroup>
                      <span className="text-right text-xs text-muted-foreground">{k.label}</span>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </DialogContent>
      </Dialog>
    </section>
  );
}
