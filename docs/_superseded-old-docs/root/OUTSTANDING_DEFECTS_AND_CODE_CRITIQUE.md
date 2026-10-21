# NEO-OS MASTER CATALOG OF OUTSTANDING DEFECTS, SHORTCOMINGS & CODE CRITIQUE
**Document ID:** DEFECT-CATALOG-2026-FINAL  
**Target:** NeoOS ARMv8-A (AArch64) Ring 0 / EL1  
**Classification:** Uncompromising Forensic Defect & Critique Record  
**Date:** 2026-10-18  

---

## 1. EXECUTIVE SUMMARY: THE CODEBASE STATE OF REALITY

This document records the exact, unvarnished state of the NeoOS codebase as verified by line-by-line inspection and hardware-level execution under QEMU AArch64. While the operating system compiles cleanly (`make -j4`), boots from UEFI into a pure HolyC shell, and presents 3D graphics, procedural fragment shaders, and interactive widgets, **several critical architectural hypocrisies, stubs, and legacy compromises remain embedded in the source code**.

These defects are not mere "polishing issues"; they are fundamental violations of the sovereign post-DOM architecture that must be systematically dismantled and replaced.

---

## 2. CRITICAL DEFECTS BY SUBSYSTEM

### 2.1 Post-DOM & DolDoc Subsystem (`apps/DolDoc.HC`)

#### Defect DOC-01: The Rigid Character Grid Buffer (`g_doc_chars`)
* **File & Lines:** `apps/DolDoc.HC:224-227`
* **Vulnerability / Code:**
  ```c
  U8  g_doc_chars[DOLDOC_CELLS]; // 16,384 cells (126 cols x 41 rows)
  U32 g_doc_fg[DOLDOC_CELLS];
  U32 g_doc_bg[DOLDOC_CELLS];
  ```
* **Forensic Critique:** Despite claiming an "OmniTape display journal" that eliminates character grids, DolDoc still allocates a fixed $126 \times 41$ cell matrix. Text rendering in `DolDocRenderScreen` iterates row-by-row and column-by-column across this grid.
* **Impact:** True proportional typography ([apps/FontVector.HC](file:///home/carlos/.gemini/antigravity/scratch/neo-os/apps/FontVector.HC)) cannot flow naturally. Vector fonts scaled to arbitrary sizes are forced to snap their advance widths to integer cell multiples:
  ```c
  cell_cols = (w + 7) / 8; // Line 859
  ```
  This causes awkward gaps, clipped descenders, and prevents subpixel kerning.
* **Required Resolution:** Completely abolish `g_doc_chars`. Emit text as `OP_TEXT_RUN` nodes into the OmniTape display list with continuous subpixel coordinates and Elastic Tabstops.

---

### 2.2 Window Manager Subsystem (`apps/WM.HC`)

#### Defect WM-01: Monolithic Static Window Array & Hardcoded Window IDs
* **File & Lines:** `apps/WM.HC:53, 1035-1049`
* **Vulnerability / Code:**
  ```c
  #define WM_MAX_WINDOWS 8
  CWindow g_wm_wins[8];
  
  // Lines 1035-1049:
  CWindow *w2 = WMGetWindowById(2);
  if (w2 && w2->is_used) DolDocRenderShaderNode(w2->x + 16, w2->y + 106, ...);
  CWindow *w3 = WMGetWindowById(3);
  if (w3 && w3->is_used) DolDocRenderSprite3D(w3->x + 14, w3->y + 54, ...);
  ```
* **Forensic Critique:** `WM.HC` is segregated from DolDoc as an isolated monolithic procedural application. It hardcodes a static limit of 8 windows and directly binds window ID 2 to render a plasma shader and window ID 3 to render 3D gears.
* **Impact:** If an application or user opens another tool into window slot 2, a plasma shader is inexplicably drawn inside its client area. Window chrome (titlebars, borders, buttons) is rendered via imperative loops instead of native DolDoc vector markup.
* **Required Resolution:** Dissolve `WM.HC` entirely. Windows must become `$WIN,title="...",x=...,y=...,w=...,h=...$` container nodes within the root DolDoc document tree.

---

### 2.3 HolyGL & 3D Rasterization Subsystem (`apps/HolyGL.HC`, `apps/RasterTile.HC`)

#### Defect HGL-01: The `z_avg` Flat-Depth Triangle Rasterizer Hack
* **File & Lines:** `apps/HolyGL.HC:351-355`
* **Vulnerability / Code:**
  ```c
  if (w0 >= 0 && w1 >= 0 && w2 >= 0) {
      if (z_avg <= g_hgl_zbuf[zb_row + hgl_px]) {
          g_hgl_zbuf[zb_row + hgl_px] = z_avg;
          fb[fb_row + hgl_px] = col;
      }
  }
  ```
* **Forensic Critique:** The HolyGL software triangle rasterizer calculates a single average depth `z_avg` for the entire triangle and compares that against the 16-bit Z-buffer.
* **Impact:** It does **not** perform perspective-correct barycentric interpolation of depth per pixel ($z(x, y) = \lambda_0 z_0 + \lambda_1 z_1 + \lambda_2 z_2$). Intersecting or interpenetrating triangles suffer from catastrophic sorting flickers, popping, and geometry inversion.

#### Defect HGL-02: Discarded Texture Coordinates
* **File & Lines:** `apps/HolyGL.HC:268-269`
* **Forensic Critique:** `HolyGLTexCoord2f` accepts $(u, v)$ coordinates into `g_hgl.v_curr`, but the rasterizer completely ignores them. There is no texture memory buffer, no bilinear sampling, and no perspective $u/w, v/w$ division.
* **Required Resolution:** Re-implement the triangle inner loop in `RasterTile.HC` with Pineda 28.4 fixed-point edge equations and barycentric $1/w, u/w, v/w$ interpolation.

---

### 2.4 Shader Engine Subsystem (`apps/ShaderEditor.HC`, `apps/DolDoc.HC`)

#### Defect SHD-01: Static Mock IDE in `ShaderEditor.HC`
* **File & Lines:** `apps/ShaderEditor.HC:1-108`
* **Forensic Critique:** `ShaderEditor.HC` is not an editor. It contains 108 lines of static UI that prints a card with preset buttons (0 to 8). It does not contain an editor, a lexer, or an interpreter. Users cannot type or compile new shaders.

#### Defect SHD-02: 2D Analytical Approximations instead of True Raymarching
* **File & Lines:** `apps/DolDoc.HC:1168-1364`
* **Forensic Critique:** The procedural shaders in `DolDocRenderShaderNode` are hand-coded 2D analytical formulas rather than authentic fragment shaders:
  - Shader #1 ("Torus") is an analytical 2D ellipse equation (`cx*cx + cy*cy*2 - ring_r`), not a raymarched 3D signed distance field.
  - Shader #3 ("Fire") is a 3-term sine summation, not multi-octave gradient noise.
  - Pixel evaluation runs sequentially in scalar loops without NEON SIMD vectorization.
* **Required Resolution:** Implement a 2x2 NEON Quad Structure-of-Arrays (SoA) fragment engine in `DolDoc.HC` with fast Newton-Raphson reciprocals, analytical derivatives (`dFdx`/`dFdy`), and multi-core tile dispatching.

---

### 2.5 Stage-2 Self-Hosting Compiler Subsystem (`apps/Compiler.HC`)

#### Defect CMP-01: Zero Floating-Point Code Generation
* **File & Lines:** `apps/Compiler.HC:1-2443`
* **Forensic Critique:** `Compiler.HC` defines `TOK_FLOAT` and `TOK_TYPE_F64`, but emits **zero** floating-point instructions (`FADD`, `FSUB`, `FMUL`, `FDIV`, `LDR D-reg`). It cannot compile `Math3D.HC`, `HolyGL.HC`, `Physics3D.HC`, or `FontVector.HC`.

#### Defect CMP-02: Missing Inline Assembly (`asm { ... }`)
* **Forensic Critique:** `Compiler.HC` has no inline assembler parser. Low-level kernel drivers require reading and writing ARMv8 system registers (`mrs`, `msr`, `isb`, `dmb`, `dc civac`). Without inline assembly, `Compiler.HC` cannot compile `HalPlatform.HC`, `Gic.HC`, or `Timer.HC`.

#### Defect CMP-03: Duplicated Lexer (`apps/Lexer.HC` is Dead Code)
* **File & Lines:** `apps/Compiler.HC:759-970` vs `apps/Lexer.HC:1-887`
* **Forensic Critique:** `Compiler.HC` re-implements its own copy of the lexical tokenizer, leaving `apps/Lexer.HC` completely unused and redundant.
* **Required Resolution:** Add scalar F64 opcodes and an inline assembler parser to `Compiler.HC`, merge the lexer, and enable `#include` to compile the entire OS and decommission `compiler/jit_arm64.c`.

---

### 2.6 Benchmarking & Profiling Subsystem (`apps/BenchCpu.HC`, `apps/HolyBenchmark.HC`)

#### Defect BEN-01: Fake "NEON" Benchmark in `BenchCpu.HC`
* **File & Lines:** `apps/BenchCpu.HC:94-103`
* **Vulnerability / Code:**
  ```c
  U0 BenchCpuMathNeon() {
      // Labeled "Tight Loop Math ALU Stress / NEON"
      while (iter < count) {
          acc = (acc * 1103515245 + 12345) & 0x7FFFFFFF;
          iter = iter + 1;
      }
  }
  ```
* **Forensic Critique:** This loop executes zero NEON vector instructions. It is a scalar integer linear congruential generator loop mislabeled as a NEON stress test.

#### Defect BEN-02: Hardcoded Synthetic Telemetry Constants
* **File & Lines:** `apps/HolyBenchmark.HC:83`
* **Vulnerability / Code:**
  ```c
  ProfilerRecordFrame(dt_us, t_logic, t_raster, 0, 1200, 400, 300);
  ```
* **Forensic Critique:** `smp_wait_us` is forced to 0; `blit_us` is hardcoded to 1,200 us; `dma_us` is hardcoded to 400 us; `wm_us` is hardcoded to 300 us. The profiler graphs these numbers as if they were real hardware measurements.
* **Required Resolution:** Read physical ARMv8 PMU hardware counters (`PMCCNTR_EL0`, `L1D_CACHE_REFILL`, `BR_MIS_PRED`) and replace average FPS with median, 1% low, and 0.1% low frametime pacing.

---

### 2.7 Dead Code & Redundant Files

| Filename | LOC | Reason for Deletion |
| :--- | :---: | :--- |
| `apps/Table.HC` | 337 | Exact 100% clone of `apps/StdLib.HC` lines 113–269. |
| `apps/Lexer.HC` | 887 | Bypassed; `Compiler.HC` embeds its own tokenizer. |
| `boot/uefi/crt_riscv64.c` | 270 | Dead code (NeoOS targets exclusively AArch64). |
| `boot/uefi/crt_x86_64.c` | 241 | Dead code (NeoOS targets exclusively AArch64). |
| `gui/shell.c` | 95 | Obsolete C shell stub (superseded by `Shell.HC`). |
| `gui/wm.c` | 569 | Obsolete C window manager (superseded by `WM.HC`). |

---

## 3. SUMMARY STATUS

All defects documented herein have been identified through direct static analysis and guest runtime screendump verification. They constitute the definitive backlog for future phases of NeoOS development.
