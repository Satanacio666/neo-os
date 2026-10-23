# NeoOS — 01 REALITY AUDIT (verified claim-by-claim)

> Consolidation doc 2 of 5. This is the **verified reality** of the code, cross-checked against every claim in the
> 44 old docs. Tags: **[REAL]** verified in code today · **[PARTIAL]** exists but incomplete/wrong · **[STUB]**
> mock/placeholder/renamed-only · **[MISSING]** claimed but absent · **[GONE]** was real, since removed ·
> **[SUPERSEDED]** claim overridden by a later decision. Where the docs contradict each other, both are noted.

Current verified baseline (**HEAD P4.8, `main` tree clean** — updated 2026-10):
`GOLDEN BOOT: PASS` · `SELF-HOST: PASS` (Compiler.HC compiles itself) · `SELFTEST 87/87` · `PARITY 56/56`
(0 diff, 6 seed-skip) · `RENDER: PASS (golden=0xD28836F)` · `DETERMINISM: PASS (1 vs 4 cores identical:
0xD28836F)` · `TEXTURE: PASS` · `FONTS: PASS` · `3D: PASS` ·
`3D-GEARS: PASS (tris=800 ink=71410)` · `SHADING: PASS (phong=30 lum_max=182 gouraud=218)` ·
`SHADERVM: PASS (14/14)` (fragment-shader VM: NEON quad, derivatives, masking) ·
`MESH: PASS (v=8 tris=12 nrm=6 ink=28177)` (OBJ parse + quad triangulation + render) ·
`PTRSCALE`/`PTRSCALE2`/`ARRAY2D`/`KHEAP` **PASS** · **36** `.HC` subsystems ·
`PANIC GATE: PASS` · `CENSUS: PASS` (181 `.HC`→C calls) · `TWINS 5/5` · `SYMS 1532, 0 unresolved`.
(The older `65/65` / `p1-parity` / `71 identical` figures are historical — the P0.5 battery was expanded.)

**Repo inventory today (after P2):** `apps/*.HC` = **37** (36 loaded by `KernelInit.HC`, plus `SelfTest.HC`);
C in build = **6** (`boot/main.c`, `boot/seed/{lexer,table,jit_arm64,seed_fs}.c`,
`boot/runtime/{kheap,symbols}.c`); asm = **4** (`kernel/sched/switch.S`,
`kernel/arch/aarch64/{vectors,smp_entry,ffi_arm64}.S`). Old docs claimed 51 `.HC` / 43 `.c` / 215 files / 75k LOC
(inconsistent between `179/71,440` and `215/75,143`) — those counts are stale.

**P2 bootstrap [REAL]:** the C seed has **no filesystem and no block driver**. `boot/main.c` reads the OS's
own `.HC` sources from the FAT32 ESP via the UEFI firmware's FAT driver (`EFI_SIMPLE_FILE_SYSTEM_PROTOCOL`,
`boot/seed/seed_fs.c`); the block device (`VirtioBlk.HC`) and filesystem (`RedSea.HC`) are `.HC`-owned. C
`redsea.c`/`virtio_blk.c`/`hal_platform.c` were **deleted**. `boot/runtime/` = `{kheap.c, symbols.c}` (the
frozen seed allocator + symbol table). `.HC`→C census: **159** (all seed: `kmalloc`/`kfree`/`symbols_*`/
`jit_compile_and_run`).

**P2.7 compiler-only bootstrap [REAL]:** the C JIT compiles **only** `Compiler.HC`; the self-hosted compiler
compiles all **31** remaining `.HC` modules at runtime (`apps/KernelInit.HC`: `Compiler.HC` → `g_hc_ready = 1`
→ everything else). Verified by the golden gate (`SELFTEST 80/80`, `SELF-HOST: PASS`, `GOLDEN BOOT: PASS`).
The fix that unblocked it: pointer-element array indexing used the pointee struct size as the stride
(`CSymbol *g_sym_buckets[256]` strided by 92 instead of 8) — see doc 2 §P2.7.

**P3 kernel correctness [REAL]:** a **hardware timer IRQ** fires (EL1 virtual timer, PPI 27, `CNTV_TVAL_EL0`;
`TICK: PASS`, ticks ~1700); the scheduler is **preemptive** — the IRQ vector resumes whatever SP
`SchedOnTick` returns and new tasks get a full 784-byte trap frame (`SCHED: PASS`); **SMP** brings cores 1–3
online via PSCI and runs dispatched jobs (`SMP: PASS`); **kernel faults reach the BSOD** while REPL faults
unwind (`BSOD: PASS`); memory is discovered from the **UEFI memory map**; and the **sovereign handover** is
live — `.HC` `KHeap`/`Symbols` own `kmalloc`/`kfree`/`symbols_*` via SIC hot-patch (`SOVEREIGN: PASS`). See
doc 2 §P3. Not yet done: SMP **per-core run queues** (workers are job-mailbox based), a tickless idle, and
`.HC` ownership of the **C JIT seed** itself (still needed to compile `Compiler.HC`).

**P4.0 render gate [REAL]:** `RenderGoldenScene()` renders a fixed integer-coordinate scene into the back
buffer; `RenderHashBuffer()` is a 32-bit FNV-1a over the whole surface; `SelfTestRender()` runs it with IRQs
masked and asserts the frozen hash **`0x7E9DE351`** (`RENDER: PASS`, verified byte-identical across ≥3
reboots) — the regression + 1-vs-N determinism gate. `renderbench` reports `13063 tri/s, 9122 Kpix/s,
72 Mpix/s` (tile Z-raster + canvas clear). The full render dead-code inventory (43 dead fns, write-only
state, duplicate paths) is in doc 2 §P4.0. The render **fragmentation is still real** — P4.1–P4.8 do the
merging; P4.0 only froze the baseline. (Hash re-baselined to **`0xD28836F`** at P4.2.)

**P4.1 unified device [REAL]:** `GfxBackend.HC` + `VirtioGpu.HC` are merged into `apps/GfxDevice.HC` (one
target resolver `GfxDeviceTarget()`, one damage tracker, one `GfxPresent()`); the virtio-gpu **truncated
command bug is fixed** (`RESOURCE_CREATE_2D` 40, `TRANSFER_TO_HOST_2D` 56). Verified live: device active,
flushes return 0, `render gpu` + `GfxPresent` present without fault. Symbols 1330→1310.

**P4.2 one rasterizer + real Z [REAL]:** one full-screen 16-bit Z-buffer, Pineda edges, top-left rule,
per-pixel Z interpolation; `HolyGLSubmitTriangle` wired to `RasterTriangleZ`; `HolyGLDrawTriangleZ`/`z_avg`/
`avg_ndc_z`/`gfx_draw_triangle_fill`/`TileRasterTri`/`TileClear`/`TileResolve`/`RasterSetVertexZ`/`g_hgl_zbuf`
deleted. **This required a real Compiler.HC fix** (below) — a global pointer's pointee width was never
registered, so `U16 *p; p[i]` emitted an 8-byte `LDR` (read `0xFFFF` as `-1`) and `U32 *p; p[i]=c` an 8-byte
`STR` (wrong address). With it fixed the rasterizer passes `RASTER: PASS` (coverage + depth-rejection +
shared-edge seam) with **no workarounds**. **p4.2b NEON span [REAL]:** each scanline is head(scalar) |
body(NEON, 8 px/iter) | tail(scalar); `RasterSpanNEON` vectorizes the 3 biased edge tests, the 8-lane depth
compare (`CMHI.8H`), the masked Z store and the masked 32-bpp framebuffer store, with **exact 64-bit** Z
(8 scalar `SDIV`/block) so the output is bit-identical to the scalar path. Words assembled from
`scripts/raster_span.s`. Measured `renderbench` **2075 → 9262 tri/s (4.46×)**, `RENDER` hash unchanged
(`0xD28836F`).

**Compiler: global-pointer element width [REAL FIX]:** `Compiler.HC` now registers the pointee width for
global *pointer* declarations and keeps a bare pointer use at 8 bytes. Locked in by `SelfTestPtrScale`
(`PTRSCALE: PASS`, byte-level alias check) and `RasterBootCheck` (`RASTER: PASS`).

---

## A. Boot & bootstrap

| Claim (source) | Reality |
|---|---|
| UEFI entry, GOP 1024×768, PL011 UART, PE32+ `BOOTAA64.EFI` | **[REAL]** `boot/main.c` |
| Boot sequence: `kheap_init`→symbols→GOP→…→`smp_init`→`enable_interrupts`→event loop (dossier.md:19-42) | **[PARTIAL]** the *HolyC* boot is `KernelInit.HC` loading 34 modules in 6 stages; the old C sequence is superseded. `smp_init` ordering/race claim is **[GONE]** (SMP now handled in `.HC`). |
| `GetMemoryMap` used for heap sizing | **[REAL]** `boot/main.c` `boot_probe_memory()` (P2a, `7199c3e`). Old "C3 never called" is **[GONE]**. |
| 32 MB fixed heap / 4 MB JIT pool / 4 MB stack | **[SUPERSEDED]** now derived from `GetMemoryMap` (heap clamp free/4 16–64 MB, JIT pool 4–16 MB). |
| "Dual-tier: precompiled AOT C + JIT HolyC" (manifesto.md:88-97) | **[PARTIAL]** C is now only the bootstrap (9 `.c`); most drivers/WM/shell are `.HC`. |
| `ExitBootServices` called | **[MISSING]** not called (SASOS keeps firmware services). |

## B. Compiler (`apps/Compiler.HC` + `boot/seed/*`)

| Claim (source) | Reality |
|---|---|
| Stage-1/Stage-2 self-hosting HolyC compiler; 7/7 self-tests (task.md:55-67, defect record:171) | **[REAL]** `CompilerSelfTest` 7/7. |
| `class`/`auto`/`U0`/pointers NOT implemented (dossier.md:96-102, audit.md:25) | **[GONE]** all supported now (forward structs, `->`, typed pointers, `U0`). |
| No FPU/NEON codegen, no inline asm, no `#include` (forensic dossier:305-312, OUTSTANDING CMP-01..03) | **[GONE]** F64 codegen, inline `asm{}`, `#include` all present. |
| Duplicated tokenizer / `apps/Lexer.HC` dead | **[PARTIAL]** `apps/Lexer.HC` no longer exists; `TOK_*` unified to `boot/seed/tok.h` + `check-token-parity.py` (71 tokens). |
| `>8` args unsupported | **[REAL]** hard error (documented; matches C JIT). |
| **Compiler can compile itself** | **[REAL]** `hcrun Compiler.HC → 0` (self-host). Was NOT true before this engagement. |
| Compiler script-mode = C JIT (REPL/`run`) | **[REAL]** — FIXED. The REPL and `run <file>` now route through `CompilerCompileAndRun` when `g_hc_ready`, and the full JIT battery passes **65/65** under `Compiler.HC` (was 61/65). `p1-parity` PASS. |
| Compiler language coverage (script mode) | **[REAL]** `auto`, array initializer lists `{…}` (globals + locals, 1-D), `#include "file"` (VFS-spliced), forward structs, function-pointer calls, F64 struct expressions, and line-number diagnostics all work. |
| **Stage-2 standalone binary blob** (task.md Phase 16, FUTURE Task 5.4) | **[SUPERSEDED]/REMOVED** — master plan §4 rejects it; seed lives in `boot/seed/`. |
| C JIT (`jit_arm64.c`) decommissioned | **[PARTIAL]** it is still the live seed (Option A) that compiles `Compiler.HC` at boot, but it is **no longer the runtime REPL/`run` compiler**. |

## C. Kernel

| Claim | Reality |
|---|---|
| Preemptive scheduler; `sched_tick()` drives preemption | **[STUB]/[MISSING]** `cpu_switch_context` assembled+registered but has zero callers; timer not armed for preemption. Old C1 (empty `sched_tick`) is **[PARTIAL]** — the `.HC` `Sched.HC` exists but is not driving preemption. |
| SMP: 4 cores via PSCI, all active | **[PARTIAL]** PSCI bring-up exists; per-core run queues absent; old "secondaries run outside scheduler / spin" claims: **[PARTIAL]** (now `Smp.HC`). |
| One allocator | **[MISSING]** two allocators: C `boot/runtime/kheap.c` (live) + dead `KHeap.HC`. |
| One symbol table | **[MISSING]** C `symbols.c` (1024 buckets, live) + `Symbols.HC` (fallback). Old docs said 256 (dossier) vs 4096 (arch_spec) — both wrong; C is 1024. |
| One HAL; no hardcoded QEMU MMIO | **[PARTIAL]** (P2.1) `apps/HalPlatform.HC` is now the single owner of cache maintenance + board profiles + `g_hal_*`; the C HAL is reduced to a 31-line early-boot stub (`boot/runtime/hal_platform.{c,h}`) that only supplies the VirtIO MMIO aperture to the C block driver, and is retired at P2.2. Drivers still partly hardcode `0x09000000`/`0x08000000`/`0x0A000000`. |
| Timer: `CNTV_TVAL_EL0` armed, IRQ 27 registered | **[MISSING]** not armed for preemption. Old "100 Hz" vs "1 ms/1000 Hz" contradiction unresolved (arch_spec:214 vs dossier:186). |
| GIC-3 configured but `-M virt` defaults GIC-2 (dossier.md:190, audit.md:100) | **[PARTIAL]** QEMU now run with `gic-version=2`. |
| Exceptions reach BSOD; re-entrancy safe | **[PARTIAL]** old `x3=1`/`while(1)__wfe` issues partly fixed; `is_user_jit` recovery exists. |
| `g_kernel_booting` dedup | **[MISSING]** redeclared in many files. |

## D. Drivers & FS

| Claim | Reality |
|---|---|
| VirtIO-Block MMIO driver | **[REAL]** `boot/runtime/virtio_blk.c` (live) + `VirtioBlk.HC` (delegates). |
| RedSea 64-bit contiguous FS | **[REAL]** `boot/runtime/redsea.c` (live, 715 lines) + `RedSea.HC`. |
| RedSea reclaims sectors / dynamic `next_alloc_lba` / grow-allocates | **[MISSING]** old defects (watermark-only; ignores `sector_count`) — needs verification but reported unfixed. |
| VirtIO-GPU 2D | **[REAL]** (P4.1) — merged into `apps/GfxDevice.HC`; the two **truncated** commands are fixed (`RESOURCE_CREATE_2D` 40, `TRANSFER_TO_HOST_2D` 56). Verified live: device active, `VirtioGpuFlushRect/Full` return 0, `render gpu` + `GfxPresent` present without fault. 3D (virgl) deferred to P9. |
| `GFX_MODE_HW_ACCELERATED` real | **[PARTIAL]** (P4.1) — `GfxDeviceSetMode(GFX_MODE_GPU_HW)` now drives a working 2D DMA present path; it is not a 3D accel mode. |
| Mouse/tablet input | **[PARTIAL]** old "empty `mouse_poll`, static cursor" — now `Mouse.HC`/`VirtioInput.HC` exist; needs verification. |
| VirtIO-Net, audio, USB xHCI | **[MISSING]** never implemented. |
| FDT parser (Pi 4/5, RK3326) | **[MISSING]** QEMU-only. |

## E. Rendering

| Claim | Reality |
|---|---|
| HolyGL OpenGL 1.3/2.0 state machine, matrix stacks | **[REAL]** `HolyGL.HC` (subset). |
| Real per-pixel Z | **[PARTIAL]** live path uses flat `z_avg` (`HolyGL.HC:351-355`); real Z only in unused `RasterTile.HC`. |
| Textures (UV) | **[STUB]** `HolyGLTexCoord2f` discards UVs; stored never sampled. |
| NEON SIMD rasterizer | **[PARTIAL]** `RasterTile.HC` claims Pineda 64×64; live path scalar-ish; tile size claimed 64×64 (manifesto) vs 32×32 (arch_spec/impl_plan). |
| 4 rasterizers / 3 fonts / 2 damage / ~3 present paths | **[PARTIAL]** fragmentation real (master P4). |
| Gouraud / SDF / shader VM | **[REAL]** Gouraud + per-fragment Blinn-Phong in the one NEON kernel (P4.5); a bytecode fragment-shader VM with 2×2 NEON quad, `dFdx`/`dFdy`, execution masking, a Perlin/fBm/Mandelbulb/SDF library and a 4-lane raymarcher (P4.6, `ShaderVM.HC`). |
| Zero-RAM direct-to-VRAM | **[REAL]** (with tearing trade-off, documented). |
| `SMP_TILED` actually dispatched | **[PARTIAL]** often falls back to Core-0 execution. |
| 40-phase benchmark | **[MISSING]** old 16-phase/6-phase matrices; master P7 wants one 40-phase suite. |
| `BenchCpuMathNeon` is a scalar LCG (OUTSTANDING BEN-01) | **[REAL defect]** not fixed. |
| Synthetic telemetry constants `blit_us=1200/dma_us=400/wm_us=300` (BEN-02) | **[REAL defect]** not fixed. |
| PMU telemetry (`PMCCNTR_EL0`, `L1D_CACHE_REFILL`, `BR_MIS_PRED`) | **[MISSING]** |

## F. DolDoc / WM / Compositor / Shell

| Claim | Reality |
|---|---|
| DolDoc 3.0 CDoc/CTree, per-char attrs | **[REAL — P5]** `DolDoc.HC` is now a genuine CDoc/CTree: flat index-linked `CDocNode` entries (`DOC_TEXT/LINK/BUTTON/DATA/SLIDER/TOGGLE/PROGRESS/TREE/BITMAP/SCENE3D/SHADER/GRAPH/MACRO/INCLUDE/ANCHOR/WINDOW/SPLIT/EQ/RULE/CARD/BOX/GLASS/SHADOW/FONT`) with a contiguous text arena and a **per-character attribute word** `g_doc_attr[fg|bg]`. The char grid is gone. |
| Full two-letter tag set `TX CR SR … FI` | **[REAL — P5]** the whole set is parsed by `DolDocExecTag` (see doc 3 §2). |
| Windows are documents (`$WIN$`/`$SPLIT$`) | **[REAL — P5]** `$WIN$`/`$SPLIT$`/`$BLUR$`/`$ELEV$`; the desktop is a document (`DolDocDesktopDraw`). |
| Compositor dissolved into DolDoc | **[REAL — P5]** `Compositor.HC` deleted; `DolDocDamage*`/`DolDocPresent`/`DolDocDrawShadow`/`DolDocDrawGlass`/`g_comp` live in `DolDoc.HC`. |
| Shell = action executor over a CDoc; command registry | **[REAL — P6]** `shell_register_cmd` is live (FNV-1a hash table, O(1) `ShellFindCmd`); the if/else ladder is gone (registry dispatch, then `<verb>.HC`, then interactive JIT); shell output is a CDoc; the action protocol (`DOC_ACT_*`) executes button/link/widget actions. |
| No cycles (`DolDoc⇄Shell`, `WM⇄Shell`, `WM⇄Compositor`, `DolDoc⇄Compositor`) | **[REAL — P6]** `WM⇄Compositor` gone (both deleted); **`DolDoc → Shell` gone** — `DolDoc.HC` has 0 `shell_run_command`/`shell_poll` references; it enqueues actions and calls a Shell-registered pump through a function pointer (`g_doc_pump_cb`). The DAG is `Shell.HC → DolDoc.HC`. |
| `g_doc_dirty_mask` bug `((U64)1<<r)` | **[FIXED — P5]** now `((U64)1) << r`; the P5 self-test asserts row 40 sets bit 40. |
| `Showcase.HC` flagship doc | **[GONE]/[MISSING]** not in the current 34 apps. |
| `$EQ$`, `$GRAPH$`, `$SHADER$`, `$SP$`, CSprite/`SPT_MESH` | **[REAL — P5]** `$EQ$` (FRAC/SQRT/SUM/INT), `$GRAPH$`/`$PL$` oscilloscope, `$SH$`/`$SHADER$` viewport, `$SP$`/`$SX$`/`$SY$` 3D scene all render through the one pipeline. |

## G. Benchmark / telemetry / harness

| Claim | Reality |
|---|---|
| 16-phase scorecard, Phase 08 "13.5 FPS winner" | **[SUPERSEDED]** old matrix; superseded by planned 40-phase suite. |
| 6-config 3.0 s time-limited suite | **[SUPERSEDED]** same. |
| `/BENCH_REPORT.TXT`, `/BENCH_COMPARISON.TXT`, `/BENCH_PROFILER.LOG`, `/BENCH_SPIKES.LOG` | **[MISSING]** planned. |
| Harness `scripts/*.py` (`test_p8_holygl.py`, `test_p9_compiler.py`, `test_cold_boot.py`, …) | **[GONE]/[MISSING]** current harness is `golden-boot.sh`, `self-host-test.sh`, `p1-parity.sh`, `run-jit-golden.py`, `audit-symbols.sh`, `crash-decode.py`, `screenshot-diff.py`, `check-token-parity.py`. The 40 legacy `test_*.py` were **moved** (not deleted) to `scripts/_superseded/` in P0.5.10. |
| In-guest regression battery `apps/SelfTest.HC` + `selftest` builtin | **[REAL]** (P0.5) one command runs 80/80 checks in-guest; also reports in-process engine parity (`PARITY: 54/54`, 0 diff, 4 seed-skip), twin-liveness (`TWINS: 5/5`) and a symbol audit (`SYMS: 1390 symbols, 0 unresolved`). Host drives it via the `<<<NEO-DONE:selftest>>>` sentinel (`scripts/neo_uart.py`). Supersedes the host-side `run-jit-golden.py` battery. Limitation: once per boot (compiler re-entrancy). |
| 2-D arrays / `enum` / function-like `#define` / unterminated `struct` / global-`F64` subtraction | **[PARTIAL]/[MISSING]** found by the P0.5 expansion: **2-D arrays FIXED** (per-dimension row strides in `Compiler.HC`; `ARRAY2D: PASS`), `enum` and arg-macros return -1, an unterminated `struct {` is silently accepted, `F64 r = 0.0 - q;` returned 0. See doc 04. |

## H. Ideas/claims that are NOT implemented (research only)

| Claim | Reality |
|---|---|
| **Ring-0 INT8 embeddings "semantic dispatch"** (ring0 manifesto; 6-layer 384-dim transformer, `sdot`, 3-zone thresholds 0.82/0.60, `kernel_action_t`, `SemanticShellExecute`) | **[MISSING]** explicitly "0 weights / 0 inference code" (defect record C19). Research manifesto. |
| **Sovereign SDL** (~500-line SDL 1.2/2.0 ABI) | **[MISSING]** idea. |
| **Game ports** Quake/Half-Life/N64Recomp | **[MISSING]** idea. |
| **Android NDK / DEX→AArch64** | **[MISSING]** idea. |
| **Static recompilation** (MIPS→C99) | **[MISSING]** idea. |
| **Physical mobile SoC bring-up** (Snapdragon/Rockchip/PMIC/touch) | **[MISSING]** QEMU-only. |
| **MCU scaling** (RP2040/RP2350 Cortex-M) | **[MISSING]**; master's MCU target is RISC-V/Xtensa (different). |
| **OmniTape / Living Cell Matrix** (ultimate_dom spec; `omnitape_core.h`, `CMD_*`, `CTapeCmdHeader`) | **[MISSING]** design spec only; two conflicting `CMD_*` opcode tables exist in two docs. |
| **SIC live-patching engine** (`JitPatchImmediate`) | **[PARTIAL]** SIC cells exist (late-binding); the full literal-pool patch engine is a spec. |
| **Class inheritance / vtables, optimizing JIT (SSA+regalloc)** | **[MISSING]** |
| **WASM** (`WasmJit.HC`) | **[GONE]** not in current apps. |

## I. Things that are REAL and verified (positive reality)

- Self-hosting compiler; 34-module boot; golden gate; parity harness; self-host gate; 65/65 battery; token parity.
- F64 codegen + intrinsics; forward structs; global arrays; `GetMemoryMap`; `boot/seed` + `boot/runtime` layout.
- Zero-RAM mode; SMP bring-up; RedSea FS; VirtIO-Blk/GPU/Input modules exist; DolDoc subset renders.

---

## J. Key contradictions found in the old docs (full detail in doc 4)

- **Lua:** dossier/audit say "zero Lua code"; manifesto/arch_spec/task/priority_plan/walkthrough say "Lua vendored
  then excised Phase 5". Both true at different times → today **[GONE]**, no Lua.
- **Timer:** 100 Hz vs 1 ms/1000 Hz. **Symbol buckets:** 256 vs 1024 vs 4096. **Tile size:** 32×32 vs 64×64.
  **Benchmark:** 16 phases vs 6 configs; 3.0 s vs 15.0 s phases. **Core count:** single-core baseline vs 2C/4C.
  **FPS:** "43+ FPS" vs measured 5.4–13.5 FPS under TCG. **File/LOC counts:** 179/71,440 vs 215/75,143.
- **Stage-2 blob:** task.md/FUTURE require it; master plan removes it. **[SUPERSEDED]**.

---

## K. P0.6 / P0.7 / P0.7b / P4.3 / p4.3b — verified state (2026-10)

### P0.6 — BSOD panic-halt + fault telemetry — **[REAL]** (`f0a407c`)
A kernel panic used to re-execute the faulting instruction forever (`vectors.S` ignored the handler's X0
return and always `eret`). Fixed: `vectors.S` branches on X0 and spins in `panic_halt` on a kernel panic;
`Exceptions.HC` latches `halted`, keeps `in_fault=1`, emits `<<<BSOD:KERNEL>>>`/`<<<BSOD:DOUBLE>>>`/
`<<<EXC:RECOVERED>>>`; `Compiler.HC` keeps an on-demand JIT symbol map (`jitmap`); `crash-decode.py v2`
decodes ESR/ISS, symbolises `ELR_EL1`, supports `--gate`. Verified `PANIC GATE: PASS`.

### P0.7 — module truncation + lexer arena + allocator hardening — **[REAL]** (`0a53886`)
**Root cause of the boot failure unmasked by P0.6:** `KInitLoad` read every module into a **128 KB** buffer
with a `131071`-byte limit, **silently truncating** any module larger than 128 KB. Baseline `Compiler.HC`
(134 KB) was already truncated past `CompilerCompileAndRun` (offset 127483); module growth pushed that
function past the cutoff so it never compiled → unresolved forward refs → dead shell. The `[HCLX]`
diagnostic had been printing the *idle* HolyC pool (`used=48`), not the failing C seed heap (21 MB used).
Fixed: 1 MB module ceiling everywhere (`HC_MODULE_MAX`, `Shell.HC`, `HC_SRC_MAX`, C-JIT `INCLUDE_BUF_SIZE`);
dedicated lexer string arena (`HcStrAlloc`, chained 256 KiB chunks, BSS-first, bounds-checked); bounds-checked
the unchecked `g_hc_code` backpatch writes; null-checked global-array alloc; exact failure diagnostics in both
allocators; `SelfTestHeap`. `KHEAP: PASS`. Pointer arithmetic verified **byte-based** (Causa-2 ruled out).

### P4.5 — lighting & shading (per-fragment Blinn-Phong + Gouraud) — **[REAL]**

**Prerequisite — 3D transform matrix order — ROOT-FIXED.** `Mat4Translate/Scale/RotateX/Y/Z` pre-multiplied,
so all 3D transform sequences were composed wrong and **every 3D object collapsed** (the 2D golden scene and
identity-projection texture tests never exercised a sequence, hiding it). Fixed to post-multiply (GL
semantics): a lit HolyGL cube now renders through the one rasterizer (`3D: PASS`, `ink=109078`),
`RENDER 0xD28836F` unchanged, and a `3D` gate was added to `golden-boot.sh`.

**Gears geometry — ROOT-FIXED (compiler, not geometry).** The gears drew 366 tris / 644 px while `z=w*0.5`
stayed correct. Root cause: `HcReset()` cleared the per-unit function table every unit, so a call to an
**F64-returning function defined in an earlier unit** (`Gears3D` → `MathCos`) was treated as returning an
integer; `HcEmitPromoteFloat` emitted `scvtf d0, x0` on the double's raw bits, so `r * MathCos(a)` was
garbage. Fixed with a **persistent `name → returns-F64` table** + `HcPrescanFuncs` (see doc 04 D11). Gears now
render **800 tris / 71410 px** (`3D-GEARS: PASS`), visually confirmed in the WM desktop.

**Smooth shading — REAL, in the ONE kernel.** `CRasterSpan.gmode` (0xF8) selects flat (0, byte-identical
solid path → golden hash untouched), **Gouraud** (1, affine per-vertex colour), or **per-fragment Blinn-Phong**
(2). After the shared coverage/depth stage, the kernel interpolates colour/normal from affine `f32`
accumulators (advanced `8*delta` per block, fanned over 8 lanes with `FMLA`), normalizes per fragment with
**`FRSQRTE` + one `FRSQRTS` Newton step**, evaluates `N·L` + `N·H^16` + `amb+diff·N·L`, and gamma-corrects
(`sqrt` → sRGB). All NEON in the span body; head/tail (<8 px/row) use a scalar mirror. `HolyGLSubmitTriangle`
rotates per-vertex normals into view space (`HolyGLViewNormal`) and feeds the rasterizer; `RenderGoldenScene`
forces flat. `SelfTestShading` → **`SHADING: PASS (phong=30 lum_max=182 gouraud=218)`**; a normal-swept quad
renders a smooth gradient with a specular highlight (verified by screendump).

### P4.6 — fragment-shader VM (2×2 NEON quad) — **[REAL]**

`apps/ShaderVM.HC` is a **register bytecode VM** evaluated per **2×2 fragment quad**: 16 registers × 4 lanes
(SoA), a 4-word instruction `[op,a,b,c]`, and a fixed ISA (arithmetic, `len`/`dot`/`mix`/`clamp`/`smooth`,
`fragx`/`fragy`/`time`, `dfdx`/`dfdy`, `if`/`else`/`endif`, `jmp`/`jnz`/`jz`, library ops, `out`). The
arithmetic core is **128-bit NEON** (`ShaderOp4`, hand-encoded in `scripts/shader_quad.s`, 75 words) so one
instruction applies to all four lanes at once. `dFdx`/`dFdy` use lane permutation; `if` builds a 4-bit
per-lane predicate intersected with the current mask (**execution masking**) with a mask stack for `else`.
The **built-in library** (native fast paths) provides Perlin gradient noise, multi-octave fBm, a Mandelbulb
distance estimator (with `atan2`/`acos`/`log`), and SDF primitives; a **text assembler** compiles custom
shaders into the same bytecode. Built-in programs: animated gradient, shaded 2-D SDF disc, Perlin fBm, and a
**masked Mandelbrot** (real per-lane divergence). A native **4-lane raymarcher** (`ShaderRaymarchQuad`)
marches 4 px/iteration against a sphere+torus+plane whose field is evaluated 4 lanes at a time through
`ShaderOp4`, with a finite-difference normal + Blinn-Phong + gamma. DolDoc routes the `$SHADER$` types
`vm`/`sdf`/`noise`/`mandel`/`bulb` to it (direct call, no census growth); `shader 9` shows the live gallery
and `shadervm` shows the raymarch. `SelfTestShaderVM` → **`SHADERVM: PASS (14/14)`**; visually confirmed.

**Root fixes it surfaced (compiler).** Two latent `Compiler.HC` bugs blocked local F64 arrays: (a) a **local
array's element floatness** was never set (inherited from the *previous* declaration), so `F64 a[3]; a[0]=1.0`
stored/loaded raw integer bits; (b) indexing a **pointer local** (`F64 *p; p[i]`) used the pointer's own
floatness (always 0) instead of the **pointee**. Both are fixed at the root via `g_hc_decl_float` /
`g_hc_decl_elem_float` / `g_hc_local_elem_float`; regression `f64_local_array_assign` (`0x4010000000000000`).
`RENDER 0xD28836F` untouched (bit-exact); census unchanged (181).

### P4.7 — OBJ mesh ingestion — **[REAL]**

`apps/Mesh.HC` is a **streaming Wavefront OBJ parser** + renderer. It handles `v`/`vn`/`vt`/`f`, negative
(relative) face indices, the `v/vt/vn`, `v//vn`, `v/vt`, `v` corner forms, and n-gon fan triangulation (a quad
→ 2 tris); `#`/`o`/`g`/`s`/`mtllib`/`usemtl`/`l`/`p` are ignored. Faces without normals get a computed face
normal so the mesh is always lit. Rendering goes through the **ONE pipeline** — HolyGL immediate mode →
`HolyGLSubmitTriangle` → `RasterTriangleZ` (P4.5 per-fragment Blinn-Phong when `GL_LIGHTING` is on); there is
no second rasterizer. Storage is fixed-capacity `CMesh g_mesh` globals (no `kmalloc` sites → census unchanged,
181). The embedded unit cube (top face uses negative indices) makes `$SP,type="mesh"` work with no file;
`obj <file>` loads one from RedSea (`redsea_read_file`; `.obj` files in `apps/` are auto-packed by `mkredsea`).
`MeshSelfTest` → **`MESH: PASS (v=8 tris=12 nrm=6 ink=28177)`**; visually confirmed by the `mesh` screendump.

**Root fixes it surfaced (compiler, D14 + D15).** (D14) `HcAddLocalTyped` returned the existing slot on a
**redeclaration without updating its type flags**, so `F64 b` in the `vn`/`v` branches made the later `I64 b`
index load as a double — leaving `x0 = &b` — and the index code multiplied that **address** by the element
size, a wild ~18 GB read (`EC 0x25`, `ESR 0x96000005`). Now the type metadata is refreshed on redeclaration
(single-pass, so earlier uses keep the old type); regression `redecl_float_int_index`. (D15) the
**struct-member array parser** accepted only a single number, so `I64 fv[MESH_MAX_T * 3]` recorded 512 elements
and corrupted every following offset (`fni`/`ft`) and `sizeof(CMesh)`; both `Compiler.HC` and the C seed
(`boot/seed/jit_arm64.c`) now fold `N*M`/`N+M` like the local/global array parsers; regression
`member_arr_compound_dim`. See doc 04 D14/D15.

### P4.8 — merge, delete, verify — **[REAL]**

The rendering stack is now a single path with **one damage tracker, one present, one theme owner**. The
compositor's duplicate bounding box (`g_comp.dmg_*`) and its write-only KolibriOS tile maps
(`tile_dirty_map`/`win_tile_map`) are gone: `CompositorDamage{All,Rect,Window}` forward to `GfxDeviceDamage`
(Render's `g_canv.dirty`), and `CompositorPresent` reads that same rect via `RenderDirtyActive()` /
`RenderDirtyBounds()` before `GfxPresent`; WM's redraw predicate uses `RenderDirtyActive()`. The theme palette
moved out of `Compositor.HC` into a new `apps/Theme.HC` (Stage 6, before Compositor; **36** subsystems) so it
survives P5's dissolution of the compositor. A batch of verified-dead functions was removed across
`Compositor.HC`/`Render.HC`/`HolyGL.HC`/`RasterTile.HC` (see doc 04 D16); the `.HC`→C census stays 181. The
new **`scripts/determinism-gate.sh`** boots the OS on 1 core and on N cores and asserts the golden-frame hash
matches — `DETERMINISM: PASS (1 vs 4 cores identical: 0xD28836F)` — wired into `golden-boot.sh`. Visually
confirmed: the desktop renders and `theme latte` recolours it live.

### P4.4 — unified `Fonts.HC` + boot-baked AA atlas — **[REAL]**
`FontMono.HC` + `FontVector.HC` merged into one `apps/Fonts.HC` (both deleted; `KernelInit` Stage 2 loads only
`Fonts.HC`). The **bitmap** 8x16 path is kept (delegates to Render's unchanged `gfx_draw_char`, so the golden
hash is preserved). The **95-glyph quadratic-Bezier outline** engine bakes, at boot, a **4x-supersampled
24x24 coverage** per glyph, packed into one **256x256** power-of-two ARGB atlas (alpha = coverage). Text is
composited by a **bilinear coverage read** straight into the framebuffer (clip-safe) — smooth anti-aliased
scalable glyphs. `FontsSelfTest` → **`FONTS: PASS`** (atlas baked, metrics, a real 80-px AA composite).
Legacy `FontVectorDrawString`/`MeasureString` names are kept (DolDoc late-binds to them).

### P4.3 — textures / perspective / filtering / blend — **[REAL]** (`51a9c68`)
`CTexture2D` pool + `glGenTextures/glBindTexture/glTexImage2D/glTexParameteri/glBlendFunc` (+
`GL_TEXTURE_2D`/`GL_BLEND`), per-vertex `u/W,v/W,1/W`, a `RasterPixelTextured` span dispatched from the **one**
`RasterRow` (no parallel scalar rasterizer), NEAREST/LINEAR (bilinear, weights sum to 256), REPEAT/CLAMP,
exact `div255` alpha blend, and `RasterDisableTexture()` on the 2D golden path. `SelfTestTexture`
(nearest quadrants / bilinear centre / perspective row / alpha blend) → **`TEXTURE: PASS`**;
**`RENDER 0xD28836F`** bit-exact.

### p4.3b — NEON textured span + D7 root fix — **[REAL]**
The textured span now runs through the **same** `RasterSpanNEON` kernel (branch on `CRasterSpan.tex_ptr`); the
solid path is byte-identical so **`RENDER 0xD28836F` is unchanged**. Per active 8-pixel block: NEON coverage +
`CMHI.8H` depth → active mask; a compact mask-skipped 8-lane loop computes perspective-correct `u,v` with
**exact 64-bit `SDIV`** (per-block `numU/numV/den` from that block's `w0,w1,w2`), gathers texels (scalar, since
**AArch64 NEON has no gather**), and does **NEON** bilinear (`UXTL`/`UMULL`/`UMLAL`/`SHRN`), modulate (exact
`/255`) and alpha blend (exact `+127` then `/255`). `SelfTestTexture` 4/4 → **`TEXTURE: PASS`**. `renderbench`
adds a `Textured` throughput line (~3493 tri/s, ~277 Kpix/s under QEMU TCG).

**D7 root fix (no workaround).** `Compiler.HC` now carries each struct member's **pointee/element width**
(`g_hc_member_elem_bytes`, published via `g_hc_found_member_elem` to respect the 8-arg cap). Indexing a pointer
member (`g_rtex.data[k]`, `U32 *`) strides by 4 and emits `LDR W`; the typed-local workaround in `RasterTile.HC`
was deleted. Regression `SelfTestStructPtrScale` → **`PTRSCALE2: PASS`** + golden case `struct_member_ptr_scale`.

**Two compiler root bugs were found and fixed on the way (the real blockers):**
1. **Mixed I64/F64 arithmetic** (`apps/Compiler.HC`): the float path did `fmov d0,x0`/`fmov d1,x1`,
   reinterpreting an integer operand's bits as a double. So `F64 half_w = g_hgl.vp_w * 0.5` was a denormal
   ~0 → **every HolyGL triangle collapsed to (0,0)**; 3D rendering was silently broken (the 2D golden scene
   uses `RasterTriangleZ` directly, masking the bug). Fixed with `HcEmitPromoteFloat` (SCVTF the integer
   operand), applied to `HcParseMultiplicative/Additive/Relational/Equality`.
2. **Struct-member pointer indexing stride 8** — **root-fixed in p4.3b** (see above; was a typed-local workaround).
The earlier WIP **BSOD** was self-inflicted: a 9-argument `doldoc_printf` inside the rasterizer exceeded the
8-arg limit → `RasterTile.HC` failed to compile → **dangling** function symbols (published before body-parse)
→ `HolyGLInit()` jumped into overwritten code. Rule: **never print from inside the rasterizer, never exceed
8 args.**

**Research briefs** (read-only, external best-in-class) added: `docs/research/*.md` (see doc 03 §11).


---

## L. Upstream salvage audit — the original C repo (`36ca4b0`) vs current HolyC

> Merged from the former `docs/05-UPSTREAM-SALVAGE-AUDIT.md` (P7.0 doc consolidation; the repo rule forbids extra `docs/*.md`). Every claim names the upstream `file:line` and the current equivalent.

## 1. Provenance — what the "upstream" actually is

- **There is no third-party upstream.** `36ca4b0` ("docs & core: master forensic architectural audit, defect
  catalog & sovereign roadmap") is **also the root commit of the current repo** (`git log --oneline --reverse`
  → `36ca4b0`, `a031e76`, `0d77b7f`, …). `/tmp/neo-upstream` is therefore the **pre-HolyC-migration original**
  of this same project; the current repo is its HolyC migration.
- **Docs are preserved, byte-for-byte.** All **25** upstream `docs/*.md` are byte-identical to
  `docs/_superseded-old-docs/root/*.md` (`diff -q` over every file: 0 differences; both directories contain
  25 `.md`). *(A prior note said 24; the verified count is 25.)* The migration dropped none of them.
- **Files DELETED during the migration (the salvage surface):**
  - the entire `compiler/` C tree (`jit_arm64.c/.h`, `lexer.c/.h`, `table.c/.h`);
  - `drivers/{block,gpu,input}/*` (`virtio_blk`, `gfx_backend`, `virtio_gpu`, `keyboard`, `mouse`,
    `virtio_input`);
  - `fs/redsea.c/.h`;
  - `gui/{render,wm,shell,font_ttf,font_ubuntu_mono}.c` + `gui/stb_truetype.h`;
  - `kernel/{arch,bench,math,mem,physics,sched,symbols}/*.c` (the whole C kernel);
  - **21 HolyC apps** (`Bench, Compositor, Editor, Filer, FontMono, FontVector, GfxBackend, HolyBenchmark3D,
    HolyGLTest, Lexer, Menu, Showcase, SmpDemo, StdLib, Table, Top, WM, WasmJit, calc, fact`, plus the
    `VirtioGpu.HC` app). Verified: none of these `.HC` exist in `apps/` today.
- **Files ADDED since (the migration's gains):** `apps/{Fonts,Mesh,SelfTest,ShaderVM,Theme}.HC` (all verified
  present); `boot/seed/*` (`seed_fs.c/.h`, `tok.h`, the frozen `jit_arm64/lexer/table` C seed);
  `boot/runtime/*` (`kheap.c/.h`, `symbols.c/.h` — the only surviving kernel C); the harness scripts
  (`scripts/golden-boot.sh`, `self-host-test.sh`, `p1-parity.sh`, `determinism-gate.sh`, `census-c-runtime.sh`,
  …); and `tests/` (`census-baseline.txt`, `jit_golden/`).
- **What survives in C today:** `boot/main.c` + `boot/seed/*` + `boot/runtime/{kheap,symbols}.c` +
  vendored `boot/uefi/*`. Everything else in the original C tree is salvage material only.

---

## 2. Area A — Compiler / JIT / seed / boot / fs / kernel C

| upstream `file:line` | what it is | current HolyC equivalent | action |
|---|---|---|---|
| `compiler/jit_arm64.c` (3739 L) | the original C JIT/compiler | `boot/seed/jit_arm64.c` (3986 L) + `apps/Compiler.HC` (3819 L) | **REFERENCE** |
| `compiler/jit_arm64.c:799` `jit_optimize_peephole` | 3-pass peephole: stack-roundtrip collapse → `MOV`+`NOP`, dead `MOV Xn,Xn`→`NOP`, `ADD Xd,Xd,#0`→`NOP` | **absent from `apps/Compiler.HC`** (grep `peephole` = 0); the C seed still carries it (`boot/seed/jit_arm64.c:800`) | **PORT** |
| `compiler/jit_arm64.c:752` `can_collapse_stack_roundtrip` | branch-target-safety scan (`B`/`B.cond`/`CBZ/CBNZ`/`BL`/`BLR`/`SVC`/`RET` + register-touch) | absent | **PORT** |
| `compiler/jit_arm64.c:713` `insn_touches_reg_or_sp` | decodes whether an insn reads/writes a reg or SP | absent | **PORT** |
| `compiler/jit_arm64.c:709-711, 869-876` | peephole counters + `[JIT OPT]` print | absent | **PORT** |
| `compiler/jit_arm64.c:1042-1064` | F32 GL marshaling: `is_holygl_float_func` (`glVertex3f`…`glClearColor`) + `fmov`/`fcvt s,d` into **S0–S7** | **obsolete** — `apps/HolyGL.HC` takes **F64/D0–D7** (`HolyGLVertex3f(F64…)`, etc.) | **DISCARD** |
| `kernel/arch/aarch64/smp.c:8-57` | `EFI_MP_SERVICES_PROTOCOL` struct + GUID | none | **PORT** |
| `kernel/arch/aarch64/smp.c:115, 171-185` | `uefi_ap_trampoline` + `StartupAllAPs` — the **first** AP bring-up path | `apps/Smp.HC` only has PSCI (`PSCI_CPU_ON_64`, `apps/Smp.HC:5,144`) | **PORT** |
| `kernel/arch/aarch64/smp.c:187-199` | PSCI `CPU_ON` fallback via HVC | `apps/Smp.HC:144` (`psci_call_hvc`) | **NONE** |
| `kernel/sched/sched.c:51` | **64 KB** task-stack floor ("full C runtime & printf safety") | `apps/Sched.HC:164` clamps to **4096** | **REFERENCE / RAISE** |
| `kernel/arch/aarch64/gic.h:42` | `MAX_GIC_INTERRUPTS 1024` | `apps/Gic.HC:23` = **128** | **REFERENCE / RAISE** |
| `kernel/arch/aarch64/ffi_arm64.S` (`arm64_ffi_call`) | generic FFI call stub; **byte-identical** to ours (`diff` = 0) | `kernel/arch/aarch64/ffi_arm64.S`; **zero callers** in either tree | **DISCARD / repurpose** |
| `kernel/sched/switch.S` (`cpu_switch_context`) | context-switch; **byte-identical** to ours (`diff` = 0) | `kernel/sched/switch.S`; registered in `boot/main.c:298` but **no runtime caller** | **DISCARD / repurpose** |
| `fs/redsea.c` (715 L) | FS: **no** CRC, **no** uberblock, **no** atomic commit | `apps/RedSea.HC` is ahead (has CRC + uberblock + atomic commit) | **NONE** |
| `kernel/mem/kheap.c`, `kernel/symbols/symbols.c` | C allocator + symbol table | `apps/KHeap.HC`, `apps/Symbols.HC` (sovereign owners) | **NONE** |
| `boot/main.c`, `boot/uefi/*` (AArch64) | UEFI bootstrap | ours is equivalent or ahead (P2) | **NONE** |
| `boot/uefi/crt_riscv64.c`, `crt_x86_64.c`, `elf_riscv64_efi.lds`, `elf_x86_64_efi.lds` | multi-arch stubs | none (AArch64-only) | **DISCARD** |

**Notes / corrections.**
- *Compiler superset.* Our seed C (`boot/seed/jit_arm64.c`, 3986 L) is larger than the upstream C (3739 L) and
  adds `#include`, block comments, inline `asm{}`, a struct pre-scan, frame-local arrays, and forward-ref SIC
  var cells. The **only** compiler feature present in the upstream/seed C JIT but **missing from the
  self-hosted `apps/Compiler.HC`** is the peephole pass. The correct action is therefore to add
  `HcOptimizePeephole()` to `Compiler.HC` and call it in `CompilerCompileAndRun` **between parse and flush**
  (mirroring upstream call sites `compiler/jit_arm64.c:2590, 3471`).
- *No regalloc / no far branches, either engine.* Both are stack machines; `emit_lsr` exists unused in both;
  both use `ASR` for `>>`. Not a salvage item — a shared limitation.
- *The `ffi`/`switch` pair.* Upstream `kernel/sched/sched.c:137` *does* call `cpu_switch_context`, but the C
  scheduler it belongs to was a stub (`docs/04` A12) and the current repo registers `cpu_switch_context`
  without a runtime caller. Both `.S` files are dead in the current tree; the useful future use of
  `arm64_ffi_call` is as the seed of the **P10 HolyPort/scripting FFI**.

---

## 3. Area B — Render / math / GPU C (the "HolyGL sovereign unification" surface)

Our HolyC rasterizer **core** is ahead (exact integer Pineda edges + top-left rule, per-pixel Z,
perspective-correct bilinear texturing, per-fragment Blinn-Phong, deterministic golden hash `0xD28836F`), but
the migration **regressed on everything around it**. This is the single largest salvage surface.

| upstream `file:line` | what it is | current HolyC equivalent | action |
|---|---|---|---|
| `kernel/math/holygl.h:32`, `holygl.c:14-15,73-131` | **depth-4 projection matrix stack** + push/pop/rotate/scale | `apps/HolyGL.HC:37-41` has a single projection mat4 + 8-deep modelview stack only; **no `glPushMatrix/PopMatrix/Rotatef/Scalef` bindings** (grep = 0) | **PORT** |
| `kernel/math/holygl.c:149` `glClear` | framebuffer clear via GL | absent | **PORT** |
| `kernel/math/holygl.c:164` `glClearColor` | clear-colour state | absent | **PORT** |
| `kernel/math/holygl.c:180` `glColor4f` | per-vertex **alpha** | absent (only `glColor3ub`) | **PORT** |
| `kernel/math/holygl.c:188` `glColor3f`, `:275` `glVertex2f` | GL entry points | absent (grep = 0) | **PORT** |
| `kernel/math/holygl.c:381` `glFlush` | GL flush | absent | **PORT** |
| `kernel/math/math3d.c:788` `clip_triangle_near_plane` | Sutherland–Hodgman near-plane clipper (call at `:1121`, `near_w = 0.2f`) | `apps/HolyGL.HC` just **rejects** `w <= 0.05` → large-triangle popping | **PORT** |
| `kernel/math/raster_tile.c:46-208`, `raster_tile.h:9-21` | **tile binning** + per-core L1 `tile_scratchpad_t` | `apps/RasterTile.HC:22-23` declares `TILE_W/H = 64` but **never bins** (no scratchpad, unused constants) | **PORT** |
| `kernel/math/raster_tile.c:212` `raster_tile_triangle_neon` | per-tile NEON triangle fill | `apps/RasterTile.HC` (present, ahead) | **NONE** |
| `kernel/math/raster_tile.c:411-445` `raster_tile_resolve_streaming` | `stnp q0..q3` **non-temporal** tile resolve direct to VRAM | `apps/Render.HC` writes spans straight to the FB | **PORT** |
| `kernel/math/raster_tile.c:447-560` | SMP tile slicing (`raster_tile_render_range`, `wfe`/`sev`/`dmb ish`) | absent; `GFX_MODE_SMP_TILED` is only a label | **PORT** |
| `kernel/math/math3d.c:1189-1230` | SMP parallel vertex transform (`smp_dispatch`, split job, `dmb ish`) | absent | **PORT** |
| `kernel/math/math3d.c:869` | 16.16 fixed-point scanline engine (alt engine) | not present (ours is integer-exact) | **REFERENCE** |
| `kernel/math/math3d.c:726` `zbuffer_clear` | **NEON** z-clear (128-byte aligned) | `apps/RasterTile.HC` uses `memset` | **PORT** |
| `drivers/gpu/gfx_backend.h:22-25` | `ZBUFFER_PRECISION_32BIT` option | absent (16-bit only) | **PORT / REFERENCE** |
| `gui/render.c:15` `gfx_neon_blit_nt` | NEON blit `ldp`×4 / `stnp`×4, 128 B/iter | `apps/Render.HC:592,614` uses `memcpy` | **PORT** |
| `gui/render.c:209` `gfx_clear` | NEON fill (`dup` + `stnp`, 64 B/iter) | `apps/Render.HC` scalar | **PORT** |
| `gui/render.c:418,463` `gfx_blend_rect` | `ld4`/`st4` byte deinterleave + `umull`/`shrn` | `apps/Render.HC` scalar | **PORT** |
| `drivers/gpu/gfx_backend.c:98-161` | `gpu_set/get_{buffering,zprecision,raster_engine,tile_size,smp_cores,shading,culling}` | `apps/GfxDevice.HC` dropped **all** of it (grep `gpu_set` = 0) | **PORT** |
| `drivers/gpu/gfx_backend.c:176,207,462` | `gpu_config_{open,render,click}` — 4-tab GPU config window | absent | **PORT** |
| `drivers/gpu/virtio_gpu.c:84,145` | `send_batch2` / `send_batch3` chained descriptors | `apps/GfxDevice.HC` sends **one** command per notify | **PORT** |
| `drivers/gpu/virtio_gpu.c:347-386,411-476` | page-flip **ping-pong** resources 1/2 (`virtio_gpu_page_flip`) | absent | **PORT** |
| `drivers/gpu/virtio_gpu.c` (whole file) | **2D only** — no virgl/Venus/3D commands anywhere | `apps/GfxDevice.HC` (2D) | **NONE** (3D is new work — §9) |
| `kernel/math/math3d.c:431` `texture_generate_procedural` | procedural texture generator | `apps/Math3D.HC`/`apps/ShaderVM.HC` supersede it | **REFERENCE** |
| `kernel/math/math3d.c:324,484,611` | painter's-algorithm renderers (solid/textured/phong cube) | superseded by the one rasterizer + shader VM | **REFERENCE** |
| `gui/wm.c` (569 L) | window model/chrome/tray/damage (`wm_handle_mouse` already a stub) | dissolved into `apps/DolDoc.HC` `$WIN$` | **NONE** |

**Bottom line.** Port the *ring around* the rasterizer (GL state machine, clipper, tile binning + L1
scratchpad + SMP slicing + `stnp` resolve, NEON 2D kernels, the GPU config plane, virtio batching/page-flip).
The rasterizer core itself is ours and stays.

---

## 4. Area C — Benchmark / telemetry C

| upstream `file:line` | what it is | current HolyC equivalent | action |
|---|---|---|---|
| `kernel/bench/bench_unified.c:56` | `s_cat_names[5]` = {Gears, Cubes, Dynamics, Sphere, Fillrate} | `apps/HolyBenchmark.HC` (166 L) | **PORT** |
| `kernel/bench/bench_unified.c:59` | `s_var_names[8]` = {SW 1C Base, SW NEON L1, SW SMP 4C, SW DirectVRAM, HW VirtIO, HW DMA+SMP, HW Wireframe, HW VSync 60Hz} | absent — `apps/HolyBenchmark.HC:59` uses `(phase/8)%5` (engine only), **ignores `phase%8`** | **PORT** |
| `kernel/bench/bench_unified.c:64-157` `bench_apply_suite_phase` | **actually reconfigures the driver** per variation (mode/buffering/raster-engine/cores/shading/vsync) | absent | **PORT** |
| `kernel/bench/bench_unified.c:151-152` | **3.5 s** per phase (`cntfrq*7/2`), advance on elapsed | absent (no time limiter) | **PORT** |
| `kernel/bench/bench_unified.c:1129` | advance when elapsed **AND** `valid_sample_count >= 15` | absent | **PORT** |
| `kernel/bench/bench_unified.c:377-491` | `BENCH_COMPARISON.TXT`: 40-row table + 8×5 matrix + empirical winner + `profiler_get_optimization_directive` text | absent — `apps/HolyBenchmark.HC:117` writes a **fake** hard-coded "Engine 1..5 PASS" scorecard | **PORT** |
| `kernel/bench/bench_unified.c:493-571` | `BENCH_REPORT.TXT` + `GEARS_BENCHMARK.LOG` | absent | **PORT** |
| `kernel/bench/bench_unified.c:1204` | `render_us` synthetic fallback `2500` | — | **PURGE** |
| `kernel/bench/bench_unified.c:150` | `freq` fallback `62500000` | — | **PURGE** |
| `kernel/bench/profiler.c` (427 L) + `.h:6-7` | `profiler_t`: 256-bin histogram (500 µs bins), p1/p0.1 lows, jitter σ, 128-spike ring | `apps/Profiler.HC` (449 L) — core ported | **REFERENCE** |
| `kernel/bench/profiler.c:72-122` | `profiler_mark_{logic,raster,blit,dma,wm}_{start,end}` API | **missing** from `apps/Profiler.HC` | **PORT** |
| `kernel/bench/profiler.c:294-327` `profiler_get_optimization_directive` | code-level recommendations per bottleneck | missing | **PORT** |
| `kernel/bench/profiler.c:330` `profiler_export_log` / `profiler_export_spikes` | log + spike dump | missing (no exports) | **PORT** |
| `kernel/bench/perf_overlay.c` (672 L) + `.h:6-7` | `perf_stats_t`: 512-frame ring, 128 `spike_record_t` with `spike_cause_t`, **steady-state** metrics (subtract frame-0 warmup), `recent_spike_ms`, `spike_count_500ms` | `apps/PerfOverlay.HC` (366 L) — **largest gap** | **PORT** |
| `kernel/bench/perf_overlay.c:177-350` | percentile/steady-state computation (p1/p0.1 lows, steady fps, stddev) | `apps/PerfOverlay.HC:105-106` initialises `fps_1pct_low/fps_01pct_low = 60.0` and **never recomputes them**; no steady-state | **PORT** |
| `kernel/bench/perf_overlay.c:467,599` | `perf_export_log` / `perf_export_spike_log` | absent | **PORT** |
| `kernel/bench/perf_overlay.c:295` | `blit_avg_ms` synthetic fallback `0.82f` | — | **PURGE** |
| `kernel/bench/perf_overlay.c:445-446` | synthetic fallbacks `1.5f` / `0.82f` | — | **PURGE** |
| `kernel/bench/perf_overlay.c:565` | hard-coded `"Memory Leaks: 0 bytes"` header string | — | **PURGE** |
| PMU (`PMCR_EL0`/`PMCCNTR_EL0`) | **absent** — all timing is `cntvct_el0`/`cntfrq_el0` (both trees) | absent | **NEW** (§9) |

**Synthetic constants to purge (all verified).** `perf_overlay.c:295` (`0.82f`), `:445-446` (`1.5f`/`0.82f`),
`bench_unified.c:1204` (`render_us = 2500`), `:150` (freq fallback `62500000`), plus the current
`apps/HolyBenchmark.HC:82-83` (`1200/400/300`) and the hard-coded scorecard at `:117`.

---

## 5. Area D — Fonts C

| upstream `file:line` | what it is | current HolyC equivalent | action |
|---|---|---|---|
| `gui/font_ttf.c` (211 L) | **real TrueType** engine: bakes a 512×512 8-bit AA atlas (ASCII 32–126) | `apps/Fonts.HC` (708 L) — hand-built Bézier + boot-baked AA atlas, **no TTF** | **PORT** |
| `gui/font_ttf.c:112-116` | `FONT_ATLAS_W/H 512`, `stbtt_bakedchar g_cdata[96]` (ASCII 32–126) | none | **PORT** |
| `gui/font_ttf.c:132` `stbtt_BakeFontBitmap` | atlas bake | `apps/Fonts.HC:423` `FontsBakeGlyph` (4× supersample, different design) | **REFERENCE** |
| `gui/font_ttf.c:163` `stbtt_GetBakedQuad` | **subpixel-positioned** quads, per-pixel alpha blend | absent (fixed advance) | **PORT** |
| `gui/stb_truetype.h` (5079 L, **stb v1.26**) | full TTF rasterizer | absent | **PORT / VENDOR** |
| `gui/stb_truetype.h:948-949, 4575, 4762` | `stbtt_GetGlyphSDF` / `stbtt_GetCodepointSDF` (dormant SDF path) | absent | **PORT** |
| `gui/stb_truetype.h:811-814, 2317-2332` | kerning APIs (`GetKerningTable`) | absent | **PORT** |
| `gui/font_ubuntu_mono.c` (12866 L) | embedded **UbuntuMono-R** SFNT, `g_ubuntu_mono_ttf_len = 205748` | absent | **PORT / VENDOR** |

**Note.** The migration's `apps/Fonts.HC` deliberately avoided the TTF path (see `docs/04` D9: "AA via a
baked coverage atlas, not a live SDF"). The upstream TTF engine is nonetheless the ready-made path to
resolution-independent text; the SDF APIs are the natural bridge to the P4.6 fragment VM.

---

## 6. Area E — Deleted HolyC apps salvage (all under `/tmp/neo-upstream/apps/`)

| upstream `file:line` | what it is | current equivalent | action |
|---|---|---|---|
| `WasmJit.HC` (222 L; parser `:44-58`, emitter `:85-130`, cache flush `:185`) | **the only WASM→AArch64 JIT in the repo** (LEB128 parser + i32.const/local.get/add/sub/mul/nop/end + cache flush + fn-ptr call) | nothing | **PORT (HIGH, P10)** |
| `SmpDemo.HC` (328 L) | 4-core parallel **Mandelbrot + ray-sphere** via `smp_dispatch`, per-core `cntvct` timing | `apps/Smp.HC` (no compute demo) | **PORT (HIGH, P7)** |
| `StdLib.HC` (338 L) | `CArray` (growable), `CDict` (djb2 `DictHashKey`, `StrDup` key isolation), self-test (`:295-329`) | only `boot/seed/table.c` (fixed **32** buckets, `boot/seed/table.h`) survives | **PORT (MED-HIGH, P8)** |
| `GfxBackend.HC` (374 L; config API `:26-150`) | full GPU config API (mode/buffering/zprecision/raster-engine/tile-size/SMP-cores/shading/culling/tab) | `apps/GfxDevice.HC` dropped it | **PORT (P7 prereq)** |
| `HolyGLTest.HC` (86 L; tests `:8,26,37,50`) | 4 GL conformance tests (matrix push/pop, perspective, Lambertian, Z-buffered triangle) | none | **PORT (P7/P9)** |
| `Top.HC` (141 L; `:41-59` per-core heartbeat/load) | live per-core heartbeat + load + task table + heap range/peak | `apps/Shell.HC` `top` (leaner) | **PORT (MEDIUM)** |
| `Editor.HC` (160 L) | syntax-highlighting editor | `apps/Shell.HC` `edit` (leaner) | **PORT (MEDIUM)** |
| `Filer.HC` (140 L) | disk telemetry + preview | `apps/Shell.HC` `filer` (leaner) | **PORT (MEDIUM)** |
| `Showcase.HC` (79 L) | flagship DolDoc demo | none | **PORT (MEDIUM)** |
| `Compositor.HC` (599 L) | KolibriOS 64×64 tile-ownership/damage maps + box model | dissolved into `apps/DolDoc.HC` | **REFERENCE** |
| `WM.HC` (1075 L) | z-order/snap/taskbar | dissolved into `apps/DolDoc.HC` `$WIN$` | **REFERENCE** |
| `HolyBenchmark3D.HC` (89 L), `calc.HC` (142 L), `fact.HC` (88 L), `Menu.HC` (27 L), `Bench.HC` (42 L) | micro-demos / orchestrators | partial | **PORT selectively (P7/P10)** |
| `Table.HC` (near-duplicate of `StdLib.HC`) | unified `CArray`/`CDict`/`Table` (`TABLE_BUCKETS 64`, `:6`) | deleted; `boot/seed/table.c` = 32 buckets | **REFERENCE (dedupe on port)** |
| `FontVector.HC` (448 L), `FontMono.HC` (295 L) | Bézier + bitmap fonts | merged into `apps/Fonts.HC` | **NONE** |
| `Lexer.HC` (887 L) | lexer | preserved inside `apps/Compiler.HC` | **NONE** |
| `VirtioGpu.HC` (531 L) | virtio-gpu transport | preserved inside `apps/GfxDevice.HC` | **NONE** |

---

## 7. Directives that constrain salvage (`SKILL.md` 20 Orders + `docs/00` invariants)

Salvage must be **re-created in HolyC**, never re-introduced as C, and must respect:

- **No new `.c`** (Order 2; `docs/00` §2.1). Everything below lands in `.HC` (or, for the frozen seed, stays in
  `boot/seed/`).
- **No stubs / placeholders / mock data** (Order 2). This is why the fake `HolyBenchmark` scorecard
  (`apps/HolyBenchmark.HC:117`) and the synthetic telemetry constants must be **replaced by the real
  upstream logic**, not patched.
- **No forward declarations** (`docs/04` D17) — order functions topologically or dispatch via the SIC.
- **No UI cycles** (`DolDoc⇄Shell`, `WM⇄Shell`, `WM⇄Compositor`, `DolDoc⇄Compositor` stay broken).
- **One pipeline, no scalar fallback** (`docs/00` §2, `docs/04` D3/D8) — the ported NEON kernels must live in
  the ONE rasterizer, not as parallel engines.
- **Golden hash `0xD28836F` bit-exact** after every change; **`GOLDEN BOOT: PASS`** after every change.
- **C-runtime census must not increase** (`docs/00` §10; baseline in `tests/census-baseline.txt`) — `.HC`-only
  ports are census-neutral; the peephole port into `Compiler.HC` adds no allocator sites.
- **8-argument call cap** (`docs/04` D4); **no cross-module struct-member access** (use accessors);
  **one merge/dissolve per commit** (`docs/00` §2.10).
- **Everything verified in QEMU via screendump** (Order 20).

---

