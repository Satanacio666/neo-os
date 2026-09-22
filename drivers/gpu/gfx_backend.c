#include "gfx_backend.h"

gfx_backend_state_t g_gfx_backend = {
    .mode = GFX_MODE_SOFTWARE_SIMD,
    .name = "AArch64 Software SIMD",
    .feature_flags = 0x01,
    .ops_counter = 0,
    .dma_transfers_bytes = 0
};

void gfx_backend_init(void) {
    g_gfx_backend.mode = GFX_MODE_SOFTWARE_SIMD;
    g_gfx_backend.name = "AArch64 Software SIMD";
    g_gfx_backend.feature_flags = 0x01;
    g_gfx_backend.ops_counter = 0;
    g_gfx_backend.dma_transfers_bytes = 0;
}

void gfx_backend_set_mode(gfx_backend_mode_t mode) {
    g_gfx_backend.mode = mode;
    if (mode == GFX_MODE_HW_ACCELERATED) {
        g_gfx_backend.name = "VirtIO/Neon HW Accel";
        g_gfx_backend.feature_flags = 0x0F;
    } else {
        g_gfx_backend.name = "AArch64 Software SIMD";
        g_gfx_backend.feature_flags = 0x01;
    }
}

gfx_backend_mode_t gfx_backend_get_mode(void) {
    return g_gfx_backend.mode;
}

const char* gfx_backend_get_name(void) {
    return g_gfx_backend.name;
}

void gfx_backend_transform_vertices_neon(const vec3_t *in, vec4_t *out, int count, const mat4_t *mvp) {
    if (!in || !out || !mvp || count <= 0) return;

    for (int i = 0; i < count; i++) {
        float x = in[i].x, y = in[i].y, z = in[i].z;
        // 4-component vector transformation
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
    // 8-pixel unrolled block store for high memory bandwidth
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
