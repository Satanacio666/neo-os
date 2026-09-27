# Systematic Master Implementation Plan: Sovereign NeoOS & HolyGL Powerhouse

## Overview
This implementation plan systematically executes the complete architectural transformation of NeoOS from the bare-metal bootstrap up to user applications. It resolves all identified regressions, eliminates 5 layers of redundant middleware, fixes hardware timekeeping, decouples VirtIO hardware queues from software rendering (restoring native 40+ FPS on a single host core), unifies the Window Manager and DolDoc into a single-pass document surface, and elevates HolyGL and HolyC 2.0 into an uncompromised graphics and programming powerhouse.

---

## User Review Required

> [!IMPORTANT]
> **Single Host Core Pinned Execution**: All QEMU instances will run pinned to physical Host Core 0 (`taskset -c 0`) with single-threaded deterministic TCG (`-accel tcg,thread=single,tb-size=512`), guaranteeing repeatable, non-contending benchmarks on entry-level hardware.
>
> **Boot to Clean Idle**: Auto-launching the 16-phase benchmark at boot will be disabled. NeoOS will boot to a calm, responsive, 0.0% CPU idle shell with the tray clock ticking in true real-time seconds. The benchmark will only run when explicitly invoked.
>
> **Benchmark Phase Duration**: Each benchmark phase will run for **at least 15.0 seconds** and must render **at least 60 frames** before concluding, completely eliminating the 1-frame skip and the 62,500 FPS glitch.

---

## Proposed Changes

### Phase 1: Bare-Metal Bootstrapping & Hardware Timekeeping

Eliminate the "lost ticks" timer flaw and the automatic benchmark thrashing at boot.

#### [MODIFY] [timer.h](file:///home/carlos/.gemini/antigravity/scratch/neo-os/kernel/arch/aarch64/timer.h)
- Add `timer_get_uptime_us(void)` and `timer_get_uptime_sec(void)` based on the monotonic 64-bit hardware counter `CNTVCT_EL0`.

#### [MODIFY] [timer.c](file:///home/carlos/.gemini/antigravity/scratch/neo-os/kernel/arch/aarch64/timer.c)
- Implement `timer_get_uptime_us()` and `timer_get_uptime_sec()` using `mrs %0, cntvct_el0` and `mrs %0, cntfrq_el0`.
- Update `timer_sleep_ms(uint64_t ms)` to use hardware cycles, ensuring accurate millisecond sleep regardless of IRQ latency.
- Remove relative countdown rearming from `timer_irq_handler` that was causing lost ticks.

#### [MODIFY] [main.c](file:///home/carlos/.gemini/antigravity/scratch/neo-os/boot/main.c)
- Remove `bench_unified_start(BENCH_MODE_SUITE)` from the boot sequence (line 293).
- Ensure the kernel boots cleanly into the interactive shell at **0.0% CPU load**.

---

### Phase 2: Driver Sanitization & VirtIO Decoupling (Restoring 40+ FPS)

Eliminate the 5,000 ms cache-invalidation spinlock and decouple software rendering from VirtIO-GPU queues.

#### [MODIFY] [virtio_gpu.c](file:///home/carlos/.gemini/antigravity/scratch/neo-os/drivers/gpu/virtio_gpu.c)
- In `virtio_gpu_send_cmd()`, remove `flush_cache_range()` and barrier spam from inside the `while (vq_used->idx == last_used && --timeout)` loop.
- Use a lightweight memory barrier and cooperative CPU yield, eliminating host I/O thread starvation.

#### [MODIFY] [gfx_backend.c](file:///home/carlos/.gemini/antigravity/scratch/neo-os/drivers/gpu/gfx_backend.c)
- In `gfx_backend_present()`, remove `|| g_gfx_backend.mode == GFX_MODE_SMP_TILED`.
- Ensure CPU Software modes (`GFX_MODE_CPU_SW`) and SMP Tiled modes (`GFX_MODE_SMP_TILED`) write **strictly to memory buffers and present directly via GOP VRAM**, completely bypassing the VirtIO virtual bus.

---

### Phase 3: Visual Unification — The Unified DolDoc Surface (UDS)

Eliminate the dual-window-manager conflict, 5-layer overdraw, and the 2,000-cell redraw trap.

#### [MODIFY] [render.h](file:///home/carlos/.gemini/antigravity/scratch/neo-os/gui/render.h)
- Add 64-bit `dirty_rows` bitmap tracking to the DolDoc terminal structure.
- Add support for the `$VP$` (3D Viewport) tag attributes.

#### [MODIFY] [render.c](file:///home/carlos/.gemini/antigravity/scratch/neo-os/gui/render.c)
- Implement dirty-row text caching in `doldoc_print()` and `doldoc_putc()`: only mark modified lines dirty.
- In `doldoc_redraw()`, skip rows where `!(dirty_rows & (1ULL << row))`. If no text changed, `doldoc_redraw()` takes **0.0 ms**.
- Add `$VP,W=...,H=...,ID=...$` tag parser to reserve 3D viewport regions directly inside the document flow.

#### [MODIFY] [wm.c](file:///home/carlos/.gemini/antigravity/scratch/neo-os/gui/wm.c)
- Update `wm_update_tray_clock()` to read `timer_get_uptime_sec()`, guaranteeing the clock updates every single real-world second.
- Implement Compositor Dynamic LOD: when an animating 3D window is active, bypass drop shadows and acrylic blur calculations for static background windows, freeing **15 to 20 ms per frame**.
- Implement unified single-swap presentation: exactly one coordinated VSync swap per frame.

---

### Phase 4: HolyGL 3D Engine & L1-Cache Tile NEON Pipeline

Ensure HolyGL operates as a complete, sovereign 3D powerhouse.

#### [MODIFY] [holygl.h](file:///home/carlos/.gemini/antigravity/scratch/neo-os/kernel/math/holygl.h)
- Ensure full immediate-mode state machine declarations: matrix stacks (`GL_MODELVIEW`, `GL_PROJECTION`), lighting (`glLightfv`, `glMaterialfv`), shading (`glShadeModel`), texturing (`glBindTexture`, `glTexCoord2f`), and depth testing (`glEnable(GL_DEPTH_TEST)`).

#### [MODIFY] [holygl.c](file:///home/carlos/.gemini/antigravity/scratch/neo-os/kernel/math/holygl.c)
- Ensure vertex transformation and perspective division cleanly route to the L1 tile rasterizer.
- Preserve primitive batching: do not clear the scene on `glEnd()`, deferring frame presentation to explicit `glFlush()`.

#### [MODIFY] [raster_tile.c](file:///home/carlos/.gemini/antigravity/scratch/neo-os/kernel/math/raster_tile.c)
- Maintain $32 \times 32$ tile resolution to guarantee memory residency inside the 32 KB AArch64 L1 data cache.
- Maintain full 16-bit scaled depth buffer testing: `(uint16_t)(clampi((int)(pz * 65534.0f), 0, 65534))`.

---

### Phase 5: The Definitive 16-Phase NeoBench Extreme Suite

Deliver 100% mathematical integrity, 15-second phases, 60-frame guards, and esports-grade telemetry.

#### [MODIFY] [perf_overlay.c](file:///home/carlos/.gemini/antigravity/scratch/neo-os/kernel/bench/perf_overlay.c)
- Delete the `elapsed_cycles = 1000` fallback that caused the 62,500 FPS glitch.
- Compute frame times strictly from consecutive completion timestamps via `CNTVCT_EL0`.
- Exclude the first 3 warmup frames (cold-start JIT translation and z-buffer allocation) from phase averages.

#### [MODIFY] [bench_unified.c](file:///home/carlos/.gemini/antigravity/scratch/neo-os/kernel/bench/bench_unified.c)
- Set `suite_phase_duration_ticks = (freq * 15ULL)` (exactly 15.0 seconds per phase).
- Add the 60-frame guard:
  ```c
  if (elapsed_ticks >= g_bench.suite_phase_duration_ticks && g_bench.phase_frame_count >= 60)
  ```
- Implement sub-millisecond stage breakdown:
  $$\Delta t_{\text{total}} = \Delta t_{\text{geom}} + \Delta t_{\text{rast}} + \Delta t_{\text{blit}} + \Delta t_{\text{wm}} + \Delta t_{\text{smp}}$$
- Implement dynamic root-cause spike logger logging frames $> 33.3\text{ ms}$ to serial and `/BENCH_SPIKES.LOG`.

---

### Phase 6: HolyC 2.0 / HolyC++ & Clean Language Substrate

Elevate HolyC to support high-level dynamic programming without relying on a disconnected Lua POSIX shim.

#### [MODIFY] [jit_arm64.c](file:///home/carlos/.gemini/antigravity/scratch/neo-os/compiler/jit_arm64.c)
- Expand struct declaration parser to support arbitrary member offsets and alignment.
- Implement typed pointer dereferencing and stores (`*(U8*)`, `*(U16*)`, `*(U32*)`, `*(I64*)`).
- Ensure AAPCS64 float argument mirroring into registers `S0–S7` / `D0–D7`.

#### [NEW] [StdLib.HC](file:///home/carlos/.gemini/antigravity/scratch/neo-os/apps/StdLib.HC)
- High-level HolyC library providing `CDict` (dynamic associative hash tables), `CArray` (dynamic arrays), and arena string formatting.

---

## Verification Plan

### Automated & Live Verification

1. **Build Integrity**:
   ```bash
   make clean && make -j4
   ```
   Must compile with 0 warnings and 0 errors across all UEFI EFI and RedSea disk targets.

2. **Hardware Timekeeping Verification**:
   - Launch NeoOS on `DISPLAY=:0.0` pinned to Host CPU 0.
   - Verify serial log: ensure `timer_init` arms at 62.5 MHz.
   - Verify the tray clock: observe the seconds counter updating at exactly 1 real-world second per second with zero lag.

3. **40+ FPS Single-Core Verification**:
   - Observe baseline idle CPU: verify **0.0% CPU load** after boot.
   - Launch NeoBench in Gears mode (`bench`).
   - Verify frame rate: must achieve **40+ FPS** on a single host core.
   - Inspect serial output: verify that `[SPIKE] ... Cause: VIRTIO_POLL` is completely absent.

4. **16-Phase Benchmark Integrity Verification**:
   - Run `benchsuite`.
   - Verify that each phase executes for a full **15 seconds** (total suite duration $\approx 240\text{ seconds}$).
   - Verify that all 16 phases record genuine empirical frame rates ($15\text{ to }45\text{ FPS}$) with **zero instances of 62,500 FPS** or $0.0\text{ ms}$ frame times.
   - Verify that `/BENCH_REPORT.TXT`, `/BENCH_SPIKES.LOG`, and `/BENCH_COMPARISON.TXT` are exported to the RedSea disk.

5. **Pristine Git Synchronization**:
   - Commit all changes with clean commit messages and push to `https://github.com/Satanacio666/neo-os.git`.
