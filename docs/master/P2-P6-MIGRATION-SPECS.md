# P2–P6 MIGRATION SPECS — gated merge targets

> **Author:** Agent B (verification + specs). **Status:** SPEC ONLY — no code changes.
> **Gate:** all of this is gated behind P1 (self-hosting flip). Do not start any merge until
> `docs/master/P1-DELEGATION.md` §0 (P1 DoD) holds.
> **Method:** every claim below was read from the tree at commit `a937748`; `file:line` cites are
> exact at that revision. Where the delegation/master-plan text disagrees with the code, it is
> flagged under **Discrepancies**.
>
> Companion docs: `P1-DELEGATION.md`, `NEXT-STEPS.md`, `SKILL.md`, `00-REALITY-AND-MASTER-PLAN.md`,
> and the persisted `NEO_OS_MASTER_PLAN.md` (project root).

---

## 0. Ground rules for every merge

1. **One merge per commit**, each ending green: `scripts/golden-boot.sh` → `GOLDEN BOOT: PASS`,
   `CompilerSelfTest()` 7/7, and `scripts/p1-parity.sh` PASS (once P1 flip is on).
2. **Delete, don't keep.** Each merged module's file is deleted from `apps/` (and therefore from
   `build/redsea.img`, which is built by `scripts/mkredsea.py` from `apps/`). Remove the matching
   `KInitLoad("X.HC");` line from `apps/KernelInit.HC`.
3. **No UI cycles** (delegation §2): `DolDoc⇄Shell`, `WM⇄Shell`, `WM⇄Compositor`,
   `DolDoc⇄Compositor` must stay broken after each step. Current cycle edges are listed in §7.
4. **Globals are heap-allocated per declaration** by the JIT (`SKILL.md` §1). A symbol redeclared in
   two `.HC` files gets a second heap cell and re-registers the symbol name in place
   (`kernel/symbols/symbols.c:63`), silently aliasing. **Dedupe before merging.**
5. **Verification step** for every item = the three checks in (1) plus the specific probes named in
   that section's *Verify* line.

---

## 1. FontMono + FontVector → `Fonts.HC`

### 1.1 What actually exists (read from code)

| File | Globals | Public entry points | Real consumers |
|---|---|---|---|
| `apps/FontMono.HC` (296 L) | `g_font_metrics` (:29), `g_font_atlas` (:30), `g_test_tables[8]` (:31), `g_mono_glyphs[1520]` (:34) | `FontMonoInit` (:77), `FontInitAtlas` (:106), `FontMonoDrawCharScaled` (:111), `FontMonoDrawStringScaled` (:145), `FontDrawChar` (:168), `FontDrawString` (:172), `FontMeasureString` (:176), `FontMeasureWrappedHeight` (:197), `FontParseTableDirectory` (:51) | **none outside the file** |
| `apps/FontVector.HC` (449 L) | `g_fv` (:12) | `BezierEval1D` (:16), `VectorDrawLine` (:24), `VectorDrawBezier` (:28), `FvMapX/Y` (:46/:50), `FvLine/FvBez/FvArc*/FvOval/FvDot` (:54–:90), `FontVectorDrawChar` (:93), `FontVectorCharAdvance` (:325), `FontVectorMeasureString` (:332), `FontVectorDrawString` (:351), `VectorDrawGlyph` (:377), `VectorDrawString` (:382), `FontVectorMain` (:387) | `apps/DolDoc.HC` only |

**Key findings**

* **FontMono's glyph data is a redundant copy.** `Render.HC:583` (`gfx_draw_char`) reads the C table
  directly via `font_get_8x16_data()` (declared `boot/main.c:55`, registered `boot/main.c:201`).
  `FontMonoInit` copies the *same* table into `g_mono_glyphs[1520]` (`FontMono.HC:78-84`) and nothing
  outside `FontMono.HC` reads `g_mono_glyphs`. The 1x/2x draw wrappers
  (`FontMonoDrawCharScaled` etc.) have **zero external callers** — `rg` finds them only inside the
  file and its self-test.
* **FontVector is the real second font engine**, used by the DolDoc `$FONT$` tag renderer:
  `DolDoc.HC:2148,2152,2153,2156,2157,2169,2179,2181,2182,2193,2211,2213` (via
  `symbols_lookup("FontVectorDrawString")` at `:2148` and `:2211`). The tag itself is parsed by
  `DolDocParseFontText` (`DolDoc.HC:841`), which only records a widget; the actual glyph draw happens
  in the `DolDocPrint`/`OmniTapeReplay` render path.
* `FontParseTableDirectory` (`FontMono.HC:51`) is a real SFNT directory parser but is only exercised
  by `FontMonoSelfTest` (`:224`) — no runtime caller. It is dead weight for the merge.

### 1.2 Migration steps (file-level)

1. Create `apps/Fonts.HC` with one metrics struct and one atlas struct:
   * `CFontMetrics` (from `FontMono.HC:12-20`) + `CFontAtlas` (`:22-27`) → single `CFonts` global.
   * Vector context `CFvCtx` (`FontVector.HC:5-10`) folded in as `CFonts.fv`.
2. Move the **live** 8×16 path: keep a single `FontsInit()` that calls `font_get_8x16_data()` once and
   stores the pointer (do **not** copy into a second 1520-byte array; delete `g_mono_glyphs`).
3. Move `FontVectorDrawChar` + all `Fv*` helpers + `BezierEval1D` + `FontVectorMeasureString` +
   `FontVectorDrawString` into `Fonts.HC` unchanged; keep the names so `DolDoc.HC` call sites
   (`:2148`…) keep resolving. `FontVectorCharAdvance` (`:325`) and `FontVectorMain` (`:387`) move too.
4. Keep a thin `FontDrawChar`/`FontDrawString`/`FontMeasureString` shim in `Fonts.HC` that delegates
   to `gfx_draw_char`/`gfx_draw_text` (so `FontMono.HC`'s public names survive if anything starts
   calling them), but **delete** `FontMonoDrawCharScaled`/`FontMonoDrawStringScaled`/
   `FontInitAtlas`/`FontParseTableDirectory`/`CFontTableRecord`/`g_test_tables`.
5. Update `apps/KernelInit.HC:55-56`: replace the two `KInitLoad("FontMono.HC");` /
   `KInitLoad("FontVector.HC");` with a single `KInitLoad("Fonts.HC");`.
6. Delete `apps/FontMono.HC` and `apps/FontVector.HC`.

### 1.3 Globals to dedupe
* `g_font_metrics`, `g_font_atlas`, `g_mono_glyphs`, `g_test_tables` (FontMono) — collapse to
  `g_fonts.*`; drop `g_mono_glyphs` entirely.
* `g_fv` (FontVector) — becomes `g_fonts.fv`.
* `g_kernel_booting` (declared in both files' tails? only FontMono/FontVector *read* it; not
  redeclared there) — leave to §7.

### 1.4 Files to delete
`apps/FontMono.HC`, `apps/FontVector.HC`.

### 1.5 Verify
`golden-boot.sh` PASS; boot banner + `$FONT,text="NEO-OS 3.0 …"` still renders (screenshot diff vs
`/tmp/golden-boot.png`); `g_fonts.char_width == 8` over UART; `p1-parity.sh` module set drops 1 net
module and both engines agree.

---

## 2. GfxBackend + VirtioGpu → `GfxDevice`

### 2.1 What actually exists

| File | Globals | Public entry points | Consumers |
|---|---|---|---|
| `apps/GfxBackend.HC` (375 L) | `g_gfx` (`CGfxBackendState`, :42) | `GfxBackendInit` (:44), `GfxBackendSetMode` (:62), `GfxBackendGetMode` (:77), `GfxBackendGetName` (:81), `GpuSet/Get*` (:85–:150), `GfxBackendPresent` (:152), `gfx_backend_set_mode/get_mode/get_name/present` (:177–:191), `gfx_is_zero_ram_mode`/`gfx_set_zero_ram_mode` (:193/:197), `GfxBackendFastClear` (:205), `GpuConfigPrintDolDoc` (:225), `GpuConfigMain` (:241), `GfxBackendSelfTest` (:256) | `Shell.HC:650,653,656` (`gfx_backend_set_mode`), `Compositor.HC:491,493,497` (`gfx_backend_present`), `WM.HC:966` (`GpuConfigPrintDolDoc`), `HolyGL.HC:285` (`GpuGetShading`) |
| `apps/VirtioGpu.HC` (532 L) | `g_vgpu` (`CVirtioGpuDev`, :147) | `VirtioGpuSendCmd` (:157), `VirtioGpuInit` (:206), `VirtioGpuFlushRect` (:393), `VirtioGpuFlushFull` (:440), `VirtioGpuIsAvailable` (:444), `virtio_gpu_*` aliases (:448–:462), `VirtioGpuSelfTest` (:464) | `GfxBackend.HC:163,165,167` only |

**Key findings**

* `g_gfx_cfg` is **defined in `Render.HC:43`** but mutated by `GfxBackend.HC:58,64,153,194` and read
  by `Render.HC:81,85,91,666,667`. A graphics-backend global living in the renderer is exactly the
  kind of cross-module alias to eliminate.
* `GfxBackendInit` (`GfxBackend.HC:44`) calls `RenderSetZeroRamMode(0)` (`:59`);
  `GpuSetBuffering` (`:85`) calls `RenderSetZeroRamMode` (`:87`); `GfxBackendPresent` (`:152`) calls
  `RenderDirtyReset` (`:160`). So the backend already depends on Render — the merged device must keep
  that dependency one-directional (Device → Canvas), not introduce a cycle.
* **VirtioGpu truncates two commands** (matches `SKILL.md` §1):
  * `RESOURCE_CREATE_2D`: `CVirtioGpuResourceCreate2D` is 40 bytes (24-byte `CVirtioGpuCtrlHdr` +
    4×U32), but `VirtioGpu.HC:345` sends `VirtioGpuSendCmd(c2d, 32, …)` → `width`/`height` are cut off.
  * `TRANSFER_TO_HOST_2D`: `CVirtioGpuTransferToHost2D` is 56 bytes (24 + 16-byte rect + U64 offset +
    2×U32), but `VirtioGpu.HC:417` sends `VirtioGpuSendCmd(t2d, 48, …)` → 8 bytes cut.
  * Fix these to `sizeof`-equivalent (`40`, `56`) as part of the merge; `SET_SCANOUT` (:384, 48),
    `RESOURCE_FLUSH` (:434, 48) and `ATTACH_BACKING` (:365, 48) are already correct.
* `VirtioGpuInit` is called at module load (`VirtioGpu.HC:528`) **and** the flush path is only reached
  through `GfxBackendPresent` (`:162-169`), i.e. the two files are already one logical device.

### 2.2 Migration steps

1. Create `apps/GfxDevice.HC`. Fold `CGfxBackendState` (`GfxBackend.HC:26-40`) and `CVirtioGpuDev`
   (`VirtioGpu.HC:131-145`) into one `CGfxDevice g_gfxdev` with a `backend` enum
   (`CPU_SW`/`GPU_HW`/`SMP_TILED`) and the virtio fields as a sub-struct.
2. Move **all** of `VirtioGpu.HC`'s command builders verbatim (`SendCmd`/`Init`/`FlushRect`/
   `FlushFull`/`IsAvailable`), fixing the two lengths above. Keep `virtio_gpu_*` aliases (some may be
   late-bound by name).
3. Move `GfxBackend.HC`'s mode/config API and `GfxBackendPresent`. Rename the public surface to
   `GfxDeviceInit/SetMode/Present/…` but keep the legacy `gfx_backend_*` and `gpu_config_open`
   spellings as thin shims for one release (they are referenced by name from `Shell.HC` and `WM.HC`).
4. **Move `g_gfx_cfg` out of `Render.HC`** into `GfxDevice.HC` (or, better, delete it and keep the
   single `zero_ram_mode` flag already on `g_canv`, `Render.HC:36`). Update `Render.HC:81,85,91,666,667`
   accordingly.
5. Update `apps/KernelInit.HC:70-71`: two loads → one `KInitLoad("GfxDevice.HC");`.
6. Delete `apps/GfxBackend.HC`, `apps/VirtioGpu.HC`.

### 2.3 Globals to dedupe
* `g_gfx` (GfxBackend) + `g_vgpu` (VirtioGpu) → `g_gfxdev`.
* `g_gfx_cfg` — **owned by Render but used by GfxBackend**; remove from Render, keep one
  `zero_ram_mode` on `g_canv`.
* `g_hal_virtio_base`, `g_hal_virtio_slots`, `g_hal_virtio_stride` (read at `VirtioGpu.HC:224-229`) —
  owned by `HalPlatform`; leave single-owned, do not redeclare.

### 2.4 Files to delete
`apps/GfxBackend.HC`, `apps/VirtioGpu.HC`.

### 2.5 Verify
`golden-boot.sh` PASS; `render gpu` / `render smp` / `render cpu` shell commands still switch
(`Shell.HC:650-656`); `VirtioGpuSelfTest` equivalent passes with corrected lengths; a full-screen
`gfx_backend_present` blits correctly (screenshot diff).

---

## 3. Render + RasterTile + HolyGL → one tiled NEON rasterizer

### 3.1 What actually exists

| File | Role | Notes |
|---|---|---|
| `apps/Render.HC` (840 L) | Canvas, clip, dirty rects, alpha primitives, `gfx_*` API | Owns `g_canv` (`:44`), `g_gfx_cfg` (`:43`). `gfx_draw_triangle_fill` (`:529`) is a flat scanline filler (no Z). |
| `apps/RasterTile.HC` (319 L) | **Real** 64×64 Pineda rasterizer + 16-bit Z-buffer | Owns `g_tile_cbuf[4096]` (`:12`), `g_tile_zbuf[4096]` (`:13`), `g_tri_z0/1/2` (`:15-17`). `RasterTriangleZ` (`:58`), `TileRasterTri` (`:149`), `TileResolve` (`:219`). **Not on the live path** — the live 3D path is HolyGL. |
| `apps/HolyGL.HC` (644 L) | OpenGL-style state machine + matrix stack + Z test | Owns `g_hgl` (`:67`), `g_hgl_zbuf` (`:68`). `HolyGLDrawTriangleZ` (`:284`) does per-pixel Z against its own `g_hgl_zbuf`, but takes a **flat `z_avg`** (`:284`, `:402-403`). |

**Key findings**

* **Two independent Z-buffers exist**: `RasterTile.g_tile_zbuf` (16 KB, 64×64) and
  `HolyGL.g_hgl_zbuf` (full-screen, `kmalloc`, `HolyGL.HC:85`). Neither is shared. The merge must keep
  exactly one.
* **Two triangle rasterizers exist**: `Render.gfx_draw_triangle_fill` (`Render.HC:529`, flat, no Z)
  and `HolyGLDrawTriangleZ` (`HolyGL.HC:284`, flat-z) and `RasterTile.RasterTriangleZ`
  (`RasterTile.HC:58`, interpolated Z). `HolyGL.HC:293` falls back to
  `gfx_draw_triangle_fill` when depth is off.
* **UVs are stored, never sampled**: `GLVertex.u/v` (`HolyGL.HC:28-29`) and
  `HolyGLTexCoord2f` (`:267`) exist, but `HolyGLSubmitTriangle` (`:370`) never reads `u`/`v`. Textures
  are cosmetic.
* **"NEON" is a label only.** `GfxBackend` exposes `RASTER_ENGINE_TILED_L1`/`GpuSetShading`
  (`GfxBackend.HC:15-20,126`) but no code emits SIMD. There is no shader VM; `$SHADER$` in DolDoc
  (`DolDocRenderShaderNode`, `DolDoc.HC:1168`) is a procedural per-pixel loop, not a VM.

### 3.2 Target: one `Raster.HC` (or `HolyGL.HC` kept as the name)

1. **Canvas moves under the rasterizer.** Keep `Render.HC`'s canvas/clip/dirty/`gfx_*` API as the
   *front end* but make the rasterizer the only thing that writes color+depth.
2. **One Z-buffer.** Delete `RasterTile.g_tile_zbuf` and `HolyGL.g_hgl_zbuf`; add a single
   `g_canv.zbuf` sized `pitch*height*2` allocated in `RenderInit` (`Render.HC:46`).
3. **Promote `RasterTriangleZ` (`RasterTile.HC:58`) to the only triangle path.** It already
   interpolates Z (`:124`) and tests `pz < g_tile_zbuf[idx]` (`:128`). Rewrite it to write into the
   canvas Z-buffer at `pitch` stride instead of the 64-wide `g_tile_zbuf`, and to accept
   per-vertex color + UV.
4. **Delete the flat fillers**: `Render.gfx_draw_triangle_fill` (`Render.HC:529`) and
   `HolyGLDrawTriangleZ` (`HolyGL.HC:284`). Redirect `HolyGL.HC:293`'s fallback to the new path.
5. **Real per-vertex Z in HolyGL.** `HolyGLSubmitTriangle` (`HolyGL.HC:370`) currently computes
   `avg_ndc_z` (`:402`) → `z16` (`:403`). Instead pass the three per-vertex `z16` values (already
   computed as `ndc_z0/1/2`, `:380,383,386`) into the promoted rasterizer.
6. **Texture sampling.** Add UV interpolation in the rasterizer and sample the bound texture; wire
   `HolyGLTexCoord2f` (`:267`) → `GLVertex.u/v` (`:28-29`) → `HolyGLSubmitTriangle`.
7. **SDF + shader VM.** Fold `Math3D.HC`'s `SdfSphere`/`SdfBox2D`/`FastSinRad` (already used by
   `DolDocRenderShaderNode`) into a tiny fragment-stage switch. `$SHADER$` (`DolDoc.HC:1168`) becomes
   the first shader program instead of a hardcoded loop.
8. **`RasterTileMain` (`:235`) is a demo** (action buttons at `:310`); keep only the library
   functions, drop the demo, delete the file after folding.
9. Update `apps/KernelInit.HC:76` (remove `RasterTile.HC`); keep `Render.HC` and `HolyGL.HC` (or
   merge HolyGL into the rasterizer and delete it too, per the master plan "MERGE→HolyGL").

### 3.3 Globals to dedupe
* `g_tile_cbuf`, `g_tile_zbuf`, `g_tri_z0/1/2`, `g_tri_use_vertex_z` (RasterTile) and
  `g_hgl_zbuf`, `g_hgl_zbuf_w`, `g_hgl_zbuf_h` (HolyGL) → one `g_canv.zbuf` + one `g_raster` state.
* `g_canv` (Render) stays single-owned.
* `TILE_W/H/PIXELS/COLOR_BYTES/DEPTH_BYTES` (`RasterTile.HC:5-9`) — constants, safe to fold.

### 3.4 Files to delete
`apps/RasterTile.HC` (definitely). `apps/HolyGL.HC` only if its API is fully re-homed (consumers:
`Physics3D.HC` 54 call sites, `Gears3D.HC` 22, `HolyBenchmark.HC` 5, `DolDoc.HC` 5 via
`symbols_lookup("HolyGLRenderCube")`/`"HolyGLViewport"` at `DolDoc.HC:1385-1386`).

### 3.5 Verify
Golden boot PASS; `gears`, `physics`, `holygl`, `bench` viewports still render (screenshot diff);
Z-occlusion test from `RasterTileMain` (`:270-281`) re-run against the unified buffer; a textured
quad shows non-flat sampling (new case in `tests/jit_golden/cases.json`).

---

## 4. Profiler + PerfOverlay; Benchmark trio

### 4.1 Profiler + PerfOverlay → one telemetry engine

| | `apps/Profiler.HC` (450 L) | `apps/PerfOverlay.HC` (367 L) |
|---|---|---|
| Global | `g_prof` (`CProfiler`, :88) | `g_perf` (`CPerfOverlay`, :68) |
| sqrt | `ProfSqrt` (:90) | `PerfSqrt` (:70) |
| ingest | `ProfilerRecordFrame` (:242) | `PerfOverlayRecordFrame` (:137) |
| metrics | `ProfilerComputeMetrics` (:168), hist[256] (:68) | rolling scan in `PerfOverlayRecordFrame` (:184-216) |
| spikes | ring 128, `spikes_33/50/100ms` (:80-85) | ring 64, `spike_records[64]` (:58) |
| draw | — | `PerfOverlayDraw` (:219) HUD sparkline |
| logs | `ProfilerWriteLogs` (:309) → `BENCH_PROFILER.LOG`, `BENCH_SPIKES.LOG` | — |

* **Consumers:** only `apps/HolyBenchmark.HC:82,83,84,100,101,111,112,121`. `Shell.HC:619` reads
  `g_comp.frame_time_us`/`g_comp.fps` (Compositor), **not** `g_prof`/`g_perf`.
* **Duplicate math:** `ProfSqrt` and `PerfSqrt` are byte-identical, and both duplicate
  `Math3D.MathSqrt` (`Math3D.HC:64`). Collapse to one `MathSqrt`.
* **Duplicate spike policy:** both classify `>33ms/>50ms/>100ms` and attribute a cause; Profiler has
  a 7-way `Bottleneck` enum (`Profiler.HC:8-14`, `ProfilerDiagnoseBottleneck` :148); PerfOverlay has
  a different 8-way `SPIKE_CAUSE_*` enum (`PerfOverlay.HC:8-15`). Keep **one** cause enum (the
  Profiler's is the richer and is the one written to disk).
* **Merge steps:** one `CTelemetry g_tele`; keep `ProfilerWriteLogs`'s on-disk format (BenchReport
  reads it, §4.3); keep `PerfOverlayDraw`'s HUD as the only renderer; delete `PerfSqrt`, the second
  ring, and the second cause enum. `PerfOverlayRecordFrame(dt,render,blit)` becomes
  `TelemetryRecordFrame(dt,logic,raster,smp,blit,dma,wm)` with the extra args defaulted.
* **Globals to dedupe:** `g_prof`, `g_perf` → `g_tele`. `warmup_frames`/`warmup_discard_count`,
  `spike_*`, `fps_*`, `frame_time_*` all collapse.
* **Files to delete:** `apps/PerfOverlay.HC` (fold into `Profiler.HC`, renamed `Telemetry.HC`).
* **Verify:** `perf` shell command (`Shell.HC:616-620`) unchanged; `bench` HUD renders;
  `BENCH_PROFILER.LOG`/`BENCH_SPIKES.LOG` byte-compatible enough for `BenchReport.HC` to read.

### 4.2 Benchmark trio → one suite

| File | Entry | Writes |
|---|---|---|
| `apps/BenchCpu.HC` (178 L) | `BenchCpuRunAll` (:126) → `BenchCpuSieve/MatrixMul/PointerChasing/MathNeon/MemBandwidth` (:4,32,68,94,105) | `BENCH_CPU.LOG` (:165) |
| `apps/BenchReport.HC` (58 L) | `BenchReportMain` (:4) reads `BENCH_COMPARISON.TXT`, `BENCH_CPU.LOG`, `BENCH_PROFILER.LOG`, `BENCH_SPIKES.LOG` (:16,26,34,42) | — |
| `apps/HolyBenchmark.HC` (167 L) | `HolyBenchmarkMain` (:142), `bench_unified_*` (:11-124) | `BENCH_COMPARISON.TXT` (:118), calls `ProfilerWriteLogs` (:121) |

* **Merge:** one `HolyBenchmark.HC` that (a) runs the CPU microbenches (move `BenchCpu*` in),
  (b) runs the 40-phase 3D suite (`bench_unified_*`), (c) emits all logs, and (d) has a `report`
  command that prints them (move `BenchReportMain` in). Delete `BenchCpu.HC`, `BenchReport.HC`.
* **Globals to dedupe:** `g_bench_active/mode/phase/frame/angle/last_us` (`HolyBenchmark.HC:4-9`)
  stay single-owned. `g_prof`/`g_perf` → `g_tele` (§4.1).
* **Note:** `Shell.HC:594` runs `HolyBenchmark.HC` for `bench`; `Shell.HC:600` etc. run
  `Gears3D/Physics3D/HolyGL` standalone. Keep those module names or update the shell strings.
* **Files to delete:** `apps/BenchCpu.HC`, `apps/BenchReport.HC`.
* **Verify:** `bench` prints a scorecard and writes the four log files; `run BenchReport.HC` still
  works if the user invokes it (or update the shell to `bench report`).

---

## 5. `WM.HC` → DolDoc `$WIN$`/`$SPLIT$`; dissolve `Compositor.HC`

### 5.1 WM as-is

* Data: `CWindow` (`WM.HC:9-27`), `CWindowManager` (`:29-50`), `g_wm` (`:52`), `g_wm_wins[8]`
  (`:53`), `g_main_win`/`g_tool_win` (`:54-55`), `g_wm_running` (`:56`), `g_wm_initialized` (`:57`).
* **Exactly three windows are hardcoded** in `WMInit` (`:345,348,351`) — Console, Telemetry, Gears.
  `WM_MAX_WINDOWS` is 8 (`:7`) but only 3 are ever created at boot.
* Entry points: `WMInit` (:318), `WMCreateWindow` (:242), `WMFocusWindow` (:219),
  `WMCloseWindow` (:271), `WMDrawWindow` (:365), `WMDrawWindows` (:455), `WMDrawDesktop` (:462),
  `WMDrawTaskbar` (:600), `WMDrawMenuDrawer` (:509), `WMHandleMouse` (:664), `WMMain` (:983),
  `WMEventLoop` (:993), `WMExit` (:979), `wm_set_dirty` (:59), `menu` (:955),
  `gpu_config_open` (:965), `wm_draw_animating_windows` (:970).
* **DolDoc has no window concept.** `$WIN$`/`$SPLIT$` do **not** exist anywhere in `DolDoc.HC`
  (only a color alias `"WINDOW"` at `DolDoc.HC:701`). DolDoc is a single fixed viewport
  (`g_doc_x/y/w/h`, `DolDoc.HC:180-183`) over a char grid (`g_doc_chars[16384]`, `:224`).

### 5.2 Target: windows are DolDoc views

1. Add two DolDoc tags in `DolDocPrint`'s tag dispatch (`DolDoc.HC:1555-1867`):
   * `$WIN,id=…,x=…,y=…,w=…,h=…,title="…"$` — starts a nested view region; everything until the
     matching `$ENDWIN$` is laid out relative to the window client rect.
   * `$SPLIT,dir=h|v,frac=…$` — splits the current region for tiling (KolibriOS tile map already
     exists in Compositor, `g_comp.win_tile_map`, `Compositor.HC:90`).
2. Represent a window as a widget (`WIDGET_*`, `DolDoc.HC:16-33`) with a child viewport; reuse the
   existing `g_widget_*` tables (`:234-251`) and `MortonSpatialInsertWidget` (`:320`) rather than a
   parallel `CWindow` table.
3. Move window chrome drawing (`WMDrawWindow` :365) into a DolDoc draw pass; z-order becomes widget
   z (currently `g_wm.zorder[8]`, `:49`); hit-testing (`WMHandleMouse` :664) becomes
   `DolDocHandleClick` (`DolDoc.HC:2365`) hit-testing windows first.
4. Re-home the three boot windows as `$WIN$` tags emitted by `ShellPrintBootBanner`
   (`Shell.HC:452`) / `DolDocInit` (`DolDoc.HC:2863`) instead of `WMCreateWindow` calls.
5. Keep a tiny `WM.HC`-named shim for the legacy entry points that `Shell.HC`/`HolyBenchmark.HC`
   call by name (`WMEventLoop`, `WMExit`, `WMCreateWindow`, `wm_set_dirty`, `bench_unified_*`
   coupling at `WM.HC:1053`), then delete the file once those are rewritten.

### 5.3 Dissolve Compositor into DolDoc/Render

* `CThemePalette g_theme` (`Compositor.HC:50`) is read **everywhere** (WM, DolDoc, Shell, GfxBackend
  action text). Keep it as the single theme global but move its **owner** to DolDoc (or a small
  `Theme.HC`); `ThemeApply` (:99) and `ThemeSetByName` (:256) move with it.
* `CCompositorState g_comp` (`:94`) mixes: screen geometry (`screen_w/h/pitch`), tile maps
  (`win_tile_map[640]`, `tile_dirty_map[640]`, :90-91), damage rect (`dmg_*`, :80-84), and frame
  pacing (`fps`, `frame_time_us`, :86-88).
  * Geometry + damage + present (`CompositorPresent` :476, `CompositorDrawShadow` :414,
    `CompositorDrawGlass` :423) → **Render/DolDoc** (one dirty system; Render already has
    `g_canv.dirty`, `Render.HC:35`).
  * Tile ownership map → the DolDoc `$WIN$`/`$SPLIT$` tile model (it is the same 64×64 partition).
  * Theme palette → `g_theme` (above).
* `CompositorCmd` (`:536`) is a shell dispatcher → fold into the Shell action executor (§6).
* `Compositor.HC:598` runs `CompositorInit()` at top level **unconditionally** (not gated on
  `g_kernel_booting`), unlike every other module — a merge must preserve this init ordering or gate it.

### 5.4 Globals to dedupe
* `g_wm`, `g_wm_wins`, `g_main_win`, `g_tool_win`, `g_wm_running`, `g_wm_initialized` (WM) → DolDoc
  window/view state.
* `g_theme`, `g_comp` (Compositor) → split into `g_theme` (DolDoc-owned) and `g_canv` fields.
* `g_doc_anim_tick` (`DolDoc.HC:78`) is read by WM (`:87,505,1034`) — keep single-owned in DolDoc.

### 5.5 Files to delete
`apps/WM.HC`, `apps/Compositor.HC` (after re-homing). Remove their `KInitLoad` lines
(`KernelInit.HC:87-91`).

### 5.6 Verify
Golden boot PASS; `wm`/`desktop` shell commands open the desktop (`Shell.HC:487-499`); window
drag/resize/close via mouse still works (QEMU `sendkey`/VNC); theme switch (`theme tokyo`) repaints;
**cycle check:** `rg "shell_run_command|WMEventLoop" apps/DolDoc.HC` must be empty, and
`rg "wm_set_dirty" apps/Compositor.HC` must be empty.

---

## 6. `Shell.HC` → action executor over a CDoc (break cycles)

### 6.1 As-is

* Registry: `CShellCmdEntry` (`Shell.HC:23`), `g_shell_cmds[32]` (`:29`), `shell_register_cmd`
  (`:42`) — **`shell_register_cmd` has zero callers** (`rg` across the repo finds only its
  definition). The "command registry" is dead; dispatch is one giant `if/else if` chain in
  `ShellRunCommand` (`:467-751`).
* Line editor: `ShellPoll` (`:757`) + `g_shell_cmd` (`:32`); history `g_history` (`:34`);
  `DolDocShellEventLoop` (`:840`).
* Cycles out of Shell: `WMEventLoop()` (`:489`), `WMExit()` (`:502`), `g_wm`/`WMCreateWindow`
  (`:505-507`), `ThemeSetByName`/`CompositorDamageAll` (`:550-551`), `CompositorCmd` (`:615`),
  `g_comp.frame_time_us`/`g_comp.fps` (`:619`), `g_theme.name` (`:460`).
* Cycles into Shell: `DolDoc.HC:2480,2490,2552` call `shell_run_command(g_click_cmd_buf)` from the
  link/button click path; `WM.HC` calls `shell_run_command` ~20× (e.g. `:681-711,739-760`).

### 6.2 Target

1. **Command table replaces the if/else.** Fill `g_shell_cmds` via `shell_register_cmd` (`:42`) at
   `ShellInit` (`:827`) — one entry per current branch — and dispatch by lookup. This makes the
   registry real and lets DolDoc/WM contribute commands.
2. **Action protocol instead of direct calls.** `$BT,LM="…"$`/`$LK,A="…"$` widgets already store the
   command string (`DolDoc.HC:1597,1617,1661`). Change `DolDocHandleClick` (`DolDoc.HC:2365`) to
   **enqueue** the action (`g_doc_actions[]`) and return; the Shell loop
   (`DolDocShellEventLoop`, `:840`) drains it. This removes `DolDoc → Shell`
   (`DolDoc.HC:2480,2490,2552`).
3. **WM emits events, not commands.** `WMHandleMouse` (`WM.HC:664`) currently calls
   `shell_run_command` directly; replace with `g_wm_events[]` drained by the same Shell loop. This
   removes `WM → Shell`. `Shell` then owns the only call to `WMEventLoop`/`WMExit`.
4. **Shell's buffer becomes a CDoc.** The line editor (`ShellPoll` :757) writes through `doldoc_*`
   today; formalize it as a CDoc/CTree node so input, history and output share the DolDoc model.
5. **Compositor commands** (`CompositorCmd`, `Compositor.HC:536`) become registered shell actions
   (`compositor shadow|glass|round|vsync …`), not a Shell→Compositor call.
6. `hcrun` (added at `Shell.HC:707-723`) already routes a file through `CompilerCompileAndRun` with
   `g_kernel_booting` forced to 1 — keep it; it is the per-file Compiler.HC path that
   `scripts/p1-parity.sh` can use once P1 lands.

### 6.3 Globals to dedupe
* `g_shell_cmds`, `g_shell_cmd_count` (Shell) — single-owned.
* `g_shell_dirty` (`Shell.HC:40`) is read by WM (`WM.HC:1014-1016`) — keep single-owned, have WM read
  it (or move to the event queue).
* `g_kernel_booting` — see §7.

### 6.4 Files to delete
None (Shell is kept); but its dispatch body shrinks to a table.

### 6.5 Verify
Golden boot PASS; every existing shell command (`help`, `ls`, `mem`, `run`, `hcrun`, `theme`,
`compositor`, `wm`, `shader`, `uf`, `src`, `bench`, `gears`, `physics`, `holygl`, `perf`, `vsync`,
`zeroram`, `render`, `cd/mkdir/rm/save/cat`) still works via `scripts/uart-repl.py`;
**cycle check:** `rg "shell_run_command" apps/DolDoc.HC apps/WM.HC` must be empty.

---

## 7. Cross-cutting: globals to dedupe, cycle map, deletion list

### 7.1 `g_kernel_booting` is redeclared in 14 files

`apps/KernelInit.HC:8` defines it. It is **re-declared** (not just read) in:
`HalPlatform.HC:369`, `Gic.HC:288`, `Exceptions.HC:304`, `KHeap.HC:465`, `Symbols.HC:334`,
`Timer.HC:160`, `Sched.HC:366`, `Smp.HC:406`, `VirtioBlk.HC:465`, `RedSea.HC:756`,
`Keyboard.HC:301`, `Mouse.HC:342`, `VirtioInput.HC:549`, `WM.HC:1072`.

Each redeclaration allocates a fresh heap cell and re-registers the name in place
(`kernel/symbols/symbols.c:63-70`), so the last writer wins for *all* readers. This is a latent
global-alias bug and **must** be fixed (declare once in `KernelInit.HC`, read elsewhere) as part of
P3, before the merges above renumber anything. `Shell.HC:714-718` already works around it by
save/restore around `hcrun`.

### 7.2 Other cross-module globals to dedupe
* `g_gfx_cfg`: defined `Render.HC:43`, used `GfxBackend.HC` — see §2.
* `g_theme`: owned `Compositor.HC:50`, read by WM/DolDoc/Shell/GfxBackend — see §5.
* `g_prof`/`g_perf`: see §4.
* `g_canv`/`g_comp`: overlapping canvas geometry — see §3/§5.
* `g_hgl_zbuf` / `g_tile_zbuf`: two Z-buffers — see §3.

### 7.3 UI cycle edges (must stay broken; source cites)
* `DolDoc → Shell`: `DolDoc.HC:2480,2490,2552` (`shell_run_command`).
* `Shell → DolDoc`: pervasive (`doldoc_*`, e.g. `Shell.HC:486,497-498,528-530,562-563`).
* `Shell → WM`: `Shell.HC:489,502,505-507`.
* `WM → Shell`: `WM.HC:1013` (`shell_poll`), plus `shell_run_command` at `:681-711,739-760`.
* `WM → Compositor`: `WM.HC:110,282,373,384,434,464,517,519,689,693,898,901,923,926,957,975,1003,1062`.
* `Compositor → WM`: `Compositor.HC:301,341` (`wm_set_dirty`).
* `DolDoc → Compositor`: `DolDoc.HC:727` (`CompositorDrawShadow`), `:731`
  (`CompositorDrawGlass`), `:1489` (`g_comp.fps`).
* `Compositor → DolDoc`: `Compositor.HC:512-530` (`doldoc_print/printf`), `:551` (`doldoc_set_bg`).

### 7.4 Files to delete (cumulative)
`FontMono.HC`, `FontVector.HC`, `GfxBackend.HC`, `VirtioGpu.HC`, `RasterTile.HC`,
`PerfOverlay.HC`, `BenchCpu.HC`, `BenchReport.HC`, `WM.HC`, `Compositor.HC` (10 files, replaced by
`Fonts.HC`, `GfxDevice.HC`, one `Raster`/`HolyGL`, `Telemetry.HC`, one `HolyBenchmark.HC`, DolDoc
`$WIN$` views). The persisted `NEO_OS_MASTER_PLAN.md` also lists `HolyBenchmark3D.HC` as DEAD — it is
**not present** in `apps/` at this revision.

### 7.5 Verification matrix (run after each merge)

| Check | Command | Expected |
|---|---|---|
| Golden gate | `scripts/golden-boot.sh` | `GOLDEN BOOT: PASS` |
| Self-test | UART `run Compiler.HC` | `All 7 / 7 tests passed` |
| Engine parity | `scripts/p1-parity.sh` | `PASS — engines agree` |
| Module set | `scripts/p1-parity.sh` table | one row per `KInitLoad` in `KernelInit.HC` |
| Undefined syms | `scripts/audit-symbols.sh` | 0 undefined, 0 unresolved |
| JIT battery | `scripts/run-jit-golden.py` | all non-known cases pass |
| Visual | `scripts/screenshot-diff.py` | no unexpected diff |
| Cycles | `rg "shell_run_command" apps/DolDoc.HC apps/WM.HC` | empty |

---

## 8. Discrepancies between the specs and the actual code

1. **`scripts/compile-parity.sh` does not exist.** `P1-DELEGATION.md` §0 item #5 and §1 name it, but
   `scripts/` has no such file. Agent B's B2 delivers `scripts/p1-parity.sh` instead. Update §0/§1 to
   point at `scripts/p1-parity.sh`.
2. **`P1-DELEGATION.md` §1 says the JIT battery is "52 cases";** `tests/jit_golden/cases.json` had
   52 before B3 and now has **67** (B3 added 15 edge cases).
3. **`P1-DELEGATION.md` §8 calls `Math3D.HC` "495 lines";** it is **496** lines
   (`wc -l apps/Math3D.HC`).
4. **`NEO_OS_MASTER_PLAN.md` line 120 says `DolDoc.HC` is 2905 lines;** it is **2913**.
5. **`NEO_OS_MASTER_PLAN.md` lists `HolyBenchmark3D.HC` as DEAD;** no such file exists in `apps/`.
6. **`SKILL.md` §1 claims `VirtioGpu` sends truncated `RESOURCE_CREATE_2D` 40→32 and
   `TRANSFER_TO_HOST_2D` 56→48** — confirmed at `VirtioGpu.HC:345` and `:417`. This is a real bug,
   not just a doc note (§2.1).
7. **`Shell.HC` gained an `hcrun` command** (`Shell.HC:707-723`, uncommitted at spec time) that
   already routes a single file through `CompilerCompileAndRun` with `g_kernel_booting` forced to 1.
   The delegation §9 describes module-by-module flipping by editing `KernelInit.HC`; `hcrun` is a
   faster, edit-free path for the parity harness once committed.
8. **`shell_register_cmd` (`Shell.HC:42`) is dead code** — the "Dynamic Command Registry" advertised
   in the file header (`Shell.HC:4`) is never populated; dispatch is an `if/else` chain. The §6
   migration is therefore a rewrite of dispatch, not a refactor.
9. **`g_kernel_booting` is redeclared in 14 files** (see §7.1). `SKILL.md`/the delegation mention
   "dedupe globals" generically under P3 but do not call out this specific, high-risk alias.
