# 02 — Full Audit

Scope: 51 `.HC` files (~22,695 LOC), the C bootstrap, and 27 `.md` docs. Read-only analysis.

## 2.1 Bad practices

### Architecture / layering
- **Cyclic dependencies:** `DolDoc → Shell` (executes links), `WM → Shell` (22 calls), `Shell → WM`, `WM ↔ Compositor`.
- **`Compiler.HC` is dead weight at boot:** loaded + compiled by the C JIT every boot, then never called (its own self-test only runs on `run Compiler.HC`).
- **Parallel C/.HC implementations** of the same modules: `kheap.c`↔`KHeap.HC`, `symbols.c`↔`Symbols.HC`, `virtio_blk.c`↔`VirtioBlk.HC`, `redsea.c`↔`RedSea.HC`, `hal_platform.c`↔`HalPlatform.HC` — two sources of truth each.
- **Shadowed allocator:** the `.HC` `KMalloc`/`KFree` is never called; everything uses the C `kmalloc`.
- **Not actually "pure HolyC":** `.HC` code calls C symbols (`doldoc_printf`, `kmalloc`, `memcpy`, `gfx_*`, `timer_*`).

### Duplication
- **3 tokenizers** (`lexer.c`, `Compiler.HC` internal, `Lexer.HC`) and **2 identical `TOK_*` tables**.
- **4 triangle rasterizers** (`gfx_draw_triangle_fill`, `HolyGLDrawTriangleZ`, `RasterTriangleZ`, `TileRasterTri`); two dead.
- **3 font engines** (`gfx_draw_char`, `FontMono` scaled, `FontVector`).
- **2 damage systems** (`g_canv.dirty`, `g_comp.dmg_*`) and **2 present paths** (`CompositorPresent`, `GfxBackendPresent`).
- **`StdLib.HC` ≡ `Table.HC`** (same `CArray`/`CDict`/`Table` classes); both entirely unused.
- **PascalCase + snake_case aliases** for nearly every driver function.
- **Duplicate globals:** `g_kernel_booting` declared in ~20 files; `g_hal_gicd_base`/`g_hal_gicc_base` (HalPlatform+Gic); `g_hal_timer_freq` (HalPlatform+Timer); `top_print_doldoc` (Sched+Top).

### Correctness hazards
- `&function` compiled to `0` (fixed in P1).
- Forward struct types + `#include` unsupported (forward structs fixed in P1; `#include` still missing).
- `DolDoc.HC` brace imbalance (fixed in P1).
- `g_doc_dirty_mask` is `U64` set with `(1 << r)` — undefined for `r ≥ 31`; rows 32–63 alias 0–31.
- Function-pointer params typed `U64` (`WMCreateWindow(..., U64 draw_fn, U64 click_fn)`).
- `%d` used for 64-bit values in ~40 places.
- `g_widget_target` (U64) smuggles `&g_shader_speed` through a **decimal text attribute** and re-parses it.
- **VirtioGpu** sends truncated commands (`RESOURCE_CREATE_2D` 40→32; `TRANSFER_TO_HOST_2D` 56→48) and flattens `ATTACH_BACKING` to one mem entry.
- `timer_get_uptime_ms()` called by WM/Shell/DolDoc/Showcase but defined nowhere (fixed in P1).

### Dead work / stubs
- ~60 zero-caller functions in the render pipeline; entire dead files `Table`, `StdLib`, `Bench`, `HolyBenchmark3D`, `HolyGLTest`.
- Write-only features: Kolibri tile-ownership map, `g_osc_mem_buf`, most of `CGfxBackendState`, `GLVertex.u/.v`.
- `GFX_MODE_SMP_TILED` is cosmetic (no SMP raster dispatch); "Gouraud" is flat-only; texture UVs stored but never sampled; "TrueType" is a mock header parse.
- Morphic `[D] Clone`/`[R] Refresh` print instead of acting; `WIDGET_TREE` has no children.
- Hardcoded lies: WM prints FPS `"60"` and `"4 Cores"`; uptime wraps at 999 s.

### Documentation
- Claims features that don't exist (`jittest` 7/7 — only true after P1's `&function` fix; auto-bench at boot; `GetMemoryMap`; preemptive scheduler; SMP rendering; Lua tier-3) and references deleted C files.
- Doc-vs-doc contradictions (see 2.4).

## 2.2 Typing audit
- **Good:** no implicit-int / missing-return-type functions anywhere.
- **Bad:** (a) `%d` for 64-bit ×~40; (b) `U64 ↔ pointer` in Virtio*/KHeap; (c) fnptr fields typed `U64`; (d) colors stored as `I64` (`CBoxStyle`, `g_widget_val`); (e) `int` used for 64-bit sizes/offsets in the compiler + `(int)` literal truncation; (f) signature mismatches (`SmpSecondaryWorker(U32)` into a `U64` vector slot; `TimerTick()` registered as `fn(data)`; `ExceptionsHandleSync(CTrapFrame*,…)` installed as a raw vector); (g) `Compiler.HC` maps `F64` to an 8-byte integer (no FP at all).

## 2.3 Forward refs / stubs / placeholders
- **Working:** forward function calls + forward global variables (SIC).
- **Broken before P1:** `&function`, forward struct types, `#include`, `case` constants, forward fnptr values. (First two fixed in P1.)
- **Runtime forward refs:** `Keyboard→VirtioInputPoll`, `Mouse→VirtioInputPoll`, `Sched→SmpPrintDolDoc`, `Compositor→wm_set_dirty`/`doldoc_*`, `GfxBackend→gpu_config_open`.
- **Stub emissions:** `symbols_unresolved_trap`→0; `jit_arm64.c` literal-0 at 3 sites; `Compiler.HC` `blr` to 0.
- No TODO/FIXME markers — the "stubs" are silent zeros / no-op bodies.

## 2.4 Documentation evaluation (claims)
- **True:** icache flush; `-cpu cortex-a72`; `g_doc_chars[16384]`; `HolyGL z_avg` hack; `Compiler.HC` zero FP; app LOC table (51 `.HC`, 22,695 LOC).
- **Contradicted:** `jittest` 7/7 (fixed→true); boot autorun of jittest/bench3d; `GetMemoryMap`; preemptive scheduler; SMP rendering; Lua tier-3; `g_doc_chars[6144]/[3072]`; "43 C modules / 31,635 LOC" (actual 18/~8,490); file counts; benchmark phase counts (6/16/40).
- **Doc-vs-doc conflicts:** Lua present vs excised; tile size 16/32/64; phases 6/16/40; grid 6144/3072/16384; identity URL Carlos-Pina vs Satanacio666.

## 2.5 Every `.HC` file classified
Legend: **CORE** kernel, **DRV** driver, **DOC/REN** document/render, **MERGE**, **DEAD**, **DEMO** (removable), **CMP** compiler, **BENCH**.

| File | LOC | Verdict | Notes |
|---|---|---|---|
| Compiler.HC | 2443 | CMP | self-host target (7/7 after P1) |
| Lexer.HC | 887 | DEAD | orphan 3rd tokenizer |
| WasmJit.HC | 222 | DEAD | 4-opcode toy |
| TestJitP0.HC | 213 | CMP/test | keep |
| DolDoc.HC | 2905 | DOC/REN | core; brace fixed |
| Shell.HC | 926 | CORE | dissolve WM/Compositor duties |
| WM.HC | 1075 | DOC/REN→MERGE | windows become DolDoc views |
| Compositor.HC | 599 | MERGE→Render | |
| Render.HC | 839 | REN | single canvas |
| GfxBackend.HC | 374 | MERGE→Device | |
| VirtioGpu.HC | 531 | DRV | fix command lengths |
| RasterTile.HC | 318 | MERGE→HolyGL | one rasterizer |
| HolyGL.HC | 643 | REN | 3D core |
| Math3D.HC | 495 | CORE | prune ~16 dead + aliases |
| Physics3D.HC | 531 | DEMO→fold | benchmark scene |
| Gears3D.HC | 348 | keep render path | DolDoc `$SP` dep |
| FontMono.HC | 295 | MERGE→Fonts | |
| FontVector.HC | 448 | MERGE→Fonts | |
| HalPlatform.HC | 374 | CORE | trim dead wrappers |
| KHeap.HC | 475 | MERGE→C heap | keep telemetry |
| Symbols.HC | 343 | CORE | |
| Table.HC | 337 | DEAD | dup of StdLib |
| StdLib.HC | 338 | DEAD | |
| Sched.HC | 371 | CORE | |
| Smp.HC | 411 | CORE | |
| SmpDemo.HC | 328 | DEMO | |
| Gic.HC | 294 | DRV | dup globals; wire interrupts |
| Timer.HC | 161 | CORE | |
| Exceptions.HC | 309 | CORE | fix vector ABI |
| Keyboard.HC | 306 | DRV | |
| Mouse.HC | 347 | DRV | |
| VirtioInput.HC | 554 | DRV | |
| VirtioBlk.HC | 470 | DRV | |
| RedSea.HC | 761 | CORE/DRV | |
| Profiler.HC | 449 | BENCH | merge w/ PerfOverlay |
| PerfOverlay.HC | 366 | BENCH | merge w/ Profiler |
| BenchCpu.HC | 177 | BENCH | needed |
| BenchReport.HC | 57 | MERGE→bench | |
| HolyBenchmark.HC | 166 | BENCH | THE one |
| HolyBenchmark3D.HC | 89 | DEAD | |
| Bench.HC | 42 | DEAD | |
| HolyGLTest.HC | 86 | DEAD | fold self-test |
| calc.HC | 142 | DEMO | |
| fact.HC | 88 | DEMO | |
| Editor.HC | 160 | DEMO→Shell | |
| Filer.HC | 140 | DEMO | |
| Top.HC | 141 | DEMO→Shell | |
| Showcase.HC | 79 | DEMO→DolDoc test | |
| Menu.HC | 27 | DEMO→DolDoc | |
| ShaderEditor.HC | 108 | DOC | wire or remove |
