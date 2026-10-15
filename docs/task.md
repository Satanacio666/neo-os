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

- [ ] **Phase 9: Self-Hosting HolyC Compiler (`apps/Compiler.HC`)**
  - [ ] Implement full HolyC tokenizer (ident, num, string, symbols) in pure HolyC.
  - [ ] Implement recursive descent parser for expressions and statement blocks in HolyC.
  - [ ] Implement AArch64 machine code emitter in HolyC emitting directly into allocated executable RAM.
  - [ ] Compile and execute a secondary HolyC program from inside HolyC without C compiler intervention.

- [ ] **Kernel Preemption & Advanced Scheduling**
  - [ ] Upgrade `sched_tick()` to preempt compute-heavy tasks when timeslice expires.
  - [ ] Save full FP/NEON register state (Q0-Q31) in exception trap frame on preemption.
  - [ ] Per-core run queues for secondary vCPUs.

- [ ] **Filesystem Expansion**
  - [ ] Dynamic sector and directory entry allocation for newly created files from scratch in `fs/redsea.c`.
  - [ ] Cluster bitmap free list reclamation upon file deletion.

- [ ] **Real Hardware Bring-up (Physical Silicon Roadmap)**
  - [ ] Flattened Device Tree (FDT / DTB) parser for physical SoC address discovery.
  - [ ] Physical board bring-up on Raspberry Pi 4/5 or Rockchip RK3399/RK3326.
  - [ ] Native USB xHCI host controller driver.
