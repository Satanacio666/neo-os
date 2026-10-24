import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import path from "node:path";

/**
 * Root of the (read-only) NeoOS source tree.
 *
 * This harness lives at `<repo>/harness`, so the OS root is the nearest ancestor
 * that contains `scripts/run-viewer-vm.sh`. Override with `NEO_OS_ROOT` when the
 * harness runs from a different checkout (e.g. the E2B preview shell at
 * `/home/user/project` drives the repo at `/home/user/neo-os`).
 */
function findRepoRoot(): string {
  if (process.env.NEO_OS_ROOT) return process.env.NEO_OS_ROOT;
  let dir = process.cwd();
  for (let i = 0; i < 8; i++) {
    if (existsSync(path.join(dir, "scripts", "run-viewer-vm.sh"))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return path.resolve(process.cwd(), "..");
}

export const NEO_OS_ROOT = findRepoRoot();
export const VM_SCRIPT = path.join(NEO_OS_ROOT, "scripts", "run-viewer-vm.sh");
export const VM_PIDFILE = process.env.NEO_VM_PIDFILE ?? "/tmp/neo-os-vm.pid";

export type VmAction = "start" | "stop" | "restart" | "status";
export const VM_ACTIONS: readonly VmAction[] = ["start", "stop", "restart", "status"];

export interface VmStatus {
  running: boolean;
  pid: number | null;
  root: string;
  script: string;
  scriptPresent: boolean;
}

export async function readVmStatus(): Promise<VmStatus> {
  let pid: number | null = null;
  try {
    const raw = await readFile(VM_PIDFILE, "utf8");
    const parsed = Number.parseInt(raw.trim(), 10);
    if (Number.isFinite(parsed)) pid = parsed;
  } catch {
    pid = null;
  }

  let running = false;
  if (pid !== null) {
    try {
      process.kill(pid, 0);
      running = true;
    } catch {
      running = false;
    }
  }

  return {
    running,
    pid: running ? pid : null,
    root: NEO_OS_ROOT,
    script: VM_SCRIPT,
    scriptPresent: existsSync(VM_SCRIPT),
  };
}

export interface VmResult {
  action: VmAction;
  code: number;
  output: string;
}

export function runVmAction(action: VmAction, timeoutMs = 30000): Promise<VmResult> {
  return new Promise((resolve) => {
    if (!existsSync(VM_SCRIPT)) {
      resolve({ action, code: -1, output: `VM script not found at ${VM_SCRIPT}` });
      return;
    }

    const child = spawn("bash", [VM_SCRIPT, action], {
      cwd: NEO_OS_ROOT,
      env: { ...process.env, NEO_OS_ROOT },
      detached: false,
    });

    let output = "";
    let settled = false;
    const finish = (code: number) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({ action, code, output: output.trim() });
    };

    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      output += `\n[timeout after ${timeoutMs}ms]`;
      finish(-1);
    }, timeoutMs);

    child.stdout.on("data", (d: Buffer) => (output += d.toString()));
    child.stderr.on("data", (d: Buffer) => (output += d.toString()));
    child.on("error", (err) => {
      output += `\n${String(err)}`;
      finish(-1);
    });
    child.on("close", (code) => finish(code ?? -1));
  });
}
