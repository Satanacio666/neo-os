# NeoOS — Updated Priorities & Fixed Checklist (v5)

> Re-listed after the deep compiler-debug round. Supersedes `02-PRIORITY-PLAN.md`'s checklist.
> Grounded in the **verified truth** (`01-VERIFIED-TRUTH.md`) + this session's findings.

---

## Priorities (re-listed, with live status)

| Pri | System | Status | Notes |
|---|---|---|---|
| **P0** | Harness | ✅ DONE | golden gate, UART, crash decoder, screenshot diff |
| **P1** | **Compiler (harden → self-host)** | 🔴 **IN PROGRESS — blocked** | hardening done; flip blocked by a **JIT codegen bug** |
| **P2** | Bootstrap minimization | ⬜ | C → `boot/main.c` + `boot/uefi` only |
| **P3** | Kernel correctness | ⬜ | allocator/table/HAL/sched/timer/IRQ/GetMemoryMap |
| **P4** | Rendering unification | ⬜ | one `GfxDevice` + one tiled rasterizer + one font |
| **P5** | DolDoc (real model + dissolution) | ⬜ | CDoc/CTree, `$WIN$`, dissolve WM/Compositor |
| **P6** | Shell | ⬜ | action protocol, registry, break cycles |
| **P7** | Benchmark | ⬜ | one real 40-phase suite |
| **P8** | Future (GPU / HolyPort / cluster) | ⬜ | deferred |

**The gate is P1.** Nothing below it can be trusted until the compiler compiles the whole OS.

---

## P1 — Compiler: what's DONE ✅
- Frame-based locals; `&function`; forward-struct two-pass; read-path late-binding.
- `#include` (C JIT); inline `asm { … }`; block comments; unresolved-symbol diagnostic + 3 fixes.
- **F64** in `Compiler.HC` (literals, locals, params, returns, arithmetic, comparisons, conversions).
- **P1.1 hardening**: `HcOpPush/Pop` bounds (stack 256→4096); **17 safe name copies**; **every silent cap → hard error** (`g_hc_error`); error flag wired into `CompilerCompileAndRun`; **per-module table resets**.
- **6 name-table copies bounded**; **`g_hc_arg_float[8]→[32]` guarded**.

## P1 — Compiler: the BLOCKER 🔴 (fixed checklist)
**Symptom:** `Compiler.HC` compiling `Render.HC` corrupts the heap; `g_hc_local_count` becomes `30836`.
**Localized:** the count cell (`0x7B057860`) is ~4 KB past `g_hc_local_names`' end (`0x7B056860`); the only write there is a bounded `HcSafeCopy(...,32)` → **the JIT miscompiles that access**. Also: the compiler **errors on >8-arg calls**.

### A. Fix the JIT codegen bug (THE blocker)
- [ ] **A1.** Disassemble the JIT-generated code for `HcAddLocalTyped` / `HcSafeCopy` / the `g_hc_local_names[g_hc_local_count*32]` access (crash-decoder + monitor `xp`).
- [ ] **A2.** Identify the miscompiled instruction (array-index scaling, global read, or the bounded-copy loop).
- [ ] **A3.** Fix `compiler/jit_arm64.c` codegen.
- [ ] **A4.** Verify: `Compiler.HC` compiles `Render.HC` with **0 heap corruption**.
- [ ] **A5.** Handle **>8-arg calls** (pass on the stack, or error clearly) — currently a silent hazard.

### B. Complete the compiler
- [ ] **B1.** `#include` **inside `Compiler.HC`**.
- [ ] **B2.** Diagnostics (`file:line`, type errors).
- [ ] **B3.** Fix `auto` (tokenizes but isn't consumed → hang).
- [ ] **B4.** Global forward cell (`symbols_lookup_or_reserve`) in `Compiler.HC`.
- [ ] **B5.** **Parity harness**: compile all **34 modules** with both engines, diff.

### C. Flip + retire
- [ ] **C1.** Flip `KInitLoad` → `CompilerCompileAndRun`.
- [ ] **C2.** Flip **module-by-module** in load order; golden gate after each.
- [ ] **C3.** Unify to **one tokenizer + one `TOK_*` enum** (enums already identical 0–70).
- [ ] **C4.** **Stage-2 blob**: pre-compile `Compiler.HC`; embed in `boot/main.c`.
- [ ] **C5.** **Retire** `jit_arm64.c`/`lexer.c`/`table.c` + dead `jit_run_self_tests`.
- [ ] **C6.** **Retire bootstrap C** (`kheap/symbols/hal_platform/virtio_blk/redsea`).

---

## P2 — Bootstrap minimization (fixed checklist)
- [ ] Keep `boot/main.c` (GOP, `AllocatePages`, seed **Stage-2 `Compiler.HC` blob**, hand over).
- [ ] Retire bootstrap C in dependency order once each `.HC`/unified version is load-bearing.
- [ ] Replace hardcoded heap/JIT/stack sizes with **`GetMemoryMap`**.
- [ ] **Exit:** only `boot/main.c` + `boot/uefi/*` in C.

## P3 — Kernel (fixed checklist)
- [ ] **One allocator** (dissolve `KHeap.HC` → C `kheap.c`, then port to `.HC`).
- [ ] **One symbol table** (dissolve `Symbols.HC` → C `symbols.c`).
- [ ] **One HAL** (dissolve `HalPlatform.HC` data → C; add all 5 platforms + timer freq).
- [ ] **Arm the timer** (`CNTP_TVAL_EL0`) + **register the timer IRQ**.
- [ ] **Real scheduler**: wire `cpu_switch_context` + run queues; `task_yield` from the tick.
- [ ] **SMP**: per-core queues; drop the silent local-execution fallback; delete `SmpWorkerLoop1/2/3`.
- [ ] **Exceptions**: fix `vectors.S` `x3`; kill `while(1)__wfe()`.
- [ ] Dedupe globals (`g_kernel_booting`×32, `g_hal_*`, `top_print_doldoc`).

## P4 — Rendering unification (fixed checklist)
- [ ] Merge `Render`+`GfxBackend`+`VirtioGpu`+Compositor-damage/present → **`GfxDevice`**.
- [ ] Fix `VirtioGpu` command lengths (40→32, 56→48) + real `ATTACH_BACKING`.
- [ ] **One tiled NEON rasterizer** (promote `RasterTile`'s real per-pixel Z; kill `z_avg`).
- [ ] Real **textures** (sample the UVs), **SDF**, **fragment-shader VM**; real NEON/SMP.
- [ ] Merge `FontMono`+`FontVector`+Render glyphs → **`Fonts.HC`** (drop mock TTF).
- [ ] Delete ~60 dead fns + write-only state.

## P5 — DolDoc (fixed checklist)
- [ ] Rewrite `DolDoc.HC` → **CDoc/CTree** + per-char attributes; delete the char grid.
- [ ] Full tag set (`MA/DA/AN/ID/LK-types/word-wrap`).
- [ ] `$WIN$`/`$SPLIT$`; **dissolve `WM.HC`**; **dissolve `Compositor.HC`**.
- [ ] Reactive cells; RedSea persistence; fix `g_doc_dirty_mask` shift.

## P6 — Shell (fixed checklist)
- [ ] Action protocol; command registry; **break all cycles**; shell buffer = a CDoc.

## P7 — Benchmark (fixed checklist)
- [ ] Merge to one suite; **real 40 phases** (real Z/textures/Gouraud/SDF/NEON); merge profilers.

## P8 — Future
- [ ] GPU provider; `HolyPort` + C→HolyC; `Surface` + `remote` → MCU cluster.

---

## Invariants
Golden gate green after every step · **C only for `boot/main.c` + `boot/uefi`** · **no unbounded compiler buffers** · **no JIT miscompiles** · no UI cycles · persist (commit+bundle) after every green step · test manually (UART+QEMU).

## The single next action
**A1 → A3**: disassemble the JIT-generated code for the `g_hc_local_names` access, find the miscompiled instruction, fix the JIT codegen. That unblocks A4 → B5 → the flip → everything below P1.
