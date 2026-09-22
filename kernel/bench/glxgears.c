#include "glxgears.h"
#include "../../gui/render.h"
#include "../../gui/wm.h"
#include "../../gui/menu.h"
#include "../../drivers/input/mouse.h"
#include "../arch/aarch64/timer.h"
#include "../arch/aarch64/smp.h"
#include <uefi.h>

extern void uart_puts(const char *s);

glxgears_state_t g_glxgears = {0};

static inline uint64_t read_cntvct(void) {
    uint64_t val;
    asm volatile("mrs %0, cntvct_el0" : "=r"(val));
    return val;
}

static inline uint64_t read_cntfrq(void) {
    uint64_t val;
    asm volatile("mrs %0, cntfrq_el0" : "=r"(val));
    return (val > 0) ? val : 62500000ULL;
}

void glxgears_init(void) {
    memset(&g_glxgears, 0, sizeof(g_glxgears));
    math3d_init();

    // Generate 3 Authentic GLXGears
    // Gear 1 (Red): 20 teeth, inner=1.0, outer=4.0, width=1.0, depth=0.7
    gear_generate(&g_glxgears.gear1, 1.0f, 4.0f, 1.0f, 20, 0.7f, 0xFFE74C3C);
    g_glxgears.gear1.pos = (vec3_t){-3.0f, -2.0f, 0.0f};

    // Gear 2 (Green): 10 teeth, inner=0.5, outer=2.0, width=2.0, depth=0.7
    gear_generate(&g_glxgears.gear2, 0.5f, 2.0f, 2.0f, 10, 0.7f, 0xFF2ECC71);
    g_glxgears.gear2.pos = (vec3_t){3.1f, -2.0f, 0.0f};

    // Gear 3 (Blue): 10 teeth, inner=1.3, outer=2.0, width=0.5, depth=0.7
    gear_generate(&g_glxgears.gear3, 1.3f, 2.0f, 0.5f, 10, 0.7f, 0xFF3498DB);
    g_glxgears.gear3.pos = (vec3_t){-3.1f, 4.2f, 0.0f};

    g_glxgears.view_rotx = 20.0f;
    g_glxgears.view_roty = 30.0f;
    g_glxgears.view_rotz = 0.0f;
    g_glxgears.gear_angle = 0.0f;
    strncpy(g_glxgears.fps_report, "Measuring real frame rates...", sizeof(g_glxgears.fps_report) - 1);
}

int glxgears_start(int wireframe, int smp_mode, int dual_mode) {
    if (g_glxgears.active) return 0;
    menu_close();
    glxgears_init();

    g_glxgears.wireframe = wireframe;
    g_glxgears.smp_mode = smp_mode;
    g_glxgears.is_dual = dual_mode;

    // Reposition Shell to lower tray so both viewports and shell remain visible
    window_t *shell_win = wm_get_window_by_id(1);
    if (shell_win) {
        shell_win->saved_x = shell_win->x;
        shell_win->saved_y = shell_win->y;
        shell_win->saved_w = shell_win->width;
        shell_win->saved_h = shell_win->height;
        shell_win->x = 20;
        shell_win->y = 480;
        shell_win->width = 984;
        shell_win->height = 240;
        doldoc_move(shell_win->x + 12, shell_win->y + 40, shell_win->width - 24, shell_win->height - 48);
    }

    if (!dual_mode) {
        zbuffer_init(&g_glxgears.zbuffer, 640, 420);
        window_t *win = wm_create_window("NeoGears 3D - Authentic GLXGears (Ring 0 SASOS)", 190, 20, 644, 442);
        if (win) {
            g_glxgears.win_id = win->id;
            win->custom_render = glxgears_render_viewport;
            win->user_data = (void*)0;
        }
    } else {
        zbuffer_init(&g_glxgears.zbuffer, 480, 420);
        zbuffer_init(&g_glxgears.zbuffer_b, 480, 420);

        window_t *win_a = wm_create_window("GLXGears Viewport A [SMP Core 1]", 20, 20, 484, 442);
        if (win_a) {
            g_glxgears.win_id = win_a->id;
            win_a->custom_render = glxgears_render_viewport;
            win_a->user_data = (void*)0;
        }

        window_t *win_b = wm_create_window("GLXGears Viewport B [SMP Core 2]", 520, 20, 484, 442);
        if (win_b) {
            g_glxgears.win_b_id = win_b->id;
            win_b->custom_render = glxgears_render_viewport;
            win_b->user_data = (void*)1;
        }
    }

    g_glxgears.active = 1;
    g_glxgears.total_frames = 0;
    g_glxgears.period_frames = 0;
    g_glxgears.period_start_ticks = timer_get_ticks();
    g_glxgears.measured_fps = 0.0f;

    uart_puts("[GLXGEARS] Started authentic 3D gears benchmark.\r\n");
    return 1;
}

void glxgears_stop(void) {
    if (!g_glxgears.active) return;

    if (g_glxgears.win_id) { wm_destroy_window(g_glxgears.win_id); g_glxgears.win_id = 0; }
    if (g_glxgears.win_b_id) { wm_destroy_window(g_glxgears.win_b_id); g_glxgears.win_b_id = 0; }

    zbuffer_free(&g_glxgears.zbuffer);
    zbuffer_free(&g_glxgears.zbuffer_b);

    window_t *shell_win = wm_get_window_by_id(1);
    if (shell_win) {
        shell_win->x = shell_win->saved_x ? shell_win->saved_x : 132;
        shell_win->y = shell_win->saved_y ? shell_win->saved_y : 119;
        shell_win->width = shell_win->saved_w ? shell_win->saved_w : 760;
        shell_win->height = shell_win->saved_h ? shell_win->saved_h : 500;
        doldoc_move(shell_win->x + 12, shell_win->y + 40, shell_win->width - 24, shell_win->height - 48);
    }

    g_glxgears.active = 0;
    uart_puts("[GLXGEARS] Benchmark stopped.\r\n");
}

int glxgears_is_active(void) {
    return g_glxgears.active;
}

void glxgears_render_viewport(window_t *win, void *user_data) {
    if (!win || !g_glxgears.active) return;

    int is_primary = (user_data == (void*)0);
    zbuffer_t *zb = is_primary ? &g_glxgears.zbuffer : &g_glxgears.zbuffer_b;

    uint64_t start_vct = read_cntvct();
    uint64_t freq = read_cntfrq();

    int client_x = win->x + 2;
    int client_y = win->y + 36;
    int client_w = win->width - 4;
    int client_h = win->height - 38;

    // 1. Mouse Drag Camera Interaction
    mouse_state_t ms = mouse_get_state();
    if (ms.x >= client_x && ms.x < client_x + client_w &&
        ms.y >= client_y && ms.y < client_y + client_h) {
        if (ms.left_button) {
            if (!g_glxgears.dragging) {
                g_glxgears.dragging = 1;
                g_glxgears.last_mouse_x = ms.x;
                g_glxgears.last_mouse_y = ms.y;
            } else {
                int dx = ms.x - g_glxgears.last_mouse_x;
                int dy = ms.y - g_glxgears.last_mouse_y;
                g_glxgears.view_roty += (float)dx * 0.6f;
                g_glxgears.view_rotx += (float)dy * 0.6f;
                g_glxgears.last_mouse_x = ms.x;
                g_glxgears.last_mouse_y = ms.y;
            }
        } else {
            g_glxgears.dragging = 0;
        }
    } else {
        g_glxgears.dragging = 0;
    }

    // 2. Advance Gear Angles (Synchronized Gear Ratios)
    if (is_primary) {
        g_glxgears.gear_angle += 2.0f;
        if (g_glxgears.gear_angle >= 360.0f) g_glxgears.gear_angle -= 360.0f;
    }

    g_glxgears.gear1.angle = g_glxgears.gear_angle;
    g_glxgears.gear2.angle = -2.0f * g_glxgears.gear_angle - 9.0f;
    g_glxgears.gear3.angle = -2.0f * g_glxgears.gear_angle - 25.0f;

    // 3. Clear Viewport and Z-Buffer
    gfx_draw_rect(client_x, client_y, client_w, client_h, 0xFF14171A);
    zbuffer_clear(zb);

    // 4. Build View-Projection Pipeline
    mat4_t proj, view, rx, ry, rz, rot_tmp, vp;
    mat4_perspective(&proj, 42.0f, (float)client_w / (float)client_h, 1.0f, 100.0f);
    mat4_translate(&view, 0.0f, 0.0f, -18.5f);

    float p_rotx = is_primary ? g_glxgears.view_rotx : (g_glxgears.view_rotx + 15.0f);
    float p_roty = is_primary ? g_glxgears.view_roty : (g_glxgears.view_roty - 20.0f);

    mat4_rotate_x(&rx, p_rotx);
    mat4_rotate_y(&ry, p_roty);
    mat4_rotate_z(&rz, g_glxgears.view_rotz);
    mat4_mul(&rot_tmp, &ry, &rx);
    mat4_mul(&rot_tmp, &rz, &rot_tmp);
    mat4_mul(&view, &view, &rot_tmp);
    mat4_mul(&vp, &proj, &view);

    // 5. Render 3 Interlocking 3D Gears
    gear_render(&g_glxgears.gear1, &vp, client_x, client_y, client_w, client_h, zb, g_glxgears.wireframe);
    gear_render(&g_glxgears.gear2, &vp, client_x, client_y, client_w, client_h, zb, g_glxgears.wireframe);
    gear_render(&g_glxgears.gear3, &vp, client_x, client_y, client_w, client_h, zb, g_glxgears.wireframe);

    // 6. Empirical Hardware Latency Calculation
    uint64_t end_vct = read_cntvct();
    uint64_t elapsed_cycles = (end_vct > start_vct) ? (end_vct - start_vct) : 1000;
    g_glxgears.frame_time_us = (elapsed_cycles * 1000000ULL) / freq;

    // 7. Empirical Hardware Timer Framerate Calculation
    if (is_primary) {
        g_glxgears.total_frames++;
        g_glxgears.period_frames++;
        uint64_t now_ticks = timer_get_ticks();
        uint64_t elapsed_ticks = now_ticks - g_glxgears.period_start_ticks;

        // Periodic Mesa-style Report every 100 ticks (1.0s real time)
        if (elapsed_ticks >= 100) {
            uint32_t fps_x100 = (uint32_t)((g_glxgears.period_frames * 10000ULL) / (elapsed_ticks > 0 ? elapsed_ticks : 1));
            uint32_t sec_x10 = (uint32_t)((elapsed_ticks * 10ULL) / 100ULL);
            g_glxgears.measured_fps = (float)fps_x100 / 100.0f;
            snprintf(g_glxgears.fps_report, sizeof(g_glxgears.fps_report),
                     "%llu frames in %u.%u seconds = %u.%02u FPS (Real Time)",
                     (unsigned long long)g_glxgears.period_frames,
                     sec_x10 / 10, sec_x10 % 10,
                     fps_x100 / 100, fps_x100 % 100);
            
            char serial_log[160];
            snprintf(serial_log, sizeof(serial_log), "[GLXGEARS] %s\r\n", g_glxgears.fps_report);
            uart_puts(serial_log);

            g_glxgears.period_frames = 0;
            g_glxgears.period_start_ticks = now_ticks;
        }
    }

    // 8. Draw Authentic Telemetry HUD
    int hud_y = client_y + 8;
    gfx_blend_rect(client_x + 10, hud_y, client_w - 20, 50, 0xDD101316);
    gfx_draw_rect(client_x + 10, hud_y, client_w - 20, 1, COLOR_ACCENT_CYAN);

    char line1[128];
    snprintf(line1, sizeof(line1), "GLXGears: Red (20T), Green (10T), Blue (10T) | %s",
             g_glxgears.wireframe ? "Wireframe" : (g_glxgears.is_dual ? "Dual SMP" : "Z-Buffer Lit"));
    gfx_draw_string(client_x + 18, hud_y + 6, line1, COLOR_TEXT_WHITE, 0);

    uint32_t fps_disp_x100;
    if (g_glxgears.measured_fps > 0.01f) {
        fps_disp_x100 = (uint32_t)(g_glxgears.measured_fps * 100.0f);
    } else {
        uint64_t now_ticks = timer_get_ticks();
        uint64_t el_t = now_ticks - g_glxgears.period_start_ticks;
        fps_disp_x100 = (uint32_t)((g_glxgears.period_frames * 10000ULL) / (el_t > 0 ? el_t : 1));
    }

    char line2[128];
    snprintf(line2, sizeof(line2), "FPS: %u.%02u (Real Measured) | Latency: %llums | Total: %llu frames",
             fps_disp_x100 / 100, fps_disp_x100 % 100,
             (unsigned long long)(g_glxgears.frame_time_us / 1000ULL),
             (unsigned long long)g_glxgears.total_frames);
    gfx_draw_string(client_x + 18, hud_y + 26, line2, COLOR_NEON_CYAN, 0);
}
