#include "bench3d.h"
#include "../../gui/render.h"
#include "../../gui/wm.h"
#include "../arch/aarch64/smp.h"
#include "../arch/aarch64/timer.h"
#include <uefi.h>

static bench3d_instance_t inst_a;
static bench3d_instance_t inst_b;
static int bench3d_running = 0;
static uint32_t win_a_id = 0;
static uint32_t win_b_id = 0;

static inline uint64_t read_cntvct(void) {
    uint64_t val;
    asm volatile("mrs %0, cntvct_el0" : "=r"(val));
    return val;
}

static inline uint64_t read_cntfrq(void) {
    uint64_t val;
    asm volatile("mrs %0, cntfrq_el0" : "=r"(val));
    return (val > 0) ? val : 62500000ULL; // Default 62.5 MHz on QEMU ARM virt
}

// Background Worker for Core 1: Vector & Matrix Stress Test
static void worker_math_stress(void *arg) {
    bench3d_instance_t *inst = (bench3d_instance_t*)arg;
    mat4_t m1, m2, m3;
    mat4_identity(&m1);
    mat4_rotate_y(&m2, 45.0f);
    
    // Perform 3,000 matrix multiplications to stress the Cortex-A72 SIMD unit
    for (int i = 0; i < 3000; i++) {
        mat4_mul(&m3, &m1, &m2);
        m1 = m3;
    }
    inst->ops_accumulator += 3000;
    inst->compute_ready = 1;
}

// Background Worker for Core 2: Memory Bandwidth & Rasterizer Stress Test
static void worker_mem_stress(void *arg) {
    bench3d_instance_t *inst = (bench3d_instance_t*)arg;
    static volatile uint32_t test_block[2048];
    uint32_t val = (uint32_t)inst->frame_count;
    uint32_t read_sink = 0;
    
    // Memory write/read throughput loop (50 * 2048 * 4 = 409,600 bytes)
    for (int pass = 0; pass < 50; pass++) {
        for (int i = 0; i < 2048; i++) {
            test_block[i] = val + i;
            read_sink += test_block[i];
        }
    }
    (void)read_sink;
    inst->ops_accumulator += (50 * 2048 * sizeof(uint32_t));
    inst->compute_ready = 1;
}

void bench3d_init(void) {
    math3d_init();

    // Setup Viewport A (Left - Wireframe, Core 1)
    memset(&inst_a, 0, sizeof(inst_a));
    inst_a.core_id = 1;
    mesh3d_init_cube(&inst_a.cube, 2.0f);
    inst_a.angle_x = 25.0f;
    inst_a.angle_y = 35.0f;
    inst_a.angle_z = 10.0f;
    inst_a.speed_x = 2.0f;
    inst_a.speed_y = 3.0f;
    inst_a.speed_z = 1.0f;
    inst_a.theme_primary = COLOR_NEON_CYAN;
    inst_a.theme_accent  = COLOR_EMERALD_GREEN;
    inst_a.is_solid = 0;
    inst_a.fps = 60;

    // Setup Viewport B (Right - Solid Shaded, Core 2)
    memset(&inst_b, 0, sizeof(inst_b));
    inst_b.core_id = 2;
    mesh3d_init_cube(&inst_b.cube, 2.0f);
    inst_b.angle_x = 15.0f;
    inst_b.angle_y = 45.0f;
    inst_b.angle_z = 30.0f;
    inst_b.speed_x = 1.5f;
    inst_b.speed_y = 2.5f;
    inst_b.speed_z = 2.0f;
    inst_b.theme_primary = COLOR_BRIGHT_GOLD;
    inst_b.theme_accent  = COLOR_MAGENTA;
    inst_b.is_solid = 1;
    inst_b.fps = 60;
}

int bench3d_is_active(void) {
    return bench3d_running;
}

int bench3d_start(void) {
    if (bench3d_running) return 0;
    bench3d_init();

    // 1. Reposition Shell window (Window 1) to bottom tray/dock area
    window_t *shell_win = wm_get_window_by_id(1);
    if (shell_win) {
        shell_win->saved_x = shell_win->x;
        shell_win->saved_y = shell_win->y;
        shell_win->saved_w = shell_win->width;
        shell_win->saved_h = shell_win->height;

        shell_win->x = 20;
        shell_win->y = 475;
        shell_win->width = 984;
        shell_win->height = 245;
        doldoc_move(shell_win->x + 12, shell_win->y + 40, shell_win->width - 24, shell_win->height - 48);
    }

    // 2. Create Window A (Left): 3D Viewport A [Core 1]
    window_t *win_a = wm_create_window("3D Viewport A [Core 1] - Math Stress", 20, 20, 480, 440);
    if (win_a) {
        win_a_id = win_a->id;
        win_a->custom_render = bench3d_render_instance;
        win_a->user_data = &inst_a;
    }

    // 3. Create Window B (Right): 3D Viewport B [Core 2]
    zbuffer_init(&inst_b.zbuffer, 480, 440);
    window_t *win_b = wm_create_window("3D Viewport B [Core 2] - Fill-Rate & Solid", 524, 20, 480, 440);
    if (win_b) {
        win_b_id = win_b->id;
        win_b->custom_render = bench3d_render_instance;
        win_b->user_data = &inst_b;
    }

    bench3d_running = 1;
    return 1;
}

void bench3d_stop(void) {
    if (!bench3d_running) return;
    if (win_a_id) { wm_destroy_window(win_a_id); win_a_id = 0; }
    if (win_b_id) { wm_destroy_window(win_b_id); win_b_id = 0; }
    zbuffer_free(&inst_b.zbuffer);

    window_t *shell_win = wm_get_window_by_id(1);
    if (shell_win) {
        shell_win->x = shell_win->saved_x ? shell_win->saved_x : 132;
        shell_win->y = shell_win->saved_y ? shell_win->saved_y : 119;
        shell_win->width = shell_win->saved_w ? shell_win->saved_w : 760;
        shell_win->height = shell_win->saved_h ? shell_win->saved_h : 500;
        doldoc_move(shell_win->x + 12, shell_win->y + 40, shell_win->width - 24, shell_win->height - 48);
    }

    bench3d_running = 0;
}

void bench3d_update_instance(bench3d_instance_t *inst) {
    uint64_t start_cycles = read_cntvct();
    uint64_t freq = read_cntfrq();

    // 1. Advance rotation
    inst->angle_x += inst->speed_x;
    if (inst->angle_x >= 360.0f) inst->angle_x -= 360.0f;
    inst->angle_y += inst->speed_y;
    if (inst->angle_y >= 360.0f) inst->angle_y -= 360.0f;
    inst->angle_z += inst->speed_z;
    if (inst->angle_z >= 360.0f) inst->angle_z -= 360.0f;

    // 2. Build MVP Matrix
    mat4_t rx, ry, rz, rot_xy, model, view, proj, mv;
    mat4_rotate_x(&rx, inst->angle_x);
    mat4_rotate_y(&ry, inst->angle_y);
    mat4_rotate_z(&rz, inst->angle_z);
    mat4_mul(&rot_xy, &ry, &rx);
    mat4_mul(&model, &rz, &rot_xy);

    mat4_translate(&view, 0.0f, 0.0f, -4.5f);
    mat4_perspective(&proj, 60.0f, 1.15f, 0.1f, 100.0f);
    mat4_mul(&mv, &view, &model);
    mat4_mul(&inst->mvp, &proj, &mv);

    // 3. Dispatch parallel compute workload to target SMP core
    inst->compute_ready = 0;
    if (inst->core_id == 1) {
        if (!g_smp.jobs[1].pending) smp_dispatch(1, worker_math_stress, inst);
    } else {
        if (!g_smp.jobs[2].pending) smp_dispatch(2, worker_mem_stress, inst);
    }

    // 4. Update frame counter & FPS telemetry
    inst->frame_count++;
    inst->fps_counter++;
    uint64_t current_ticks = timer_get_ticks();
    if (current_ticks - inst->fps_timer_ticks >= 50) { // Update every 500ms
        uint64_t dt = current_ticks - inst->fps_timer_ticks;
        inst->fps = (uint32_t)((inst->fps_counter * 100ULL) / (dt > 0 ? dt : 1));
        if (inst->core_id == 1) {
            // Empirical matrix transforms per second: (ops * 100) / elapsed ticks
            inst->throughput_metric = (inst->ops_accumulator * 100ULL) / (dt > 0 ? dt : 1);
        } else {
            // Empirical memory write bandwidth in MB/s: ((bytes * 100) / elapsed ticks) / (1024 * 1024)
            inst->throughput_metric = ((inst->ops_accumulator * 100ULL) / (dt > 0 ? dt : 1)) / (1024 * 1024);
        }
        inst->ops_accumulator = 0;
        inst->fps_counter = 0;
        inst->fps_timer_ticks = current_ticks;
    }

    uint64_t end_cycles = read_cntvct();
    uint64_t elapsed_cycles = (end_cycles > start_cycles) ? (end_cycles - start_cycles) : 1000;
    inst->frame_time_us = (elapsed_cycles * 1000000ULL) / freq;
}

void bench3d_render_instance(window_t *win, void *user_data) {
    bench3d_instance_t *inst = (bench3d_instance_t*)user_data;
    if (!win || !inst) return;

    bench3d_update_instance(inst);

    int client_x = win->x + 2;
    int client_y = win->y + 36;
    int client_w = win->width - 4;
    int client_h = win->height - 38;

    // 1. Dark Viewport Canvas
    gfx_draw_rect(client_x, client_y, client_w, client_h, 0xFF181B1E);

    // Subtle 3D crosshair / grid background
    int mid_x = client_x + client_w / 2;
    int mid_y = client_y + client_h / 2;
    for (int gx = mid_x - 120; gx <= mid_x + 120; gx += 40) {
        gfx_draw_line_clipped(gx, mid_y - 120, gx, mid_y + 120, 0xFF22262B);
    }
    for (int gy = mid_y - 120; gy <= mid_y + 120; gy += 40) {
        gfx_draw_line_clipped(mid_x - 120, gy, mid_x + 120, gy, 0xFF22262B);
    }

    // 2. Render Cube (Wireframe vs Solid)
    if (!inst->is_solid) {
        mesh3d_render_wireframe(&inst->cube, &inst->mvp,
                                client_x, client_y + 25, client_w, client_h - 45,
                                inst->theme_primary, inst->theme_accent);
    } else {
        zbuffer_clear(&inst->zbuffer);
        vec3_t light = {0.6f, 0.8f, -1.0f};
        mesh3d_render_solid_zbuffered(&inst->cube, &inst->mvp,
                                      client_x, client_y + 25, client_w, client_h - 45,
                                      &inst->zbuffer, gfx_get_backbuffer(), gfx_get_canvas_pitch(),
                                      inst->theme_primary, light);
    }

    // 3. Telemetry HUD (Upper overlay inside window)
    int hud_y = client_y + 8;
    gfx_blend_rect(client_x + 10, hud_y, client_w - 20, 52, 0xCC111316);
    gfx_draw_rect(client_x + 10, hud_y, client_w - 20, 1, inst->theme_primary);

    char hud_line1[96];
    snprintf(hud_line1, sizeof(hud_line1), "FPS: %u | Core %u | Frame: %lluus | Ticks: %llu",
             inst->fps, inst->core_id, (unsigned long long)inst->frame_time_us,
             (unsigned long long)inst->frame_count);
    gfx_draw_string(client_x + 18, hud_y + 8, hud_line1, COLOR_TEXT_WHITE, 0);

    char hud_line2[96];
    if (inst->core_id == 1) {
        snprintf(hud_line2, sizeof(hud_line2), "Math Stress: %llu transforms/s [Cortex-A72 SIMD]",
                 (unsigned long long)inst->throughput_metric);
        gfx_draw_string(client_x + 18, hud_y + 28, hud_line2, COLOR_EMERALD_GREEN, 0);
    } else {
        snprintf(hud_line2, sizeof(hud_line2), "Fill-Rate: %llu MB/s | 16-bit Z-Buffer Scanline",
                 (unsigned long long)inst->throughput_metric);
        gfx_draw_string(client_x + 18, hud_y + 28, hud_line2, COLOR_BRIGHT_GOLD, 0);
    }

    // 4. Bottom status readout
    char bot_buf[80];
    snprintf(bot_buf, sizeof(bot_buf), "Rot: X=%d Y=%d Z=%d | %s",
             (int)inst->angle_x, (int)inst->angle_y, (int)inst->angle_z,
             inst->is_solid ? "Solid Shaded Mesh" : "Neon Wireframe Mesh");
    gfx_draw_string(client_x + 18, client_y + client_h - 22, bot_buf, COLOR_TEXT_MUTED, 0);
}
