# NeoOS — P4.0 → P4.8 Forensic Audit (unified render pipeline, NEON, fonts, shaders, mesh)

Scope: `apps/GfxDevice.HC`, `apps/RasterTile.HC`, `scripts/raster_span.s`, `apps/HolyGL.HC`,
`apps/Render.HC`, `apps/Fonts.HC`, `apps/ShaderVM.HC`, `scripts/shader_quad.s`, `apps/Mesh.HC`,
`apps/Gears3D.HC`, `apps/Physics3D.HC`, `apps/Math3D.HC`, `apps/Theme.HC`, plus
`docs/02-TASKLIST.md` §P4 (P4.0 inventory) and `docs/04-CONTRADICTIONS-DECISIONS-OPEN-QUESTIONS.md` D6–D16.

Method: read every listed file line-by-line; verified claims with repository-wide `grep` for
cross-module globals, dead symbols, write-only state, and rasterizer entry points. Read-only audit;
no repo file was modified.

---

## 1. One pipeline / no scalar fallback

### 1.1 The single triangle entry point is real
- `apps/RasterTile.HC:711` — `RasterTriangleZ(x0,y0,x1,y1,x2,y2,color)` is the only triangle
  rasterizer in the tree. It sets up Pineda edges, top-left biases and the per-row loop, then calls
  `RasterRow` at `RasterTile.HC:762-764`.
- `apps/RasterTile.HC:670` — `RasterRow(yy)` is the ONE scanline routine; it always ends in the NEON
  body: `RasterTile.HC:680` (textured) or `RasterTile.HC:699` (solid/shaded) call `RasterSpanBlocks`,
  and `RasterTile.HC:600` returns `RasterSpanNEON(&g_rspan)` unconditionally.
- Every triangle producer funnels here: `apps/HolyGL.HC:369` (`HolyGLSubmitTriangle` →
  `RasterTriangleZ`); `apps/Mesh.HC:290-308` and `apps/Gears3D.HC:202-225` and
  `apps/Physics3D.HC:330-366` all go through `HolyGL*`; golden scene `apps/Render.HC:736`; benchmark
  `apps/Render.HC:763,766,799,805`; `apps/SelfTest.HC:542`. A repo-wide grep for
  `gfx_draw_triangle_fill`, `TileRasterTri`, `HolyGLDrawTriangleZ`, `z_avg`, `avg_ndc` returns
  **nothing** — the old parallel/second rasterizers and the averaged-Z path are gone.

### 1.2 Dispatch quote (RasterRow)
`apps/RasterTile.HC:670-708`:
```
I64 RasterRow(I64 yy) {
  if (g_raster_tex_active) {                       // textured
    ... while (xx&7) RasterPixelTextured(xx,yy);   // scalar head (<8 px)
    if (tb>0) RasterSpanBlocks(xx,yy,1);           // NEON body
    ... while (xx<max) RasterPixelTextured(...);   // scalar tail
  }
  I64 smode = g_rj_shade_mode;
  ... while (xx&7) { smode?RasterPixelShaded:RasterPixelScalar }  // scalar head
  if (blocks>0) RasterSpanBlocks(xx,yy,0);         // NEON body (flat/Gouraud/Phong)
  ... while (xx<max) { smode?RasterPixelShaded:RasterPixelScalar } // scalar tail
}
```
`apps/RasterTile.HC:566-567` selects the colour stage and `:600` dispatches:
```
I64 mode = (tex != 0) ? 0 : g_rj_shade_mode;
g_rspan.gmode = mode;
...
return RasterSpanNEON(&g_rspan);
```
So flat, textured, Gouraud and Blinn-Phong **bodies** all run the one hand-assembled NEON kernel
(`apps/RasterTile.HC:374-503`, source of record `scripts/raster_span.s`).

### 1.3 Scalar sub-paths that DO exist (bounded, documented)
- `apps/RasterTile.HC:506` `RasterPixelScalar` — solid head/tail (<8 aligned px per row).
- `apps/RasterTile.HC:257` `RasterPixelTextured` — textured head/tail.
- `apps/RasterTile.HC:648` `RasterPixelShaded` + `:606` `RasterShadeColorAt` — Gouraud/Phong head/tail.
These are the p4.2b/P4.5 "head | body | tail" split documented in the file header
(`RasterTile.HC:11-15`) and D8/D12. They are **not** a fallback selected by a capability/condition; they
cover only the `<8 px` unaligned ends of a row. **Severity: Low (informational).** Root-fix: none
required; if a future requirement is "0 scalar pixels", process the row from a shifted origin so the
whole span is 8-aligned (out of scope for P7.2).

### 1.4 FINDING — conditional non-rasterizer triangle path (wireframe)
`apps/HolyGL.HC:346-352`:
```
if (g_hgl.wireframe || GfxDeviceGetShading() == RASTER_SHADE_WIREFRAME) {
    gfx_draw_line(sx0, sy0, sx1, sy1, col);
    gfx_draw_line(sx1, sy1, sx2, sy2, col);
    gfx_draw_line(sx2, sy2, sx0, sy0, col);
    g_hgl.tris_rendered = g_hgl.tris_rendered + 1;
    return;
}
```
Under wireframe a triangle is drawn as three `gfx_draw_line` calls and **never reaches**
`RasterTriangleZ`. Today every caller passes 0 (`Mesh.HC:314,360`; `SelfTest.HC:436,494,708`;
`Mesh.HC:361`/`SelfTest.HC:437,495,709` set shading 0), so the branch is latent — but it is reachable
via `HolyGLSetWireframe(1)` (`HolyGL.HC:180`) or `GfxDeviceSetShading(RASTER_SHADE_WIREFRAME)`
(`GfxDevice.HC:525`, constant at `GfxDevice.HC:22`). This contradicts a literal reading of "100% of
triangles flow through `RasterTriangleZ`".
**Severity: Medium (correctness of the claim, not of the image).** Root-fix: either delete the
wireframe branch and expose wireframe as a rasterizer shade mode, or explicitly document it as the one
non-rasterizer triangle path.

### 1.5 Does the 2D golden path force the NEON solid span? YES
`apps/Render.HC:719-722`:
```
// P4.3/P4.5: the 2D golden path is untextured and unshaded — force the unified
// span onto the NEON solid (flat) path so the golden hash 0xD28836F is bit-exact.
RasterDisableTexture();
RasterDisableGouraud();
```
`RasterDisableTexture` sets `g_raster_tex_active=0` (`RasterTile.HC:113`) and `RasterDisableGouraud`
sets `g_rj_shade_mode=0` (`RasterTile.HC:163`), so `RasterRow` takes the `else` branch with `smode==0`
→ `RasterPixelScalar` head/tail + `RasterSpanBlocks(...,0)` → `RasterSpanNEON` with `tex_ptr=0`,
`gmode=0` (the byte-identical solid path, `RasterTile.HC:566-567,600`). The golden triangle itself is
`apps/Render.HC:736`.
**Severity: Low (verified correct).**

### 1.6 Note — benchmark does not force the untextured state at entry
`apps/Render.HC:748` calls `RasterDisableGouraud()` but **not** `RasterDisableTexture()` before the
"Z-raster" loop (`Render.HC:753-768`). If a texture were left bound by a prior command, the
"Z-raster" benchmark line would silently run the textured span. `RenderGoldenScene` is safe (it does
disable). **Severity: Low.** Root-fix: add `RasterDisableTexture();` next to `Render.HC:748`.

**Section 1 verdict:** one triangle pipeline, NEON body for every colour stage, no parallel scalar
rasterizer; scalar work is limited to the documented `<8 px` head/tail, plus one latent wireframe
escape hatch.

---

## 2. Cross-module struct access

A systematic scan (`grep -rhoE '\bg_[a-zA-Z0-9_]+' apps/*.HC`, then "globals appearing in >1 file")
was run. Findings for the in-scope rendering modules:

| Global | Owner | Foreign reader/writer | Accessor exists? | Severity |
|---|---|---|---|---|
| `g_hgl.*` | `HolyGL.HC` | none — only `Compiler.HC:2212` (comment) | yes (`HolyGLGetTrisRendered` `HolyGL.HC:545`) | OK |
| `g_rtex.*` | `RasterTile.HC` | none (only `&g_rtex` at `RasterTile.HC:554`, same file) | n/a | OK |
| `g_canv.*` | `Render.HC` | `GfxDevice.HC:9` (comment only) | yes (`RenderDirtyActive/Bounds`) | OK |
| `g_gdev.*` | `GfxDevice.HC` | none | yes (`GfxDeviceGetMode/Name/Buffering/Shading`) | OK |
| `g_fv.*`, `g_font_metrics.*`, `g_font_atlas`, `g_fonts_*` | `Fonts.HC` | none | n/a | OK |
| `g_bench_tex` | `Render.HC` | none (`Render.HC:742,782,783` only) | n/a | OK |
| `g_mesh*`, `g_phys_*`, `g_red/green/blue_gear` | own modules | none | yes (`MeshGetVertexCount/TriCount` `Mesh.HC:267-268`) | OK |
| **`g_theme.*`** | `Theme.HC` | **`DolDoc.HC` (many), `Shell.HC`, `ShaderEditor.HC`** | **no** | **Medium** |
| **`g_gfx_cfg.*`** | `Render.HC` | **`GfxDevice.HC:493,499,519`** | **no** | **Low** |
| **`g_shader_speed/zoom/morph`** | `DolDoc.HC` | **`ShaderEditor.HC:36,41-43`** | registered via `symbols_register` (`DolDoc.HC:2679-2681`) | **Low** |

### 2.1 `g_hgl.v_curr.color` — CONFIRMED fixed, no others remain
The prior direct writes were replaced by `HolyGLColorPacked` (`HolyGL.HC:273`):
`apps/Gears3D.HC:217` (`HolyGLColorPacked(tri->color)`) and `apps/Physics3D.HC:338,389,412,421`.
No remaining `g_hgl.` access exists outside `HolyGL.HC` (only the `Compiler.HC:2212` comment).
**Verified clean.**

### 2.2 FINDING — `g_theme.*` read directly from three foreign modules, no accessors
`Theme.HC` owns `CThemePalette g_theme` (`Theme.HC:53`) but provides **no getters**. Direct reads:
- `apps/DolDoc.HC:152` (`g_theme.bg_base`), `:171-196` (18 semantic colour mappings),
  `:1655,1656,1678,1680` (radius/shadow), `:1996`, `:2010`, `:2018` (shadow/glass),
  `:2058,2077,2079`, `:2166-2315` (titlebar/window/menu/drawer palette, dozens), `:2369`, `:2394`.
- `apps/Shell.HC:489,613` (`g_theme.name`).
- `apps/ShaderEditor.HC:36` (`g_theme.name`).
D16 explicitly says "WM, DolDoc and Compositor all read the same global", so this is *intended by
design*, but it violates the sovereign accessor rule used everywhere else and there is no accessor.
**Severity: Medium.** Root-fix: add `ThemeGetColor(field_id)` / `ThemeGetName()` /
`ThemeGetMetric(id)` and route the reads through them (or accept D16 and document the exception
in-code).

### 2.3 FINDING — `g_gfx_cfg.*` written from `GfxDevice.HC` (owner is `Render.HC`)
`Render.HC:43` owns `CGfxConfig g_gfx_cfg`. `GfxDevice.HC` writes it at `:493` (`g_gfx_cfg.mode`),
`:499` (`g_gfx_cfg.mode`) and reads `:519` (`g_gfx_cfg.buffer_mode`) with no accessor.
**Severity: Low.** Root-fix: `RenderSetMode()` / `RenderGetBufferMode()` accessors.

### 2.4 FINDING — shader uniforms `g_shader_speed/zoom/morph` are DolDoc globals read by ShaderEditor
Owned by `DolDoc.HC:112-114`; read/used by `ShaderEditor.HC:36,41-43` with no accessor (they are
exported to `$SL$` only via `symbols_register`, `DolDoc.HC:2679-2681`).
**Severity: Low.** Root-fix: move the uniforms to a small `ShaderUniforms` owner (or `ShaderVM`) and
expose accessors.

---

## 3. P4.8 dead-code / write-only state

The P4.0 inventory (`docs/02-TASKLIST.md:610-613`) named `raster_engine, tile_size, zprecision,
smp_cores, culling, active_tab, feature_flags` (the old `CGfxBackendState`). That struct and all its
knobs are **gone** (`grep` for `GpuSetRasterEngine/GpuGetRasterEngine/GpuConfigMain/CGfxBackendState`
returns nothing). All P4.8-deleted symbols (`RenderIsZeroRamMode`, `gfx_mark_dirty`, `gfx_draw_circle`,
`RasterGetDepthTest`, `RasterShadeMode`, `RasterTextureActive`, `HolyGLApplyLighting`,
`HolyGLGetViewportW/H`, `HolyGLGetBound*`, `HolyGLTexOK`, `gfx_draw_triangle_fill`, `TileRasterTri`,
`TileClear`, `TileResolve`, `RasterSetVertexZ`, `g_hgl_zbuf`, `g_tile_zbuf`) are confirmed **absent**.

However, the P4.8 "purge" was **incomplete** in the broader write-only sense:

| Item | file:line | Status |
|---|---|---|
| `g_bench_mode` | `apps/HolyBenchmark.HC:5` decl, `:13` reset, `:93` set | **write-only (0 reads) — REMAINS** |
| `g_shadervm_demo_keep` | `apps/ShaderVM.HC:1220` decl, `:1223` `=1`, `:1246` `=0` | **write-only (0 reads) — REMAINS** |
| `g_hgl.verts_processed` | `apps/HolyGL.HC:64` field, `:147` reset, `:394` increment | **write-only (0 reads) — REMAINS** |
| `g_tex_blend_src` | `apps/HolyGL.HC:101` decl, `:152` reset, `:525` set by `glBlendFunc` | **write-only (0 reads) — REMAINS** |
| `g_tex_blend_dst` | `apps/HolyGL.HC:102` decl, `:153` reset, `:526` set by `glBlendFunc` | **write-only (0 reads) — REMAINS** |
| `g_gfx_cfg.mode` | `apps/GfxDevice.HC:493,499` set | **write-only (0 reads) — REMAINS** |
| `g_gfx_cfg.vsync_en` / `.vsync_hz` | `apps/Render.HC:625-626` set | **write-only (0 reads) — REMAINS** |
| `g_theme.btn_size` | `apps/Theme.HC:50` field, `:64` set | **write-only (0 reads) — REMAINS** |
| `g_theme.bg_surface2` | `apps/Theme.HC:29` field, `:73,97,121,145,169,195` set | **write-only (0 reads) — REMAINS** |
| `TILE_W` / `TILE_H` | `apps/RasterTile.HC:22-23` | **declared-but-unused — REMAINS (the P7.3 gap)** |

- `apps/HolyBenchmark.HC:5,13,93` — `g_bench_mode` is assigned but never read.
  **Severity: Low.** Root-fix: delete it, or wire it into the phase report.
- `apps/ShaderVM.HC:1220,1223,1246` — `g_shadervm_demo_keep` is a write-only "held visual" flag.
  **Severity: Low.** Root-fix: delete.
- `apps/HolyGL.HC:64,147,394` — `g_hgl.verts_processed` counts vertices but no reader exists
  (contrast `tris_rendered`, read at `HolyGL.HC:545`). **Severity: Low.** Root-fix: expose via an
  accessor or delete.
- `apps/HolyGL.HC:101-102,525-526` — `glBlendFunc` writes `g_tex_blend_src/dst` that nothing consumes
  (the rasterizer uses `g_tex_blend` via `RasterSetBlend`, `HolyGL.HC:536`). So `glBlendFunc` is a
  no-op knob. **Severity: Low.** Root-fix: either honour src/dst factors or delete the state.
- `apps/GfxDevice.HC:493,499`, `apps/Render.HC:625-626` — `g_gfx_cfg.mode/vsync_en/vsync_hz` are
  write-only duplicates of `g_gdev.mode` / `g_canv.vsync_*`. **Severity: Low.** Root-fix: delete the
  duplicate `CGfxConfig` fields (keep `buffer_mode`, the only field read at `Render.HC:86`).
- `apps/Theme.HC:50,64,29` — `g_theme.btn_size` and `bg_surface2` are set per theme and never read.
  **Severity: Low.** Root-fix: delete or consume.
- `apps/RasterTile.HC:22-23` — `I64 TILE_W = 64; I64 TILE_H = 64;` are declared but referenced
  nowhere else (repo-wide grep). Confirmed still unused = the **P7.3** tiling gap: the 64×64 tile
  model is declared but the rasterizer is a full-screen row-major scan. **Severity: Low now /
  blocker for P7.3.** Root-fix: implement P7.3 binning against these constants, or delete them until
  then.

No duplicate globals remain in the render set (`g_zbuf` only in `RasterTile.HC`; `g_comp` only in
`DolDoc.HC`; `g_theme` only in `Theme.HC`).

---

## 4. Fonts / ShaderVM debt

### 4.1 Fonts — the glyph composite IS scalar, and it is an *allowed font-subsystem exception*
- `apps/Fonts.HC:481-540` `FontsDrawGlyphSdf` is a per-pixel scalar loop: bilinear coverage read from
  `g_font_atlas` (`:516-522`), then an integer alpha composite straight into the framebuffer
  (`:525-532`). It does **not** call `RasterTriangleZ` and does not use the NEON span.
- The stroke fallback is also scalar: `FontsStrokeString` (`:543-559`) → `FontVectorDrawChar` (`:178`)
  → `VectorDrawLine` (`:109-112`) → `gfx_draw_line` (Render's scalar Bresenham) or the scalar
  supersample `FontsSsLine` (`:94-107`) during bake.
- The header comment `apps/Fonts.HC:471` ("SDF/AA text composited as **textured quads through the one
  rasterizer**") and the self-test comment `apps/Fonts.HC:650` ("draw a glyph big **through the one
  rasterizer**") are **stale/incorrect** — D9 (`docs/04:443-454`) records that the rasterizer-quad
  composite was **abandoned** because the atlas sub-texel UV is fragile at the NEON span's 16.16
  precision. The live code is a direct scalar blit.
- Verdict: this is a **font-subsystem exception, not a rasterizer violation** (text is not triangles;
  D9 explicitly allows it), **but the comments lie about it.**
  **Severity: Low (Medium for documentation accuracy).** Root-fix: correct the two comments; optionally
  add a font NEON blit later.

### 4.2 ShaderVM — scalar per-lane hot paths, an unwired assembler, no TODO markers
- `apps/ShaderVM.HC:83-96` `ShaderOp4` is the NEON 4-lane arithmetic core (source of record
  `scripts/shader_quad.s`), and only `add/sub/mul/div/min/max/sqrt/rsq/abs/neg/floor/fract` are
  covered (`ShaderVM.HC:351-355`). Everything else is a **scalar per-lane `while (l<4)` loop**:
  `SIN/COS` (`:363-372`), `LEN2/LEN3` (`:373-384`), `DOT2` (`:385-396`), `MIX` (`:397-407`),
  `CLAMP` (`:408-420`), `SMOOTH` (`:421-431`), `FRAGX/FRAGY/TIME` (`:432-440`), `DFDX/DFDY`
  (`:441-460`), `PERLIN/FBM/MANDEL/SDF*` (`:489-537`), `OUT` (`:538-552`). The native raymarcher
  `ShaderRaymarchQuad` (`:924-1040`) marches scalar per-lane; only its field `ShaderField4`
  (`:882-920`) is 4-lane NEON. The module header itself calls the interpreter "the per-lane masked
  blend" (`:9-10`) — so this is **documented**, not a hidden scalar fallback.
  **Severity: Low.** Root-fix: if VM throughput matters, add NEON intrinsics for sin/cos/len/dot/mix.
- `apps/ShaderVM.HC:649-743` `ShaderVMAssemble` (the text assembler) has **no caller outside
  `ShaderVM.HC`** — it is exercised only by `ShaderVMEvalR` (`:1123-1128`) inside `ShaderVMSelfTest`
  (`:1130`). It is not wired to any shell/DolDoc command. **Severity: Low (unwired library path).**
  Root-fix: expose a `shader asm <text>` shell command or mark it test-only.
- No `TODO/FIXME/XXX/DEFERRED` markers exist in `Fonts.HC` or `ShaderVM.HC` (grep clean). The only
  "workaround" string in the audited set is a historical comment at `RasterTile.HC:193`.

---

## 5. Golden-hash integrity

- `apps/SelfTest.HC:327` — `I64 g_render_golden = 0x0D28836F;` (the frozen baseline; docs write it as
  `0xD28836F`). `apps/SelfTest.HC:585-604` `SelfTestRender` masks IRQs (`:586-587`), calls
  `RenderGoldenScene()` (`:588`), hashes the target buffer with `RenderHashBuffer` (`:593`) and
  compares to `g_render_golden` (`:595`).
- `apps/Render.HC:689-711` `RenderHashBuffer` — 32-bit FNV-1a, row-by-row with explicit pitch,
  all arithmetic masked to 32 bits.
- `apps/Render.HC:718-738` `RenderGoldenScene` exercises **two different code paths**:
  1. the 2D canvas primitives — `gfx_clear` (`:724`), `gfx_draw_rect` (`:725,726`),
     `gfx_draw_line` (`:727`), `gfx_draw_circle_filled` (`:728`), `gfx_draw_rounded_rect` (`:729`),
     `gfx_draw_gradient_v` (`:730`), `gfx_draw_text` (`:737`) — all **scalar** in `Render.HC`
     (`RenderDrawRect:308`, `RenderDrawLine:205`, `RenderFillCircleAA:346`, `RenderRoundedRect:383`,
     `gfx_draw_char:536`);
  2. exactly one triangle through the unified rasterizer — `RasterClearZ`/`RasterSetZ`/
     `RasterTriangleZ(300,240,420,300,340,380,0xFFA6E3A1)` (`:733-736`), forced onto the **NEON solid
     span** by `RasterDisableTexture()`/`RasterDisableGouraud()` (`:721-722`).
- **Which rasterizer path the 2D golden triangle uses:** `RasterTriangleZ` → `RasterRow` (`smode==0`,
  `g_raster_tex_active==0`) → `RasterPixelScalar` for the `<8 px` head/tail + `RasterSpanBlocks(...,0)`
  → `RasterSpanNEON` with `tex_ptr=0`, `gmode=0` (byte-identical solid path,
  `RasterTile.HC:566-567,600`). Row-major scan order and exact 64-bit Z division
  (`scripts/raster_span.s:410-431`, `ZLANE`) are what make it deterministic.
- **Consequence for P7.3 (tiling/SMP):** the hash is preserved iff (a) the NEON solid path's
  arithmetic is untouched, (b) the scan order remains row-major/order-independent, and (c) the 2D
  scalar canvas primitives are untouched. P7.3 must add binning as an *outer* job model without
  reordering writes or changing the per-pixel Z. The plan's own "golden-hash protection protocol"
  (`docs/02-TASKLIST.md:1607-1618`) matches this: the P7.3 hoist (`RasterTriangleZ` →
  `RasterTriangleZCore`) only moves the setup.
  **Severity: Low (verified); a regression here is High-impact.**
- Note the golden scene's 2D primitives (`gfx_draw_rect` etc.) are **not** part of the "one
  rasterizer" — they are separate scalar 2D paths. Any P7.x refactor that routes 2D rects/AA circles
  through the tile rasterizer will change `0xD28836F` and must re-baseline the hash.

---

## 6. NEON kernel gaps (for P7.2)

Confirmed: the present/blit/blend/clear paths are `memcpy`/scalar — there is **no NEON blit, blend or
clear** anywhere (grep for `asm`/`NEON` in `Render.HC` finds only comments).

- `apps/Render.HC:587-595` `gfx_swap_buffers`:
```
U0 gfx_swap_buffers() {
  if (!g_canv.front_buffer) return;
  U32 *target = RenderGetTargetBuffer();
  if (target && target != g_canv.front_buffer) {
    I64 total_bytes = g_canv.pitch * g_canv.height * 4;
    memcpy(g_canv.front_buffer, target, total_bytes);
  }
  RenderDirtyReset();
}
```
- `apps/Render.HC:596-618` `gfx_swap_rect` — per-row `memcpy` (`:614`) in a scalar `while` loop
  (`:610-616`).
- `apps/Render.HC:484-530` `gfx_blend_rect` — scalar per-pixel alpha blend (`:520-527`).
- `apps/Render.HC:584-586` `gfx_clear` → `RenderDrawRect` (`:308-343`), a scalar nested
  `while` fill (`:334-342`).
- `apps/GfxDevice.HC:562-579` `GfxDeviceFastClear` — an 8-way **manually unrolled scalar** store loop
  (`:564-574`), not NEON. (Called only by `GfxDeviceSelfTest`, `GfxDevice.HC:629`.)
- `apps/Render.HC:649-658` `gfx_lerp_color` and `:664-673` `gfx_draw_gradient_v` — scalar.
**Severity: Medium (P7.2 targets).** Root-fix: add `scripts/*.s` NEON kernels for full-rect copy,
rect blend and clear (and a `stnp`-streaming resolve per P7.3), dispatched from these functions.

---

## 7. GfxDevice config-plane gap (for P7.4)

Confirmed `apps/GfxDevice.HC` has **no** `gpu_set/get_{zprecision,raster_engine,tile_size,smp_cores,
culling}` (grep for `gpu_set`/`gpu_get`/`GpuSet`/`GpuGet` returns only the `CVirtioGpuSetScanout`
struct). `CGfxDeviceState` (`GfxDevice.HC:24-31`) exposes only `mode, buffering, shading, name[64],
ops_counter, dma_bytes`. `GFX_MODE_SMP_TILED` is defined (`:15`) but `GfxDeviceSetMode` (`:497-507`)
only renames the device — there is no SMP tile dispatch. `RASTER_SHADE_WIREFRAME` (`:22`) exists but is
not a real engine selector.

No VirtIO batch2/batch3 and no page-flip exist: the transport is strictly **one command per call**.
`apps/GfxDevice.HC:191-238` `VirtioGpuSendCmd`:
```
I64 VirtioGpuSendCmd(U64 cmd, U32 cmd_size, U64 resp, U32 resp_size) {
  ...
  CVringDesc *d0 = &vq_desc[0];  d0->addr = cmd; ... d0->next = 1;   // one cmd desc
  CVringDesc *d1 = &vq_desc[1];  d1->addr = resp; ...               // one resp desc
  ...
  vavail->ring[a_idx % g_vgpu.queue_num] = 0;
  vavail->idx = a_idx + 1;
  ... VGpuMmioWrite32(b, VIRTIO_MMIO_QUEUE_NOTIFY, 0);               // one notify (:224)
  I64 vg_timeout = 5000000;
  while (vused->idx == last_used && vg_timeout > 0) { ... }          // busy-wait poll (:226-231)
  ...
}
```
`VirtioGpuFlushRect` (`:427-473`) issues **two sequential** single-command sends
(`TRANSFER_TO_HOST_2D` `:437-454`, then `RESOURCE_FLUSH` `:456-471`), each blocking on its own notify
+ poll. There is no descriptor batching (batch2/batch3), no fence pipelining, and no page-flip
ping-pong (double buffering is a CPU `memcpy` in `gfx_swap_*`, section 6).
**Severity: High for P7.4/P7.5.** Root-fix: add a `CGfxConfigPlane` with `gpu_set/get_*` accessors,
a `CVirtioBatch` descriptor for batch2/batch3 command submission (the 8-arg cap requires passing a
descriptor struct by pointer, per the risk register `docs/02-TASKLIST.md:1728`), and a page-flip
ping-pong scanout path.

---

## Prioritized root-fix list

1. **P7.5 (High):** Add the GPU config plane to `GfxDevice.HC` — `gpu_set/get_{zprecision,raster_engine,
   tile_size,smp_cores,culling}`, VirtIO batch2/batch3, and page-flip. Replace the single-command
   `VirtioGpuSendCmd` (`GfxDevice.HC:191`) with a batched submit path.
2. **P7.2 (Medium):** Add NEON blit/blend/clear kernels and dispatch them from `gfx_swap_buffers`
   (`Render.HC:587`), `gfx_swap_rect` (`:596`), `gfx_blend_rect` (`:484`), `gfx_clear` (`:584`),
   `GfxDeviceFastClear` (`GfxDevice.HC:562`).
3. **P7.3 (Medium):** Implement L1 tile binning using the declared `TILE_W/TILE_H`
   (`RasterTile.HC:22-23`) without touching the NEON solid path or scan order, so `0xD28836F` is
   preserved.
4. **Section 1.4 (Medium):** Resolve the wireframe escape (`HolyGL.HC:346-352`) — delete it or
   document it as the one non-rasterizer triangle path.
5. **Section 2.2 (Medium):** Add `Theme` accessors and route the `g_theme.*` reads in `DolDoc.HC`,
   `Shell.HC`, `ShaderEditor.HC` through them (or document the D16 exception in-code).
6. **Section 4.1 (Low/Medium):** Fix the stale "textured quads through the one rasterizer" comments
   in `Fonts.HC:471,650`; keep the direct scalar composite (allowed exception per D9).
7. **Section 3 (Low):** Delete/consume the write-only state: `g_bench_mode`
   (`HolyBenchmark.HC:5,13,93`), `g_shadervm_demo_keep` (`ShaderVM.HC:1220,1223,1246`),
   `g_hgl.verts_processed` (`HolyGL.HC:64,147,394`), `g_tex_blend_src/dst`
   (`HolyGL.HC:101-102,525-526`), `g_gfx_cfg.mode/vsync_en/vsync_hz`
   (`GfxDevice.HC:493,499`; `Render.HC:625-626`), `g_theme.btn_size/bg_surface2` (`Theme.HC:50,64,29`).
8. **Section 2.3/2.4 (Low):** Add `Render` accessors for `g_gfx_cfg`; give the shader uniforms a
   proper owner/accessors.
9. **Section 1.6 (Low):** Add `RasterDisableTexture();` at the start of `RenderBench`
   (`Render.HC:748`).
10. **Section 4.2 (Low):** Wire `ShaderVMAssemble` to a user-facing command or mark it test-only;
    consider NEON for the VM's scalar per-lane ops.

---

### Files audited (all read line-by-line)
`apps/GfxDevice.HC`, `apps/RasterTile.HC`, `scripts/raster_span.s`, `apps/HolyGL.HC`,
`apps/Render.HC`, `apps/Fonts.HC`, `apps/ShaderVM.HC`, `scripts/shader_quad.s`, `apps/Mesh.HC`,
`apps/Gears3D.HC`, `apps/Physics3D.HC`, `apps/Math3D.HC`, `apps/Theme.HC`,
`docs/02-TASKLIST.md` §P4, `docs/04-CONTRADICTIONS-DECISIONS-OPEN-QUESTIONS.md` D6–D16.
