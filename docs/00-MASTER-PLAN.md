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
| **P4** | Rendering unification (merges) | ✅ **DONE** — P4.0 ✅ (render gate + bench + inventory); P4.1 ✅ (one `GfxDevice.HC`, virtio-gpu command fix); P4.2 ✅ (one rasterizer with real Z + NEON 8-px span, 4.46× + **Compiler.HC global-pointer width fix**); P4.3 ✅ (textures/perspective/filters/blend) + **p4.3b ✅** (NEON textured span + **D7 struct-member pointer root fix**) + **P4.4 ✅** (merged `Fonts.HC` + boot-baked AA atlas) + **P4.5 ✅** (per-fragment Blinn-Phong + Gouraud in the one NEON kernel, `FRSQRTE` normalize, gamma; + **D11 cross-unit F64 return-type root fix** that unblocked the gears) + **P4.6 ✅** (fragment-shader VM: 2×2 NEON quad, `dFdx`/`dFdy`, execution masking, Perlin/fBm/Mandelbulb/SDF library, 4-lane raymarcher; + **D13**, and the local-array/pointer-pointee F64 root fixes) + **P4.7 ✅** (OBJ mesh ingestion: streaming parser + quad triangulation rendering through the one pipeline; + **D14** redeclared-local type-flag root fix, **D15** struct-member array `N*M` dimension root fix in both `Compiler.HC` and the C seed) + **P4.8 ✅** (merge/delete/verify: one damage tracker + one present + `apps/Theme.HC` theme owner; dead-code purge; **determinism gate** proving `0xD28836F` byte-identical on 1 vs 4 cores — doc 2 §P4, doc 3 §3.1, doc 4 D16) | one `GfxDevice` + one tiled rasterizer + one font + one fragment VM + one mesh path + one theme owner |
| **P5** | DolDoc (real model + dissolution) | ✅ **DONE** — `DolDoc.HC` rewritten as a genuine **CDoc/CTree** (flat index-linked `CDocNode` tree + per-character attribute arena `g_doc_attr[fg|bg]`); the full two-letter tag set (`TX CR SR CU TB CL PB PL LM RM HD FO ID FD/BD/FG/BG PT WW UL IV BK SX SY CM AN LK BT DA MA SP FI`) incl. `$MA` macros, `$DA` forms, `$AN` anchors, `$ID` trees, typed `$LK` links, word-wrap; **windows are documents** (`$WIN$`/`$SPLIT$`/`$BLUR$`/`$ELEV$`); **`WM.HC` and `Compositor.HC` DELETED** (desktop/window/damage/present/effects absorbed into DolDoc); reactive cells (`$SL`/`$DA` target= binding); `$FI` include (RedSea doc persistence); `g_doc_dirty_mask` shift fixed; new `DOLDOC: PASS` gate (doc 2 §P5, doc 4 **D17/D18/D19/D20**) | no char grid; one CDoc/CTree; windows are documents; 34 modules |
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
| `WM.HC` | DolDoc `$WIN$`/`$SPLIT$` views | ✅ P5 (deleted; desktop is a document) |
| `Compositor.HC` | DolDoc single-pass (damage/present → GfxDevice; theme → DolDoc) | ✅ P5 (deleted; `DolDocPresent`/`DolDocDamage*`) |
| char grid `g_doc_chars/fg/bg`, `g_hist_chars` | CDoc/CTree text runs | ✅ P5 (gone; per-char attr arena) |
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
`BenchCpu.HC`, `BenchReport.HC` → replaced by `Fonts.HC`, `GfxDevice.HC`, one
`Raster`/`HolyGL`, `Telemetry.HC`, one `HolyBenchmark.HC`, DolDoc `$WIN$` views.
**Deleted in P5:** `WM.HC`, `Compositor.HC` (folded into `DolDoc.HC`).

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

---

## 9. Sovereign algorithm integration — best-in-class external designs, re-created in HolyC

Every entry is a **root fix/upgrade** of a real subsystem, not a shim. Code-level detail, pseudocode and
citations live in `docs/research/NEO_OS_AARCH64_ENGINEERING_BRIEF.md` and
`docs/research/holyc-aarch64-sasos-engineering-brief.md` (added 2026-10).

### 9.1 Compiler & symbols (`apps/Compiler.HC`, `apps/Symbols.HC`) — inspiration: chibicc / SubC
- **Lexer with no per-token heap**: POD token (`CToken`), interned identifier strings, a single string arena
  (already landed in P0.7: `HcStrAlloc`, 256 KiB chunks, BSS-first). Keep it.
- **O(1) symbol resolution**: the SIC cell *is* the GOT/PLT slot (`ldr x16,[&sym->address]; blr x16`). Upgrade
  the hash from DJB2 to **FNV-1a 64-bit** (`0xcbf29ce484222325` / `0x100000001b3`) and make the
  canonical-name (case/underscore-insensitive) lookup O(1) by storing a normalized key at registration.
- **Self-hosting safety**: never let self-compilation clobber a live function (`HcPublishFunc` guard); publish
  a function's entry **before** its body so recursion/forward calls resolve. Implement stack-arg spill for
  >8 args (today it hard-errors) or document the limit.
- **Backpatch ranges**: `CBZ/CBNZ` are ±1 MiB; add range-extension thunks (invert cond + `B`).

### 9.2 RedSea FS (`apps/RedSea.HC`, `apps/KHeap.HC`) — inspiration: ZFS CoW + littlefs CRC
- **CRC32C (Castagnoli)** 256-entry table (`0x82F63B78` reflected), self-test vector `0xE3069283`; optional
  `CRC32CB/CH/CW/CX` hardware path. Every block carries a CRC.
- **Atomic commit**: littlefs metadata-pair + ZFS **uberblock ring** (monotonic `txg`, highest valid wins);
  durability via `DC CVAC` + `DSB SY`. Torn writes fall back to the previous slot — no corruption on power loss.

### 9.3 Concurrency & SMP (`apps/Sched.HC`, `apps/Smp.HC`) — inspiration: Linux arm64 + Vyukov
- Replace the SPSC mailbox with **Vyukov bounded MPMC** (per-cell sequence, ABA-free) plus **MPSC per-core
  inboxes**; load balancing via a global queue. `LDAXR/STLXR` (acquire/release), `LDAR/STLR`, `WFE`/`SEV`
  idle with re-check. No libatomic (use `__atomic_*` builtins / inline asm).

### 9.4 Unified NEON rasterizer (`apps/RasterTile.HC`, `apps/HolyGL.HC`, `scripts/raster_span.s`)
- **Perspective-correct texturing**: interpolate `u/W, v/W, 1/W` (the `area` factor cancels), recover
  `u,v = (u/W)/(1/W)`; keep coverage exact `I64`, attributes `16.16`. Bilinear weights sum to **exactly 256**;
  `REPEAT` via bitwise mask (power-of-two), `CLAMP` via `SMIN/SMAX`; exact `div255` blend.
- **NEON has no gather**: the 8-texel fetch is scalar `LDR` + `INS` lane-pack; SIMD the coordinate math, the
  filter and the blend. **One pipeline only** (`RasterTriangleZ → RasterRow → RasterSpanNEON | textured
  span`) — no parallel/`permanent scalar rasterizer`. The 2D golden path forces the NEON solid span so
  `RENDER 0xD28836F` stays bit-exact.
- **Programmable fragments (`apps/ShaderVM.HC`, `scripts/shader_quad.s`)**: a register bytecode VM over a 2×2
  quad (16 registers × 4 lanes, SoA) whose arithmetic core is 128-bit NEON (`ShaderOp4`, 75 words) — one
  instruction = 4 px; `dFdx`/`dFdy` by lane permutation; execution masking via a per-lane predicate and mask
  stack. Built-in library (Perlin/fBm/Mandelbulb/SDF) + a text assembler for custom shaders; a native 4-lane
  raymarcher evaluates the field 4 lanes at a time through `ShaderOp4`. Separate path from the fixed-function
  rasterizer, so the golden 2D hash is untouched.

### 9.5 Fonts & typography (`apps/Fonts.HC` merge, `apps/DolDoc.HC`) — inspiration: stb_truetype
- **stb_truetype v2 signed-area AA rasterizer** + `GetGlyphSDF` (or rasterize-then-EDT). Bake a **SDF atlas**
  at boot; composite glyphs as textured quads through the unified rasterizer → resolution-independent,
  anti-aliased text with real weights.

### 9.6 DolDoc 3.0 (`apps/DolDoc.HC`, `apps/Compositor.HC`) — inspiration: React/Smalltalk/Figma
- Flat **index-based `CDNode` tree** (relocatable, serializable to RedSea), **React O(n) keyed
  reconciliation**, **memory-watch bindings** (`$DA`). The document IS the window, the shell and the editor;
  Morton dirty tiles; draw through the one rasterizer.

### 9.7 Reactive shell (`apps/Shell.HC`, `apps/Symbols.HC`) — inspiration: Lisp-machines/PowerShell
- Replace the `if/strcmp` ladder with **symbol-table O(1) dispatch**; command output is a mounted `CDoc`
  subtree (interactive, linkable, live-updating); `WFE` idle with a lost-wakeup-safe re-check.

---

## 10. Current execution state (2026-10)

- **P0.6** (`f0a407c`) DONE — BSOD panic-halt + fault telemetry + `crash-decode.py v2`.
- **P0.7** (`0a53886`) DONE — silent 128 KB module-truncation root-fix + lexer string arena + allocator hardening.
- **P0.7b** (`77d407f`) DONE — `KHEAP: PASS` split/coalesce regression + pointer-arithmetic audit.
- **`main` is green.** P0.7's blocker diagnosis: the *failing* allocator was the C seed heap; the *root* cause
  was module truncation, not exhaustion.
- **P4.3 (textures / perspective / filters / blend) DONE** (`51a9c68`) — one unified rasterizer, golden hash
  preserved (`RENDER 0xD28836F`), `TEXTURE: PASS`. Two **compiler root bugs** fixed on the way: mixed I64/F64
  arithmetic (all HolyGL geometry had collapsed to (0,0)) and struct-member pointer stride (8 vs 4).
- **p4.3b (NEON textured span + D7 root fix) DONE** — the textured span runs in the **same** `RasterSpanNEON`
  kernel (mask-skip, exact 64-bit `SDIV` perspective, scalar gather, NEON bilerp/modulate/blend); `RENDER
  0xD28836F` unchanged; `TEXTURE: PASS`; `PTRSCALE2: PASS`. **D7 is now root-fixed** (no typed-local workaround):
  `Compiler.HC` carries each struct member's pointee element width. `renderbench` reports textured throughput.
- **P4.4 (fonts) DONE** — `FontMono`+`FontVector` merged into `apps/Fonts.HC`; boot-baked AA coverage atlas;
  `FONTS: PASS`.
- **P4.5 (lighting & shading) DONE** — per-fragment **Blinn-Phong** + **Gouraud** in the SAME NEON kernel
  (gmode dispatch), `FRSQRTE`/`FRSQRTS` normal normalize, gamma-corrected; `SHADING: PASS`. On the way, the
  **gears-geometry "collapse" was root-fixed in `Compiler.HC`**: cross-unit F64 function return types were lost
  (`HcReset` cleared the per-unit table), so `r * MathCos(a)` promoted the double's raw bits as an integer.
  A persistent `name → returns-F64` table + `HcPrescanFuncs` fixed it; gears render `800 tris / 71410 px`
  (`3D-GEARS: PASS`), `RENDER 0xD28836F` untouched.
- **P4.6 (fragment-shader VM) DONE** — `apps/ShaderVM.HC`: a register bytecode VM over a 2×2 quad with a
  128-bit NEON op core (`ShaderOp4`, `scripts/shader_quad.s`), `dFdx`/`dFdy` by lane permutation, execution
  masking, a Perlin/fBm/Mandelbulb/SDF library + a text assembler, and a native 4-lane raymarcher; DolDoc
  routes `$SHADER$` `vm`/`sdf`/`noise`/`mandel`/`bulb` to it (`shader 9`, `shadervm`). `SHADERVM: PASS (14/14)`,
  `SELFTEST 85/85`, `RENDER 0xD28836F` untouched, census 181 unchanged. On the way, **two `Compiler.HC` root
  bugs** were fixed: local-array element floatness (inherited from the previous declaration) and pointer-local
  indexing (`F64 *p; p[i]`) using the pointer's own floatness instead of the pointee (D13).
- **P4.7 (OBJ mesh ingestion) DONE** — `apps/Mesh.HC`: a streaming Wavefront OBJ parser (`v/vn/vt/f`, relative
  indices, n-gon fan triangulation) rendering through the ONE pipeline (HolyGL → `RasterTriangleZ`), fixed-cap
  globals (census neutral), `mesh` demo + `$SP,type="mesh"`; `MESH: PASS (v=8 tris=12 nrm=6 ink=28177)`. On the
  way, **two more `Compiler.HC` root bugs** were fixed: **D14** — a local redeclared with a different type kept
  the FIRST type (`F64 b` then `I64 b` → the index loaded as a double and `&b × elem` became a wild ~18 GB
  read); **D15** — the struct-member array parser ignored `N*M`/`N+M` (fixed in both `Compiler.HC` and the C
  seed, so the parity gate stays at 0 diff). `SELFTEST 87/87`, `PARITY 56/56`, `RENDER 0xD28836F` untouched.
- **P4.8 (merge/delete/verify) DONE** — the rendering stack is now a single path with **one damage tracker, one
  present, one theme owner**: the compositor's duplicate bounding box + write-only tile maps are gone
  (`CompositorDamage*` → `GfxDeviceDamage`; `CompositorPresent` reads Render's dirty rect via
  `RenderDirtyActive()`/`RenderDirtyBounds()`), the palette moved to `apps/Theme.HC` (**36** subsystems), a
  batch of verified-dead functions was purged (census 181 unchanged), and a new **`scripts/determinism-gate.sh`**
  proves `RENDER 0xD28836F` is byte-identical on **1 vs 4 cores** (`DETERMINISM: PASS`). `GOLDEN BOOT: PASS`.
- Remaining near-term ladder: **P5** DolDoc 3.0 → **P6** reactive shell
  → **P7** bench → **P8** self-host-all → **P9** GPU → **P10** MCU cluster. The §9 integrations are folded into
  their owning priorities.
