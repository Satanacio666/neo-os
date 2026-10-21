# NeoOS — 00 MASTER PLAN (objectives, priorities, architecture)

> Consolidation doc 1 of 5. Sources: all 44 `docs/*.md` + `docs/master/*.md` + repo `README.md`/`SKILL.md`.
> This is the **plan** (what we are building and why). Reality is in `01-REALITY-AUDIT.md`; the task list is in
> `02-TASKLIST.md`; ideas/research in `03-IDEAS-AND-RESEARCH.md`; contradictions/decisions in
> `04-CONTRADICTIONS-DECISIONS-OPEN-QUESTIONS.md`. Nothing from the old docs is dropped — outdated/superseded
> claims are preserved in doc 4.

---

## 1. Vision & objectives (the whole project, fully looked upon)

**NeoOS** is a **64-bit AArch64 Ring-0 (EL1) Single Address Space OS (SASOS)** in the TempleOS tradition —
"the Compiler IS the OS", no userspace, one flat 1:1 identity-mapped address space, direct MMIO/VRAM access
from any module. It boots natively via **UEFI** (no Linux, no hypervisor in the normal path).

**End goals (all stated across the docs):**
1. **Self-hosting** — everything in HolyC; C only for the minimal UEFI bootstrap (`boot/main.c` + `boot/uefi`).
2. **A perfect HolyC compiler** — `apps/Compiler.HC` compiles the entire OS *and itself*.
3. **One unified render pipeline** — HolyGL as an API with backends (soft NEON×SMP → GPU → remote); one tiled
   rasterizer; no scalar fallback; real per-pixel Z, textures, SDF, shader VM.
4. **A real TempleOS-model DolDoc** — CDoc/CTree, per-char attributes, the full two-letter tag set,
   macros/forms/sprites/anchors/links/trees, **windows-as-documents**, reactive cells.
5. **A unified shell** — documents emit *Actions*; the shell executes; no cycles.
6. **One HolyGL-max benchmark** — 40 phases, real NEON/Gouraud/texture/Z/SDF, esports telemetry.
7. **Run anything at max native performance** — porting ladder (native → recompiled → WASM → emulation) +
   `HolyPort` (SDL/raylib-like) + a C→HolyC / LLVM→HolyC toolchain.
8. **Scale down** — the same `Surface`/tile abstractions → an **MCU cluster**.
9. **No unnecessary C.**

**Philosophy / non-negotiables (from `README.md` + `SKILL.md`):** No gambiarras; no userspace; single address
space; zero-RAM & double-buffered dual mode; sovereign L1 tile NEON SIMD; no stubs/mocks/placeholders;
no forward declarations; no hardcoded themes/grids/windows.

---

## 2. Invariants (never break)

1. **C only in the bootstrap:** `boot/main.c` + `boot/uefi/*` + the compiler seed (`boot/seed/*`) + the runtime
   substrate (`boot/runtime/*`) — until each is retired to `.HC`. No new `.c`.
2. **Golden gate green after every change** — `scripts/golden-boot.sh` must print `GOLDEN BOOT: PASS`.
3. **Compiler self-host** — `scripts/self-host-test.sh` must print `SELF-HOST: PASS` (Compiler.HC compiles itself).
4. **No unbounded compiler buffers** — every cap is a hard error (`g_hc_error`), never silent truncation.
5. **No JIT miscompiles / no special-casing** — fix the general codegen/parser path, never a module name.
6. **No UI cycles** — `DolDoc⇄Shell`, `WM⇄Shell`, `WM⇄Compositor`, `DolDoc⇄Compositor` stay broken.
7. **Never leave the tree red.**
8. **Test manually** — UART + QEMU protocols for every change; never trust a build alone.
9. **Persist after every green step** — `git commit` + `git bundle create /home/user/project/neo-os.bundle --all`.
10. **One merge/dissolve per commit**, each ending green.

---

## 3. Priority ladder (P0 → P10)

| Pri | System | Status | Gate to exit |
|---|---|---|---|
| **P0** | Observability & debug harness | ✅ DONE | — |
| **P0.5** | Test & harness 200% (in-guest SelfTest) | ✅ DONE — one command runs 80/80 + parity 54/54 + twins 5/5 + 0 unresolved + census | `golden-boot.sh` PASS on one boot |
| **P1** | Compiler (self-host) | ✅ **DONE** — self-hosts; REPL/`run` on Compiler.HC; parity PASS | both engines agree on all 34 modules + Compiler.HC compiles itself |
| **P2** | Bootstrap perfection (seed = compiler substrate only) | ✅ **DONE** — seed reads `.HC` from the FAT32 ESP via UEFI; C `redsea`/`virtio_blk`/HAL deleted | seed has no FS/block driver; C = `main.c`+`seed/*`+`kheap.c`+`symbols.c`+`uefi/*` |
| **P3** | Kernel correctness | ✅ **DONE** — timer IRQ, preemptive scheduler, SMP, BSOD, sovereign handover (doc 2 §P3) | timer IRQ fires; real preemptive scheduler; one allocator/table/HAL; kernel faults reach BSOD |
| **P4** | Rendering unification (merges) | 🔄 **IN PROGRESS** — P4.0 ✅ (render gate + bench + inventory); P4.1 ✅ (one `GfxDevice.HC`, virtio-gpu command fix); P4.2–P4.8 planned (doc 2 §P4, doc 3 §3.1) | one `GfxDevice` + one tiled rasterizer + one font |
| **P5** | DolDoc (real model + dissolution) | ⬜ | CDoc/CTree; windows are docs; no char grid |
| **P6** | Shell (action executor over a CDoc) | ⬜ | no cycles; shell output is a CDoc |
| **P7** | Benchmark (one HolyGL-max suite) | ⬜ | one real 40-phase suite; profilers merged |
| **P8** | Self-hosting everything | ⬜ | boot as a document; only boot C remains |
| **P9** | GPU provider | ⬜ | virtio-gpu 3D / native |
| **P10** | Run anything + MCU cluster | ⬜ | `HolyPort` + `Surface`/`remote` |

**Earlier "Level" scheme (L0–L8)** from `NEO_OS_MASTER_PLAN.md` maps onto this: L1 = P1 compiler, L2 = P2
bootstrap, L3 = P3 kernel, L4 = P4 render, L5 = P5 DolDoc, L6 = P6 shell, L7 = P7/P8 bench+self-host, L8 =
P9/P10. The old docs also used "Phase 0–17" (task.md), "Steps 1.0–6.0" (forensic dossier), "Phases 1–5"
(POST_DOM), "Phases 1–4" (DolDoc continuum), "P0–P3" (audit). All of these are reconciled in doc 2/4.

---

## 4. The bootstrap (the seed-compiler question — NO blob)

**Paradox:** `Compiler.HC` must be compiled before it can compile anything. The C JIT
(`boot/seed/jit_arm64.c`) compiles **only `Compiler.HC`**; `Compiler.HC` then compiles **every** other `.HC`
module (the "flip", now P2.7-complete — the seed compiles 1 module, not 7).

**DECIDED — Option A (implemented, `708c92a`).** The seed compiler is *necessary* C and lives in `boot/seed/`.
**The "Stage-2 binary blob" is REMOVED** — it came from the superseded `FUTURE_IMPLEMENTATIONS_MASTER_ROADMAP.md`
(Task 5.4) and `task.md` (Phase 16); it is the opposite of `.HC` sovereignty and was never requested. Options
B/C (fold a minimal seed into `boot/main.c`; true self-host from source) remain possible later. **No blob.**

**P2 bootstrap — DONE.** The old "delete the C runtime `.c`" plan was **unreachable**: the C FS/block stack
(`boot/main.c` → C `redsea.c` → C `virtio_blk.c`) loaded *every* `.HC` module. Fixed by giving the seed the
`.HC` sources *without* a filesystem of its own: it uses the **UEFI firmware's own FAT driver**
(`EFI_SIMPLE_FILE_SYSTEM_PROTOCOL`) to read them from the FAT32 ESP — no custom FS, no block driver, no blob,
no custom layout. `main.c` never calls `ExitBootServices`. The C block driver, filesystem and HAL were then
deleted; `boot/runtime/` is now only `{kheap.c, symbols.c}` (the frozen seed substrate). Seed floor =
`boot/main.c` + `boot/seed/*` + `boot/runtime/{kheap,symbols}.c` + vendored `boot/uefi/*`.

---

## 5. Architecture (target)

- **Boot:** UEFI → `boot/main.c` (GOP, `GetMemoryMap`, pools, symbol/heap init, read `KernelInit.HC`) →
  `KernelInit.HC` loads 34 `.HC` modules in 6 stages → `DolDocShellEventLoop`.
- **Address space:** flat 1:1 `VA==PA`; MMIO `0x0000_0000–0x3FFF_FFFF` Device-nGnRE; RAM `0x4000_0000+` Normal
  Write-Back Cacheable (MAIR index0 `0x04`, index1 `0xFF`); no per-process page tables.
- **Graphics:** one tiled NEON rasterizer (64×64 or 32×32 tile in L1 scratchpad, 16-bit Z, `stnp` resolve) →
  UEFI GOP direct scanout or VirtIO-GPU DMA; Zero-RAM (front==back) and Double-Buffered modes.
- **DolDoc:** documents are the UI; windows are `$WIN$` nodes; shell is a `$REPL$` node; one event/compose loop.
- **Multicore:** Core 0 coordinator; Cores 1–3 SIMD tile workers; lockless SPSC; `WFE`/`SEV` tickless idle.

---

## 6. Merge / dissolve / integrate matrix (gated behind P1)

### 6.1 Merge
| Fuse into | Sources | Pri |
|---|---|---|
| `Fonts.HC` | `FontMono.HC` + `FontVector.HC` + Render `gfx_draw_char` | P4 |
| `GfxDevice.HC` | `GfxBackend.HC` + `VirtioGpu.HC` (+ Render damage/present) | P4 |
| one tiled rasterizer | `Render.HC` + `RasterTile.HC` + `HolyGL.HC` | P4 |
| `Telemetry.HC` | `Profiler.HC` + `PerfOverlay.HC` | P7 |
| one `HolyBenchmark.HC` | `HolyBenchmark.HC` + `BenchCpu.HC` + `BenchReport.HC` | P7 |
| one compiler | `compiler/*.c` → `Compiler.HC` (as far as the seed allows) | P1/P2 |

### 6.2 Dissolve
| Dissolve | Into | Pri |
|---|---|---|
| `WM.HC` | DolDoc `$WIN$`/`$SPLIT$` views | P5 |
| `Compositor.HC` | DolDoc single-pass (damage/present → GfxDevice; theme → DolDoc) | P5 |
| char grid `g_doc_chars/fg/bg`, `g_hist_chars` | CDoc/CTree text runs | P5 |
| duplicate C/.HC stacks | one each | P2/P3 |

### 6.3 Retire
- `boot/seed/{jit_arm64,lexer,table}.c` — per the seed decision (Option A, no blob).
- bootstrap runtime C: `boot/runtime/{kheap,symbols,hal_platform,virtio_blk,redsea}.c` — once their `.HC` twins
  are load-bearing.

### 6.4 Globals to dedupe (before any merge)
`g_kernel_booting` (14 files), `g_gfx_cfg`, `g_theme`, `g_prof`/`g_perf`, `g_canv`/`g_comp`,
`g_hgl_zbuf`/`g_tile_zbuf` (two Z-buffers), `g_hal_gicd/gicc_base`, `g_hal_timer_freq`, `top_print_doldoc`.

### 6.5 Files deleted (cumulative, planned)
`FontMono.HC`, `FontVector.HC`, `GfxBackend.HC`, `VirtioGpu.HC`, `RasterTile.HC`, `PerfOverlay.HC`,
`BenchCpu.HC`, `BenchReport.HC`, `WM.HC`, `Compositor.HC` → replaced by `Fonts.HC`, `GfxDevice.HC`, one
`Raster`/`HolyGL`, `Telemetry.HC`, one `HolyBenchmark.HC`, DolDoc `$WIN$` views.

---

## 7. Verification matrix (run after every change)

| Check | Command | Expected |
|---|---|---|
| Golden gate | `scripts/golden-boot.sh` | `GOLDEN BOOT: PASS` |
| Self-host | `scripts/self-host-test.sh` | `SELF-HOST: PASS` |
| Self-test | UART `CompilerSelfTest();` | `All 7 / 7 tests passed` |
| Engine parity | `scripts/p1-parity.sh` | `RESULT: PASS — engines agree` |
| Undefined syms | `scripts/audit-symbols.sh` | 0 undefined, 0 unresolved |
| JIT battery | `scripts/run-jit-golden.py` | 65/65 |
| Token parity | `scripts/check-token-parity.py` | 71 tokens identical |
| Visual | `scripts/screenshot-diff.py` | no unexpected diff |

Persist after every green step: `git commit` + `git bundle create /home/user/project/neo-os.bundle --all`.

---

## 8. Deferred backlog (real, NOT near-term — do not pull forward)

Kept from the old docs so nothing is lost (full detail + reality tags in doc 3): PMU hardware telemetry;
Blinn-Phong; bilinear/trilinear textures; alpha blend modes; NEON 2×2 quad shadertoy engine (raymarching,
Mandelbulb, Perlin); Wavefront OBJ loader; `$EQ$` math typography; `$GRAPH$` telemetry; full CSprite opcode set;
`SPT_MESH` embedded 3D; FDT parser (Pi 4/5, RK3326, Snapdragon); audio (virtio-snd/HDA); networking
(virtio-net + lwIP); USB xHCI; class inheritance/vtables; optimizing JIT (SSA + regalloc); incremental
recompile cache; Ring-0 INT8 embeddings "semantic dispatch"; physical mobile SoC bring-up; game ports
(Quake/Half-Life), N64Recomp, Android NDK; `HolyPort`; MCU cluster.
