#include "shell.h"
#include "render.h"
#include "wm.h"
#include "menu.h"
#include "../compiler/jit_arm64.h"
#include "../compiler/lua_bridge.h"
#include "../drivers/input/keyboard.h"
#include "../kernel/mem/kheap.h"
#include "../kernel/sched/sched.h"
#include "../kernel/symbols/symbols.h"
#include "../fs/redsea.h"
#include "../kernel/arch/aarch64/smp.h"
#include "../kernel/bench/bench_unified.h"
#include "../drivers/input/mouse.h"
#include "../drivers/gpu/gfx_backend.h"
#include "apps_gui.h"
#include <uefi.h>

#define SHELL_MAX_LINE 256
static char cmd_buf[SHELL_MAX_LINE];
static int  cmd_len = 0;
static int  cursor_visible = 1;
static uint32_t cursor_ticks = 0;

static void print_prompt(void) {
    doldoc_printf("$FG,CYAN$neo:%s>$FG,WHITE$ ", redsea_get_pwd());
}

void shell_init(void) {
    cmd_len = 0;
    cmd_buf[0] = '\0';
    cursor_visible = 1;
    cursor_ticks = 0;

    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print("$FG,WHITE$ NeoOS DolDoc 2.0 / Native HolyC Interactive Shell (Ring 0)$FG$\n");
    doldoc_print("$FG,CYAN$==============================================================$FG$\n");
    doldoc_print(" Architecture: ARMv8-A (AArch64) SASOS | Identity Paging 1:1\n");
    doldoc_print(" Actions: $BT,\"✦ NeoMenu\",LM=\"menu\"$ $BT,\"NeoBench\",LM=\"bench\"$ $BT,\"GLXGears\",LM=\"gears\"$ $BT,\"Dynamics 3D\",LM=\"dynamics\"$ $BT,\"Top\",LM=\"top\"$ $BT,\"Files\",LM=\"ls\"$ $BT,\"Help\",LM=\"help\"$\n");
    doldoc_print(" Code: $FG,YELLOW$menu$FG$, $FG,YELLOW$bench$FG$, $FG,YELLOW$gears$FG$, $FG,YELLOW$dynamics$FG$, $FG,YELLOW$benchsuite$FG$, $FG,YELLOW$top$FG$, $FG,YELLOW$run Bench.HC$FG$\n\n");

    print_prompt();
    doldoc_draw_cursor(1);
    gfx_swap_buffers();
}

static int is_whitespace(char c) {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

static const char* skip_leading_ws(const char *s) {
    while (*s && is_whitespace(*s)) s++;
    return s;
}

void shell_run_command(const char *raw_cmd) {
    const char *cmd = skip_leading_ws(raw_cmd);
    if (!*cmd) {
        print_prompt();
        return;
    }

    if (strcmp(cmd, "help") == 0) {
        doldoc_print("$FG,CYAN$--- NeoOS Interactive Shell Help ---$FG$\n");
        doldoc_print(" $FG,YELLOW$Application Hub:$FG$     menu, [✦ NeoMenu] button\n");
        doldoc_print(" $FG,YELLOW$NeoBench Extreme:$FG$      bench, gears, dynamics, benchsuite, benchcompare\n");
        doldoc_print(" $FG,YELLOW$Graphics HAL Pipeline:$FG$ render <cpu|gpu|smp>, raster <tile|scanline>, tilesize <32|64|128>\n");
        doldoc_print(" $FG,YELLOW$Pipeline Parameters:$FG$   cores <1|2|4>, shading <gouraud|flat|wire>, cull <0|1>, gpuconfig\n");
        doldoc_print(" $FG,YELLOW$GUI Applications:$FG$      menu, filer, edit <file>, gpuconfig, compositor\n");
        doldoc_print(" $FG,YELLOW$RivaTuner RTSS Telemetry:$FG$ perf (FPS, 1% low, 0.1% low, stddev, latency)\n");
        doldoc_print(" $FG,YELLOW$V-Sync Frame Pacing:$FG$  vsync <on | off | 60 | 120 | 144 | 240>\n");
        doldoc_print(" $FG,YELLOW$Zero-RAM Buffer:$FG$      zeroram (on, off, status)\n");
        doldoc_print(" $FG,YELLOW$JIT Engine:$FG$           jit <expr>, jittest, arithmetic, loops, switch/case\n");
        doldoc_print(" $FG,YELLOW$Lua 5.4.7 Engine:$FG$     lua <expr>, run <file.lua>\n");
        doldoc_print(" $FG,YELLOW$System Telemetry:$FG$     top, smp, affinity <task> <core>, tasks, mem, sym\n");
        doldoc_print(" $FG,YELLOW$Storage & RedSea:$FG$     ls, cd, mkdir, rm, cat, write, run\n");
        doldoc_print(" $FG,YELLOW$Arithmetic & HolyC:$FG$   10 + 4 * 8;, I64 x = 10; x * 2;\n");
        doldoc_print(" $FG,YELLOW$Control flow:$FG$         for, while, do..while, switch/case, ? :\n");
        doldoc_print(" $FG,YELLOW$Interactive Tags:$FG$     $BT,\"NeoMenu\",LM=\"menu\"$ $BT,\"Files\",LM=\"filer\"$ $BT,\"GPU\",LM=\"gpuconfig\"$ $BT,\"Comp\",LM=\"compositor\"$\n");
        doldoc_print("$FG,CYAN$------------------------------------$FG$\n");
    } else if (strcmp(cmd, "menu") == 0) {
        menu_toggle();
        doldoc_print("$FG,CYAN$[NEOMENU]$FG$ Toggled NeoMenu application hub.\n");
        wm_draw_all();
        gfx_swap_buffers();
        mouse_draw_cursor_front();
        return;
    } else if (strcmp(cmd, "clear") == 0 || strcmp(cmd, "cls") == 0) {
        doldoc_clear();
    } else if (strcmp(cmd, "mem") == 0) {
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
    } else if (strcmp(cmd, "scroll up") == 0) {
        doldoc_scroll_up(10);
        gfx_swap_buffers();
        return;
    } else if (strcmp(cmd, "scroll down") == 0) {
        doldoc_scroll_down(10);
        gfx_swap_buffers();
        return;
    } else if (strcmp(cmd, "bench") == 0 || strcmp(cmd, "benchsuite") == 0 || strcmp(cmd, "benchcompare") == 0) {
        bench_unified_start(BENCH_MODE_SUITE);
        doldoc_print("$FG,GREEN$[NEOBENCH]$FG$ Launched Sovereign 16-Phase Multi-Configuration Benchmark Suite!\n");
        doldoc_print(" Testing CPU SW, Direct VRAM, VirtIO-GPU, SMP 1C/2C/4C, Resolutions (360p/480p/720p), and VSync.\n");
        doldoc_print(" Autonomous execution: no interaction required. Results will auto-export to /BENCH_COMPARISON.TXT.\n");
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
        mouse_draw_cursor_front();
        return;
    } else if (strcmp(cmd, "stopbench") == 0 || strcmp(cmd, "closebench") == 0) {
        bench_unified_stop();
        doldoc_print("$FG,YELLOW$[NEOBENCH]$FG$ NeoBench Extreme closed. Focus returned to shell.\n");
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
        mouse_draw_cursor_front();
        return;
    } else if (strcmp(cmd, "bench3d") == 0 || strcmp(cmd, "cube2") == 0) {
        bench_unified_start(BENCH_MODE_CUBES_SMP);
        doldoc_print("$FG,GREEN$[NEOBENCH]$FG$ Launched Dual Cubes SMP on Core 1 & Core 2!\n");
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
        mouse_draw_cursor_front();
        return;
    } else if (strcmp(cmd, "dynamics") == 0 || strcmp(cmd, "bench_dyn") == 0 || strcmp(cmd, "physics") == 0) {
        bench_unified_start(BENCH_MODE_DYNAMICS);
        doldoc_print("$FG,GREEN$[NEOBENCH]$FG$ Launched 3D Multi-Body Rigid Dynamics & Collisions!\n");
        doldoc_print(" Click viewport or [Explode!] to trigger impulse dynamics. Type $FG,YELLOW$stopbench$FG$ to dismiss.\n");
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
        mouse_draw_cursor_front();
        return;
    } else if (strcmp(cmd, "close3d") == 0 || strcmp(cmd, "bench3d stop") == 0 || strcmp(cmd, "bench3d close") == 0) {
        bench_unified_stop();
        doldoc_print("$FG,YELLOW$[NEOBENCH]$FG$ Benchmark viewports closed. Focus returned to shell.\n");
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
        mouse_draw_cursor_front();
        return;
    } else if (strncmp(cmd, "zeroram", 7) == 0) {
        const char *arg = cmd + 7;
        while (*arg == ' ') arg++;
        if (strcmp(arg, "on") == 0 || strcmp(arg, "1") == 0) {
            gfx_set_zero_ram_mode(1);
        } else if (strcmp(arg, "off") == 0 || strcmp(arg, "0") == 0) {
            gfx_set_zero_ram_mode(0);
        }
        int is_zr = gfx_is_zero_ram_mode();
        doldoc_print("$FG,CYAN$=======================================================$FG$\n");
        doldoc_print("$FG,WHITE$ NeoOS Zero-RAM Framebuffer Architecture (TempleOS SASOS)$FG$\n");
        doldoc_print("$FG,CYAN$=======================================================$FG$\n");
        if (is_zr) {
            doldoc_print(" Mode:               $FG,GREEN$Zero-RAM Direct-to-VRAM (Active)$FG$\n");
            doldoc_print(" RAM Buffer:         $FG,YELLOW$0 MB allocated$FG$ ($FG,GREEN$3.14 MB RAM saved$FG$)\n");
            doldoc_print(" Memcpy Latency:     $FG,GREEN$0 ms (100%% Copy Overhead Eliminated)$FG$\n");
            doldoc_printf(" Hardware VRAM Base: 0x%p (GOP Linear Scanout)\n", gfx_get_frontbuffer());
        } else {
            doldoc_print(" Mode:               $FG,YELLOW$Double-Buffering (RAM Backbuffer)$FG$\n");
            doldoc_print(" RAM Buffer:         3.14 MB (Dedicated Pages)\n");
            doldoc_printf(" Hardware VRAM Base: 0x%p (GOP Linear Scanout)\n", gfx_get_frontbuffer());
            doldoc_print(" Type $FG,CYAN$zeroram on$FG$ to eliminate the 3.14 MB backbuffer!\n");
        }
        doldoc_print("$FG,CYAN$-------------------------------------------------------$FG$\n");
        wm_draw_all();
        gfx_swap_buffers();
        mouse_draw_cursor_front();
        return;
    } else if (strncmp(cmd, "vsync", 5) == 0) {
        const char *arg = skip_leading_ws(cmd + 5);
        if (strcmp(arg, "on") == 0 || strcmp(arg, "1") == 0 || strcmp(arg, "60") == 0) {
            gfx_vsync_set(1, 60);
            doldoc_print("$FG,GREEN$[VSYNC]$FG$ Software V-Sync enabled @ 60 Hz (Smooth frame pacing, 0 tearing).\n");
        } else if (strcmp(arg, "120") == 0) {
            gfx_vsync_set(1, 120);
            doldoc_print("$FG,GREEN$[VSYNC]$FG$ Software V-Sync enabled @ 120 Hz.\n");
        } else if (strcmp(arg, "144") == 0) {
            gfx_vsync_set(1, 144);
            doldoc_print("$FG,GREEN$[VSYNC]$FG$ Software V-Sync enabled @ 144 Hz.\n");
        } else if (strcmp(arg, "240") == 0) {
            gfx_vsync_set(1, 240);
            doldoc_print("$FG,GREEN$[VSYNC]$FG$ Software V-Sync enabled @ 240 Hz.\n");
        } else if (strcmp(arg, "off") == 0 || strcmp(arg, "0") == 0) {
            gfx_vsync_set(0, 0);
            doldoc_print("$FG,YELLOW$[VSYNC]$FG$ V-Sync disabled (Uncapped maximum framerate).\n");
        } else {
            doldoc_print("Usage: vsync <on | off | 60 | 120 | 144 | 240>\n");
        }
        wm_draw_all();
        gfx_swap_buffers();
        mouse_draw_cursor_front();
        return;
    } else if (strcmp(cmd, "perf") == 0) {
        perf_stats_t *ps = bench_unified_get_stats();
        perf_overlay_update_metrics(ps);
        doldoc_print("$FG,CYAN$=======================================================$FG$\n");
        doldoc_print("$FG,WHITE$ NeoOS RivaTuner (RTSS) Empirical Hardware Telemetry $FG$\n");
        doldoc_print("$FG,CYAN$=======================================================$FG$\n");
        uint32_t fps_curr_i = (uint32_t)ps->fps_current;
        uint32_t fps_curr_f = (uint32_t)((ps->fps_current - (float)fps_curr_i) * 10.0f);
        doldoc_printf(" Instantaneous Framerate: $FG,GREEN$%u.%u FPS$FG$\n", fps_curr_i, fps_curr_f);
        doldoc_printf(" Rolling Average (512fr):  $FG,CYAN$%u FPS$FG$ (Total: %llu frames)\n", (uint32_t)ps->fps_avg, (unsigned long long)ps->total_frames);
        doldoc_printf(" 1%% Low Framerate:       $FG,%s$%u FPS$FG$ (Worst 1%% Frame Drops)\n", (ps->fps_1pct_low >= 30) ? "GREEN" : "RED", (uint32_t)ps->fps_1pct_low);
        doldoc_printf(" 0.1%% Low Framerate:     $FG,%s$%u FPS$FG$ (Severe Spikes / Stutter)\n", (ps->fps_01pct_low >= 20) ? "GREEN" : "RED", (uint32_t)ps->fps_01pct_low);
        doldoc_printf(" Frame Time Average:      %u.%02u ms\n", (uint32_t)ps->frame_time_avg_ms, (uint32_t)((ps->frame_time_avg_ms - (float)(uint32_t)ps->frame_time_avg_ms) * 100.0f));
        doldoc_printf(" Fastest Frame:           %u.%02u ms\n", (uint32_t)ps->frame_time_min_ms, (uint32_t)((ps->frame_time_min_ms - (float)(uint32_t)ps->frame_time_min_ms) * 100.0f));
        doldoc_printf(" Worst Peak Spike:        $FG,YELLOW$%u.%02u ms$FG$\n", (uint32_t)ps->frame_time_max_ms, (uint32_t)((ps->frame_time_max_ms - (float)(uint32_t)ps->frame_time_max_ms) * 100.0f));
        doldoc_printf(" Consistency (StdDev):    $FG,CYAN$%u.%02u ms$FG$ (Frame Jitter)\n", (uint32_t)ps->frame_time_stddev_ms, (uint32_t)((ps->frame_time_stddev_ms - (float)(uint32_t)ps->frame_time_stddev_ms) * 100.0f));
        doldoc_printf(" NEON Blit Latency:       %u.%u ms\n", (uint32_t)ps->blit_avg_ms, (uint32_t)((ps->blit_avg_ms - (float)(uint32_t)ps->blit_avg_ms) * 10.0f));
        doldoc_printf(" 3D Render Latency:       %u.%u ms\n", (uint32_t)ps->render_avg_ms, (uint32_t)((ps->render_avg_ms - (float)(uint32_t)ps->render_avg_ms) * 10.0f));
        doldoc_print("$FG,CYAN$-------------------------------------------------------$FG$\n");
        wm_draw_all();
        gfx_swap_buffers();
        mouse_draw_cursor_front();
        return;
    } else if (strcmp(cmd, "jittest") == 0) {
        jit_run_self_tests();
        wm_draw_all();
        gfx_swap_buffers();
        mouse_draw_cursor_front();
        return;
    } else if (strcmp(cmd, "gears") == 0 || strcmp(cmd, "glxgears") == 0) {
        bench_unified_start(BENCH_MODE_GEARS);
        doldoc_print("$FG,GREEN$[NEOBENCH]$FG$ Launched Authentic 3D GLXGears with Z-Buffer & Lighting!\n");
        doldoc_print(" Click and drag mouse inside window to rotate view. Type $FG,YELLOW$stopbench$FG$ to dismiss.\n");
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
        mouse_draw_cursor_front();
        return;
    } else if (strcmp(cmd, "gears_wire") == 0) {
        bench_unified_start(BENCH_MODE_GEARS);
        g_bench.wireframe = 1;
        doldoc_print("$FG,CYAN$[NEOBENCH]$FG$ Launched 3D Gears in Wireframe Mode!\n");
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
        mouse_draw_cursor_front();
        return;
    } else if (strcmp(cmd, "gears_dual") == 0) {
        bench_unified_start(BENCH_MODE_GEARS);
        g_bench.smp_mode = 1;
        doldoc_print("$FG,MAGENTA$[NEOBENCH]$FG$ Launched 3D Gears with Parallel SMP Stress Cores 1 & 2!\n");
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
        mouse_draw_cursor_front();
        return;
    } else if (strcmp(cmd, "closegears") == 0) {
        bench_unified_stop();
        doldoc_print("$FG,YELLOW$[NEOBENCH]$FG$ Benchmark window closed. Focus returned to shell.\n");
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
        mouse_draw_cursor_front();
        return;
    } else if (strcmp(cmd, "gears_log") == 0 || strcmp(cmd, "benchlog") == 0) {
        int res = bench_unified_export_log();
        if (res == 0) {
            doldoc_print("$FG,GREEN$[NEOBENCH]$FG$ Exported empirical telemetry log to /BENCH_REPORT.TXT & /GEARS_BENCHMARK.LOG!\n");
        } else {
            doldoc_print("$FG,RED$[NEOBENCH]$FG$ No benchmark telemetry available to export (run 'bench' first).\n");
        }
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
        mouse_draw_cursor_front();
        return;
    } else if (strncmp(cmd, "gpu_backend", 11) == 0 || strncmp(cmd, "render", 6) == 0) {
        const char *arg = (strncmp(cmd, "gpu_backend", 11) == 0) ? skip_leading_ws(cmd + 11) : skip_leading_ws(cmd + 6);
        if (strcmp(arg, "cpu") == 0 || strcmp(arg, "sw") == 0 || strcmp(arg, "0") == 0) {
            gfx_backend_set_mode(GFX_MODE_CPU_SW);
            doldoc_print("$FG,CYAN$[GFX-HAL]$FG$ Switched to $FG,GREEN$Pure CPU Software (UEFI GOP)$FG$.\n");
            doldoc_print(" Original UEFI software graphics active. Zero VirtIO overhead.\n");
        } else if (strcmp(arg, "gpu") == 0 || strcmp(arg, "hw") == 0 || strcmp(arg, "1") == 0) {
            gfx_backend_set_mode(GFX_MODE_GPU_HW);
            doldoc_print("$FG,CYAN$[GFX-HAL]$FG$ Switched to $FG,MAGENTA$VirtIO-GPU Hardware DMA Scanout$FG$.\n");
            doldoc_print(" Physical DMA backing + PoC cache clean active.\n");
        } else if (strcmp(arg, "smp") == 0 || strcmp(arg, "2") == 0) {
            gfx_backend_set_mode(GFX_MODE_SMP_TILED);
            doldoc_print("$FG,CYAN$[GFX-HAL]$FG$ Switched to $FG,EMERALD_GREEN$SMP Multi-Core Parallel (Cores 1-3)$FG$.\n");
            doldoc_print(" Multi-core parallel geometry transforms active.\n");
        } else {
            doldoc_print("Usage: render <cpu | gpu | smp>\n");
            doldoc_printf(" Active Mode: %s\n", gfx_backend_get_name());
        }
        wm_set_dirty();
        wm_draw_all();
        gfx_swap_buffers();
        mouse_draw_cursor_front();
        return;
    } else if (strncmp(cmd, "raster", 6) == 0) {
        const char *arg = skip_leading_ws(cmd + 6);
        if (strcmp(arg, "tile") == 0 || strcmp(arg, "l1") == 0 || strcmp(arg, "1") == 0) {
            gpu_set_raster_engine(RASTER_ENGINE_TILED_L1);
            doldoc_print("$FG,GREEN$[GFX-HAL]$FG$ Switched to $FG,CYAN$Unified L1 Tile NEON Engine$FG$ (24 KB Scratchpad, 4-Wide Pineda SIMD).\n");
        } else if (strcmp(arg, "scanline") == 0 || strcmp(arg, "0") == 0) {
            gpu_set_raster_engine(RASTER_ENGINE_SCANLINE);
            doldoc_print("$FG,GREEN$[GFX-HAL]$FG$ Switched to $FG,YELLOW$Classic Scanline SIMD$FG$ (16.16 Fixed-Point Slope-Walker).\n");
        } else {
            doldoc_print("Usage: raster <tile | scanline>\n");
            doldoc_printf(" Active Engine: %s\n", (gpu_get_raster_engine() == RASTER_ENGINE_TILED_L1) ? "Unified L1 Tile NEON" : "Classic Scanline SIMD");
        }
        wm_set_dirty();
        return;
    } else if (strncmp(cmd, "tilesize", 8) == 0) {
        const char *arg = skip_leading_ws(cmd + 8);
        int sz = atoi(arg);
        if (sz == 32 || sz == 64 || sz == 128) {
            gpu_set_tile_size(sz);
            doldoc_printf("$FG,GREEN$[GFX-HAL]$FG$ Tile size set to $FG,CYAN$%dx%d$FG$ (%d KB L1 Scratchpad).\n",
                          sz, sz, (sz == 64) ? 24 : ((sz == 32) ? 6 : 96));
        } else {
            doldoc_print("Usage: tilesize <32 | 64 | 128>\n");
            doldoc_printf(" Current Tile Size: %dx%d\n", gpu_get_tile_size(), gpu_get_tile_size());
        }
        wm_set_dirty();
        return;
    } else if (strncmp(cmd, "cores", 5) == 0) {
        const char *arg = skip_leading_ws(cmd + 5);
        int c = atoi(arg);
        if (c >= 1 && c <= 4) {
            gpu_set_smp_cores(c);
            doldoc_printf("$FG,GREEN$[GFX-HAL]$FG$ Active SMP raster cores set to $FG,ORANGE$%d Core(s)$FG$.\n", c);
        } else {
            doldoc_print("Usage: cores <1 | 2 | 4>\n");
            doldoc_printf(" Current Active Cores: %d\n", gpu_get_smp_cores());
        }
        wm_set_dirty();
        return;
    } else if (strncmp(cmd, "shading", 7) == 0) {
        const char *arg = skip_leading_ws(cmd + 7);
        if (strcmp(arg, "gouraud") == 0 || strcmp(arg, "smooth") == 0) {
            gpu_set_shading(RASTER_SHADE_GOURAUD);
            doldoc_print("$FG,GREEN$[GFX-HAL]$FG$ Shading model set to $FG,CYAN$Gouraud Smooth$FG$.\n");
        } else if (strcmp(arg, "flat") == 0) {
            gpu_set_shading(RASTER_SHADE_FLAT);
            doldoc_print("$FG,GREEN$[GFX-HAL]$FG$ Shading model set to $FG,YELLOW$Flat Shading$FG$.\n");
        } else if (strcmp(arg, "wire") == 0 || strcmp(arg, "wireframe") == 0) {
            gpu_set_shading(RASTER_SHADE_WIREFRAME);
            doldoc_print("$FG,GREEN$[GFX-HAL]$FG$ Shading model set to $FG,MAGENTA$Wireframe Overlay$FG$.\n");
        } else {
            doldoc_print("Usage: shading <gouraud | flat | wire>\n");
        }
        wm_set_dirty();
        return;
    } else if (strncmp(cmd, "cull", 4) == 0) {
        const char *arg = skip_leading_ws(cmd + 4);
        if (strcmp(arg, "1") == 0 || strcmp(arg, "on") == 0) {
            gpu_set_culling(1);
            doldoc_print("$FG,GREEN$[GFX-HAL]$FG$ Backface Culling $FG,CYAN$ENABLED (CCW)$FG$.\n");
        } else if (strcmp(arg, "0") == 0 || strcmp(arg, "off") == 0) {
            gpu_set_culling(0);
            doldoc_print("$FG,GREEN$[GFX-HAL]$FG$ Backface Culling $FG,YELLOW$DISABLED (Two-Sided)$FG$.\n");
        } else {
            doldoc_print("Usage: cull <1 | 0>\n");
            doldoc_printf(" Current Culling: %s\n", gpu_get_culling() ? "ON" : "OFF");
        }
        wm_set_dirty();
        return;
    } else if (strcmp(cmd, "benchcompare") == 0) {
        bench_unified_start(BENCH_MODE_SUITE);
        doldoc_print("$FG,MAGENTA$[NEOBENCH]$FG$ Launched Automated 10-Phase Multi-Configuration Comparison Suite (10s/test).\n");
        doldoc_print(" Testing CPU SW, Zero-RAM GOP, VirtIO DMA, Direct VRAM, 2C/4C SMP, Unified L1 Tile NEON & Mixed Modes.\n");
        return;
    } else if (strcmp(cmd, "gpuconfig") == 0 || strcmp(cmd, "gpu") == 0) {
        gpu_config_open();
        doldoc_print("$FG,CYAN$[GPU-CONFIG]$FG$ Opened Dedicated GPU Hardware & Buffering Configuration Window.\n");
        return;
    } else if (strcmp(cmd, "compositor") == 0 || strcmp(cmd, "comp") == 0) {
        compositor_config_open();
        doldoc_print("$FG,CYAN$[COMPOSITOR]$FG$ Opened Dedicated Desktop Compositor & Effects Window.\n");
        return;
    } else if (strcmp(cmd, "filer") == 0 || strcmp(cmd, "files") == 0) {
        filer_open();
        doldoc_print("$FG,CYAN$[FILER]$FG$ Opened Dedicated DolDoc File Explorer Window.\n");
        return;
    } else if (strncmp(cmd, "edit", 4) == 0) {
        const char *target_file = "fact.HC";
        if (strlen(cmd) > 4) {
            target_file = skip_leading_ws(cmd + 4);
            if (*target_file == '\0') target_file = "fact.HC";
        }
        editor_open(target_file);
        doldoc_printf("$FG,CYAN$[EDITOR]$FG$ Opened Dedicated Code Editor Window for '%s'.\n", target_file);
    } else if (strcmp(cmd, "top") == 0) {
        top_print_doldoc();
    } else if (strncmp(cmd, "affinity ", 9) == 0) {
        const char *p = skip_leading_ws(cmd + 9);
        uint64_t tid = (uint64_t)atoi(p);
        while (*p && *p != ' ') p++;
        p = skip_leading_ws(p);
        int cid = atoi(p);
        uint32_t mask = 0x0F;
        if (cid == 0) mask = 0x01;
        else if (cid == 1) mask = 0x02;
        else if (cid == 2) mask = 0x04;
        else if (cid == 3) mask = 0x08;
        else mask = 0x0F;
        extern int task_set_affinity(uint64_t task_id, uint32_t mask);
        task_set_affinity(tid, mask);
        doldoc_printf("$FG,GREEN$[SCHED]$FG$ Task PID %llu affinity set to Core %d (Mask: 0x%02X)\n",
                      (unsigned long long)tid, cid, mask);
        return;
    } else if (strcmp(cmd, "tasks") == 0) {
        sched_print_doldoc();
    } else if (strcmp(cmd, "sym") == 0) {
        symbols_print_doldoc();
    } else if (strcmp(cmd, "smp") == 0 || strcmp(cmd, "cpu") == 0) {
        smp_print_doldoc();
    } else if (strcmp(cmd, "pwd") == 0) {
        doldoc_printf("$FG,CYAN$%s$FG$\n", redsea_get_pwd());
    } else if (strncmp(cmd, "cd ", 3) == 0 || strcmp(cmd, "cd") == 0) {
        const char *dir = (cmd[2] == '\0') ? "/" : skip_leading_ws(cmd + 3);
        if (redsea_change_dir(dir) != 0) {
            doldoc_printf("$FG,RED$Directory not found: %s$FG$\n", dir);
        }
    } else if (strncmp(cmd, "mkdir ", 6) == 0) {
        const char *dir = skip_leading_ws(cmd + 6);
        if (redsea_mkdir(dir) == 0) {
            doldoc_printf("$FG,GREEN$Created directory: %s$FG$\n", dir);
        } else {
            doldoc_printf("$FG,RED$Failed to create directory: %s$FG$\n", dir);
        }
    } else if (strncmp(cmd, "rm ", 3) == 0 || strncmp(cmd, "del ", 4) == 0) {
        const char *fname = (cmd[0] == 'r') ? skip_leading_ws(cmd + 3) : skip_leading_ws(cmd + 4);
        if (redsea_delete_file(fname) == 0) {
            doldoc_printf("$FG,GREEN$Deleted: %s$FG$\n", fname);
        } else {
            doldoc_printf("$FG,RED$File not found: %s$FG$\n", fname);
        }
    } else if (strcmp(cmd, "ramdisk") == 0 || strcmp(cmd, "ramls") == 0) {
        ramdisk_list_dir();
    } else if (strncmp(cmd, "ramcat ", 7) == 0) {
        const char *fname = skip_leading_ws(cmd + 7);
        char fbuf[4096];
        size_t fsize = 0;
        if (ramdisk_read_file(fname, fbuf, sizeof(fbuf) - 1, &fsize) == 0) {
            fbuf[fsize] = '\0';
            doldoc_printf("$FG,YELLOW$--- RAMDISK %s (%llu bytes) ---$FG$\n", fname, (unsigned long long)fsize);
            doldoc_print(fbuf);
            doldoc_print("\n$FG,YELLOW$-------------------------$FG$\n");
        } else {
            doldoc_printf("$FG,RED$RAMDisk file not found: %s$FG$\n", fname);
        }
    } else if (strncmp(cmd, "ramwrite ", 9) == 0) {
        const char *p = skip_leading_ws(cmd + 9);
        char fname[64];
        int fi = 0;
        while (*p && *p != ' ' && fi < (int)sizeof(fname) - 1) {
            fname[fi++] = *p++;
        }
        fname[fi] = '\0';
        p = skip_leading_ws(p);
        size_t dlen = strlen(p);
        if (ramdisk_write_file(fname, p, dlen) == 0) {
            doldoc_printf("$FG,GREEN$[RAMDISK]$FG$ Saved %s (%llu bytes) to RAMDisk.\n", fname, (unsigned long long)dlen);
        } else {
            doldoc_printf("$FG,RED$Failed to write %s to RAMDisk.\n$FG$", fname);
        }
    } else if (strcmp(cmd, "ls") == 0 || strcmp(cmd, "dir") == 0) {
        redsea_list_dir();
    } else if (strncmp(cmd, "cat ", 4) == 0 || strncmp(cmd, "type ", 5) == 0) {
        const char *fname = (cmd[0] == 'c') ? cmd + 4 : cmd + 5;
        fname = skip_leading_ws(fname);
        char fbuf[4096];
        size_t fsize = 0;
        if (redsea_read_file(fname, fbuf, sizeof(fbuf) - 1, &fsize) == 0) {
            fbuf[fsize] = '\0';
            doldoc_printf("$FG,CYAN$--- %s (%llu bytes) ---$FG$\n", fname, (unsigned long long)fsize);
            doldoc_print(fbuf);
            doldoc_print("\n$FG,CYAN$-------------------------$FG$\n");
        } else {
            doldoc_printf("$FG,RED$File not found: %s$FG$\n", fname);
        }
    } else if (strncmp(cmd, "jit ", 4) == 0) {
        const char *jcode = skip_leading_ws(cmd + 4);
        int64_t val = jit_compile_and_run(jcode);
        doldoc_printf("$FG,YELLOW$--> %lld (0x%llX)$FG$\n", (long long)val, (unsigned long long)val);
    } else if (strncmp(cmd, "lua ", 4) == 0) {
        const char *lcode = skip_leading_ws(cmd + 4);
        size_t len = strlen(lcode);
        int is_file = 0;
        char file_to_run[64] = {0};

        if (len > 4 && (strcmp(lcode + len - 4, ".lua") == 0 || strcmp(lcode + len - 4, ".LUA") == 0)) {
            strncpy(file_to_run, lcode, sizeof(file_to_run) - 1);
            is_file = 1;
        } else if (len > 0 && strchr(lcode, ' ') == NULL && strchr(lcode, '(') == NULL && strchr(lcode, '=') == NULL) {
            char try_path[64];
            snprintf(try_path, sizeof(try_path), "%s.lua", lcode);
            char dummy[16];
            size_t dummy_sz = 0;
            if (redsea_read_file(try_path, dummy, sizeof(dummy), &dummy_sz) == 0) {
                strncpy(file_to_run, try_path, sizeof(file_to_run) - 1);
                is_file = 1;
            } else if (redsea_read_file(lcode, dummy, sizeof(dummy), &dummy_sz) == 0) {
                strncpy(file_to_run, lcode, sizeof(file_to_run) - 1);
                is_file = 1;
            }
        }

        if (is_file) {
            neo_lua_dofile(file_to_run);
        } else {
            int64_t res = neo_lua_eval(lcode);
            doldoc_printf("$FG,YELLOW$--> %lld$FG$\n", (long long)res);
        }
    } else if (strncmp(cmd, "run ", 4) == 0) {
        const char *fname = skip_leading_ws(cmd + 4);
        size_t flen = strlen(fname);
        if (flen > 4 && strcmp(fname + flen - 4, ".lua") == 0) {
            neo_lua_dofile(fname);
        } else {
            char fbuf[8192];
            size_t fsize = 0;
            if (redsea_read_file(fname, fbuf, sizeof(fbuf) - 1, &fsize) == 0) {
                fbuf[fsize] = '\0';
                doldoc_printf("$FG,GREEN$[RUN]$FG$ Compiling and executing %s (%llu bytes)...\n", fname, (unsigned long long)fsize);
                int64_t res = jit_compile_and_run(fbuf);
                doldoc_printf("$FG,YELLOW$--> %lld (0x%llX)$FG$\n", (long long)res, (unsigned long long)res);
            } else {
                doldoc_printf("$FG,RED$File not found: %s$FG$\n", fname);
            }
        }
    } else if (strncmp(cmd, "write ", 6) == 0) {
        const char *p = skip_leading_ws(cmd + 6);
        char fname[64];
        int fi = 0;
        while (*p && *p != ' ' && fi < (int)sizeof(fname) - 1) {
            fname[fi++] = *p++;
        }
        fname[fi] = '\0';
        p = skip_leading_ws(p);
        size_t dlen = strlen(p);
        if (redsea_write_file(fname, p, dlen) == 0) {
            doldoc_printf("$FG,GREEN$[WRITE]$FG$ Saved %s (%llu bytes) to RedSea disk.\n", fname, (unsigned long long)dlen);
        } else {
            doldoc_printf("$FG,RED$Failed to write %s to disk.\n$FG$", fname);
        }
    } else if (strncmp(cmd, "mouse ", 6) == 0) {
        const char *p = skip_leading_ws(cmd + 6);
        int mx = atoi(p);
        while (*p && *p != ' ') p++;
        p = skip_leading_ws(p);
        int my = atoi(p);
        while (*p && *p != ' ') p++;
        p = skip_leading_ws(p);
        int btn = (*p) ? atoi(p) : 0;
        mouse_set_pos(mx, my);
        mouse_set_button(btn, 0);
        extern void wm_handle_mouse(mouse_state_t mouse);
        wm_handle_mouse(mouse_get_state());
        doldoc_printf("[MOUSE] Pos (%d, %d), button=%d\n", mx, my, btn);
    } else if (strcmp(cmd, "reboot") == 0) {
        doldoc_print("$FG,RED$Rebooting system via ARM PSCI...$FG$\n");
        gfx_swap_buffers();
        extern int64_t psci_call_hvc(uint64_t func, uint64_t arg1, uint64_t arg2, uint64_t arg3);
        psci_call_hvc(0x84000009ULL, 0, 0, 0); // PSCI 0.2+ SYSTEM_RESET
    } else {
        // Execute C/HolyC source code through AArch64 JIT
        int is_func = (strstr(cmd, "{") != NULL && (strstr(cmd, "I64 ") != NULL || strstr(cmd, "U0 ") != NULL || strstr(cmd, "F64 ") != NULL || strstr(cmd, "int ") != NULL));
        int64_t val = jit_compile_and_run(cmd);
        if (!is_func) {
            doldoc_printf("$FG,YELLOW$--> %lld (0x%llX)$FG$\n", (long long)val, (unsigned long long)val);
        }
    }

    print_prompt();
}

void shell_poll(void) {
    while (keyboard_has_char()) {
        int c = keyboard_getchar();
        if (c == '\n') {
            doldoc_draw_cursor(0);
            doldoc_putc('\n');
            cmd_buf[cmd_len] = '\0';
            shell_run_command(cmd_buf);
            cmd_len = 0;
            cmd_buf[0] = '\0';
            cursor_visible = 1;
            doldoc_draw_cursor(1);
            wm_draw_all();
            mouse_draw_cursor();
            gfx_swap_buffers();
        } else if (c == KEY_BACKSPACE) {
            if (cmd_len > 0) {
                doldoc_draw_cursor(0);
                cmd_len--;
                cmd_buf[cmd_len] = '\0';
                doldoc_backspace();
                doldoc_draw_cursor(1);
                doldoc_swap_term();
            }
        } else if (c == KEY_PAGE_UP) {
            doldoc_scroll_up(5);
            doldoc_swap_term();
        } else if (c == KEY_PAGE_DOWN) {
            doldoc_scroll_down(5);
            doldoc_swap_term();
        } else if (c >= 32 && c < 127) {
            if (cmd_len < SHELL_MAX_LINE - 1) {
                doldoc_draw_cursor(0);
                cmd_buf[cmd_len++] = (char)c;
                cmd_buf[cmd_len] = '\0';
                doldoc_putc((char)c);
                doldoc_draw_cursor(1);
                doldoc_swap_term();
            }
        }
    }

    // Cursor Blink animation
    cursor_ticks++;
    if (cursor_ticks % 20 == 0) {
        cursor_visible = !cursor_visible;
        doldoc_draw_cursor(cursor_visible);
        doldoc_swap_cursor();
    }
}
