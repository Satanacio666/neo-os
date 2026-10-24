# NeoOS web console (browser harness)

A Next.js app that drives the **NeoOS Ring 0 AArch64 guest** in a browser: live framebuffer streaming,
keyboard + pointer input, a UART console, and VM start/stop control. It is the "web GUI harness" for the OS in
the parent directory — it does **not** contain any OS code.

```
harness/                     <- this Next.js app (browser harness)
../apps, ../boot, ../kernel, ../scripts, ../docs, ../Makefile   <- the actual OS + its CLI harness
```

## How it connects to the OS

| Harness piece | Talks to | Transport |
|---|---|---|
| `src/app/api/neo-os/frames` | QEMU VNC server (`scripts/run-viewer-vm.sh` → `-vnc 127.0.0.1:5900`) | binary dirty-rect RGBA stream |
| `src/app/api/neo-os/stream` | same VNC server | SSE + PNG (used by `scripts/golden-boot.sh` for screenshots) |
| `src/app/api/neo-os/input` | VNC | keyboard/pointer events (`src/lib/neo-os/keysym.ts`) |
| `src/app/api/neo-os/serial` | `scripts/uart-bridge.mjs` UART socket + `/tmp/neo-os-serial.log` | newline REPL |
| `src/app/api/neo-os/vm` | `scripts/run-viewer-vm.sh start\|stop\|restart\|status` | spawn |
| `src/lib/neo-os/vnc.ts` | VNC RFB client + framebuffer decoder | TCP |

The OS root is auto-detected as the nearest ancestor of this directory containing `scripts/run-viewer-vm.sh`
(override with `NEO_OS_ROOT`). All endpoints are env-configurable — see `.env.example`.

## Run it

```bash
# 1. Build + boot the OS VM (from the repo root)
cd .. && make all && ./scripts/run-viewer-vm.sh restart

# 2. Install + start the harness
cd harness
bun install
bun run dev          # http://localhost:3000/neo-os
```

The console lives at `/neo-os`; `/` is the landing page. `bun run typecheck` type-checks the app.

> The E2B/Ideavo preview injects an instrumentation script (`src/app/layout.tsx`) and a webpack tagger
> (`next.config.ts`). Both are no-ops outside that environment; the app runs on plain `next dev`/`next build`.

## Layout

```
src/app/page.tsx                 landing page (features + live status)
src/app/neo-os/page.tsx          the console (viewer + VM controls + serial)
src/app/api/neo-os/*             the six API routes above
src/components/neo-os/*          NeoViewer, SerialConsole, VmControls, LiveStatus
src/lib/neo-os/*                 vnc, png, frame-encode, frame-protocol, keysym, input-client, vm-control
src/components/ui/*              the shadcn/ui primitives actually used
```

See the repo root `README.md` and `docs/00`–`docs/04` for the OS itself.
