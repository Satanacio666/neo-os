# NeoOS — Priority Plan (system by system) — minimal bootstrap, JIT-first

> Built on the **verified truth** (`01-VERIFIED-TRUTH.md`). Goal: a **minimal, perfect C bootstrap**
> (only `boot/main.c` + `boot/uefi/*`), with **everything else compiled and run by the HolyC JIT
> (`Compiler.HC`)**. Ordered so nothing is built on sand. Every step ends at a green golden gate.

---

## 0. Principle
The **compiler is the root**: it compiles everything. So it is hardened and self-hosted **first**.
Then the bootstrap is minimized, then each subsystem is fixed on a trustworthy base.
Dependencies point **down only**: compiler → kernel → device → pipeline → document → shell → apps.

## 1. Target end-state
- **C:** `boot/main.c` + `boot/uefi/*` only (UEFI entry + vendored gnu-efi). Nothing else.
- **Compiler:** `Compiler.HC` compiles every module; the C JIT is **gone**.
- **Kernel:** one allocator, one symbol table, one HAL; armed timer + registered IRQ; a real scheduler; `GetMemoryMap`.
- **Render:** one `GfxDevice` + one tiled rasterizer (real Z, textures, SDF) + one font system.
- **DolDoc:** a real CDoc/CTree document engine; windows are documents; one damage/present path.
- **Shell:** an action executor over a CDoc; no cycles.
- **Benchmark:** one real HolyGL-max suite.

---

## 2. Priority ladder

| Pri | System | Why now |
|---|---|---|
| **P0** | Harness | ✅ done — the lens for every step |
| **P1** | **Compiler (harden → self-host)** | the root; blocks everything |
| **P2** | **Bootstrap minimization** | shrink C to `boot/main.c` + `boot/uefi` |
| **P3** | Kernel correctness | the base the pipeline/document sit on |
| **P4** | Rendering unification | the spine for DolDoc/shell/benchmark |
| **P5** | DolDoc (real model + dissolution) | the document engine |
| **P6** | Shell | interaction layer over DolDoc |
| **P7** | Benchmark | proof over the unified pipeline |
| **P8** | Future (GPU / HolyPort / cluster) | deferred |

---

## 3. System-by-system detail

### P1 — COMPILER (the gate; do fully before anything else)
**P1.1 Harden `Compiler.HC`** (verified defects to fix):
- [ ] **Bounds-check `HcOpPush`/`HcOpPop`** (188-196) — heap-backed or hard-fail; never write past `g_hc_op_stack[256]`. *(This is the Render.HC crash.)*
- [ ] **Bound every name copy**: 10 `strcpy` sites (1214,1097,1336,1675,1707,1744,1901,1934,2372,2414) into 64-byte buffers from a 256-byte token buffer → use bounded copies.
- [ ] **Turn every silent cap into a hard error**: structs (32; `HcAddStruct` must not return 0), members (16), locals (64), funcs (128), defines (64), loop-depth (16; fix the OOB `g_brk_count[16]`), epilogue patches (64), frame clamp (4080), `HcEmit` drop (1,048,576).
- [ ] **Add `#include`** (mirror the C JIT's `expand_includes`); support **table literals** and **expression global initializers** if modules need them.
- [ ] **Fix `auto`** (tokenizes but isn't consumed → hang) — either support or hard-error.
- [ ] **Global forward cell**: use `symbols_lookup_or_reserve` (like the C JIT) so a module can reference a later module's globals.
**P1.2 Parity harness** — compile every one of the **34 modules** with both engines; diff behavior; the C JIT stays the reference until parity holds.
**P1.3 Flip** — `KInitLoad` (KernelInit.HC:15-31) → `CompilerCompileAndRun`; keep the C JIT only to seed `Compiler.HC`.
**P1.4 Unify the tokenizer** — the two `TOK_*` enums are **numerically identical (0–70)**; generate both from one table; delete the C tokenizer.
**P1.5 Stage-2 blob** — pre-compile `Compiler.HC` into a standalone image; embed in `boot/main.c`; load it directly.
**P1.6 Retire** — delete `jit_arm64.c` (3,954 L), `lexer.c` (547), `table.c` (81) + dead `jit_run_self_tests`, `emit_lsr`, `emit_b_cond_placeholder`, `patch_b_cond`.

### P2 — BOOTSTRAP MINIMIZATION (C → `boot/main.c` + `boot/uefi` only)
- [ ] Keep `boot/main.c` as the UEFI entry: GOP, `AllocatePages`, seed the **Stage-2 `Compiler.HC` blob**, hand over.
- [ ] Retire the bootstrap C **in dependency order** once each `.HC`/unified version is load-bearing: `kheap.c` → `KHeap.HC`; `symbols.c` → `Symbols.HC`; `hal_platform.c` → `HalPlatform.HC`; `virtio_blk.c` → `VirtioBlk.HC`; `redsea.c` → `RedSea.HC`.
- [ ] Replace hardcoded heap/JIT/stack sizes with `GetMemoryMap`-derived regions.
- [ ] **Exit:** the only `.c` in the build are `boot/main.c` + `boot/uefi/*`.

### P3 — KERNEL (make it a real kernel)
- **Allocator:** [ ] dissolve `KHeap.HC` → **one** allocator (C `kheap.c` now; port to `.HC` in P2). Remove `HEAP_CANARY`/`CHeapBlock` duplication.
- **Symbols:** [ ] dissolve `Symbols.HC` → **one** table (C `symbols.c`, 1024 buckets). Port `SymCanonicalMatch`/Pascal/snake helpers into it.
- **HAL:** [ ] dissolve `HalPlatform.HC` data → C `hal_platform.c`; add **all 5 platforms** + `g_hal_timer_freq`; one set of `g_hal_*` globals.
- **Timer:** [ ] arm `CNTP_TVAL_EL0`/`CNTV_TVAL_EL0`; register the timer IRQ (`GicRegisterHandler(27, TimerTick)`).
- **GIC:** [ ] dedupe `g_hal_gicd/gicc_base`; register the timer handler at boot.
- **Scheduler:** [ ] wire `cpu_switch_context` (already assembled+registered) and give tasks a run queue + `task_yield` from the tick.
- **SMP:** [ ] remove the silent local-execution fallback; per-core run queues shared with Sched; delete `SmpWorkerLoop1/2/3` copy-paste.
- **Exceptions:** [ ] fix `vectors.S` `x3` (real kernel faults must reach the BSOD); kill the `while(1)__wfe()` re-entrancy hang.
- **Globals:** [ ] dedupe `g_kernel_booting` (32 files), `g_hal_*`, `top_print_doldoc`.
- **Exit:** preemptive scheduling works; a timer IRQ fires; memory is discovered, not hardcoded.

### P4 — RENDERING UNIFICATION (one pipeline)
- [ ] **Merge → `GfxDevice`:** `Render.HC` + `GfxBackend.HC` + `VirtioGpu.HC` + `Compositor` damage/present. One target resolver, one damage system, one present path.
- [ ] **Fix `VirtioGpu` command lengths** (`RESOURCE_CREATE_2D` 40→32, `TRANSFER_TO_HOST_2D` 56→48) + real `ATTACH_BACKING` SG.
- [ ] **One tiled rasterizer:** promote `RasterTile.HC`'s `RasterTriangleZ` (real per-pixel Z); wire `HolyGLSubmitTriangle` to it; delete `HolyGLDrawTriangleZ` (`z_avg`), `gfx_draw_triangle_fill`, dead `TileRasterTri`/`TileClear`.
- [ ] **Real features:** per-pixel Z, **perspective-correct textures** (sample the UVs), SDF, a small fragment-shader VM; **NEON** (4 px/op); **SMP tiles** (actually dispatch).
- [ ] **Merge → `Fonts.HC`:** `FontMono` + `FontVector` + Render's `gfx_draw_char`; drop the mock SFNT parser.
- [ ] **Themes stay** in `Compositor` (or move to `GfxDevice`); delete its damage/present.
- [ ] Delete ~60 dead fns + write-only state (`raster_engine`, `tile_size`, `zprecision`, `culling`, tile map).
- **Exit:** a triangle, textured quad, SDF glyph, and shaded mesh all render through one path with real Z; `RasterTile` is the kernel.

### P5 — DOLDOC (real model + dissolution)
- [ ] **Rewrite `DolDoc.HC`** → **CDoc/CTree** of entries + **per-char attributes**; delete `g_doc_chars/fg/bg`, `g_doc_link_idx`, `g_hist_chars`.
- [ ] **Full tag set:** `TX CR SR CU TB CL PB PL LM RM HD FO ID FD/BD/FG/BG PT WW UL IV BK SX SY CM AN LK BT DA MA SP FI` — including `$MA` macros, `$DA` forms, `$AN` anchors, `$ID` trees, typed `$LK` links, word-wrap.
- [ ] **Windows are documents:** `$WIN$`/`$SPLIT$`; **dissolve `WM.HC`** (delete `g_wm_wins[]`, chrome, drag loop, hardcoded windows 2/3).
- [ ] **Dissolve `Compositor.HC`** damage/present into `GfxDevice`; delete its tile map.
- [ ] **Reactive cells** (generalize `DolDocPatchTarget`); RedSea document persistence; the DolDoc reference is a DolDoc.
- [ ] Fix `g_doc_dirty_mask` (`((U64)1 << r)`).
- **Exit:** a doc with text/link/button/slider/form/tree/3D-scene/shader renders + responds; no char grid; windows are docs.

### P6 — SHELL
- [ ] **Action protocol:** documents emit `Action{Run,Open,Set,Clone,Focus}`; the shell executes.
- [ ] **Command registry:** replace the if/else ladder with `shell_register_cmd` (the API already exists, unused).
- [ ] **Break all cycles** (`DolDoc→Shell`, `WM→Shell`, `WM↔Compositor`).
- [ ] **Shell buffer is a CDoc** (thin executor keeps input/event loop).
- **Exit:** no cycles; shell output is a document.

### P7 — BENCHMARK
- [ ] Merge `HolyBenchmark` + `BenchCpu` + `BenchReport` (+ merge `Profiler`+`PerfOverlay`).
- [ ] **Real 40 phases** (or relabel): per-pixel Z, textures, Gouraud (interpolated), SDF, real NEON; remove the write-only `g_bench_mode`; fix `BenchCpuMathNeon` to use NEON.
- [ ] Write `/BENCH_REPORT.TXT`.

### P8 — FUTURE
- [ ] GPU provider (virtio-gpu 3D / native); `HolyPort` + C→HolyC; `Surface` + `remote` → MCU cluster.

---

## 4. The minimal-bootstrap path (explicit)
```
UEFI firmware
  → boot/main.c  (GOP, AllocatePages, seed C symbols, load Stage-2 Compiler.HC blob)   [C, permanent]
  → Compiler.HC  (JIT) compiles every .HC module                                       [HolyC]
  → KernelInit.HC (topological load)                                                   [HolyC]
  → DolDocShellEventLoop()                                                             [HolyC]
```
C shrinks from **9 `.c`** → **1 `boot/main.c`** (+ vendored `boot/uefi/*`). Everything else is HolyC, compiled by the JIT.

## 5. Tasklist (condensed)
- **P1** harden `Compiler.HC` (op-stack, name buffers, caps→errors, `#include`, `auto`, forward cell) → parity → flip → tokenizer unify → Stage-2 blob → retire C compiler.
- **P2** shrink C to `boot/main.c` + `boot/uefi`; retire `kheap/symbols/hal_platform/virtio_blk/redsea`; `GetMemoryMap`.
- **P3** one allocator/table/HAL; arm timer+IRQ; real scheduler (`cpu_switch_context`); SMP queues; exception `x3`; dedupe globals.
- **P4** `GfxDevice`; one tiled NEON rasterizer (real Z/textures/SDF/shader); `Fonts.HC`; fix VirtioGpu; delete dead.
- **P5** CDoc/CTree + full tag set; `$WIN$` dissolve WM; dissolve Compositor; reactive cells/persistence.
- **P6** action protocol; command registry; break cycles; shell-as-CDoc.
- **P7** one real benchmark + telemetry; real NEON.
- **P8** GPU/HolyPort/cluster.

## 6. Invariants
Golden gate green after every step · **C only for `boot/main.c` + `boot/uefi`** · **no unbounded compiler buffers** · no UI cycles · persist (commit+bundle) after every green step · test manually (UART+QEMU).
