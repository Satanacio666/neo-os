import { readVmStatus, runVmAction, VM_ACTIONS, type VmAction } from "@/lib/neo-os/vm-control";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** VM status without spawning a shell. */
export async function GET() {
  return Response.json(await readVmStatus());
}

/**
 * Control the viewer VM. `start`, `stop` and `restart` are destructive, so they
 * require an explicit `confirm: true` from the caller; `status` does not.
 */
export async function POST(req: Request) {
  let body: { action?: unknown; confirm?: unknown };
  try {
    body = (await req.json()) as { action?: unknown; confirm?: unknown };
  } catch {
    return Response.json({ error: "invalid json" }, { status: 400 });
  }

  const action = body.action;
  if (typeof action !== "string" || !VM_ACTIONS.includes(action as VmAction)) {
    return Response.json({ error: `action must be one of ${VM_ACTIONS.join(", ")}` }, { status: 400 });
  }

  const typed = action as VmAction;
  if (typed !== "status" && body.confirm !== true) {
    return Response.json(
      { error: "confirmation required", hint: "send { action, confirm: true }" },
      { status: 400 },
    );
  }

  const result = await runVmAction(typed);
  const status = await readVmStatus();
  return Response.json({
    action: typed,
    ok: result.code === 0,
    code: result.code,
    output: result.output,
    status,
  });
}
