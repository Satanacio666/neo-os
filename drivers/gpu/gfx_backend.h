#ifndef NEO_GFX_BACKEND_H
#define NEO_GFX_BACKEND_H

#include <uefi.h>
#include "../../kernel/math/math3d.h"

typedef enum {
    GFX_MODE_SOFTWARE_SIMD  = 0,
    GFX_MODE_HW_ACCELERATED = 1
} gfx_backend_mode_t;

typedef struct {
    gfx_backend_mode_t mode;
    const char        *name;
    uint32_t           feature_flags;
    uint64_t           ops_counter;
    uint64_t           dma_transfers_bytes;
} gfx_backend_state_t;

extern gfx_backend_state_t g_gfx_backend;

void gfx_backend_init(void);
void gfx_backend_set_mode(gfx_backend_mode_t mode);
gfx_backend_mode_t gfx_backend_get_mode(void);
const char* gfx_backend_get_name(void);

// Hardware SIMD Accelerated Bulk Vertex Transformation (AArch64 Neon)
void gfx_backend_transform_vertices_neon(const vec3_t *in, vec4_t *out, int count, const mat4_t *mvp);

// Hardware Blit / DMA Clear
void gfx_backend_fast_clear(uint32_t *dst, size_t num_pixels, uint32_t color);

#endif // NEO_GFX_BACKEND_H
