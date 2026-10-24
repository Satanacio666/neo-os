"use client";

import { useEffect, useState } from "react";
import { cn } from "@/lib/utils";

interface StatusPayload {
  connected: boolean;
  width: number;
  height: number;
  vm?: { running: boolean };
}

export function LiveStatus() {
  const [status, setStatus] = useState<StatusPayload | null>(null);
  const [reachable, setReachable] = useState(true);

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      try {
        const res = await fetch("/api/neo-os/status", { cache: "no-store" });
        const data = (await res.json()) as StatusPayload;
        if (!cancelled) {
          setStatus(data);
          setReachable(true);
        }
      } catch {
        if (!cancelled) setReachable(false);
      }
    };
    void load();
    const id = setInterval(() => void load(), 5000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  const online = reachable && status?.connected === true;
  const label = !reachable
    ? "console unreachable"
    : online
      ? `guest live${status?.width ? ` · ${status.width}×${status.height}` : ""}`
      : "guest offline";

  return (
    <span className="inline-flex items-center gap-2 rounded-full border bg-card px-3 py-1 text-xs text-muted-foreground">
      <span
        className={cn(
          "size-2 rounded-full",
          online ? "bg-emerald-500" : reachable ? "bg-amber-500" : "bg-muted-foreground",
        )}
        aria-hidden
      />
      {label}
    </span>
  );
}
