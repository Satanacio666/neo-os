# NeoOS — Consolidated Defect, Design-Change and Fix Record
**A Comprehensive Register of Every Shortcoming, Defect, Retracted Premise, and Engineering Fix Across the Engagement**

---

## 0. Scope & Categorization Rules

This record documents **problems only**: defects, incorrect premises, documentation contradictions, dead/unreachable code, integration gaps, hardware/environment failures, and the concrete engineering fixes applied to resolve each. 

Features and subsystems that were already functioning correctly are omitted, except where an explicit *"checked, not a defect"* analysis was required to refute an invalid hypothesis. All game/Minecraft-specific items have been filtered out to focus strictly on the **NeoOS operating system, kernel, drivers, graphics pipeline, JIT compiler, window manager, and infrastructure**.

### Classification Buckets
Every finding falls into one of eight distinct categories:

| # | Category | Nature | Count | Consequence if Ignored |
|---|:---|:---|:---:|:---|
| **1** | **Documentation Contradictions** | Claims in README/commits contradicting actual implementation | 17 (C1–C18) | Unverifiable claims; user confusion; misleading architecture specifications |
| **2** | **Dead / Unreachable Code** | Vendored trees, orphan files, phantom shell commands | 8 (D1–D10) | Image bloat, repository clutter, uncallable code paths |
| **3** | **Integration Gaps** | Subsystems present in tree but disconnected from interfaces | 5 (I1–I5) | Functional capabilities completely unreachable at runtime |
| **4** | **Real Code Defects** | Kernel, math, driver, and compiler logic bugs | 13 (R1–R13) | Memory corruption, hard freezes, distorted rendering, CPU stalls |
| **5** | **JIT Compiler Defects & Limits** | Flaws in the AArch64 machine code emitter and parser | 8 (J1–J8) | Infinite compilation loops, register clobbering, type reflection failure |
| **6** | **Kernel Video & Compositor Defects** | Rendering bugs, framebuffer collisions, cache overhead | 8 (K1–K8) | Screen corruption, flickering, tearing, 350ms pipeline stalls |
| **7** | **Wrong Premises in Plans** | Flawed assumptions in design plans that had to be retracted | 6 (P1–P6) | Optimization of wrong subsystems; regression risks |
| **8** | **Environment & Infrastructure** | Host toolchain, QEMU, Python, and container failures | 6 (E1–E6) | Broken build pipelines; unreproducible benchmarks; black live stream |

---

## 1. Documentation Contradictions (C1–C18)

| ID | Documented Claim | Code Reality | Resolution / Status |
|:---|:---|:---|:---|
| **C1** | *"Cooperative + preemptive scheduler"* | `sched_tick()` (`kernel/sched/sched.c:142`) is an empty stub; multitasking is purely cooperative via `task_yield()` and GUI event loops. | Documented as overstated in architecture docs. Open: true preemption requires timer interrupt context switching. |
| **C2** | *"SMP-accelerated rendering"* | `bench3d` secondary cores executed `worker_math_stress` / `worker_mem_stress` (`kernel/bench/bench3d.c:27,43`), not the 3D rasterizer. | Flagged as overstated benchmark claim. Real multi-core rasterization was subsequently implemented via L1 Tiled NEON bands. |
| **C3** | *"Boot memory map discovery"* | `GetMemoryMap` was never called from `boot/main.c`; only invoked within vendored `gnu-efi` stdlib. | Flagged as inaccurate; physical memory layout is hardcoded to QEMU virt flat space. |
| **C4** | *"`jit <expr>` is a shell command"* | `jit` was never a registered shell command; bare expressions evaluate on the catch-all fallthrough path in `gui/shell.c`. | Flagged and documented. JIT parser evaluation verified via bare expression inputs. |
| **C5** | *"`edit <file>`, `filer` exist as shell commands"* | Absent from shell verb dispatch table; lines fell through to JIT parser printing `--> 0` ("parser made no progress"). | Confirmed pre-existing shell mismatch. Documented in `AGENTS.md`. |
| **C6** | *"`bench3d stop` stops the 3D demo"* | Absent from shell dispatch table; the real stop command is `close3d`. | Documented and corrected in shell command guides. |
| **C7** | *"Per-pixel Z-buffer everywhere"* | Only `mesh3d_render_solid_zbuffered` used a per-pixel Z-buffer; shaded cube paths used painter's algorithm sorting (`kernel/math/math3d.c:364,490,642`). | Flagged. True per-pixel 16-bit Z-buffering consolidated in `holygl.c` and `raster_tile.c`. |
| **C8** | *"3.14 MB Zero-RAM buffer size"* | Hardcoded string in README. `gfx_init` prints *"1024 x 768, 3 MB buffer"*; $1024 \times 768 \times 4 = 3,145,728$ bytes (3.0 MiB). | Corrected mathematical rounding discrepancy across documentation. |
| **C9** | *README screenshots valid* | Six `screenshots/*.png` markdown embeds 404'd because images were committed at repository root instead of `screenshots/`. | **Fixed**: Restored all screenshots into `screenshots/` and `docs/images/`. |
| **C10** | *"Validated on Real Hardware"* | All benchmark results and telemetry were produced under QEMU AArch64 TCG emulation. | Corrected in all architectural manifestos. |
| **C11** | *"No gambiarras (hacks)"* | Contradicted by hardcoded QEMU virt MMIO addresses and autorun boot toggles. | Formally documented as QEMU virt-specific bring-up. |
| **C12** | *JIT pipeline diagram with `mprotect`* | Diagram depicted page protection calls (`mprotect`, W^X permissions) that do not exist in Ring 0 flat address space. | Diagram updated to reflect flat identity-mapped cache flushes (`dc civac` / `ic ivau`). |
| **C13** | *"`make run-headless` works out of the box"* | `run-headless` was declared `.PHONY` with no recipe (a silent no-op); `make run` hardcoded `-display gtk`. | **Fixed**: Parameterized Makefile with `NEO_DISPLAY` defaulting to `none`. |
| **C14** | *README QEMU flags match build* | README documented `-cpu cortex-a57` while Makefile configured `-cpu cortex-a72`. | Synchronized QEMU flags across Makefile and test runners. |
| **C15** | *`redsea.img` documented* | Storage disk image generation was entirely omitted from README build instructions. | Documented `scripts/mkredsea.py` and `build/redsea.img` generation. |
| **C16** | *Git clone URL* | README clone URL pointed to an external repository. | Corrected to `https://github.com/Satanacio666/neo-os.git`. |
| **C17** | *Outdated audit documentation* | `docs/audit.md` claimed Lua 5.4 was absent; `docs/dossier.md` claimed arrays, floats, and VirtIO-GPU were unimplemented. | **Fixed**: Appended dated correction notices across all legacy audit files. |

---

## 2. Dead / Unreachable Code (D1–D10)

| ID | Finding | Technical Root Cause | Resolution |
|:---|:---|:---|:---|
| **D1** | `apps/*.HC` unreferenced by Makefile | Six HolyC application files existed in `apps/` but Makefile never compiled or packaged them into the EFI boot image. | **Fixed**: Integrated `scripts/mkredsea.py` to package all `apps/*.HC` into `build/redsea.img`. |
| **D2** | Duplicated `.HC` source strings in kernel | Code executed by the shell during early boot was hardcoded as C string literals in `fs/redsea.c`; editing `apps/*.HC` had zero effect. | Decoupled hardcoded literals; shell now reads dynamically from mounted RedSea filesystem blocks. |
| **D3** | 117 MB third-party survey trees | Unused third-party repositories committed under `tools/mc-survey/` (1,434 files). | Added `tools/mc-survey/` to `.gitignore`. |
| **D4** | Unreferenced reference sources | Reference C files in `tools/` unreferenced by build rules. | Kept as offline reference or excluded from build. |
| **D5** | Committed build artifacts | `boot/uefi/*.o` and `libuefi.a` tracked in Git, creating noise on every local compilation. | Cleaned build tree and enforced `.gitignore` on build outputs. |
| **D6** | Stagnant `kernel/physics/` | 3D physics engine compiled but disconnected from interactive shell or window manager. | Documented as dormant subsystem available for HolyC linkage. |
| **D7** | Phantom `mprotect` code | Documented page-permission routines absent from tree. | Documented: flat SASOS identity-mapping renders page protection unnecessary. |
| **D8** | Hardcoded host script paths | 24 test scripts hardcoded `/home/carlos/.gemini/antigravity/scratch/neo-os` across 176 lines, breaking on any other host. | **Fixed**: Replaced all hardcoded paths with `NEO_ROOT = os.environ.get("NEO_OS_ROOT") or Path(__file__).resolve().parents[1]`. |
| **D9** | Hardcoded `-display gtk` in Python scripts | Prevented headless CI / container test execution. | **Fixed**: Added `NEO_DISPLAY = os.environ.get("NEO_DISPLAY", "none")` across all runner scripts. |
| **D10** | Committed Python byte-code | `__pycache__/*.pyc` files tracked in Git. | Removed byte-code and added `__pycache__/` and `*.pyc` to `.gitignore`. |

---

## 3. Integration Gaps (I1–I5)

| ID | Gap | Technical Root Cause | Concrete Fix |
|:---|:---|:---|:---|
| **I1** | Software-only mouse cursor | `mouse_poll()` was an empty stub; EFI pointer protocol was never bound. | **Fixed**: `mouse_init()` binds `EFI_SIMPLE_POINTER_PROTOCOL`, resets device, and `mouse_poll()` scales relative motion to framebuffer boundaries. |
| **I2** | Blind DolDoc terminal output | The DolDoc terminal rendered exclusively into the GOP framebuffer; command outputs could not be read or asserted via serial console. | **Fixed**: Updated `doldoc_putc()` (`gui/render.c`) to mirror every character to the PL011 UART register (`0x09000000`). |
| **I3** | Keyboard input swallowed by shell | Shell line editor intercepted all keystrokes during interactive application runs, corrupting the command line. | **Fixed**: `shell_poll()` yields keyboard focus to active window callback when an application is running. |
| **I4** | Split UART escape sequences (Latency bug) | At 115200 baud, bytes of `ESC [ R` or `ESC O R` arrive ~87 µs apart. The parser checked the FIFO immediately after ESC, treating arrows/function keys as bare ESC. | **Fixed**: Implemented `uart_rx_wait()` spinning with a bounded `cntvct_el0` deadline (~320 µs), properly decoding multi-byte escape sequences. |
| **I5** | Unreachable Function Keys (F3/F4/Tab) | Tab (0x09) was filtered as a control character; F3/F4 lacked scancode mappings. | **Fixed**: Added `KEY_F3`, `KEY_F4`, `KEY_TAB` codes and explicit decoding branches in `drivers/input/keyboard.c`. |

---

## 4. Real Code Defects & Root Causes (R1–R13)

| ID | Defect | Root Cause | Concrete Fix |
|:---|:---|:---|:---|
| **R1** | Memory-corrupting crash on header edits (`FAR_EL1 = 0x80000000`) | Makefile compilation rules lacked `-MMD -MP` and `-include $(ALL_OBJS:.o=.d)`. Editing a header struct left object files linked against stale memory offsets, producing synchronous data aborts. | **Fixed**: Added `-MMD -MP` and `-include $(ALL_OBJS:.o=.d)` to `.c` and `.S` Makefile rules. |
| **R2** | Rotating cube frozen on red face | `glRotatef` -> `mat4_rotate_*` -> `math3d_sin/cos` use integer degree lookup tables ($0^\circ–359^\circ$), but the cube script converted frame counts to radians (`* 0.0174532925`), rotating only 0° to 6°. | **Fixed**: Passed raw integer degree values cast to `(F64)deg`, restoring continuous 360° rotation across all 6 faces. |
| **R3** | Double-precision float corruption on rotation | `F64 * float-literal` routed through JIT double-precision path, but the C graphics engine consumes single-precision `float`. | **Fixed**: Passed integer rotation angles cast cleanly to `F64`. |
| **R4** | Z-buffer dimension mismatch | Z-buffer initialized to hardcoded $960 \times 500$ while window was $984 \times 540$ (client $980 \times 502$) and framebuffer $1024 \times 768$, leaving a $20 \times 2$ pixel unrasterized strip. | **Fixed**: Dynamically sized Z-buffer from window client width and height constants. |
| **R5** | Zero-RAM presentation tearing | Rendering directly into the live scanout buffer caused display to sample between framebuffer clear and polygon rasterization, causing visible flickering. | **Fixed**: Interactive applications force the RAM backbuffer (`gfx_get_backbuffer()`), blitting clean completed frames. |
| **R6** | UEFI console overwriting GUI | Early boot `printf` calls invoked `ST->ConOut->OutputString()`, drawing firmware text boxes over the graphical desktop. | **Fixed**: Added `gfx_is_active()` guard in `boot/uefi/stdio.c`. When active, firmware console output is suppressed and routed exclusively to UART. |
| **R7** | 500 cache flushes per frame | VirtIO-GPU driver executed `for (y = 0; y < h; y++) flush_cache_range(...)`, issuing 500 `dsb sy\nisb` memory barriers per frame (+350 ms latency). | **Fixed**: Consolidated into a single bulk cache flush across $[addr, addr+size]$ followed by one synchronization barrier. |
| **R8** | Normal lighting recalculation stall | Flat-shaded gear teeth share identical face normals across multiple quads. Transforming and dot-producting identical normals took 60% of frame time (+130 ms). | **Fixed**: Implemented normal vector caching in `kernel/math/holygl.c`. If normal matches previous, lighting calculation is bypassed, reusing 32-bit shaded color (render time cut from 245 ms to 115 ms). |
| **R9** | `vsnprintf` 64-bit register garbage | `vsnprintf` in `boot/uefi/stdio.c` read all integer arguments as `int64_t`. With bare `%d`, uninitialized upper 32-bit register contents were printed (e.g. `960x-9223372036854775308`). | **Fixed**: Added `is_long` flag tracking `l`/`ll`/`z` specifiers; narrowed bare `%d` to `int32_t`/`uint32_t`. |
| **R10** | DolDoc redundant text redraw | Window manager redrew all terminal text glyphs on every frame even when no text changed, stalling the 3D pipeline. | **Fixed**: Implemented `s_doc_dirty_mask` in `gui/render.c`. If mask is zero, text glyph rasterization is skipped entirely during animation. |
| **R11** | UART serial latency jitter | Emulated serial output on every frame stalled the CPU by up to 350 ms per frame (jitter of 359.9 ms). | **Fixed**: Restricted real-time UART logging to latency spikes ($>400$ ms); buffered metrics in memory rings (jitter dropped to 37.7 ms). |
| **R12** | SMP job dispatch race condition | `smp_dispatch` published function and argument pointers after setting `pending = 1`, and worker cores read them without acquire barriers. | **Fixed**: Inserted `dmb ish` (release) before setting `pending = 1`, and `dmb ish` (acquire) in worker cores before reading job parameters. |
| **R13** | `fast_sqrt` inline asm host build failure | `kernel/math/math3d.c` used raw AArch64 `fsqrt` inline assembly unconditionally, breaking host unit tests on x86_64. | **Fixed**: Guarded with `#if defined(__aarch64__)` and provided `__builtin_sqrtf` fallback for host compilation. |

---

## 5. HolyC JIT Compiler Defects & Limitations (J1–J8)

| ID | Defect / Limitation | Technical Root Cause | Resolution |
|:---|:---|:---|:---|
| **J1** | One-compile-per-boot limit | The top-level compilation path was designed to run once; global parser state was not re-initialized for subsequent scripts. Subsequent `run` commands silently no-oped. | **Diagnosed & Documented**: Identified as core bootstrap limitation. Scripts must execute in fresh boot or register callbacks into the persistent event loop. |
| **J2** | Infinite compilation hang on syntax error | When encountering an unexpected token, `parse_block` looped without consuming tokens, spinning 100% CPU in a non-preemptible kernel loop. | **Fixed**: Added compile loop guard: if a statement parser consumes zero tokens, it immediately raises a compile error instead of spinning. |
| **J3** | Long-running HolyC loops starve OS | No cooperative yield was emitted at loop back-edges, starving the window manager and shell. | **Fixed**: Code generator emits a cooperative yield call on loop back-edges. |
| **J4** | Unary minus on float literals | The compiler emitted `FNEG` on register `D0`, but floating-point values were stored as raw 64-bit integer bit-casts in `X0`. | **Fixed**: Aligned floating-point literal negation to manipulate the sign bit in the integer register representation. |
| **J5** | Missing array declaration support | Compiler parser lacked syntax rules for `Type name[count];`. Array indexing hung the parser. | **Fixed**: Added array declaration parsing, element width scaling, and array indexing lookahead in `compiler/jit_arm64.c`. |
| **J6** | AAPCS64 calling convention float mismatch | JIT passed all function arguments in integer registers `X0–X7`. C functions expecting floats in `S0–S7` / `D0–D7` read uninitialized garbage. | **Fixed**: Implemented automatic argument mirroring: for each argument emitted to `Xn`, the JIT also emits `fmov dn, xn`, guaranteeing floats arrive in both register banks. |
| **J7** | Struct member array indexing | The compiler failed to resolve member array offsets within structs (`obj.array[idx]`). | **Fixed**: Enhanced struct type reflection engine with member size and array indexing logic. |
| **J8** | Missing `load` command | `load` command was referenced in documentation but `load_live()` was absent from the codebase. | **Diagnosed & Documented**: Flagged as dead shell command. HolyC scripts are executed via `run <file.HC>`. |

---

## 6. Kernel Video & Compositor Defects (K1–K8)

| ID | Defect | Root Cause | Concrete Fix |
|:---|:---|:---|:---|
| **K1** | Double-buffering tear-free presentation | Zero-RAM mode rendered directly into the scanout buffer, creating tearing between clear and rasterization. | Implemented explicit RAM backbuffer toggle (`gfx_get_backbuffer()`) for animated 3D applications. |
| **K2** | Viewport coordinate inversion | HolyGL viewport transformations inverted the Y-axis winding order, causing backface culling to discard front-facing triangles. | Adjusted winding order sign in triangle setup to ensure clockwise/counter-clockwise consistency. |
| **K3** | Buffer size rounding contradictions | Inconsistent buffer size reporting across label, printout, and code. | Reconciled buffer size constants across `gui/render.c` and documentation. |
| **K4** | Missing cache maintenance on present | Hardware scanout requires cleaning CPU data cache to Point of Coherency (`dc civac`). While QEMU ramfb masks this, real hardware would show stale pixels. | Documented cache flush requirement for physical hardware porting. |
| **K5** | Padded pitch allocation waste | Framebuffer pitch calculations assumed power-of-two padding, allocating redundant memory. | Aligned pitch calculations strictly with GOP reported scanline stride. |
| **K6** | Row-by-row `gfx_swap_rect` overhead | Compositor copied modified rectangles row-by-row with individual function calls. | Consolidated contiguous row blits into bulk `memcpy` operations. |
| **K7** | Viewport pixel explosion | Enlarging viewport from $484 \times 442$ to $680 \times 560$ increased rasterized pixels by $1.78\times$ (+250 ms per frame under QEMU softMMU). | Standardized default benchmark viewports to 360p ($640 \times 360$) for optimal cache utilization. |
| **K8** | VSync spinloop CPU burn | `gfx_vsync_wait()` spun in a busy loop even when VSync was disabled, wasting CPU cycles. | **Fixed**: Added early return in `gfx_vsync_wait()` when `!s_vsync.enabled`, eliminating spin overhead. |

---

## 7. Wrong Premises in Plans (Retracted Design Decisions P1–P6)

| # | Retracted Premise | Why It Was Wrong | Concrete Correction | Cost if Uncaught |
|:---:|:---|:---|:---|:---|
| **P1** | *"Multi-threaded TCG (`-accel tcg,thread=multi -smp 4`) will yield 4x rendering speedup"* | On the dual-core host (Intel Celeron N4020, 2 cores @ 1.10 GHz), 7 host threads competed for 2 physical cores, causing severe context-switching thrashing (0.6–1.5 FPS). | Pivoted to deterministic single-core pinned execution (`taskset -c 0 -accel tcg,thread=single`), achieving **13.5 FPS** (Phase 8 winner). | Would have wasted engineering effort chasing multi-threaded locks on an oversubscribed host. |
| **P2** | *"Meshing is the largest per-frame bottleneck; we must multi-thread the mesher"* | Profiling log *"mesh=1290 ms"* represented a one-time world initialization on a 100 Hz timer. Per-frame time was 99.1% rasterization and lighting. | Retargeted optimization to rasterizer NEON tiling and normal vector caching. | Would have multi-threaded a subsystem that only runs once, leaving per-frame rendering unoptimized. |
| **P3** | *"Benchmark phases should advance after N rendered frames"* | Counting 40 frames at 1.5 s/frame caused each benchmark phase to take 60 seconds (freezing the test suite for 6 minutes). | Replaced frame counting with hardware timer `cntvct_el0` elapsed time (3.0 seconds wall-clock per phase). | Automated test runs would have timed out or stalled continuously. |
| **P4** | *"Window animation freeze after close is caused by stale `custom_render` pointers"* | Investigation showed `wm_create_window` already set `custom_render = NULL`. The real freeze was caused by J1 (JIT one-compile-per-boot). | Corrected root-cause attribution to J1 compiler state. | Would have introduced unnecessary window manager complexity without fixing the compiler freeze. |
| **P5** | *"`math3d_sin` and `math3d_cos` expect angles in radians"* | Trigonometric functions in `math3d.c` use 360-entry integer degree lookup tables ($0^\circ–359^\circ$), not radians. Converting to radians froze rotations. | Passed raw integer degrees cast to `(F64)deg`. | 3D rotations would have remained frozen on a single face. |
| **P6** | *"Zero-RAM direct scanout is always superior to double-buffering"* | While Zero-RAM has 0.0 ms blit time, rendering multi-pass scenes directly into VRAM causes visual tearing between clear and draw passes. | Maintained both paths: Zero-RAM for maximum raw throughput benchmarks; RAM backbuffer for tear-free interactive applications. | Interactive applications would have suffered from visible scanline tearing. |

---

## 8. Environment & Infrastructure Failures (E1–E6)

| # | Failure Symptom | Technical Root Cause | Resolution |
|:---:|:---|:---|:---|
| **E1** | Build and execution failed after container reset | Ephemeral container root filesystem wiped installed packages; `/usr/share/qemu-efi-aarch64/QEMU_EFI.fd` and `aarch64-linux-gnu-gcc` were missing. | Reinstalled `qemu-system-arm`, `aarch64-linux-gnu-gcc`, and restored `QEMU_EFI.fd`. |
| **E2** | `mkfs.vfat` / `mcopy` command not found | Disk formatting utilities (`dosfstools`, `mtools`) missing from host environment. | Reinstalled `dosfstools` and `mtools`. |
| **E3** | Live web console `/stream` returned 0 bytes | System Python lacked `Pillow`, causing the console's screendump-to-JPEG conversion to return `None` silently. | **Fixed**: Installed Pillow 12.3.0. |
| **E4** | *"Failed to get write lock"* on `disk.img` | Second QEMU instance attempted to open disk image already locked read-write by running console. | **Worked around**: Cloned disk image for debug sessions or shut down active console before testing. |
| **E5** | QMP debugging impossible while console runs | QMP UNIX socket accepts only a single client connection, held exclusively by the web console. | Managed QMP socket lifecycle; added dedicated debug socket configuration. |
| **E6** | QMP test scripts crashed with `OSError: [Errno 22]` | Test scripts called `s.recv(1024)` before draining the QMP greeting JSON. | **Fixed**: Updated test harness to drain the QMP greeting banner before issuing monitor commands. |

---

## 9. Still Open: The Unfixed Defect Register

The following items are deliberately recorded as **open / not fixed**, with the architectural reason for each:

1. **Preemptive Task Switching (C1)**: `sched_tick()` remains an empty stub. Multitasking is cooperative via `task_yield()`. Implementing true preemption requires saving all 31 registers and SIMD state in the timer interrupt vector (`vectors.S`).
2. **UEFI `GetMemoryMap` Integration (C3)**: Physical RAM layout is hardcoded to QEMU virt flat space; full dynamic UEFI memory map parsing is not integrated into `boot/main.c`.
3. **Phantom Shell Commands (C5, C6, J8)**: `edit`, `filer`, `load`, and `bench3d stop` remain absent from the shell command table; they fall through to the JIT catch-all.
4. **JIT One-Compile-Per-Boot Limitation (J1)**: Running multiple top-level scripts sequentially requires a reboot because parser symbol state is not reset between runs.
5. **JIT `printf` Routing Discrepancy (J6/J8)**: `printf` output from JIT scripts routes to the DolDoc GUI terminal, with only specific lines mirrored to the UART serial port.
6. **Hardcoded QEMU `virt` MMIO Addresses**: Hardware addresses (UART `0x09000000`, GIC `0x08000000`, VirtIO `0x0A000000`) are compile-time constants, preventing bare-metal boot without source modification.
7. **Tracked Binary Artifacts in Git (D5)**: `boot/uefi/*.o` and `libuefi.a` are tracked in version control, producing churn across builds.
8. **Lack of Automated CI Workflow (D6)**: No `.github/workflows/` exists; verification relies on local test runners.

---

## 10. One-Line Summary of Every Applied Fix

1. **Makefile `-MMD -MP`**: Fixed memory-corrupting data aborts caused by stale struct layouts after header edits (**R1**).
2. **Degree-based `glRotatef`**: Restored 360° continuous rotation across all cube faces by passing integer degrees (**R2**).
3. **AAPCS64 `fmov dn, xn` Mirroring**: Eliminated float garbage in C graphics functions by mirroring arguments into SIMD registers (**J6**).
4. **JIT Zero-Progress Compile Guard**: Prevented infinite parser hangs by treating zero-token statements as compile errors (**J2**).
5. **JIT Cooperative Yield Emission**: Prevented long-running HolyC loops from starving the window manager (**J3**).
6. **JIT Array Declaration & Indexing**: Added parser support for `Type name[count]` and element width indexing (**J5**).
7. **JIT Struct Type Reflection**: Enabled member array indexing and nested struct dereferencing (**J7**).
8. **HolyGL Normal Vector Caching**: Cut 3D render time from 245 ms to 115 ms by caching lighting on identical normals (**R8**).
9. **VirtIO-GPU Bulk Cache Invalidation**: Eliminated 500 per-frame pipeline stalls by replacing row flushes with a single bulk barrier (**R7**).
10. **`gfx_is_active()` Console Suppression**: Prevented UEFI firmware text boxes from defacing the GUI desktop (**R6**).
11. **DolDoc Text Redraw Dirty Mask**: Skipped redundant text glyph rendering during 3D animation passes (**R10**).
12. **UART Logging Throttling**: Reduced telemetry jitter from 359.9 ms to 37.7 ms by restricting UART output to latency spikes (**R11**).
13. **UART Bounded Escape Wait (`uart_rx_wait`)**: Fixed split escape sequences, enabling reliable arrow and function key input (**I4**).
14. **EFI Simple Pointer Binding**: Connected physical/emulated mouse hardware to the window manager cursor (**I1**).
15. **DolDoc UART Mirroring**: Allowed all shell output to be captured and asserted over the serial console (**I2**).
16. **Dynamic Z-Buffer Sizing**: Eliminated unrasterized pixel strips by deriving Z-buffer dimensions from window bounds (**R4**).
17. **SMP Memory Barriers (`dmb ish`)**: Fixed race conditions during multi-core job dispatch (**R12**).
18. **`fast_sqrt` AArch64 Guard**: Enabled math unit tests to compile and run on x86_64 host machines (**R13**).
19. **`vsnprintf` Integer Width Narrowing**: Fixed 64-bit register garbage in formatted integer printouts (**R9**).
20. **VSync Spinloop Elimination**: Eliminated 100% CPU burn when running with uncapped frame rates (**K8**).
21. **Single-Core Sovereign Pinning (`taskset -c 0`)**: Overcame host dual-core contention, boosting frame rate from 1.5 to 13.5 FPS (**P1**).
22. **Hardware Timer Suite Advancing**: Replaced frame-count benchmark advancement with wall-clock timer checks (**P3**).
23. **Host Script Portability (`NEO_ROOT`)**: Replaced 176 hardcoded paths across 24 scripts with dynamic root resolution (**D8**).
24. **Headless Display Configuration (`NEO_DISPLAY`)**: Enabled test suites to run in headless environments (**D9**).
25. **Pillow Installation**: Restored live web console video stream rendering (**E3**).
26. **QMP Greeting Drain**: Fixed socket handshake crashes across test automation scripts (**E6**).
27. **README Screenshot Path Restoration**: Restored broken image embeds across project documentation (**C9**).
28. **RedSea Application Packaging**: Automated packaging of HolyC applications into the data disk image (**D1**).
