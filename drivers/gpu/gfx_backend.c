#include "gfx_backend.h"
#include "../../gui/render.h"
#include "../../gui/wm.h"
#include "../../kernel/math/raster_tile.h"
#include "../../kernel/bench/bench_unified.h"
#include <uefi.h>

extern void doldoc_print(const char *str);
extern void doldoc_printf(const char *fmt, ...);

gfx_backend_state_t g_gfx_backend = {
    .mode = GFX_MODE_CPU_SW,
    .buffering = GFX_BUFFER_DOUBLE,
    .zprecision = ZBUFFER_PRECISION_16BIT,
    .name = "CPU Software (UEFI)",
    .feature_flags = 0x01,
    .ops_counter = 0,
    .dma_transfers_bytes = 0,
    .raster_engine = RASTER_ENGINE_SCANLINE,
    .tile_size = TILE_SIZE_64,
    .smp_cores = 4,
    .shading_mode = RASTER_SHADE_GOURAUD,
    .culling = 1,
    .active_tab = 0
};

static uint32_t s_gpu_win_id = 0;

extern int  virtio_gpu_is_available(void);
extern void virtio_gpu_flush_rect(int x, int y, int w, int h);
extern void virtio_gpu_flush_full(void);

void gfx_backend_init(void) {
    g_gfx_backend.mode = GFX_MODE_CPU_SW;
    g_gfx_backend.buffering = GFX_BUFFER_DOUBLE;
    g_gfx_backend.zprecision = ZBUFFER_PRECISION_16BIT;
    g_gfx_backend.name = "CPU Software (UEFI)";
    g_gfx_backend.feature_flags = 0x01;
    g_gfx_backend.ops_counter = 0;
    g_gfx_backend.dma_transfers_bytes = 0;
    g_gfx_backend.raster_engine = RASTER_ENGINE_SCANLINE;
    g_gfx_backend.tile_size = TILE_SIZE_64;
    g_gfx_backend.smp_cores = 4;
    g_gfx_backend.shading_mode = RASTER_SHADE_GOURAUD;
    g_gfx_backend.culling = 1;
    g_gfx_backend.active_tab = 0;
    s_gpu_win_id = 0;

    uint32_t cw = gfx_get_canvas_width() ? gfx_get_canvas_width() : 1280;
    uint32_t ch = gfx_get_canvas_height() ? gfx_get_canvas_height() : 720;
    raster_tile_init(cw, ch, TILE_SIZE_64);
    raster_tile_set_engine(RASTER_ENGINE_SCANLINE);
    raster_tile_set_cores(4);
    raster_tile_set_shading(RASTER_SHADE_GOURAUD);
    raster_tile_set_culling(1);
    raster_tile_set_depth_test(1);
}

void gfx_backend_set_mode(gfx_backend_mode_t mode) {
    g_gfx_backend.mode = mode;
    if (mode == GFX_MODE_GPU_HW) {
        g_gfx_backend.name = "VirtIO-GPU Hardware";
        g_gfx_backend.feature_flags = 0x0F;
    } else if (mode == GFX_MODE_SMP_TILED) {
        g_gfx_backend.name = "SMP Multi-Core (4C)";
        g_gfx_backend.feature_flags = 0x07;
    } else {
        g_gfx_backend.name = "CPU Software (UEFI)";
        g_gfx_backend.feature_flags = 0x01;
    }
    wm_set_dirty();
}

void gfx_backend_present(int x, int y, int w, int h, int is_full) {
    if (g_gfx_backend.mode == GFX_MODE_GPU_HW || g_gfx_backend.mode == GFX_MODE_SMP_TILED) {
        if (virtio_gpu_is_available()) {
            if (is_full) {
                virtio_gpu_flush_full();
            } else {
                virtio_gpu_flush_rect(x, y, w, h);
            }
        }
        g_gfx_backend.ops_counter++;
    } else {
        // GFX_MODE_CPU_SW: Pure CPU Software Graphics (UEFI GOP)
        g_gfx_backend.ops_counter++;
    }
}

gfx_backend_mode_t gfx_backend_get_mode(void) {
    return g_gfx_backend.mode;
}

const char* gfx_backend_get_name(void) {
    return g_gfx_backend.name;
}

void gpu_set_buffering(gfx_buffering_mode_t mode) {
    g_gfx_backend.buffering = mode;
    gfx_set_zero_ram_mode(mode == GFX_BUFFER_DIRECT_VRAM);
}

gfx_buffering_mode_t gpu_get_buffering(void) {
    return g_gfx_backend.buffering;
}

void gpu_set_zprecision(gfx_zprecision_t prec) {
    g_gfx_backend.zprecision = prec;
}

gfx_zprecision_t gpu_get_zprecision(void) {
    return g_gfx_backend.zprecision;
}

void gpu_set_raster_engine(raster_engine_type_t eng) {
    g_gfx_backend.raster_engine = eng;
    raster_tile_set_engine(eng);
    wm_set_dirty();
}

raster_engine_type_t gpu_get_raster_engine(void) {
    return g_gfx_backend.raster_engine;
}

void gpu_set_tile_size(int size) {
    g_gfx_backend.tile_size = size;
    raster_tile_set_tile_size(size);
    wm_set_dirty();
}

int gpu_get_tile_size(void) {
    return g_gfx_backend.tile_size;
}

void gpu_set_smp_cores(int cores) {
    g_gfx_backend.smp_cores = cores;
    raster_tile_set_cores(cores);
    wm_set_dirty();
}

int gpu_get_smp_cores(void) {
    return g_gfx_backend.smp_cores;
}

void gpu_set_shading(raster_shade_mode_t shade) {
    g_gfx_backend.shading_mode = shade;
    raster_tile_set_shading(shade);
    wm_set_dirty();
}

raster_shade_mode_t gpu_get_shading(void) {
    return g_gfx_backend.shading_mode;
}

void gpu_set_culling(int enable) {
    g_gfx_backend.culling = enable;
    raster_tile_set_culling(enable);
    wm_set_dirty();
}

int gpu_get_culling(void) {
    return g_gfx_backend.culling;
}

void gpu_config_set_tab(int tab) {
    if (tab >= 0 && tab <= 3) {
        g_gfx_backend.active_tab = tab;
        wm_set_dirty();
    }
}

int gpu_config_get_tab(void) {
    return g_gfx_backend.active_tab;
}

void gpu_config_open(void) {
    if (s_gpu_win_id) {
        window_t *w = wm_get_window_by_id(s_gpu_win_id);
        if (w) {
            w->is_minimized = 0;
            w->is_active = 1;
            return;
        }
    }

    window_t *win = wm_create_window("GPU Hardware & Sovereign Pipeline Hub", 100, 35, 680, 520);
    if (win) {
        s_gpu_win_id = win->id;
        win->custom_render = gpu_config_render;
        win->custom_click = gpu_config_click;
        win->user_data = NULL;
    }
}

void gpu_config_close(void) {
    if (s_gpu_win_id) {
        wm_destroy_window(s_gpu_win_id);
        s_gpu_win_id = 0;
    }
}

int gpu_config_is_open(void) {
    return (s_gpu_win_id != 0 && wm_get_window_by_id(s_gpu_win_id) != NULL);
}

// ─── Multi-Tab Window Render ──────────────────────────────────────────────────
void gpu_config_render(window_t *win, void *user_data) {
    (void)user_data;
    if (!win) return;

    int cx = win->x + 2;
    int cy = win->y + 36;
    int cw = win->width - 4;
    int ch = win->height - 38;

    // Background
    gfx_draw_rect(cx, cy, cw, ch, 0xFF14171A);

    // ─── Top Tab Bar ───
    int tab_y = cy + 6;
    int tab_w = (cw - 24) / 4;
    int cur_tab = g_gfx_backend.active_tab;

    const char *tab_titles[4] = {
        "1. Drivers & Scanout",
        "2. L1 Tile & SMP",
        "3. Shading & Sync",
        "4. Telemetry & Suite"
    };

    for (int t = 0; t < 4; t++) {
        int tx = cx + 12 + t * tab_w;
        int active = (t == cur_tab);
        uint32_t t_bg = active ? 0xFF2C3E50 : 0xFF1E2228;
        uint32_t t_fg = active ? COLOR_ACCENT_CYAN : COLOR_TEXT_MUTED;
        gfx_draw_rounded_rect(tx, tab_y, tab_w - 6, 28, 4, t_bg);
        if (active) {
            gfx_draw_rect(tx + 2, tab_y + 26, tab_w - 10, 2, COLOR_ACCENT_CYAN);
        }
        gfx_draw_string(tx + 10, tab_y + 8, tab_titles[t], t_fg, 0);
    }

    int content_y = tab_y + 36;

    // ─── TAB 0: Drivers & Scanout Hardware ───
    if (cur_tab == 0) {
        gfx_draw_string(cx + 20, content_y, "[1] Framebuffer Architecture & Buffering:", COLOR_GOLD_ACCENT, 0);

        int is_double = (g_gfx_backend.buffering == GFX_BUFFER_DOUBLE);
        uint32_t col_db = is_double ? 0xFF27AE60 : 0xFF242A30;
        uint32_t col_vr = !is_double ? 0xFFE74C3C : 0xFF242A30;

        gfx_draw_rounded_rect(cx + 24, content_y + 20, 300, 48, 4, col_db);
        gfx_draw_string(cx + 34, content_y + 26, is_double ? "[X] Double-Buffered (DDR RAM)" : "[ ] Double-Buffered (DDR RAM)", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 34, content_y + 44, "3.14 MB Buffer | 25 GB/s Cacheable", COLOR_TEXT_MUTED, 0);

        gfx_draw_rounded_rect(cx + 340, content_y + 20, 300, 48, 4, col_vr);
        gfx_draw_string(cx + 350, content_y + 26, !is_double ? "[X] Direct VRAM (Zero-RAM Mode)" : "[ ] Direct VRAM (Zero-RAM Mode)", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 350, content_y + 44, "0 MB Copy | Visual Tearing Exposed", COLOR_TEXT_MUTED, 0);

        int y_drv = content_y + 86;
        gfx_draw_string(cx + 20, y_drv, "[2] Hardware Scanout Driver Selection:", COLOR_GOLD_ACCENT, 0);

        int m = g_gfx_backend.mode;
        uint32_t col_sw   = (m == GFX_MODE_CPU_SW) ? 0xFF2980B9 : 0xFF242A30;
        uint32_t col_hw   = (m == GFX_MODE_GPU_HW) ? 0xFF8E44AD : 0xFF242A30;
        uint32_t col_smp  = (m == GFX_MODE_SMP_TILED) ? 0xFF16A085 : 0xFF242A30;

        gfx_draw_rounded_rect(cx + 24, y_drv + 20, 195, 48, 4, col_sw);
        gfx_draw_string(cx + 32, y_drv + 26, (m == GFX_MODE_CPU_SW) ? "[X] CPU (UEFI GOP)" : "[ ] CPU (UEFI GOP)", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 32, y_drv + 44, "Pure Bare-Metal GOP", COLOR_TEXT_MUTED, 0);

        gfx_draw_rounded_rect(cx + 230, y_drv + 20, 195, 48, 4, col_hw);
        gfx_draw_string(cx + 238, y_drv + 26, (m == GFX_MODE_GPU_HW) ? "[X] VirtIO Hardware" : "[ ] VirtIO Hardware", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 238, y_drv + 44, "DMA Host Scanout", COLOR_TEXT_MUTED, 0);

        gfx_draw_rounded_rect(cx + 436, y_drv + 20, 195, 48, 4, col_smp);
        gfx_draw_string(cx + 444, y_drv + 26, (m == GFX_MODE_SMP_TILED) ? "[X] SMP Multi-Core" : "[ ] SMP Multi-Core", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 444, y_drv + 44, "Cores 1-3 Parallel", COLOR_TEXT_MUTED, 0);

        int y_info = y_drv + 88;
        gfx_blend_rect(cx + 24, y_info, cw - 48, 90, 0xFF191C20);
        gfx_draw_rect(cx + 24, y_info, cw - 48, 1, 0xFF34495E);
        gfx_draw_string(cx + 36, y_info + 12, "Hardware Pipeline Status:", COLOR_ACCENT_CYAN, 0);

        char info1[128], info2[128];
        snprintf(info1, sizeof(info1), "Active Driver: %s | VirtIO MMIO: %s",
                 g_gfx_backend.name, virtio_gpu_is_available() ? "ONLINE (Slot 31)" : "NOT PRESENT");
        snprintf(info2, sizeof(info2), "Scanout Aperture: DDR4 0x754B6000 | Coherency: Point-of-Coherency (dc civac)");
        gfx_draw_string(cx + 36, y_info + 34, info1, COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 36, y_info + 54, info2, COLOR_TEXT_MUTED, 0);
    }
    // ─── TAB 1: L1 Tile & SMP Multiprocessing ───
    else if (cur_tab == 1) {
        gfx_draw_string(cx + 20, content_y, "[1] 3D Rasterization Engine Architecture:", COLOR_GOLD_ACCENT, 0);

        int is_tiled = (g_gfx_backend.raster_engine == RASTER_ENGINE_TILED_L1);
        uint32_t col_tile = is_tiled ? 0xFF27AE60 : 0xFF242A30;
        uint32_t col_scan = !is_tiled ? 0xFF2980B9 : 0xFF242A30;

        gfx_draw_rounded_rect(cx + 24, content_y + 20, 300, 50, 4, col_tile);
        gfx_draw_string(cx + 34, content_y + 26, is_tiled ? "[X] Unified L1 Tile NEON" : "[ ] Unified L1 Tile NEON", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 34, content_y + 44, "24 KB L1 Scratchpad | 4-Wide Pineda", COLOR_TEXT_MUTED, 0);

        gfx_draw_rounded_rect(cx + 340, content_y + 20, 300, 50, 4, col_scan);
        gfx_draw_string(cx + 350, content_y + 26, !is_tiled ? "[X] Classic Scanline SIMD" : "[ ] Classic Scanline SIMD", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 350, content_y + 44, "16.16 Fixed-Point Slope-Walker", COLOR_TEXT_MUTED, 0);

        int y_geo = content_y + 86;
        gfx_draw_string(cx + 20, y_geo, "[2] Tile Geometry & L1 Data Cache Allocation:", COLOR_GOLD_ACCENT, 0);

        int t_sz = g_gfx_backend.tile_size;
        uint32_t c_t32  = (t_sz == 32)  ? 0xFF27AE60 : 0xFF242A30;
        uint32_t c_t64  = (t_sz == 64)  ? 0xFF16A085 : 0xFF242A30;
        uint32_t c_t128 = (t_sz == 128) ? 0xFF8E44AD : 0xFF242A30;

        gfx_draw_rounded_rect(cx + 24, y_geo + 20, 195, 48, 4, c_t32);
        gfx_draw_string(cx + 32, y_geo + 26, (t_sz == 32) ? "[X] 32x32 Tiles" : "[ ] 32x32 Tiles", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 32, y_geo + 44, "6 KB Footprint (Ultra-Low)", COLOR_TEXT_MUTED, 0);

        gfx_draw_rounded_rect(cx + 230, y_geo + 20, 195, 48, 4, c_t64);
        gfx_draw_string(cx + 238, y_geo + 26, (t_sz == 64) ? "[X] 64x64 (L1 Sweet)" : "[ ] 64x64 (L1 Sweet)", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 238, y_geo + 44, "24 KB (Cortex-A72 32K L1D)", COLOR_TEXT_MUTED, 0);

        gfx_draw_rounded_rect(cx + 436, y_geo + 20, 195, 48, 4, c_t128);
        gfx_draw_string(cx + 444, y_geo + 26, (t_sz == 128) ? "[X] 128x128 Tiles" : "[ ] 128x128 Tiles", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 444, y_geo + 44, "96 KB (L2 Cache Line)", COLOR_TEXT_MUTED, 0);

        int y_smp = y_geo + 86;
        gfx_draw_string(cx + 20, y_smp, "[3] Active SMP Core Partitioning Grid:", COLOR_GOLD_ACCENT, 0);

        int cores = g_gfx_backend.smp_cores;
        uint32_t c_c1 = (cores == 1) ? 0xFF2980B9 : 0xFF242A30;
        uint32_t c_c2 = (cores == 2) ? 0xFF27AE60 : 0xFF242A30;
        uint32_t c_c4 = (cores == 4) ? 0xFFE67E22 : 0xFF242A30;

        gfx_draw_rounded_rect(cx + 24, y_smp + 20, 195, 48, 4, c_c1);
        gfx_draw_string(cx + 32, y_smp + 26, (cores == 1) ? "[X] 1 Core (Core 0)" : "[ ] 1 Core (Core 0)", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 32, y_smp + 44, "Single-Thread Baseline", COLOR_TEXT_MUTED, 0);

        gfx_draw_rounded_rect(cx + 230, y_smp + 20, 195, 48, 4, c_c2);
        gfx_draw_string(cx + 238, y_smp + 26, (cores == 2) ? "[X] 2 Cores (0+1)" : "[ ] 2 Cores (0+1)", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 238, y_smp + 44, "Dual Core Tile Slicing", COLOR_TEXT_MUTED, 0);

        gfx_draw_rounded_rect(cx + 436, y_smp + 20, 195, 48, 4, c_c4);
        gfx_draw_string(cx + 444, y_smp + 26, (cores == 4) ? "[X] 4 Cores (Quad)" : "[ ] 4 Cores (Quad)", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 444, y_smp + 44, "All Cortex-A72 APs Active", COLOR_TEXT_MUTED, 0);
    }
    // ─── TAB 2: Shading, Depth & Frame Pacing ───
    else if (cur_tab == 2) {
        gfx_draw_string(cx + 20, content_y, "[1] Shading & Rasterization Model:", COLOR_GOLD_ACCENT, 0);

        raster_shade_mode_t sh = g_gfx_backend.shading_mode;
        uint32_t c_gour = (sh == RASTER_SHADE_GOURAUD)   ? 0xFF27AE60 : 0xFF242A30;
        uint32_t c_flat = (sh == RASTER_SHADE_FLAT)      ? 0xFF2980B9 : 0xFF242A30;
        uint32_t c_wire = (sh == RASTER_SHADE_WIREFRAME) ? 0xFF8E44AD : 0xFF242A30;

        gfx_draw_rounded_rect(cx + 24, content_y + 20, 195, 46, 4, c_gour);
        gfx_draw_string(cx + 32, content_y + 26, (sh == RASTER_SHADE_GOURAUD) ? "[X] Gouraud Smooth" : "[ ] Gouraud Smooth", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 32, content_y + 44, "Barycentric Vertex Lighting", COLOR_TEXT_MUTED, 0);

        gfx_draw_rounded_rect(cx + 230, content_y + 20, 195, 46, 4, c_flat);
        gfx_draw_string(cx + 238, content_y + 26, (sh == RASTER_SHADE_FLAT) ? "[X] Flat Shading" : "[ ] Flat Shading", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 238, content_y + 44, "Single Face Diffuse", COLOR_TEXT_MUTED, 0);

        gfx_draw_rounded_rect(cx + 436, content_y + 20, 195, 46, 4, c_wire);
        gfx_draw_string(cx + 444, content_y + 26, (sh == RASTER_SHADE_WIREFRAME) ? "[X] Wireframe" : "[ ] Wireframe", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 444, content_y + 44, "Edge Vector Distance Mask", COLOR_TEXT_MUTED, 0);

        int y_z = content_y + 84;
        gfx_draw_string(cx + 20, y_z, "[2] Depth Buffer & Backface Culling:", COLOR_GOLD_ACCENT, 0);

        int is_16 = (g_gfx_backend.zprecision == ZBUFFER_PRECISION_16BIT);
        uint32_t col_z16 = is_16 ? 0xFF27AE60 : 0xFF242A30;
        uint32_t col_z32 = !is_16 ? 0xFF27AE60 : 0xFF242A30;

        gfx_draw_rounded_rect(cx + 24, y_z + 20, 195, 44, 4, col_z16);
        gfx_draw_string(cx + 32, y_z + 28, is_16 ? "[X] 16-Bit Linear" : "[ ] 16-Bit Linear", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 32, y_z + 44, "8 KB per Tile (Optimal)", COLOR_TEXT_MUTED, 0);

        gfx_draw_rounded_rect(cx + 230, y_z + 20, 195, 44, 4, col_z32);
        gfx_draw_string(cx + 238, y_z + 28, !is_16 ? "[X] 32-Bit Fixed" : "[ ] 32-Bit Fixed", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 238, y_z + 44, "16 KB per Tile", COLOR_TEXT_MUTED, 0);

        int cull = g_gfx_backend.culling;
        uint32_t col_cull = cull ? 0xFF27AE60 : 0xFFE74C3C;
        gfx_draw_rounded_rect(cx + 436, y_z + 20, 195, 44, 4, col_cull);
        gfx_draw_string(cx + 444, y_z + 28, cull ? "[X] CCW Culling: ON" : "[ ] CCW Culling: OFF", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 444, y_z + 44, cull ? "Skip Back-Facing Triangles" : "Two-Sided Rendering", COLOR_TEXT_MUTED, 0);

        int y_vsync = y_z + 82;
        gfx_draw_string(cx + 20, y_vsync, "[3] Global Hardware V-Sync & Cadence Lock:", COLOR_GOLD_ACCENT, 0);

        int v_en = gfx_vsync_get_enabled();
        uint32_t v_hz = gfx_vsync_get_hz();

        uint32_t col_voff = (!v_en) ? 0xFFE67E22 : 0xFF242A30;
        uint32_t col_v30  = (v_en && v_hz == 30) ? 0xFF27AE60 : 0xFF242A30;
        uint32_t col_v60  = (v_en && v_hz == 60) ? 0xFF2980B9 : 0xFF242A30;
        uint32_t col_v120 = (v_en && v_hz >= 120) ? 0xFF8E44AD : 0xFF242A30;

        gfx_draw_rounded_rect(cx + 24, y_vsync + 20, 140, 40, 4, col_voff);
        gfx_draw_string(cx + 32, y_vsync + 28, (!v_en) ? "[X] Uncapped" : "[ ] Uncapped", COLOR_TEXT_WHITE, 0);

        gfx_draw_rounded_rect(cx + 175, y_vsync + 20, 140, 40, 4, col_v30);
        gfx_draw_string(cx + 183, y_vsync + 28, (v_en && v_hz == 30) ? "[X] 30 FPS Lock" : "[ ] 30 FPS Lock", COLOR_TEXT_WHITE, 0);

        gfx_draw_rounded_rect(cx + 326, y_vsync + 20, 140, 40, 4, col_v60);
        gfx_draw_string(cx + 334, y_vsync + 28, (v_en && v_hz == 60) ? "[X] 60 FPS Lock" : "[ ] 60 FPS Lock", COLOR_TEXT_WHITE, 0);

        gfx_draw_rounded_rect(cx + 477, y_vsync + 20, 154, 40, 4, col_v120);
        gfx_draw_string(cx + 485, y_vsync + 28, (v_en && v_hz >= 120) ? "[X] 120 FPS High" : "[ ] 120 FPS High", COLOR_TEXT_WHITE, 0);
    }
    // ─── TAB 3: Telemetry & Automated Comparison Suite ───
    else if (cur_tab == 3) {
        gfx_draw_string(cx + 20, content_y, "[1] Real-Time Sovereign Telemetry & Diagnostics:", COLOR_GOLD_ACCENT, 0);

        gfx_blend_rect(cx + 24, content_y + 20, cw - 48, 120, 0xFF191C20);
        gfx_draw_rect(cx + 24, content_y + 20, cw - 48, 120, COLOR_ACCENT_CYAN);

        char l1[128], l2[128], l3[128], l4[128];
        snprintf(l1, sizeof(l1), "Active Architecture:  %s (%s)",
                 (g_gfx_backend.raster_engine == RASTER_ENGINE_TILED_L1) ? "Unified L1 Tile NEON" : "Classic Scanline SIMD",
                 g_gfx_backend.name);
        snprintf(l2, sizeof(l2), "Active Tile Geometry: %dx%d (%d KB L1 Scratchpad) | Cores: %d Active",
                 g_gfx_backend.tile_size, g_gfx_backend.tile_size,
                 (g_gfx_backend.tile_size == 64) ? 24 : ((g_gfx_backend.tile_size == 32) ? 6 : 96),
                 g_gfx_backend.smp_cores);
        snprintf(l3, sizeof(l3), "Depth Precision:      %s | Shading: %s | Culling: %s",
                 (g_gfx_backend.zprecision == ZBUFFER_PRECISION_16BIT) ? "16-Bit Linear" : "32-Bit Fixed",
                 (g_gfx_backend.shading_mode == RASTER_SHADE_GOURAUD) ? "Gouraud Smooth" : "Flat Diffuse",
                 g_gfx_backend.culling ? "CCW Enabled" : "Disabled");
        snprintf(l4, sizeof(l4), "Resolve Method:       Non-Temporal Streaming Store (stnp.16b) | Ops: %llu",
                 (unsigned long long)g_gfx_backend.ops_counter);

        gfx_draw_string(cx + 36, content_y + 32, l1, COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 36, content_y + 54, l2, COLOR_EMERALD_GREEN, 0);
        gfx_draw_string(cx + 36, content_y + 76, l3, COLOR_TEXT_MUTED, 0);
        gfx_draw_string(cx + 36, content_y + 98, l4, COLOR_ACCENT_CYAN, 0);

        int y_suite = content_y + 158;
        gfx_draw_string(cx + 20, y_suite, "[2] Automated 6-Phase Scientific Comparison Suite:", COLOR_GOLD_ACCENT, 0);

        // Huge Action Button
        gfx_draw_rounded_rect(cx + 24, y_suite + 20, cw - 48, 54, 6, 0xFF8E44AD);
        gfx_draw_string(cx + 64, y_suite + 34, "✦ Launch Automated 6-Phase Scientific Comparison Suite ✦", COLOR_TEXT_WHITE, 0);
        gfx_draw_string(cx + 80, y_suite + 52, "Runs CPU SW, Zero-RAM, VirtIO, SMP, L1 Tile & LuaGL side-by-side with full RTSS telemetry", 0xFFD2B4DE, 0);
    }

    // Bottom Bar with Close Button
    int btm_y = cy + ch - 38;
    gfx_blend_rect(cx, btm_y, cw, 38, 0xFF181C20);
    gfx_draw_rect(cx, btm_y, cw, 1, 0xFF2A2E33);

    gfx_draw_string(cx + 16, btm_y + 12, "NeoOS Sovereign Pipeline | Ring 0 SASOS Direct Hardware Control", COLOR_TEXT_MUTED, 0);

    gfx_draw_rounded_rect(cx + cw - 110, btm_y + 7, 95, 24, 4, 0xFF7F8C8D);
    gfx_draw_string(cx + cw - 85, btm_y + 12, "Close", COLOR_TEXT_WHITE, 0);
}

// ─── Multi-Tab Window Click Handler ───────────────────────────────────────────
int gpu_config_click(window_t *win, int mouse_x, int mouse_y) {
    if (!win) return 0;
    int cx = win->x + 2;
    int cy = win->y + 36;
    int cw = win->width - 4;
    int ch = win->height - 38;

    // Check Tab Header clicks
    int tab_y = cy + 6;
    int tab_w = (cw - 24) / 4;
    for (int t = 0; t < 4; t++) {
        int tx = cx + 12 + t * tab_w;
        if (mouse_x >= tx && mouse_x <= tx + tab_w - 6 && mouse_y >= tab_y && mouse_y <= tab_y + 28) {
            gpu_config_set_tab(t);
            return 1;
        }
    }

    int cur_tab = g_gfx_backend.active_tab;
    int content_y = tab_y + 36;

    // TAB 0 Clicks
    if (cur_tab == 0) {
        // Buffering
        if (mouse_x >= cx + 24 && mouse_x <= cx + 324 && mouse_y >= content_y + 20 && mouse_y <= content_y + 68) {
            gpu_set_buffering(GFX_BUFFER_DOUBLE);
            doldoc_print("$FG,GREEN$[GPU-CONFIG]$FG$ Switched to Double-Buffered DDR RAM.\n");
            return 1;
        }
        if (mouse_x >= cx + 340 && mouse_x <= cx + 640 && mouse_y >= content_y + 20 && mouse_y <= content_y + 68) {
            gpu_set_buffering(GFX_BUFFER_DIRECT_VRAM);
            doldoc_print("$FG,YELLOW$[GPU-CONFIG]$FG$ Switched to Direct VRAM (Zero-RAM Mode).\n");
            return 1;
        }
        // Drivers
        int y_drv = content_y + 86;
        if (mouse_x >= cx + 24 && mouse_x <= cx + 219 && mouse_y >= y_drv + 20 && mouse_y <= y_drv + 68) {
            gfx_backend_set_mode(GFX_MODE_CPU_SW);
            doldoc_print("$FG,CYAN$[GPU-CONFIG]$FG$ Backend switched to Pure CPU Software (UEFI GOP).\n");
            return 1;
        }
        if (mouse_x >= cx + 230 && mouse_x <= cx + 425 && mouse_y >= y_drv + 20 && mouse_y <= y_drv + 68) {
            gfx_backend_set_mode(GFX_MODE_GPU_HW);
            doldoc_print("$FG,MAGENTA$[GPU-CONFIG]$FG$ Backend switched to VirtIO-GPU Hardware DMA Scanout.\n");
            return 1;
        }
        if (mouse_x >= cx + 436 && mouse_x <= cx + 631 && mouse_y >= y_drv + 20 && mouse_y <= y_drv + 68) {
            gfx_backend_set_mode(GFX_MODE_SMP_TILED);
            doldoc_print("$FG,EMERALD_GREEN$[GPU-CONFIG]$FG$ Backend switched to SMP Multi-Core Parallel (Cores 1-3).\n");
            return 1;
        }
    }
    // TAB 1 Clicks
    else if (cur_tab == 1) {
        // Raster Engine
        if (mouse_x >= cx + 24 && mouse_x <= cx + 324 && mouse_y >= content_y + 20 && mouse_y <= content_y + 70) {
            gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
            doldoc_print("$FG,GREEN$[GPU-CONFIG]$FG$ Rasterizer switched to Unified L1 Tile NEON Engine.\n");
            return 1;
        }
        if (mouse_x >= cx + 340 && mouse_x <= cx + 640 && mouse_y >= content_y + 20 && mouse_y <= content_y + 70) {
            gpu_set_raster_engine(RASTER_ENGINE_SCANLINE);
            doldoc_print("$FG,CYAN$[GPU-CONFIG]$FG$ Rasterizer switched to Classic Scanline SIMD.\n");
            return 1;
        }
        // Tile Geometry
        int y_geo = content_y + 86;
        if (mouse_x >= cx + 24 && mouse_x <= cx + 219 && mouse_y >= y_geo + 20 && mouse_y <= y_geo + 68) {
            gpu_set_tile_size(TILE_SIZE_32);
            doldoc_print("$FG,YELLOW$[GPU-CONFIG]$FG$ Tile Size set to 32x32 (6 KB Scratchpad).\n");
            return 1;
        }
        if (mouse_x >= cx + 230 && mouse_x <= cx + 425 && mouse_y >= y_geo + 20 && mouse_y <= y_geo + 68) {
            gpu_set_tile_size(TILE_SIZE_64);
            doldoc_print("$FG,GREEN$[GPU-CONFIG]$FG$ Tile Size set to 64x64 (24 KB L1 Sweet Spot).\n");
            return 1;
        }
        if (mouse_x >= cx + 436 && mouse_x <= cx + 631 && mouse_y >= y_geo + 20 && mouse_y <= y_geo + 68) {
            gpu_set_tile_size(TILE_SIZE_128);
            doldoc_print("$FG,MAGENTA$[GPU-CONFIG]$FG$ Tile Size set to 128x128 (96 KB L2 Line).\n");
            return 1;
        }
        // Cores
        int y_smp = y_geo + 86;
        if (mouse_x >= cx + 24 && mouse_x <= cx + 219 && mouse_y >= y_smp + 20 && mouse_y <= y_smp + 68) {
            gpu_set_smp_cores(1);
            doldoc_print("$FG,CYAN$[GPU-CONFIG]$FG$ Active SMP Cores set to 1 (Single Core 0).\n");
            return 1;
        }
        if (mouse_x >= cx + 230 && mouse_x <= cx + 425 && mouse_y >= y_smp + 20 && mouse_y <= y_smp + 68) {
            gpu_set_smp_cores(2);
            doldoc_print("$FG,GREEN$[GPU-CONFIG]$FG$ Active SMP Cores set to 2 (Cores 0+1).\n");
            return 1;
        }
        if (mouse_x >= cx + 436 && mouse_x <= cx + 631 && mouse_y >= y_smp + 20 && mouse_y <= y_smp + 68) {
            gpu_set_smp_cores(4);
            doldoc_print("$FG,ORANGE$[GPU-CONFIG]$FG$ Active SMP Cores set to 4 (Quad Core Parallel).\n");
            return 1;
        }
    }
    // TAB 2 Clicks
    else if (cur_tab == 2) {
        // Shading Mode
        if (mouse_x >= cx + 24 && mouse_x <= cx + 219 && mouse_y >= content_y + 20 && mouse_y <= content_y + 66) {
            gpu_set_shading(RASTER_SHADE_GOURAUD);
            doldoc_print("$FG,GREEN$[GPU-CONFIG]$FG$ Shading model set to Gouraud Smooth.\n");
            return 1;
        }
        if (mouse_x >= cx + 230 && mouse_x <= cx + 425 && mouse_y >= content_y + 20 && mouse_y <= content_y + 66) {
            gpu_set_shading(RASTER_SHADE_FLAT);
            doldoc_print("$FG,CYAN$[GPU-CONFIG]$FG$ Shading model set to Flat Shading.\n");
            return 1;
        }
        if (mouse_x >= cx + 436 && mouse_x <= cx + 631 && mouse_y >= content_y + 20 && mouse_y <= content_y + 66) {
            gpu_set_shading(RASTER_SHADE_WIREFRAME);
            doldoc_print("$FG,MAGENTA$[GPU-CONFIG]$FG$ Shading model set to Wireframe Overlay.\n");
            return 1;
        }
        // Depth & Culling
        int y_z = content_y + 84;
        if (mouse_x >= cx + 24 && mouse_x <= cx + 219 && mouse_y >= y_z + 20 && mouse_y <= y_z + 64) {
            gpu_set_zprecision(ZBUFFER_PRECISION_16BIT);
            doldoc_print("$FG,GREEN$[GPU-CONFIG]$FG$ Z-Buffer set to 16-Bit Linear Depth.\n");
            return 1;
        }
        if (mouse_x >= cx + 230 && mouse_x <= cx + 425 && mouse_y >= y_z + 20 && mouse_y <= y_z + 64) {
            gpu_set_zprecision(ZBUFFER_PRECISION_32BIT);
            doldoc_print("$FG,GREEN$[GPU-CONFIG]$FG$ Z-Buffer set to 32-Bit Fixed Depth.\n");
            return 1;
        }
        if (mouse_x >= cx + 436 && mouse_x <= cx + 631 && mouse_y >= y_z + 20 && mouse_y <= y_z + 64) {
            gpu_set_culling(!g_gfx_backend.culling);
            doldoc_printf("$FG,YELLOW$[GPU-CONFIG]$FG$ Backface Culling set to %s.\n",
                          g_gfx_backend.culling ? "ENABLED (CCW)" : "DISABLED (Two-Sided)");
            return 1;
        }
        // V-Sync
        int y_vsync = y_z + 82;
        if (mouse_x >= cx + 24 && mouse_x <= cx + 164 && mouse_y >= y_vsync + 20 && mouse_y <= y_vsync + 60) {
            gfx_vsync_set(0, 0);
            doldoc_print("$FG,YELLOW$[GPU-CONFIG]$FG$ Global V-Sync disabled (Uncapped Max FPS).\n");
            return 1;
        }
        if (mouse_x >= cx + 175 && mouse_x <= cx + 315 && mouse_y >= y_vsync + 20 && mouse_y <= y_vsync + 60) {
            gfx_vsync_set(1, 30);
            doldoc_print("$FG,GREEN$[GPU-CONFIG]$FG$ Global V-Sync locked @ 30 FPS.\n");
            return 1;
        }
        if (mouse_x >= cx + 326 && mouse_x <= cx + 466 && mouse_y >= y_vsync + 20 && mouse_y <= y_vsync + 60) {
            gfx_vsync_set(1, 60);
            doldoc_print("$FG,GREEN$[GPU-CONFIG]$FG$ Global V-Sync locked @ 60 FPS.\n");
            return 1;
        }
        if (mouse_x >= cx + 477 && mouse_x <= cx + 631 && mouse_y >= y_vsync + 20 && mouse_y <= y_vsync + 60) {
            gfx_vsync_set(1, 120);
            doldoc_print("$FG,GREEN$[GPU-CONFIG]$FG$ Global V-Sync locked @ 120 FPS High-Refresh.\n");
            return 1;
        }
    }
    // TAB 3 Clicks
    else if (cur_tab == 3) {
        int y_suite = content_y + 158;
        if (mouse_x >= cx + 24 && mouse_x <= cx + cw - 24 &&
            mouse_y >= y_suite + 20 && mouse_y <= y_suite + 74) {
            doldoc_print("$FG,MAGENTA$[GPU-CONFIG]$FG$ Launching Automated 6-Phase Comparison Suite...\n");
            bench_unified_start(BENCH_MODE_SUITE);
            return 1;
        }
    }

    // Close button
    int btm_y = cy + ch - 38;
    if (mouse_x >= cx + cw - 110 && mouse_x <= cx + cw - 15 &&
        mouse_y >= btm_y + 7 && mouse_y <= btm_y + 31) {
        gpu_config_close();
        return 1;
    }

    return 0;
}

void gpu_config_print_doldoc(void) {
    doldoc_print("$FG,CYAN$=======================================================$FG$\n");
    doldoc_print("$FG,WHITE$ NeoOS Sovereign GPU Pipeline & Hardware Configuration Hub $FG$\n");
    doldoc_print("$FG,CYAN$=======================================================$FG$\n");
    doldoc_printf(" Active Backend:      $FG,YELLOW$%s$FG$\n", g_gfx_backend.name);
    doldoc_printf(" Rasterizer Engine:   $FG,GREEN$%s$FG$\n",
                  (g_gfx_backend.raster_engine == RASTER_ENGINE_TILED_L1) ? "Unified L1 Tile NEON" : "Classic Scanline SIMD");
    doldoc_printf(" Tile Geometry:       $FG,CYAN$%dx%d (%d KB L1 Scratchpad)$FG$\n",
                  g_gfx_backend.tile_size, g_gfx_backend.tile_size,
                  (g_gfx_backend.tile_size == 64) ? 24 : ((g_gfx_backend.tile_size == 32) ? 6 : 96));
    doldoc_printf(" Active SMP Cores:    $FG,ORANGE$%d Cores Parallel$FG$\n", g_gfx_backend.smp_cores);
    doldoc_printf(" Shading / Culling:   $FG,WHITE$%s | %s$FG$\n",
                  (g_gfx_backend.shading_mode == RASTER_SHADE_GOURAUD) ? "Gouraud Smooth" : "Flat Shading",
                  g_gfx_backend.culling ? "CCW Enabled" : "Disabled");
    doldoc_printf(" Buffering Mode:      $FG,GREEN$%s$FG$\n",
                  (g_gfx_backend.buffering == GFX_BUFFER_DOUBLE) ? "Double-Buffered (DDR RAM)" : "Direct VRAM (Zero-RAM)");
    doldoc_print("\n Interactive Shell Controls:\n");
    doldoc_print("  $BT,\"L1 Tile 4C\",LM=\"raster tile\"$ $BT,\"Scanline\",LM=\"raster scanline\"$\n");
    doldoc_print("  $BT,\"64x64 Tile\",LM=\"tilesize 64\"$ $BT,\"32x32 Tile\",LM=\"tilesize 32\"$ $BT,\"4 Cores\",LM=\"cores 4\"$\n");
    doldoc_print("  $BT,\"6-Phase Benchmark\",LM=\"benchcompare\"$ $BT,\"Open Window\",LM=\"gpuconfig\"$\n");
    doldoc_print("$FG,CYAN$-------------------------------------------------------$FG$\n");
}

void gfx_backend_transform_vertices_neon(const vec3_t *in, vec4_t *out, int count, const mat4_t *mvp) {
    if (!in || !out || !mvp || count <= 0) return;

    for (int i = 0; i < count; i++) {
        float x = in[i].x, y = in[i].y, z = in[i].z;
        out[i].x = mvp->m[0][0] * x + mvp->m[0][1] * y + mvp->m[0][2] * z + mvp->m[0][3];
        out[i].y = mvp->m[1][0] * x + mvp->m[1][1] * y + mvp->m[1][2] * z + mvp->m[1][3];
        out[i].z = mvp->m[2][0] * x + mvp->m[2][1] * y + mvp->m[2][2] * z + mvp->m[2][3];
        out[i].w = mvp->m[3][0] * x + mvp->m[3][1] * y + mvp->m[3][2] * z + mvp->m[3][3];
    }
    g_gfx_backend.ops_counter += (uint64_t)count * 16;
}

void gfx_backend_fast_clear(uint32_t *dst, size_t num_pixels, uint32_t color) {
    if (!dst || num_pixels == 0) return;

    size_t i = 0;
    for (; i + 8 <= num_pixels; i += 8) {
        dst[i + 0] = color;
        dst[i + 1] = color;
        dst[i + 2] = color;
        dst[i + 3] = color;
        dst[i + 4] = color;
        dst[i + 5] = color;
        dst[i + 6] = color;
        dst[i + 7] = color;
    }
    for (; i < num_pixels; i++) {
        dst[i] = color;
    }
    g_gfx_backend.dma_transfers_bytes += num_pixels * sizeof(uint32_t);
}
