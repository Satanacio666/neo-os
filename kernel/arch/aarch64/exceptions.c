#include <uefi.h>
#include "../../gui/render.h"
#include "../../gui/font8x16.h"
#include "../../gui/shell.h"
#include "../../compiler/jit_arm64.h"

typedef struct {
    uint64_t x[30];
    uint64_t lr;      // x30
    uint64_t elr_el1; // Exception Link Register (PC where exception occurred)
    uint64_t spsr_el1;// Saved Program Status Register
    uint64_t sp_el0;  // Saved Stack Pointer
    uint8_t  q[32][16]; // NEON / Floating-Point registers Q0-Q31
} __attribute__((packed)) trap_frame_t;

extern void virtio_gpu_flush_full(void);

static void bsod_draw_char(int x, int y, char c, uint32_t fg, uint32_t bg) {
    uint32_t *fb = gfx_get_backbuffer() ? gfx_get_backbuffer() : gfx_get_frontbuffer();
    if (!fb) return;
    uint32_t pitch = gfx_get_canvas_pitch() ? gfx_get_canvas_pitch() : 1024;
    if (c < 32 || c > 126) c = '?';
    const uint8_t *bitmap = font8x16_data[c - 32];
    for (int r = 0; r < 16; r++) {
        uint8_t row = bitmap[r];
        uint32_t *line = fb + (y + r) * pitch + x;
        for (int col = 0; col < 8; col++) {
            if (row & (0x80 >> col)) {
                line[col] = fg;
            } else if (bg != 0) {
                line[col] = bg;
            }
        }
    }
}

static void bsod_draw_string(int x, int y, const char *str, uint32_t fg, uint32_t bg) {
    int cx = x;
    while (*str) {
        if (*str == '\n') {
            y += 18;
            cx = x;
        } else {
            bsod_draw_char(cx, y, *str, fg, bg);
            cx += 8;
        }
        str++;
    }
}

void arm64_sync_exception(trap_frame_t *frame) {
    uint64_t esr, far;
    asm volatile("mrs %0, esr_el1" : "=r"(esr));
    asm volatile("mrs %0, far_el1" : "=r"(far));

    uint32_t ec = (esr >> 26) & 0x3F; // Exception Class
    uint32_t iss = esr & 0x01FFFFFF;  // Instruction Specific Syndrome

    const char *fault_name = "Unknown Abort";
    if (ec == 0x25) fault_name = "Data Abort (Memory access violation)";
    else if (ec == 0x21) fault_name = "Instruction Abort (Execution violation)";
    else if (ec == 0x26) fault_name = "SP Alignment Fault";
    else if (ec == 0x15) fault_name = "SVC Trap";
    else if (ec == 0x00) fault_name = "Undefined Instruction";

    // 1. Always dump full telemetry to UART MMIO
    printf("\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
    printf(" [CPU EXCEPTION] Synchronous Abort Trapped in Ring 0!\n");
    printf("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n");
    printf(" Exception Class (EC): 0x%02X | ISS: 0x%08X\n", ec, iss);
    printf(" Faulting PC (ELR_EL1):   0x%016llX\n", (unsigned long long)frame->elr_el1);
    printf(" Fault Address (FAR_EL1): 0x%016llX\n", (unsigned long long)far);
    printf(" Saved Status (SPSR_EL1): 0x%016llX\n", (unsigned long long)frame->spsr_el1);
    printf(" Fault Type: %s\n", fault_name);
    printf("\n--- REGISTERS DUMP ---\n");
    for (int i = 0; i < 30; i += 2) {
        printf(" X%02d: 0x%016llX   X%02d: 0x%016llX\n",
               i, (unsigned long long)frame->x[i],
               i+1, (unsigned long long)frame->x[i+1]);
    }
    printf(" X30 (LR): 0x%016llX\n", (unsigned long long)frame->lr);
    printf("--------------------------------------------------------\n\n");

    // 2. Sovereign Error Recovery Protocol:
    // Check if the fault occurred in userland HolyC code (inside the JIT code pool)
    if (jit_is_in_code_pool((void*)frame->elr_el1)) {
        printf("[BSOD RECOVERY] Fault inside HolyC JIT pool (0x%016llX). Recovering to Shell...\n",
               (unsigned long long)frame->elr_el1);

        // Flash an emergency recovery notification banner on the screen
        bsod_draw_string(24, 24, " [BSOD RECOVERED] HolyC Task Fault Unwound Successfully ", 0xFFFFFFFF, 0xFFE74C3C);
        gfx_swap_buffers();

        // Redirect exception return directly to shell_task_recover
        frame->elr_el1 = (uint64_t)shell_task_recover;
        return; // ERET returns to shell_task_recover with Ring 0 EL1 restored!
    }

    // 3. Core Kernel Panic (Unrecoverable C Substrate Crash)
    // Render full Royal Blue Screen (BSOD) directly to the framebuffer
    uint32_t *fb = gfx_get_backbuffer() ? gfx_get_backbuffer() : gfx_get_frontbuffer();
    uint32_t w = gfx_get_canvas_width() ? gfx_get_canvas_width() : 1024;
    uint32_t h = gfx_get_canvas_height() ? gfx_get_canvas_height() : 768;

    if (fb) {
        for (size_t p = 0; p < (size_t)w * h; p++) {
            fb[p] = 0xFF0000AA; // Royal Blue
        }

        char buf[128];
        bsod_draw_string(40, 40,  "*** NeoOS KERNEL PANIC (RING 0 AArch64 EL1) ***", 0xFFFFFFFF, 0xFF0000AA);
        bsod_draw_string(40, 70,  "A critical hardware exception occurred in the kernel substrate.", 0xFFFFFFFF, 0xFF0000AA);
        bsod_draw_string(40, 90,  "System execution halted to protect memory integrity.", 0xFFFFFFFF, 0xFF0000AA);

        snprintf(buf, sizeof(buf), "Fault Type: %s (EC: 0x%02X, ISS: 0x%08X)", fault_name, ec, iss);
        bsod_draw_string(40, 130, buf, 0xFFFFFF00, 0xFF0000AA);

        snprintf(buf, sizeof(buf), "ELR_EL1 (PC) : 0x%016llX", (unsigned long long)frame->elr_el1);
        bsod_draw_string(40, 160, buf, 0xFFFFFFFF, 0xFF0000AA);

        snprintf(buf, sizeof(buf), "FAR_EL1 (Addr): 0x%016llX", (unsigned long long)far);
        bsod_draw_string(40, 180, buf, 0xFFFFFFFF, 0xFF0000AA);

        snprintf(buf, sizeof(buf), "SPSR_EL1     : 0x%016llX", (unsigned long long)frame->spsr_el1);
        bsod_draw_string(40, 200, buf, 0xFFFFFFFF, 0xFF0000AA);

        bsod_draw_string(40, 230, "--- General Purpose Register State (X0 - X30) ---", 0xFF00FFFF, 0xFF0000AA);
        int y = 260;
        for (int i = 0; i < 30; i += 2) {
            snprintf(buf, sizeof(buf), "X%02d: 0x%016llX   X%02d: 0x%016llX",
                     i, (unsigned long long)frame->x[i],
                     i+1, (unsigned long long)frame->x[i+1]);
            bsod_draw_string(40, y, buf, 0xFFFFFFFF, 0xFF0000AA);
            y += 20;
        }
        snprintf(buf, sizeof(buf), "X30 (LR): 0x%016llX", (unsigned long long)frame->lr);
        bsod_draw_string(40, y, buf, 0xFFFFFFFF, 0xFF0000AA);

        bsod_draw_string(40, y + 40, "Telemetry successfully logged to UART. System halted safely.", 0xFFFFFFFF, 0xFF0000AA);

        gfx_swap_buffers();
        virtio_gpu_flush_full();
    }

    while (1) {
        asm volatile("wfe");
    }
}

void arm64_unhandled_abort(trap_frame_t *frame) {
    arm64_sync_exception(frame);
}
