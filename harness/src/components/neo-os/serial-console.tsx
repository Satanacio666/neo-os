"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Check, Copy, Eraser, Send, TerminalSquare } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Spinner } from "@/components/ui/spinner";
import { cn } from "@/lib/utils";

const MAX_VIEW_BYTES = 200 * 1024;
const POLL_MS = 1000;

interface SerialResponse {
  size: number;
  offset: number;
  next?: number;
  text: string;
}

export function SerialConsole() {
  const [text, setText] = useState("");
  const [size, setSize] = useState(0);
  const [input, setInput] = useState("");
  const [autoScroll, setAutoScroll] = useState(true);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [sending, setSending] = useState(false);
  const [copied, setCopied] = useState(false);

  const offsetRef = useRef(0);
  const initializedRef = useRef(false);
  const boxRef = useRef<HTMLPreElement | null>(null);

  const poll = useCallback(async () => {
    try {
      const url = initializedRef.current
        ? `/api/neo-os/serial?offset=${offsetRef.current}`
        : "/api/neo-os/serial";
      const res = await fetch(url, { cache: "no-store" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = (await res.json()) as SerialResponse;
      initializedRef.current = true;

      if (data.offset < offsetRef.current) {
        // Log rotated/truncated: replace instead of appending.
        setText(data.text);
      } else if (data.text) {
        setText((prev) => {
          const next = prev + data.text;
          return next.length > MAX_VIEW_BYTES ? next.slice(next.length - MAX_VIEW_BYTES) : next;
        });
      }
      offsetRef.current = data.next ?? data.offset + data.text.length;
      setSize(data.size);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void poll();
    const id = setInterval(() => void poll(), POLL_MS);
    return () => clearInterval(id);
  }, [poll]);

  useEffect(() => {
    if (autoScroll && boxRef.current) boxRef.current.scrollTop = boxRef.current.scrollHeight;
  }, [text, autoScroll]);

  const send = async () => {
    if (!input) return;
    setSending(true);
    try {
      const res = await fetch("/api/neo-os/serial", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ data: `${input}\r` }),
      });
      const data = (await res.json()) as { ok?: boolean; error?: string };
      if (!res.ok || !data.ok) throw new Error(data.error ?? `HTTP ${res.status}`);
      setInput("");
    } catch (err) {
      toast.error("Could not send to UART", {
        description: err instanceof Error ? err.message : String(err),
      });
    } finally {
      setSending(false);
    }
  };

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      toast.error("Clipboard unavailable");
    }
  };

  return (
    <section className="flex flex-col overflow-hidden rounded-lg border bg-card">
      <div className="flex items-center justify-between gap-2 border-b px-3 py-2">
        <div className="flex items-center gap-2">
          <TerminalSquare className="size-4 text-muted-foreground" />
          <h2 className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            UART · PL011 serial
          </h2>
          <Badge variant="secondary" className="font-mono text-[10px] tabular-nums">
            {size.toLocaleString()} B
          </Badge>
        </div>
        <div className="flex items-center gap-1">
          <Button
            size="xs"
            variant={autoScroll ? "secondary" : "ghost"}
            onClick={() => setAutoScroll((v) => !v)}
            aria-pressed={autoScroll}
          >
            Auto-scroll
          </Button>
          <Button size="icon-xs" variant="ghost" aria-label="Copy serial output" onClick={() => void copy()}>
            {copied ? <Check className="size-3" /> : <Copy className="size-3" />}
          </Button>
          <Button
            size="icon-xs"
            variant="ghost"
            aria-label="Clear serial view"
            onClick={() => setText("")}
          >
            <Eraser className="size-3" />
          </Button>
        </div>
      </div>

      <pre
        ref={boxRef}
        className="h-64 overflow-auto whitespace-pre-wrap break-words bg-background/60 p-3 font-mono text-[11px] leading-relaxed text-emerald-400/90"
      >
        {loading ? (
          <span className="flex items-center gap-2 text-muted-foreground">
            <Spinner className="size-3" /> Reading serial log…
          </span>
        ) : error ? (
          <span className="text-destructive">Serial log unavailable: {error}</span>
        ) : text ? (
          text
        ) : (
          <span className="text-muted-foreground">No serial output yet.</span>
        )}
      </pre>

      <div className="flex items-center gap-2 border-t p-2">
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              void send();
            }
          }}
          placeholder="Send a line to the guest over UART…"
          aria-label="UART input"
          className={cn(
            "h-8 flex-1 rounded-md border bg-background px-2 text-xs outline-none",
            "focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50",
          )}
        />
        <Button size="sm" variant="secondary" disabled={sending || !input} onClick={() => void send()}>
          {sending ? <Spinner className="size-3" /> : <Send className="size-3" />}
          Send
        </Button>
      </div>
    </section>
  );
}
