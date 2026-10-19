# 01 — Status & History

## Current status (green checkpoint)
- **Build:** `make all` → `build/BOOTAA64.EFI`, `build/disk.img`, `build/redsea.img`. Toolchain: `gcc-aarch64-linux-gnu`, `qemu-system-aarch64`, `dosfstools`, `mtools`, `python3-pil`, `socat`.
- **Boot:** reaches `DolDocShell`, prints "ALL 32 HOLYC SUBSYSTEMS COMPILED & ACTIVE IN RING 0", **0 exceptions**.
- **Symbols:** `[SYMBOLS] No unresolved forward references.` — **0 undefined identifiers**.
- **JIT battery:** **50/50** (`tests/jit_golden/cases.json`).
- **Golden gate:** `scripts/golden-boot.sh` → **PASS**.
- **Repo:** clone at `/home/user/neo-os`; commits `P0` (harness), `P1` (compiler fixes); bundle at `/home/user/project/neo-os.bundle`.

## Environment
- Sandbox: Debian 12, AArch64 cross-target, QEMU TCG (`-M virt -cpu cortex-a72 -smp 4 -m 1024`).
- The app workspace (`/home/user/project`) is the **persisted** area (auto-committed). `/home/user/neo-os` and `/tmp` are **not** persisted.

## Chronological history

### Session 1 — Clone, build, run, viewer
- Cloned `https://github.com/Satanacio666/neo-os`; installed toolchain; built; booted headless → HolyC shell, 32 subsystems JIT-compiled.
- Built the **browser viewer** (`/neo-os`): a server-side RFB/VNC client decodes QEMU's framebuffer and streams PNG frames over SSE to a canvas; keyboard/mouse forwarded back via VNC; a UART panel tails/sends the PL011 serial; VM start/stop controls. Files (in the project, persisted): `src/lib/neo-os/{vnc,png}.ts`, `src/app/api/neo-os/{stream,input,status,serial,vm}/route.ts`, `src/app/neo-os/page.tsx`. Backing scripts (in the clone): `run-viewer-vm.sh`, `uart-bridge.mjs`, `uart-repl.py`.

### Session 2 — First compiler fix: frame-based locals
- **Bug:** all locals lived in shared global heap cells; recursion corrupted them. Repro: `I64 f(I64 n){I64 t=n; if(n<2) return t; return f(n-1)+t;} f(5);` returned **5**, should be **15**.
- **Root cause:** the frame machinery (`s_frame`, `frame_alloc`, `local_ref`, `emit_zero_slot`, `emit_frame_addr`) existed but was **never wired up** — `s_frame` was always NULL.
- **Fix:** set `s_frame` during function-body parse; prologue reserves a stack frame (`MOVZ X16,#n; SUB SP,SP,X16` — note the **extended-register** encoding `0xCB3063FF`; the shifted-register form is a silent no-op); declaration path frame-allocates non-array locals; array locals frame-resident; every lvalue/address/array/pointer/member site resolves via `lookup_var_ref`; added `is_array` to `var_type_t`.
- **Verified:** `f(5)=15`, `fib(10)=55`, struct-local recursion `=18`, arrays-in-functions `=12`.

### Session 3 — C pruning
- Deleted **23 dead `.c`** + **24 orphan `.h`** (subsystems reimplemented in `.HC`, never compiled): `drivers/gpu/*`, `drivers/input/*`, `gui/{render,shell,wm,font_ttf,font_ubuntu_mono}.c`, `kernel/arch/aarch64/{exceptions,gic,smp,timer}.c`, `kernel/bench/*`, `kernel/math/*`, `kernel/physics/physics3d.c`, `kernel/sched/sched.c`.
- Removed 5 empty dirs, `boot/build/`, unused riscv/x86 CRTs + linker scripts. Hardened the Makefile (`mkfs.vfat` detection + `check-tools`).
- Remaining C = the bootstrap (9 `.c` + `boot/uefi/*`).

### Session 4 — Deep audit + external research + first master plan
- 5 parallel explorers audited: docs (27 `.md`), render pipeline, shell/DolDoc/WM, compiler stack, kernel+drivers.
- Tavily configured; researched the canonical **TempleOS DolDoc** spec, **Zig** incremental compilation, and **IMGUI vs retained** design.

### Session 5 — Execution (later LOST in the reset)
- L0.2 DolDoc brace fix; L1.1 `&function`; L1.2 forward-struct two-pass; L1.3 WM-before-Shell; L1.4 unresolved-symbol diagnostic + 3 fixes; harness scripts. Golden gate PASS (49/49).

### Session 6 — THE RESET
- The sandbox was reprovisioned: `/home/user/neo-os` and `/tmp` wiped; apt toolchain removed. The **project + viewer survived** (committed in project git).
- **Recovered:** re-cloned `neo-os` at baseline `36ca4b0`; reinstalled the toolchain; re-applied **every** fix; rebuilt the harness; verified the golden gate PASS (50/50).

### Session 7 — Design brainstorm (no code)
- Reframed HolyGL as an **API with backends**; designed the **Unified Tile Pipeline** (tile jobs + providers: SIMD = kernel shape, SMP = core count, GPU = a provider; **no scalar fallback** since AArch64 mandates NEON).
- Expanded the vision: run any program/game via a porting ladder (native → recompiled → WASM → emulation); a `HolyPort` platform layer; a `Surface` abstraction; and a future **MCU cluster** as just another provider.
- Chose a new priority order: **P0 harness → P1 compiler → P2 pipeline → DolDoc → Shell → Benchmark → Self-host → (GPU/cluster)**.

### Session 8 — Re-execution of P0/P1
- **P0:** rebuilt the harness; golden gate works and accurately measures baseline.
- **P1:** re-applied all compiler fixes; **GOLDEN BOOT: PASS** (50/50, 0 undefined, 0 exceptions). Committed `P0`,`P1`; bundled to the project.

### Session 9 — Documentation (this)
- Created `docs/master/*` (this set) and prepared the project tarball.

## What "done" means per the end goal
1. Everything in **HolyC** except `boot/main.c` + `boot/uefi` (self-hosting).
2. One **Unified Tile Pipeline** (no duplicate rasterizers/fonts/damage/present).
3. A real **TempleOS-model DolDoc** (CDoc/CTree, full tag set, links/anchors/macros/forms/trees/windows-as-docs).
4. A **shell** that is a document producer + action executor (no cycles).
5. One **HolyGL-max benchmark**.
6. (Future) GPU provider + `HolyPort` + MCU-cluster provider.
