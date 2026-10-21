# SKILL — Working on NeoOS (the sovereign HolyC AArch64 OS)

> Distilled from an entire working session: every discovery, trap, and verified fact.
> Read this before touching the code. It will save you days.

## 0. What NeoOS is
A bare-metal **AArch64** OS. A small **C bootstrap** (`boot/main.c` + vendored `boot/uefi/*`) plus a **C JIT compiler** (`compiler/jit_arm64.c` + `lexer.c` + `table.c`) compiles **~34 HolyC `.HC` files** at boot into native Ring-0 code. It boots to a HolyC **DolDoc shell**.
**End goal:** everything in HolyC; C only for `boot/main.c` + `boot/uefi`; `Compiler.HC` self-hosts.

## 1. Verified facts (checked against CODE, not docs)
- The **C JIT is what runs the OS today**; `Compiler.HC` is a subset that is **not self-hosting**.
- **`Compiler.HC` has F64 and inline `asm{}` implemented** (docs claiming otherwise are stale).
- **The compiler errors on calls with >8 args** (args live in X0–X7). Any >8-arg call silently breaks compilation.
- **Kernel is not a kernel:** no preemptive scheduler (`cpu_switch_context` has zero callers), the timer is **never armed**, **no IRQ registered at boot**, **`GetMemoryMap` never called**, **two allocators / two symbol tables / two HALs**.
- **Rendering is fragmented:** 4 triangle rasterizers (2 dead), 3 font engines, 2 damage systems, ~3 present paths; the live 3D path uses a flat `z_avg` (real per-pixel Z exists only in the **unused** `RasterTile.HC`); **textures UVs are stored, never sampled**; `SMP_TILED`/`Gouraud`/`TrueType` are cosmetic/mock.
- **DolDoc is a fixed character grid** (`g_doc_chars[16384]`), **not** a CDoc/CTree; missing `$MA/$DA/$AN/$ID`/word-wrap; **WM owns windows** (3 hardcoded), DolDoc has no window concept; **cycles**: `DolDoc⇄Shell`, `WM⇄Shell`, `WM⇄Compositor`, `DolDoc⇄Compositor`.
- **VirtioGpu sends truncated commands** (`RESOURCE_CREATE_2D` 40→32, `TRANSFER_TO_HOST_2D` 56→48).
- **Duplicate C/.HC stacks**: `redsea.c`↔`RedSea.HC`, `virtio_blk.c`↔`VirtioBlk.HC`, `hal_platform.c`↔`HalPlatform.HC`, `kheap.c`↔`KHeap.HC`, `symbols.c`↔`Symbols.HC`.
- **`.HC` globals are heap-allocated by the JIT** (`kmalloc` per global) — so overflowing one array corrupts a *neighbor's heap block*.

## 2. The traps that cost the most time (learned the hard way)
1. **Bootstrap paradox:** `Compiler.HC` must be compiled before it can compile anything → the C JIT seeds it. To retire the C JIT, `Compiler.HC` must be a **pre-compiled blob** embedded in `boot/main.c`.
2. **Unbounded compiler buffers:** `HcOpPush` had **no bounds check** (`g_hc_op_stack[256]`); name copies used `strcpy` into 32/64-byte slots from a 256-byte token buffer. **Always bound.**
3. **>8-arg calls break the compiler** — keep calls ≤8 args, or fix the call path to spill to the stack.
4. **`g_hc_local_count` corruption:** compiling `Render.HC` corrupts the count (→30836) and the heap. The count cell sits **~4 KB past `g_hc_local_names`' end**; the only write there is a *bounded* `HcSafeCopy` → **the JIT miscompiles that access** (a codegen bug, still open).
5. **Silent caps miscompile** — 32 structs (overflow *aliases struct 0*), 16 members, 64 locals, 128 funcs, 16 loop depth. All now hard errors.
6. **Counts must reset per module** (`g_hc_func_count`/`struct_count`/`def_count`) — otherwise they accumulate.
7. **The sandbox can reset** and wipe paths outside the workspace. **Persist after every green step** (commit + `git bundle` into the project).

## 3. How to work (non-negotiable)
- **Golden gate after every change:** `scripts/golden-boot.sh` (rebuild → boot → assert shell + 32 subsystems + 0 exceptions + 0 undefined → JIT battery → screenshot). Must print `GOLDEN BOOT: PASS`.
- **Test manually via UART:** `scripts/uart-repl.py "expr" "cmd"`; serial tee at `/tmp/neo-os-serial.log`.
- **Debug via QEMU protocols:** monitor (`screendump`, `sendkey`, `info registers`, `xp /Ni ADDR`), VNC viewer (`/neo-os`), `scripts/crash-decode.py` (ELR/FAR/ESR + disasm).
- **Never leave the tree red.** The flip is a 2-line `KernelInit.HC` change — revert it after each experiment.
- **Persist:** `git add -A && git commit` then `git bundle create /home/user/project/neo-os.bundle --all`.
- **C only for `boot/main.c` + `boot/uefi`.** No new C without retiring something.

## 4. Key files
- Compiler: `compiler/jit_arm64.c` (3,954 L, live), `apps/Compiler.HC` (2,616 L, self-host target), `compiler/lexer.c`.
- Kernel: `apps/{HalPlatform,KHeap,Symbols,Sched,Smp,Gic,Timer,Exceptions}.HC` + C twins.
- Render: `apps/{Render,GfxBackend,VirtioGpu,RasterTile,HolyGL,FontMono,FontVector,Compositor}.HC`.
- UI: `apps/{DolDoc,WM,Shell,ShaderEditor}.HC`.
- Boot: `boot/main.c`, `apps/KernelInit.HC` (loads **34** modules; banner wrongly says "32").

## 5. Priorities
**P0 Harness ✅ → P1 Compiler (in progress; flip blocked by the JIT codegen bug) → P2 Bootstrap minimization → P3 Kernel → P4 Rendering unification → P5 DolDoc → P6 Shell → P7 Benchmark → P8 Future.**

**The gate is P1.** Fix the JIT codegen bug → parity → flip → retire the C compiler → everything below unlocks.
