# NeoOS — 01 REALITY AUDIT (verified claim-by-claim)

> Consolidation doc 2 of 5. This is the **verified reality** of the code, cross-checked against every claim in the
> 44 old docs. Tags: **[REAL]** verified in code today · **[PARTIAL]** exists but incomplete/wrong · **[STUB]**
> mock/placeholder/renamed-only · **[MISSING]** claimed but absent · **[GONE]** was real, since removed ·
> **[SUPERSEDED]** claim overridden by a later decision. Where the docs contradict each other, both are noted.

Current verified baseline (HEAD `efc6b81`, tree clean):
`GOLDEN BOOT: PASS` · `SELF-HOST: PASS` (Compiler.HC compiles itself) · battery **65/65** · `p1-parity` **PASS**
(34 modules, engines agree) · `check-token-parity` **71 identical**.

**Repo inventory today:** `apps/*.HC` = **36** (34 loaded by `KernelInit.HC`, plus `TestJitP0.HC` and one other
not in the boot list); C in build = **9** (`boot/main.c`, `boot/seed/{lexer,table,jit_arm64}.c`,
`boot/runtime/{virtio_blk,redsea,kheap,symbols,hal_platform}.c`); asm = **4** (`kernel/sched/switch.S`,
`kernel/arch/aarch64/{vectors,smp_entry,ffi_arm64}.S`). Old docs claimed 51 `.HC` / 43 `.c` / 215 files / 75k LOC
(inconsistent between `179/71,440` and `215/75,143`) — those counts are stale.

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
| Compiler script-mode = C JIT (REPL/`run`) | **[PARTIAL]** Compiler.HC handles bare expressions & modules, but the REPL still uses the C JIT (`Shell.HC:732,762`): `.HC` REPL is 61/65, missing fnptr calls, F64 struct *expressions*, forward structs, cross-unit interference. |
| **Stage-2 standalone binary blob** (task.md Phase 16, FUTURE Task 5.4) | **[SUPERSEDED]/REMOVED** — master plan §4 rejects it; seed lives in `boot/seed/`. |
| C JIT (`jit_arm64.c`) decommissioned | **[MISSING]** it is the live seed (Option A) and the runtime REPL compiler. |

## C. Kernel

| Claim | Reality |
|---|---|
| Preemptive scheduler; `sched_tick()` drives preemption | **[STUB]/[MISSING]** `cpu_switch_context` assembled+registered but has zero callers; timer not armed for preemption. Old C1 (empty `sched_tick`) is **[PARTIAL]** — the `.HC` `Sched.HC` exists but is not driving preemption. |
| SMP: 4 cores via PSCI, all active | **[PARTIAL]** PSCI bring-up exists; per-core run queues absent; old "secondaries run outside scheduler / spin" claims: **[PARTIAL]** (now `Smp.HC`). |
| One allocator | **[MISSING]** two allocators: C `boot/runtime/kheap.c` (live) + dead `KHeap.HC`. |
| One symbol table | **[MISSING]** C `symbols.c` (1024 buckets, live) + `Symbols.HC` (fallback). Old docs said 256 (dossier) vs 4096 (arch_spec) — both wrong; C is 1024. |
| One HAL; no hardcoded QEMU MMIO | **[MISSING]** C `hal_platform.c` (live) + `HalPlatform.HC` (dup `g_hal_*`); drivers still partly hardcode `0x09000000`/`0x08000000`/`0x0A000000`. |
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
| VirtIO-GPU 2D | **[PARTIAL]** `VirtioGpu.HC` sends **truncated** commands (`RESOURCE_CREATE_2D` 40→32, `TRANSFER_TO_HOST_2D` 56→48) — real bug (master P4). |
| `GFX_MODE_HW_ACCELERATED` real | **[STUB]** old claim: it only renamed + set `feature_flags=0x0F`. |
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
| Gouraud / SDF / shader VM | **[STUB]/[MISSING]** flat shading live; SDF + fragment-shader VM absent. |
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
| Harness `scripts/*.py` (`test_p8_holygl.py`, `test_p9_compiler.py`, `test_cold_boot.py`, …) | **[GONE]/[MISSING]** current harness is `golden-boot.sh`, `self-host-test.sh`, `p1-parity.sh`, `run-jit-golden.py`, `audit-symbols.sh`, `crash-decode.py`, `screenshot-diff.py`, `check-token-parity.py`. |

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
