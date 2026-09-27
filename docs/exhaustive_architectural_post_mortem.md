# NeoOS Architectural Post-Mortem & Root Cause Analysis

An exhaustive, unvarnished deep dive into every architectural bottleneck, hardware trap, compiler limitation, and rendering flaw encountered during the engineering of NeoOS on AArch64 bare-metal, and the exact mathematical and systems-level resolutions applied.

---

## 1. Host Emulation Topology: Single-Threaded vs. Multi-Threaded TCG Contention

### The Problem
When running an emulated multi-core guest (**4x Cortex-A72 AArch64**) on a dual-core host processor (**Intel Celeron N4020 @ 1.10 GHz, 2 cores, 2 threads**), configuring multi-threaded TCG (`-accel tcg,thread=multi`) produced counter-intuitive performance degradation compared to single-threaded execution (`-accel tcg,thread=single`).

### Empirical Comparison
| Execution Mode | Host Cores | TCG Mode | Phase 1 (DoubleBuf 360p) | Phase 8 (Sovereign L1 Tile 2C) |
| :--- | :---: | :---: | :---: | :---: |
| **Pinned Single Host Core** | 1 Core (`taskset -c 0`) | `thread=single` | **5.4 FPS (184.9 ms)** | **13.5 FPS (74.0 ms, 30.9 ms jitter)** 🏆 |
| **All Host Cores** | 2 Cores (unpinned) | `thread=multi` | **0.6 FPS (1623.1 ms)** | **1.5 FPS (631.4 ms, 621.4 ms jitter)** |

### Root Cause Analysis
1. **Thread Oversubscription**: In `thread=multi`, QEMU spawns:
   - 4 guest vCPU execution threads.
   - 1 TCG JIT translation helper thread.
   - 1 GTK GUI display and presentation thread.
   - 1 QMP socket polling thread.
   
   Running 7 active threads across 2 physical cores without hyperthreading causes constant thread preemption and host context switching.
2. **Cross-Thread Synchronization Overhead**: Guest SMP spinlocks (`yield`, `dmb ish`) force host Linux kernel scheduling preemption, invalidating host L1/L2 caches.
3. **Deterministic Single-Threaded Efficiency**: In `thread=single`, QEMU runs a cooperative round-robin time-slice engine on a single physical host thread. Translation blocks remain hot in the 512 MB buffer without cross-core lock contention.

---

## 2. The Self-Induced Latency Stall: Synchronous UART I/O Feedback Loop

### The Problem
Frametime standard deviation (jitter) was inflated to **359.95 ms**, and worst-case frame spikes reached **1,275 ms**, causing visible stutters despite simple 3D scenes.

### Root Cause Analysis
In `kernel/bench/perf_overlay.c`:
```c
if (frame_delta_us > 33333) { // 30 FPS threshold
    snprintf(spk_msg, sizeof(spk_msg), "[SPIKE] Frame #%u | %.1f ms | Cause: %s\r\n", frame_id, frame_ms, cause_str);
    uart_puts(spk_msg); // Synchronous host MMIO write!
}
```
1. Software TCG rendering naturally requires 70–150 ms per frame on a 1.10 GHz CPU.
2. Setting the alert threshold to 33.3 ms caused **every frame to be classified as a spike**.
3. Every frame executed `uart_puts()`, which writes characters one-by-one to PL011 UART register `0x09000000ULL`.
4. In QEMU, PL011 writes trigger synchronous `write(1, ...)` syscalls to the host terminal. The host terminal blocked the emulation thread for 20–40 ms per frame.
5. The latency incurred by logging was counted in the subsequent frame duration, causing an artificial self-sustaining spike loop.

### Resolution
In [`kernel/bench/perf_overlay.c`](file:///home/carlos/.gemini/antigravity/scratch/neo-os/kernel/bench/perf_overlay.c), real-time UART alert output was reserved for genuine latency stalls ($>400\text{ ms}$), with standard metrics buffered in memory rings. Jitter dropped immediately from **359.9 ms to 37.7 ms** ($10\times$ improvement).

---

## 3. False Classification of Memory Bus Transfers as VirtIO Polling

### The Problem
Telemetry logs categorized normal software blits as `SPIKE_CAUSE_VIRTIO_POLL` even when running exclusively on the UEFI GOP linear framebuffer.

### Root Cause Analysis
```c
if (stats->last_blit_us > 25000) {
    cause = SPIKE_CAUSE_VIRTIO_POLL; // Incorrect assumption
}
```
Copying a 3.14 MB (1024x768x32bpp) buffer across the emulated PCI bus to GOP VRAM takes 10–30 ms under load. Classifying all blits $>25\text{ ms}$ as VirtIO polling obscured the true performance of the memory subsystem.

### Resolution
We introduced distinct architectural metrics:
- `SPIKE_CAUSE_GOP_BLIT_MEM`: Identifies DDR4-to-VRAM bandwidth saturation.
- `SPIKE_CAUSE_VIRTIO_POLL`: Verified only when VirtIO control queue rings have pending descriptors.

---

## 4. DolDoc Terminal Client Repaint Bug (Background Erasing)

### The Problem
During full window redraws, existing terminal text was wiped, leaving an empty slate window body.

### Root Cause Analysis
In [`gui/wm.c`](file:///home/carlos/.gemini/antigravity/scratch/neo-os/gui/wm.c):
1. `wm_draw_window()` fills the client area with solid `COLOR_WINDOW_BODY`.
2. It then invokes `doldoc_redraw()`.
3. In [`gui/render.c`](file:///home/carlos/.gemini/antigravity/scratch/neo-os/gui/render.c), `doldoc_redraw()` optimizes drawing by checking `s_doc_dirty_mask`. If zero, it skips all text rendering.
4. Because no new keypress occurred, the dirty mask was zero; `doldoc_redraw()` returned immediately, leaving the cleared window empty.

### Resolution
Inside `wm_draw_window()` for Window ID 1, we added an explicit call to `doldoc_mark_all_dirty()`, ensuring complete text re-rasterization upon full window repaints.

---

## 5. Framebuffer Defacement via UEFI ConOut (`vprintf`)

### The Problem
When the HolyC JIT compiler compiled functions, black boxes with white text rendered directly over the graphical windowing canvas.

### Root Cause Analysis
In `boot/uefi/stdio.c`:
```c
int vprintf(const char_t* fmt, __builtin_va_list args) {
    ...
    ST->ConOut->OutputString(ST->ConOut, (wchar_t *)&dst);
    return ret;
}
```
UEFI's `ST->ConOut` protocol renders text by drawing bitmap rectangles onto the video display scanout buffer. After the NeoOS window manager took ownership of GOP VRAM, any call to `printf()` invoked `OutputString`, overwriting window pixels with firmware console characters.

### Resolution
1. Implemented `gfx_is_active()` in [`gui/render.c`](file:///home/carlos/.gemini/antigravity/scratch/neo-os/gui/render.c).
2. Updated `vprintf()` in [`boot/uefi/stdio.c`](file:///home/carlos/.gemini/antigravity/scratch/neo-os/boot/uefi/stdio.c) to mirror all output to the PL011 UART register (`0x09000000ULL`) while suppressing `ST->ConOut->OutputString` once the GUI is active.

---

## 6. HolyGL 3D Redundant Lighting Math

### The Problem
3D render time for GLXGears hovered around **221.7 ms** per frame.

### Root Cause Analysis
GLXGears renders 7,200 triangles (21,600 vertices) per frame. Every gear tooth face comprises planar polygons sharing identical surface normal vectors. In the unoptimized pipeline, `glVertex3f()` performed 3x3 matrix multiplication, square-root calculation (`fast_rsqrt_neon`), and directional dot products for every single vertex, calculating identical lighting factors 6 times per face.

### Resolution
In [`kernel/math/holygl.c`](file:///home/carlos/.gemini/antigravity/scratch/neo-os/kernel/math/holygl.c), we implemented **Normal Factor Caching**:
```c
if (s_last_mv_depth != g_holygl.modelview_depth ||
    nx != s_last_normal.x || ny != s_last_normal.y || nz != s_last_normal.z) {
    // Recompute lighting factor only when normal or ModelView matrix changes
    s_cached_factor = factor;
    s_last_normal = (vec3_t){nx, ny, nz};
}
```
This eliminated 66.7% of vertex lighting math, cutting 3D render time to **115.7 ms** (nearly $2\times$ faster).

---

## 7. HolyC JIT Struct Reflection Loss in Function Parameters

### The Problem
Compiling functions with struct parameters (such as `U0 ArrayPush(CArray *arr, I64 val)`) resulted in memory corruption during field access (`arr->count`, `arr->capacity = new_cap`).

### Root Cause Analysis
In `compiler/jit_arm64.c`, local variable declarations registered type information via `register_var_type()`. However, the function parameter parsing loop consumed the type name without calling `register_var_type()`.
As a result, `lookup_var_type("arr")` returned `NULL` inside the function body. Member expressions defaulted to dynamic hash table lookup (`table_get`/`table_set`), treating raw struct heap pointers as table objects.

### Resolution
Preserved `param_st_name` in the parameter loop and explicitly called:
```c
register_var_type(p_tok.str_value, 8, is_param_ptr, 0, param_st_name[0] ? param_st_name : NULL);
```
Parameter member accesses now emit direct AArch64 offset loads and stores (`ldr x0, [x1, #8]`, `str x0, [x1, #16]`).

---

## 8. Missing Member Array Assignment in HolyC JIT

### The Problem
Writing `arr->data[idx] = val;` in HolyC failed with a compilation syntax error.

### Root Cause Analysis
The JIT statement parser handled:
1. `ident = expr;`
2. `ident[index] = expr;`
3. `ident->field = expr;`

It did not support composite l-values of the form `ident->field[index] = expr;`. Encountering `[` after `field` caused the parser to fall through to `parse_expr`, which evaluated `arr->data[idx]` and stopped before `=`, leaving `=` unparsed and causing a syntax error.

### Resolution
Implemented lookahead for `is_member_arr_assign`:
1. Resolves struct base pointer `arr`.
2. Adds member offset to load array pointer `arr->data` into register `X2`.
3. Evaluates index into `X1`, scales by 8 bytes, and adds to base.
4. Evaluates RHS into `X0` and emits `str x0, [x2, x1, lsl #3]`.

---

## 9. Global Symbol Registry Omission for Standard String Operations

### The Problem
Compiling `apps/StdLib.HC` produced `[JIT] Error: Undefined symbol 'strcmp'`.

### Root Cause Analysis
In TempleOS, HolyC code accesses kernel and C runtime symbols without header files via the global symbol table. While memory allocation primitives (`kmalloc`, `kfree`) were registered, string operations were absent.

### Resolution
Registered standard string and memory functions in [`boot/main.c`](file:///home/carlos/.gemini/antigravity/scratch/neo-os/boot/main.c):
`strcmp`, `strncmp`, `strlen`, `strcpy`, `strncpy`, `memset`, `memcpy`, `memcmp`.

---

## 10. Decoupling VirtIO Software from CPU/SMP Scanout

### The Problem
VirtIO-GPU mode exhibited high latency ($>5,000\text{ ms}$), and software modes suffered from hardware queue polling overhead.

### Root Cause Analysis
In legacy MMIO VirtIO-GPU mode, presenting a frame required `TRANSFER_TO_HOST_2D` and `RESOURCE_FLUSH`. In software TCG, polling the used ring descriptor involved multi-megabyte cache flushes (`dc civac`), stalling the single-threaded CPU.

### Resolution
In [`drivers/gpu/gfx_backend.c`](file:///home/carlos/.gemini/antigravity/scratch/neo-os/drivers/gpu/gfx_backend.c):
- Software, SMP, and Sovereign L1 Tile pipelines write directly to RAM backbuffers and transfer via non-temporal NEON stores (`stnp`) to UEFI GOP VRAM, bypassing queues and cache invalidation loops entirely.
- Zero-RAM Direct VRAM Mode renders directly into scanout memory, achieving **0.0 ms blit time**.
- VirtIO-GPU hardware DMA is isolated as an opt-in hardware accelerator.
