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
| DolDoc 3.0 CDoc/CTree, per-char attrs | **[STUB]** DolDoc is a **fixed char grid** (`g_doc_chars[16384]`, 126×41), `g_doc_fg/bg`, `g_hist_chars`; not a CDoc/CTree. |
| Full two-letter tag set `TX CR SR … FI` | **[MISSING]** only a subset (`$FG$/$BT$/$LK$/$PB$`-style) implemented. |
| Windows are documents (`$WIN$`/`$SPLIT$`) | **[MISSING]** `WM.HC` owns 8 hardcoded windows (`g_wm_wins[8]`), window ID 2=plasma, ID 3=3D gears. |
| Compositor dissolved into DolDoc | **[MISSING]** `Compositor.HC` separate. |
| Shell = action executor over a CDoc; command registry | **[MISSING]** if/else ladder in `Shell.HC` (~467-751); `shell_register_cmd` dead (zero callers). |
| No cycles (`DolDoc⇄Shell`, `WM⇄Shell`, `WM⇄Compositor`, `DolDoc⇄Compositor`) | **[MISSING]** cycles present. |
| `g_doc_dirty_mask` bug `((U64)1<<r)` | **[PARTIAL]** reported. |
| `Showcase.HC` flagship doc | **[GONE]/[MISSING]** not in the current 36 apps. |
| `$EQ$`, `$GRAPH$`, `$SHADER$`, `$SP$`, CSprite/`SPT_MESH` | **[MISSING]** specs only. |

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
