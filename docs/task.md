# NeoOS Sovereign Engineering Roadmap & Task Tracker

## 1. Master Phase Progression (Empirical Status)

- [x] **Phase 0: Bare-Metal UEFI Bootstrap & GOP Discovery**
  - AArch64 PE32+ loader in `boot/uefi/uefi_main.c`.
  - GOP Linear Framebuffer discovery (1024x768x32bpp).
  - PL011 UART early serial logging (`0x09000000`).
  - GICv2 distributor & CPU interface initialization.

- [x] **Phase 1: Zero-RAM Scanout & NEON 128-bit Blit Engine**
  - Direct GOP non-temporal streaming blits (`stnp`) via `gfx_neon_blit_nt()` in `gui/render.c`.
  - Double-buffering vs. Zero-RAM direct mode toggle (`zeroram on/off`).
  - Hardware monotonic timer integration (`CNTVCT_EL0`, 62.5MHz).

- [x] **Phase 2: Input Subsystem & Hardware Tablet Driver**
  - Two-level `LocateHandleBuffer` discovery for `EFI_SIMPLE_POINTER` and `EFI_ABSOLUTE_POINTER`.
  - Non-buffered frontbuffer cursor save/restore (`mouse_draw_cursor_front()`).
  - VirtIO-Input transport bridge in `drivers/input/virtio_input.c`.

- [x] **Phase 3: VirtIO Hardware Drivers & Storage Subsystem**
  - VirtIO-GPU 2D paravirtualized driver (`drivers/gpu/virtio_gpu.c`).
  - VirtIO-Block MMIO driver (`drivers/block/virtio_blk.c`).
  - Terry Davis RedSea 64-bit contiguous filesystem (`fs/redsea.c`).

- [x] **Phase 4: Unified DolDoc Surface (UDS) & Window Manager**
  - 64-bit dirty row mask (`s_doc_dirty_mask`) for 0.0 ms static redraw.
  - Interactive DolDoc markup tags (`$BT$`, `$TX$`, `$VP$`).
  - Window manager chrome, dragging, focus, and Z-ordering (`gui/wm.c`).

- [x] **Phase 5: Purging Lua & Restoring Pure HolyC Sovereignty**
  - Completely excised 35 foreign C files, 13,000+ lines of Lua 5.4.7 and libc POSIX shims.
  - Reclaimed heap memory and eliminated GC fragmentation.
  - Re-anchored the userland on pure HolyC (`.HC`) applications.

- [x] **Phase 6: Visual HolyC Applications & RedSea Persistence**
  - Visual File Manager (`apps/Filer.HC`) and DolDoc Editor (`apps/Editor.HC`).
  - System monitor (`apps/Top.HC`) tracking heap and CPU stats.
  - In-place RedSea sector modification and persistence (`save` / `edit`).

- [x] **Phase 7: Multi-Core SMP Dispatch & Task Architecture**
  - Secondary vCPU bring-up via PSCI `CPU_ON` in `kernel/arch/aarch64/smp.c`.
  - Atomic spinlocks with release semantics (`stlxr`) and memory barriers (`DMB SY`).
  - Multiprocessing demo application in HolyC (`apps/SmpDemo.HC`).

- [x] **Phase 8: Sovereign Pure HolyC OpenGL Pipeline & JIT Upgrades**
  - Pure HolyC 3D Graphics pipeline & OpenGL state machine (`apps/HolyGL.HC`).
  - Upgraded JIT compiler (`compiler/jit_arm64.c`) with comma variable declarations, member array indexing, chained struct assignment, and in-place `++`/`--`.
  - Verified by `scripts/test_p8_holygl.py` passing 100% with zero regressions.

---

## 2. What Is Left & Incomplete (Remaining Work)

- [x] **Phase 9: Sovereign Pure HolyC Self-Hosting Compiler (`apps/Compiler.HC`)**
  - [x] Implemented full HolyC tokenizer (ident, num, string, symbols) in pure HolyC.
  - [x] Implemented recursive descent parser for expressions, functions, conditionals, and while loops in pure HolyC.
  - [x] Implemented native AArch64 machine code emitter emitting directly into executable RAM (`hal_flush_cache`).
  - [x] Full self-hosting JIT scorecard running in native Ring 0 RAM with 7 of 7 suites passing (100% precision):
    - Test 1: Arithmetic Precedence `(10+20)*3 - 50/2 = 65` [PASS]
    - Test 2: Local Variables & Compound Ops `a=40; b=2; a+=b = 42` [PASS]
    - Test 3: Conditionals & Branching `Check(15) + Check(5) = 300` [PASS]
    - Test 4: While Loop Accumulator `sum(1..10) = 55` [PASS]
    - Test 5: Multi-parameter Function Calls `Add3(10, 20, 30) = 60` [PASS]
    - Test 6: Recursive Call `Fact(5) = 120` [PASS]
    - Test 7: External Ring 0 Symbol Invocation (`doldoc_printf`) = `777` [PASS]
  - [x] Empirically validated via `scripts/test_p9_compiler.py` in live QEMU virt RAM.

---

- [x] **Phase 10: Grand Architectural Consolidation & Pure HolyC Sovereign Desktop**
  - [x] Cold-boot directly into `WMEventLoop()` across all 31 HolyC subsystems in Ring 0 with 0 C stubs and 0 dummy passes.
  - [x] Cold-boot reaches all 8 presentation milestones: `WMInit` -> `CompositorDamageAll` -> `gfx_dirty_all` -> `WMDrawDesktop` -> `WMDrawWindows` -> `WMDrawTaskbar` -> `CompositorPresent` -> `mouse_draw_cursor_front`.
  - [x] Fixed compiler JIT 32-bit load zero-extension (`LDR Wd, [Xn]` opcode `0xB9400000`) resolving unsigned 32-bit pixel comparisons in `compiler/jit_arm64.c`.
  - [x] Decoupled CPU presentation from VirtIO-GPU queue polling stall in `apps/GfxBackend.HC`.
  - [x] Repackaged RedSea with standard partition boot record signature on LBA 0 (`scripts/mkredsea.py`).
  - [x] 100% Hardware-Driven Verification Scorecards:
    - `VirtioBlk.HC`: 5 / 5 [PASS] (MMIO scan, capacity query, bare-metal sector read, LBA 0 boot record, DMA round-trip).
    - `VirtioGpu.HC`: 5 / 5 [PASS] (2D controller init, controlq 0 page-alignment, 2D resource create, backing memory attach, flush pipeline).
    - `VirtioInput.HC`: 5 / 5 [PASS] (MMIO scanner discovering slots 29 & 30, vring alignment, EV_KEY translation, shift state machine, 15-bit tablet axis normalization).
    - `Keyboard.HC`: 5 / 5 [PASS] (FIFO queue, special keys, 256-element wrap-around integrity, PL011 UART hardware reflection).
    - `Mouse.HC`: 5 / 5 [PASS] (bounds clamping, button states, 16x16 cursor bitmap, non-destructive save-under pixel preservation/restore, trajectory tracking).

---

- [x] **Phase 11: The DolDoc Unified Continuum, Sovereign Fullscreen Shell & TempleOS Parity Tools**
  - [x] Dedicated 4 MB Kernel Execution Stack (`EfiLoaderData`) resolving nested compiler/parser stack consumption across all 31 HolyC subsystems.
  - [x] Pixel-perfect, distraction-free fullscreen DolDoc 3.0 shell cold boot with dual-column hardware telemetry and clickable quick-launch tags.
  - [x] Bidirectional seamless switching between Fullscreen DolDoc Shell and Multi-Window Desktop Compositor (`wm` <-> `shell`).
  - [x] Runtime AArch64 Machine Code Disassembler (`uf <symbol>`) with colored mnemonics, operands, branch offsets, and byte metrics.
  - [x] Interactive HolyC Source Code Inspector (`src <file>`) reading directly from RedSea FS with line numbering and syntax highlighting.
  - [x] Master DolDoc Capabilities Showcase (`apps/Showcase.HC`) displaying interactive widgets, inline vector 3D polyhedral sprites, real-time telemetry, and executable code links.
  - [x] Cleaned up compiler debug traces achieving instantaneous (~1s) cold-boot compilation of all 31 HolyC files.
  - [x] 100% verified via automated tests: `test_cold_boot.py`, `test_showcase_and_tools.py`, and `test_wm_shell_switch.py`.

---

## 3. Future Implementation Phases & Sovereign Roadmap

- [ ] **Phase 12: Dead Code Elimination & Clean 0-Redundancy Baseline**
  - [ ] Delete `apps/Table.HC` (100% duplicate clone of `apps/StdLib.HC`).
  - [ ] Merge and delete `apps/Lexer.HC` (bypassed by `Compiler.HC`).
  - [ ] Delete dead non-ARM UEFI files: `boot/uefi/crt_riscv64.c`, `boot/uefi/crt_x86_64.c`, and their linker scripts.
  - [ ] Delete obsolete legacy C GUI stubs: `gui/shell.c`, `gui/wm.c`.
  - [ ] Consolidate benchmark wrappers (`Bench.HC`, `BenchReport.HC`, `HolyBenchmark3D.HC`) into `HolyBenchmark.HC`.

- [ ] **Phase 13: Sovereign DolDoc 3.0 & Complete Window Dissolution**
  - [ ] Eradicate `g_doc_chars[16384]` and transition all text to continuous subpixel vector runs (`FontVector.HC`).
  - [ ] Implement Elastic Tabstops to preserve strict columnar alignment for code, memory listings, and disassembly with proportional typography.
  - [ ] Implement `$WIN,title="...",x=...,y=...,w=...,h=...$` container nodes in DolDoc with native Catppuccin vector chrome.
  - [ ] Dissolve `apps/WM.HC` and `apps/Compositor.HC` into DolDoc's single-pass OmniTape traversal over Morton 64x64 L1 cache-resident tiles.
  - [ ] Inline the interactive shell into a `$REPL$` node supporting both inline command outputs and elevated floating windows.

- [ ] **Phase 14: Barycentric Perspective HolyGL 3D Pipeline Overhaul**
  - [ ] Eradicate the flat `z_avg` depth hack in `apps/HolyGL.HC:351-355`.
  - [ ] Implement Juan Pineda's 28.4 subpixel fixed-point edge equations in `apps/RasterTile.HC`.
  - [ ] Implement perspective-correct barycentric depth ($z/w$) and texture coordinate ($u/w, v/w$) interpolation with NEON fast reciprocals.
  - [ ] Implement bilinear texture mapping (`glTexImage2D`, `glBindTexture`) and Blinn-Phong specular shading.
  - [ ] Implement a streaming Wavefront OBJ polygonal mesh loader in HolyC.

- [ ] **Phase 15: Native 2x2 NEON Quad Shadertoy Fragment Engine**
  - [ ] Redesign `DolDocRenderShaderNode` using a Structure-of-Arrays (SoA) 2x2 Pixel Quad model evaluating 4 pixels per NEON SIMD iteration.
  - [ ] Implement fast Newton-Raphson inverse square roots, analytical screen-space derivatives (`dFdx`, `dFdy`), and SIMD execution masking.
  - [ ] Implement authentic raymarched SDF primitives (Sphere, Torus, Box) and multi-octave Perlin/Simplex gradient noise.
  - [ ] Upgrade `apps/ShaderEditor.HC` into an authentic live code editor.
  - [ ] Parallelize 32x32 pixel tiles across all 4 SMP CPU cores.

- [ ] **Phase 16: Stage-2 Compiler Self-Hosting Upgrade & Seed C Retirement**
  - [ ] Add scalar 64-bit floating-point code generation (`FADD`, `FSUB`, `FMUL`, `FDIV`, `LDR/STR D-reg`) to `apps/Compiler.HC`.
  - [ ] Implement inline assembly parsing (`asm { ... }`) for ARMv8 system instructions (`mrs`, `msr`, `isb`, `dmb`, `wfe`, `sev`, `dc civac`).
  - [ ] Implement `#include` preprocessor directives using RedSea VFS file reads.
  - [ ] Pre-compile `Compiler.HC` into a Stage-2 standalone binary blob and decommission `compiler/jit_arm64.c` (3,739 LOC), `lexer.c` (534 LOC), and `table.c` (81 LOC).

- [ ] **Phase 17: Hardware-Grounded PMU Telemetry & Undeniable Verification**
  - [ ] Read physical ARMv8 PMU hardware counters (`PMCCNTR_EL0`, `L1D_CACHE_REFILL`, `BR_MIS_PRED`, `CNTVCT_EL0`).
  - [ ] Purge all synthetic dummy constants (`blit_us=1200`, `dma_us=400`) and `"PERFECT 100%"` vanity strings from `HolyBenchmark.HC` and `Profiler.HC`.
  - [ ] Report statistical frame pacing distributions: median ($p_{50}$), 1% low ($p_{99}$), 0.1% low ($p_{99.9}$), and jitter variance ($\sigma_{\text{jitter}}$).

---

## 4. Physical Silicon Roadmap

- [ ] **Real Hardware Bring-up (Physical Silicon Roadmap)**
  - [ ] Flattened Device Tree (FDT / DTB) parser for physical SoC address discovery.
  - [ ] Physical board bring-up on Raspberry Pi 4/5 or Rockchip RK3399/RK3326.
  - [ ] Native USB xHCI host controller driver.


