"use client";

import { useCallback, useEffect, useState } from "react";
import { AlertTriangle, Play, Power, RotateCcw } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Spinner } from "@/components/ui/spinner";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

type VmAction = "start" | "stop" | "restart";

interface VmStatus {
  running: boolean;
  pid: number | null;
  root: string;
  script: string;
  scriptPresent: boolean;
}

interface VmResponse {
  action: string;
  ok: boolean;
  code: number;
  output: string;
  status: VmStatus;
}

const ACTION_COPY: Record<VmAction, { label: string; verb: string; description: string }> = {
  start: {
    label: "Start VM",
    verb: "start",
    description: "Boot the QEMU guest. This rebuilds the serial log and takes a few seconds.",
  },
  restart: {
    label: "Restart VM",
    verb: "restart",
    description: "Stop and cold-boot the guest. Any unsaved in-guest state will be lost.",
  },
  stop: {
    label: "Stop VM",
    verb: "stop",
    description: "Kill the QEMU process and its UART bridge. The console will go offline.",
  },
};

export function VmControls({ onRunningChange }: { onRunningChange?: (running: boolean) => void }) {
  const [status, setStatus] = useState<VmStatus | null>(null);
  const [busy, setBusy] = useState<VmAction | null>(null);
  const [pending, setPending] = useState<VmAction | null>(null);
  const [lastOutput, setLastOutput] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const res = await fetch("/api/neo-os/vm", { cache: "no-store" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = (await res.json()) as VmStatus;
      setStatus(data);
      onRunningChange?.(data.running);
    } catch {
      // Keep the previous status; the header shows the stream state separately.
    }
  }, [onRunningChange]);

  useEffect(() => {
    void refresh();
    const id = setInterval(() => void refresh(), 5000);
    return () => clearInterval(id);
  }, [refresh]);

  const run = async (action: VmAction) => {
    setPending(null);
    setBusy(action);
    setLastOutput(null);
    try {
      const res = await fetch("/api/neo-os/vm", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, confirm: true }),
      });
      const data = (await res.json()) as VmResponse;
      if (!res.ok || !data.ok) {
        throw new Error(data.output || `HTTP ${res.status}`);
      }
      setStatus(data.status);
      onRunningChange?.(data.status.running);
      setLastOutput(data.output || null);
      toast.success(`VM ${action} complete`, { description: data.output || undefined });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      setLastOutput(message);
      toast.error(`VM ${action} failed`, { description: message });
    } finally {
      setBusy(null);
      void refresh();
    }
  };

  const running = status?.running ?? false;

  return (
    <section className="rounded-lg border bg-card p-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="mr-1 flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
          <Power className="size-3.5" />
          QEMU guest
        </span>
        <Badge variant={running ? "secondary" : "outline"} className="gap-1.5">
          <span
            className={`size-1.5 rounded-full ${running ? "bg-emerald-500" : "bg-muted-foreground"}`}
            aria-hidden
          />
          {running ? `running · pid ${status?.pid ?? "?"}` : "stopped"}
        </Badge>

        <div className="ml-auto flex items-center gap-2">
          <Button
            size="sm"
            variant="secondary"
            disabled={busy !== null || running || status?.scriptPresent === false}
            onClick={() => setPending("start")}
          >
            {busy === "start" ? <Spinner className="size-3" /> : <Play className="size-3" />}
            Start
          </Button>
          <Button
            size="sm"
            variant="secondary"
            disabled={busy !== null || !running}
            onClick={() => setPending("restart")}
          >
            {busy === "restart" ? <Spinner className="size-3" /> : <RotateCcw className="size-3" />}
            Restart
          </Button>
          <Button
            size="sm"
            variant="outline"
            disabled={busy !== null || !running}
            onClick={() => setPending("stop")}
          >
            {busy === "stop" ? <Spinner className="size-3" /> : <Power className="size-3" />}
            Stop
          </Button>
        </div>
      </div>

      {status && status.scriptPresent === false && (
        <p className="mt-2 flex items-center gap-1.5 text-xs text-destructive">
          <AlertTriangle className="size-3" />
          VM script not found at <code className="font-mono">{status.script}</code>. Set{" "}
          <code className="font-mono">NEO_OS_ROOT</code> to the NeoOS source root.
        </p>
      )}
      {lastOutput && (
        <pre className="mt-2 max-h-24 overflow-auto whitespace-pre-wrap rounded-md bg-background/60 p-2 font-mono text-[11px] text-muted-foreground">
          {lastOutput}
        </pre>
      )}

      <AlertDialog open={pending !== null} onOpenChange={(open) => !open && setPending(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{pending ? ACTION_COPY[pending].label : ""}</AlertDialogTitle>
            <AlertDialogDescription>
              {pending ? ACTION_COPY[pending].description : ""}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              className={pending === "stop" || pending === "restart" ? "bg-destructive text-white hover:bg-destructive/90" : ""}
              onClick={() => pending && void run(pending)}
            >
              {pending ? `Yes, ${ACTION_COPY[pending].verb}` : "Confirm"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </section>
  );
}
