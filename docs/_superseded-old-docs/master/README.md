# NeoOS — Master Documentation (authoritative index)

> This `docs/master/` set supersedes the older, contradictory `docs/*.md` files.
> It records **everything**: history, the audit, the designs, the decisions, the
> priority plan, the methodology, and what remains. Written after a sandbox reset
> that wiped the OS clone, so it doubles as the recovery record.

## Documents
1. [`01-status-and-history.md`](01-status-and-history.md) — current state + chronological history (incl. the reset & recovery).
2. [`02-audit.md`](02-audit.md) — full code/doc audit: bad practices, typing, forward refs, stubs, doc-claim verification, every `.HC` classified.
3. [`03-design.md`](03-design.md) — the design brainstorms: DolDoc model, shell, HolyGL-as-API, the Unified Tile Pipeline, "run anything", the MCU cluster.
4. [`04-plan.md`](04-plan.md) — the priority plan P0→P7 with every task.
5. [`05-methodology.md`](05-methodology.md) — testing & debugging via UART + QEMU protocols (mandatory for every change).
6. [`06-decisions-and-todo.md`](06-decisions-and-todo.md) — every decision made + the full remaining TODO.

## One-paragraph summary
NeoOS is a bare-metal **AArch64** OS: a small **C bootstrap** (`boot/main.c` + `boot/uefi`) plus a
**C JIT compiler** (`compiler/jit_arm64.c` + `lexer.c` + `table.c`) that compiles **51 HolyC `.HC` files**
at boot into Ring-0 machine code. It boots to a HolyC shell, renders a DolDoc UI, and has a fragmented
graphics stack (4 rasterizers / 3 fonts / 2 damage systems) and a cyclically-coupled UI stack
(DolDoc ↔ Shell ↔ WM ↔ Compositor). The end goal is **true self-hosting** (everything in HolyC, C only for
the UEFI bootstrap), a **perfect Unified Tile Pipeline** (HolyGL as an API with backends), a **real
TempleOS-model DolDoc**, and eventually running **any program/game at native speed** and scaling down to
**MCU clusters**.

## Current checkpoint
- **Golden gate: PASS** — shell active, all 32 subsystems, 0 exceptions, 0 undefined symbols, 50/50 JIT tests.
- Baseline commit `36ca4b0` + our commits `P0`, `P1`.
- Persisted: committed in the clone and bundled to `/home/user/project/neo-os.bundle`.
