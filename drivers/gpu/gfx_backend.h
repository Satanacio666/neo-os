#ifndef NEO_GFX_BACKEND_H
#define NEO_GFX_BACKEND_H

#include <uefi.h>
#include "../../kernel/math/math3d.h"
#include "../../kernel/math/raster_tile.h"
#include "../../gui/wm.h"

typedef enum {
    GFX_MODE_CPU_SW         = 0, // Pure CPU / UEFI GOP Software Graphics (Original UEFI pipeline)
    GFX_MODE_GPU_HW         = 1, // VirtIO-GPU Hardware Accelerated DMA Scanout
    GFX_MODE_SMP_TILED      = 2, // SMP Multi-Core Parallel Graphics (Cores 1-3)
    GFX_MODE_SOFTWARE_SIMD  = 0, // Backward-compat alias
    GFX_MODE_HW_ACCELERATED = 1  // Backward-compat alias
} gfx_backend_mode_t;

typedef enum {
    GFX_BUFFER_DOUBLE       = 0,
    GFX_BUFFER_DIRECT_VRAM  = 1
} gfx_buffering_mode_t;

typedef enum {
    ZBUFFER_PRECISION_16BIT = 0,
    ZBUFFER_PRECISION_32BIT = 1
} gfx_zprecision_t;

typedef struct {
    gfx_backend_mode_t   mode;
    gfx_buffering_mode_t buffering;
    gfx_zprecision_t     zprecision;
    const char          *name;
    uint32_t             feature_flags;
    uint64_t             ops_counter;
    uint64_t             dma_transfers_bytes;

    // Sovereign L1 Tile Pipeline & Systemwide Config
    raster_engine_type_t raster_engine;
    int                  tile_size;
    int                  smp_cores;
    raster_shade_mode_t  shading_mode;
    int                  culling;
    int                  active_tab; // 0=Drivers, 1=Tile&SMP, 2=Shading&Sync, 3=Telemetry
} gfx_backend_state_t;

extern gfx_backend_state_t g_gfx_backend;

void gfx_backend_init(void);
void gfx_backend_set_mode(gfx_backend_mode_t mode);
gfx_backend_mode_t gfx_backend_get_mode(void);
const char* gfx_backend_get_name(void);
void gfx_backend_present(int x, int y, int w, int h, int is_full);

void gpu_set_buffering(gfx_buffering_mode_t mode);
gfx_buffering_mode_t gpu_get_buffering(void);

void gpu_set_zprecision(gfx_zprecision_t prec);
gfx_zprecision_t gpu_get_zprecision(void);

void gpu_set_raster_engine(raster_engine_type_t eng);
raster_engine_type_t gpu_get_raster_engine(void);

void gpu_set_tile_size(int size);
int  gpu_get_tile_size(void);

void gpu_set_smp_cores(int cores);
int  gpu_get_smp_cores(void);

void gpu_set_shading(raster_shade_mode_t shade);
raster_shade_mode_t gpu_get_shading(void);

void gpu_set_culling(int enable);
int  gpu_get_culling(void);

void gpu_config_set_tab(int tab);
int  gpu_config_get_tab(void);

// Dedicated GPU Configuration Window Interface
void gpu_config_open(void);
void gpu_config_close(void);
int  gpu_config_is_open(void);
void gpu_config_render(window_t *win, void *user_data);
int  gpu_config_click(window_t *win, int mouse_x, int mouse_y);
void gpu_config_print_doldoc(void);

// Hardware SIMD Accelerated Bulk Vertex Transformation (AArch64 Neon)
void gfx_backend_transform_vertices_neon(const vec3_t *in, vec4_t *out, int count, const mat4_t *mvp);

// Hardware Blit / DMA Clear
void gfx_backend_fast_clear(uint32_t *dst, size_t num_pixels, uint32_t color);

#endif // NEO_GFX_BACKEND_H
