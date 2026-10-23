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
| **P6** | Shell (action executor over a CDoc) | ✅ **DONE** — `Shell.HC` is now an **O(1) action executor**: FNV-1a `CShellCmd` registry (`shell_register_cmd`/`ShellFindCmd`, real hash dispatch replacing the ~50-branch if/else ladder); the **action protocol** `DOC_ACT_{RUN,OPEN,SET,CLONE,FOCUS}` (ring queue in `DolDoc.HC` + `DolDocPushAction`/`DolDocPollAction`/`ShellDrainActions`); **the `DolDoc → Shell` cycle is broken** (DolDoc has 0 `shell_run_command`/`shell_poll` references; it emits actions and calls a Shell-registered pump via a function pointer); shell output is a CDoc; `top`/`filer`/`edit` tools render interactive CDoc (buttons/progress/line-numbered text); `WFE` idle; new `SHELL: PASS` gate (doc 2 §P6, doc 4 **D21**) | no cycles; shell output is a CDoc |
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


---

## 11. Perfected priority plan (P7 → P11)

> Merged from the former `docs/06-PERFECTED-PRIORITY-PLAN.md` (P7.0 doc consolidation). Authoritative post-P6 roadmap; the P7 runbook is in `02-TASKLIST.md`.

> Consolidation doc 6 of 6. **This is the authoritative roadmap** for everything after P6.
> Sources: `00-MASTER-PLAN.md` §3/§6/§8/§9, `02-TASKLIST.md` §P7–P10, `04-CONTRADICTIONS-DECISIONS-OPEN-QUESTIONS.md`
> (D1–D22 + Part D open questions), the original C repo at `/tmp/neo-upstream` (satanacio666/neo-os, HEAD
> `36ca4b0` = our root commit), and the sibling salvage audit `docs/05-UPSTREAM-SALVAGE-AUDIT.md` (which holds the
> file-by-file salvage detail; this doc references it by name and does not duplicate it).
>
> **Status at authoring:** P0–P6 DONE and committed. HEAD `d657e70`. Remaining ladder: **P7 Benchmark**,
> **P8 Self-hosting**, **P9 GPU provider**, **P10 Run anything + MCU cluster**.

---

## 0. How to read this doc

- The ladder is **P7 → P10**, each executable in **one clean pass** with an **unambiguous exit gate**.
  P11 is a deferred/backlog bucket (real, not near-term).
- Every priority inherits the **locked invariants** below. A priority is *not* done until its gate *and* the
  global gate are green.
- "Salvage folded in" names what from the original C is reused (never re-invented). Detailed salvage evidence is
  in `docs/05-UPSTREAM-SALVAGE-AUDIT.md`.
- **No outdated format.** The old `tests/jit_golden/cases.json` battery is **declared historical** in this
  revision. `apps/SelfTest.HC` is the **single source of truth** for tests. The benchmark must be **real**
  (time-limited, driver-reconfiguring, PMU-backed) — no synthetic constants, no fake scorecards.

### 0.1 Locked invariants (every priority, every commit)

| Invariant | Gate string | Notes |
|---|---|---|
| Golden render hash bit-exact | `RENDER: PASS (0xD28836F)` | 1 vs 4 cores (`DETERMINISM: PASS`) |
| In-guest self-test | `SELFTEST: a/b` with **a == b** and **a ≥ frozen baseline** (≥74 absolute floor; 87 at P6) | never decreases |
| Engine parity | `PARITY: n/n (0 diff)` | both engines agree |
| `.HC`→C census | `CENSUS: PASS (181)` | **no counter may increase**; new code reuses existing sites / fixed-cap buffers |
| Compiler self-host | `SELF-HOST: PASS` | `Compiler.HC` compiles itself |
| Determinism | `DETERMINISM: PASS (1 vs 4 cores identical)` | |
| Golden boot | `GOLDEN BOOT: PASS` | one boot, `scripts/golden-boot.sh` |
| Visual proof | QEMU screendump only | `scripts/screenshot-diff.py` / `run-viewer-vm.sh` |

### 0.2 Locked code rules (compile-time / review-time)

- **No new `.c`.** C stays `boot/main.c` + `boot/seed/*` + `boot/runtime/{kheap,symbols}.c` + vendored `boot/uefi/*`.
- **No stubs, placeholders, or mock data.** A phase that cannot be real is not shipped.
- **No function forward declarations** (D17). **One initialized variable per declaration** (D18).
  **Declare a global before its first use** (D20). Mask power-of-two hash tables, never signed-`%` (D21).
- **Max 8 args per call** (D4) — a 9th arg is a hard error and leaves dangling symbols.
- **One pipeline, no scalar fallback.** NEON span body is mandatory; head/tail scalar mirrors are the only exception.
- **No cross-module struct-member access** — route through exported accessors (P4.8 rule; sweep in §4).
- **Inline asm / hand-encoded NEON is an accepted mechanism** (`scripts/raster_span.s`, `scripts/shader_quad.s`).

---

## 1. What changed vs the old ladder, and why

The old ladder (`00-MASTER-PLAN §3`) treated P7 as "a benchmark", P8 as "self-hosting", P9 as "GPU", P10 as
"run anything". That framing was **too thin for what the code actually needs**, and it let the "sovereign
unification" claimed by P4 stay **incomplete**. This revision fixes the framing:

1. **P7 becomes two things, not one.** The render reality shows P4's "one pipeline" is a *core*, not the whole
   engine. The original C had a **full GL 1.3 surface** (projection/modelview stacks, `glClear`/`glClearColor`,
   `glColor4f` vertex alpha, `glFlush`, a near-plane clipper) plus **NEON memory kernels** (`ldp/stnp` blit,
   `ld4/st4` blend, `dup/stnp` clear), a **real L1 tile binner with SMP slicing**, and a **GPU config plane +
   VirtIO batch/page-flip** — none of which we have. And the benchmark cannot be real until the profiler is real.
   So **P7 = "HolyGL Sovereign Unification + Real Telemetry/Benchmark"**, with the GL surface, the memory
   kernels, the tile/SMP path, the GPU plumbing, the merged profiler, the 40-phase suite, the rebuilt tests, and
   the GL conformance proof **all inside one priority**, in dependency order.
2. **The profiler is promoted from a side-quest to a first-class deliverable, at ALL levels.** The original
   `profiler.c` + `perf_overlay.c` had stage marks, 256-bin percentiles, jitter, warmup subtraction, a 128-entry
   spike ring with `spike_cause_t`, and `profiler_get_optimization_directive()`. Neither our `Profiler.HC` nor
   `PerfOverlay.HC` uses the **ARM PMU** — which is the key to *minimal hardware usage* and to *instruction &
   memory optimization* guidance. P7.5 makes one `Telemetry.HC` that profiles **frame / stage / subsystem /
   instruction / memory**.
3. **"Rebuild tests and benchmarks — no outdated format" is explicit.** `tests/jit_golden/cases.json` is frozen
   historical; `apps/SelfTest.HC` is the source of truth; the benchmark is a real 40-phase, 3.5 s/phase,
   `cntvct_el0`-limited suite that reconfigures the real driver per variation and exports real logs.
4. **P9 is re-ordered to reuse P7 plumbing.** The original had **no 3D transport at all** — not even upstream.
   P7.4 lands the transport plumbing (batch2/batch3, page-flip, 32-bit Z, tile parallelism); P9 builds the actual
   virgl/Venus provider on that seam.
5. **P8 folds the salvage that would otherwise be lost** when the C seed is retired: the compiler **peephole
   optimizer** (the *only* compiler feature our `Compiler.HC` lacks vs the C seed), **EFI MP Services** SMP
   bring-up, boot-as-document, and compiler-as-document.
6. **Cross-cutting hygiene is a first-class section** (§4): typing, dead code, committed `.o` artifacts, the
   orphan `apps/TestJitP0.HC`, the stale `GEARS_BENCHMARK.LOG`, the stale `p4.3-wip` branch, duplicate telemetry.

Everything from the old P7–P10 lists is preserved here, either folded into a sub-step or parked in P11.

---

## 2. The perfected ladder

### Priority overview

| Pri | Title | One-line definition of done |
|---|---|---|
| **P7** | **HolyGL Sovereign Unification + Real Telemetry/Benchmark** | One complete GL 1.3 surface + clipper + NEON memory kernels + L1/SMP tiling + GPU plumbing, measured by one merged PMU-backed all-level profiler and one real 40-phase suite, proven by a GL conformance test. |
| **P8** | **Self-hosting everything** | Boot is a document, the compiler is a document, the peephole optimizer is in `Compiler.HC`, and C is only `boot/main.c` + `boot/uefi`. |
| **P9** | **GPU provider** | A real virgl/Venus 3D transport behind the `GfxDevice` provider seam, with 32-bit Z and 4-core tile parallelism, golden-hash-safe on the software path. |
| **P10** | **Run anything + MCU cluster** | `HolyPort` + Sovereign SDL ABI + `Surface`/`remote` + a RISC-V/FDT MCU target, running a recompiled/WASM workload. |
| **P11** | **Deferred / backlog** | Real, not near-term: networking, USB, audio, optimizing JIT, physical SoC, game ports. |

---

## P7 — HolyGL Sovereign Unification + Real Telemetry/Benchmark

**Purpose.** P4 delivered the *core* of the unified pipeline (one device, one rasterizer, real per-pixel Z,
perspective texturing, per-fragment Blinn-Phong, a fragment VM, a mesh path, a determinism gate). It did **not**
deliver the *whole engine* the owner's requirements demand. The HolyC rasterizer core is genuinely **ahead** of
the original C (real per-pixel Z, top-left rule, perspective-correct bilinear texturing, per-fragment
Blinn-Phong, deterministic golden hash `0xD28836F`), but the surrounding GL surface, memory kernels, tiling,
GPU plumbing, and telemetry are **behind or absent**. P7 closes every one of those gaps and then *measures* the
result with a profiler that reaches instruction and memory level via the ARM PMU, and a benchmark that is a real
40-phase scientific suite rather than a hard-coded scorecard. When P7 exits, "sovereign unification" is no longer
a claim — it is a tested, profiled, benchmarked fact with a GL 1.3 conformance certificate.

### The verified gaps P7 must close (from the original C, `kernel/math/*`, `drivers/gpu/*`, `gui/render.c`)

- **HolyGL lacks:** a separate **PROJECTION** matrix stack (needs depth **4**; modelview depth **16**);
  `gl*` bindings for `Push/Pop/Rotatef/Scalef/Color3f/Vertex2f`; `glClear`/`glClearColor`; `glColor4f` vertex
  alpha; `glFlush`; and the **Sutherland–Hodgman near-plane clipper** (today `HolyGL.HC:292` just
  `return`s when any vertex has `w <= 0.05`).
- **RasterTile:** `TILE_W/H = 64` (`apps/RasterTile.HC:22-23`) declared but **unused** — no L1 tile binning, no
  per-core scratchpad, no SMP tile slicing, no `stnp` streaming resolve. `GFX_MODE_SMP_TILED` is a label only.
- **Render:** `gfx_swap_buffers`/`gfx_blend_rect`/`gfx_clear` are `memcpy`/scalar — the original had NEON
  `ldp/stnp` blit, `ld4/st4` blend, `dup/stnp` clear.
- **GfxDevice:** no `gpu_set/get_{zprecision,raster_engine,tile_size,smp_cores,culling}` config plane, no GPU
  config window, single-command VirtIO send (no `batch2`/`batch3`), no page-flip ping-pong.
- **Lighting:** the original `holygl.c` had GL 1.x per-vertex directional lighting; **ours (per-fragment
  Blinn-Phong) is better — keep ours** and route the original's per-vertex path only as a conformance fixture.
- **GL conformance:** the deleted `HolyGLTest.HC` proved 4 assertions (matrix push/pop, perspective, Lambertian
  lighting, Z-buffered triangle). P7.8 expands this to the **full GL 1.3 surface**.

### P7.0 — Baseline, gate freeze, and the "no outdated format" declaration

- **Purpose.** Freeze a green baseline and declare the test/benchmark truth *before* touching code, so every
  later step has an unambiguous reference and nothing "passes" by moving the goalposts.
- **Deliverables.**
  - Freeze: `GOLDEN BOOT: PASS`, `SELFTEST: 87/87`, `PARITY: 56/56 (0 diff)`, `CENSUS: PASS (181)`,
    `SELF-HOST: PASS`, `DETERMINISM: PASS`, `RENDER: PASS (0xD28836F)`; record the numbers in
    `tests/census-baseline.txt` and this doc's §0.1 table.
  - **Declare historical:** tag `tests/jit_golden/cases.json` superseded-by-`apps/SelfTest.HC` in
    `docs/01-REALITY-AUDIT.md`; `apps/SelfTest.HC` is the **single source of truth** (no new cases added to the
    JSON). `scripts/run-jit-golden.py` becomes a thin wrapper over `selftest`.
  - **Inventory of P7 targets:** call-site counts for every `gl*` alias, `gfx_*` swap/blend/clear, `TILE_W/H`,
    `GpuSet/Get*`, `VirtioGpuSendCmd`, and the telemetry globals (`g_prof`, `g_perf`); write the dead/write-only
    lists into §P7 of `docs/02-TASKLIST.md`.
  - New gate script `scripts/p7-verify.sh` that runs the full P7 gate (see P7 exit) and is called by
    `scripts/golden-boot.sh`.
- **Salvage folded in.** The original `holygl.h` GL surface inventory and `gfx_backend.h` config-plane inventory
  (from `docs/05-UPSTREAM-SALVAGE-AUDIT.md`) are the checklist for P7.1/P7.4.
- **Exit gate.** `scripts/p7-verify.sh` prints `P7.0: PASS`; all frozen numbers recorded; the JSON is tagged
  historical.
- **Risks/ordering.** Must run first; nothing else starts until the baseline is frozen.

### P7.1 — GL surface completion (a)

- **Purpose.** Make HolyGL a *complete* GL 1.3 API surface, not a partial one, so the conformance test in P7.8
  has a full target and the benchmark variations have real toggles to flip.
- **Deliverables.**
  - **`apps/HolyGL.HC`:** two matrix stacks — **PROJECTION depth 4** and **MODELVIEW depth 16** (today one
    implicit stack). `HolyGLMatrixMode(GL_PROJECTION|GL_MODELVIEW)`, `PushMatrix`/`PopMatrix` per mode.
  - `gl*` bindings: `glPushMatrix`, `glPopMatrix`, `glRotatef`, `glScalef`, `glColor3f`, `glVertex2f`
    (all currently dead/absent as live aliases).
  - Clear semantics: `glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT)`, `glClearColor(r,g,b,a)`,
    `glClearDepth(d)` — clear through the **one** `RasterTile` Z-buffer and the one framebuffer.
  - Vertex alpha: `glColor4f(r,g,b,a)` carried per-vertex into the span's alpha blend (the rasterizer already
    does exact `/255` alpha).
  - `glFlush()` → `GfxPresent` of the dirty rect (one present).
  - Keep the existing better-than-original per-fragment Blinn-Phong; the per-vertex directional path from the
    original `holygl.c` is exposed only as a conformance fixture (`GL_FLAT`/Gouraud), not the default.
- **Salvage folded in.** `kernel/math/holygl.c` (`glMatrixMode`/`glPushMatrix`/`glPopMatrix`/`glClear`/
  `glClearColor`/`glColor4f`/`glFlush`) and `kernel/math/math3d.c` (post-multiply matrix helpers, already
  root-fixed as D10). The GL 1.3 surface list is in `docs/05-UPSTREAM-SALVAGE-AUDIT.md`.
- **Exit gate.** `apps/SelfTest.HC` gains `SelfTestGLSurface()` → `GLSURFACE: PASS` (both stacks push/pop to
  depth, `glClear` clears color+depth, `glColor4f` alpha blends, `glFlush` presents); `RENDER: PASS (0xD28836F)`
  unchanged; `CENSUS: PASS (181)`.
- **Risks/ordering.** Must precede P7.2 (the clipper emits vertices into this surface) and P7.8 (conformance).
  Two stacks risk a regression in `Gears3D`/`Mesh` callers — audit every `HolyGLMatrixMode` caller first.

### P7.2 — Near-plane clipper + NEON memory kernels (b)

- **Purpose.** Stop *rejecting* geometry that crosses the near plane (the single biggest visual correctness gap:
  objects clip out instead of being clipped), and make the memory paths (present/blend/clear) as fast as the
  original's NEON kernels so the benchmark's memory-bandwidth bottleneck is real, not synthetic.
- **Deliverables.**
  - **Sutherland–Hodgman near-plane clipper** in `apps/HolyGL.HC`: clip each triangle's clip-space polygon
    against `w = 0.05`, re-triangulate the resulting 3–4 vertex polygon, then submit through
    `HolyGLSubmitTriangle`. Replaces the `w <= 0.05` early-return at `HolyGL.HC:292`.
  - **`scripts/neon_mem.s`** — hand-encoded kernels, wired into `apps/Render.HC`/`apps/GfxDevice.HC`:
    - `NeonBlitNT` — 128-byte unrolled `ldp q0..q7` / `stnp q0..q7` streaming blit (row + full + dirty-rect).
    - `NeonBlendRect` — `ld4 {v0-v3}.8b` byte-deinterleave ARGB, exact `/255` blend, `st4` (replaces scalar
      `gfx_blend_rect`).
    - `NeonClear` — `dup v.4s, col` / `stnp` fill (replaces scalar `gfx_clear`).
  - Route `gfx_swap_buffers`/`gfx_swap_rect`/`gfx_blend_rect`/`gfx_clear` through the NEON kernels; keep the
    scalar path only for unaligned head/tail.
- **Salvage folded in.** `gui/render.c` `gfx_neon_blit_nt` (ldp/stnp, 8×128-bit), the `ld4/st4` blend
  (`render.c:463-488`), and the `dup/stnp` clear (`render.c:210-224`). The original had no clipper — this is
  **new work**, specified against the standard Sutherland–Hodgman algorithm.
- **Exit gate.** `SelfTestClipper()` → `CLIP: PASS` (a triangle crossing `w=0.05` yields a non-degenerate clipped
  polygon with correct screen area); `SelfTestMemKernels()` → `NEONMEM: PASS` (NEON blit/blend/clear produce
  byte-identical output to the scalar reference on aligned+unaligned rows); `RENDER: PASS (0xD28836F)`;
  `CENSUS: PASS (181)`.
- **Risks/ordering.** Depends on P7.1. Clipping changes the golden 2D path? No — the 2D golden scene is
  axis-aligned and never crosses the near plane, so `0xD28836F` is safe; verify anyway.

### P7.3 — L1 tile binning + per-core scratchpad + SMP tile slicing (c)

- **Purpose.** Make `TILE_W/H = 64` and `GFX_MODE_SMP_TILED` **real**: bin triangles into tiles, rasterize each
  tile in a per-core L1 scratchpad, slice tiles across the 4 cores, and stream the resolved tiles out with
  `stnp`. This is what turns the benchmark's "SW NEON L1" and "SW SMP 4C" variations into measured differences.
- **Deliverables.**
  - **`apps/RasterTile.HC`:** a real L1 binner — tile queue per frame, per-core `tile_scratchpad_t`
    (64×64 color + 16-bit Z = 24 KB, cache-line aligned) in `apps/Smp.HC`; `RasterTileBeginScene`/`AddTriangle`/
    `EndScene`; a **streaming resolve** (`stnp` tiles into the framebuffer) replacing the full-frame writeback.
  - **SMP slicing:** `apps/Smp.HC` dispatches tile ranges to cores 1–3 with per-core scratchpads; one generic
    worker loop (P3 already deleted the copy-paste workers) takes a tile range. Deterministic order: tiles
    resolved row-major so 1-vs-4-core output is byte-identical.
  - `RasterTile` becomes the **only** tiled path (the full-screen `RasterRow` scan is the same code with a
    full-screen tile). No second rasterizer.
- **Salvage folded in.** `kernel/math/raster_tile.c` (`tile_scratchpad_t s_scratchpads[SMP_MAX_CORES]`,
  `raster_tile_render_range`, `tile_worker_smp`, `raster_tile_resolve_streaming`) — the *structure* is reused;
  the *math* stays ours (real per-pixel Z + NEON span, which the original lacked).
- **Exit gate.** `DETERMINISM: PASS (1 vs 4 cores identical: 0xD28836F)`; `TILE: PASS` (binner assigns the
  correct tile set to a known triangle; per-core scratchpads non-overlapping); `renderbench` shows a measured
  SMP speedup on 4 vs 1 cores in the benchmark (P7.6); `CENSUS: PASS (181)`.
- **Risks/ordering.** Depends on P7.2 (memory kernels) and P7.1 (surface). Determinism is the hard gate — the
  scratchpad→framebuffer resolve must be order-independent. This is the highest-risk P7 sub-step; keep the
  full-screen scan as the fallback *path* (not a scalar rasterizer) until SMP slicing is proven byte-identical.

### P7.4 — GPU config plane + VirtIO batch2/batch3 + page-flip ping-pong + 32-bit Z (d)

- **Purpose.** Give the benchmark a real config plane to reconfigure (so variations are genuine), batch the
  VirtIO command stream (so HW latency is measured honestly), add zero-copy page-flip, and make 32-bit Z a real
  toggle.
- **Deliverables.**
  - **`apps/GfxDevice.HC` config plane:** `GpuSet/Get{ZPrecision,RasterEngine,TileSize,SmpCores,Culling,Buffering}`
    + a `GpuConfigWindow` (DolDoc `$WIN$`, not a hardcoded grid) that displays and mutates the live config.
  - **VirtIO batching:** `VirtioGpuSendBatch2`/`SendBatch3` (multiple commands + one `RESOURCE_FLUSH` + one
    notify), ported into `GfxDevice.HC`; `VirtioGpuSendCmd` stays for singles.
  - **Page-flip ping-pong:** allocate two resources, `virtio_gpu_page_flip(resource_id)`, and drive
    `GfxPresent` through it in double-buffered mode.
  - **32-bit Z:** a second `CRasterSpan`/kernel variant (`scripts/z32_span.s`) selected by
    `GpuSetZPrecision(ZBUFFER_PRECISION_32BIT)`; 16-bit stays the default so `0xD28836F` is untouched.
- **Salvage folded in.** `drivers/gpu/virtio_gpu.c` `virtio_gpu_send_batch2` (`:84`), `send_batch3` (`:145`),
  `virtio_gpu_page_flip` (`:411`), the dual-resource ping-pong allocation (`:368-386`); `drivers/gpu/gfx_backend.c`
  the `gpu_set/get_*` config plane (`:98-161`) and the GPU config window (`:265-593`); `kernel/math/raster_tile.c`
  `raster_tile_set_zprecision`.
- **Exit gate.** `GPUCFG: PASS` (every `GpuSet*` is read back and changes behaviour: culling removes backfaces,
    32-bit Z resolves a Z-fighting case the 16-bit path merges, tile size changes the binner, SMP cores changes
    the dispatch count); live device `VirtioGpuIsAvailable()==1` with batched flush returning 0;
    `RENDER: PASS (0xD28836F)` on the 16-bit default; `CENSUS: PASS (181)`.
- **Risks/ordering.** Depends on P7.3 (tile size/cores must be real first). Batch3 must preserve response
  ordering; a batch failure must not leave a half-issued frame. This step lands the **plumbing P9 reuses**.

### P7.5 — Merged `Telemetry.HC` with ARM PMU + all-level profiling (e)

- **Purpose.** Replace the two partial telemetry modules with **one** engine that profiles at **frame / stage /
  subsystem / instruction / memory** level, uses the ARM PMU with **minimal hardware usage**, detects **spikes**
  with a cause, and emits **instruction & memory optimization directives**. This is what makes the P7.6 benchmark
  real and is the owner's explicit "profiler at ALL levels" requirement.
- **Deliverables.**
  - **`apps/Telemetry.HC`** (new; **delete** `apps/Profiler.HC` + `apps/PerfOverlay.HC`; load in `KernelInit.HC`
    where `Profiler.HC` was). One `CTelemetry g_tel`.
  - **Frame level:** `TelBeginFrame`/`TelEndFrame`, FPS avg, **1% low + 0.1% low** (256-bin histogram
    percentiles — `PerfOverlay.HC` never computed these), jitter σ, steady-state (subtract frame-0 warmup).
  - **Stage level:** `mark_*` API (`TelMarkLogic/Raster/Blit/Dma/Wm/SmpWait`) → per-stage µs accumulators.
  - **Subsystem level:** per-subsystem attribution (rasterizer / shader VM / fonts / RedSea / sched / mesh) via
    named scopes.
  - **Instruction level (PMU, new work):** `scripts/pmu_read.s` + `Telemetry.HC` program `PMCR_EL0`,
    `PMCCNTR_EL0`, and the 4 `PMEVCNTRn`/`PMEVTYPERn` pairs. Events: `CPU_CYCLES (0x11)`,
    `INST_RETIRED (0x08)`, `L1D_CACHE_REFILL (0x03)`, `BR_MIS_PRED (0x10)`. Derive **CPI**, IPC, instructions/
    frame, branch-mispredict rate, plus optional NEON/`sdot` utilization checks.
  - **Memory level:** L1D refill rate, bytes/blit, cache-miss-per-KiB, and an estimated DRAM-bandwidth figure
    from the refill counter and the blit byte counters.
  - **Minimal hardware usage:** PMU is enabled **only** inside a bounded measurement window (one event group at a
    time; counters disabled otherwise; event rotation across phases). Always-on timing uses the cheap
    `cntvct_el0`. Document the exact enable/disable discipline in the module header.
  - **Spike detection:** 128-entry ring, `spike_cause_t` (`SPIKE_CAUSE_{NONE,WM_FULL_REDRAW,SMP_SYNC_WAIT,
    VIRTIO_POLL,GOP_BLIT_MEM,SCHED_PREEMPT,RASTER_EDGE,PMU_BRANCH}`), `recent_spike_ms`,
    `spike_count_{50,100,500}ms`.
  - **Optimization directives:** `TelemetryGetDirective()` returns code-level recommendations keyed on the
    measured bottleneck **and** the PMU signature (high CPI → instruction-path work; high L1D refill → tile/
    scratchpad work; high BR_MIS_PRED → branchless/`csel` work; high SMP wait → chunk size; high blit/dma →
    direct scanout / batch).
  - `TelemetryWriteLogs()` → `/BENCH_PROFILER.LOG` + `/BENCH_SPIKES.LOG`.
- **Salvage folded in.** `kernel/bench/profiler.c` + `profiler.h` (stage marks, histogram percentiles, warmup
  discard, spike ring, `profiler_get_optimization_directive`) and `kernel/bench/perf_overlay.c` + `perf_overlay.h`
  (`spike_cause_t`, `recent_spike_ms`, sparkline history). The **PMU half is new work** (neither upstream nor ours
  used `PMCR_EL0`/`PMCCNTR_EL0`/`PMEVCNTR*`).
- **Exit gate.** `TELEMETRY: PASS` (`SelfTestTelemetry()`): (1) frame metrics match a synthetic 100-frame series
  (avg/1%/0.1%/jitter within tolerance); (2) all six stage marks accumulate; (3) a forced 65 ms stall produces a
  spike with the correct cause; (4) the PMU reads a strictly increasing `INST_RETIRED` and `CPU_CYCLES` across a
  known loop, with a CPI in the expected band; (5) the directive string is non-empty and cause-consistent;
  (6) logs serialize to RedSea. `CENSUS: PASS (181)` (fixed-cap globals, no new allocator sites).
- **Risks/ordering.** Depends on P7.2–P7.4 (stages must exist to mark). PMU availability on QEMU TCG must be
  probed (`PMCR_EL0.N` / `ID_AA64DFR0_EL1`); if a counter is unavailable, `Telemetry.HC` must fall back to
  `cntvct_el0` **without** breaking the gate — but never fabricate a PMU number (no mock data).

### P7.6 — Real 40-phase suite (f)

- **Purpose.** Replace the degraded `apps/HolyBenchmark.HC` (which ignores `phase%8`, has no time limiter, and
  writes a **fake hard-coded scorecard**) with the real design: **40 phases = 5 categories × 8 driver/architectural
  variations**, each time-limited to **3.5 s via `cntvct_el0`**, applying **real driver reconfiguration** per
  variation, and exporting real telemetry.
- **Deliverables.**
  - **Rewrite `apps/HolyBenchmark.HC`** (delete `apps/BenchCpu.HC` + `apps/BenchReport.HC`; merge into the one
    suite). `BenchUnifiedStart`/`BenchApplySuitePhase`/`BenchUnifiedTick`.
  - **Categories (5):** Gears, Cubes, Dynamics, Sphere, Fillrate. **Variations (8):** SW 1C Base, SW NEON L1,
    SW SMP 4C, SW DirectVRAM, HW VirtIO, HW DMA+SMP, HW Wireframe, HW VSync 60Hz. Phase `p` = category `p/8`,
    variation `p%8` — `BenchApplySuitePhase(p)` reconfigures the **real** `GfxDevice` config plane (P7.4) and
    scheduler.
  - **Time limiter:** each phase runs until `read_cntvct() - phase_start >= freq*7/2` (3.5 s).
  - **Per-phase metrics (from `Telemetry.HC`):** avg FPS, 1% low, 0.1% low, frame-time avg/min/max, jitter σ,
    stage breakdown (logic/raster/blit/dma/wm/smp), spike counts, bottleneck, optimization directive.
  - **Real compute:** replace `BenchCpuMathNeon()`'s integer LCG (**BEN-01**) with real NEON math
    (FMA/`FRSQRTE`/`sdot`-style) and remove the synthetic constants `blit_us=1200`/`dma_us=400`/`wm_us=300`
    (**BEN-02**) — stages are measured, not assumed.
  - **Exports:** `/BENCH_COMPARISON.TXT` (40-row table + 8×5 matrix + winner), `/BENCH_REPORT.TXT`,
    `/BENCH_PROFILER.LOG`, `/BENCH_SPIKES.LOG`.
  - **`renderbench`** (P4.0) is folded into the suite as the Fillrate category's micro-metric; the standalone
    command remains as a quick probe.
- **Salvage folded in.** `kernel/bench/bench_unified.c` (the whole 40-phase model: `bench_apply_suite_phase`,
  `s_cat_names`/`s_var_names`, `BENCH_SUITE_TOTAL_PHASES 40`, the `freq*7/2` limiter, `bench_comparison_record_t`,
  the sphere mesh builder, the export functions).
- **Exit gate.** `bench` runs 40 phases to completion, each ≈3.5 s (verified by total wall time and per-phase
  tick deltas), with a **different measured signature** per variation (e.g. SW SMP 4C > SW 1C Base on the
  raster stage; HW VSync clamps to ~60 FPS; DirectVRAM lowers the blit stage). `BENCH: PASS` asserts:
  all 40 records non-empty, the 8×5 matrix complete, a winner named, and **no record is a constant** across
  variations. `CENSUS: PASS (181)`.
- **Risks/ordering.** Depends on P7.4 (config plane) and P7.5 (telemetry). A 40×3.5 s run is ~140 s of guest
  time — the host gate must allow it (headless `run-viewer-vm.sh`, QEMU screendump only). The suite must be
  interruptible (`stopbench`) so the gate never hangs.

### P7.7 — Rebuilt tests & benchmarks — no outdated format (g)

- **Purpose.** Ensure there is exactly **one** test source of truth and **one** benchmark, both current, so no
  future step can pass against a stale battery or a fake report.
- **Deliverables.**
  - `apps/SelfTest.HC` is the only test runner; it absorbs the new P7 gates (`GLSURFACE`, `CLIP`, `NEONMEM`,
    `TILE`, `GPUCFG`, `TELEMETRY`, `BENCH`, `GLCONFORMANCE`) and prints the single `SELFTEST: a/b` summary.
  - `tests/jit_golden/cases.json` is **frozen historical** (no edits; no new cases). `scripts/run-jit-golden.py`
    is a thin `selftest` wrapper (or retired to `scripts/_superseded/`).
  - `scripts/bench-verify.sh` (new): boots headless, runs `bench`, and asserts the four export files exist and
    are internally consistent (matrix sums = 40, winner ∈ phases, per-phase metric ranges sane).
  - `scripts/p7-verify.sh` (new): the single P7 exit gate (below), wired into `scripts/golden-boot.sh`.
  - Update `docs/02-TASKLIST.md` §P7 and `docs/00-MASTER-PLAN.md` §3/§7 to this revision's gates.
- **Salvage folded in.** The original's export set (`BENCH_COMPARISON.TXT`, `BENCH_REPORT.TXT`,
  `BENCH_PROFILER.LOG`, `BENCH_SPIKES.LOG`) and its matrix-table format.
- **Exit gate.** Adding any test requires editing **only** `apps/SelfTest.HC`; no host script polls a log for
  size-stability; the JSON is not referenced by any gate. `P7.7: PASS`.
- **Risks/ordering.** Do this *before* P7.8 so the conformance test lands in the one runner.

### P7.8 — OpenGL conformance test + visual proof (h)

- **Purpose.** Prove — not claim — that NeoOS implements the full GL 1.3 surface the owner asked for, with a
  real test covering every capability and a screendump as visual evidence.
- **Deliverables.**
  - **`apps/HolyGLConformance.HC`** (new): a conformance battery over the **full GL 1.3 surface**, each assertion
  producing a pass/fail line, invoked by `SelfTest.HC` (`SelfTestGLConformance` → `GLCONFORMANCE: PASS (n/n)`):
    1. **Matrix stacks in both modes** — PROJECTION push/pop depth 4, MODELVIEW depth 16, overflow is a clean
       error (no silent corruption).
    2. **Clear semantics** — `glClear` clears color+depth; `glClearColor`/`glClearDepth` take effect.
    3. **Vertex alpha** — `glColor4f` produces the expected blend (`0xFF800000` at 50%).
    4. **Perspective-correct texturing** — the P4.3 row-boundary test at `v = 3t/(1+2t)`.
    5. **Near-plane clipping** — a triangle crossing `w=0.05` yields the exact clipped polygon area (Sutherland–
       Hodgman), not a rejection.
    6. **All primitive modes** — points/lines/triangles/triangle-strip/triangle-fan each render the expected
       coverage.
    7. **Depth/cull toggles** — Z-test on/off and backface culling on/off change the pixel set as predicted.
    8. **Lighting** — per-fragment Blinn-Phong + Gouraud (ours) plus a per-vertex Lambertian fixture (original),
       each matching an analytic reference within tolerance.
    9. **Textures + blend modes** — NEAREST/LINEAR, REPEAT/CLAMP, alpha blend, exact `div255`.
    10. **`glFlush`** presents the dirty rect through the one `GfxPresent`.
  - **Visual proof:** `gl-conformance` shell command renders a fixed conformance scene (stacks, clipped triangle,
    textured quad, lit mesh, all primitive modes) → QEMU screendump `screenshots/p7_gl_conformance_live.png`;
    `scripts/gl-conformance.sh` runs it headless and diffs the screendump.
- **Salvage folded in.** The deleted `HolyGLTest.HC`'s 4 assertions (matrix push/pop, perspective, Lambertian
  lighting, Z-buffered triangle) are the seed of this battery — expanded to the full GL 1.3 surface. The
  per-vertex directional lighting fixture comes from `kernel/math/holygl.c`.
- **Exit gate.** `GLCONFORMANCE: PASS (n/n)` with **n = 10 capability groups**, every sub-assertion green;
  `RENDER: PASS (0xD28836F)`; screendump captured and stable; `SELFTEST` count **increases** (never decreases).
- **Risks/ordering.** Last P7 step; depends on all others. This is the certificate that closes the "fully
  compatible with everything" requirement.

### P7 exit gate (the whole priority, one command)

`scripts/p7-verify.sh` prints, on one boot:

```
GOLDEN BOOT: PASS
SELFTEST: a/b PASS          (a == b, a >= 87)
PARITY: n/n (0 diff)
CENSUS: PASS (181)
SELF-HOST: PASS
DETERMINISM: PASS (1 vs 4 cores identical: 0xD28836F)
RENDER: PASS (0xD28836F)
GLSURFACE: PASS   CLIP: PASS   NEONMEM: PASS   TILE: PASS   GPUCFG: PASS
TELEMETRY: PASS   BENCH: PASS   GLCONFORMANCE: PASS (10/10)
```

**Definition of done (P7):** one complete GL 1.3 surface with a near-plane clipper, NEON memory kernels, a real
L1/SMP tile pipeline, a GPU config plane with batched VirtIO + page-flip + 32-bit Z, one merged PMU-backed
all-level profiler with spike detection and optimization directives, one real 40-phase 3.5 s/phase benchmark with
four real exports, and a 10-group GL conformance test with a screendump — all under the locked invariants.

### P7 risks (whole-priority)

- **Determinism vs SMP tiling** (P7.3) is the single highest risk — gate it byte-exact before proceeding.
- **PMU on QEMU TCG** (P7.5) may expose fewer counters; degrade gracefully, never fake.
- **8-arg cap / no-prototype / one-init-per-decl rules** (D4/D17/D18/D20) bite hardest in the new modules —
  keep functions small and diagnostics in globals.
- **Benchmark wall time** (P7.6) must stay interruptible or the gate hangs.

---

## P8 — Self-hosting everything

**Purpose.** Finish the self-hosting loop so the C seed is a *bootstrap-only* artifact and the OS can rebuild,
edit, and document itself entirely in HolyC. The compiler must **lose nothing** when the C seed stops being the
runtime owner — which means porting the one compiler feature our `Compiler.HC` still lacks versus the C seed (the
**peephole optimizer**) and proving boot and the compiler themselves are documents. Multicore bring-up must not
depend on QEMU/PSCI quirks, so EFI **MP Services** is ported as a second, firmware-provided SMP path. Two
resource ceilings that the growing UI/compiler have already outgrown (task stack, GIC interrupt count) are raised
at the root. When P8 exits, C is exactly `boot/main.c` + `boot/uefi` and the OS edits and boots itself as
documents.

- **Deliverables.**
  - **Peephole optimizer in `apps/Compiler.HC`** (port from `boot/seed/jit_arm64.c`): the only compiler feature
    the C seed has and we lack. Fold redundant `mov`/`add`/`str`/`ldr` sequences, constant `movz`+`movk`
    fusion, and self-move elimination. Must keep `PARITY: 0 diff` (run the peephole on **both** engines or keep
    it off the parity path — decide in P8.0 and document).
  - **EFI MP Services SMP bring-up** (`apps/Smp.HC`): locate `EFI_MP_SERVICES_PROTOCOL`, `StartupAllAPs`/
    `StartupThisAP`, as a firmware-independent path beside the existing PSCI path. Keeps `SMP: PASS` on any
    firmware that exposes MP Services.
  - **Boot as a document** (`apps/BootDoc.HC`, or a `$BOOT$` node in `apps/DolDoc.HC`): the boot sequence is a
    CDoc (stages as tree nodes, live status cells, a `Reboot`/`Re-run stage` action) instead of a linear
    `doldoc_print`.
  - **Compiler as a document** (`CompilerDocMain()` in `apps/Compiler.HC`): source buffer + Run + output/errors
    as a CDoc, using `apps/ShaderEditor.HC` as the **editor template** (buffer, line numbers, run button).
  - **Raise the task-stack floor** 4 KB → **64 KB** (`apps/Sched.HC`) and **`MAX_GIC_INTERRUPTS`** 128 → **1024**
    (`apps/Gic.HC`) — root fixes for ceilings that silently truncate.
  - Retire any remaining runtime C the seed still owns, if P8.0 shows it is now safe.
- **Salvage folded in.** `boot/seed/jit_arm64.c` peephole pass; the EFI MP Services usage (per the salvage audit);
  `apps/ShaderEditor.HC` as the editor template (ours, already written); the stack/GIC constants from the
  original (`kernel/arch`, `kernel/sched`).
- **Exit gate.**
  ```
  GOLDEN BOOT: PASS
  SELFTEST: a/b PASS (a == b, a >= P7 baseline)
  PARITY: n/n (0 diff)          SELF-HOST: PASS
  PEEPHOLE: PASS                (a known redundant sequence is shortened; behaviour identical)
  MPSERVICES: PASS              (APs online via EFI MP Services OR documented-unavailable fallback to PSCI)
  BOOTDOC: PASS                 COMPILERDOC: PASS
  STACK64K: PASS                GIC1024: PASS
  CENSUS: PASS (181)
  ```
  `apps/*.c` runtime set == `{}` (only `boot/main.c` + `boot/seed/*` + `boot/runtime/{kheap,symbols}.c` +
  `boot/uefi/*` remain).
- **Risks/ordering.** Peephole first (it must not perturb parity — decide the parity policy in P8.0). Boot-as-
  document last (it touches the boot path). The stack/GIC raises are independent and can land early. Raising
  `MAX_GIC_INTERRUPTS` must not grow the census (fixed-cap array, no new allocator sites).
- **Definition of done (P8):** the peephole optimizer is in `Compiler.HC`, EFI MP Services brings cores online,
  boot and the compiler are documents, the stack/GIC ceilings are raised, and C is only `boot/main.c` +
  `boot/uefi`.

---

## P9 — GPU provider

**Purpose.** Turn the software-first renderer into a genuine provider architecture with a **hardware 3D**
backend. P7.4 already landed the transport *plumbing* (batch2/batch3, page-flip ping-pong, the config plane,
32-bit Z, tile parallelism). P9 builds the actual 3D transport on that seam: a **virgl/Venus** provider that
submits GL/Vulkan command streams to the host GPU, behind the `GfxDevice` provider interface, while the software
NEON×SMP path remains the deterministic default and the golden-hash authority. When P9 exits, `GfxDevice` can
select a real host GPU for 3D without changing a single caller, and the software path is provably unaffected.

- **Deliverables.**
  - **Provider seam:** `GfxDevice` gains a provider vtable (`GfxProvider{Init,Submit,Present,Flush,Query}`) with
    two implementations: `gfx_provider_soft` (the existing NEON×SMP path) and `gfx_provider_virtio3d`.
  - **`apps/Virtio3D.HC`** (new): a virgl command-stream builder (context create, resource create/blob, submit
    3D, fence) over the P7.4 VirtIO batch plumbing; a **Venus** path (Vulkan) behind a compile-time/runtime
    switch if the host exposes it. GLSL→virgl shader translation for the fixed-function + fragment-VM shaders.
  - **32-bit Z + 32×32 tile parallelism across 4 cores** are wired through the provider config plane (P7.4) and
    exercised by the HW 3D provider.
  - **Fallback discipline:** if no 3D host is present, `GfxDevice` selects `gfx_provider_soft` — never a stub,
    never a silent half-render.
- **Salvage folded in.** **None exists** — the original C repo had no 3D transport (only 2D virtio-gpu). This is
  genuinely new work, specified against the Collabora/QEMU virgl + Venus specs; P7.4's `virtio_gpu_send_batch2/3`
  and `page_flip` are the reused transport primitives.
- **Exit gate.**
  ```
  GOLDEN BOOT: PASS
  SELFTEST: a/b PASS (a == b, a >= P8 baseline)
  CENSUS: PASS (181)            RENDER: PASS (0xD28836F)   DETERMINISM: PASS
  GPU3D: PASS        (virgl/Venus path renders a lit textured mesh; result matches the software path within
                      tolerance, or the provider reports "unavailable" and soft is selected — never a stub)
  PROVIDER: PASS     (soft<->hw switch is caller-transparent; every caller unchanged)
  ```
- **Risks/ordering.** Depends on P7.4 (plumbing). Requires a host QEMU build with virgl/Venus; if unavailable in
  the sandbox, `GPU3D: PASS` must accept the documented-unavailable branch **without** fabricating output, and
  the provider seam is still proven by the soft provider. Keep the software path the golden authority.
- **Definition of done (P9):** a real virgl/Venus 3D provider behind the `GfxDevice` provider seam, with 32-bit Z
  and 4-core tile parallelism, golden-hash-safe on the software path and caller-transparent to switch.

---

## P10 — Run anything + MCU cluster

**Purpose.** Deliver the "run anything at max native performance" end goal and the "scale down" end goal: a
porting ladder (native → recompiled → WASM → emulation) with a `HolyPort` platform layer and a Sovereign SDL
ABI so existing games/software can be retargeted, plus the same `Surface`/tile abstractions pushed down to an
**MCU cluster** (RISC-V backend + FDT parser) so the render/compute model scales both up and down. When P10
exits, a recompiled or WASM workload runs on NeoOS through `HolyPort`, and the same pipeline runs distributed on
MCU-class targets.

- **Deliverables.**
  - **`apps/WasmJit.HC`** (port — the only WASM→ARM64 JIT): a WASM module decoder + ARM64 JIT (reuses the
    existing JIT emitter), wired to the shell as `wasm <file>`.
  - **`apps/HolyPort.HC`** (new): an SDL/raylib-like platform layer — window, input, audio, files, threads,
    timers — implemented over the **Sovereign SDL ABI** (`GfxDevice` + `Keyboard` + `Mouse` + `VirtioInput` +
    `Timer`). No libc, no host calls.
  - **`apps/StdLib.HC`** (port): `CArray`/`CDict` containers (replace the dead duplicate noted in the P6 sweep —
    one real implementation, not a stub).
  - **`apps/Surface.HC`** (new): a `Surface` abstraction unifying framebuffer/tile/texture targets and a
    **`remote`** provider (render locally, present over a transport).
  - **MCU cluster:** `apps/Mcu.HC` + `apps/Fdt.HC` (new): an **FDT parser** (Pi 4/5, RK3326, Snapdragon device
    trees) and a **RISC-V backend** for the compiler/JIT, with a distributed runtime that dispatches tile jobs to
    MCU nodes (offload model — whole-OS-on-MCU is not the goal).
  - **`apps/SmpDemo.HC`** (port): the SMP demonstration harness, folded into `SelfTest.HC` as a gate.
- **Salvage folded in.** `apps/WasmJit.HC` (WASM→ARM64 JIT), `apps/SmpDemo.HC`, `apps/StdLib.HC`
  (`CArray`/`CDict`) — all present in the original repo (see `docs/05-UPSTREAM-SALVAGE-AUDIT.md`). `HolyPort`,
  `Surface`/`remote`, and the RISC-V/FDT MCU path are **new**.
- **Exit gate.**
  ```
  GOLDEN BOOT: PASS
  SELFTEST: a/b PASS (a == b, a >= P9 baseline)
  CENSUS: PASS (181)
  WASM: PASS        (a WASM module produces the expected result through the JIT)
  HOLYPORT: PASS    (a window opens, input is read, a timer fires, a file is read — over the Sovereign SDL ABI)
  SURFACE: PASS     (local + remote providers present the same image)
  MCU: PASS         (FDT parses a sample DT; a RISC-V target compiles/runs a tile job; cluster dispatch is real)
  ```
- **Risks/ordering.** `WasmJit.HC` and `StdLib.HC` are ports — land them first (low risk). `HolyPort` depends on
  P7.4/P9 providers. MCU/FDT is the most speculative: gate it behind a **real** emulated target (QEMU RISC-V) and
  never claim physical hardware. FDT parsing is the prerequisite for the hardcoded-MMIO cleanup (C11).
- **Definition of done (P10):** `HolyPort` + Sovereign SDL ABI + `Surface`/`remote` + a real RISC-V/FDT MCU
  target run a recompiled/WASM workload end-to-end.

---

## P11 — Deferred / backlog (real, not near-term — do not pull forward)

**Purpose.** Preserve everything from the master plan's deferred backlog so no idea is lost, while keeping it
out of the critical path. Each item is a real subsystem with a named home; none blocks P7–P10.

- **Networking:** `virtio-net` + lwIP (`apps/Net.HC`).
- **USB:** xHCI (`apps/Usb.HC`).
- **Audio:** `virtio-snd` / HDA (`apps/Audio.HC`).
- **Fonts/graphics:** full SDF atlas from a real TTF parser; trilinear mipmaps; full color-space unification
  (linear present + premultiplied alpha everywhere) — the golden 2D path stays pinned.
- **Compiler:** optimizing JIT (SSA + register allocation); incremental recompile cache; class
  inheritance/vtables; `>8`-arg stack spill (today a hard error); the latent `*p` F64 deref fix.
- **DolDoc:** `$EQ$` math typography; `$GRAPH$` telemetry; full `CSprite` opcode set; `SPT_MESH` embedded 3D.
- **RedSea:** in-place sector allocation/reclaim/dynamic `next_alloc_lba`; CRC32C + uberblock ring (from §9.2).
- **Concurrency:** Vyukov bounded MPMC + MPSC per-core run queues; tickless idle; `.HC` ownership of the C JIT
  seed.
- **Scale:** physical mobile SoC bring-up; game ports (Quake/Half-Life), N64Recomp, Android NDK; Ring-0 INT8
  embeddings "semantic dispatch".
- **Hardware:** PMU-driven auto-tuning (feed P7.5 directives back into the config plane).

**Exit gate (P11):** none — this bucket exists to keep the backlog visible; items graduate into a numbered
priority when the owner pulls them forward.

---

## 3. Cross-cutting sweeps (fold into the owning priority)

These are not priorities; they are mandatory hygiene that each priority absorbs. A priority is not green while
any sweep item it touches is open.

| Sweep | Concrete work | Owner priority | Gate |
|---|---|---|---|
| **Typing** | `%d`→`%lld`/`%llX` (~40 sites); function-pointer fields typed `U64`; colors as `I64`; `int` truncation in the compiler; duplicate globals; `g_doc_dirty_mask` shift. | P7 (with P7.5 log work) | `TYPES: PASS` (a grep-based lint in `scripts/`) |
| **Dead code** | Purge every verified 0-call-site function in the P7.0 inventory (dead `gl*` aliases, dead `gfx_*` swap/blend helpers, write-only state). | P7.0/P7.8 | symbol count drops; `CENSUS: PASS (181)` |
| **Committed `.o`/`.a` artifacts** | `git rm --cached` the tracked `boot/uefi/*.o` and `boot/uefi/libuefi.a` (11 files); add to `.gitignore`; keep the vendored `boot/uefi/*.c` sources. | P7.0 | `git ls-files` shows no `.o`/`.a` |
| **Orphan `apps/TestJitP0.HC`** | Remove or fold into `apps/SelfTest.HC` (it is not loaded by `KernelInit.HC`). | P7.0 | no orphan test module |
| **Stale `GEARS_BENCHMARK.LOG`** | Delete the stale root artifact (and `docs/images/`/`screenshots/` duplicates if unreferenced); real logs are `/BENCH_*.TXT`/`.LOG` from P7.6. | P7.6 | no stale log tracked |
| **Stale `p4.3-wip` branch** | Delete the local `p4.3-wip` branch (superseded; its work landed in P4.3/D7). | P7.0 | `git branch` shows `main` only |
| **Duplicate telemetry** | Merge `apps/Profiler.HC` + `apps/PerfOverlay.HC` → one `apps/Telemetry.HC`; merge `apps/BenchCpu.HC` + `apps/BenchReport.HC` → one `apps/HolyBenchmark.HC`. | P7.5/P7.6 | one module each; `KernelInit.HC` loads one |
| **Cross-module accessor rule** | Purge direct `g_hgl.*`/`g_rtex.*` struct-member writes (`Gears3D.HC`, `Physics3D.HC`); route through exported accessors; add a static check to `scripts/`. | P7.0 (lint) | `ACCESSORS: PASS` |
| **Forward-decl / decl rules** | Enforce D17/D18/D20 as a lint (no `Type name(args);` prototypes; one initialized var per decl; declare globals before use). | P7.0 (lint) | `STYLE: PASS` |

---

## 4. One-line definition of done per priority

- **P7:** one complete GL 1.3 surface + near-plane clipper + NEON memory kernels + real L1/SMP tiling + GPU config
  plane with batch/page-flip/32-bit Z, measured by one PMU-backed all-level profiler with spike detection and a
  real 40-phase 3.5 s/phase benchmark, proven by a 10-group GL conformance test — golden hash `0xD28836F`
  bit-exact.
- **P8:** the peephole optimizer is in `Compiler.HC`, EFI MP Services brings cores online, boot and the compiler
  are documents, the stack/GIC ceilings are raised, and C is only `boot/main.c` + `boot/uefi`.
- **P9:** a real virgl/Venus 3D provider behind the `GfxDevice` provider seam, with 32-bit Z and 4-core tile
  parallelism, caller-transparent and golden-hash-safe on the software path.
- **P10:** `HolyPort` + Sovereign SDL ABI + `Surface`/`remote` + a real RISC-V/FDT MCU target run a
  recompiled/WASM workload end-to-end.
- **P11:** the backlog stays visible; nothing here blocks P7–P10.
