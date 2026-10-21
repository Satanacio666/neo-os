# NEO-OS MASTER FUTURE IMPLEMENTATIONS & EXECUTION ROADMAP
**Document ID:** ROADMAP-2026-SOVEREIGN-MASTER  
**Target:** NeoOS ARMv8-A (AArch64) Ring 0 / EL1  
**Classification:** Strategic Architectural Roadmap & Step-by-Step Tasklist  
**Date:** 2026-10-18  

---

## 1. STRATEGIC MASTER PHASING

```
+======================================================================================================================+
|                                    MASTER FUTURE EXECUTION PHASING                                                   |
+======================================================================================================================+
| Phase | Title                                  | Subsystems Involved             | Core Deliverable                  |
+-------+----------------------------------------+---------------------------------+-----------------------------------+
| 1.0   | Dead Code Purge & Repository Hygiene   | Table, Lexer, UEFI stubs, C WM  | Clean 0-redundancy codebase       |
| 2.0   | Complete Window Dissolution into DolDoc| DolDoc.HC, WM.HC, Shell.HC      | Windows as native $WIN$ nodes     |
| 3.0   | Barycentric Perspective HolyGL 3D      | HolyGL.HC, RasterTile.HC        | Zero sorting bugs, textured meshes|
| 4.0   | Native 2x2 NEON Quad Shadertoy Engine  | DolDoc.HC, ShaderEditor.HC      | True raymarching & procedural SDFs|
| 5.0   | Stage-2 Compiler Self-Hosting Upgrade  | Compiler.HC, jit_arm64.c        | F64, inline asm, C retirement     |
| 6.0   | Hardware-Grounded PMU Telemetry        | Profiler.HC, PerfOverlay.HC     | Zero synthetic metrics, 1% lows   |
+======================================================================================================================+
```

---

## 2. DETAILED STEP-BY-STEP CHECKLIST

### Phase 1: Dead Code Purge & Repository Hygiene
- [ ] **Task 1.1: Purge Duplicate Containers**
  - Delete `apps/Table.HC` (100% duplicate clone of `apps/StdLib.HC`).
  - Update any residual references in `KernelInit.HC` and `Shell.HC`.
- [ ] **Task 1.2: Purge Orphaned Lexer**
  - Merge any unique token descriptors from `apps/Lexer.HC` into `apps/Compiler.HC`.
  - Delete `apps/Lexer.HC`.
- [ ] **Task 1.3: Purge Non-ARM UEFI Bootstrap Files**
  - Delete `boot/uefi/crt_riscv64.c` (270 LOC).
  - Delete `boot/uefi/crt_x86_64.c` (241 LOC).
  - Delete `boot/uefi/elf_riscv64_efi.lds` and `boot/uefi/elf_x86_64_efi.lds`.
- [ ] **Task 1.4: Purge Obsolete Legacy C GUI Stubs**
  - Delete `gui/shell.c` (superseded by `apps/Shell.HC`).
  - Delete `gui/wm.c` (superseded by `apps/WM.HC`).
- [ ] **Task 1.5: Consolidate Benchmark Wrappers**
  - Merge `apps/Bench.HC`, `apps/BenchReport.HC`, and `apps/HolyBenchmark3D.HC` directly into `apps/HolyBenchmark.HC`.
  - Delete the wrapper files.
- [ ] **Task 1.6: Verify Build Baseline**
  - Run `make -j4` and confirm 0 warnings, 0 errors, and clean packaging into `build/redsea.img`.

---

### Phase 2: Complete Window Dissolution into Sovereign DolDoc 3.0
- [ ] **Task 2.1: Eradicate the Rigid Character Cell Array**
  - Remove `g_doc_chars[16384]`, `g_doc_fg[16384]`, and `g_doc_bg[16384]` from `apps/DolDoc.HC`.
  - Re-target all text rendering to continuous subpixel vector runs (`FontVector.HC`) using subpixel coordinates ($26.6$ fixed-point).
- [ ] **Task 2.2: Implement Elastic Tabstops**
  - Add elastic tabstop column grouping in `DolDoc.HC` so code, structs, disassembly, and tables align to vertical pixel perfection without fixed-width monospace grid snapping.
- [ ] **Task 2.3: Implement Native Spatial Window Containers (`$WIN$`)**
  - Add `$WIN,title="...",x=...,y=...,w=...,h=...,flags=...$` parser and layout handler in `DolDoc.HC`.
  - Render window chrome (titlebars, minimize/maximize buttons, drop shadows) using native DolDoc vector drawing primitives and Catppuccin theme tokens.
- [ ] **Task 2.4: Dissolve `apps/WM.HC`**
  - Replace the static `CWindow g_wm_wins[8]` array with dynamic `$WIN$` nodes in the root DolDoc tree.
  - Eliminate hardcoded window ID logic (`if (w2) DolDocRenderShaderNode`).
  - Transition window dragging and resizing to universal Morphic halo interaction handles on `$WIN$` nodes.
- [ ] **Task 2.5: Inline the Shell REPL into DolDoc**
  - Represent the interactive shell as an active `$REPL$` node in the document stream.
  - Maintain arrow key history navigation, cursor movement, tab autocomplete, and immediate HolyC expression evaluation.
  - Enable running applications both inline within the scrollback (e.g. `gears`, `shader 4`) and elevated into floating windows (`--win`).

---

### Phase 3: Barycentric Perspective HolyGL 3D Pipeline Overhaul
- [ ] **Task 3.1: Eradicate the Flat `z_avg` Rasterizer Hack**
  - Remove lines 351–355 of `apps/HolyGL.HC`.
  - Re-implement the software triangle rasterizer in `apps/RasterTile.HC` using Juan Pineda's 28.4 subpixel fixed-point edge equations.
- [ ] **Task 3.2: Implement Perspective-Correct Barycentric Interpolation**
  - Interpolate $1/w$, depth $z/w$, and texture coordinates $u/w, v/w$ linearly in screen space.
  - Recover true texel coordinates via AArch64 NEON fast reciprocals (`vrecpeq_f32`, `vrecpsq_f32`).
- [ ] **Task 3.3: Bilinear Texture Sampling & Blinn-Phong Shading**
  - Implement `glTexImage2D`, `glBindTexture`, and bilinear texture filtering.
  - Implement dynamic directional lighting with Blinn-Phong specular highlights.
- [ ] **Task 3.4: Streaming Wavefront OBJ Mesh Ingestion**
  - Implement a streaming `.OBJ` polygonal mesh parser in HolyC to load external 3D models into HolyGL vertex buffers.
- [ ] **Task 3.5: Hook HolyGL as the Sovereign Compositor Backend**
  - Re-target DolDoc's 2D cards, acrylic glass panels, and drop shadows to output HolyGL textured quads (`glBegin(GL_QUADS)`), transforming the entire desktop into a hardware-accelerated 3D scene graph.

---

### Phase 4: Native 2x2 NEON Quad Shadertoy Fragment Engine
- [ ] **Task 4.1: Structure-of-Arrays (SoA) 2x2 Pixel Quad Model**
  - Redesign `DolDocRenderShaderNode` to evaluate 4 pixels in parallel per iteration using 128-bit AArch64 NEON registers (`float32x4_t`).
- [ ] **Task 4.2: Fast Transcendentals & Vector Derivatives**
  - Implement Newton-Raphson fast inverse square roots (`vrsqrteq_f32` / `vrsqrtsq_f32`).
  - Implement analytical screen-space vector derivatives (`dFdx`, `dFdy`) via NEON register lane permutations.
  - Implement SIMD execution masking (`vcgtq_f32`, `vbslq_f32`) for divergent raymarching loops.
- [ ] **Task 4.3: Authentic Procedural Shader Kernels**
  - Implement true raymarched SDF primitives (Sphere, Torus, Box) with numerical normal estimation and soft shadows.
  - Implement multi-octave Perlin/Simplex gradient noise for realistic terrain and volumetric clouds.
  - Implement 3D Mandelbulb fractal raymarching.
- [ ] **Task 4.4: Upgrade `ShaderEditor.HC` into an Authentic Live IDE**
  - Add live text editing allowing users to edit HolyC shader kernels on screen and recompile in real-time.
- [ ] **Task 4.5: Multi-Core Tile Parallelization**
  - Distribute 32×32 pixel tiles across all 4 SMP CPU cores via the `Smp.HC` lockless SPSC queue for 60 FPS performance.

---

### Phase 5: Stage-2 Compiler Self-Hosting Upgrade & Seed C Retirement
- [ ] **Task 5.1: 64-Bit Floating-Point Code Generation**
  - Add scalar AArch64 floating-point instructions to `apps/Compiler.HC`:
    * `FADD Dd, Dn, Dm` (`0x1E602800`), `FSUB`, `FMUL`, `FDIV`.
    * `LDR Dd, [Xn, #imm]`, `STR Dd, [Xn, #imm]`.
    * Floating-point comparison (`FCMP`) and type conversions (`FCVT`, `SCVTF`).
  - Verify compilation of `Math3D.HC`, `HolyGL.HC`, and `Physics3D.HC` by `Compiler.HC`.
- [ ] **Task 5.2: Inline Assembly Parser (`asm { ... }`)**
  - Implement an inline assembler parser in `Compiler.HC` supporting ARMv8 system instructions (`mrs`, `msr`, `isb`, `dmb`, `wfe`, `sev`, `dc civac`).
  - Verify compilation of `HalPlatform.HC`, `Gic.HC`, and `Timer.HC`.
- [ ] **Task 5.3: `#include` Preprocessor Support**
  - Implement file-inclusion parsing using RedSea VFS file reads to support multi-file compilation.
- [ ] **Task 5.4: Package Standalone Stage-2 Binary & Retire Seed C**
  - Pre-compile `Compiler.HC` into a Stage-2 executable binary blob loaded by UEFI.
  - Decommission and delete `compiler/jit_arm64.c` (3,739 LOC), `compiler/lexer.c` (534 LOC), and `compiler/table.c` (81 LOC).

---

### Phase 6: Hardware-Grounded PMU Telemetry & Undeniable Verification
- [ ] **Task 6.1: Direct Hardware Performance Monitor (PMU) Interfacing**
  - Enable EL0/EL1 PMU access via `PMCR_EL0`.
  - Read `PMCCNTR_EL0` (CPU cycles) and event counters:
    * `0x08`: `INST_RETIRED` (Instructions retired / IPC).
    * `0x03`: `L1D_CACHE_REFILL` (Data cache misses).
    * `0x10`: `BR_MIS_PRED` (Branch mispredictions).
- [ ] **Task 6.2: Purge Synthetic Constants from Profiler**
  - Remove all hardcoded dummy constants (`blit_us=1200`, `dma_us=400`) from `HolyBenchmark.HC` and `Profiler.HC`.
  - Remove static `"PERFECT (100%)"` marketing strings.
- [ ] **Task 6.3: Statistical Frame Pacing Metrics**
  - Replace average FPS with:
    * Median frametime ($p_{50}$).
    * 99th percentile ($p_{99}$ / 1% low).
    * 99.9th percentile ($p_{99.9}$ / 0.1% low hitch metric).
    * Frame pacing jitter variance ($\sigma_{\text{jitter}}$).
- [ ] **Task 6.4: Automated QMP Screendump Verification**
  - Maintain automated test scripts (`scripts/verify_shaders_and_3d.py`) capturing direct framebuffer dumps via QMP to ensure zero visual regressions.
