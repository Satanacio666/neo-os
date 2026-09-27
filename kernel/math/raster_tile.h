#ifndef NEO_RASTER_TILE_H
#define NEO_RASTER_TILE_H

#include <uefi.h>
#include "math3d.h"

// ─── Tile Dimensions & L1 Cache Constants ─────────────────────────────────────

#define TILE_SIZE_32              32
#define TILE_SIZE_64              64   // The Cortex-A72 32 KB L1 Data Cache Sweet Spot
#define TILE_SIZE_128             128

#define TILE_MAX_WIDTH            128
#define TILE_MAX_HEIGHT           128

#define TILE_MAX_COLS             48   // 1280 / 32 = 40 (ample room for 720p/1080p)
#define TILE_MAX_ROWS             32   // 720 / 32 = 23
#define TILE_MAX_TOTAL            (TILE_MAX_COLS * TILE_MAX_ROWS) // 1536 tiles max

#define TILE_MAX_SCENE_TRIS       4096
#define TILE_MAX_TRIS_PER_TILE    1024

// ─── Shading & Precision Enums ────────────────────────────────────────────────

typedef enum {
    RASTER_SHADE_GOURAUD   = 0,
    RASTER_SHADE_FLAT      = 1,
    RASTER_SHADE_WIREFRAME = 2
} raster_shade_mode_t;

typedef enum {
    RASTER_ENGINE_TILED_L1 = 0,
    RASTER_ENGINE_SCANLINE = 1
} raster_engine_type_t;

// ─── Geometric Primitives for Tile Binning ────────────────────────────────────

typedef struct {
    float    x, y, z;
    uint32_t color;
} raster_vertex_t;

typedef struct {
    raster_vertex_t v[3];
    uint32_t        flat_color;
    int             min_tx, max_tx;
    int             min_ty, max_ty;
} raster_triangle_t;

// ─── 24 KB Per-Core L1 Cache Tile Scratchpad ──────────────────────────────────
// Aligned to 64 bytes (ARMv8-A cache line boundary)
typedef struct {
    uint32_t color[TILE_MAX_WIDTH * TILE_MAX_HEIGHT]; // Up to 64 KB (16 KB for 64x64)
    uint16_t depth[TILE_MAX_WIDTH * TILE_MAX_HEIGHT]; // Up to 32 KB (8 KB for 64x64)
} __attribute__((aligned(64))) tile_scratchpad_t;

// ─── Coarse Tile Binning Container ───────────────────────────────────────────

typedef struct {
    uint16_t count;
    uint16_t indices[TILE_MAX_TRIS_PER_TILE];
} tile_bin_t;

typedef struct {
    int               tile_size;
    int               screen_w;
    int               screen_h;
    int               cols;
    int               rows;
    int               total_tiles;

    // Viewport Clipping Bounds
    int               vp_x, vp_y, vp_w, vp_h;

    // Global Scene Triangles
    raster_triangle_t triangles[TILE_MAX_SCENE_TRIS];
    int               num_triangles;

    // Binned tile grid
    tile_bin_t        bins[TILE_MAX_TOTAL];

    // Pipeline State
    raster_engine_type_t engine;
    raster_shade_mode_t  shade_mode;
    int                  culling;
    int                  depth_test;
    int                  active_cores;

    // Destination target buffer and pitch
    uint32_t         *target_buffer;
    uint32_t          target_pitch;
    uint32_t          clear_color;
} raster_scene_t;

extern raster_scene_t g_raster_scene;

// ─── Sovereign Tile Engine API ────────────────────────────────────────────────

void raster_tile_init(int screen_w, int screen_h, int tile_size);
void raster_tile_set_engine(raster_engine_type_t engine);
raster_engine_type_t raster_tile_get_engine(void);

void raster_tile_set_tile_size(int size);
int  raster_tile_get_tile_size(void);

void raster_tile_set_cores(int cores);
int  raster_tile_get_cores(void);

void raster_tile_set_shading(raster_shade_mode_t mode);
raster_shade_mode_t raster_tile_get_shading(void);

void raster_tile_set_culling(int enable);
int  raster_tile_get_culling(void);

void raster_tile_set_depth_test(int enable);
int  raster_tile_get_depth_test(void);

// Scene submission pipeline
void raster_tile_begin_scene(int vp_x, int vp_y, int vp_w, int vp_h,
                             uint32_t *target_buffer, uint32_t pitch,
                             uint32_t clear_color);

int  raster_tile_add_triangle(const raster_vertex_t *v0,
                              const raster_vertex_t *v1,
                              const raster_vertex_t *v2,
                              uint32_t flat_color);

void raster_tile_end_scene(void);

// Direct single-triangle NEON kernel for L1 scratchpad
void raster_tile_triangle_neon(tile_scratchpad_t *pad,
                               int tile_w, int tile_h,
                               int tile_x, int tile_y,
                               const raster_triangle_t *tri,
                               raster_shade_mode_t shade_mode,
                               int depth_test);

// Non-temporal streaming resolve from L1 tile to scanout aperture
void raster_tile_resolve_streaming(const tile_scratchpad_t *pad,
                                   int tile_w, int tile_h,
                                   int tile_x, int tile_y,
                                   uint32_t *target, uint32_t pitch);

#endif // NEO_RASTER_TILE_H
