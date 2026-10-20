# NeoOS — VERIFIED Truth, Critique & Implementation Plan (v4)

> Every claim below was checked **against the actual code** (line-cited), not against other docs.
> This unifies the 25 original `docs/*.md` into one document of *checked truth* + critique + the
> file-by-file, system-by-system merge/dissolution plan + the complete tasklist.
> Method: 5 independent code audits (kernel, rendering, DolDoc/UI, compiler, drivers/bench/bootstrap).

---

## 1. All `.md` files — inventory & verdict

**Directives:** `AGENTS.md`, `SKILL.md`, `.agents/skills/neo-os-directives/SKILL.md` — *rules* (HolyC-first, minimal C, topological load order, zero stubs). **Verdict: valid, keep.**

**Original design docs (25, ~9,000 lines):** `neo_os_grand_forensic_dossier_and_sovereign_blueprint.md`, `neo_os_grand_consolidation_encyclopedia.md`, `neo_os_grand_architecture_manifesto.md`, `neo_os_architecture_specification.md`, `doldoc_sovereign_unified_continuum_master_specification.md`, `doldoc3_graphics_typography_sprite_spec.md`, `holygl_sovereign_unified_master_architecture.md`, `shell_doldoc_symbiosis_and_sovereign_compositor_blueprint.md`, `ultimate_dom_substitute_paradigm_spec.md`, `POST_DOM_OS_ARCHITECTURE_BLUEPRINT.md`, `complete_render_stack_master_evaluation.md`, `neo_os_consolidated_defect_record.md`, `OUTSTANDING_DEFECTS_AND_CODE_CRITIQUE.md`, `exhaustive_architectural_post_mortem.md`, `FUTURE_IMPLEMENTATIONS_MASTER_ROADMAP.md`, `ring0_embeddings_engine_manifesto.md`, `priority_implementation_plan.md`, `implementation_plan.md`, `consolidation_dossier.md`, `dossier.md`, `single_core_sovereign_master_audit.md`, `bench_empirical_analysis.md`, `audit.md`, `task.md`, `walkthrough.md`.

**Verdict: the docs are largely ASPIRATIONAL or SELF-CONTRADICTORY.** Recurring false claims (verified in §2): "windows dissolved into DolDoc", "shell IS a CDoc", "40 phases", "GetMemoryMap", "SMP rendering", "preemptive scheduler", "TrueType", "Compiler.HC self-hosting", stale LOC counts. The docs' own `neo_os_consolidated_defect_record.md` / `forensic_dossier` *acknowledge* most gaps — treat those as the honest subset; discard the marketing claims.

---

## 2. Verified truth, system by system

### 2.1 Compiler — two compilers, two tokenizers, one actually runs the OS
- **`compiler/jit_arm64.c` = 3,954 lines** (docs said 3,739 — stale). It is the **live compiler**; `boot/main.c:273/283` and `KernelInit.HC:25` call `jit_compile_and_run` for every module.
- **`apps/Compiler.HC` = 2,616 lines** (docs said 2,443). **F64 ✅ and inline `asm{}` ✅ are IMPLEMENTED** (docs claiming they're missing are stale). But it is **not self-hosting**: its 7 tests are *feature* tests and **run only when `g_kernel_booting==0`** (never at boot).
- **Two tokenizers** (`compiler/lexer.c` vs `Compiler.HC`'s `HcLexNext`) and **two `TOK_*` enums** (`lexer.h:6-83` enum vs `Compiler.HC:8-83` defines) — **numerically identical (0–70)**, so unification is mechanical. The 3rd (`Lexer.HC`) was deleted.
- **`Compiler.HC` is not memory-safe** — the bootstrap blocker:
  - `HcOpPush` (188-191) writes `g_hc_op_stack[256]` with **NO bounds check** → deep expressions corrupt adjacent globals (`g_hc_expr_float` sits right after). **This is the Render.HC crash.**
  - **10 unbounded `strcpy`** into 64-byte name buffers from a 256-byte token buffer (1214,1097,1336,1675,1707,1744,1901,1934,2372,2414).
  - **Silent caps that miscompile:** 32 structs (overflow returns index 0 → aliases struct 0), 16 members/struct, 64 locals, 128 funcs, 64 defines, 16 loop-depth (out-of-bounds `g_brk_count[16]`), frame clamped to 4080 B, `HcEmit` silently drops past 1,048,576 instrs.
  - **Missing constructs:** `#include`, table literals `{…}`, `auto` (tokenizes but not consumed → **potential hang**), expression/string global initializers, nested functions.
  - **No forward cell for globals** (uses `symbols_lookup` at compile time; the C JIT has `symbols_lookup_or_reserve`).
- **Dead C:** `jit_run_self_tests()` (never called), `emit_lsr`, `emit_b_cond_placeholder`, `patch_b_cond`.

### 2.2 Kernel core — mostly non-functional
- **Scheduler is NOT preemptive.** `TaskYield` (Sched.HC:161-203) only reassigns a pointer; `cpu_switch_context` (registered in `main.c:245`) has **zero callers**; no task is ever created. Docs "preemptive scheduler" = **FALSE**.
- **Timer is never armed.** `TimerInit` (Timer.HC:51-59) never writes `CNTP/CNTV_TVAL`; `TimerTick` is a counter; **no timer IRQ registered at boot** (only in `GicSelfTest`).
- **GIC:** no IRQ handler registered at boot; `GicRegisterHandler` has no external callers.
- **`GetMemoryMap` is NOT called.** `boot/main.c` uses `AllocatePages` for heap/JIT/stack. Docs claim = **FALSE**.
- **Two allocators:** the C `kernel/mem/kheap.c` is live (every `.HC` calls lowercase `kmalloc`); `KHeap.HC`'s `KMalloc/KFree` are **dead**.
- **Two symbol tables:** C `symbols.c` (1024 buckets, live) + `Symbols.HC` (256 buckets, fallback). Two `SYM_*`/canary constant sets.
- **Two HALs:** C `hal_platform.c` (live, 3 platforms) + `HalPlatform.HC` (separate cells, 5 platforms) — duplicated `g_hal_*`.
- **Trap-frame ABI: CORRECT** (`CTrapFrame` 272 B matches `vectors.S SAVE_ALL`); but `vectors.S` hardcodes `x3=1` so the BSOD is unreachable for kernel faults.
- **Duplicate globals:** `g_kernel_booting` in ~32 `.HC` files; `g_hal_gicd/gicc_base` (HalPlatform+Gic); `g_hal_timer_freq` (HalPlatform+Timer).
- **Dead:** `HalPlatformSelect`, most `HalGet*`, `TaskCreate/Exit/SetAffinity`, `SmpDispatch/WaitJob`, `GicDispatch`, `TimerGetTicks`, all `*SelfTest`.

### 2.3 Rendering — fragmented, partly fake
- **4 triangle rasterizers:** `gfx_draw_triangle_fill` (Render:529, fallback-only), `RasterTriangleZ` (RasterTile:58, **bench-only**), `TileRasterTri` (RasterTile:149, **DEAD**), `HolyGLDrawTriangleZ` (HolyGL:284, **live**, flat `z_avg`).
- **3 font engines:** Render's `gfx_draw_char` (live, 8×16 bitmap), `FontMono` (real bitmap but **mock "TrueType"** — SFNT header only, `mock_ttf[64]`), `FontVector` (real Bézier strokes). No `font_ttf.c`/`stb_truetype.h` exist (README lies).
- **2 damage systems** (Render bbox + Compositor bbox/tile-map) **+ WM boolean**; **~3 present paths** (swap-copy / Compositor / VirtIO-DMA). Not unified.
- **Z-buffer:** real per-pixel Z **exists only in the unused `RasterTile.HC`**; the **live 3D path uses per-triangle `z_avg`** (HolyGL:402-403, 352-354).
- **Textures:** UVs are stored (`HolyGL:439-440`) and **never sampled** — no texture object/sampler.
- **`GFX_MODE_SMP_TILED` is cosmetic** (a name string); `Smp.HC` has no render code. **"Gouraud" is flat** (`v0->color`). Docs "SMP tiled / Gouraud / TrueType" = **FALSE**.
- **Hardcoded:** 1024×768 (Render/VirtioGpu/Compositor), 1280×768 (HolyGL), tile 64, caps 32×20=640 (Compositor) vs 1024 (DolDoc).

### 2.4 DolDoc / UI — a character grid, not a document tree; cycles everywhere
- **DolDoc is a FIXED CHARACTER GRID** (`g_doc_chars[16384]`, `g_doc_fg/bg`, `g_doc_link_idx`), plus a parallel widget list and a separate bump-allocated "OmniTape". **No `CDoc`/`CTree`/`CDocEntry` anywhere.**
- **Tags actually parsed:** `FG, BG, LK, BT, PB, CB, TR, HR, PUSH, POP, CLEAR, ROW, COL, BOX, CARD, GLASS, SHADOW, SL, EQ, GRAPH, SP, SHADER, FONT/H1`. **Missing:** `$MA` macros, `$DA` forms, `$AN` anchors, `$ID` trees (the `$TR` "tree" has no children), word-wrap. `$SP` is repurposed to render a 3D mesh, not a bitmap sprite.
- **WM owns windows** (`g_wm_wins[8]`, 3 hardcoded windows); **DolDoc has no window concept** (`$WIN` absent). Docs "windows dissolved into DolDoc" = **FALSE**.
- **Cycles (proven call sites):** `DolDoc ⇄ Shell` (`shell_run_command` 2480/2490/2552; Shell reads `g_doc_chars`), `WM ⇄ Shell`, `WM ⇄ Compositor` (`wm_set_dirty`), `DolDoc ⇄ Compositor`. **DolDoc never calls WM.**
- **Fake telemetry:** WM prints literal `"60"` and `"4 Cores"`; Compositor seeds `fps=60`, `frame_time_us=12000`; uptime renders 3 digits (wraps at 1000 s).
- **`g_doc_dirty_mask` shift bug:** `1 << r` is 32-bit; rows 32–63 alias 0–31.
- **Dead:** `DolDocSelfTest`, `ShaderEvaluateGlass`, `CompositorDrawBox`, `CompositorQueryTileOwner`, `g_main_win/g_tool_win`.

### 2.5 Drivers — duplicate stacks; VirtioGpu genuinely buggy
- **VirtioGpu truncated commands: TRUE** — `RESOURCE_CREATE_2D` 40→32 (drops width/height), `TRANSFER_TO_HOST_2D` 56→48 (drops resource_id) (`VirtioGpu.HC:345/417`).
- **Two FS stacks:** `fs/redsea.c` (live, C) vs `apps/RedSea.HC` (loaded, symbol-name collision, different layout/timestamps).
- **Two block stacks:** `drivers/block/virtio_blk.c` (live) vs `apps/VirtioBlk.HC` (on normal boot **delegates to the C driver** — `VirtioBlkInit` early-returns if `DRIVER_OK`, so `vq_desc==0` → calls `virtio_read/write`).
- **Hardcoded virtio MMIO** duplicated in every driver + both HALs (`0x0A000000/0x200`).
- **Typing:** `U64`-as-pointer in `VirtioGpuSendCmd`/`VirtioBlk`; `%X`/`%d` for 64-bit.

### 2.6 Benchmark — 5 files, "40 phases" is nominal
- **5 entry points** (`HolyBenchmark`, `BenchCpu`, `BenchReport`, `Profiler`, `PerfOverlay`); only `HolyBenchmarkMain` is wired (shell `bench`), plus `bench_unified_*` driven by `WM.HC:971`.
- **"40 phases" = counter `% 40` over only 5 real engines** (`HolyBenchmark.HC:59`); the "8 variations" are unread. **`g_bench_mode` write-only.**
- **`BenchCpuMathNeon` is scalar** (name lies). Profilers duplicate sqrt/FPS/stddev.
- **Lua excised: TRUE.** **Bench autorun at boot: FALSE** (only `BenchUnifiedInit` runs).

### 2.7 Bootstrap
- `boot/main.c` seeds C symbols, loads `KernelInit.HC` on a 4 MB stack; **no GetMemoryMap**.
- `KernelInit.HC` loads **34 modules** (banner says "32" — wrong).
- C symbols are the real substrate (`kmalloc`, `symbols_*`, `doldoc_printf`, `jit_compile_and_run`).

---

## 3. Critique — the real problems (ranked)
1. **The compiler can't yet compile the OS** (`Compiler.HC` unbounded buffers + silent caps + missing constructs). *This is the #1 blocker.*
2. **The kernel is not a kernel**: no real scheduler, no armed timer, no registered IRQ, no memory map; two allocators/symbol-tables/HALs.
3. **The render pipeline is 4 rasterizers / 3 fonts / 2 damages / 3 presents, with a fake "SMP-tiled Gouraud" and `z_avg`** — and the only real per-pixel-Z + tiled rasterizer (`RasterTile`) is unused.
4. **DolDoc is not a document model** — it's a char grid with a tag subset, entangled in cycles with Shell/WM/Compositor; the "dissolved" docs are false.
5. **Duplicate C/.HC stacks** for FS, block, HAL, heap, symbols.
6. **Docs contradict the code** pervasively.

---

## 4. Consolidation / Dissolution Matrix (file by file, system by system)

| System | File | Action | Target |
|---|---|---|---|
| Compiler | `jit_arm64.c`, `lexer.c`, `table.c` | **RETIRE** after parity | `Compiler.HC` |
| Compiler | `apps/Compiler.HC` | **HARDEN** (bounds, caps→errors, `#include`) | sole compiler |
| Compiler | `TestJitP0.HC` | keep as tests; delete `jit_run_self_tests` (C) | — |
| Kernel | `KHeap.HC` | **DISSOLVE** → C `kheap.c` (keep stats shim) | one allocator |
| Kernel | `Symbols.HC` | **DISSOLVE** → C `symbols.c` | one table |
| Kernel | `HalPlatform.HC` | **DISSOLVE data** → C `hal_platform.c` (+2 platforms, timer freq) | one HAL |
| Kernel | `Timer.HC` | **FIX** (arm `CNTP_TVAL` + register IRQ) | real timer |
| Kernel | `Gic.HC` | **FIX** (dedupe bases, register timer IRQ) | real IRQ |
| Kernel | `Sched.HC` | **FIX** (wire `cpu_switch_context`, real run queue) | real scheduler |
| Kernel | `Smp.HC` | **FIX** (drop local fallback, per-core queues, delete copy-paste loops) | real SMP |
| Kernel | `Exceptions.HC` | **FIX** (vector `x3`, kill `while(1)__wfe`) | real faults |
| Rendering | `Render.HC` + `GfxBackend.HC` + `VirtioGpu.HC` + `Compositor`(damage/present) | **MERGE** | one **`GfxDevice`** |
| Rendering | `RasterTile.HC` + `HolyGL.HC` | **MERGE** | one tiled NEON rasterizer (promote `RasterTriangleZ`; kill `z_avg`, `gfx_draw_triangle_fill`, dead `TileRasterTri`) |
| Rendering | `FontMono.HC` + `FontVector.HC` + Render's `gfx_draw_char` | **MERGE** | one **`Fonts.HC`** (drop mock TTF) |
| Rendering | `Math3D.HC` | keep (behind HolyGL) | — |
| Rendering | `Physics3D.HC`, `Gears3D.HC` | keep as **clients** | — |
| Rendering | `Compositor.HC` (themes) | keep **themes only**; damage/present → GfxDevice | — |
| Documents | `DolDoc.HC` | **REWRITE** → CDoc/CTree + full tag set | document engine |
| Documents | `WM.HC` | **DISSOLVE** → DolDoc `$WIN$/$SPLIT$` | — |
| Documents | `Compositor.HC` | **DISSOLVE** (damage/present) | GfxDevice |
| Documents | `Shell.HC` | **THIN** → action executor over a CDoc (keep input/event loop) | — |
| Documents | `ShaderEditor.HC` | keep (already a pure doc) | — |
| Drivers | `apps/RedSea.HC` | **DISSOLVE** → C `redsea.c` (or vice-versa) | one FS |
| Drivers | `apps/VirtioBlk.HC` | **DISSOLVE** → C `virtio_blk.c` | one block |
| Drivers | `Keyboard.HC`, `Mouse.HC`, `VirtioInput.HC` | keep; dedupe MMIO constants | — |
| Drivers | `VirtioGpu.HC` | **FIX** (command lengths) then MERGE → GfxDevice | — |
| Benchmark | `HolyBenchmark.HC` + `BenchReport.HC` + `BenchCpu.HC` | **MERGE** | one suite (real 40 phases or relabel) |
| Benchmark | `Profiler.HC` + `PerfOverlay.HC` | **MERGE** | one telemetry |
| Bootstrap | `boot/main.c`, `boot/uefi/*` | keep (last C) | — |

---

## 5. The Bootstrap Paradox — verified hazards + safe order

**Paradox:** `Compiler.HC` must be compiled before it can compile anything → the C JIT does that → to retire the C JIT, `Compiler.HC` must be a pre-compiled blob. **No blob exists** (verified).

**Verified blockers to the flip (all in §2.1):** unbounded `HcOpPush`; 10 unbounded `strcpy`s; silent caps that *miscompile* (32 structs→alias 0, 16 members, 64 locals, 128 funcs, 16 loop depth); missing `#include`/table-literals/`auto`; no global forward cell; no blob.

**Safe order:**
1. **Harden `Compiler.HC`** (gate): bounds-check `HcOpPush`; bounded name copies; turn every silent cap into a hard error; add `#include`.
2. **Parity harness:** compile every `.HC` with both engines; diff. Keep the C JIT as reference.
3. **Flip** `KInitLoad` → `CompilerCompileAndRun`.
4. **Unify the tokenizer** (enums already identical 0–70 → generate both from one table).
5. **Pre-compile `Compiler.HC` → Stage-2 blob**; embed in `boot/main.c`; retire `jit_arm64.c`/`lexer.c`/`table.c`.
6. Retire the bootstrap C runtime (`kheap/symbols/hal_platform/virtio_blk/redsea`) as their `.HC`/C-unified versions become boot-load-bearing.

---

## 6. Parallel workstreams (disjoint files)
- **A Compiler** (gate): `Compiler.HC`, `KernelInit.HC`, `compiler/*`.
- **B Rendering**: `Render/GfxBackend/VirtioGpu/RasterTile/HolyGL/Font*/Compositor`.
- **C DolDoc/UI**: `DolDoc/WM/Shell/Compositor/ShaderEditor`.
- **D Kernel**: `HalPlatform/KHeap/Symbols/Sched/Smp/Gic/Timer/Exceptions` + C twins.
- **E Benchmark**: `HolyBenchmark/BenchCpu/BenchReport/Profiler/PerfOverlay`.
- **F Sweep**: typing, dup globals, dead code.
Each agent owns disjoint files; **the compiler (A) is the gate**; every step runs `golden-boot.sh` + manual UART/QEMU.

---

## 7. Complete Tasklist

**L0 Harness** ✅ (golden gate, UART, crash decoder, screenshot diff).
**L1 Compiler** — [x] F64, [x] asm, [x] `#include`(C JIT), [x] forward structs/`&fn`/frame locals. ⬜ **harden `Compiler.HC`** (op-stack + name buffers + caps→errors + `#include`), ⬜ parity harness, ⬜ **flip**, ⬜ unify tokenizer, ⬜ **Stage-2 blob**, ⬜ retire C compiler + bootstrap C.
**L2 Kernel** — ⬜ single allocator/table/HAL; ⬜ arm timer + register IRQ; ⬜ real scheduler (`cpu_switch_context`) + run queues; ⬜ SMP queues + drop local fallback; ⬜ `GetMemoryMap`; ⬜ exception `x3` fix; ⬜ dedupe globals.
**L3 Rendering** — ⬜ `GfxDevice` (Render+GfxBackend+VirtioGpu+damage/present); ⬜ one tiled NEON rasterizer (real Z, textures, SDF, shader VM); ⬜ `Fonts.HC`; ⬜ fix VirtioGpu lengths; ⬜ delete ~60 dead fns.
**L4 DolDoc** — ⬜ CDoc/CTree + per-char attrs + full tag set (`MA/DA/AN/ID/LK-types/word-wrap`); ⬜ `$WIN$/$SPLIT$`; ⬜ dissolve WM; ⬜ dissolve Compositor; ⬜ delete char grid/window table.
**L5 Shell** — ⬜ action protocol + command registry; ⬜ break cycles; ⬜ shell buffer as a CDoc.
**L6 Benchmark** — ⬜ one real suite (real NEON/Gouraud/texture/Z/SDF); ⬜ merge profilers; ⬜ relabel/implement the 40 phases.
**L7 Docs/hygiene** — ⬜ rewrite to verified truth; ⬜ typing sweep; ⬜ naming/single-source.
**L8 Future** — GPU provider; `HolyPort`+C→HolyC; `Surface`+`remote` → MCU cluster.

---

## 8. Invariants
Golden gate green after every change · C only for bootstrap · **no unbounded compiler buffers** · no UI cycles · persist after every green step · test manually (UART+QEMU).

---

## 9. Bottom line
The OS **boots and runs**, but nearly every headline claim in the docs is **aspirational**: the compiler doesn't self-host (unbounded stack), the kernel isn't preemptive (no timer/scheduler), the renderer is 4 rasterizers/3 fonts/`z_avg`/no textures, and DolDoc is a char grid entangled in cycles. The **single highest-leverage next action** is **hardening `Compiler.HC`** so it can compile the whole OS → flip → retire the C compiler; then the kernel fixes (L2) and the rendering unification (L3) can proceed in parallel.
