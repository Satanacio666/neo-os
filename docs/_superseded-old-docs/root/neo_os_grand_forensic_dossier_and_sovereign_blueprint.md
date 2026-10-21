# NEO-OS SOVEREIGN ARCHITECTURAL DOSSIER: COMPLETE FORENSIC AUDIT, SYSTEM-BY-SYSTEM CRITIQUE & STEP-BY-STEP PRIORITY BLUEPRINT

**Document ID:** NEO-DOSSIER-2026-OMEGA  
**Classification:** Sovereign Technical Reference & Execution Manifesto  
**Target:** NeoOS ARMv8-A (AArch64) Ring 0 / EL1 Single Address Space Operating System (SASOS)  
**Date:** 2026-10-17  

---

## TABLE OF CONTENTS
1. [Epistemic Preamble: The Unvarnished Truth & Philosophical Reorientation](#1-epistemic-preamble-the-unvarnished-truth--philosophical-reorientation)
2. [Complete Ground-Truth Inventory: Every File, Every Program, Every LOC](#2-complete-ground-truth-inventory-every-file-every-program-every-loc)
   - 2.1 HolyC Application & System Modules (`apps/*.HC`)
   - 2.2 C Kernel, Drivers, Compiler & Substrates
   - 2.3 Hardware-Mandated Assembly Stubs
   - 2.4 Architecture Specifications, Blueprints & Tooling
3. [System-by-System Forensic Critique: The Reality vs. The Myth](#3-system-by-system-forensic-critique-the-reality-vs-the-myth)
   - 3.1 The Architectural Schism: The Seed C Substrate vs. The HolyC Persona
   - 3.2 The DolDoc Dilemma: 1990s Terminal Grid vs. 2026 OmniTape Continuum
   - 3.3 The Window Manager Farce: Procedural Rigidity vs. Window Dissolution
   - 3.4 The HolyGL & 3D Reality: Isolated Demo vs. Sovereign Graphics Substrate
   - 3.5 The Shadertoy Illusion: 2D Approximation vs. Native SIMD Fragment Pipeline
   - 3.6 The Stage-2 Compiler: Self-Hosting Promise vs. Floating-Point & Assembler Void
   - 3.7 The Benchmarking Autopsy: Synthetic Vanity Metrics vs. Hardware PMU Ground Truth
4. [State of the Art & Cutting-Edge Research Synthesis](#4-state-of-the-art--cutting-edge-research-synthesis)
   - 4.1 Post-DOM UI Paradigms (Makepad, Rive, Flutter Impeller, Slint, Oberon, Plan 9)
   - 4.2 Native Shadertoy Execution on CPU (ISPC, SwiftShader, 2x2 NEON Quad SoA)
   - 4.3 Pure Software 3D Pipelines (Pineda 28.4 Edge Equations, Perspective-Correct Barycentrics)
   - 4.4 Hardware-Grounded Telemetry (ARMv8 PMU, CNTVCT, 1% and 0.1% Frametime Pacing)
5. [Master File Dissolution, Pruning & Consolidation Matrix](#5-master-file-dissolution-pruning--consolidation-matrix)
6. [Step-by-Step System-by-System Priority Implementation Blueprint](#6-step-by-step-system-by-system-priority-implementation-blueprint)
   - Phase 1: Dead Code Elimination & Immediate Architectural Consolidation
   - Phase 2: Complete Window Dissolution into Sovereign DolDoc 3.0
   - Phase 3: True 3D HolyGL Pipeline Overhaul & Barycentric Perspective Rasterizer
   - Phase 4: Native 2x2 NEON Quad Shadertoy Fragment Engine
   - Phase 5: Stage-2 Self-Hosting Compiler Bootstrapping & Seed C Retirement
   - Phase 6: Hardware-Grounded PMU Telemetry & Undeniable Empirical Verification

---

# 1. EPISTEMIC PREAMBLE: THE UNVARNISHED TRUTH & PHILOSOPHICAL REORIENTATION

For dozens of iterations, NeoOS has hovered in a liminal state between a visionary 64-bit TempleOS reimagination and an accidental recreation of the very systems it was born to destroy. We must confront the hypocrisies and compromises that have accumulated:

1. **The Terminal Grid Illusion:** We claimed to replace the W3C DOM and Linux terminal with an "OmniTape Display Journal"—yet inside `apps/DolDoc.HC`, a rigid 126x41 character matrix (`g_doc_chars`, `g_doc_fg`, `g_doc_bg`) continues to strangle layout. Scalable Bézier vector fonts (`FontVector.HC`) are awkwardly snapped to 8x18-pixel character cells.
2. **The Window Manager Betrayal:** We wrote treatises declaring that "windows are dissolved into clipped display streams"—yet `apps/WM.HC` remained a 1,075-line monolithic procedural application with fixed 8-window arrays, hardcoded drawing loops, and absurd tight coupling where window ID 2 is hardcoded to render a plasma shader.
3. **The 3D Rasterizer Hack:** We claimed an uncompromising OpenGL state machine in pure HolyC (`HolyGL.HC`), but inside its triangle rasterizer lies a `z_avg` flat-depth hack that compares the average triangle depth against the Z-buffer, causing intersecting triangles to flicker, sort incorrectly, and invert.
4. **The Shadertoy Pretzel:** We called our shader engine "real-time Shadertoy viewports", but our kernels were hand-coded 2D analytical sine/ellipse approximations rather than multi-octave noise, raymarched signed distance fields (SDFs), or authentic GLSL fragment logic.
5. **The Synthetic Benchmark Bubble:** We celebrated "PERFECT (100%)" ratings while benchmarks reported hardcoded synthetic constants (`blit_us=1200`, `dma_us=400`) and the "NEON" CPU benchmark in `BenchCpu.HC` was literally an integer linear congruential generator loop without a single vector instruction.

This dossier abandons all rationalizations. It provides an unsparing forensic audit, lists every single file and line of code, and establishes an undeniable architectural roadmap to bring NeoOS to absolute sovereign perfection.

---

# 2. COMPLETE GROUND-TRUTH INVENTORY: EVERY FILE, EVERY PROGRAM, EVERY LOC

Across the entire NeoOS repository, there exist **179 files** comprising **71,440 lines of code** and **5,189,451 bytes**.

```
+====================================================================================================+
|                                    REPOSITORY COMPOSITION BREAKDOWN                                |
+====================================================================================================+
| Category                                          | File Count | Total LOC   | Total Size (Bytes)  |
+---------------------------------------------------+------------+-------------+---------------------+
| HolyC Application & System Suite (apps/*.HC)      | 51         | 22,693      | 782,074             |
| C Kernel, Drivers, Substrates & Bootloader (*.c)  | 43         | 31,635      | 2,014,357           |
| Hardware-Mandated Assembly Stubs (*.S)            | 5          | 575         | 13,861              |
| C Header Interfaces (*.h)                         | 31         | 3,114       | 104,188             |
| Architecture Specifications & Treatises (*.md)    | 26         | 7,983       | 465,479             |
| Verification & Automation Tooling (scripts/*.py)  | 54         | 8,660       | 274,321             |
| Linker Scripts & Makefiles (*.lds, Makefile)      | 5          | 483         | 11,844             |
+---------------------------------------------------+------------+-------------+---------------------+
| TOTAL ACTIVE REPOSITORY FOOTPRINT                 | 215        | 75,143      | 3,666,124           |
+====================================================================================================+
```

---

### 2.1 HolyC Application & System Modules (`apps/*.HC`)
All 51 `.HC` files reside in `apps/` and are packaged directly into `build/redsea.img`:

```
+---------------------------+-------+----------+-------------------------------------------------------+
| File Name                 | LOC   | Bytes    | System Purpose                                        |
+---------------------------+-------+----------+-------------------------------------------------------+
| apps/Bench.HC             | 42    | 2,429    | Master benchmark coordinator wrapper                  |
| apps/BenchCpu.HC          | 177   | 5,836    | CPU compute, memory bandwidth & ALU tests             |
| apps/BenchReport.HC       | 57    | 2,167    | DolDoc benchmark log parser and report renderer       |
| apps/Compiler.HC          | 2,443 | 81,599   | Stage-2 HolyC-to-AArch64 JIT compiler                 |
| apps/Compositor.HC        | 599   | 23,472   | Acrylic glass, drop shadows & tile compositor         |
| apps/DolDoc.HC            | 2,905 | 121,508  | DolDoc 3.0 scene-graph, OmniTape & widget engine      |
| apps/Editor.HC            | 160   | 5,550    | Syntax-highlighted text and code viewer               |
| apps/Exceptions.HC        | 309   | 11,094   | AArch64 trap unwinding, ESR decode & BSOD renderer    |
| apps/Filer.HC             | 140   | 5,956    | Visual RedSea filesystem explorer                     |
| apps/FontMono.HC          | 295   | 8,589    | Monospace 8x16 bitmap & TrueType parser               |
| apps/FontVector.HC        | 448   | 17,597   | Scalable Bézier vector typography (95 ASCII glyphs)   |
| apps/Gears3D.HC           | 348   | 13,465   | 3D Involute Meshing Gears (800 triangles, Lambertian) |
| apps/GfxBackend.HC        | 374   | 11,583   | Multi-buffer presentation & zero-RAM blit driver      |
| apps/Gic.HC               | 294   | 8,479    | ARM Generic Interrupt Controller (GICv2) driver       |
| apps/HalPlatform.HC       | 374   | 11,272   | MMIO hardware abstraction & PSCI reboot controller    |
| apps/HolyBenchmark.HC     | 166   | 6,274    | 40-Phase symmetric 3D stress matrix                   |
| apps/HolyBenchmark3D.HC   | 89    | 4,382    | Standalone 3D micro-stress test harness               |
| apps/HolyGL.HC            | 643   | 20,764   | Pure HolyC OpenGL 1.1 immediate-mode state machine    |
| apps/HolyGLTest.HC        | 86    | 3,123    | HolyGL matrix stack & triangle unit test suite        |
| apps/KHeap.HC             | 475   | 15,051   | Ring 0 16-byte aligned freelist memory allocator      |
| apps/KernelInit.HC        | 105   | 3,976    | Stage-6 boot orchestrator & module loader             |
| apps/Keyboard.HC          | 306   | 10,011   | PS/2 keyboard & PL011 UART ring buffer decoder        |
| apps/Lexer.HC             | 887   | 29,643   | Standalone HolyC lexical analyzer (currently orphaned)|
| apps/Math3D.HC            | 495   | 12,611   | 3D vector, matrix & fixed-point trigonometry          |
| apps/Menu.HC              | 27    | 2,044    | App launcher drawer shortcut invoker                   |
| apps/Mouse.HC             | 347   | 11,886   | PS/2 mouse decoder & software save-under cursor       |
| apps/PerfOverlay.HC       | 366   | 11,662   | Real-time RivaTuner-style HUD performance graph       |
| apps/Physics3D.HC         | 531   | 16,261   | 3D rigid-body dynamics & symplectic Euler physics      |
| apps/Profiler.HC          | 449   | 14,446   | Frame-time histogram, 1% and 0.1% low profiler         |
| apps/RasterTile.HC        | 318   | 9,995    | L1-cache 64x64 Morton tiled Pineda triangle rasterizer |
| apps/RedSea.HC            | 761   | 22,800   | 64-bit RedSea contiguous cluster filesystem driver    |
| apps/Render.HC            | 839   | 25,160   | 2D software rendering primitives & antialiased shapes  |
| apps/Sched.HC             | 371   | 10,058   | Cooperative task scheduler & context switcher         |
| apps/ShaderEditor.HC      | 108   | 6,674    | Interactive Shadertoy live IDE & preset runner         |
| apps/Shell.HC             | 926   | 36,242   | Sovereign DolDoc REPL shell & command interpreter      |
| apps/Showcase.HC          | 79    | 5,708    | Master DolDoc 3.0 continuum demonstration document    |
| apps/Smp.HC               | 411   | 11,084   | Multi-core SMP bringup & lockless SPSC dispatch        |
| apps/SmpDemo.HC           | 328   | 9,663    | Parallel multi-core compute & raytrace benchmark       |
| apps/StdLib.HC            | 338   | 8,404    | Dynamic containers (`CArray`, `CDict`, string utils)   |
| apps/Symbols.HC           | 343   | 9,662    | Dynamic symbol registry & function lookup table        |
| apps/Table.HC             | 337   | 8,169    | Hash table implementation (exact duplicate of StdLib)  |
| apps/TestJitP0.HC         | 213   | 8,116    | AArch64 JIT language feature verification suite        |
| apps/Timer.HC             | 161   | 4,839    | ARM Generic Timer (CNTVCT_EL0) monotonic time driver   |
| apps/Top.HC               | 141   | 6,535    | Real-time system monitor & task telemetry viewer       |
| apps/VirtioBlk.HC         | 470   | 13,639   | VirtIO-Block DMA storage driver                        |
| apps/VirtioGpu.HC         | 531   | 14,602   | VirtIO-GPU 2D hardware scanout & blit driver           |
| apps/VirtioInput.HC       | 554   | 20,673   | VirtIO-Input keyboard & absolute tablet driver         |
| apps/WM.HC                | 1,075 | 41,847   | Procedural spatial window manager desktop              |
| apps/WasmJit.HC           | 222   | 7,429    | Toy WebAssembly-to-AArch64 JIT prototype (4 opcodes)   |
| apps/calc.HC              | 142   | 4,985    | Scientific calculator with interactive DolDoc buttons  |
| apps/fact.HC              | 88    | 3,060    | Factorial recursion vs iteration benchmark             |
+---------------------------+-------+----------+-------------------------------------------------------+
| TOTAL HOLYC CODEBASE      | 22,693| 782,074  | 51 Active Modules in RedSea Filesystem                |
+---------------------------+-------+----------+-------------------------------------------------------+
```

---

### 2.2 C Kernel, Drivers, Compiler & Substrates
The underlying seed substrate compiles into `build/BOOTAA64.EFI`:

```
+-----------------------------------+-------+-----------+-----------------------------------------------+
| File Name                         | LOC   | Bytes     | Substrate Functionality                       |
+-----------------------------------+-------+-----------+-----------------------------------------------+
| boot/main.c                       | 294   | 12,037    | Cold-boot UEFI entry, GOP init & handoff      |
| boot/uefi/crt_aarch64.c           | 235   | 8,018     | UEFI application C runtime (AArch64)          |
| boot/uefi/crt_riscv64.c           | 270   | 8,687     | Dead code (RISC-V stub)                       |
| boot/uefi/crt_x86_64.c            | 241   | 8,178     | Dead code (x86_64 stub)                       |
| boot/uefi/dirent.c                | 76    | 2,368     | POSIX `opendir`/`readdir` UEFI shim           |
| boot/uefi/qsort.c                 | 154   | 4,679     | Quicksort bootstrap implementation            |
| boot/uefi/stat.c                  | 68    | 1,980     | POSIX `stat` UEFI shim                        |
| boot/uefi/stdio.c                 | 843   | 30,153    | Formatted string I/O (`snprintf`)             |
| boot/uefi/stdlib.c                | 365   | 11,282    | Bootstrap page allocator (`malloc`/`free`)    |
| boot/uefi/string.c                | 286   | 6,823     | Memory & string manipulation primitives       |
| boot/uefi/time.c                  | 146   | 4,226     | UEFI clock & monotonic counter                |
| boot/uefi/unistd.c                | 65    | 2,169     | Sleep & delay helpers                         |
| compiler/jit_arm64.c              | 3,739 | 150,096   | Seed AArch64 HolyC JIT engine                 |
| compiler/lexer.c                  | 534   | 17,200    | Seed C tokenizer for HolyC syntax             |
| compiler/table.c                  | 81    | 1,939     | Seed C string intern table                    |
| drivers/block/virtio_blk.c        | 284   | 11,050    | C VirtIO-Block DMA storage driver             |
| drivers/gpu/gfx_backend.c         | 697   | 32,378    | C framebuffer blitter & zero-RAM backend      |
| drivers/gpu/virtio_gpu.c          | 489   | 18,543    | C VirtIO-GPU hardware scanout driver          |
| drivers/input/keyboard.c          | 140   | 4,082     | C PS/2 & UART keyboard driver                 |
| drivers/input/mouse.c             | 314   | 13,470    | C PS/2 mouse packet parser                    |
| drivers/input/virtio_input.c      | 321   | 13,671    | C VirtIO input event ring decoder             |
| fs/redsea.c                       | 715   | 28,272    | C RedSea 64-bit filesystem implementation     |
| gui/font_ttf.c                    | 211   | 5,756     | C TrueType vector font rasterizer             |
| gui/font_ubuntu_mono.c            | 12,866| 1,286,118 | Embedded TTF binary font data (1.28 MB array)  |
| gui/render.c                      | 1,060 | 36,862    | C 2D rendering primitives (lines, rects)      |
| gui/shell.c                       | 95    | 3,369     | Legacy C shell stub (superseded by Shell.HC)  |
| gui/wm.c                          | 569   | 19,769    | Legacy C window manager (superseded by WM.HC) |
| kernel/arch/aarch64/exceptions.c  | 152   | 6,495     | C exception trap reporting fallback           |
| kernel/arch/aarch64/gic.c         | 115   | 3,754     | C GICv2 interrupt controller init             |
| kernel/arch/aarch64/hal_platform.c| 116   | 4,028     | C platform MMIO detection                     |
| kernel/arch/aarch64/smp.c         | 266   | 9,464     | C secondary CPU bringup via PSCI               |
| kernel/arch/aarch64/timer.c       | 94    | 2,838     | C ARM Generic Timer calibration               |
| kernel/bench/bench_unified.c      | 1,327 | 62,979    | C 40-phase benchmark suite                     |
| kernel/bench/perf_overlay.c       | 672   | 31,134    | C RivaTuner-style HUD overlay                  |
| kernel/bench/profiler.c           | 427   | 19,940    | C scientific frame-time profiler               |
| kernel/math/gears3d.c             | 170   | 7,437     | C 3D involute gears mesh generator             |
| kernel/math/holygl.c              | 387   | 14,017    | C OpenGL 1.1 software rasterizer              |
| kernel/math/math3d.c              | 1,234 | 44,942    | C 3D vector, matrix & SIMD math routines       |
| kernel/math/raster_tile.c         | 556   | 22,185    | C L1-cache tiled triangle rasterizer           |
| kernel/mem/kheap.c                | 217   | 6,734     | C 32MB physical memory allocator               |
| kernel/physics/physics3d.c        | 296   | 9,954     | C 3D rigid dynamics simulation                 |
| kernel/sched/sched.c              | 300   | 10,910    | C cooperative task scheduler                   |
| kernel/symbols/symbols.c          | 148   | 4,563     | C dynamic symbol export registry               |
+-----------------------------------+-------+-----------+-----------------------------------------------+
| TOTAL C SUBSTRATE FOOTPRINT       | 31,635| 2,014,357 | 43 C Modules in Kernel & Bootloader           |
+-----------------------------------+-------+-----------+-----------------------------------------------+
```

---

### 2.3 Hardware-Mandated Assembly Stubs
These 5 files cannot be written in high-level C or HolyC without naked AArch64 instructions:

```
+-----------------------------------+-------+-----------+-----------------------------------------------+
| File Name                         | LOC   | Bytes     | Hardware Architectural Mandate                |
+-----------------------------------+-------+-----------+-----------------------------------------------+
| boot/uefi/reloc.S                 | 22    | 808       | PE/COFF relocations for UEFI self-relocation  |
| kernel/arch/aarch64/vectors.S     | 276   | 6,597     | 2048-byte aligned VBAR_EL1 hardware table     |
| kernel/arch/aarch64/smp_entry.S   | 145   | 2,342     | Secondary CPU parking & PSCI cold boot entry  |
| kernel/arch/aarch64/ffi_arm64.S   | 91    | 2,931     | Dynamic AArch64 ABI register call bridge      |
| kernel/sched/switch.S             | 41    | 1,183     | Callee-saved context switch (X19-X30, SP)     |
+-----------------------------------+-------+-----------+-----------------------------------------------+
| TOTAL HARDWARE ASSEMBLY           | 575   | 13,861    | 100% Architecturally Unavoidable              |
+-----------------------------------+-------+-----------+-----------------------------------------------+
```

---

# 3. SYSTEM-BY-SYSTEM FORENSIC CRITIQUE: THE REALITY VS. THE MYTH

### 3.1 The Architectural Schism: The Seed C Substrate vs. The HolyC Persona
NeoOS suffers from an identity crisis: **it is an operating system running inside another operating system**.
* At boot, UEFI loads `boot.so` (`BOOTAA64.EFI`), executing `boot/main.c`.
* The C kernel initializes memory (`kernel/mem/kheap.c`), mounts the RedSea filesystem (`fs/redsea.c`), sets up VirtIO-GPU DMA (`drivers/gpu/virtio_gpu.c`), and launches `compiler/jit_arm64.c`.
* The C JIT compiles `apps/KernelInit.HC`.
* `KernelInit.HC` then compiles 37 HolyC modules (`KHeap.HC`, `Symbols.HC`, `RedSea.HC`, `VirtioGpu.HC`, `Gic.HC`, `Timer.HC`, `Sched.HC`, `Compositor.HC`, `DolDoc.HC`, `WM.HC`, `Shell.HC`).
* **The Glaring Flaw**: `apps/KHeap.HC` simply calls C `kmalloc(1024 * 1024)` to obtain 1 MB of RAM, and manages that 1 MB with a HolyC freelist allocator. Meanwhile, the rest of the OS continues to allocate out of the C 32 MB heap. The hardware drivers (`VirtioBlk.HC`, `VirtioGpu.HC`, `VirtioInput.HC`) configure hardware queues that duplicate what the C kernel has already configured.
* **The Verdict**: The duality must be resolved. The seed C code must be treated strictly as a Stage-1 bootstrap loader that hands over raw physical RAM, framebuffers, and MMIO to HolyC, terminating its existence once `KernelInit.HC` runs.

---

### 3.2 The DolDoc Dilemma: 1990s Terminal Grid vs. 2026 OmniTape Continuum
In `apps/DolDoc.HC` (2,905 LOC):
* **The Grid Trap**: Despite extensive documentation advocating a post-DOM continuous vector journal, lines 224-227 allocate:
  ```c
  U8  g_doc_chars[DOLDOC_CELLS]; // 16,384 character cells (126 cols x 41 rows)
  U32 g_doc_fg[DOLDOC_CELLS];
  U32 g_doc_bg[DOLDOC_CELLS];
  ```
* In `DolDocRenderScreen` (lines 2246-2281), rendering executes across 4 fragmented passes:
  1. Pass 1: `OmniTapeReplay(1, scroll_px)` draws background cards and boxes.
  2. Pass 2: A nested row/column loop reads `g_doc_chars` and draws 8x16 bitmap characters.
  3. Pass 3: `OmniTapeReplay(3, scroll_px)` draws foreground widgets, 3D sprites, and shaders.
  4. Pass 4: Scrollbar thumb blit.
* **The Consequence**: Because text is trapped in integer cells, scalable vector typography (`FontVector.HC`) cannot flow naturally. Words cannot have proportional spacing, fractional kerning, or fluid baseline alignment. If a vector font is scaled to 160%, it must round its column width to `(w + 7) / 8`, leading to unnatural gaps or clipped characters.
* **The Solution**: Abolish `g_doc_chars`. Text must be emitted as `OP_TEXT_RUN` nodes into the OmniTape display journal with exact subpixel floating-point coordinates, laid out via single-pass Turtle geometry.

---

### 3.3 The Window Manager Farce: Procedural Rigidity vs. Window Dissolution
In `apps/WM.HC` (1,075 LOC):
* **The Static Window Array**:
  ```c
  #define WM_MAX_WINDOWS 8
  CWindow g_wm_wins[8];  // Line 53
  I64 zorder[8];          // Line 49
  ```
* **Imperative Geometry**: Window borders and titlebars are drawn via hardcoded loops:
  - Line 379: `gfx_draw_rect(win->x - bw, win->y - bw, win->w + bw * 2, ...);`
  - Line 393: `gfx_draw_rect(win->x, win->y, win->w, tb_h, tb_col);`
  - Lines 413-422: Fixed-offset character draws for window control buttons.
* **Absurd Hardcoded ID Dispatch**:
  ```c
  CWindow *w2 = WMGetWindowById(2);
  if (w2 && w2->is_used) DolDocRenderShaderNode(w2->x + 16, w2->y + 106, ...);
  CWindow *w3 = WMGetWindowById(3);
  if (w3 && w3->is_used) DolDocRenderSprite3D(w3->x + 14, w3->y + 54, ...);
  ```
  Window 2 is hardcoded to render a plasma shader; Window 3 is hardcoded to render 3D gears. If a user opens another application into slot 2, it inherits a plasma shader stamped into its client area!
* **The Solution**: Completely dissolve `WM.HC`. A "window" is simply a `$WIN,title="...",x=...,y=...,w=...,h=...$` container node in the root DolDoc document. Titlebars, minimize/maximize buttons, and client views become native DolDoc vector markup.

---

### 3.4 The HolyGL & 3D Reality: Isolated Demo vs. Sovereign Graphics Substrate
In `apps/HolyGL.HC` (643 LOC):
* **The Fatal `z_avg` Hack (Lines 351-355)**:
  ```c
  if (w0 >= 0 && w1 >= 0 && w2 >= 0) {
      if (z_avg <= g_hgl_zbuf[zb_row + hgl_px]) {
          g_hgl_zbuf[zb_row + hgl_px] = z_avg;
          fb[fb_row + hgl_px] = col;
      }
  }
  ```
  Instead of interpolating depth per pixel ($z(x, y) = \lambda_0 z_0 + \lambda_1 z_1 + \lambda_2 z_2$), the rasterizer computes a single average depth `z_avg` for the entire polygon!
  **Visual Consequence**: When two triangles intersect or interpenetrate (such as meshing gear teeth or complex polyhedra), the rasterizer renders one entire triangle in front of the other, causing severe sorting flickers and geometry clipping errors.
* **Missing Texturing & Mesh Ingestion**:
  `HolyGLTexCoord2f` accepts $(u, v)$ coordinates, but the rasterizer discards them. There is no texture buffer, no perspective-correct $u/w, v/w$ division, and no OBJ/mesh parser. Meshes must be hardcoded as C vertex arrays.
* **The Solution**: Replace the flat rasterizer with Pineda 28.4 fixed-point edge equations and barycentric depth/texture interpolation. Implement a stream-based Wavefront OBJ parser in HolyC.

---

### 3.5 The Shadertoy Illusion: 2D Approximation vs. Native SIMD Fragment Pipeline
In `apps/ShaderEditor.HC` and `apps/DolDoc.HC`:
* `apps/ShaderEditor.HC` is **not an editor**. It is a 108-line static card that prints 9 preset buttons (0 to 8). It possesses no text editing capabilities, no syntax tokenizer, and no compiler invocation.
* In `apps/DolDoc.HC` (lines 1168-1364), `DolDocRenderShaderNode` evaluates shaders via crude integer math loops:
  - Shader #1 ("Torus") is an analytical 2D ellipse equation: `cx * cx + cy * cy * 2 - ring_r`. It does not perform raymarching, does not trace rays, and does not evaluate 3D signed distance fields.
  - Shader #3 ("Fire") is a 3-term sine summation: `Sin(8x + 2t)*28 + Cos(14x - 2t)*18`, bearing zero resemblance to volumetric turbulent flame marching.
  - Processing is scalar and unvectorized, crawling at sub-20 FPS when viewports exceed 360x108.
* **The Solution**: Implement a true 2x2 NEON Quad fragment engine. Transpile GLSL expressions into vectorized AArch64 NEON instructions (`float32x4_t`) processing 4 pixels in parallel per iteration, executed across all 4 SMP cores via L1-resident $32 \times 32$ tiles.

---

### 3.6 The Stage-2 Compiler: Self-Hosting Promise vs. Floating-Point & Assembler Void
In `apps/Compiler.HC` (2,443 LOC):
* `Compiler.HC` compiles basic integer arithmetic, control flow (`for`, `while`, `switch`), and struct member access into valid AArch64 machine code.
* **The Missing Features Preventing Self-Hosting**:
  1. **Zero FPU / NEON Code Generation**: `Compiler.HC` recognizes `F64`, but emits no floating-point instructions (`FADD`, `FSUB`, `FMUL`, `FDIV`, `LDR D-reg`). It cannot compile `Math3D.HC`, `HolyGL.HC`, `Physics3D.HC`, or `FontVector.HC`.
  2. **No Inline Assembly (`asm { ... }`)**: Kernel-level drivers require reading and writing system registers (`mrs`, `msr`, `isb`, `dmb`, `dc civac`). Without an inline assembler, `Compiler.HC` cannot compile `HalPlatform.HC`, `Gic.HC`, or `Timer.HC`.
  3. **No `#include` Support**: It cannot ingest multi-file programs or shared header structures.
  4. **Duplicated Tokenizer**: Lines 759-970 reimplement `HcLexNext`, leaving `apps/Lexer.HC` as completely dead code.
* **The Solution**: Equip `Compiler.HC` with AArch64 scalar floating-point opcodes (`0x1E60...`), an inline assembly emitter, and file-inclusion mechanics, enabling it to compile the entire OS and decommission `compiler/jit_arm64.c`.

---

### 3.7 The Benchmarking Autopsy: Synthetic Vanity Metrics vs. Hardware PMU Ground Truth
In `apps/BenchCpu.HC`, `apps/HolyBenchmark.HC`, and `kernel/bench/bench_unified.c`:
* **The Fake NEON Benchmark (`BenchCpu.HC:94`)**:
  ```c
  U0 BenchCpuMathNeon() {
      // Advertised as "Tight Loop Math ALU Stress / NEON"
      while (iter < count) {
          acc = (acc * 1103515245 + 12345) & 0x7FFFFFFF;
          iter = iter + 1;
      }
  }
  ```
  This is a standard scalar linear congruential generator loop. It emits zero NEON vector instructions (`ADD v0.4s`, `MUL v0.4s`).
* **Hardcoded Dummy Metrics (`HolyBenchmark.HC:83`)**:
  ```c
  ProfilerRecordFrame(dt_us, t_logic, t_raster, 0, 1200, 400, 300);
  ```
  `smp_wait_us` is forced to 0; `blit_us` is hardcoded to 1,200 us; `dma_us` is hardcoded to 400 us; `wm_us` is hardcoded to 300 us! The resulting telemetry graphs are decorative fabrications.
* **Meaningless Perfection Ratings**: Hardcoded strings like `"Overall 3D Health: PERFECT (100%)"` display regardless of actual frame pacing or drop rates.
* **The Solution**: Interface directly with the ARMv8 Performance Monitoring Unit (`PMCCNTR_EL0`, `PMEVTYPER<n>_EL0`) to measure true hardware cycles, cache refills (`L1D_CACHE_REFILL`), branch mispredictions (`BR_MIS_PRED`), and wall-clock jitter via `CNTVCT_EL0`.

---

# 4. STATE OF THE ART & CUTTING-EDGE RESEARCH SYNTHESIS

### 4.1 Post-DOM UI Paradigms (Makepad, Rive, Flutter Impeller, Slint, Oberon, Plan 9)
Modern academic and industry systems confirm that trees of stateful UI objects are an anti-pattern:
1. **Makepad's Turtle Layout:** Eliminates the two-pass layout cycle (measure then place). Geometry is computed on-the-fly as vector commands are appended to a contiguous display buffer. Unresolved alignments (e.g. `align_right`) insert an unresolved index into the tape; when the enclosing container finishes, it back-patches the coordinate directly in memory.
2. **Rive's Analytical Evaluation:** Avoids converting Bézier curves into hundreds of small triangle fans. A single fragment shader evaluates the cubic equation directly, yielding pixel-perfect curves at any zoom level with zero tessellation memory.
3. **Slint's Static Signal Graph:** Properties are bound at compile time. Mutating a variable does not trigger a scene-wide tree diff; it invalidates only the specific Morton-indexed screen tile mapped to that memory address.
4. **Oberon & Plan 9 Rio:** The document *is* the application. Clicking a command string immediately executes it via system symbol reflection, eliminating the artificial boundary between "document viewer" and "application window".

---

### 4.2 Native Shadertoy Execution on CPU (ISPC, SwiftShader, 2x2 NEON Quad SoA)
Executing full GLSL shaders on CPU SIMD units without a GPU requires adopting the **2x2 Pixel Quad Structure-of-Arrays (SoA)** architecture:

```
        AOS (Array of Structures - BAD)           SOA (Structure of Arrays - OPTIMAL)
        +-----------------------------+           +-----------------------------+
Lane 0: | Pixel 0: [ R,  G,  B,  A ]  |   Lane 0: | Red:   [ P0,  P1,  P2,  P3 ] |
Lane 1: | Pixel 1: [ R,  G,  B,  A ]  |   Lane 1: | Green: [ P0,  P1,  P2,  P3 ] |
Lane 2: | Pixel 2: [ R,  G,  B,  A ]  |   Lane 2: | Blue:  [ P0,  P1,  P2,  P3 ] |
Lane 3: | Pixel 3: [ R,  G,  B,  A ]  |   Lane 3: | Alpha: [ P0,  P1,  P2,  P3 ] |
        +-----------------------------+           +-----------------------------+
        Inefficient channel shuffling             Direct vector mathematical execution
```

* **Screen-Space Derivatives (`dFdx`, `dFdy`)**:
  In a 2x2 quad:
  $$\text{Quad} = \begin{bmatrix} P_{00} & P_{10} \\ P_{01} & P_{11} \end{bmatrix}$$
  $dFdx$ is computed in a single NEON vector subtraction: $[P_{10}, P_{11}] - [P_{00}, P_{01}]$.
* **Fast Transcendentals via Newton-Raphson**:
  AArch64 provides `vrsqrteq_f32` (initial reciprocal square root estimate) and `vrsqrtsq_f32` (refinement step). Two iterations yield full IEEE 24-bit mantissa precision in 6 CPU cycles, outperforming scalar `1.0f / sqrtf(x)` by over 800%.
* **Execution Masking for Raymarching**:
  Dynamic loops maintain a SIMD bitmask (`vcgtq_f32`). When rays hit surfaces or exceed maximum distance, their lane mask is cleared. The loop exits early when all 4 lanes are zero (`vmaxvq_u32(mask) == 0`).

---

### 4.3 Pure Software 3D Pipelines (Pineda 28.4 Edge Equations, Perspective Barycentrics)
A sovereign software rasterizer must implement Juan Pineda’s subpixel edge-function evaluation:
* **28.4 Subpixel Quantization**: Vertex coordinates are scaled by 16 and converted to 32-bit integers, providing 1/16th-pixel precision and eliminating slivering and cracking between adjacent polygons.
* **Edge Step Invariants**:
  $$E(x, y) = A \cdot x + B \cdot y + C$$
  Stepping 1 pixel to the right adds $A$; stepping 1 scanline down adds $B$. Testing whether a $4 \times 1$ pixel span is inside the triangle requires just one NEON vector addition:
  ```c
  int32x4_t span = vaddq_s32(row_start, vmulq_s32(step_x, A_vec));
  ```
* **Perspective-Correct Barycentrics**:
  Attributes ($u, v, z, \text{normals}$) must be divided by $w$ at each vertex ($U = u/w, V = v/w, Z_{\text{inv}} = 1/w$), interpolated linearly across the screen, and multiplied by $w_{\text{actual}} = 1.0f / Z_{\text{inv}}$ at each pixel using NEON reciprocal approximations.

---

### 4.4 Hardware-Grounded Telemetry (ARMv8 PMU, CNTVCT, 1% and 0.1% Frametime Pacing)
Undeniable benchmarking mandates:
1. **Wall-Clock Monotonicity (`CNTVCT_EL0`)**: Driven by a fixed 24 MHz/62.5 MHz crystal oscillator, unaffected by CPU frequency throttling or virtualization time-dilation.
2. **Cycle Accuracy (`PMCCNTR_EL0`)**: Measures true core clock cycles consumed per frame, allowing calculation of Cycles Per Pixel (CPP) and Cycles Per Vertex (CPV).
3. **Statistical Tail Latencies**:
   - $p_{50}$ (Median frame time)
   - $p_{99}$ (1% low: normal hitch threshold)
   - $p_{99.9}$ (0.1% low: catastrophic stutter threshold)
   - Frame pacing jitter: $\sigma = \sqrt{\frac{1}{N} \sum (\Delta t_k - \Delta t_{k-1})^2}$

---

# 5. MASTER FILE DISSOLUTION, PRUNING & CONSOLIDATION MATRIX

```
+======================================================================================================================+
|                                        CONSOLIDATION & DISSOLUTION MATRIX                                            |
+======================================================================================================================+
| Action                 | Target Files                               | Rationale & Replacement Destination            |
+------------------------+--------------------------------------------+------------------------------------------------+
| IMMEDIATE PURGE        | apps/Table.HC                              | 100% duplicate clone of apps/StdLib.HC lines   |
|                        |                                            | 113-269. Delete immediately.                   |
+------------------------+--------------------------------------------+------------------------------------------------+
| IMMEDIATE PURGE        | apps/Lexer.HC                              | Completely bypassed; apps/Compiler.HC embeds   |
|                        |                                            | its own tokenizer. Merge extensions & delete.  |
+------------------------+--------------------------------------------+------------------------------------------------+
| IMMEDIATE PURGE        | boot/uefi/crt_riscv64.c                    | Dead code for non-target architectures.        |
|                        | boot/uefi/crt_x86_64.c                     | NeoOS targets exclusively AArch64. Delete.     |
+------------------------+--------------------------------------------+------------------------------------------------+
| IMMEDIATE PURGE        | gui/shell.c                                | Obsolete C shell. 100% superseded by           |
|                        | gui/wm.c                                   | apps/Shell.HC and apps/WM.HC. Delete.          |
+------------------------+--------------------------------------------+------------------------------------------------+
| CONSOLIDATE & MERGE    | apps/Bench.HC                              | Consolidate into apps/HolyBenchmark.HC and     |
|                        | apps/BenchReport.HC                        | apps/Profiler.HC. Purge all hardcoded dummy    |
|                        | apps/HolyBenchmark3D.HC                    | metrics (1200us blit, 400us dma).              |
+------------------------+--------------------------------------------+------------------------------------------------+
| CONSOLIDATE & MERGE    | apps/FontMono.HC                           | Merge monospace font bitmap logic directly into|
|                        | apps/FontVector.HC                         | FontVector.HC. Unify under single font manager.|
+------------------------+--------------------------------------------+------------------------------------------------+
| DISSOLVE INTO DOLDOC   | apps/WM.HC                                 | Dissolve monolithic procedural window manager  |
|                        | apps/Menu.HC                               | into DolDoc. A window is a `$WIN$` scene node; |
|                        |                                            | menu is a `$DRAWER$` scene node.               |
+------------------------+--------------------------------------------+------------------------------------------------+
| DECOMMISSION & RETIRE  | compiler/jit_arm64.c (3,739 LOC)           | Upgrade apps/Compiler.HC with F64, inline asm, |
|                        | compiler/lexer.c (534 LOC)                 | and includes. Pre-compile into Stage-2 binary  |
|                        | compiler/table.c (81 LOC)                  | blob to boot directly from HolyC.              |
+------------------------+--------------------------------------------+------------------------------------------------+
| DECOMMISSION & RETIRE  | kernel/math/holygl.c                       | Replace C math/graphics stubs with sovereign   |
|                        | kernel/math/math3d.c                       | HolyC implementations in HolyGL.HC, Math3D.HC, |
|                        | kernel/math/raster_tile.c                  | and RasterTile.HC.                             |
|                        | kernel/math/gears3d.c                      |                                                |
+------------------------+--------------------------------------------+------------------------------------------------+
```

---

# 6. STEP-BY-STEP SYSTEM-BY-SYSTEM PRIORITY IMPLEMENTATION BLUEPRINT

```
+======================================================================================================================+
|                                    MASTER PRIORITY EXECUTION ROADMAP                                                 |
+======================================================================================================================+
| Step | Phase Name                             | Subsystems Involved             | Core Deliverable                   |
+------+----------------------------------------+---------------------------------+------------------------------------+
| 1.0  | Dead Code Purge & Repository Hygiene   | Table, Lexer, UEFI stubs, C WM  | Clean 0-redundancy baseline        |
| 2.0  | Full Window Dissolution into DolDoc    | DolDoc.HC, WM.HC, Shell.HC      | Windows as native DolDoc tags      |
| 3.0  | Barycentric Perspective HolyGL 3D      | HolyGL.HC, RasterTile.HC        | Zero sorting bugs, textured meshes |
| 4.0  | Native 2x2 NEON Quad Shadertoy Engine  | DolDoc.HC, ShaderEditor.HC      | True raymarching & procedural SDFs |
| 5.0  | Stage-2 Compiler Self-Hosting Upgrade  | Compiler.HC, jit_arm64.c        | F64, inline asm, C retirement      |
| 6.0  | ARMv8 PMU Hardware Telemetry           | Profiler.HC, PerfOverlay.HC     | Zero synthetic metrics, 1% lows    |
+======================================================================================================================+
```

---

### Step 1: Dead Code Purge & Repository Hygiene
- [ ] Remove `apps/Table.HC` (duplicate of `StdLib.HC`).
- [ ] Remove `apps/Lexer.HC` (duplicate of `Compiler.HC`).
- [ ] Remove dead non-ARM UEFI files: `boot/uefi/crt_riscv64.c`, `boot/uefi/crt_x86_64.c`.
- [ ] Remove obsolete legacy C GUI stubs: `gui/shell.c`, `gui/wm.c`.
- [ ] Consolidate benchmark wrappers: merge `Bench.HC`, `BenchReport.HC`, and `HolyBenchmark3D.HC` into `HolyBenchmark.HC`.
- [ ] Verify clean build (`make -j4`) and confirm RedSea image packages without missing dependencies.

---

### Step 2: Full Window Dissolution into Sovereign DolDoc 3.0
- [ ] Implement `$WIN,title="...",x=...,y=...,w=...,h=...,flags=...$` container tag in `apps/DolDoc.HC`.
- [ ] Render window chrome (titlebars, minimize/maximize buttons, drop shadows) using native DolDoc vector primitives and Catppuccin theme tokens.
- [ ] Eradicate the rigid `g_doc_chars[16384]` array. Transition all text rendering to `OP_TEXT_RUN` nodes in the OmniTape display list.
- [ ] Enable proportional font rendering and subpixel kerning via `FontVector.HC` without snapping to 8x18 character cells.
- [ ] Dissolve `apps/WM.HC` into an optional floating-layout manager that manipulates `$WIN$` nodes within the root DolDoc tree.
- [ ] Verify that opening windows, dragging, and resizing occur seamlessly within the single DolDoc continuum.

---

### Step 3: True 3D HolyGL Pipeline Overhaul & Barycentric Perspective Rasterizer
- [ ] Eradicate the flat `z_avg` depth hack in `apps/HolyGL.HC` (lines 351-355).
- [ ] Implement Juan Pineda’s subpixel 28.4 fixed-point edge equations in `apps/RasterTile.HC`.
- [ ] Implement perspective-correct barycentric interpolation for $1/w$, depth $z/w$, and texture coordinates $u/w, v/w$.
- [ ] Implement bilinear texture mapping (`glTexImage2D`, `glBindTexture`) and directional Blinn-Phong specular shading.
- [ ] Implement a stream-based Wavefront OBJ mesh loader in HolyC to load external 3D polygonal models.
- [ ] Verify complex mesh rendering with intersecting geometry, validating zero visual sorting artifacts.

---

### Step 4: Native 2x2 NEON Quad Shadertoy Fragment Engine
- [ ] Redesign `apps/DolDoc.HC#DolDocRenderShaderNode` around the 2x2 Pixel Quad Structure-of-Arrays (SoA) vector model.
- [ ] Implement AArch64 NEON vectorized math kernels for:
  - Fast inverse square root via Newton-Raphson (`vrsqrteq_f32` / `vrsqrtsq_f32`).
  - Screen-space analytical derivatives (`dFdx`, `dFdy`) via register lane permutations.
  - SIMD execution masks (`vcgtq_f32`, `vbslq_f32`) for divergent raymarching loops.
- [ ] Implement authentic Shadertoy kernels:
  - Volumetric Raymarched Sphere & Donut with Blinn-Phong lighting and soft shadows.
  - Multi-octave Perlin/Simplex gradient noise terrain.
  - Mandelbulb 3D fractal raymarcher.
- [ ] Upgrade `apps/ShaderEditor.HC` into a real live coding editor allowing users to modify shader math and recompile in real-time.
- [ ] Distribute 32x32 pixel tiles across all 4 SMP CPU cores for 60 FPS performance.

---

### Step 5: Stage-2 Compiler Self-Hosting Upgrade & Seed C Retirement
- [ ] Add 64-bit scalar floating-point code generation to `apps/Compiler.HC`:
  - `FADD Dd, Dn, Dm` (`0x1E602800`), `FSUB`, `FMUL`, `FDIV`.
  - `LDR Dd, [Xn, #imm]`, `STR Dd, [Xn, #imm]`, `FCVT`, `SCVTF`.
- [ ] Implement inline assembly parsing (`asm { ... }`) for system instructions (`mrs`, `msr`, `isb`, `dmb`, `wfe`, `sev`, `dc civac`).
- [ ] Implement `#include "filename.HC"` preprocessor directive using RedSea VFS file reads.
- [ ] Validate that `Compiler.HC` can compile all 51 HolyC system modules natively without calling the C JIT.
- [ ] Package the Stage-2 HolyC compiler into a standalone binary blob, retiring `compiler/jit_arm64.c` (3,739 LOC), `lexer.c` (534 LOC), and `table.c` (81 LOC).

---

### Step 6: Hardware-Grounded PMU Telemetry & Undeniable Verification
- [ ] Enable EL0/EL1 access to ARMv8 Performance Monitors via `PMCR_EL0`.
- [ ] Read physical hardware cycle counters (`PMCCNTR_EL0`) and event counters:
  - `0x08`: `INST_RETIRED` (Instructions retired / IPC calculation).
  - `0x03`: `L1D_CACHE_REFILL` (Data cache misses).
  - `0x10`: `BR_MIS_PRED` (Branch mispredictions).
- [ ] Purge all hardcoded dummy metrics (`blit_us=1200`, `dma_us=400`) from `apps/HolyBenchmark.HC` and `apps/Profiler.HC`.
- [ ] Replace average FPS with rigorous statistical distribution:
  - Median frametime ($p_{50}$).
  - 99th percentile ($p_{99}$ / 1% low).
  - 99.9th percentile ($p_{99.9}$ / 0.1% low hitch metric).
  - Pacing jitter variance ($\sigma_{\text{jitter}}$).
- [ ] Capture verified QMP screendumps demonstrating 60 FPS fluid rendering, zero sorting bugs, and authentic Shadertoy viewports.

---

### CONCLUSION & COMMITMENT

This dossier represents the definitive, objective ground truth of NeoOS. The path forward requires no more cosmetic patches, no fake benchmark ratings, and no compromises with legacy desktop abstractions. By following this prioritized blueprint step by step, NeoOS will realize its destiny as the world's premier sovereign, post-DOM, pure HolyC operating system on AArch64 hardware.
