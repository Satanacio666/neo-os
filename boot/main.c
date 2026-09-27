#include "../compiler/lua_bridge.h"
#include <uefi.h>
#include "../kernel/mem/kheap.h"
#include "../kernel/symbols/symbols.h"
#include "../kernel/sched/sched.h"
#include "../kernel/arch/aarch64/gic.h"
#include "../kernel/arch/aarch64/timer.h"
#include "../compiler/jit_arm64.h"
#include "../gui/render.h"
#include "../gui/wm.h"
#include "../gui/shell.h"
#include "../drivers/input/keyboard.h"
#include "../drivers/input/mouse.h"
#include "../gui/font_ttf.h"
#include "../drivers/block/virtio_blk.h"
#include "../fs/redsea.h"
#include "../kernel/arch/aarch64/smp.h"
#include "../kernel/math/math3d.h"
#include "../kernel/bench/bench_unified.h"
#include "../drivers/gpu/gfx_backend.h"
#include "../drivers/gpu/virtio_gpu.h"
#include "../gui/wm.h"
#include "../gui/menu.h"
#include "../kernel/math/holygl.h"

extern void install_vector_table(void);
extern void enable_interrupts(void);
extern void disable_interrupts(void);

// 32 MB Heap size for kernel dynamic allocation
#define KERNEL_HEAP_SIZE (32 * 1024 * 1024)


static inline void aarch64_enable_fp(void) {
    uint64_t val;
    asm volatile("mrs %0, cpacr_el1" : "=r"(val));
    val |= (3ULL << 20); // Bits [21:20] = 0b11: Enable FP/ASIMD instructions without EL1/EL0 traps
    asm volatile("msr cpacr_el1, %0\nisb" :: "r"(val));
}

int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;

    aarch64_enable_fp();

    printf("\n======================================================\n");
    printf(" NeoOS AArch64 (ARMv8-A Ring 0 / EL1)\n");
    printf(" Interactive DolDoc 2.0 & Native NeoC JIT Engine\n");
    printf("======================================================\n\n");

    // 1. Initialize Kernel Heap Allocator (32 MB Pool)
    efi_physical_address_t heap_phys = 0;
    efi_status_t h_status = BS->AllocatePages(AllocateAnyPages, EfiLoaderData, KERNEL_HEAP_SIZE / 4096, &heap_phys);
    if (EFI_ERROR(h_status) || !heap_phys) {
        printf("FATAL: Could not allocate kernel heap!\n");
        return 1;
    }
    kheap_init((void*)heap_phys, KERNEL_HEAP_SIZE);

    // 1B. Initialize NeoC JIT Dedicated Executable Pool (EfiLoaderCode, 4 MB)
    #define JIT_CODE_POOL_SIZE (4 * 1024 * 1024)
    efi_physical_address_t jit_code_phys = 0;
    efi_status_t j_status = BS->AllocatePages(AllocateAnyPages, EfiLoaderCode, JIT_CODE_POOL_SIZE / 4096, &jit_code_phys);
    if (!EFI_ERROR(j_status) && jit_code_phys) {
        extern void jit_init_code_pool(void *pool_start, size_t pool_size);
        jit_init_code_pool((void*)jit_code_phys, JIT_CODE_POOL_SIZE);
    }

    // 2. Initialize Global Dynamic Symbol Table (TempleOS DNA)
    symbols_init();

    // Register all core kernel and subsystem symbols for live JIT reflection
    symbols_register("kmalloc", (void*)kmalloc, SYM_FUNC);
    symbols_register("kfree", (void*)kfree, SYM_FUNC);
    symbols_register("task_yield", (void*)task_yield, SYM_FUNC);
    symbols_register("gfx_put_pixel", (void*)gfx_put_pixel, SYM_FUNC);
    symbols_register("doldoc_print", (void*)doldoc_print, SYM_FUNC);
    symbols_register("doldoc_printf", (void*)doldoc_printf, SYM_FUNC);
    symbols_register("doldoc_clear", (void*)doldoc_clear, SYM_FUNC);
    symbols_register("jit_eval", (void*)jit_eval, SYM_FUNC);
    symbols_register("jit_compile_and_run", (void*)jit_compile_and_run, SYM_FUNC);
    symbols_register("sched_print_doldoc", (void*)sched_print_doldoc, SYM_FUNC);
    symbols_register("symbols_print_doldoc", (void*)symbols_print_doldoc, SYM_FUNC);
    symbols_register("mouse_set_pos", (void*)mouse_set_pos, SYM_FUNC);
    symbols_register("mouse_set_button", (void*)mouse_set_button, SYM_FUNC);
    symbols_register("bench_unified_start", (void*)bench_unified_start, SYM_FUNC);
    symbols_register("bench_unified_stop", (void*)bench_unified_stop, SYM_FUNC);
    symbols_register("bench_unified_is_active", (void*)bench_unified_is_active, SYM_FUNC);
    symbols_register("bench_unified_set_mode", (void*)bench_unified_set_mode, SYM_FUNC);
    symbols_register("bench_unified_export_log", (void*)bench_unified_export_log, SYM_FUNC);
    symbols_register("bench_unified_trigger_impulse", (void*)bench_unified_trigger_impulse, SYM_FUNC);
    symbols_register("physics3d_world_explode", (void*)physics3d_world_explode, SYM_FUNC);
    symbols_register("top_print_doldoc", (void*)top_print_doldoc, SYM_FUNC);
    symbols_register("redsea_list_dir", (void*)redsea_list_dir, SYM_FUNC);
    symbols_register("gfx_backend_set_mode", (void*)gfx_backend_set_mode, SYM_FUNC);
    symbols_register("gfx_backend_get_mode", (void*)gfx_backend_get_mode, SYM_FUNC);
    symbols_register("math3d_sin", (void*)math3d_sin, SYM_FUNC);
    symbols_register("math3d_cos", (void*)math3d_cos, SYM_FUNC);
    symbols_register("math3d_sin_d", (void*)math3d_sin_d, SYM_FUNC);
    symbols_register("fast_rsqrt_neon", (void*)fast_rsqrt_neon, SYM_FUNC);
    symbols_register("fast_sqrt_neon", (void*)fast_sqrt_neon, SYM_FUNC);
    symbols_register("fast_sqrt_d", (void*)fast_sqrt_d, SYM_FUNC);
    symbols_register("math3d_transform_vertices_parallel", (void*)math3d_transform_vertices_parallel, SYM_FUNC);
    symbols_register("gfx_vsync_set", (void*)gfx_vsync_set, SYM_FUNC);
    symbols_register("gfx_set_zero_ram_mode", (void*)gfx_set_zero_ram_mode, SYM_FUNC);
    symbols_register("gfx_is_zero_ram_mode", (void*)gfx_is_zero_ram_mode, SYM_FUNC);
    symbols_register("kheap_is_valid_ptr", (void*)kheap_is_valid_ptr, SYM_FUNC);
    symbols_register("wm_sweep_destroyed_windows", (void*)wm_sweep_destroyed_windows, SYM_FUNC);
    symbols_register("zbuffer_resize", (void*)zbuffer_resize, SYM_FUNC);
    symbols_register("redsea_mkdir", (void*)redsea_mkdir, SYM_FUNC);
    symbols_register("redsea_delete_file", (void*)redsea_delete_file, SYM_FUNC);
    symbols_register("redsea_read_file", (void*)redsea_read_file, SYM_FUNC);
    symbols_register("redsea_write_file", (void*)redsea_write_file, SYM_FUNC);
    symbols_register("redsea_change_dir", (void*)redsea_change_dir, SYM_FUNC);
    symbols_register("ramdisk_write_file", (void*)ramdisk_write_file, SYM_FUNC);
    symbols_register("ramdisk_read_file", (void*)ramdisk_read_file, SYM_FUNC);
    symbols_register("ramdisk_delete_file", (void*)ramdisk_delete_file, SYM_FUNC);
    symbols_register("ramdisk_list_dir", (void*)ramdisk_list_dir, SYM_FUNC);
    symbols_register("gfx_blend_pixel", (void*)gfx_blend_pixel, SYM_FUNC);
    symbols_register("gfx_draw_rect", (void*)gfx_draw_rect, SYM_FUNC);
    symbols_register("gfx_blend_rect", (void*)gfx_blend_rect, SYM_FUNC);
    symbols_register("gfx_draw_line", (void*)gfx_draw_line, SYM_FUNC);
    symbols_register("gfx_dirty_expand", (void*)gfx_dirty_expand, SYM_FUNC);
    symbols_register("neo_lua_eval", (void*)neo_lua_eval, SYM_FUNC);
    symbols_register("neo_lua_dofile", (void*)neo_lua_dofile, SYM_FUNC);
    symbols_register("gpu_config_open", (void*)gpu_config_open, SYM_FUNC);
    symbols_register("gpu_config_close", (void*)gpu_config_close, SYM_FUNC);
    symbols_register("gpu_set_buffering", (void*)gpu_set_buffering, SYM_FUNC);
    symbols_register("gpu_set_zprecision", (void*)gpu_set_zprecision, SYM_FUNC);
    symbols_register("compositor_config_open", (void*)compositor_config_open, SYM_FUNC);
    symbols_register("compositor_config_close", (void*)compositor_config_close, SYM_FUNC);
    symbols_register("compositor_set_vsync", (void*)compositor_set_vsync, SYM_FUNC);
    symbols_register("compositor_set_shadows", (void*)compositor_set_shadows, SYM_FUNC);
    symbols_register("compositor_set_glass", (void*)compositor_set_glass, SYM_FUNC);
    extern void filer_open(void);
    extern void filer_close(void);
    extern void editor_open(const char *filename);
    extern void editor_close(void);
    symbols_register("filer_open", (void*)filer_open, SYM_FUNC);
    symbols_register("filer_close", (void*)filer_close, SYM_FUNC);
    symbols_register("editor_open", (void*)editor_open, SYM_FUNC);
    symbols_register("editor_close", (void*)editor_close, SYM_FUNC);
    symbols_register("glViewport", (void*)glViewport, SYM_FUNC);
    symbols_register("glMatrixMode", (void*)glMatrixMode, SYM_FUNC);
    symbols_register("glLoadIdentity", (void*)glLoadIdentity, SYM_FUNC);
    symbols_register("glPushMatrix", (void*)glPushMatrix, SYM_FUNC);
    symbols_register("glPopMatrix", (void*)glPopMatrix, SYM_FUNC);
    symbols_register("glTranslatef", (void*)glTranslatef, SYM_FUNC);
    symbols_register("glRotatef", (void*)glRotatef, SYM_FUNC);
    symbols_register("glScalef", (void*)glScalef, SYM_FUNC);
    symbols_register("gluPerspective", (void*)gluPerspective, SYM_FUNC);
    symbols_register("glClear", (void*)glClear, SYM_FUNC);
    symbols_register("glColor4f", (void*)glColor4f, SYM_FUNC);
    symbols_register("glColor3f", (void*)glColor3f, SYM_FUNC);
    symbols_register("glColor3ub", (void*)glColor3ub, SYM_FUNC);
    symbols_register("glNormal3f", (void*)glNormal3f, SYM_FUNC);
    symbols_register("glTexCoord2f", (void*)glTexCoord2f, SYM_FUNC);
    symbols_register("glBegin", (void*)glBegin, SYM_FUNC);
    symbols_register("glVertex3f", (void*)glVertex3f, SYM_FUNC);
    symbols_register("glVertex2f", (void*)glVertex2f, SYM_FUNC);
    symbols_register("glEnd", (void*)glEnd, SYM_FUNC);
    symbols_register("glFlush", (void*)glFlush, SYM_FUNC);
    symbols_register("glEnable", (void*)glEnable, SYM_FUNC);
    symbols_register("glDisable", (void*)glDisable, SYM_FUNC);
    symbols_register("glClearColor", (void*)glClearColor, SYM_FUNC);

    // 3. Initialize Graphics (GOP) & Double-Buffered Canvas
    efi_guid_t gopGuid = EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID;
    efi_gop_t *gop = NULL;
    efi_status_t status = BS->LocateProtocol(&gopGuid, NULL, (void**)&gop);
    if (EFI_ERROR(status) || !gop) {
        printf("FATAL: GOP not available!\n");
        return 1;
    }

    // Dynamic UEFI GOP Mode Discovery
    uint32_t chosen_mode = 0;
    uint32_t max_modes = gop->Mode ? gop->Mode->MaxMode : 0;
    uint32_t best_area = 0;

    for (uint32_t m = 0; m < max_modes; m++) {
        efi_gop_mode_info_t *info = NULL;
        uintn_t info_size = 0;
        if (gop->QueryMode(gop, m, &info_size, &info) == EFI_SUCCESS && info) {
            uint32_t area = info->HorizontalResolution * info->VerticalResolution;
            if (info->HorizontalResolution == 1280 && info->VerticalResolution == 720) {
                chosen_mode = m;
                best_area = area * 2; // Strong preference for 720p if available
            } else if (area > best_area) {
                best_area = area;
                chosen_mode = m;
            }
        }
    }
    gop->SetMode(gop, chosen_mode);

    uint32_t *vram = (uint32_t*)gop->Mode->FrameBufferBase;
    uint32_t width = gop->Mode->Information->HorizontalResolution;
    uint32_t height = gop->Mode->Information->VerticalResolution;
    uint32_t pitch = gop->Mode->Information->PixelsPerScanLine;
    printf("[GFX] GOP FrameBufferBase: 0x%016llX (%ux%u, pitch %u)\r\n",
           (unsigned long long)gop->Mode->FrameBufferBase, width, height, pitch);

    gfx_init(vram, width, height, pitch);
    gfx_backend_init();
    holygl_init();
    bench_unified_init();
    font_ttf_init(16.0f);

    // Initialize VirtIO-GPU 2D accelerator (graceful fallback to ramfb if absent)
    int vgpu_ok = virtio_gpu_init();
    if (vgpu_ok == 0) {
        printf("[BOOT] VirtIO-GPU hardware ready (Default: CPU SW low-latency presentation)\n");
    } else {
        printf("[BOOT] VirtIO-GPU not available, using ramfb + NEON SIMD\n");
    }

    // 4. Initialize Hardware Interrupts, Timer & Exceptions
    disable_interrupts();
    sched_init();
    gic_init();
    install_vector_table();
    timer_init(100); // 100 Hz ARM Generic Timer ticks

    // 5. Initialize Input Devices (Keyboard & Mouse)
    keyboard_init();
    mouse_init(width, height);

    // 6. Initialize Window Manager & DolDoc Terminal Window
    printf("[TRACE] Calling wm_init...\r\n");
    wm_init(width, height);
    printf("[TRACE] wm_init done\r\n");

    uint32_t win_w = 880;
    uint32_t win_h = 520;
    uint32_t win_x = (width - win_w) / 2;
    uint32_t win_y = (height - 44 - win_h) / 2;

    printf("[TRACE] Calling wm_create_window...\r\n");
    window_t *main_win = wm_create_window("NeoOS Interactive Shell (DolDoc 2.0 / ARM64 JIT)",
                                          win_x, win_y, win_w, win_h);
    (void)main_win;
    printf("[TRACE] wm_create_window done\r\n");

    printf("[TRACE] Calling wm_draw_all...\r\n");
    wm_draw_all();
    gfx_swap_buffers();
    printf("[TRACE] wm_draw_all done\r\n");

    // Initialize DolDoc 2.0 console inside the central window
    uint32_t doc_x = win_x + 12;
    uint32_t doc_y = win_y + 40;
    uint32_t doc_w = win_w - 24;
    uint32_t doc_h = win_h - 48;
    printf("[TRACE] Calling doldoc_init...\r\n");
    doldoc_init(doc_x, doc_y, doc_w, doc_h);
    printf("[TRACE] doldoc_init done\r\n");

    // 7. Initialize Storage Driver & RedSea Filesystem
    printf("[TRACE] Calling virtio_blk_init...\r\n");
    virtio_blk_init();
    printf("[TRACE] Calling redsea_init...\r\n");
    redsea_init(0);
    menu_init();
    symbols_register("menu", (void*)menu_toggle, SYM_FUNC);

    // 8. Initialize Native AArch64 JIT Compiler & Shell
    printf("[TRACE] Calling jit_init...\r\n");
    jit_init();
    printf("[TRACE] Calling neo_lua_init...\r\n");
    neo_lua_init();
    printf("[TRACE] Calling shell_init...\r\n");
    shell_init();
    printf("[TRACE] shell_init done\r\n");

    // 9. Initialize SMP Multiprocessing (ARM PSCI Cores 1-3)
    printf("[TRACE] Calling smp_init...\r\n");
    smp_init();
    printf("[TRACE] smp_init done\r\n");

    printf("[KERNEL] Interactive Shell operational. Starting main loop...\r\n");

    // Redraw window manager and mouse to present pristine shell
    wm_draw_all();
    gfx_swap_buffers();
    mouse_draw_cursor_front();

    enable_interrupts();

    // 10. Interactive Main Loop (Polls input, renders UI, handles animation)
    while (1) {
        // Poll keyboard & execute shell commands
        shell_poll();

        // Poll mouse movement and handle window dragging / controls
        mouse_poll();
        wm_handle_mouse(mouse_get_state());

        // If 3D benchmark is active, update animating window directly
        if (bench_unified_is_active()) {
            if (wm_is_dirty()) {
                uint64_t wm_start = 0, wm_end = 0;
                __asm__ volatile("mrs %0, cntvct_el0" : "=r"(wm_start));
                wm_draw_all();
                gfx_swap_buffers();
                __asm__ volatile("mrs %0, cntvct_el0" : "=r"(wm_end));
                uint64_t freq = 0;
                __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(freq));
                if (freq == 0) freq = 62500000ULL;
                uint64_t wm_us = (wm_end > wm_start) ? (((wm_end - wm_start) * 1000000ULL) / freq) : 0;
                extern void bench_unified_record_wm_overhead(uint64_t wm_us);
                bench_unified_record_wm_overhead(wm_us);
            } else {
                wm_draw_animating_windows();
            }
            wm_update_tray_clock();
            gfx_vsync_wait();
        } else {
            if (wm_is_dirty()) {
                wm_draw_all();
                gfx_swap_buffers();
            } else {
                wm_update_tray_clock();
            }
        }

        // Cooperative yield between active Ring 0 scheduler tasks
        task_yield();
    }

    return 0;
}
