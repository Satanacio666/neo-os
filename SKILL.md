---
name: neo-os-directives
description: >-
  Complete, chronological, and ironclad engineering directives for NeoOS (Prompts #1-#301).
  Enforces zero shortcuts, zero stubs, zero hardcoded themes/grids/windows, full Pure HolyC
  sovereignty, unified DolDoc/WM/Compositor/Shell scene-graph continuum, KolibriOS speed
  optimizations, native Shadertoy in DolDoc, and full Stage-2 self-hosting Compiler.HC.
  Activate on every architectural, coding, or verification task in NeoOS.
---

# NeoOS Master Sovereign Directives & Explicit Execution Order

> [!CRITICAL]
> **IRONCLAD MANDATE**: This skill codifies every explicit order, architectural law, and verification standard issued by the user across the entire history of NeoOS (Prompts #1–#301). Never bypass, stub, fake, or water down any item in this specification.

---

## PART I: Explicit Ordered Mandates (Nothing Left Behind)

### Order 1: Bare-Metal AArch64 Ring-0 (EL1) Single Address Space Sovereignty
1. Everything runs in **ARMv8-A EL1 (Ring 0)** inside a **1:1 flat physical identity-mapped address space (`VA == PA`)**.
2. Zero Ring-3 isolation, zero `SVC` syscall overhead, zero address-space context-switch TLB flushes.
3. Direct pointer access to MMIO, VRAM, virtqueues, and executable JIT code pools from any `.HC` module.

### Order 2: 100% Pure `.HC` Sovereignty & Zero C Expansion
1. **No new `.c` files may ever be created.** Only the minimal UEFI hardware bootstrap (`boot/main.c`) may exist in C until retired by self-hosted boot.
2. **Zero Stubs, Zero Placeholders, Zero Mock Data**: Every function in every `.HC` file must implement the real, complete algorithm. Never write `return 0;` stubs, fake static strings, or fake benchmark ratings.
3. **Zero Trivial Wrapper Files**: Eliminate redundant 1-line `.HC` wrapper files (`Bench.HC`, `HolyBenchmark3D.HC`, `GpuConfig.HC`, `Top.HC`, `Gears.HC`, `HolyGLTest.HC`, `calc.HC`, `fact.HC`) by consolidating them into their canonical subsystems and registering aliases in the command/symbol table.
4. **Zero Forward Declarations**: Order functions in strict topological dependency order or dispatch via the Symbol Indirect Cell (SIC) table.

### Order 3: Real Hardware Portability via `HalPlatform.HC`
1. Never hardcode QEMU `virt` MMIO addresses (`0x08000000`, `0x09000000`, `0x0A000000`) or timer frequencies (`62500000`) inside drivers (`Gic.HC`, `Timer.HC`, `VirtioBlk.HC`, `VirtioGpu.HC`, `VirtioInput.HC`, `Keyboard.HC`).
2. All drivers must query `g_current_platform` / `g_hal_*` in `HalPlatform.HC` (supporting QEMU `virt`, Raspberry Pi 4/5, Rockchip RK3226/RK3399, and Snapdragon 860 / Poco X3 Pro).
3. `HalFlushCache(addr, size)` **must** perform both data-cache clean (`__dc_civac`) AND instruction-cache invalidation (`__ic_ivau`) followed by `dsb sy; isb`.

### Order 4: Sovereign Physical Heap Allocator (`KHeap.HC`)
1. `KHeap.HC` must manage the **entire multi-megabyte physical kernel heap** directly (not a 64 KB toy sub-pool allocated inside C `kmalloc`).
2. Protect `KMalloc` and `KFree` with hardware atomic spinlocks (`smp_spin_lock` / `smp_spin_unlock`) for SMP safety.
3. Accurately maintain `used_memory`, `free_memory`, `allocation_count`, `free_count`, and `peak_used`, and bind `kmalloc`/`kfree` in the global symbol table directly to `KMalloc`/`KFree`.

### Order 5: Unified Symbol Indirect Cell (SIC) & Container Library (`Symbols.HC`, `Table.HC`, `StdLib.HC`)
1. Eliminate the 3-way duplicated DJB2 hash tables across `Symbols.HC`, `Table.HC`, and `StdLib.HC`.
2. `Symbols.HC` must own the live Ring-0 symbol table (`symbols_lookup`, `symbols_register`, `SymLookup`, `SymRegister`) with canonical case-folding (`snake_case` $\leftrightarrow$ `CamelCase`) and O(1) hot-patching—never wiping live kernel symbols during self-tests.
3. `StdLib.HC` must provide leak-free dynamic `CArray` and `CDict` containers (including `DictFree`, key string duplication, and null-check guards) available to all subsystems from Stage 1 of boot.

### Order 6: Complete, Uncompromised Lexical Analyzer (`Lexer.HC`)
1. Unify token IDs (`TOK_*`) across `Lexer.HC` and `Compiler.HC` so there is only **one** tokenizer in the OS.
2. Implement full IEEE-754 floating-point literal lexing (`TOK_FLOAT`, e.g., `3.14159`, `1e-6`).
3. Support both `//` single-line comments and `/* ... */` multi-line block comments.
4. Implement an active `#define` macro expansion table and `#include` file splicing (never blindly skip `#define` lines as comments).
5. Store string literals in a dynamic string arena rather than truncating strings at 63 characters (`str_value[64]`).

### Order 7: Production Stage-2 Self-Hosting Compiler (`Compiler.HC`)
1. Allocate emitted machine code into the persistent executable JIT pool (`EfiLoaderCode`) with monotonic offset advancing (never overwrite index 0 of `g_hc_code` and corrupt previously registered functions).
2. Fix `HcParseLogOr` backpatching so `CBNZ` (`0xB5000000`) is never overwritten with `CBZ` (`0xB4000000`).
3. Dynamically compute function prologue/epilogue stack frame sizes (`stp x29, x30, [sp, #-frame_sz]!`) instead of hardcoding a 256-byte (15-local) limit.
4. Implement complete HolyC language parity:
   - `class` and `struct` declarations, `sizeof()`, member offset tables, and `.` / `->` member access (including chained `a->b.c`).
   - Width-aware memory loads and stores (`U8` $\rightarrow$ `LDRB`/`STRB`, `U16` $\rightarrow$ `LDRH`/`STRH`, `U32` $\rightarrow$ `LDR W`/`STR W`, `I64`/`U64` $\rightarrow$ `LDR X`/`STR X`) and typed pointer arithmetic.
   - Multi-dimensional arrays (`arr[i][j]`) and global variable declarations in Ring 0.
   - Full control flow: `for (init; cond; step)`, `while`, `do-while`, `switch`/`case`/`default`, `break`, `continue`.
   - IEEE-754 `F64` floating-point expressions emitting native AArch64 scalar FP instructions (`FADDD`, `FSUBD`, `FMULD`, `FDIVD`, `FCMPD`, `SCVTF`, `FCVTZS`, and 1-cycle hardware `FSQRT Dd, Dn` `0x1E61C000`).
   - AArch64 NEON 4-lane (`V0.4S`–`V31.4S`) vector intrinsics (`DUP.4S`, `FADD.4S`, `FMUL.4S`, `FMLA.4S`, `FRSQRTE.4S`) for shaders and 3D math.
   - Linear-scan register allocation across `X19`–`X28` / `D8`–`D15` to eliminate naive per-operator stack push/pop traffic.

### Order 8: Non-Fatal Ring-0 Fault Recovery & Royal Blue BSOD (`Exceptions.HC`)
1. Fix `ExceptionsHandleSync` to call `ExceptionsDecodeClass(ec)` (not undefined `ExceptionsGetEcDesc`).
2. Replace `if (g_exc.total_exceptions > 1) while(1){}` with a proper re-entrancy depth counter (`g_exc.in_fault`) that resets on recovery so multiple independent user faults can be recovered across a session without hanging the OS.
3. Validate `f->elr_el1` before dereferencing `*insn_ptr` (especially on `EC_INSN_ABORT`).
4. If a fault occurs inside a user JIT command/app (`is_user_jit`), display a structured DolDoc crash card (`ESR_EL1`, `FAR_EL1`, `ELR_EL1`, decoded syndrome, register dump) and unwind cleanly to `ShellRecover()`. If an unrecoverable kernel fault occurs, render a full-screen diagnostic **Royal Blue BSOD**.

### Order 9: Real Interrupts, Hardware Generic Timer & Context-Switching Scheduler (`Gic.HC`, `Timer.HC`, `Sched.HC`)
1. **`Gic.HC`**: Remove the catastrophic `if (irq < 32) GicDisableIrq(irq);` bug in `GicHardwareIrqHandler` so periodic PPIs (such as Timer IRQ 27) continue firing; use `__mmio_r32`/`__mmio_w32` and `HalPlatform.HC` bases.
2. **`Timer.HC`**: Actually program hardware `CNTP_TVAL_EL0` and `CNTP_CTL_EL0` registers in `TimerInit` and `TimerTick`; remove the hardcoded `62500000` Hz assumption in `TimerSelfTest()`; prevent `(cnt * 1000000)` 64-bit overflow via `cnt / (frq / 1000000)`.
3. **`Sched.HC`**: Implement real AArch64 context switching in `TaskCreate` and `TaskYield` (initializing and swapping callee-saved registers `X19`–`X30`, `SP`, and `D8`–`D15` via `__cpu_switch_to`), define `TASK_BLOCKED`, and defer stack deallocation in `TaskExit` via `g_sched_zombie`.

### Order 10: Real Tickless Multi-Core SMP (`Smp.HC`, `SmpDemo.HC`)
1. Boot secondary cores 1–3 via PSCI `CPU_ON` (`0xC4000003`) into `smp_secondary_entry` -> `SmpSecondaryWorker`.
2. Secondary workers must sleep in hardware **`WFE` (Wait For Event)** consuming **0% host CPU** when idle, woken by **`SEV` (Send Event)** with `dmb ish` acquire/release barriers.
3. **Remove the fake synchronous Core-0 execution hack** in `SmpDispatch()` (`L120–130`), remove the magic `0x75001111` test address hack, and remove all fake heartbeats (`100 + i*25`) and synthetic load formulas.

### Order 11: Unified VirtIO Transport & Non-Corrupting RedSea FS (`Virtio*.HC`, `RedSea.HC`, `Keyboard.HC`, `Mouse.HC`)
1. **Unified VirtIO MMIO Transport**: Write full 64-bit physical addresses (`addr & 0xFFFFFFFF` and `addr >> 32`) to `QUEUE_DESC/AVAIL/USED_LOW/HIGH`, cast `cap_high` to `U64` before `<< 32`, and guard `Init` routines against leaking memory on re-init.
2. **`VirtioGpu.HC`**: Query native display resolution dynamically via `VIRTIO_GPU_CMD_GET_DISPLAY_INFO` and check `resp->type == VIRTIO_GPU_RESP_OK_NODATA`.
3. **`VirtioInput.HC` & `Mouse.HC` & `Keyboard.HC`**:
   - Treat `CVirtioInputEvent.value` as signed `I32` for `EV_REL` so moving the mouse left/up does not wrap by `+4294967295`!
   - Fix typed pointer scaling (`&dev->vq_desc[i]` and `&dev->event_buf[desc_id]` instead of `+ i * 16` / `+ desc_id * 8`).
   - `KeyboardPoll()` must poll **both** PL011 UART (with multi-byte ANSI escape wait window for arrows, `PageUp`/`PageDown`, `F1`–`F12`) **and** `VirtioInputPoll()`.
   - `Mouse.HC` must query dynamic canvas dimensions (`gfx_get_canvas_width`/`height`), deduplicate front/back cursor save-under drawing, and export `mouse_get_buttons()`.
4. **`RedSea.HC` & `Filer.HC`**:
   - On mount (`RedSeaMountHardware`), scan the directory tree to compute `g_rs.next_alloc_lba = max(cluster + sectors)` dynamically (never hardcode `1024`!).
   - In `RedSeaWriteFile`, if an overwritten file grows beyond its old sector count (`need_sec > old_sec`), allocate a new contiguous cluster range at `next_alloc_lba` instead of overwriting adjacent files in place!
   - Fix `cd ..` path parent popping in `RedSeaChangeDir` and stamp real uptime/RTC timestamps.

### Order 12: High-Resolution Canvas, Zero-RAM Scanout & VSync (`Render.HC`, `GfxBackend.HC`)
1. Support arbitrary high resolutions (`1024x768`, `1280x720`, `1920x1080`, etc.) dynamically without hardcoded `1024` pitch or dimensions.
2. Fix the pointer scaling bug in `gfx_swap_rect` (`(U8*)g_canv.front_buffer + (y * g_canv.pitch + rx) * 4` or `U32*` indexed without `* 4`).
3. Wire `GfxBackend.HC` **Zero-RAM Direct Scanout** (`GFX_BUFFER_DIRECT_VRAM`) directly into `Render.HC` so drawing operations target `front_buffer` with 0 ms blit overhead when enabled.
4. Implement real `CNTVCT_EL0` frame-pacing in `gfx_vsync_set(en, hz)` and `gfx_vsync_wait()`.
5. Implement Cohen-Sutherland viewport line clipping in `RenderDrawLine` and ensure all drawing primitives expand the dirty rectangle.

### Order 13: Dynamic Semantic Theme & KolibriOS Skin Engine (`CThemePalette`)
1. **Zero Raw Hex Color Macros in Apps**: Delete duplicated `#define COLOR_*` and `#define CAT_*` blocks from `DolDoc.HC`, `Compositor.HC`, `WM.HC`, and `Showcase.HC`.
2. Centralize all styling in a live **`CThemePalette`** table combining 16 semantic color tokens (`bg_base`, `bg_surface`, `bg_elevated`, `border_subtle`, `border_active`, `text_primary`, `text_secondary`, `text_muted`, `accent_primary`, `accent_secondary`, `danger`, `warning`, `success`, `info`, `glass_tint`, `shadow_color`) with KolibriOS `SKIN_PARAMS` metrics (`titlebar_h`, `border_w`, `corner_radius`, button relative offsets).
3. Include 6 built-in runtime-switchable themes: **Catppuccin Mocha**, **Catppuccin Latte**, **Tokyo Night**, **Nord**, **TempleOS Divine CGA**, and **Cyberpunk OLED** (`theme <name>` command and UI selector).

### Order 14: Complete Scalable Bézier & TrueType Typography (`FontVector.HC` + `FontMono.HC`)
1. Merge `FontVector.HC` and `FontMono.HC` into a single sovereign typography subsystem.
2. Replace the 10-letter stub in `FontVector.HC` with a complete **95-glyph printable ASCII (`32`–`126`) analytical stroke + quadratic Bézier vector font table**, plus TrueType `cmap`/`loca`/`glyf` contour parsing into `g_font_atlas`.
3. Support multiple font families (`FONT_MONO`, `FONT_VECTOR_SANS`, `FONT_MATH_SERIF`), arbitrary pixel/point sizes (`$FONT,size=12..72$`), subpixel anti-aliased rendering, and accurate `FontMeasureString` / `FontMeasureWrappedHeight` metrics.

### Order 15: Abolish the `128x48` Terminal Grid — True Post-DOM `CDocNode` + OmniTape + Morton Continuum (`DolDoc.HC`)
1. **Demolish `g_doc_chars[6144]`**: Completely remove the `128x48` character array, `col * 8 / row * 18` grid snapping, and write-only `g_hist_chars`.
2. Represent every document as a live doubly-linked scene graph of **`CDocNode`** elements compiled into the 64-byte-aligned **`OmniTape`** command stream (`g_omnitape_buf`) and indexed by dynamic **`Morton2D`** $64\times 64$ spatial tile bins (sized dynamically from `g_canv.width / 64` and `g_canv.height / 64`).
3. **`DolDocRedraw()` Must Render From the Scene Graph / OmniTape**:
   - Support fluid word-wrapping on viewport resize, nested Flexbox containers (`$ROW$`, `$COL$`, `$CARD$`, `$BOX$`), smooth pixel-granular scrolling (`scroll_y`) with an interactive draggable scrollbar (`CBoxScrollbar`), and localized dirty-tile redraws.
4. **Real Living Widgets (Zero Cosmetic Mockups)**:
   - `$BT$` (3D/vector elevated button), `$LK$` (executable plumb link), `$CB$` (live boolean toggle), `$PB$` (live progress bar).
   - `$SL$` (reactive slider bound via `target_ptr` to live `I64*` or `F64*` variables with `MOVZ` JIT immediate patching and live numeric tooltip).
   - `$EQ$` (recursive mathematical equation layout supporting nested fractions $\frac{A}{B}$, dynamic-height square roots $\sqrt{X}$, superscripts/subscripts, $\sum$, and $\int$).
   - `$GRAPH$` (live Catmull-Rom / anti-aliased oscilloscope plotting real ring-buffer telemetry arrays, not a static sawtooth wave!).
   - `$SP$` (live rotating, shaded 3D `CSprite` mesh embedded inline in the document stream, not 12 static isometric lines!).
   - **Smalltalk Morphic Halos (`Alt+Click`)**: Alt-clicking any node spawns a live inspector overlay showing its memory address, bounding box, theme token, and bound HolyC variable.

### Order 16: Dissolve the Separation of `WM.HC`, `Compositor.HC`, `Shell.HC`, and `DolDoc.HC`
1. **One Unified Spatial Scene Graph (`g_root_doc`)**:
   - There are no separate modal loops (`WMEventLoop` vs `DolDocShellEventLoop`). The entire OS runs one unified event and composition loop over `g_root_doc`.
   - Fullscreen Shell mode is simply the Console `$WIN$` node maximized (`NODE_FLAG_MAXIMIZED`) with the taskbar auto-hidden or docked; Desktop mode restores floating/tiled windows effortlessly without losing state or clearing the document!
2. **Arbitrary $N$-Window Management (`DOC_NODE_WINDOW` / `$WIN$`)**:
   - Abolish static `g_main_win` and `g_tool_win`. Any app or command can call `DocCreateWindow(title, x, y, w, h)` to spawn a new dynamic window node.
   - Window chrome (titlebar, title text, `[−][+][×]` buttons, resize grip) is built out of child DolDoc nodes (`DOC_NODE_ROW` + `DOC_NODE_BUTTON`) styled by `CThemePalette`.
   - Use a KolibriOS-inspired **Hierarchical Screen Ownership Map (`g_win_tile_map`)** + hardware scissor clipping (`gfx_set_clip`) + per-window damage rectangles so ticking the taskbar clock or animating one window only redraws the affected tiles!
3. **The Shell IS a `$REPL$` Document Node (`DOC_NODE_REPL`)**:
   - Abolish the 270-line `if (strcmp(cmd, ...))` ladder in `Shell.HC` (and fix the missing `}` in `ShellAutocomplete`!).
   - Implement a dynamic command registry (`shell_register_cmd(name, fn, help)`) populated by each subsystem, with fallback to direct Ring-0 HolyC JIT evaluation (`CompilerCompileAndRun` / `jit_eval`).
   - Any window or document can host an active `$REPL$` node (`CBoxEdit` input); command outputs and live widgets insert directly into the document tree above the prompt.

### Order 17: Native Real-Time Shadertoy Engine Inside DolDoc (`$SHADER$` & `ShaderEditor.HC`)
1. Implement `DOC_NODE_SHADER` (`$SHADER,w=...,h=...,fn="..."$`) as a first-class animated node in `DolDoc.HC`.
2. Evaluate shaders in $4\times 1$ horizontal SIMD quads inside the L1 tile scratchpad (`RenderShaderNode`) passing `CShaderUniforms` (`iTime`, `iTimeDelta`, `iFrame`, `iResolutionX/Y`, `iInvResX/Y`, `iMouseX/Y`, `bound_cell`).
3. Provide a built-in library of fast branchless shader math in `Math3D.HC` / `ShaderEditor.HC`: `FastSinRad`, `FastCosRad`, `ShaderFract`, `ShaderMix`, `ShaderSmoothstep`, `SdfSphere`, `SdfBox2D`, `SdfTorus`, and at least 3 built-in procedural shaders (**Cyber Plasma**, **Raymarched SDF Morphing Torus**, and **Acrylic Glass Wave**).
4. Upgrade `ShaderEditor.HC` from a 48-line static text stub into a **live split-pane DolDoc Shadertoy IDE**: editable HolyC shader source code (`CBoxEdit`) on the left, `[Compile & Run JIT]` button + live `$SL$` parameter sliders in the middle, and a real-time 60 FPS `$SHADER$` viewport + FPS telemetry counter on the right!

### Order 18: Unified 3D Graphics, Physics & Symmetrical 40-Phase Benchmark (`Math3D.HC`, `RasterTile.HC`, `HolyGL.HC`, `Gears3D.HC`, `Physics3D.HC`, `HolyBenchmark.HC`, `PerfOverlay.HC`, `Profiler.HC`)
1. **`Math3D.HC` & `GrMath.HC`**: Delete dead duplicate `GrMath.HC`; emit 1-cycle hardware `FSQRT` in `MathSqrt`; fix `MathSin` range reduction to $O(1)$ modular math; fix `Mat4MulVec4` aliasing.
2. **`RasterTile.HC` & `HolyGL.HC`**: Implement real 16-bit Z-buffer depth testing (`TILE_DEPTH_BYTES`) and incremental Pineda edge stepping in `RasterTile.HC`; wire `HolyGLSubmitTriangle` into `RasterTile.HC` with near-plane clipping and all 8 `GL_*` primitive modes; remove the 7.2x fake FPS multiplier in `HolyGLMain`.
3. **`Gears3D.HC` & `Gears.HC`**: Add `Gears3DRender()` to actually render `g_red_gear`, `g_green_gear`, and `g_blue_gear` with Lambertian lighting; merge `Gears.HC`.
4. **`Physics3D.HC`**: Refactor `CRigidBody` to use `CVec3`, honor `g_phys_gravity`, and add `Physics3DRender()` to render the 3D rigid-body arena.
5. **`PerfOverlay.HC` & `Profiler.HC` & `HolyBenchmark.HC`**:
   - Unify `PerfOverlay.HC` and `Profiler.HC` so frame times, 1%/0.1% lows, and spike forensics are computed once and rendered completely inside the RivaTuner HUD (`PerfOverlayDraw`).
   - Upgrade `HolyBenchmark.HC` to execute all **5 real visual engines** (1: GLXGears 3D, 2: Dual Cubes SMP, 3: 3D Rigid-Body Physics, 4: Lit UV Sphere, 5: Tile Fillrate & Shaders) across all **8 rendering/hardware variations** (40 phases total) and write complete telemetry logs to `/BENCH_COMPARISON.TXT`, `/BENCH_PROFILER.LOG`, and `/BENCH_SPIKES.LOG`.

### Order 19: The Flagship Master Showcase Document (`Showcase.HC`)
1. `Showcase.HC` must be a single, breathtaking, high-resolution interactive document that simultaneously demonstrates **every capability of NeoOS on one scrollable/windowed canvas**:
   - **Typography & Themes**: Multiple font families (`FONT_VECTOR_SANS`, `FONT_MONO`, `FONT_MATH_SERIF`), multiple sizes (`12pt`, `18pt`, `28pt`, `42pt`), and instant 1-click theme switching buttons (`Mocha`, `Latte`, `Nord`, `Tokyo Night`, `TempleOS CGA`, `Cyberpunk OLED`).
   - **Native Shadertoy Viewport (`$SHADER$`)**: Live animated procedural fragment shader running inline with interactive `$SL$` sliders mutating shader uniforms in real time.
   - **3D `CSprite` & `HolyGL` Viewports (`$SP$`)**: Live rotating, Z-buffered, Lambertian-lit 3D involute gears and polyhedral meshes embedded directly in the text flow.
   - **Mathematical Typography (`$EQ$`)**: Multi-level nested equations (General Relativity / Navier-Stokes / Quadratic & Integral formulas with dynamic radical and summation symbols).
   - **Live Telemetry & Oscilloscopes (`$GRAPH$`)**: Real-time Catmull-Rom spline oscilloscopes plotting live CPU frame time (`us`), heap memory (`KB`), and per-core SMP load (`%`).
   - **Interactive Controls & Live JIT REPL (`$BT$`, `$SL$`, `$CB$`, `$PB$`, `$REPL$`)**: Live sliders bound to kernel variables, checkboxes toggling compositor effects (Glass, Shadows, VSync, Zero-RAM), and an inline `$REPL$` box compiling and executing HolyC expressions on the spot.

### Order 20: Empirical QEMU Framebuffer Verification Protocol
1. **Never screenshot the host desktop.** Every visual feature must be verified by booting NeoOS in QEMU and capturing the guest framebuffer via QEMU monitor `screendump` (converted to PNG and inspected via `view_file`).
2. Every subsystem self-test and benchmark must assert real mathematical/hardware invariants (never static print strings).
