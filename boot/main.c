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
#include "../kernel/bench/bench3d.h"
#include "../kernel/bench/bench_suite.h"
#include "../kernel/bench/glxgears.h"
#include "../drivers/gpu/gfx_backend.h"
#include "../gui/menu.h"

extern void install_vector_table(void);
extern void enable_interrupts(void);
extern void disable_interrupts(void);

// 32 MB Heap size for kernel dynamic allocation
#define KERNEL_HEAP_SIZE (32 * 1024 * 1024)

// Background Task: System Heartbeat and telemetry
static void task_telemetry(void *arg) {
    (void)arg;
    uint64_t counter = 0;
    while (1) {
        counter++;
        if (counter % 500 == 0) {
            uart_puts("[TELEMETRY] Ring 0 SASOS active | Background Task Yield OK\r\n");
        }
        task_yield();
    }
}

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
    printf(" Interactive DolDoc 2.0 & Native HolyC Shell OS\n");
    printf("======================================================\n\n");

    // 1. Initialize Kernel Heap Allocator (32 MB Pool)
    efi_physical_address_t heap_phys = 0;
    efi_status_t h_status = BS->AllocatePages(AllocateAnyPages, EfiLoaderData, KERNEL_HEAP_SIZE / 4096, &heap_phys);
    if (EFI_ERROR(h_status) || !heap_phys) {
        printf("FATAL: Could not allocate kernel heap!\n");
        return 1;
    }
    kheap_init((void*)heap_phys, KERNEL_HEAP_SIZE);

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
    symbols_register("bench3d_start", (void*)bench3d_start, SYM_FUNC);
    symbols_register("bench3d_stop", (void*)bench3d_stop, SYM_FUNC);
    symbols_register("bench_suite_start", (void*)bench_suite_start, SYM_FUNC);
    symbols_register("bench_suite_stop", (void*)bench_suite_stop, SYM_FUNC);
    symbols_register("glxgears_start", (void*)glxgears_start, SYM_FUNC);
    symbols_register("glxgears_stop", (void*)glxgears_stop, SYM_FUNC);
    symbols_register("glxgears_is_active", (void*)glxgears_is_active, SYM_FUNC);
    symbols_register("top_print_doldoc", (void*)top_print_doldoc, SYM_FUNC);
    symbols_register("redsea_list_dir", (void*)redsea_list_dir, SYM_FUNC);
    symbols_register("gfx_backend_set_mode", (void*)gfx_backend_set_mode, SYM_FUNC);
    symbols_register("gfx_backend_get_mode", (void*)gfx_backend_get_mode, SYM_FUNC);
    symbols_register("math3d_sin", (void*)math3d_sin, SYM_FUNC);
    symbols_register("math3d_cos", (void*)math3d_cos, SYM_FUNC);

    // 3. Initialize Graphics (GOP) & Double-Buffered Canvas
    efi_guid_t gopGuid = EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID;
    efi_gop_t *gop = NULL;
    efi_status_t status = BS->LocateProtocol(&gopGuid, NULL, (void**)&gop);
    if (EFI_ERROR(status) || !gop) {
        printf("FATAL: GOP not available!\n");
        return 1;
    }

    // Select Mode 2 (1024x768 on QEMU)
    gop->SetMode(gop, 2);

    uint32_t *vram = (uint32_t*)gop->Mode->FrameBufferBase;
    uint32_t width = gop->Mode->Information->HorizontalResolution;
    uint32_t height = gop->Mode->Information->VerticalResolution;
    uint32_t pitch = gop->Mode->Information->PixelsPerScanLine;

    gfx_init(vram, width, height, pitch);
    font_ttf_init(16.0f);

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

    uint32_t win_w = 760;
    uint32_t win_h = 500;
    uint32_t win_x = (width - win_w) / 2;
    uint32_t win_y = (height - win_h) / 2 - 15;

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
    printf("[TRACE] Calling shell_init...\r\n");
    shell_init();
    printf("[TRACE] shell_init done\r\n");

    // Execute HolyC 2.0 JIT advanced self-tests and activate Zero-RAM Direct-to-VRAM mode
    shell_run_command("jittest");
    shell_run_command("zeroram on");
    shell_run_command("bench3d");

    // 9. Launch background tasks
    printf("[TRACE] Calling task_create...\r\n");
    task_create("TelemetryTask", task_telemetry, NULL, 16384);
    printf("[TRACE] task_create done\r\n");

    // 10. Initialize SMP Multiprocessing (ARM PSCI Cores 1-3)
    printf("[TRACE] Calling smp_init...\r\n");
    smp_init();
    printf("[TRACE] smp_init done\r\n");

    printf("[KERNEL] Interactive Shell and Multitasking operational. Starting main loop...\r\n");

    // Redraw window manager and mouse to present pristine shell
    wm_draw_all();
    mouse_draw_cursor();
    gfx_swap_buffers();

    enable_interrupts();

    // 9. Interactive Main Loop (Yields with preemption, polls input, renders UI)
    while (1) {
        // Poll keyboard & execute shell commands
        shell_poll();

        // Poll mouse movement and handle window dragging / controls
        mouse_poll();
        wm_handle_mouse(mouse_get_state());

        // If 3D benchmarks or suite are active, update and render with zero-copy dirty rects
        if (bench3d_is_active() || bench_suite_is_active() || glxgears_is_active()) {
            if (wm_is_dirty()) {
                wm_draw_all();
                mouse_draw_cursor();
                gfx_swap_buffers();
            } else {
                wm_draw_animating_windows();
            }
        }

        // Cooperative yield between active Ring 0 scheduler tasks
        task_yield();

        // Sleep CPU until next hardware interrupt (timer @ 100Hz or UART input) if no active animation
        if (!bench3d_is_active() && !bench_suite_is_active() && !glxgears_is_active() && !keyboard_has_char()) {
            asm volatile("wfi");
        }
    }

    return 0;
}
