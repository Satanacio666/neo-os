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
#include "../kernel/math/raster_tile.h"
#include "../kernel/arch/aarch64/hal_platform.h"

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

void wm_step_frame(void) {
    shell_poll();
    mouse_poll();
    wm_handle_mouse(mouse_get_state());

    if (bench_unified_is_active()) {
        if (wm_is_dirty()) {
            wm_clear_dirty();
        }
        wm_draw_animating_windows();
        wm_update_tray_clock();
        gfx_vsync_wait();
    } else {
        if (wm_is_dirty()) {
            wm_draw_all();
            gfx_swap_buffers();
            wm_clear_dirty();
        } else {
            wm_update_tray_clock();
        }
    }

    task_yield();

    if (!bench_unified_is_active() && !wm_is_dirty() && !keyboard_has_char()) {
        asm volatile("yield");
    }
}

void kheap_dump_doldoc(void) {
    heap_stats_t stats;
    kheap_get_stats(&stats);
    doldoc_print("$FG,CYAN$--- KERNEL HEAP ALLOCATOR STATS ---$FG$\n");
    doldoc_printf(" Total Memory:     %llu MB (%llu bytes)\n",
                  (unsigned long long)(stats.total_memory / (1024 * 1024)),
                  (unsigned long long)stats.total_memory);
    doldoc_printf(" Allocated (Used): %llu KB (%llu bytes)\n",
                  (unsigned long long)(stats.used_memory / 1024),
                  (unsigned long long)stats.used_memory);
    doldoc_printf(" Free Space:       %llu MB (%llu bytes)\n",
                  (unsigned long long)(stats.free_memory / (1024 * 1024)),
                  (unsigned long long)stats.free_memory);
    doldoc_printf(" Live Allocations: %llu (Total frees: %llu)\n",
                  (unsigned long long)stats.allocation_count,
                  (unsigned long long)stats.free_count);
    uint64_t pct = (stats.total_memory > 0) ? ((stats.used_memory * 100) / stats.total_memory) : 0;
    doldoc_printf(" Heap Utilization: $PB,VAL=%llu,MAX=100$\n", (unsigned long long)pct);
    doldoc_print("$FG,CYAN$-----------------------------------$FG$\n");
}

void hal_reset_system(void) {
    doldoc_print("$FG,RED$Rebooting system via ARM PSCI...$FG$\n");
    gfx_swap_buffers();
    extern int64_t psci_call_hvc(uint64_t func, uint64_t arg1, uint64_t arg2, uint64_t arg3);
    psci_call_hvc(0x84000009ULL, 0, 0, 0); // PSCI 0.2+ SYSTEM_RESET
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

    // 0. Initialize Hardware Abstraction Layer
    hal_platform_init();

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
    symbols_register("strcmp", (void*)strcmp, SYM_FUNC);
    symbols_register("strncmp", (void*)strncmp, SYM_FUNC);
    symbols_register("strlen", (void*)strlen, SYM_FUNC);
    symbols_register("strcpy", (void*)strcpy, SYM_FUNC);
    symbols_register("strncpy", (void*)strncpy, SYM_FUNC);
    symbols_register("memset", (void*)memset, SYM_FUNC);
    symbols_register("memcpy", (void*)memcpy, SYM_FUNC);
    symbols_register("memcmp", (void*)memcmp, SYM_FUNC);
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
    symbols_register("mouse_get_x", (void*)mouse_get_x, SYM_FUNC);
    symbols_register("mouse_get_y", (void*)mouse_get_y, SYM_FUNC);
    symbols_register("mouse_get_btn", (void*)mouse_get_btn, SYM_FUNC);
    symbols_register("keyboard_has_char", (void*)keyboard_has_char, SYM_FUNC);
    symbols_register("keyboard_getchar", (void*)keyboard_getchar, SYM_FUNC);
    symbols_register("bench_unified_start", (void*)bench_unified_start, SYM_FUNC);
    symbols_register("bench_unified_stop", (void*)bench_unified_stop, SYM_FUNC);
    symbols_register("bench_unified_is_active", (void*)bench_unified_is_active, SYM_FUNC);
    symbols_register("bench_unified_set_mode", (void*)bench_unified_set_mode, SYM_FUNC);
    symbols_register("bench_unified_export_log", (void*)bench_unified_export_log, SYM_FUNC);
    symbols_register("bench_unified_export_comparison", (void*)bench_unified_export_comparison, SYM_FUNC);
    symbols_register("bench_unified_trigger_impulse", (void*)bench_unified_trigger_impulse, SYM_FUNC);
    symbols_register("physics3d_world_explode", (void*)physics3d_world_explode, SYM_FUNC);
    symbols_register("shell_run_command", (void*)shell_run_command, SYM_FUNC);
    symbols_register("top_print_doldoc", (void*)top_print_doldoc, SYM_FUNC);
    symbols_register("redsea_list_dir", (void*)redsea_list_dir, SYM_FUNC);
    symbols_register("gfx_backend_set_mode", (void*)gfx_backend_set_mode, SYM_FUNC);
    symbols_register("gfx_backend_get_mode", (void*)gfx_backend_get_mode, SYM_FUNC);
    symbols_register("hal_get_uart_base", (void*)hal_get_uart_base, SYM_FUNC);
    symbols_register("hal_get_gicd_base", (void*)hal_get_gicd_base, SYM_FUNC);
    symbols_register("hal_get_gicc_base", (void*)hal_get_gicc_base, SYM_FUNC);
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
    symbols_register("wm_is_dirty", (void*)wm_is_dirty, SYM_FUNC);
    symbols_register("wm_set_dirty", (void*)wm_set_dirty, SYM_FUNC);
    symbols_register("wm_clear_dirty", (void*)wm_clear_dirty, SYM_FUNC);
    symbols_register("wm_draw_all", (void*)wm_draw_all, SYM_FUNC);
    symbols_register("wm_draw_animating_windows", (void*)wm_draw_animating_windows, SYM_FUNC);
    symbols_register("wm_update_tray_clock", (void*)wm_update_tray_clock, SYM_FUNC);
    symbols_register("wm_handle_mouse", (void*)wm_handle_mouse, SYM_FUNC);
    symbols_register("wm_step_frame", (void*)wm_step_frame, SYM_FUNC);
    symbols_register("mouse_poll", (void*)mouse_poll, SYM_FUNC);
    symbols_register("mouse_get_state", (void*)mouse_get_state, SYM_FUNC);
    symbols_register("shell_poll", (void*)shell_poll, SYM_FUNC);
    symbols_register("gfx_vsync_wait", (void*)gfx_vsync_wait, SYM_FUNC);
    symbols_register("zbuffer_resize", (void*)zbuffer_resize, SYM_FUNC);
    symbols_register("redsea_mkdir", (void*)redsea_mkdir, SYM_FUNC);
    symbols_register("redsea_delete_file", (void*)redsea_delete_file, SYM_FUNC);
    symbols_register("redsea_read_file", (void*)redsea_read_file, SYM_FUNC);
    symbols_register("redsea_write_file", (void*)redsea_write_file, SYM_FUNC);
    symbols_register("redsea_change_dir", (void*)redsea_change_dir, SYM_FUNC);
    symbols_register("redsea_get_pwd", (void*)redsea_get_pwd, SYM_FUNC);
    symbols_register("timer_get_uptime_us", (void*)timer_get_uptime_us, SYM_FUNC);
    symbols_register("timer_get_ticks", (void*)timer_get_ticks, SYM_FUNC);
    symbols_register("ramdisk_write_file", (void*)ramdisk_write_file, SYM_FUNC);
    symbols_register("ramdisk_read_file", (void*)ramdisk_read_file, SYM_FUNC);
    symbols_register("ramdisk_delete_file", (void*)ramdisk_delete_file, SYM_FUNC);
    symbols_register("ramdisk_list_dir", (void*)ramdisk_list_dir, SYM_FUNC);
    symbols_register("gfx_blend_pixel", (void*)gfx_blend_pixel, SYM_FUNC);
    symbols_register("gfx_draw_rect", (void*)gfx_draw_rect, SYM_FUNC);
    symbols_register("gfx_blend_rect", (void*)gfx_blend_rect, SYM_FUNC);
    symbols_register("gfx_draw_line", (void*)gfx_draw_line, SYM_FUNC);
    symbols_register("gfx_clear", (void*)gfx_clear, SYM_FUNC);
    symbols_register("gfx_swap_buffers", (void*)gfx_swap_buffers, SYM_FUNC);
    symbols_register("gfx_get_backbuffer", (void*)gfx_get_backbuffer, SYM_FUNC);
    symbols_register("gfx_get_canvas_width", (void*)gfx_get_canvas_width, SYM_FUNC);
    symbols_register("gfx_get_canvas_height", (void*)gfx_get_canvas_height, SYM_FUNC);
    symbols_register("gfx_get_canvas_pitch", (void*)gfx_get_canvas_pitch, SYM_FUNC);
    symbols_register("gfx_get_frontbuffer", (void*)gfx_get_frontbuffer, SYM_FUNC);
    symbols_register("virtio_gpu_page_flip", (void*)virtio_gpu_page_flip, SYM_FUNC);
    symbols_register("smp_get_current_core", (void*)smp_get_current_core, SYM_FUNC);
    symbols_register("smp_get_core_count", (void*)smp_get_core_count, SYM_FUNC);
    symbols_register("smp_dispatch", (void*)smp_dispatch, SYM_FUNC);
    symbols_register("smp_is_job_done", (void*)smp_is_job_done, SYM_FUNC);
    symbols_register("smp_wait_job", (void*)smp_wait_job, SYM_FUNC);
    symbols_register("raster_tile_begin_scene", (void*)raster_tile_begin_scene, SYM_FUNC);
    symbols_register("raster_tile_add_triangle", (void*)raster_tile_add_triangle, SYM_FUNC);
    symbols_register("raster_tile_end_scene", (void*)raster_tile_end_scene, SYM_FUNC);
    symbols_register("gfx_draw_triangle_fill", (void*)gfx_draw_triangle_fill, SYM_FUNC);
    symbols_register("gfx_draw_triangle_wire", (void*)gfx_draw_triangle_wire, SYM_FUNC);
    symbols_register("gfx_draw_string", (void*)gfx_draw_string, SYM_FUNC);
    symbols_register("gfx_draw_char", (void*)gfx_draw_char, SYM_FUNC);
    symbols_register("gfx_dirty_expand", (void*)gfx_dirty_expand, SYM_FUNC);
    symbols_register("gfx_draw_rounded_rect", (void*)gfx_draw_rounded_rect, SYM_FUNC);
    symbols_register("gfx_draw_rounded_rect_outline", (void*)gfx_draw_rounded_rect_outline, SYM_FUNC);
    symbols_register("gfx_draw_shadow", (void*)gfx_draw_shadow, SYM_FUNC);
    symbols_register("gfx_swap_rect", (void*)gfx_swap_rect, SYM_FUNC);
    symbols_register("gfx_get_pixel", (void*)gfx_get_pixel, SYM_FUNC);
    symbols_register("gfx_draw_rect_outline", (void*)gfx_draw_rect_outline, SYM_FUNC);
    symbols_register("gfx_fill_circle", (void*)gfx_fill_circle, SYM_FUNC);
    symbols_register("atoi", (void*)atoi, SYM_FUNC);
    symbols_register("gpu_config_open", (void*)gpu_config_open, SYM_FUNC);
    symbols_register("gpu_config_close", (void*)gpu_config_close, SYM_FUNC);
    symbols_register("gpu_set_buffering", (void*)gpu_set_buffering, SYM_FUNC);
    symbols_register("gpu_set_zprecision", (void*)gpu_set_zprecision, SYM_FUNC);
    symbols_register("compositor_config_open", (void*)compositor_config_open, SYM_FUNC);
    symbols_register("compositor_config_close", (void*)compositor_config_close, SYM_FUNC);
    symbols_register("compositor_set_vsync", (void*)compositor_set_vsync, SYM_FUNC);
    symbols_register("compositor_set_shadows", (void*)compositor_set_shadows, SYM_FUNC);
    symbols_register("compositor_set_glass", (void*)compositor_set_glass, SYM_FUNC);
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
    symbols_register("gfx_set_clip", (void*)gfx_set_clip, SYM_FUNC);
    symbols_register("gfx_reset_clip", (void*)gfx_reset_clip, SYM_FUNC);
    symbols_register("mouse_draw_cursor_front", (void*)mouse_draw_cursor_front, SYM_FUNC);
    symbols_register("mouse_erase_cursor_front", (void*)mouse_erase_cursor_front, SYM_FUNC);
    symbols_register("doldoc_redraw", (void*)doldoc_redraw, SYM_FUNC);
    symbols_register("doldoc_move", (void*)doldoc_move, SYM_FUNC);
    symbols_register("doldoc_handle_click", (void*)doldoc_handle_click, SYM_FUNC);
    symbols_register("doldoc_mark_all_dirty", (void*)doldoc_mark_all_dirty, SYM_FUNC);
    symbols_register("timer_get_uptime_sec", (void*)timer_get_uptime_sec, SYM_FUNC);
    symbols_register("timer_sleep_ms", (void*)timer_sleep_ms, SYM_FUNC);
    symbols_register("gfx_dirty_all", (void*)gfx_dirty_all, SYM_FUNC);
    symbols_register("wm_set_holyc_active", (void*)wm_set_holyc_active, SYM_FUNC);
    symbols_register("doldoc_putc", (void*)doldoc_putc, SYM_FUNC);
    symbols_register("doldoc_backspace", (void*)doldoc_backspace, SYM_FUNC);
    symbols_register("doldoc_draw_cursor", (void*)doldoc_draw_cursor, SYM_FUNC);
    symbols_register("doldoc_swap_term", (void*)doldoc_swap_term, SYM_FUNC);
    symbols_register("doldoc_swap_cursor", (void*)doldoc_swap_cursor, SYM_FUNC);
    symbols_register("doldoc_scroll_up", (void*)doldoc_scroll_up, SYM_FUNC);
    symbols_register("doldoc_scroll_down", (void*)doldoc_scroll_down, SYM_FUNC);
    symbols_register("redsea_get_entries", (void*)redsea_get_entries, SYM_FUNC);
    symbols_register("kheap_dump_doldoc", (void*)kheap_dump_doldoc, SYM_FUNC);
    symbols_register("hal_reset_system", (void*)hal_reset_system, SYM_FUNC);
    symbols_register("shell_register_holyc", (void*)shell_register_holyc, SYM_FUNC);
    symbols_register("doldoc_register_holyc", (void*)doldoc_register_holyc, SYM_FUNC);
    extern void uart_putc(char c);
    symbols_register("uart_putc", (void*)uart_putc, SYM_FUNC);
    symbols_register("memmove", (void*)memmove, SYM_FUNC);
    symbols_register("strstr", (void*)strstr, SYM_FUNC);
    symbols_register("menu_toggle", (void*)menu_toggle, SYM_FUNC);

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

    // 5. Initialize Input Devices (Keyboard, Mouse & VirtIO Input)
    keyboard_init();
    mouse_init(width, height);
    extern int virtio_input_init(uint32_t screen_width, uint32_t screen_height);
    virtio_input_init(width, height);

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
    symbols_register("menu", (void*)menu_toggle, SYM_FUNC);

    // 8. Initialize Native AArch64 JIT Compiler & Shell
    printf("[TRACE] Calling jit_init...\r\n");
    jit_init();
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

    // 10A. Sovereign Handover: Compile Pure HolyC DolDoc.HC
    printf("[BOOT] Sovereign Handover: Loading Pure HolyC DolDoc.HC...\r\n");
    static char doldoc_src[32768];
    size_t doldoc_src_len = 0;
    if (redsea_read_file("DolDoc.HC", doldoc_src, sizeof(doldoc_src) - 1, &doldoc_src_len) == 0) {
        doldoc_src[doldoc_src_len] = '\0';
        printf("[BOOT] Compiling DolDoc.HC (%llu bytes)...\r\n", (unsigned long long)doldoc_src_len);
        int64_t dres = jit_compile_and_run(doldoc_src);
        printf("[BOOT] DolDoc.HC compiled, res = %lld\r\n", (long long)dres);
    } else {
        printf("[BOOT WARN] Could not read DolDoc.HC from RedSea disk!\r\n");
    }

    // 10B. Sovereign Handover: Compile Pure HolyC Compositor.HC
    printf("[BOOT] Sovereign Handover: Loading Pure HolyC Compositor.HC...\r\n");
    static char comp_src[32768];
    size_t comp_src_len = 0;
    if (redsea_read_file("Compositor.HC", comp_src, sizeof(comp_src) - 1, &comp_src_len) == 0) {
        comp_src[comp_src_len] = '\0';
        printf("[BOOT] Compiling Compositor.HC (%llu bytes)...\r\n", (unsigned long long)comp_src_len);
        int64_t cres = jit_compile_and_run(comp_src);
        printf("[BOOT] Compositor.HC compiled, res = %lld\r\n", (long long)cres);
    } else {
        printf("[BOOT WARN] Could not read Compositor.HC from RedSea disk!\r\n");
    }

    // 10C. Sovereign Handover: Compile Pure HolyC Shell.HC
    printf("[BOOT] Sovereign Handover: Loading Pure HolyC Shell.HC...\r\n");
    static char shell_src[32768];
    size_t shell_src_len = 0;
    if (redsea_read_file("Shell.HC", shell_src, sizeof(shell_src) - 1, &shell_src_len) == 0) {
        shell_src[shell_src_len] = '\0';
        printf("[BOOT] Compiling Shell.HC (%llu bytes)...\r\n", (unsigned long long)shell_src_len);
        int64_t sres = jit_compile_and_run(shell_src);
        printf("[BOOT] Shell.HC compiled, res = %lld\r\n", (long long)sres);
    } else {
        printf("[BOOT WARN] Could not read Shell.HC from RedSea disk!\r\n");
    }

    // 10C. Sovereign Handover: Transfer Primary Execution to Pure HolyC WM.HC
    printf("[BOOT] Sovereign Handover: Transferring primary execution to Pure HolyC WM.HC...\r\n");
    static char wm_src[32768];
    size_t wm_src_len = 0;
    if (redsea_read_file("WM.HC", wm_src, sizeof(wm_src) - 1, &wm_src_len) == 0) {
        wm_src[wm_src_len] = '\0';
        printf("[BOOT] Compiling WM.HC (%llu bytes)...\r\n", (unsigned long long)wm_src_len);
        int64_t res = jit_compile_and_run(wm_src);
        printf("[BOOT] WM.HC compiled, res = %lld\r\n", (long long)res);
        printf("[BOOT] Entering Sovereign HolyC WMEventLoop()...\r\n");
        wm_set_holyc_active(1);
        int64_t wm_loop_res = jit_compile_and_run("WMEventLoop();");
        printf("[BOOT] HolyC WMEventLoop returned: %lld\r\n", (long long)wm_loop_res);
    } else {
        printf("[BOOT WARN] Could not read WM.HC from RedSea disk, falling back to C loop.\r\n");
    }

    // 11. Fallback Main Loop (Only if HolyC returns)
    while (1) {
        // Poll keyboard & execute shell commands
        shell_poll();

        // Poll mouse movement and handle window dragging / controls
        mouse_poll();
        wm_handle_mouse(mouse_get_state());

        // If 3D benchmark is active, update animating window directly with isolated viewport swap
        if (bench_unified_is_active()) {
            if (wm_is_dirty()) {
                wm_clear_dirty();
            }
            wm_draw_animating_windows();
            wm_update_tray_clock();
            gfx_vsync_wait();
        } else {
            if (wm_is_dirty()) {
                wm_draw_all();
                gfx_swap_buffers();
                wm_clear_dirty();
            } else {
                wm_update_tray_clock();
            }
        }

        // Cooperative yield between active Ring 0 scheduler tasks
        task_yield();

        // CPU Cycle Budgeting: When system is idle, yield CPU execution slice
        if (!bench_unified_is_active() && !wm_is_dirty() && !keyboard_has_char()) {
            asm volatile("yield");
        }
    }

    return 0;
}
