# NeoOS — MASTER CONSOLIDATED PLAN (v7, authoritative)

> The **single** source of truth. Consolidates the entire project: vision, verified state, every
> priority, every sub-task, the merge/dissolve/integrate matrix, the bootstrap fix, open decisions,
> the deferred backlog, and the methodology. Supersedes `00-CONSOLIDATED.md`, `00-REALITY-AND-MASTER-PLAN.md`,
> `02-PRIORITY-PLAN.md`, `04-plan.md`, `04-UPDATED-PRIORITIES-AND-CHECKLIST.md`, `05-NEW-TASKLIST.md`,
> `03-NEXT-STEP-TASKLIST.md`, and every older `docs/*.md`.
>
> **Scope corrections applied in v7:**
> 1. **The "Stage-2 blob" is REMOVED.** It was never requested by the owner; it came from the superseded
>    `FUTURE_IMPLEMENTATIONS_MASTER_ROADMAP.md` / `task.md` Phase 16 and was wrongly promoted into P1.
>    See §4. There is **no binary blob** in this plan.
> 2. The self-hosting **flip is DONE and committed** (`0b2db9d`), not pending. See §3.
> 3. Every task is traced to the docs/code it came from. Nothing is invented; nothing is dropped.

---

## 0. How to use this document

- Priorities run **P0 → P10**. Do them in order; each is the foundation for the next.
- **Do not start a lower priority until the one above it is green** (`scripts/golden-boot.sh` PASS).
- At the **end of each priority**, stop and ask the owner what to do next (stage-by-stage gate).
- The **merges/dissolutions** (§7) are gated behind P1 and land inside P4/P5/P7.
- The **deferred backlog** (§11) is real but explicitly *not* near-term. Do not pull it forward.

---

## 1. Vision & end goals

1. **Self-hosting** — everything in HolyC; C only for the minimal UEFI bootstrap (`boot/main.c` + `boot/uefi`).
2. **One unified render pipeline** — HolyGL as an *API with backends* (soft NEON×SMP → GPU → remote),
   one tile pipeline, **no scalar fallback** (AArch64 mandates NEON).
3. **A real TempleOS-model DolDoc** — CDoc/CTree, per-char attributes, the full two-letter tag set,
   macros/forms/sprites/anchors/links/trees, **windows-as-documents**.
4. **A unified shell** — documents emit *Actions*; the shell executes; **no cycles**.
5. **One HolyGL-max benchmark** — 40 phases, real NEON/Gouraud/texture/Z/SDF.
6. **Run anything at max native performance** — porting ladder (native → recompiled → WASM → emulation)
   + `HolyPort` (SDL/raylib-like) + a C→HolyC / LLVM→HolyC toolchain.
7. **Scale down** — the same `Surface`/tile abstractions → an **MCU cluster** (future).
8. **No unnecessary C.**

---

## 2. Invariants (never break)

1. **C only in the bootstrap:** `boot/main.c` + `boot/uefi/*` + `boot/seed/*` (the compiler seed). No new C without retiring something.
2. **Golden gate green after every change** — `scripts/golden-boot.sh` must print `GOLDEN BOOT: PASS`.
3. **No unbounded compiler buffers** — every cap is a hard error (`g_hc_error`), never silent truncation.
4. **No JIT miscompiles / no special-casing** — fix the general codegen/parser path, never a module name.
5. **No UI cycles** — `DolDoc⇄Shell`, `WM⇄Shell`, `WM⇄Compositor`, `DolDoc⇄Compositor` stay broken.
6. **Never leave the tree red.**
7. **Test manually** — UART + QEMU protocols for every change; never trust a build alone.
8. **Persist after every green step** — `git commit` + `git bundle create /home/user/project/neo-os.bundle --all`.
9. **One merge/dissolve per commit**, each ending green.

---

## 3. Current verified state (green checkpoint + one red WIP)

- **Boot:** reaches `DolDocShell`; **32-subsystem banner** (loads **34** modules — banner text is wrong);
  **0 exceptions**; **0 undefined identifiers**.
- **Golden gate:** **PASS** with the self-hosting flip **ON**. JIT battery: **67/67**.
- **Self-hosting FLIP: DONE** (commit `0b2db9d`). `apps/KernelInit.HC` sets `g_hc_ready = 1` after
  `Compiler.HC` loads; every later module is compiled by `Compiler.HC` via `CompilerCompileAndRun`.
  Precisely: **7 modules** are still compiled by the C JIT (`HalPlatform, Timer, Gic, Exceptions, KHeap,
  Symbols` + `Compiler.HC`); **27 modules** are compiled by `Compiler.HC`.
- **P1 fixes already committed:** F64 codegen + intrinsics; frame locals; `&function`; forward structs;
  read-path late-binding; `#include` (C JIT); inline `asm{}`; op-stack/name-copy bounds; caps→hard errors;
  per-module resets; Math3D F64-global hang fix (`6f15bee`); global-array element scale (`d33e0e6`);
  cross-module struct table + local cap 256 (`1ecd5ae`); packed struct layout (`0619cb1`);
  DolDoc global-array addressing (`9cef4de`); >8-arg calls → hard error (`0738474`).
- **P1 COMPLETE** (commits `b4242c8` → `f763612`): the blob WIP was discarded; **parity PASS** (34/34
  modules, all key globals agree, 0 undefined/unresolved); self-test **7/7**; battery **65/65**; the C
  seed compiler relocated to **`boot/seed/`** (Option A — no blob); `TOK_*` unified to one source of truth
  (`boot/seed/tok.h`) enforced by `scripts/check-token-parity.py`. Golden gate PASS with the flip ON.
- **Persisted:** `neo-os.bundle`, `neo-os-src.tar.gz`, `neo-os-docs/`, `public/neo-os.zip` (OS only),
  `public/neo-os-full.zip` (OS + viewer + docs).

---

## 4. Scope correction: the "blob" is removed

**What it was:** a precompiled machine-code image of `Compiler.HC` (plus a relocation table + manifest),
to be embedded in the boot path so the C JIT would not be needed to seed the compiler.

**Why it is gone:** it is a frozen, host-C-generated binary — the opposite of `.HC` sovereignty — and the
owner never asked for it. It came from the **superseded** `FUTURE_IMPLEMENTATIONS_MASTER_ROADMAP.md`
(Phase 5.4) and `task.md` (Phase 16); the *authoritative* `NEO_OS_MASTER_PLAN.md` L1.6 and
`03-design.md §3.9` only say "flip boot; retire `jit_arm64.c`/`lexer.c`/`table.c`." It was wrongly
promoted into P1's Definition-of-Done by `P1-DELEGATION.md` §0 item 6 / §A5, which sent an agent into a
large, off-plan detour.

**What replaces it:** an honest bootstrap design (§8). The seed compiler is *necessary* C; the question is
where it lives and how small it is — never a binary blob.

---

## 5. Priority ladder (P0 → P10)

| Pri | System | Status | Gate to exit |
|---|---|---|---|
| **P0** | Observability & debug harness | ✅ DONE | — |
| **P1** | Compiler (self-host) | ✅ DONE — flip + parity + tokenizer + seed (Option A) | both engines agree on all 34 modules |
| **P2** | Minimal bootstrap / fix the bootstrap | ⬜ | C = `boot/main.c` + `boot/uefi` + `boot/seed` only |
| **P3** | Kernel correctness | ⬜ | timer IRQ fires; real scheduler; one allocator/table/HAL |
| **P4** | Rendering unification (merges) | ⬜ | one `GfxDevice` + one tiled rasterizer + one font |
| **P5** | DolDoc (real model + dissolution) | ⬜ | CDoc/CTree; windows are docs; no char grid |
| **P6** | Shell (action executor over a CDoc) | ⬜ | no cycles; shell output is a CDoc |
| **P7** | Benchmark (one HolyGL-max suite) | ⬜ | one real suite; profilers merged |
| **P8** | Self-hosting everything | ⬜ | boot as a document; only boot C remains |
| **P9** | GPU provider | ⬜ | virtio-gpu 3D / native |
| **P10** | Run anything + MCU cluster | ⬜ | `HolyPort` + `Surface`/`remote` |

---

## 6. Full tasklist per priority

### P0 — Observability & Debug Harness ✅ DONE
`run-viewer-vm.sh` (+ gdbstub flag), `uart-bridge.mjs`, `uart-repl.py`, `run-jit-golden.py` +
`tests/jit_golden/cases.json` (**67 cases**), `golden-boot.sh`, `audit-symbols.sh`, `crash-decode.py`,
`screenshot-diff.py`, plus `p1-flip-test.sh` (hang detector) and `p1-parity.sh` (both-engine diff).

### P1 — Compiler (self-hosting) — IN PROGRESS

**P1.0 Housekeeping (do first):**
- [ ] Discard the blob WIP: `git checkout compiler/jit_arm64.c`, delete `compiler/seed_blob.h`; confirm
      `make all` + `golden-boot.sh` PASS at `0b2db9d`.
- [ ] Update `P1-DELEGATION.md`/`NEXT-STEPS.md` to remove the blob items (they name a non-existent
      `scripts/compile-parity.sh`; the real tool is `scripts/p1-parity.sh`).

**P1.1 Parity (the P1 exit gate):**
- [ ] Run `scripts/p1-parity.sh`: compile **all 34 modules** with both engines; diff module set, per-module
      result, undefined/late-bound reports, key globals. All must agree.

**P1.2 Tokenizer unification:**
- [ ] One `TOK_*` enum (the two are numerically identical 0–70); generate both from one table; delete the
      duplicate lexer in `Compiler.HC` / `compiler/lexer.c` as appropriate.

**P1.3 Remaining compiler capability (only if a module needs it):**
- [ ] Diagnostics (`file:line`, type errors).
- [ ] `#include` **inside `Compiler.HC`** (mirror the C JIT's `expand_includes`).
- [ ] `auto` — support or hard-error (currently tokenizes but is not consumed → hang).
- [ ] Table literals `{…}`; expression/string global initializers (if any module needs them).
- [ ] Global forward cell via `symbols_lookup_or_reserve` (like the C JIT).
- [ ] >8-arg calls: currently a hard error (`0738474`); optionally spill to stack later.

**P1.4 Seed-compiler decision + implementation (see §8):**
- [ ] Decide the no-blob seed mechanism with the owner.
- [ ] Implement it; retire/relocate the C compiler accordingly.

**P1 exit:** parity PASS on all 34 modules + the seed decision implemented + golden gate PASS with the flip ON.

### P2 — Minimal bootstrap (make everything but the irreducible seed HolyC)

**Truth (verified, not aspirational):** the bootstrap C is *physically confined* to `boot/` but
*functionally live*. The build has **9 `.c`** — `boot/main.c`; `boot/seed/{lexer,table,jit_arm64}.c`
(the compiler seed); `boot/runtime/{kheap,symbols,hal_platform,virtio_blk,redsea}.c` (the runtime) — plus
**4 `.S`**. `boot/main.c` registers the C runtime as the live symbols (`kmalloc`, `kfree`, `symbols_*`,
`redsea_read_file`, `hal_flush_cache`, …), so `.HC` modules call **C** for allocation, symbols, block I/O
and the FS. The `.HC` twins (`KHeap.HC`, `Symbols.HC`, `HalPlatform.HC`, `VirtioBlk.HC`, `RedSea.HC`) are
loaded but **mostly dead** (`KMalloc`/`KFree`/`SymRegister`/`VirtioBlk*`/`RedSea*` have ~0 callers;
`SymLookup` is used once by `DolDoc.HC`; the `g_hal_*` data is live in `HalPlatform.HC`). **This is NOT yet
"minimal C + everything else `.HC`."** It is "C confined to `boot/`, still live".

**The irreducible C (the true minimal bootstrap):**
1. UEFI entry + GOP + memory map — `boot/main.c` + `boot/uefi/*`.
2. A compiler to turn `.HC` into code — the seed (circular: something must compile `Compiler.HC`, §8).
3. An allocator + symbol table — the compiler needs them to allocate/register.
4. A block driver + FS — to *read* the `.HC` files.
Everything above that layer (sched, SMP, GIC, timer, exceptions, drivers beyond block, rendering, DolDoc,
shell, apps) is **already `.HC`**.

**Work — retire the C runtime by making the `.HC` twins live, least-circular first:**
- [x] `GetMemoryMap`-derived heap/JIT pool (`7199c3e`).
- [x] C physically confined to `boot/seed` + `boot/runtime` (`708c92a`, `P2b.1`).
- [ ] `HalPlatform.HC` live (data already `.HC`; move `hal_platform_init`/`hal_flush_cache`).
- [ ] `VirtioBlk.HC` live (own the virtqueue; stop delegating to C).
- [ ] `RedSea.HC` live (own the FS; retire `redsea.c`).
- [ ] `Symbols.HC` live (retire `symbols.c`).
- [ ] `KHeap.HC` live (retire `kheap.c`) — last, most circular.
- [ ] Delete each C file once its `.HC` replacement is load-bearing; keep only the irreducible seed.
- [ ] **Exit:** C = `boot/main.c` + `boot/uefi/*` + the compiler seed (§8) + the minimal
      allocator/symbols/loader substrate that cannot be `.HC`.

### P3 — Kernel correctness
- **Allocator:** one allocator (C `kheap.c` is live; `KHeap.HC`'s `KMalloc/KFree` are dead) — dissolve the
  shadow, then port to `.HC`; remove `HEAP_CANARY`/`CHeapBlock` duplication.
- **Symbols:** one table (C `symbols.c`, 1024 buckets, live; `Symbols.HC` 256 buckets, fallback).
- **HAL:** one set of `g_hal_*` globals (C `hal_platform.c` live; `HalPlatform.HC` duplicate cells); add
  the missing platforms + `g_hal_timer_freq`.
- **Timer:** arm `CNTP_TVAL_EL0`/`CNTV_TVAL_EL0`; register the timer IRQ (`GicRegisterHandler(27, TimerTick)`).
- **GIC:** dedupe `g_hal_gicd/gicc_base`; register the timer handler at boot.
- **Scheduler:** wire `cpu_switch_context` (assembled + registered, **zero callers** today); real run
  queue; `task_yield` from the tick; make it preemptive.
- **SMP:** per-core run queues; drop the silent local-execution fallback; delete `SmpWorkerLoop1/2/3`
  copy-paste; idle secondaries `wfe`/`sev` (no spin loops).
- **Exceptions:** fix `vectors.S` hardcoded `x3=1` (kernel faults must reach the BSOD); kill the
  `while(1)__wfe()` re-entrancy hang; clean ESR/FAR/ELR dump.
- **Globals:** dedupe `g_kernel_booting` (**redeclared in 14 files** — start here), `g_hal_*`,
  `top_print_doldoc`.
- **Exit:** a timer IRQ fires; preemptive scheduling works; memory is discovered, not hardcoded.

### P4 — Rendering unification (merges — see §7.2)
- [ ] Merge `Render` + `GfxBackend` + `VirtioGpu` + Compositor damage/present → **`GfxDevice`**.
- [ ] Fix `VirtioGpu` truncated commands: `RESOURCE_CREATE_2D` 40→32 (`VirtioGpu.HC:345`),
      `TRANSFER_TO_HOST_2D` 56→48 (`:417`); real `ATTACH_BACKING`.
- [ ] One **tiled NEON rasterizer**: promote `RasterTile.RasterTriangleZ` (real per-pixel Z); wire
      `HolyGLSubmitTriangle` to it; delete `HolyGLDrawTriangleZ` (`z_avg`), `gfx_draw_triangle_fill`,
      dead `TileRasterTri`/`TileClear`; one Z-buffer.
- [ ] Real features: per-pixel Z, perspective-correct **textures** (sample the stored UVs), **SDF**,
      a small **fragment-shader VM**; **NEON** (4 px/op); **SMP tiles** actually dispatched.
- [ ] Merge → **`Fonts.HC`**: `FontMono` + `FontVector` + Render's `gfx_draw_char`; drop the mock SFNT.
- [ ] One damage system, one present path. Themes stay (move owner per §7.2).
- [ ] Delete ~60 dead fns + write-only state (`raster_engine`, `tile_size`, `zprecision`, `culling`,
      tile map). Determinism test (1 core vs N cores).
- **Exit:** a triangle, textured quad, SDF glyph, and shaded mesh all render through one path with real Z.

### P5 — DolDoc (real model + dissolution — see §7.5)
- [ ] Rewrite `DolDoc.HC` → **CDoc/CTree** of entries + **per-char attributes**; delete `g_doc_chars/fg/bg`,
      `g_doc_link_idx`, `g_hist_chars`.
- [ ] Full two-letter tag set: `TX CR SR CU TB CL PB PL LM RM HD FO ID FD/BD/FG/BG PT WW UL IV BK SX SY
      CM AN LK BT DA MA SP FI` — including `$MA` macros, `$DA` forms, `$AN` anchors, `$ID` trees, typed
      `$LK` links, word-wrap.
- [ ] Windows are documents: `$WIN$`/`$SPLIT$`/`$BLUR$`/`$ELEV$`; **dissolve `WM.HC`**; **dissolve
      `Compositor.HC`**.
- [ ] Reactive cells (generalize `DolDocPatchTarget`); RedSea document persistence; the DolDoc reference
      is a DolDoc (dogfood).
- [ ] Fix `g_doc_dirty_mask` (`((U64)1 << r)`).
- **Exit:** a doc with text/link/button/slider/form/tree/3D-scene/shader renders + responds; no char grid.

### P6 — Shell (action executor over a CDoc)
- [ ] **Action protocol:** documents emit `Action{Run,Open,Set,Clone,Focus}`; the shell executes.
- [ ] **Command registry:** fill the dead `shell_register_cmd` (`Shell.HC:42`, zero callers) and replace
      the if/else ladder (`Shell.HC:467-751`).
- [ ] **Break all cycles** (`DolDoc→Shell`, `WM→Shell`, `WM↔Compositor`).
- [ ] **Shell buffer is a CDoc**; keep the input/event loop.
- [ ] Fold `top`/`edit`/`filer` into shell-backed docs.
- **Exit:** no cycles; shell output *is* a CDoc.

### P7 — Benchmark (one HolyGL-max suite)
- [ ] Merge `HolyBenchmark` + `BenchCpu` + `BenchReport` → one suite; merge `Profiler` + `PerfOverlay`
      → one telemetry engine.
- [ ] **Real 40 phases** (or relabel): per-pixel Z, textures, Gouraud (interpolated), SDF, real NEON;
      remove the write-only `g_bench_mode`; fix `BenchCpuMathNeon` (currently an integer LCG loop).
- [ ] Write `/BENCH_REPORT.TXT` (+ `/BENCH_COMPARISON.TXT`, `BENCH_PROFILER.LOG`, `BENCH_SPIKES.LOG`).

### P8 — Self-hosting everything
- [ ] Boot as a document; only `boot/main.c` + `boot/uefi` in C; finish the self-host loop.

### P9 — GPU provider
- [ ] virtio-gpu 3D (virgl/Venus) + native GPU drivers, behind the HolyGL provider seam.

### P10 — Run anything + MCU cluster
- [ ] `HolyPort` platform layer + C→HolyC / LLVM→HolyC toolchain (run decompiled games).
- [ ] `Surface` + `remote` provider → **MCU cluster** (RISC-V backend + distributed runtime).

### Cross-cutting (fold into the relevant priority)
- **Typing sweep:** `%d`→`%lld`/`%llX` (~40 sites); fnptr fields typed `U64`; colors as `I64`;
  `int` truncation in the compiler; duplicate globals; `g_doc_dirty_mask` shift.
- **Docs:** rewrite README/docs to the verified truth; this file supersedes the older `docs/*.md`.
- **Remove demos:** `calc`, `fact`, `SmpDemo`, `Showcase`, `Menu`, `Editor`, `Filer`, `Top`.
- **Naming:** one convention (kill PascalCase+snake aliases); single source of truth per module.

---

## 7. Merge / dissolve / integrate matrix (gated behind P1)

> File-level detail lives in `docs/master/P2-P6-MIGRATION-SPECS.md` (read it before each merge).
> One merge per commit; each ends green.

### 7.1 Merge
| Fuse into | Sources | Priority |
|---|---|---|
| `Fonts.HC` | `FontMono.HC` + `FontVector.HC` + Render `gfx_draw_char` | P4 |
| `GfxDevice.HC` | `GfxBackend.HC` + `VirtioGpu.HC` (+ Render damage/present) | P4 |
| one tiled rasterizer (`Raster`/`HolyGL`) | `Render.HC` + `RasterTile.HC` + `HolyGL.HC` | P4 |
| `Telemetry.HC` | `Profiler.HC` + `PerfOverlay.HC` | P7 |
| one `HolyBenchmark.HC` | `HolyBenchmark.HC` + `BenchCpu.HC` + `BenchReport.HC` | P7 |
| one compiler | `compiler/*.c` → `Compiler.HC` (as far as the seed allows, §8) | P1/P2 |

### 7.2 Dissolve
| Dissolve | Into | Priority |
|---|---|---|
| `WM.HC` | DolDoc `$WIN$`/`$SPLIT$` views | P5 |
| `Compositor.HC` | DolDoc single-pass (damage/present → GfxDevice; theme → DolDoc-owned) | P5 |
| char grid `g_doc_chars/fg/bg`, `g_hist_chars` | CDoc/CTree text runs | P5 |
| duplicate C/.HC stacks | one each | P2/P3 |

### 7.3 Retire
- `compiler/jit_arm64.c`, `lexer.c`, `table.c` — per the seed decision (§8), not via a blob.
- bootstrap runtime C: `kheap.c`, `symbols.c`, `hal_platform.c`, `virtio_blk.c`, `redsea.c` — once their
  `.HC`/unified versions are boot-load-bearing.

### 7.4 Globals to dedupe (before any merge)
`g_kernel_booting` (14 files), `g_gfx_cfg` (owned Render, used GfxBackend), `g_theme` (owned Compositor,
read everywhere), `g_prof`/`g_perf`, `g_canv`/`g_comp`, `g_hgl_zbuf`/`g_tile_zbuf` (two Z-buffers),
`g_hal_gicd/gicc_base`, `g_hal_timer_freq`, `top_print_doldoc`.

### 7.5 Files deleted (cumulative)
`FontMono.HC`, `FontVector.HC`, `GfxBackend.HC`, `VirtioGpu.HC`, `RasterTile.HC`, `PerfOverlay.HC`,
`BenchCpu.HC`, `BenchReport.HC`, `WM.HC`, `Compositor.HC` (10 files) → replaced by `Fonts.HC`,
`GfxDevice.HC`, one `Raster`/`HolyGL`, `Telemetry.HC`, one `HolyBenchmark.HC`, DolDoc `$WIN$` views.

---

## 8. The bootstrap fix (the seed-compiler question — NO blob)

**The paradox:** `Compiler.HC` must be compiled before it can compile anything. Today the C JIT
(`boot/seed/jit_arm64.c`) compiles `Compiler.HC` (and the 6 modules it needs). To remove the C JIT you need
*something* to produce `Compiler.HC`'s machine code at boot.

**DECIDED — Option A (implemented, commit `708c92a`).** The blob is rejected, so the seed compiler is
*necessary* C. It now lives in **`boot/seed/`** (`jit_arm64.{c,h}`, `lexer.{c,h}`, `table.{c,h}`), i.e.
inside the bootstrap substrate, documented as the one necessary seed. Every `.c` in the build is under
`boot/`. No binary artifact; the seed is readable C source. Later (P2/P8) it can be minimized or replaced
by Option B/C.

- **Option A — Keep the C seed compiler, confined to the bootstrap (recommended).** Move/keep it as
  bootstrap substrate (e.g. under `boot/`), documented as the one necessary seed. C stays confined to
  `boot/main.c` + `boot/uefi` (+ the seed). No binary artifact; the seed is readable C source.
- **Option B — Fold a minimal HolyC-subset seed compiler into `boot/main.c`.** Same idea, one file; the
  seed is as small as possible.
- **Option C — True self-host from source.** A tiny seed compiles `Compiler.HC` from `.HC` source; the
  running `Compiler.HC` then recompiles itself (self-verify). This is the ideal end state; A/B are its
  prerequisites.

Options B/C remain possible later (minimize the seed, or reach true self-host from source). **No blob. No
frozen binary.**

---

## 9. Verification matrix (run after every change)

| Check | Command | Expected |
|---|---|---|
| Golden gate | `scripts/golden-boot.sh` | `GOLDEN BOOT: PASS` |
| Self-test | UART `CompilerSelfTest();` | `All 7 / 7 tests passed` |
| Engine parity | `scripts/p1-parity.sh` | engines agree |
| Module set | `scripts/p1-parity.sh` table | one row per `KInitLoad` |
| Undefined syms | `scripts/audit-symbols.sh` | 0 undefined, 0 unresolved |
| JIT battery | `scripts/run-jit-golden.py` | all non-known cases pass |
| Visual | `scripts/screenshot-diff.py` | no unexpected diff |
| Cycles | `rg "shell_run_command" apps/DolDoc.HC apps/WM.HC` | empty |

Persist after every green step: `git commit` + `git bundle create /home/user/project/neo-os.bundle --all`.
Serialize VM/build/git with `flock -w 900 /tmp/neo-os-vm.lock` (start the VM with `flock --close`).

---

## 10. Open decisions (ask the owner at each stage boundary)

1. ~~**P1→P2 — Seed compiler**~~ **RESOLVED: Option A** (seed relocated to `boot/seed/`, commit `708c92a`).
2. **P5 — Per-char attributes vs per-run styling** (authentic-but-heavy vs cheap-and-simple).
3. **P5 — `$MA` macros:** JIT'd HolyC vs an interpreted tag language.
4. **P6 — Shell-as-document scope:** whole shell vs output pane only.
5. **P4 — Tile size** (32×32 vs 64×64) and bin-then-raster vs raster-then-optimize.
6. **P4 — Fragment shaders:** tiny HolyC shader VM vs fixed-function for v1.
7. **P9 — GPU scope:** software-first with a stubbed seam (recommended) vs GPU-first.
8. **P10 — MCU target:** RISC-V vs Xtensa; whole-OS vs render/compute offload (offload recommended).

---

## 11. Deferred backlog (real, but NOT near-term — do not pull forward)

From the original dossiers; kept so nothing is lost. These belong to P9/P10 or later:

- **Compiler:** class inheritance + vtables; optimizing JIT (SSA + register allocation); incremental
  recompile cache (Zig-style); table-literal/global-initializer breadth.
- **Rendering:** Blinn-Phong; bilinear/trilinear textures; alpha blend modes (additive/multiply);
  NEON 2×2 quad shadertoy engine (raymarching, Mandelbulb, Perlin); Wavefront OBJ loader; `$EQ$` math
  typography; `$GRAPH$` telemetry; full CSprite opcode set; `SPT_MESH` embedded 3D.
- **Kernel/hardware:** FDT parser (Pi 4/5, RK3326, Snapdragon); audio (virtio-snd/HDA); networking
  (virtio-net + lwIP); USB (xHCI); PMU hardware telemetry (`PMCR_EL0`, `PMCCNTR_EL0`).
- **Research (manifesto-level, not implemented):** Ring-0 INT8 embeddings "semantic dispatch" engine;
  physical mobile SoC bring-up; game ports (Quake/Half-Life), N64Recomp, Android NDK.
- **Benchmark:** the 16-phase and 6-phase matrices in the old docs are superseded by the one 40-phase suite.

---

## 12. Method & persistence

- **Golden gate** after every change; **manual UART/QEMU** verification of the new behavior.
- **Debug via protocols:** monitor (`screendump`, `sendkey`, `info registers`, `xp /Ni`), VNC viewer
  (`/neo-os`), gdbstub, `crash-decode.py`.
- **Persistence:** commit + bundle after every green step; never rely on `/tmp` or paths outside the
  project. The sandbox can reset.
- **History of this project:** cloned → booted headless → built the viewer → frame-local fix → C pruning
  → deep audit → a sandbox reset that wiped the clone (recovered + re-applied) → P0 harness → P1 compiler
  hardening → **P1 flip (0b2db9d)** → this consolidation.
